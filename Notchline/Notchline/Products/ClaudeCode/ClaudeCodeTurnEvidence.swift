import Foundation

/// What Claude Code writes down about a Turn that no hook reports: an interrupt, and a dialog
/// answered in Desktop's window. This product's ``TurnEvidenceSource``
/// ([ADR 0011](../../docs/adr/0011-a-turn-may-end-on-evidence-that-is-not-a-hook-event.md)),
/// reading the refresh's session list and owning the two file watchers.
actor ClaudeCodeTurnEvidence: TurnEvidenceSource, ManagedMonitoringSource {
    private var watchGeneration = 0
    private let sessions: ClaudeCodeSessionSource
    private let transcripts: ClaudeCodeTranscriptReader
    /// When Claude Desktop last recorded a human answering one of its dialogs: the only answer signal
    /// for a desktop-hosted session (see ``ClaudeDesktopPermissionLogReader``).
    private let permissions: any DesktopPermissionResponseReporting
    /// Claude Desktop's records, joining its session id to the CLI's.
    private let readState: any ClaudeCodeReadStateProviding
    /// The file behind `permissions`, for the watcher; a test must point both at one log.
    nonisolated private let permissionLogURL: URL
    /// Transcripts of running turns in sessions that report no status (CC-022); files, since an
    /// append produces no directory event. Does not invalidate the session list: the answer is a tail
    /// read, not a `claude` launch. Not private, so tests can state what is watched.
    nonisolated let transcriptWatcher: PathSetChangeWatcher
    /// Claude Desktop's own log, watched only while a dialog it raised is open: the answered line is
    /// the wait's only end, otherwise a minute of heartbeat. Does not invalidate the session list.
    nonisolated let permissionLogWatcher: PathSetChangeWatcher

    init(
        sessions: ClaudeCodeSessionSource,
        transcripts: ClaudeCodeTranscriptReader,
        permissions: any DesktopPermissionResponseReporting,
        permissionLogURL: URL,
        readState: any ClaudeCodeReadStateProviding,
        timing: MonitorTiming
    ) {
        self.sessions = sessions
        self.transcripts = transcripts
        self.permissions = permissions
        self.permissionLogURL = permissionLogURL
        self.readState = readState
        transcriptWatcher = PathSetChangeWatcher(
            debounceInterval: timing.unreadStateDebounceInterval
        )
        permissionLogWatcher = PathSetChangeWatcher(
            debounceInterval: timing.unreadStateDebounceInterval
        )
    }

    nonisolated var changeEvents: [AsyncStream<Void>] {
        [
            // A transcript gaining a record during a turn: a signal, answered by the refresh.
            transcriptWatcher.events(),
            // Claude Desktop logging a dialog answered; watched only while one is awaited.
            permissionLogWatcher.events(),
        ]
    }

    nonisolated var phases: [TurnEvidencePhase] { [.lifecycle, .afterLifecycle] }

    func observations(in state: MonitoringStateSnapshot, phase: TurnEvidencePhase) async -> TurnEvidenceBatch {
        if phase == .afterLifecycle { return await desktopAnswers(in: state) }
        let reading = await sessions.currentReading()
        let live = reading.sessions
        let liveByID = reading.sessionsByID

        // Applied after the drain, so a later event still wins by instant. The only route out of a
        // user-interrupted turn; otherwise the row stays *Running* or *Approval needed* (CC-019).
        let stopped = Dictionary(
            live.compactMap { session -> (String, Date)? in
                guard let activity = session.activity, !activity.isWorking else {
                    return nil
                }
                return (session.sessionID, activity.observedAt)
            },
            // Duplicate entries for one session are someone else's bug, not a reason to trap.
            uniquingKeysWith: { first, _ in first }
        )
        // `busy` is the only evidence an approval was answered: no hook fires on approval, and
        // `PostToolUse` lands when the tool finishes. See
        // ``HookEventRepository/endAnsweredApprovalWaits(_:)`` for the measurement and why `idle` does not.
        let working = Dictionary(
            live.compactMap { session -> (String, Date)? in
                guard let activity = session.activity, activity.state == .busy else {
                    return nil
                }
                return (session.sessionID, activity.observedAt)
            },
            uniquingKeysWith: { first, _ in first }
        )
        // Desktop-hosted sessions report no status, so `stopped` is empty for them (CC-022); read their
        // transcript's interrupt record, only for a Turn still open.
        var interruptions: [TurnInterruption] = []
        for turn in state.turns where turn.sessionStatus.keepsTiming {
            guard let session = liveByID[turn.threadID],
                  session.activity == nil else {
                continue
            }
            guard let endedAt = await transcripts.interruption(
                forSession: session.sessionID,
                workingDirectory: session.workingDirectory,
                turnID: turn.turnID,
                after: turn.lastEventAt
            ) else {
                continue
            }
            interruptions.append(
                TurnInterruption(
                    threadID: turn.threadID,
                    turnID: turn.turnID,
                    endedAt: endedAt
                )
            )
        }

        return TurnEvidenceBatch(stopped: stopped, interruptions: interruptions, answeredApprovals: working)
    }

    private func desktopAnswers(in hookState: MonitoringStateSnapshot) async -> TurnEvidenceBatch {
        // Desktop-hosted sessions publish no status; Desktop logs both ends of each dialog. Read only
        // while an approval is open, keeping Desktop's tree off the ordinary refresh (CR-Fable-003).
        let waitsOnAnApproval = hookState.turns.contains { turn in
            turn.pendingApproval != nil || turn.subagentsAwaitingApproval
        }
        if waitsOnAnApproval {
            let answered = await permissions.answeredAt()
            if !answered.isEmpty {
                // The log names Desktop's session id; its records join that to the CLI's. No id is guessed.
                let records = await readState.snapshot()
                let answeredByThread = Dictionary(
                    answered.compactMap { desktopSessionID, at -> (String, Date)? in
                        guard let threadID = records.cliSessionID(
                            forDesktopSessionID: desktopSessionID
                        ) else {
                            return nil
                        }
                        return (threadID, at)
                    },
                    uniquingKeysWith: { first, second in max(first, second) }
                )
                if !answeredByThread.isEmpty {
                    return TurnEvidenceBatch(answeredApprovals: answeredByThread)
                }
            }
        }
        return TurnEvidenceBatch()
    }

    func watch(openTurnsIn state: HookStateSnapshot) async {
        let generation = watchGeneration
        let liveByID = await sessions.currentReading().sessionsByID
        // Watch the log only while a Desktop answer is awaited, recomputed from post-refresh state.
        // Terminal-hosted sessions are excluded: their `waiting` to `busy` flip arrives on the record edge.
        guard generation == watchGeneration else { return }
        let awaitsADesktopAnswer = state.turns.contains { turn in
            guard turn.pendingApproval != nil || turn.subagentsAwaitingApproval,
                  let session = liveByID[turn.threadID] else {
                return false
            }
            return session.activity == nil
        }
        permissionLogWatcher.watch(paths: awaitsADesktopAnswer ? [permissionLogURL] : [])

        // Watch transcripts of running Turns in silent sessions, from every listed Turn (a row withheld
        // for presence is still held). Sessions that report status are not watched here.
        var watchedTranscripts: Set<URL> = []
        for turn in state.turns where turn.status.keepsTiming {
            guard let session = liveByID[turn.threadID],
                  session.activity == nil,
                  let url = await transcripts.transcriptURL(
                    forSession: session.sessionID,
                    workingDirectory: session.workingDirectory
                  ) else {
                continue
            }
            watchedTranscripts.insert(url)
        }
        guard generation == watchGeneration else { return }
        transcriptWatcher.watch(paths: watchedTranscripts)
    }

    /// Nothing is being monitored, so neither file is worth an edge.
    nonisolated var sourceChanges: [AsyncStream<Void>] { changeEvents }
    func stopMonitoring() { stopWatching() }

    func stopWatching() {
        watchGeneration += 1
        transcriptWatcher.watch(paths: [])
        permissionLogWatcher.watch(paths: [])
    }
}
