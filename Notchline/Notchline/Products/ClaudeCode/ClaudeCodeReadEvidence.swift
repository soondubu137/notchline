import Foundation

/// Claude Code's read evidence (``ReadEvidenceSource``); which rows are judged is the shared
/// ``TerminalUnreadRowFilter``.
///
/// Five routes to "read". The provider's own: Desktop displayed the session after the Turn
/// ended, or it was archived. Decided here:
/// - came back to it: Desktop returned to the front after the Turn ended, showing it;
/// - in front of them: Desktop holds the front on a waking, unlocked screen showing it. The
///   one state-based route, so it accepts retiring a row for a user who walked away;
/// - moved on from it: seen on screen with its Turn over, then another session displayed;
/// - at its terminal: its controlling terminal got input after the Turn ended.
///
/// The terminal route is asked of every session, not only as a fallback: remote control shows
/// one session in both places, and reading in the terminal stamps nothing in Desktop. It never
/// asks which tab is visible (``ControllingTerminalGestureReporting``).
///
/// A session with neither a controlling terminal nor a Desktop record stays out of the gate
/// and books no re-check. Desktop's records never note a session leaving the screen, so
/// ``isOnScreen(_:)`` reads Desktop's log as a veto; an unparseable log changes no verdict.
actor ClaudeCodeReadEvidence: ReadEvidenceSource, ManagedMonitoringSource {
    nonisolated private let readState: any ClaudeCodeReadStateProviding
    /// When Claude Desktop last came to the front. Desktop writes nothing when its window regains
    /// focus over a session already shown (measured 2026-08-19), so the file cannot see it.
    nonisolated private let activations: any DesktopActivationReporting
    /// Whether Claude Desktop is in front of the user now: covers a session already on screen
    /// when its Turn ended. The one state-based route (see ``DesktopReadingWatcher``).
    private let reading: any DesktopReadingReporting
    /// What Claude Desktop says it has on screen, including nothing: a veto over the Desktop
    /// routes that can only keep a row (``DesktopDisplayedSessionReporting``).
    private let displayed: any DesktopDisplayedSessionReporting
    /// When the user was last at a session's own terminal; never which tab is visible
    /// (``ControllingTerminalGestureReporting``).
    private let terminal: TerminalReadEvidence
    /// Sessions seen on Claude Desktop's screen with their Turn already finished.
    ///
    /// Observed live, not reconstructed from focus stamps: an older stamp says a session was
    /// displayed once, not then (`AGENTS.md` §6.2). Half a rule: retiring also needs a move only a
    /// person makes.
    private var sessionsSeenOnScreenSinceTheirTurnEnded: Set<String> = []
    private var observationGeneration = 0

    /// Whether there is a screen the user could read a finished answer on.
    nonisolated var screen: any ScreenAvailabilityReporting { terminal.screen }

    init(
        /// Each session's process, from the list the judged refresh read; never looked up again, since
        /// a second reading could launch a `claude` mid-verdict.
        sessions: any SessionProcessLocating,
        readState: any ClaudeCodeReadStateProviding,
        activations: any DesktopActivationReporting,
        reading: any DesktopReadingReporting,
        displayed: any DesktopDisplayedSessionReporting,
        terminalGestures: any ControllingTerminalGestureReporting,
        screen: any ScreenAvailabilityReporting
    ) {
        self.readState = readState
        self.activations = activations
        self.reading = reading
        self.displayed = displayed
        self.terminal = TerminalReadEvidence(
            sessions: sessions,
            gestures: terminalGestures,
            screen: screen
        )
    }

    /// With no finished row listed the on-screen membership goes, so a session on screen when the
    /// integration was switched off cannot come back claiming to have been seen.
    nonisolated var sourceChanges: [AsyncStream<Void>] {
        [readState.changeEvents(), activations.changeEvents()]
    }
    func startMonitoring() async {
        await (readState as? any ManagedMonitoringSource)?.startMonitoring()
    }
    func stopMonitoring() async {
        forget()
        await (readState as? any ManagedMonitoringSource)?.stopMonitoring()
    }

    func forget() {
        observationGeneration += 1
        sessionsSeenOnScreenSinceTheirTurnEnded.removeAll()
    }

    func verdicts(for candidates: [ReadGateCandidate], now: Date) async -> ReadEvidenceJudgement {
        let generation = observationGeneration
        let readState = await self.readState.snapshot()
        let activatedAt = await activations.lastActivation()
        let desktopIsInFrontOfTheUser = await reading.isInFrontOfTheUser()
        let displayedSession = await displayed.displayedSession()
        var unreadThreadIDs: Set<String> = []
        /// Each judged row and whether the terminal reading decides it; absent rows had nothing to
        /// speak for them.
        var restsOnTerminalByRowID: [String: Bool] = [:]

        /// Whether Claude Desktop has this session on screen right now.
        ///
        /// The records name the session last put on screen; Desktop's log (`sessionId=null` included)
        /// is a veto that can withhold, never nominate. ``DesktopDisplayedSession/unknown`` behaves as
        /// if there were no log.
        func isOnScreen(_ sessionID: String) -> Bool {
            guard sessionID == readState.mostRecentlyDisplayedSessionID else {
                return false
            }
            switch displayedSession {
            case .unknown:
                return true
            case .nothing:
                return false
            case let .session(desktopSessionID):
                return readState.cliSessionID(forDesktopSessionID: desktopSessionID)
                    == sessionID
            }
        }

        /// Whether Claude Desktop has put a different session on screen (a composer is
        /// ``DesktopDisplayedSession/nothing``, not a session).
        ///
        /// The log answers alone; the records stand in only when it cannot. Desktop logs the
        /// navigation and stamps `lastFocusedAt` at once but writes the record ~1.03 s later
        /// (2026-08-20); waiting for the records brought the row back unread for that second (CC-024).
        func hasReplacedItOnScreen(_ sessionID: String) -> Bool {
            switch displayedSession {
            case .unknown:
                guard let stamped = readState.mostRecentlyDisplayedSessionID else {
                    return false
                }
                return stamped != sessionID
            case .nothing:
                return false
            case let .session(desktopSessionID):
                if let onScreen = readState
                    .cliSessionID(forDesktopSessionID: desktopSessionID) {
                    return onScreen != sessionID
                }
                // The name on screen joins to nothing: Desktop's record is not written yet, or it lost its
                // id. If this session's own record names a different Desktop id, it is not on screen; if it
                // names none, the records answer alone.
                guard let own = readState.desktopSessionID(forSession: sessionID) else {
                    guard let stamped = readState.mostRecentlyDisplayedSessionID else {
                        return false
                    }
                    return stamped != sessionID
                }
                return own != desktopSessionID
            }
        }

        /// Whether coming back to Claude Desktop showed this session: an activation after the Turn
        /// ended, not merely frontmost, so walking away with the window in front retires nothing.
        func comingBackShowedIt(_ sessionID: String, since boundary: Date) -> Bool {
            guard isOnScreen(sessionID), let activatedAt else { return false }
            return activatedAt >= boundary
        }

        /// Whether the finished answer is in front of the user right now: on screen when the Turn
        /// ended, and nobody left.
        ///
        /// A state, not a gesture, so it can retire a row nobody read; accepted, since nothing
        /// separates a watcher from someone who walked away. See ``DesktopReadingWatcher``.
        func isInFrontOfThem(_ sessionID: String) -> Bool {
            isOnScreen(sessionID) && desktopIsInFrontOfTheUser
        }

        /// Whether the user moved on inside Claude Desktop: seen on screen with its Turn over, then
        /// displaced by another session (``hasReplacedItOnScreen(_:)``). No timestamps needed; waking
        /// from sleep re-stamps the same session, never another.
        func movedOnFrom(_ sessionID: String) -> Bool {
            sessionsSeenOnScreenSinceTheirTurnEnded.contains(sessionID)
                && hasReplacedItOnScreen(sessionID)
        }

        /// One terminal reading per row per refresh, so the verdict, the gate entry, the gesture and
        /// who held the front describe one instant (``TerminalReadEvidence``).
        var terminalVerdictByThreadID: [String: TerminalReadEvidence.Verdict] = [:]
        for candidate in candidates {
            terminalVerdictByThreadID[candidate.row.threadID] = await terminal.verdict(
                forThreadID: candidate.row.threadID,
                turnEndedAt: candidate.turnEndedAt
            )
        }

        /// Whether this session's terminal can ever say the user was at it after it finished.
        ///
        /// A peer of the Desktop routes, not a fallback: remote control shows one session in both
        /// places. Taking either is safe because Desktop-hosted sessions have no controlling terminal
        /// (`--output-format stream-json` over pipes, #41). It needs the gesture and the terminal's
        /// app holding the front: Claude Code's any-event mouse tracking turns a pointer crossing an
        /// unfocused terminal into pty bytes (``ControllingTerminalGestureReporting``).
        func terminalCanSpeak(_ threadID: String) -> Bool {
            terminalVerdictByThreadID[threadID].map { $0 != .cannotBeAsked } ?? false
        }
        func wereAtItsTerminal(_ threadID: String) -> Bool {
            terminalVerdictByThreadID[threadID] == .read
        }

        guard generation == observationGeneration else {
            return ReadEvidenceJudgement(verdicts: [:], diagnostic: nil)
        }
        // Only rows the user has not removed reach this (CR-Fable-003).
        for candidate in candidates {
            let row = candidate.row
            let turnEndedAt = candidate.turnEndedAt
            let state = readState.readState(
                forSession: row.threadID,
                terminalBoundaryAt: turnEndedAt
            )
            // Kept here, the one place that knows both what Desktop has on screen and whether the Turn
            // is over. Running again drops the membership; it is earned against what Desktop says is on
            // screen, not the newest stamp.
            if row.status == .completed, isOnScreen(row.threadID) {
                sessionsSeenOnScreenSinceTheirTurnEnded.insert(row.threadID)
            } else if row.status != .completed {
                sessionsSeenOnScreenSinceTheirTurnEnded.remove(row.threadID)
            }
            // A terminal nobody is in front of answers "not read", so the row stays gated. A device is
            // not enough (CR-Fable-036): under `tmux`, `screen` or `ssh` the ancestry runs to `launchd`,
            // the host can never hold the front, and the row re-checked once a second forever.
            let terminalCanSpeak = terminalCanSpeak(row.threadID)
            let terminalSaysRead = wereAtItsTerminal(row.threadID)
            switch state {
            case .unknown:
                // Only its terminal can speak for it; a gesture after the Turn ended is the evidence.
                guard terminalCanSpeak else {
                    // Nothing can speak for it (no device, or a `launchd` host): kept
                    // out of the gate so it books no re-check.
                    break
                }
                if !terminalSaysRead {
                    unreadThreadIDs.insert(row.threadID)
                }
                restsOnTerminalByRowID[row.id] = true
            case .unread:
                if comingBackShowedIt(row.threadID, since: turnEndedAt)
                    || isInFrontOfThem(row.threadID)
                    || movedOnFrom(row.threadID)
                    || terminalSaysRead {
                    restsOnTerminalByRowID[row.id] = terminalSaysRead
                } else {
                    unreadThreadIDs.insert(row.threadID)
                    restsOnTerminalByRowID[row.id] = false
                }
            case .read:
                restsOnTerminalByRowID[row.id] = false
            }
        }
        // Membership goes with a session no longer listed or a row the user removed; the next Turn
        // must earn it again.
        sessionsSeenOnScreenSinceTheirTurnEnded.formIntersection(
            Set(candidates.map(\.row.threadID))
        )

        // Both snapshots come from readings this refresh took, so `now` is their true
        // ``DesktopUnreadStateSnapshot/currentAsOf``.
        let desktopUnreadState = DesktopUnreadStateSnapshot(
            unreadThreadIDs: unreadThreadIDs,
            // A non-current reading may not hide anything, as on the Codex side.
            source: readState.source.isAuthoritative ? .current : .lastKnownGood,
            currentAsOf: now
        )
        // Terminal verdicts carry their own authority: a machine without Claude Desktop reports
        // `unavailable`, which would leave every terminal row ungated. A device's access time is read
        // from the kernel this refresh and cannot be a generation behind.
        let terminalUnreadState = DesktopUnreadStateSnapshot(
            unreadThreadIDs: unreadThreadIDs,
            source: .current,
            currentAsOf: now
        )
        var verdicts: [String: ReadGateVerdict] = [:]
        for candidate in candidates {
            guard let restsOnTerminal = restsOnTerminalByRowID[candidate.row.id] else {
                verdicts[candidate.row.id] = .cannotBeAsked
                continue
            }
            verdicts[candidate.row.id] = .judged(
                by: restsOnTerminal ? terminalUnreadState : desktopUnreadState
            )
        }
        return ReadEvidenceJudgement(verdicts: verdicts, diagnostic: readState.diagnostic)
    }
}
