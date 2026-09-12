import Foundation

/// What Claude Code writes down about a Turn that no hook reports: the user
/// interrupting it, and a dialog being answered in the product's own window.
///
/// This product's ``TurnEvidenceSource``, taken out of
/// `ClaudeCodeMonitorService` on 2026-09-12. Every sentence of it is a fact the
/// reducer is handed and then applies with the rules any event gets
/// ([ADR 0011](../../docs/adr/0011-a-turn-may-end-on-evidence-that-is-not-a-hook-event.md)):
/// a session the list says has stopped working, an interrupt record in a
/// transcript, a session the list says is busy again, and Claude Desktop's own
/// log of a permission dialog closing. It reads all of them off the session
/// list the refresh has just taken (``ClaudeCodeSessionSource``), and owns the
/// two watchers that bring a refresh round when one of those files changes.
actor ClaudeCodeTurnEvidence: TurnEvidenceSource {
    private let sessions: ClaudeCodeSessionSource
    private let transcripts: ClaudeCodeTranscriptReader
    /// When Claude Desktop last recorded a human answering one of its dialogs.
    ///
    /// The desktop half of "the approval has been answered", and the only half
    /// that reaches a desktop-hosted session -- see
    /// ``ClaudeDesktopPermissionLogReader`` for why no hook and no session
    /// status can.
    private let permissions: any DesktopPermissionResponseReporting
    /// Claude Desktop's records, for the join from its session id to the
    /// CLI's.
    private let readState: any ClaudeCodeReadStateProviding
    /// The file behind that, for the watcher rather than the reader.
    ///
    /// Held separately because the reader answers questions and the watcher
    /// needs a path; a test pointing one at its own log has to be able to point
    /// the other at the same one.
    nonisolated private let permissionLogURL: URL
    /// The transcripts of the turns that are still going in a session which
    /// reports no status of its own.
    ///
    /// The same job as ``ClaudeCodeSessionSource/recordWatcher`` for the sessions that one cannot
    /// answer for: a desktop-hosted session publishes no working status, so the
    /// only report its interrupt makes is the record Claude Code appends to
    /// this file (CC-022). A file rather than the directory it sits in, for the
    /// reason given on ``ClaudeCodeSessionRecordWatcher`` -- an append inside a
    /// directory produces no directory event.
    ///
    /// **It deliberately does not invalidate the session list.** That is the
    /// difference between this edge and the record one: an edge here means a
    /// file this app reads itself has changed, and the answer costs a 64 KiB
    /// tail read rather than a `claude` launch. Invalidating as well would buy
    /// a subprocess for an answer no subprocess holds.
    ///
    /// Not private, for the reason ``ClaudeCodeSessionSource/recordWatcher`` is not: what is watched,
    /// and for how long, is an invariant a test has to be able to state.
    nonisolated let transcriptWatcher: PathSetChangeWatcher
    /// Claude Desktop's own log, while a dialog it raised is still open.
    ///
    /// **The third watcher pointed at only what is worth watching, and the one
    /// with the strongest reason to be.** ``ClaudeDesktopFocusLogReader``
    /// deliberately has no watcher at all, because a wake-up per line of a log
    /// that records oauth lookups and git timings buys nothing -- and that
    /// argument holds for exactly as long as nothing is waiting on the file.
    /// While a desktop-hosted session is sitting on a permission dialog,
    /// something is: the line saying the human answered is the only report that
    /// dialog is over (see ``ClaudeDesktopPermissionLogReader``), and without
    /// this edge it would wait out the heartbeat -- a whole minute of a row
    /// asking for an answer already given.
    ///
    /// Pointed at the log only while such a wait is open, and at nothing the
    /// rest of the time, so the noise the focus reader declined to pay for is
    /// still not paid for.
    ///
    /// It does not invalidate the session list, for the reason
    /// ``transcriptWatcher`` does not: the answer is in a file this app reads
    /// itself, and no `claude` launch holds it.
    ///
    /// Not private, for the reason the other two are not.
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

    /// The two edges, for whoever merges a refresh's wake-ups.
    nonisolated var changeEvents: [AsyncStream<Void>] {
        [
            // A transcript gaining a record while its turn is still going.
            // Only one kind of record can end that turn, but this is a signal
            // and not a reading: what arrived is answered by the refresh, in
            // the reader that already knows how to answer it. Nothing here
            // invalidates the session list -- see ``transcriptWatcher``.
            transcriptWatcher.events(),
            // Claude Desktop logging that a dialog it raised has been
            // answered. A signal and not a reading, exactly like the one above
            // it, and pointed at the log only while such an answer is what the
            // app is waiting for -- see ``permissionLogWatcher``.
            permissionLogWatcher.events(),
        ]
    }

    func settle(_ state: HookStateSnapshot, in reducer: HookEventRepository) async -> HookStateSnapshot {
        let reading = await sessions.currentReading()
        let live = reading.sessions
        let liveByID = reading.sessionsByID

        // The events are drained first and this is applied to what they left,
        // so an event that arrived after the list was read still wins -- the
        // reducer compares the two instants and keeps the later one.
        //
        // This is the only route out of a turn a user interrupted: no hook
        // fires for that, so without it the row keeps saying *Running* -- or
        // *Approval needed*, which asks the user to answer something nobody is
        // waiting for any more (CC-019).
        let stopped = Dictionary(
            live.compactMap { session -> (String, Date)? in
                guard let activity = session.activity, !activity.isWorking else {
                    return nil
                }
                return (session.sessionID, activity.observedAt)
            },
            // The list is keyed the same way the reading's own index is, and for the
            // same reason: two entries naming one session is somebody else's
            // bug, not a reason to trap.
            uniquingKeysWith: { first, _ in first }
        )
        // The same reading's other word, and the only evidence this product
        // gives that an approval was *answered*. No hook fires when a human
        // approves: `PermissionRequest` opens the wait and the next event is
        // the call's own `PostToolUse`, which lands when the tool finishes
        // rather than when the dialog closes. `busy` means no dialog is in
        // front of the user, so it ends the wait the moment the record's flip
        // brings this refresh round -- see
        // ``HookEventRepository/endAnsweredApprovalWaits(_:)`` for
        // the measurement and for why `idle` is not allowed to say the same.
        let working = Dictionary(
            live.compactMap { session -> (String, Date)? in
                guard let activity = session.activity, activity.state == .busy else {
                    return nil
                }
                return (session.sessionID, activity.observedAt)
            },
            uniquingKeysWith: { first, _ in first }
        )
        // The other half of the same question, for the sessions the reading
        // above cannot answer for at all. A desktop-hosted session never
        // reports a working status -- the terminal interface publishes that
        // field and the desktop app runs the CLI without one -- so `stopped`
        // above is empty for it however long ago it was interrupted (CC-022).
        // What it does leave is a record in its own transcript, and that record
        // names the turn it ended.
        //
        // Asked only of the sessions that say nothing, and only about a turn
        // this app is still holding open: a session that answers for itself is
        // answered by its own answer, and a file read that nothing is waiting
        // on is a file read not worth doing.
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

        var hookState = state
        if !stopped.isEmpty {
            hookState = await reducer.endTurnsForStoppedSessions(stopped)
        }
        if !interruptions.isEmpty {
            hookState = await reducer.endInterruptedTurns(interruptions)
        }
        // After both, and disjoint from `stopped` by construction: a session is
        // either working or it is not. A turn those two just ended keeps no
        // approval for this to clear, and a turn still running is exactly the
        // one that has an answered dialog to forget.
        if !working.isEmpty {
            hookState = await reducer.endAnsweredApprovalWaits(working)
        }
        // And the same sentence for the sessions that cannot say it themselves.
        // A desktop-hosted session publishes no status ever, so `working` above
        // is empty for it however long ago the user answered -- the same shape
        // as CC-022 / #41 one paragraph up, and answered the same way: with
        // something the desktop app writes down. Claude Desktop logs both ends
        // of every dialog it raises, joined by a request id.
        //
        // **Asked only while an approval is actually open.** Everything here is
        // free until a dialog exists to close: no log read, no account-tree
        // read, and no watcher. That gate is what keeps a second reading of
        // Claude Desktop's tree off the ordinary refresh (CR-Fable-003), and it
        // closes again the moment the wait does.
        let waitsOnAnApproval = hookState.turns.contains { turn in
            turn.pendingApproval != nil || turn.subagentsAwaitingApproval
        }
        if waitsOnAnApproval {
            let answered = await permissions.answeredAt()
            if !answered.isEmpty {
                // The log names Desktop's own id for the session; the reducer
                // knows the CLI's. Desktop's records carry both, which is the
                // join this app already keeps for the read state -- so no id is
                // guessed and a session whose record cannot say is left alone.
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
                    hookState = await reducer.endAnsweredApprovalWaits(answeredByThread)
                }
            }
        }
        return hookState
    }

    func watch(openTurnsIn state: HookStateSnapshot) async {
        let liveByID = await sessions.currentReading().sessionsByID
        // Claude Desktop's log, and only while its answer is what this app is
        // waiting for. Recomputed from the state the refresh left, so a wait
        // it just closed unwatches it in the same refresh.
        //
        // Held to sessions that report no status of their own, which is the
        // only place this evidence is needed: a terminal-hosted session's
        // `waiting` to `busy` flip already arrives on the record edge, and it
        // is the reading this app trusts first.
        let awaitsADesktopAnswer = state.turns.contains { turn in
            guard turn.pendingApproval != nil || turn.subagentsAwaitingApproval,
                  let session = liveByID[turn.threadID] else {
                return false
            }
            return session.activity == nil
        }
        permissionLogWatcher.watch(paths: awaitsADesktopAnswer ? [permissionLogURL] : [])

        // And the transcripts of exactly the turns the reading above cannot
        // see stop -- the ones whose session reports nothing. Watched from
        // every Turn the list names rather than from the rows shown, for the
        // same reason: a row withheld for presence is still a turn this app is
        // holding.
        //
        // A session that answers for itself is not watched here at all, even
        // while its turn runs: its record already reports the flip, and the
        // reading behind it is the one this app trusts first.
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
        transcriptWatcher.watch(paths: watchedTranscripts)
    }

    /// Nothing is being monitored, so neither file is worth an edge.
    func stopWatching() {
        transcriptWatcher.watch(paths: [])
        permissionLogWatcher.watch(paths: [])
    }
}
