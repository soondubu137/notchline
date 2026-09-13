import Foundation

/// Whether a finished Claude Code row has been read — this product's read
/// evidence (``ReadEvidenceSource``), taken out of `ClaudeCodeMonitorService`
/// on 2026-09-12 so that which rows are judged, and how the gate is booked, is
/// the rule every product shares (``TerminalUnreadRowFilter``) and only the
/// verdict is this product's.
///
/// **Five routes to "read", answering five different ways of reading it.**
/// The first is the file's own and lives in the provider: Claude Desktop
/// put the session on screen after the Turn ended, or the user archived it.
/// The other four are decided here, because each needs a fact the file
/// does not hold, and a decision spanning sources belongs with the evidence
/// that spans them rather than in any one reader:
///
/// - **came back to it** -- the application returned to the front after the
///   Turn ended, showing this session (the user was somewhere else);
/// - **it is in front of them** -- the application holds the front, on a
///   waking, unlocked screen, with this session on it (the user never went
///   anywhere);
/// - **moved on from it** -- this session was seen on screen with its Turn
///   already over, and Claude Desktop has since put a different one there;
/// - **they were at its terminal** -- the session's own controlling
///   terminal handed it something after the Turn ended. The only one of
///   the five that never mentions Claude Desktop, and the only one a
///   session started from a terminal can reach.
///
/// Three of them are the same claim in three shapes -- *the user made a
/// move only a person makes, while the answer was in front of them*. The
/// second is not, and it is the one that decides how this product fails: at
/// the instant a Turn ends, somebody watching it finish and somebody who
/// submitted and walked away have done exactly the same last thing, so no
/// move separates them. Rather than keep every such row, the product
/// retires it and accepts losing the row for the second user.
///
/// **The fifth route asks the session's own terminal, and it is asked for
/// every session, not only the ones Claude Desktop has never heard of.**
/// The first four all rest on Desktop's record of which session it has on
/// screen, and a session started from a terminal has no such record -- so
/// the obvious shape is a fallback, consulted only when Desktop answers
/// `unknown`. Remote control is why it is not written that way: it puts
/// one session in front of the user in both places at once, and reading it
/// in the terminal stamps nothing Desktop writes down. A row that deferred
/// to Desktop's record would then never leave for a user who reads where
/// the session is actually running. See
/// ``ControllingTerminalGestureReporting``.
///
/// It answers a **narrower** question than the Desktop routes on purpose.
/// Those ask "was this session on screen when the user did something";
/// this one cannot, because which tab of a terminal emulator is visible is
/// not knowable without inspecting windows, and that ban stands. What it
/// asks instead is "was the user at *this* session's terminal after the
/// Turn ended", which the kernel already records per device.
///
/// **Only a session nothing can speak for is kept out of the gate.** That
/// is now the narrow case rather than the common one: a session with no
/// controlling terminal, and no Desktop record either. Its row keeps the
/// behaviour it has always had -- the next submission, the session going
/// away, or the user removing it -- and it books no re-check, because a
/// question with no possible answer must not be re-asked once a second for
/// the life of the session.
///
/// The cost of that choice is one narrow case: if the whole account tree
/// stops being readable while a row is already hidden, its session goes
/// back to `unknown` and the row returns. Deleting a session in Claude
/// Desktop is the only way to reach it, and that also ends the session, so
/// the row leaves on the next refresh anyway.
///
/// **The first three all ask one question, and it now has two sources.**
/// *Is this session the one on Claude Desktop's screen?* The records answer
/// only half of it -- they record a session being put on screen and never
/// one being taken away -- so a user who leaves a session for the composer
/// of a new one leaves it named as if it were still there, and the row is
/// retired unread the moment the new session starts. Desktop's own log says
/// the other half; ``isOnScreen(_:)`` reads it as a veto over the records,
/// which is what keeps a log this app cannot parse from changing any
/// verdict at all.
actor ClaudeCodeReadEvidence: ReadEvidenceSource, ManagedMonitoringSource {
    /// Which sessions the user has already read, when anything can say.
    nonisolated private let readState: any ClaudeCodeReadStateProviding
    /// When Claude Desktop last came to the front.
    ///
    /// The second of the two routes to "read", and the one that covers the
    /// ordinary way people use this product: you leave a session running, go
    /// somewhere else, and come back to the same session. Claude Desktop stamps
    /// a focus when it *puts* a session on screen and writes nothing at all
    /// when its window regains focus over a session already there -- measured
    /// 2026-08-19 across the whole application-support tree, zero files touched
    /// -- so the file alone can never see that reading happen.
    nonisolated private let activations: any DesktopActivationReporting
    /// Whether Claude Desktop is in front of the user right now.
    ///
    /// The third route, and the one that covers a session that was *already* on
    /// screen when its Turn ended. Neither of the first two can: nothing is
    /// written when a window regains focus over the session already showing,
    /// and no activation happens when the application never lost the front.
    /// It is also the only route that asks a state instead of watching for a
    /// gesture, and therefore the only one that can retire a row nobody read --
    /// see ``DesktopReadingWatcher`` for why that is the accepted trade and
    /// what it excludes.
    private let reading: any DesktopReadingReporting
    /// What Claude Desktop says it has on screen, including nothing.
    ///
    /// Not a fifth route: a veto over the three above. All three ask whether a
    /// session is on Desktop's screen, and the records they ask can only ever
    /// say a session was *put* there -- so a user who navigates to the composer
    /// for a new session leaves the last-stamped session named as if it were
    /// still in front of them, and its finished row is retired unread the
    /// moment that new session starts. This is where Desktop says otherwise;
    /// see ``DesktopDisplayedSessionReporting`` for the measurement and for why
    /// it may only ever keep a row.
    private let displayed: any DesktopDisplayedSessionReporting
    /// When the user was last at a session's own terminal.
    ///
    /// The answer for the half of this product Claude Desktop cannot speak for
    /// at all. It is not the same claim as any of the three above — nothing
    /// here says which tab is on screen, which is the question a terminal
    /// cannot answer and this app does not ask. It says that *this* session's
    /// terminal handed it something, which no other tab, window or application
    /// can cause: a key, or that surface gaining or losing the front. See
    /// ``ControllingTerminalGestureReporting``.
    private let terminal: TerminalReadEvidence
    /// The sessions this app has seen on Claude Desktop's screen while their
    /// Turn was already finished.
    ///
    /// Observed live, refresh by refresh, rather than reconstructed afterwards
    /// from the focus instants in the records. Both would answer "was it on
    /// screen when it ended", but only one of them obeys `AGENTS.md` §6.2: a
    /// timestamp older than this process says a session was displayed once, not
    /// that it was displayed *then*, and a record the user has since deleted
    /// would silently hand the answer to whichever session held the next-oldest
    /// stamp.
    ///
    /// It is half of a rule, never a verdict. On its own it says a finished
    /// answer is sitting on the user's screen, which is not the same as their
    /// having read it -- Claude Desktop leaves a session on screen whether
    /// anybody is in front of it or not. What retires the row is this plus a
    /// move only a person makes.
    private var sessionsSeenOnScreenSinceTheirTurnEnded: Set<String> = []
    private var observationGeneration = 0

    /// Whether there is a screen the user could read a finished answer on.
    nonisolated var screen: any ScreenAvailabilityReporting { terminal.screen }

    init(
        /// Which process each session runs as, from the list the refresh
        /// being judged read -- never looked up again, since a second reading
        /// could launch a `claude` in the middle of the verdicts.
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

    /// No finished row is listed, or nothing is. Every listed row would have
    /// dropped its on-screen membership, so the membership goes; and a session
    /// that was on screen when the integration was switched off must not come
    /// back holding a claim to have been seen there.
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
        /// Each judged row, and whether the terminal reading is what decides
        /// it. A row absent here was one nothing can speak for.
        ///
        /// The two sources carry different authority and one snapshot cannot
        /// hold both -- see where they are built below.
        var restsOnTerminalByRowID: [String: Bool] = [:]

        /// Whether Claude Desktop has this session on screen right now.
        ///
        /// **Two sources, and the row stays unless they agree.** The records
        /// answer "which session was last *put* on screen", which is all they
        /// can: Claude Desktop stamps a session being displayed and writes
        /// nothing when it is taken away, so the newest stamp goes on naming a
        /// session the user has since navigated away from. Desktop's own log
        /// says the other half, `sessionId=null` included, and it is read as a
        /// veto rather than as a source: it can withhold a session the stamps
        /// claim, never nominate one they do not.
        ///
        /// That asymmetry is what makes a log this app cannot read harmless.
        /// ``DesktopDisplayedSession/unknown`` -- no log, an unreadable one, a
        /// line shape some future Desktop no longer writes -- is exactly the
        /// behaviour the three rules below had before the log was consulted at
        /// all.
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

        /// Whether Claude Desktop has put a *different session* on screen.
        ///
        /// Not the negation of the above, and the difference is the whole
        /// point: a composer is not a session, so navigating to one displaces a
        /// session without anybody having moved on from reading it. That is
        /// what ``DesktopDisplayedSession/nothing`` answers, and it answers it
        /// here as it does above.
        ///
        /// **The log answers this one on its own, and the records only stand in
        /// when it cannot.** Everywhere else the log is a veto over the records
        /// and never a source, because the direction it is trusted in can only
        /// *keep* a row. This is the one question where the same asymmetry
        /// pointed the same way produces a hole instead, and the hole is a
        /// visible bug: the two sources say the same thing at different times.
        /// Claude Desktop stamps `lastFocusedAt` and logs the navigation in the
        /// same instant, then writes the record about a second later (measured
        /// on this machine, 2026-08-20: 1.03s between the stamp and the write
        /// landing). Requiring the *records* to already name something else
        /// meant that for that second the session the user had just left was
        /// neither on screen -- the log vetoed it -- nor replaced, because the
        /// newest stamp was still its own. Every read route failed, the row was
        /// reported unread again, and the finished row came back and lit the
        /// matrix until the record landed (CC-024).
        ///
        /// Believing the log here is not a new verdict, only an earlier one: it
        /// is the same session the records name a second later. And it stays a
        /// claim about what is *on screen* rather than about what was read --
        /// ``movedOnFrom(_:)`` is what turns it into reading, and it does that
        /// only for a session already seen on screen with its Turn over.
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
                // The name on screen joins to nothing, and two very different
                // things look like that. A record Claude Desktop has not
                // written yet is the case this branch exists for. A record
                // that has stopped carrying its own id is the other, and
                // retiring a row on a name nothing verified is exactly what
                // reading the log as a veto is meant to prevent.
                //
                // This session's own record separates them without waiting for
                // anything: a session whose record names a *different* Desktop
                // id is not the one on screen, whatever the pending record
                // turns out to say. A session whose record names none cannot be
                // told apart from the name on screen at all, so the records
                // answer alone, exactly as they did before the log was read.
                guard let own = readState.desktopSessionID(forSession: sessionID) else {
                    guard let stamped = readState.mostRecentlyDisplayedSessionID else {
                        return false
                    }
                    return stamped != sessionID
                }
                return own != desktopSessionID
            }
        }

        /// Whether coming back to Claude Desktop showed the user this session.
        ///
        /// Two facts, and neither is a guess on its own: Claude Desktop's own
        /// record says which session it last put on screen, and the workspace
        /// says the application came to the front. Requiring the activation to
        /// be *later than the Turn's end* is what makes it evidence of reading
        /// rather than of having been there -- and requiring an activation at
        /// all, rather than "is frontmost now", is what stops a user who walked
        /// away with the window in front from having the row retired for them.
        func comingBackShowedIt(_ sessionID: String, since boundary: Date) -> Bool {
            guard isOnScreen(sessionID), let activatedAt else { return false }
            return activatedAt >= boundary
        }

        /// Whether the finished answer is in front of the user right now.
        ///
        /// The case neither route above can reach: the session was on screen
        /// before the Turn ended and nobody left, so Claude Desktop wrote
        /// nothing and never came back to the front.
        ///
        /// **The one rule here that asks a state rather than watching for a
        /// gesture, and the one that can retire a row nobody read.** That is a
        /// decision rather than a slip: at the instant a Turn ends, somebody
        /// watching it finish and somebody who submitted and walked away have
        /// done exactly the same last thing, so no gesture separates them and
        /// no amount of waiting will produce one. The product chooses to answer
        /// the narrower question -- is that answer on a screen somebody could
        /// be looking at -- and to accept losing the row for a user who stepped
        /// away with the window in front. ``DesktopReadingWatcher`` carries
        /// what "could be looking at" excludes; the row is dismissible by hand
        /// either way, and a row retired early cannot be brought back.
        func isInFrontOfThem(_ sessionID: String) -> Bool {
            isOnScreen(sessionID) && desktopIsInFrontOfTheUser
        }

        /// Whether the user moved on from it inside Claude Desktop.
        ///
        /// Seen on screen with its Turn already over, and Claude Desktop has
        /// since put something else there. Putting a session on screen is a
        /// deliberate act on a session -- the same act the first route reads,
        /// pointed the other way -- so it says the user was in that window,
        /// looking at this answer, and chose to go elsewhere.
        ///
        /// No timestamps are compared, because none are needed: the membership
        /// was recorded while this session *was* the one displayed and its Turn
        /// was already finished, so anything that displaced it necessarily
        /// happened afterwards. It is also what keeps Claude Desktop's own
        /// bookkeeping out of the verdict -- waking from sleep re-stamps the
        /// session already on screen, never a different one.
        ///
        /// **What displaced it has to be another session.** Starting a new one
        /// displaces the last-stamped session too, and used to retire its row
        /// on that alone -- the user had been typing into a composer since
        /// before the Turn ended, so the answer they were credited with reading
        /// had not been on screen for any of it. That is now the difference
        /// between "something else is displayed" and
        /// ``hasReplacedItOnScreen(_:)``.
        func movedOnFrom(_ sessionID: String) -> Bool {
            sessionsSeenOnScreenSinceTheirTurnEnded.contains(sessionID)
                && hasReplacedItOnScreen(sessionID)
        }

        /// What this session's own terminal says about the user being at it.
        ///
        /// Read once per row per refresh rather than lazily inside the switch,
        /// so a row's verdict and its gate entry come from one reading -- and
        /// so the two halves of that reading, the gesture and who was holding
        /// the front when it was taken, describe the same instant. Only a
        /// session with a controlling terminal answers at all.
        ///
        /// It is the terminal verdict every CLI product gets
        /// (``TerminalReadEvidence``), asked about the process the refresh's own
        /// session list named rather than about one looked up again.
        var terminalVerdictByThreadID: [String: TerminalReadEvidence.Verdict] = [:]
        for candidate in candidates {
            terminalVerdictByThreadID[candidate.row.threadID] = await terminal.verdict(
                forThreadID: candidate.row.threadID,
                turnEndedAt: candidate.turnEndedAt
            )
        }

        /// Whether the user was at this session's own terminal after it
        /// finished, and whether that terminal can ever say so.
        ///
        /// **A peer of the three routes above, not a fallback behind them.**
        /// It is tempting to ask this only when Claude Desktop has nothing to
        /// say, because the two halves normally partition cleanly -- a session
        /// Desktop hosts has a record, a session started from a terminal does
        /// not. Remote control is the case that shows why the product must not
        /// depend on that: it puts one session in front of the user in *both*
        /// places, and the two are read by different gestures. A session
        /// answered only by Desktop's record would then keep its row forever
        /// for a user who reads it in the terminal, because reading there
        /// stamps nothing Desktop writes down.
        ///
        /// Asking both and taking either is safe in the direction that
        /// matters, and the reason is structural rather than lucky: this can
        /// only fire for a session that **has** a controlling terminal, and a
        /// session Claude Desktop hosts has none -- Desktop runs the CLI as
        /// `--output-format stream-json` over pipes, with no terminal UI at
        /// all, which is also why those sessions report no `status` (#41).
        ///
        /// **Two facts, and the second is not decoration.** The gesture says
        /// the terminal handed this session something after its answer landed;
        /// the front says that terminal's application was the one the user was
        /// in when it did. Requiring both is what stops the pointer crossing an
        /// unfocused terminal window on a second display from retiring a row --
        /// Claude Code turns on any-event mouse tracking, so that crossing is
        /// bytes into the pty and a gesture indistinguishable from a keystroke
        /// by the time it is read. ``ControllingTerminalGestureReporting``
        /// carries the measurements.
        func terminalCanSpeak(_ threadID: String) -> Bool {
            terminalVerdictByThreadID[threadID].map { $0 != .cannotBeAsked } ?? false
        }
        func wereAtItsTerminal(_ threadID: String) -> Bool {
            terminalVerdictByThreadID[threadID] == .read
        }

        guard generation == observationGeneration else {
            return ReadEvidenceJudgement(verdicts: [:], diagnostic: nil)
        }
        // Only rows the user has not taken off the list reach this, so none
        // of the reading above or below is spent on one (CR-Fable-003).
        for candidate in candidates {
            let row = candidate.row
            let turnEndedAt = candidate.turnEndedAt
            let state = readState.readState(
                forSession: row.threadID,
                terminalBoundaryAt: turnEndedAt
            )
            // Kept up to date here rather than anywhere else, because this is
            // the one place that knows both halves at once: which session
            // Claude Desktop has on screen, and whether this row's Turn is over.
            // A row that is running again drops its membership -- it belongs to
            // the finished Turn that was on screen, not to the session, and a
            // new Turn has to earn it again. And it is earned against what
            // Desktop says is on screen, not against the newest stamp: a Turn
            // that ended behind the composer for a new session was never on
            // screen for the user to move on from.
            if row.status == .completed, isOnScreen(row.threadID) {
                sessionsSeenOnScreenSinceTheirTurnEnded.insert(row.threadID)
            } else if row.status != .completed {
                sessionsSeenOnScreenSinceTheirTurnEnded.remove(row.threadID)
            }
            // Whether a reading that cannot be a generation behind is what
            // decides this row -- see where the two snapshots are built.
            // A terminal nobody is in front of answers "not read" rather than
            // "cannot say", so that row belongs in the gate and gets looked at
            // again a second later.
            //
            // Having a device is not enough to be asked, though, and reading it
            // that way was CR-Fable-036. A session under `tmux`, `screen` or
            // `ssh` has a controlling terminal -- so it answers non-nil -- while
            // its ancestry runs to `launchd` without passing through an
            // application, so its host can never hold the front and the verdict
            // is permanently false. That is a question with no possible answer
            // wearing the clothes of one that merely has not been answered yet,
            // and it booked a full two-product refresh once a second for the
            // life of the session. The predicate has to ask what the comment
            // below says: not "is there a device" but "is there a host that
            // could ever say yes".
            let terminalCanSpeak = terminalCanSpeak(row.threadID)
            let terminalSaysRead = wereAtItsTerminal(row.threadID)
            switch state {
            case .unknown:
                // Claude Desktop cannot speak for this session, so only its
                // terminal can. A gesture *after* the Turn ended is what makes
                // it evidence of reading rather than of having been there at
                // some point — the same shape as every rule above.
                guard terminalCanSpeak else {
                    // Nothing anywhere can speak for it -- no device at all, or
                    // a device whose host is `launchd` and so can never be in
                    // front. Kept out of the gate entirely rather than reported
                    // unread, so it books no re-check for a question with no
                    // possible answer. Such a row leaves the way a terminal row
                    // always did: on the next submission, when the session goes
                    // away, or when the user removes it.
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
        // A session nobody is listing any more takes its membership with it, so
        // a session that comes back cannot be retired on what it did last time.
        // A row the user removed goes too: its Turn is no longer judged, and
        // the next Turn in that session has to earn the membership again.
        sessionsSeenOnScreenSinceTheirTurnEnded.formIntersection(
            Set(candidates.map(\.row.threadID))
        )

        // `now` is part of what the two snapshots below say: both are assembled
        // here, out of readings this refresh took, so the instant they are a
        // complete account up to is this refresh's own.
        //
        // That is the honest answer and not a convenient one. The Codex file
        // needs ``DesktopUnreadStateSnapshot/currentAsOf`` because it is a
        // projection Desktop writes when it gets round to it; nothing here is
        // a projection of anything -- the verdicts below were computed from
        // `readState`, the terminal readings and the front, in this call.
        let desktopUnreadState = DesktopUnreadStateSnapshot(
            unreadThreadIDs: unreadThreadIDs,
            // A reading that is not current may not hide anything, exactly as
            // on the Codex side. It matters less here -- a focus instant older
            // than the Turn cannot claim the Turn was read, whatever generation
            // it came from -- but the rule is the product's, not the schema's.
            source: readState.source.isAuthoritative ? .current : .lastKnownGood,
            currentAsOf: now
        )
        // A terminal verdict carries its own authority rather than Claude
        // Desktop's, and the difference is not cosmetic: a user who has never
        // opened Claude Desktop has no tree at all, which reports
        // `unavailable`, and a non-authoritative snapshot may hide nothing --
        // so borrowing that source would leave every terminal row permanently
        // ungated, on exactly the machines this route exists for.
        //
        // It is honest as well as necessary. The Desktop source exists because
        // a reading can be a generation behind: a snapshot retained after a
        // parse failure carries yesterday's focus instants. A device's access
        // time cannot be behind -- it is read from the kernel in the same
        // refresh that uses it, and a reading that fails answers nil and takes
        // its row out of the gate entirely rather than into it with a stale
        // verdict.
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
