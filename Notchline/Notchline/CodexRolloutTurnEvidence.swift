import Foundation

/// What Codex writes in a thread's rollout about a Turn no hook reports: which
/// held Turn a thread is really on, and a Turn the user stopped.
///
/// This product's ``TurnEvidenceSource``, taken out of
/// `LiveCodexMonitorService` on 2026-09-12. The service still decides which
/// file each thread is written to -- the App Server hands the path over with
/// the thread's metadata -- and hands the paths of the Turns it holds to this
/// before each refresh settles them (``hold(rolloutPaths:)``); everything read
/// out of those files, and the watcher on them, is here.
actor CodexRolloutTurnEvidence: TurnEvidenceSource, ManagedMonitoringSource {
    /// Whether a Turn this app still holds open was stopped by the user, and
    /// which Turn that thread's rollout says it is on.
    ///
    /// The Codex half of [ADR 0011](../../docs/adr/0011-a-turn-may-end-on-evidence-that-is-not-a-hook-event.md):
    /// pressing stop sends no `Stop` and no `PostToolUse` for the call left
    /// open, so without this the row says *Running* until the user resumes that
    /// thread or waves the row away. The same rollout the reviewer is read
    /// from carries the answer — see ``CodexRolloutTurnAbortReader``.
    ///
    /// **One reader, two questions, one read.** They are the two halves of what
    /// a file can settle about a Turn this app is holding open — whose it is
    /// and whether it is over — and both are answered from the same cached tail
    /// of the same rollout, so the second costs nothing the first had not
    /// already spent. See ``CodexTurnOnRecordReading`` for the identity half.
    private let turnAbort: any CodexTurnAbortReading & CodexTurnOnRecordReading
    /// The rollouts of the Turns that are still going, and nothing else.
    ///
    /// The edge under the reading above, and the same shape as the Claude Code
    /// side's `transcriptWatcher`: an abort appends a record to a file inside a
    /// directory, which produces no directory-level event, so the file itself
    /// is watched. Without it the abort waits for whatever wakes this service
    /// next — at best the metadata interval, and on a thread that had gone
    /// quiet, the heartbeat.
    ///
    /// **Pointed at open Turns only.** A finished row's rollout is not watched,
    /// and neither is a thread this app has no live Turn for, so a quiet
    /// monitor still watches nothing at all. What it costs while a Turn runs is
    /// one wake-up per append, and a Codex turn appends 0.17–0.3 records a
    /// second over its life (measured over this machine's rollouts, with bursts
    /// to ~6/s that the debounce collapses).
    ///
    /// It reads nothing itself: an edge means *this file changed*, and the
    /// refresh it wakes is what asks the reader the question.
    ///
    /// Not private, so a test can state what is watched and for how long.
    nonisolated let rolloutWatcher: PathSetChangeWatcher
    /// The rollout each held Turn's thread is written to, as the refresh being
    /// settled found it.
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

    /// The paths the App Server has reported, for the refresh about to settle.
    /// A thread with none has no rollout this app may read, and no row either.
    func hold(rolloutPaths: [String: String]) {
        rolloutPathByThreadID = rolloutPaths
    }

    /// The one thing that ends a Codex Turn without a hook event, and the
    /// reason it has to exist: pressing stop in Desktop sends nothing at all --
    /// no `Stop`, and not even the `PostToolUse` for the call that was still
    /// open -- so the row said *Running* with its timer counting until the user
    /// resumed that exact thread or waved the row away. Codex does write the
    /// abort down, in the same rollout the reviewer is read from (ADR 0011,
    /// ``CodexRolloutTurnAbortReader``).
    ///
    /// Identity before termination: a prompt held back is settled first, so
    /// that a Turn resumed and then stopped again inside one refresh interval
    /// is the Turn the abort reading is asked about. The same rollout answers
    /// both, and the two questions are the two halves of ADR 0011 — which Turn
    /// this thread is on, and whether it is over.
    nonisolated var phases: [TurnEvidencePhase] { [.identity, .lifecycle] }

    func observations(in state: MonitoringStateSnapshot, phase: TurnEvidencePhase) async -> TurnEvidenceBatch {
        switch phase {
        case .identity: return await adoptTurnsOnRecord(in: state)
        case .lifecycle: return await endAbortedTurns(in: state)
        case .afterLifecycle: return TurnEvidenceBatch()
        }
    }

    /// Nothing is being monitored, so no rollout is worth an edge.
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
    /// **The Codex side of "a Turn's identity may be settled by evidence that
    /// is not a hook event"**, and the companion to the abort reading below.
    /// A prompt naming a Turn the reducer was not holding is held back rather
    /// than adopted, because a nested agent runs under the parent thread's
    /// `session_id` with a turn id of its own and no `agent_id` to be told
    /// apart by (``HookTurnState/heldTurnStart``). Its own events prove nothing
    /// — they carry that same id — so what settles it is the thread's rollout,
    /// where Codex writes each Turn's `turn_context` ~65 ms *before* that
    /// Turn's first hook. A reviewer's turns are written to a rollout of its
    /// own, so this thread's record never names one.
    ///
    /// Asked only of threads with a prompt actually held, which is a thread
    /// with something nested running on it or a Turn the user has just resumed
    /// — and asked of the same cached tail the abort reading below already
    /// takes of the same file on the same refresh, so it adds no read. Nothing
    /// is asked about a thread whose rollout the App Server has not handed
    /// over, on the same terms as that reading: a row this app cannot draw is
    /// not one worth reading a file for.
    ///
    /// **Deliberately not held to Turns that are still going**, which is the
    /// one place it differs from the abort reading. The resumed-Turn case ends
    /// with the interrupted Turn *finished* — by that reading, a refresh
    /// earlier — and the prompt held during it still waiting to be adopted, so
    /// a `keepsTiming` filter here would close the door on the very case this
    /// exists to open. A hold left on a finished Turn costs one `lstat`: its
    /// rollout has stopped changing, so the reader answers from its cache.
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

    /// Ends the Turns Codex recorded as aborted, and only those.
    ///
    /// **The Codex side of "a Turn may end on evidence that is not a Hook
    /// event"** (ADR 0011). A user pressing stop in Codex Desktop produces no
    /// hook of any kind, so the reducer holds that Turn open for ever: no event
    /// will name its `turn_id` again, membership reconciliation keeps the row
    /// because the thread is still listed, and this product has no
    /// activity-status read like `claude agents --json` to fall back on. What
    /// Codex leaves instead is a `turn_aborted` record in the thread's own
    /// rollout, and it names the Turn.
    ///
    /// The reducer stays the only thing that computes Turn state: this hands it
    /// a fact about a Turn Codex wrote down and lets
    /// ``HookEventRepository/endInterruptedTurns(_:)`` apply the rules any
    /// event gets. Held to Turns that are still going and to threads the App
    /// Server has handed over a path for -- a row this app cannot draw is not
    /// one worth reading a file for.
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
                    // The stop killed the `wait_agent` this Turn was going to
                    // collect its subagents with, so their results can never
                    // reach it. See ``TurnInterruption/orphansSubagents`` for
                    // the measurement, and why a row that went on counting
                    // them said the thread was working for as long as an
                    // orphan ran -- on a Turn the user ended by hand.
                    orphansSubagents: true
                )
            )
        }
        return TurnEvidenceBatch(interruptions: interruptions)
    }

    /// Watches the rollouts of the Turns that are still going, and no others.
    ///
    /// The same set the reading above asks about, so the edge and the answer
    /// cannot disagree about which files are worth anything. It doubles as the
    /// reader's retention: a rollout nothing is waiting on is one nothing needs
    /// a cached answer about either.
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
