import Foundation

/// What Codex writes in a thread's rollout about a Turn no hook reports: which held Turn a
/// thread is really on, and a Turn the user stopped. The service supplies the rollout paths
/// before each refresh settles (``hold(rolloutPaths:)``).
actor CodexRolloutTurnEvidence: TurnEvidenceSource, ManagedMonitoringSource {
    /// Whether a held-open Turn was stopped by the user, and which Turn its rollout names
    /// (ADR 0011): stop sends no `Stop` and no `PostToolUse`. Both come from one cached tail read;
    /// see ``CodexRolloutTurnAbortReader`` and ``CodexTurnOnRecordReading``.
    private let turnAbort: any CodexTurnAbortReading & CodexTurnOnRecordReading
    /// The rollouts of the Turns still going, and nothing else. An append produces no
    /// directory-level event, so the files themselves are watched; otherwise an abort waits for
    /// the metadata interval or the heartbeat. A Codex turn appends 0.17–0.3 records/s (bursts to
    /// ~6/s, debounced). Reads nothing itself. Not private, for tests.
    nonisolated let rolloutWatcher: PathSetChangeWatcher
    private var rolloutPathByThreadID: [String: String] = [:]

    init(
        turnAbort: any CodexTurnAbortReading & CodexTurnOnRecordReading,
        timing: MonitorTiming
    ) {
        self.turnAbort = turnAbort
        rolloutWatcher = PathSetChangeWatcher(
            debounceInterval: timing.unreadStateDebounceInterval
        )
    }

    /// The paths the App Server reported, for the refresh about to settle. A thread with none has
    /// no rollout this app may read, and no row either.
    func hold(rolloutPaths: [String: String]) {
        rolloutPathByThreadID = rolloutPaths
    }

    /// Identity before termination: a held prompt is settled first, so a Turn resumed and stopped
    /// again inside one refresh interval is the one the abort reading is asked about (ADR 0011).
    nonisolated var phases: [TurnEvidencePhase] { [.identity, .lifecycle] }

    func observations(in state: MonitoringStateSnapshot, phase: TurnEvidencePhase) async -> TurnEvidenceBatch {
        switch phase {
        case .identity: return await adoptTurnsOnRecord(in: state)
        case .lifecycle: return await endAbortedTurns(in: state)
        case .afterLifecycle: return TurnEvidenceBatch()
        }
    }

    nonisolated var sourceChanges: [AsyncStream<Void>] { [rolloutWatcher.events()] }
    func stopMonitoring() async {
        stopWatching()
        rolloutPathByThreadID.removeAll()
        await turnAbort.retain(rolloutPaths: [])
    }

    func stopWatching() {
        rolloutWatcher.watch(paths: [])
    }

    /// Gives a thread the held Turn its own rollout names, and only that one.
    ///
    /// A nested agent runs under the parent's `session_id` with its own turn id and no `agent_id`
    /// (``HookTurnState/heldTurnStart``), so its events prove nothing; the thread's rollout does,
    /// where `turn_context` lands ~65 ms before the Turn's first hook. A reviewer's turns go to a
    /// rollout of their own. Asked only for threads with a held prompt, from the abort reading's
    /// cached tail. Deliberately not limited to Turns still going: a resumed Turn's held prompt
    /// outlives the interrupted Turn, and a hold on a finished rollout costs one `lstat`.
    private func adoptTurnsOnRecord(
        in hookState: HookStateSnapshot
    ) async -> TurnEvidenceBatch {
        var records: [TurnOnRecord] = []
        for turn in hookState.turns {
            guard let held = turn.heldTurnStart,
                  let rolloutPath = rolloutPath(ofThread: turn.threadID) else {
                continue
            }
            guard await turnAbort.turnOnRecord(inRolloutAt: rolloutPath)
                == held.turnID else {
                continue
            }
            records.append(
                TurnOnRecord(threadID: turn.threadID, turnID: held.turnID)
            )
        }
        return TurnEvidenceBatch(onRecord: records)
    }

    /// Ends the Turns Codex recorded as aborted, and only those (ADR 0011). Stop in Codex Desktop
    /// fires no hook and membership reconciliation keeps a listed thread's row, so `turn_aborted`
    /// is the only evidence; ``HookEventRepository/endInterruptedTurns(_:)`` applies it. Limited
    /// to Turns still going on threads the App Server handed a path for.
    private func endAbortedTurns(
        in hookState: HookStateSnapshot
    ) async -> TurnEvidenceBatch {
        var interruptions: [TurnInterruption] = []
        for turn in hookState.turns where turn.sessionStatus.keepsTiming {
            guard let rolloutPath = rolloutPath(ofThread: turn.threadID) else {
                continue
            }
            guard let endedAt = await turnAbort.abortedAt(
                turnID: turn.turnID,
                inRolloutAt: rolloutPath,
                after: turn.lastEventAt
            ) else {
                continue
            }
            interruptions.append(
                TurnInterruption(
                    threadID: turn.threadID,
                    turnID: turn.turnID,
                    endedAt: endedAt,
                    // The stop killed the `wait_agent` that would have collected its subagents
                    // (``TurnInterruption/orphansSubagents``).
                    orphansSubagents: true
                )
            )
        }
        return TurnEvidenceBatch(interruptions: interruptions)
    }

    /// Watches the rollouts of the Turns still going: the set the reading asks about, which also
    /// bounds the reader's cache.
    func watch(openTurnsIn hookState: HookStateSnapshot) async {
        var paths: Set<String> = []
        for turn in hookState.turns where turn.sessionStatus.keepsTiming {
            guard let rolloutPath = rolloutPath(ofThread: turn.threadID) else {
                continue
            }
            paths.insert(rolloutPath)
        }
        rolloutWatcher.watch(paths: Set(paths.map { URL(fileURLWithPath: $0) }))
        await turnAbort.retain(rolloutPaths: paths)
    }

    private func rolloutPath(ofThread threadID: String) -> String? {
        rolloutPathByThreadID[threadID]
    }
}
