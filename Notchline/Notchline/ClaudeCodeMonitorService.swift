import Foundation

/// Watches Claude Code, and is one of the products the notch summarises.
///
/// Deliberately smaller than the Codex service. The biggest of that one's jobs
/// is simply absent here: there is no app-server subprocess to run and keep
/// alive, because session identity comes from a documented command.
///
/// Hook registration is no longer a difference between the two. It once was —
/// ADR 0010 left `~/.claude/settings.json` to the user — and ADR 0016 took that
/// back: both products install and remove their own definitions, through the
/// same strict editor, and this one keeps a copy of the user's file beside it
/// before each change.
///
/// The startup boundary, though, is the same on both sides: nothing that
/// happened before this app launched is ever shown. Claude Code's transcript
/// can name a turn already in flight and this service used to read it, which
/// was the one place the two products genuinely differed in what they could
/// know. It was removed. A turn waiting on the user writes nothing at all, so
/// the reconstruction could only ever say Running -- a session parked on a
/// permission prompt when the app started was drawn as working, and telling a
/// wait from work is precisely what the product is for.
actor ClaudeCodeMonitorService: AgentMonitoring, IntegrationConfiguring, AnswerDelivering,
    DiskFootprintReporting, SessionProcessLocating {
    nonisolated let agent = AgentKind.claudeCode
    nonisolated let stateChangeEvents: AsyncStream<Void>

    /// Claude Desktop's bundle identifier, used only to recognise the
    /// application in the workspace's activation notification. It is not
    /// promised by any official contract -- see the registry.
    nonisolated static let desktopBundleIdentifier = "com.anthropic.claudefordesktop"

    /// The hook transport, wired once (``HookLifecycleSource``); the reducer
    /// below is its member, kept under its own name because the rest of this
    /// actor reads it constantly.
    private let hooks: HookLifecycleSource
    private let hookEvents: HookEventRepository
    private let sessions: any ClaudeCodeSessionListing
    private let transcripts: ClaudeCodeTranscriptReader
    private let usage: ClaudeCodeUsageReader
    /// Whether there is a `claude` on this machine for the registry to run.
    ///
    /// Asked only when the registry has stopped answering, so on a healthy
    /// machine it costs nothing: a list that came back is itself proof that
    /// an executable was found. Injected so the suite's own answer does not
    /// depend on whether Claude Code happens to be installed beside it.
    nonisolated private let commandIsInstalled: @Sendable () -> Bool
    /// Held, because a watcher nobody holds is a watcher that has already
    /// stopped.
    ///
    /// It used to be built inline and only its stream kept. ``AsyncStream``
    /// does not retain the object that vends it -- the subscription is a
    /// continuation stored *in* the watcher, and the termination handler holds
    /// the watcher weakly -- so the instance died at the end of the expression
    /// that created it, and its `deinit` finished every continuation and
    /// cancelled the dispatch source. The stream was therefore not merely
    /// silent: it was over before `init` returned. This is the only watcher in
    /// the app that was built that way; the Hook queue's and the Codex unread
    /// adapter's have always been stored properties.
    nonisolated private let sessionsWatcher: DirectoryChangeWatcher
    /// The records of the sessions whose turn is still going.
    ///
    /// Held for the same reason ``sessionsWatcher`` is, and answering what that
    /// one cannot: a session being interrupted neither creates nor removes a
    /// file, so the directory says nothing about it.
    ///
    /// Not private, so a test can read how many records are being watched.
    /// What it costs to watch one is a `claude` launch per rewrite, so "only
    /// while that turn is going" is a real invariant and not an implementation
    /// detail -- and asserting it through the change stream instead means
    /// asserting that an edge did *not* arrive, which any other source firing
    /// would make untrue.
    nonisolated let recordWatcher: ClaudeCodeSessionRecordWatcher
    /// The transcripts of the turns that are still going in a session which
    /// reports no status of its own.
    ///
    /// The same job as ``recordWatcher`` for the sessions that one cannot
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
    /// Not private, for the reason ``recordWatcher`` is not: what is watched,
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
    /// Which sessions the user has already read, when anything can say.
    private let readState: any ClaudeCodeReadStateProviding
    /// When Claude Desktop last recorded a human answering one of its dialogs.
    ///
    /// The desktop half of "the approval has been answered", and the only half
    /// that reaches a desktop-hosted session -- see
    /// ``ClaudeDesktopPermissionLogReader`` for why no hook and no session
    /// status can.
    private let permissions: any DesktopPermissionResponseReporting
    /// The file behind that, for the watcher rather than the reader.
    ///
    /// Held separately because the reader answers questions and the watcher
    /// needs a path; a test pointing one at its own log has to be able to point
    /// the other at the same one.
    nonisolated private let permissionLogURL: URL
    /// Whether a finished row has been read: the five routes, and the
    /// on-screen membership they keep across refreshes
    /// (``ClaudeCodeReadEvidence``).
    private let readEvidence: ClaudeCodeReadEvidence
    /// The process each session ran as in the list the current refresh read,
    /// which is what the terminal route asks about.
    private let listedProcesses: ListedSessionProcesses
    /// Keeps a finished row listed until it has been read, and retires it the
    /// moment it has been.
    ///
    /// The same filter the Codex side uses, given the same shape of answer:
    /// this product's evidence is a focus instant rather than a blue dot, so
    /// the verdicts handed over are computed per refresh from those instants
    /// and each Turn's own last moment -- see
    /// ``ClaudeCodeReadStateSnapshot/readState(forSession:terminalBoundaryAt:)``.
    private var terminalReadMembershipGate: TerminalUnreadRowFilter
    /// Whether there is a screen the user could read a finished answer on.
    ///
    /// Read where the gate books its re-check, not inside the verdicts -- those
    /// already make the same reading for themselves. See
    /// ``TerminalUnreadMembershipGate/nextDeadline(now:screenIsAvailable:)``.
    nonisolated private let screenAvailability: any ScreenAvailabilityReporting
    private let clock: any MonitorClock
    /// Whether ``sessionsWatcher`` was attached at the end of the last refresh.
    ///
    /// Only ever used to spot it becoming attached, which is an edge the
    /// watcher has no way to deliver -- see ``fetchSnapshot()``.
    private var wasWatchingSessionsDirectory: Bool

    init(
        paths: HookIntegrationPaths = .liveClaudeCode(),
        setup: ManagedHooksSetup? = nil,
        hookEvents: HookEventRepository? = nil,
        sessions: (any ClaudeCodeSessionListing)? = nil,
        listener: AgentHookListener? = nil,
        transcripts: ClaudeCodeTranscriptReader? = nil,
        usage: ClaudeCodeUsageReader? = nil,
        readState: (any ClaudeCodeReadStateProviding)? = nil,
        activations: (any DesktopActivationReporting)? = nil,
        reading: (any DesktopReadingReporting)? = nil,
        displayed: (any DesktopDisplayedSessionReporting)? = nil,
        permissions: (any DesktopPermissionResponseReporting)? = nil,
        permissionLogURL: URL = ClaudeDesktopFocusLogReader.liveLogURL(),
        terminalGestures: (any ControllingTerminalGestureReporting)? = nil,
        screenAvailability: (any ScreenAvailabilityReporting)? = nil,
        sessionsDirectory: URL? = nil,
        /// Which entries of that directory belong to a `claude` this app
        /// launched. Injected only so the rule can be tested without launching
        /// one — see ``sessionsChanged(_:invalidating:in:ownedBy:)``.
        ownsSessionRecord: (@Sendable (String) -> Bool)? = nil,
        /// Whether a `claude` executable can be found at all. Injected for the
        /// reason the readers above are: left with the default, a test would
        /// answer with whatever the developer happens to have installed.
        commandIsInstalled: (@Sendable () -> Bool)? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard
    ) {
        self.commandIsInstalled = commandIsInstalled
            ?? { ClaudeExecutableLocator.locate() != nil }
        // The one folder this app's own quota reading runs in, named once and
        // given to everything that has to be able to tell that reading apart
        // from a session the user started. It reaches the app by two routes and
        // both of them need it: the reading is listed by `claude agents --json`
        // like any other session, and it is a session that could fire hooks.
        // Before this the directory was only ever spelled out where the reading
        // was pinned to it -- the store was handed nothing, and the registry
        // had no notion that such a session existed.
        let quotaDirectory = paths.quotaWorkingDirectory
        // Resolved before the two readers below rather than beside the gate
        // that reads it, because both of them now take it: a `claude` launched
        // for a figure nobody can look at is the same waste as a re-check
        // booked for a row nobody can read.
        let resolvedScreenAvailability = screenAvailability
            ?? ScreenAvailabilityWatcher()
        self.screenAvailability = resolvedScreenAvailability
        let hooks = HookLifecycleSource(
            paths: paths,
            vocabulary: ClaudeCodeHookVocabulary(),
            clock: clock,
            timing: timing,
            ignoredWorkingDirectory: quotaDirectory,
            setup: setup,
            repository: hookEvents,
            listener: listener
        )
        self.hooks = hooks
        let repository = hooks.repository
        self.hookEvents = repository
        let resolvedSessions = sessions ?? ClaudeCodeSessionRegistry(
            clock: clock,
            ignoringWorkingDirectory: quotaDirectory,
            screenIsAvailable: resolvedScreenAvailability.isAvailable
        )
        self.sessions = resolvedSessions
        // A row's third line arriving where there was none used to need a
        // stream of its own. It does not any more: the store signals when what
        // a row draws has changed, and "this session has text where it had
        // none" is part of that projection -- while the deltas themselves stay
        // off it, because three a second is not a redraw rate.
        self.transcripts = transcripts ?? ClaudeCodeTranscriptReader()
        // The quota's own edge. Nothing waits for the reading any more, so the
        // reading has to say when it landed -- otherwise a figure read at
        // second five would not be drawn until whatever happened to refresh
        // next, which is the wait this stopped blocking to avoid.
        let (quotaUpdates, quotaLanded) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        // Pinned to a directory of its own, which is the only thing that
        // separates this reading from the user's own sessions -- `claude agents
        // --json` reports it as `kind: "interactive"` like any other.
        //
        // Measured on 2.1.234, 2026-08-18: `-p "/usage"` is a slash command, so
        // it reaches no model (`num_turns: 0`) and fires **no hooks at all**.
        // The listener's filter is therefore belt to the registry's braces
        // today, and is wired anyway: "fires no hooks" is a property of
        // somebody else's command, not a promise to this app.
        self.usage = usage ?? ClaudeCodeUsageReader(
            clock: clock,
            workingDirectory: quotaDirectory,
            screenIsAvailable: resolvedScreenAvailability.isAvailable,
            tokens: ClaudeCodeTokenCounter(clock: clock),
            transcripts: ClaudeCodeUsageTranscripts(clock: clock),
            onUpdate: { quotaLanded.yield() }
        )
        self.clock = clock
        let resolvedReadState = readState ?? ClaudeCodeDesktopReadStateRepository(
            changeDebounceInterval: timing.unreadStateDebounceInterval
        )
        self.readState = resolvedReadState
        let resolvedActivations = activations ?? DesktopActivationWatcher(
            bundleIdentifier: Self.desktopBundleIdentifier,
            clock: clock
        )
        // No change stream of its own: the front, the lock and the display are
        // three states that have to agree, so a notification for any one of
        // them says nothing on its own, and the reading is sampled at the
        // re-check a row waiting on the user books every
        // ``MonitorTiming/terminalUnreadRecheckInterval``.
        //
        // It used to say the notifications were not needed at all. They are:
        // the re-check is now deferred while the display is asleep or the
        // screen locked, because every route out of that state needs a screen
        // the user can see, and a sample taken through a locked screen is not
        // a sample of anything (CR-Fable-018). ``ScreenAvailabilityWatcher``
        // carries those edges -- one stream for the moment the answer could
        // have become yes, rather than three states this reading would have to
        // re-derive.
        let resolvedReading = reading ?? DesktopReadingWatcher(
            bundleIdentifier: Self.desktopBundleIdentifier
        )
        // No change stream of its own either, and for its own reason: the
        // transition only this reader can see -- a session leaving the screen
        // for a composer -- can only ever *keep* a row, and a listed row books
        // a re-check every second anyway. Every transition that can retire one
        // arrives on an edge that already exists, because Desktop writes the
        // record of whatever it put on screen instead. See
        // ``ClaudeDesktopFocusLogReader``.
        let resolvedDisplayed = displayed ?? ClaudeDesktopFocusLogReader()
        // No change stream of its own either, and for a sharper reason than
        // the reading above: a device's access time moves in the kernel and
        // leaves nothing a file-system watcher can attach to. It is sampled at
        // the same re-check a row waiting on the user already books, so the
        // bound on how late such a row leaves is
        // ``MonitorTiming/terminalUnreadRecheckInterval`` -- one `sysctl` and
        // one `stat` per listed terminal row per second, and nothing at all
        // when no such row is listed.
        let listedProcesses = ListedSessionProcesses()
        self.listedProcesses = listedProcesses
        self.readEvidence = ClaudeCodeReadEvidence(
            sessions: listedProcesses,
            readState: resolvedReadState,
            activations: resolvedActivations,
            reading: resolvedReading,
            displayed: resolvedDisplayed,
            terminalGestures: terminalGestures ?? ControllingTerminalGestureReader(),
            screen: resolvedScreenAvailability
        )
        self.terminalReadMembershipGate = TerminalUnreadRowFilter(timing: timing)

        // Two edges, no cadence. An event arriving means a turn moved; the
        // sessions directory changing means one appeared or went away, which is
        // the only way a row whose session died can be retired now that
        // SessionEnd is not registered.
        let watched = sessionsDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/sessions", isDirectory: true)
        let sessionsWatcher = DirectoryChangeWatcher(
            directoryURL: watched,
            debounceInterval: timing.unreadStateDebounceInterval
        )
        self.sessionsWatcher = sessionsWatcher
        // Seeded from the attach `init` has just attempted, so an ordinary
        // launch -- the directory already there -- does not report an edge for
        // a watcher that was never off.
        self.wasWatchingSessionsDirectory = sessionsWatcher.isAttached
        let recordWatcher = ClaudeCodeSessionRecordWatcher(
            directory: watched,
            debounceInterval: timing.unreadStateDebounceInterval
        )
        self.recordWatcher = recordWatcher
        let transcriptWatcher = PathSetChangeWatcher(
            debounceInterval: timing.unreadStateDebounceInterval
        )
        self.transcriptWatcher = transcriptWatcher
        let permissionLogWatcher = PathSetChangeWatcher(
            debounceInterval: timing.unreadStateDebounceInterval
        )
        self.permissionLogWatcher = permissionLogWatcher
        self.permissions = permissions
            ?? ClaudeDesktopPermissionLogReader(logURL: permissionLogURL)
        self.permissionLogURL = permissionLogURL
        self.stateChangeEvents = DirectoryChangeWatcher.merged([
            repository.changeEvents(),
            Self.sessionsChanged(
                sessionsWatcher.events(),
                invalidating: resolvedSessions,
                in: watched,
                ownedBy: ownsSessionRecord ?? ClaudeCommand.ownsSessionRecord(named:)
            ),
            // Two edges from one directory, answering two different questions.
            // The one above is a session appearing or going away, which is the
            // list being *wrong*; this one is a record being rewritten, which
            // is the list being *out of date* about what that session is doing.
            // Both invalidate it, because in both cases the held answer cannot
            // be the current one.
            Self.sessionsChanged(
                recordWatcher.events(),
                invalidating: resolvedSessions
            ),
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
            // Claude Desktop writing a session's record. It is the low-latency
            // half of retiring a finished row: the write that stamps a focus is
            // an atomic replace inside the account folder, so this edge lands
            // on the same gesture that reads the answer. Nothing here
            // invalidates the session list -- that file says who has read what,
            // not which sessions exist.
            resolvedReadState.changeEvents(),
            // Claude Desktop coming to the front. It is an edge rather than a
            // deadline for the same reason the record write is: a row waiting
            // to be read should leave on the gesture that reads it, not on the
            // next re-check after it.
            resolvedActivations.changeEvents(),
            // The display waking or the screen unlocking. A row waiting on the
            // user books no re-check while neither is true, because every route
            // that could retire it needs a screen somebody can see; this is the
            // edge that starts the re-checks again. Without it such a row would
            // sit until the heartbeat, at the one moment the user is most
            // likely to be looking.
            resolvedScreenAvailability.changeEvents(),
            quotaUpdates
        ])
    }

    // MARK: - AgentMonitoring

    func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot {
        // The registration checked and the socket bound, in the order every
        // hook product refreshes in (``HookLifecycleSource/gate(productName:)``).
        // Both are this app's own files in this app's own directory, so unlike
        // the port they replaced there is nothing to lose a race for and
        // nothing in the user's file to follow.
        let status: IntegrationSetupStatus
        switch await hooks.gate(productName: agent.displayName) {
        case let .open(openStatus):
            status = openStatus
        case let .closed(availability, closedStatus, diagnostic):
            // Nothing is being monitored, so nothing is worth an edge. Left
            // alone, an integration switched off would keep a descriptor open
            // on the record of whatever turn happened to be running when it
            // was.
            recordWatcher.watch(processIdentifiers: [])
            transcriptWatcher.watch(paths: [])
            // Nothing is listed, so nothing is waiting to be read. Left alone,
            // the gate would go on reporting a re-check deadline for rows this
            // branch is not going to publish, and a session that was on screen
            // when the integration was switched off would still be holding a
            // claim to have been seen there when it comes back.
            terminalReadMembershipGate.reset()
            await readEvidence.forget()
            return snapshot(
                availability: availability,
                sessions: [],
                setupStatus: closedStatus,
                diagnostic: diagnostic
            )
        }

        // `~/.claude/sessions` does not exist until Claude Code has run once,
        // so the attach made in `init` fails for a user who registered the
        // hooks first. Retried here, on work this refresh was doing anyway, for
        // the reason the Hook queue's watcher is: nothing else would ever ask
        // again, and one failed `open` per refresh is cheaper than a timer.
        //
        // **Attaching is itself an edge**, and it has to be reported as one
        // now that a known-empty session list is held rather than re-read on a
        // cadence (CR-Fable-002). Until this moment nothing was watching the
        // directory, so the emptiness the registry is holding was read blind:
        // the very first Claude Code session a user ever starts is the one
        // that *creates* this directory, and it would otherwise go unlisted
        // until it fired a hook. The watcher itself cannot deliver this --
        // attaching bumps its change count but yields nothing to a stream that
        // had no event -- so the transition is noticed here.
        let watchingSessionsDirectory = sessionsWatcher.attachIfNeeded()
        if watchingSessionsDirectory, !wasWatchingSessionsDirectory {
            await sessions.invalidate()
        }
        wasWatchingSessionsDirectory = watchingSessionsDirectory

        let consumed = await hookEvents.drainDeliveredEvents()
        // Presence first, and once. It is asked before the list rather than
        // after it so both come from the same reading: asked afterwards, the
        // two calls could land either side of a refresh and describe different
        // instants.
        func readSessions() async -> (
            presence: AgentPresence,
            live: [ClaudeCodeSession],
            byID: [String: ClaudeCodeSession]
        ) {
            let presence = await sessions.presence()
            let live = await sessions.liveSessions()
            return (
                presence,
                live,
                Dictionary(
                    live.map { ($0.sessionID, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            )
        }
        var (presence, live, liveByID) = await readSessions()

        // **A hook event is itself evidence that its session exists**, and
        // when it is newer than the reading, it outranks it.
        //
        // Every route by which the list goes wrong is meant to be reported by
        // an edge, and one route had none: a session id is not fixed for the
        // life of a process. `/clear` and an in-session `/resume` rotate it in
        // place -- same pid, same `~/.claude/sessions/<pid>.json`, same inode,
        // a new `sessionId` written into it. Measured on this machine
        // 2026-08-21: a record still naming the pid and start time of a process
        // launched at 23:14 carried a session id whose transcript begins at
        // 01:14, two hours later. Nothing is created and nothing is removed, so
        // the directory source cannot see it; the record source is the one that
        // can, and it is now pointed at every listed session for exactly this
        // reason (below).
        //
        // This is the fail-safe behind that, and it is stated in terms of the
        // evidence rather than of any one way the list can rot: the reducer is
        // holding a Turn whose session the list does not name, and that Turn
        // has moved since the reading was taken. A reading that started before
        // the event cannot have seen what the event is reporting, so it is the
        // reading that is wrong, not the Turn -- and the row that would
        // otherwise be dropped below is drawn in this same refresh instead of
        // whenever the next reading happens to land.
        //
        // Bounded on both sides. Turns that have *not* moved since the reading
        // -- a session that really did end without a `Stop` -- never ask for
        // anything, so a Turn the list will never name cannot become a `claude`
        // launch every refresh. And what an invalidation costs is the
        // registry's decision, not this one's: ``edgeFloor`` holds the extra
        // reading to one every two seconds however many events arrive.
        var readStartedAt = await sessions.listReadStartedAt()
        let heardFromAnUnlistedSession = consumed.turns.contains { turn in
            liveByID[turn.threadID] == nil && turn.lastEventAt > readStartedAt
        }
        if heardFromAnUnlistedSession {
            await sessions.invalidate()
            (presence, live, liveByID) = await readSessions()
            // Re-asked so this stays the reading `liveByID` actually came from.
            // It is the left-hand side of the pruning below as well as of the
            // test above, and a list re-read on the spot can speak for
            // everything up to the moment it started -- which is the whole
            // point of having asked for it again.
            readStartedAt = await sessions.listReadStartedAt()
        }

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
            // The list is keyed the same way ``liveByID`` above is, and for the
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
        for turn in consumed.turns where turn.sessionStatus.keepsTiming {
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

        var hookState = consumed
        if !stopped.isEmpty {
            hookState = await hookEvents.endTurnsForStoppedSessions(stopped)
        }
        if !interruptions.isEmpty {
            hookState = await hookEvents.endInterruptedTurns(interruptions)
        }
        // After both, and disjoint from `stopped` by construction: a session is
        // either working or it is not. A turn those two just ended keeps no
        // approval for this to clear, and a turn still running is exactly the
        // one that has an answered dialog to forget.
        if !working.isEmpty {
            hookState = await hookEvents.endAnsweredApprovalWaits(working)
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
                    hookState = await hookEvents.endAnsweredApprovalWaits(answeredByThread)
                }
            }
        }
        // The reducer's own account of its health. It stands for the run
        // rather than for one drain, so every snapshot the calls above return
        // carries the whole of it; joining the drain's copy to a later one
        // said the same sentence twice.
        let hookDiagnostic = hookState.diagnostic

        // What this refresh's reading of the list says exists. Three things
        // are held to it below, and "the same set" is meant literally.
        let listedSessionIDs = Set(liveByID.keys)
        await transcripts.retain(sessionIDs: listedSessionIDs)
        // Text belonging to a session that has ended does not outlive the row
        // that showed it. Pruned against the same set as the titles.
        hookEvents.retainPreviews(forSessions: listedSessionIDs)
        // And the turns behind both of them, against that same set.
        //
        // This was the one pruning missing (CR-Fable-008). Rows were right
        // without it -- a turn whose session is not listed draws nothing, which
        // is the gate a few lines below -- so what grew was not the panel but
        // the work behind it: `HookEventRepository` builds and sorts one string
        // per held turn on *every* reduced batch of events, and sorts them all
        // again on every refresh. Both therefore scaled with everything the
        // process had ever seen rather than with what was on screen, and each
        // dead entry also held its two previews and a `retiredTurnIDs` set for
        // the life of the app. Measured under Release at ~2.2 µs per held turn
        // per event, which puts one event at 5.3 ms once 2000 entries have
        // collected -- 2.5x what CC-015 priced the whole transport at
        // (`system-architecture.md` §6).
        //
        // A session count understates how fast that arrives here. `/clear` and
        // an in-session `/resume` rotate the session id in place, so a single
        // long-lived CLI mints a fresh dead entry every time the user clears
        // context -- the same behaviour the unlisted-session check above exists
        // for, seen from the other end.
        //
        // **Only where the list is knowledge.** Presence `unknown` is `claude`
        // having failed to answer past the trust ceiling, and a list nobody has
        // confirmed is not evidence that a session ended (`AGENTS.md` §6.2) --
        // it is the reading that is missing, not the session. `closed` is the
        // opposite and prunes like any other answer: it is the command saying
        // nothing is running. The rows are withheld either way, and the
        // difference is that only one of the two may also *forget*.
        if presence != .unknown {
            hookState = await hookEvents.removeThreads(
                notIn: listedSessionIDs,
                snapshotStartedAt: readStartedAt
            )
        }

        func title(for session: ClaudeCodeSession) async -> String? {
            await transcripts.title(
                forSession: session.sessionID,
                workingDirectory: session.workingDirectory
            )
        }

        /// What this turn has said, from `MessageDisplay`, and the prompt it
        /// started from until it has said anything.
        ///
        /// Both halves are scoped to the turn. The text is asked for by turn
        /// because the store outlives one, and the prompt is the turn's own --
        /// so a row that has just been given a new prompt shows that prompt
        /// rather than the answer to the last one.
        func preview(for turn: HookTurnState, in session: ClaudeCodeSession) -> String? {
            hookEvents.preview(forSession: session.sessionID, inTurn: turn.turnID)
                ?? turn.promptPreview
        }

        var rows: [MonitoredSession] = []
        // Each row's last moment, keyed the way the rows are. Only a finished
        // row uses it, and for that row it is the instant the Turn ended -- the
        // event that ended it, or the reading that found the session no longer
        // working. That is the left-hand side of "has this been read": a focus
        // recorded before it cannot have shown the user this answer.
        var boundaryByRowID: [String: Date] = [:]
        /// Each row's Turn ending on its own, with no subagent folded in.
        ///
        /// **This is the left-hand side of every "has this been read" test**,
        /// and the map beside it is only the settling window's origin. Reading
        /// is something a person does to a Turn's answer, and the answer landed
        /// here -- so a focus stamp, a return to the foreground or a terminal
        /// gesture is evidence if it came after *this*, whatever a subagent
        /// went on doing afterwards. The two are the same instant for every row
        /// without a subagent, which is nearly all of them.
        var turnEndByRowID: [String: Date] = [:]
        for turn in hookState.turns {
            // A turn whose session is gone is gone. This is the whole reason
            // the session list is load-bearing rather than a convenience.
            guard let session = liveByID[turn.threadID] else { continue }
            let built = row(
                for: turn,
                in: session,
                title: await title(for: session),
                preview: preview(for: turn, in: session)
            )
            // The later of the turn's own last event and the last subagent
            // boundary. For every row without a subagent they are the same
            // instant; for one with a subagent still working, the turn's `Stop`
            // may be minutes old by the time the thread actually stops working,
            // and a settling window measured from it would be long spent -- the
            // row would go the moment it stopped saying anything was running.
            boundaryByRowID[built.id] = turn.terminalBoundaryAt
            turnEndByRowID[built.id] = turn.turnEndedAt
            rows.append(built)
        }

        // A session the reducer has never heard of contributes no row --
        // whether it was already running when this app started, or its hooks
        // were registered after it began. The transcript can name the turn such
        // a session is part-way through, and for a while the product read it;
        // that reconstruction was removed rather than extended.
        //
        // Nothing is written to the transcript while a turn waits on the user,
        // so a reconstructed row could only ever be Running -- and a session
        // that was in fact sitting on a permission prompt when this app
        // launched was therefore shown as working, which is the one answer the
        // product exists to get right. The alternative was to guess between
        // waiting and working, which §6.2 forbids outright. So "anything from
        // before launch is invisible" is now one sentence covering both
        // products, rather than a capability one of them happens to have.

        rows.sort(by: MonitorAggregation.rowOrder)
        let read = await rowsStillWorthShowing(
            rows,
            boundaryByRowID: boundaryByRowID,
            turnEndByRowID: turnEndByRowID,
            // Which process each row belongs to, from the same list that
            // proved the session exists. It is the only way to reach a
            // terminal session's read state: the answer is a property of the
            // device that process is attached to, and nothing in the row
            // carries it.
            processIdentifierByThreadID: liveByID.mapValues(\.processIdentifier),
            // And which of them the user has already taken off the list, so
            // none of the reading below is spent on one.
            dismissedRowIDs: dismissedRowIDs
        )
        let visibleRows = read.rows

        // Watch every listed session's record -- not only the ones with a Turn
        // in flight.
        //
        // It used to be only those, on the argument that a session sitting at
        // its prompt needs no edge because "the turn it starts next announces
        // itself with a hook, and its record flips `busy` in the same moment,
        // which would have bought a launch for an answer already on its way".
        // That argument holds only while the hook and the list agree on what
        // the session is called, and the record of an idle session is where
        // they stop agreeing: `/clear` rotates the session id in place, so the
        // list goes on naming the id the session had before while every hook
        // from then on carries the new one. The idle record is not the one
        // edge that could be spared, it is the one edge that reports the
        // rename -- and the app was blind to it for the whole freshness
        // window, which is up to thirty seconds of a turn drawing no row at
        // all.
        //
        // The cost of an edge is still one `claude agents --json`, and it is
        // small because these files are quiet. Measured here 2026-08-21, one
        // sample a second for ninety seconds across six live sessions -- two
        // of them interactive and sitting at their prompt: **not one record was
        // rewritten**. A record is written when a session flips `busy`,
        // `waiting` or `idle`, several times a turn, and the registry's
        // ``edgeFloor`` caps a burst of those at one reading every two seconds
        // whatever their source.
        //
        // Taken from `live` rather than from `rows`, which also settles what
        // the old comment had to argue around: a row withheld for presence is
        // a Turn this app still holds and still has to be able to end, and its
        // session is listed either way.
        recordWatcher.watch(processIdentifiers: Set(live.map(\.processIdentifier)))

        // Claude Desktop's log, and only while its answer is what this app is
        // waiting for. Recomputed from the state the calls above left, so a
        // wait they just closed unwatches it in the same refresh.
        //
        // Held to sessions that report no status of their own, which is the
        // only place this evidence is needed: a terminal-hosted session's
        // `waiting` to `busy` flip already arrives on the record edge, and it
        // is the reading this app trusts first.
        let awaitsADesktopAnswer = hookState.turns.contains { turn in
            guard turn.pendingApproval != nil || turn.subagentsAwaitingApproval,
                  let session = liveByID[turn.threadID] else {
                return false
            }
            return session.activity == nil
        }
        permissionLogWatcher.watch(paths: awaitsADesktopAnswer ? [permissionLogURL] : [])

        // And the transcripts of exactly the turns the reading above cannot
        // see stop -- the ones whose session reports nothing. Watched from
        // `rows` for the same reason: a row withheld for presence is still a
        // turn this app is holding.
        //
        // A session that answers for itself is not watched here at all, even
        // while its turn runs: its record already reports the flip, and the
        // reading behind it is the one this app trusts first.
        var watchedTranscripts: Set<URL> = []
        for row in rows where row.status.keepsTiming {
            guard let session = liveByID[row.threadID],
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

        // **The card may not say Connected while the mark is absent.**
        //
        // Registration used to be the whole of what this product reported, so
        // `Connected · hooks installed` was said on a machine where nothing was
        // being watched at all -- the notch drew no Claude Code mark, no row
        // ever appeared, and the one surface with room to explain that agreed
        // with none of it. `unknown` is the registry saying it has no reading
        // to offer, which is `AGENTS.md` §6.7's plain sense of the word: there
        // is no working connection to report on. `closed` is not the same
        // sentence and must not be caught by it -- that is `claude` answering
        // that nothing is open, which is a healthy machine with no session
        // running.
        //
        // Only the availability moves. Rows and presence are decided exactly
        // as before, and the mark this now agrees with was already absent.
        let watchFailure = presence == .unknown ? unwatchableReason() : nil

        return snapshot(
            availability: watchFailure == nil ? .ready : .disconnected,
            // A product that is not connected contributes no rows.
            //
            // The registry is written against exactly this: it goes on handing
            // back its last list when a read fails, because a failed read is
            // not evidence a session ended, and it says so on the understanding
            // that "the surface retires them by going Disconnected". The
            // surface did not. ``MonitorAggregation/status(agents:sessions:)``
            // reads the rows before it reads presence, so a product whose mark
            // had already gone -- presence `unknown`, no matrix drawn -- still
            // had its row on screen saying `Running`. That is the state the
            // user sees as Claude Code vanishing while it carries on working,
            // and it is the surface's half of the contract, not the registry's.
            sessions: presence.isOpen ? visibleRows : [],
            setupStatus: status,
            diagnostic: MonitorDiagnostics.combined(
                watchFailure,
                hookDiagnostic,
                read.diagnostic,
                // Last, because it is the least urgent of the four: the rows
                // are all still there and working, and what is missing is the
                // footer's two rules. It is here at all because nothing else
                // reports it -- a signed-out CLI draws `--` and says nothing.
                await usage.quotaDiagnostic()
            ),
            // Whatever is known right now. Awaiting the reading here is what
            // made a hook event's row wait on a `claude` launch.
            quota: await usage.currentQuota(),
            // Not `rows.isEmpty`: a session with no turn in flight is still an
            // open Claude Code. The list answers which sessions exist and the
            // reducer answers what they are doing — presence draws the matrix,
            // the reducer lights it, and merging the two would put the mark
            // back to reporting turns instead of openness.
            presence: presence
        )
    }

    /// Drops the finished rows the user has already read.
    ///
    /// Which rows are judged, and how the gate is booked, is
    /// ``TerminalUnreadRowFilter``'s; whether each has been read is
    /// ``ClaudeCodeReadEvidence``'s five routes. Nothing is read unless a
    /// finished row the user has not removed is listed (CR-Fable-041,
    /// CR-Fable-003), and the membership that evidence keeps across refreshes
    /// goes with such a list.
    private func rowsStillWorthShowing(
        _ rows: [MonitoredSession],
        boundaryByRowID: [String: Date],
        turnEndByRowID: [String: Date],
        processIdentifierByThreadID: [String: Int32],
        dismissedRowIDs: Set<String>
    ) async -> (rows: [MonitoredSession], diagnostic: String?) {
        let candidates = rows.map { row in
            // Every row carries one: rows come only from the reducer, and
            // the reducer stamps every turn with its last event. The fallback
            // is a fail-closed default rather than a case -- an unknown
            // boundary is read as "ended just now", so nothing can be judged
            // already read on a boundary nobody supplied.
            let boundary = boundaryByRowID[row.id] ?? clock.now()
            return ReadGateCandidate(
                row: row,
                // What every read test below is dated against. The same
                // fail-closed default as `boundary`, and the same instant as
                // it on every row with no subagent that outlived its Turn.
                turnEndedAt: turnEndByRowID[row.id] ?? boundary,
                terminalBoundaryAt: boundary
            )
        }
        let now = clock.now()
        guard TerminalUnreadRowFilter.needsReadEvidence(
            rows,
            dismissedRowIDs: dismissedRowIDs
        ) else {
            await readEvidence.forget()
            return (
                terminalReadMembershipGate.rows(
                    candidates,
                    dismissedRowIDs: dismissedRowIDs,
                    now: now,
                    verdict: { _ in .cannotBeAsked }
                ),
                nil
            )
        }
        // Which process each row belongs to, from the same list that proved
        // the session exists. It is the only way to reach a terminal session's
        // read state: the answer is a property of the device that process is
        // attached to, and nothing in the row carries it.
        await listedProcesses.hold(processIdentifierByThreadID)
        let judgement = await readEvidence.verdicts(
            for: candidates.filter { !dismissedRowIDs.contains($0.row.id) },
            now: now
        )
        let shown = terminalReadMembershipGate.rows(
            candidates,
            dismissedRowIDs: dismissedRowIDs,
            now: now
        ) { judgement.verdicts[$0.row.id] ?? .cannotBeAsked }
        return (shown, judgement.diagnostic)
    }

    /// No cadence for the rows: turn changes and session changes both arrive as
    /// edges on ``stateChangeEvents``, and reporting a deadline this refresh
    /// could not advance would be a busy-wait wearing a deadline's clothes.
    ///
    /// The quota is the one thing here that changes on the clock rather than on
    /// an edge, so it reports when it wants reading again -- a cache going
    /// stale is exactly what a deadline is for, and each refresh moves it. Left
    /// at nil, the reading was paced by unrelated hook traffic and the
    /// 60-second heartbeat: a failed attempt, which happens whenever something
    /// else logs onto the command's stdout, went uncorrected for up to two
    /// minutes.
    ///
    /// The second one is a finished, Desktop-hosted row waiting to be read. It
    /// waits on the user rather than on time, so its deadline is a floor under
    /// the account-folder watcher and not a sampling cadence -- the same
    /// reasoning, and the same numbers, as
    /// ``TerminalUnreadMembershipGate/nextDeadline(now:screenIsAvailable:)``
    /// on the Codex side. A row nothing can ever clear never reaches the gate,
    /// so it never books one of these -- and neither does one waiting on a user
    /// who has no screen to read it on.
    ///
    /// Two of the routes to "read" do turn that floor into a sampling cadence,
    /// and only for as long as a row is standing. `isInFrontOfThem` reads three
    /// states that have to agree, so it can only be asked at a re-check; a
    /// terminal session's last gesture is a device timestamp the kernel moves
    /// with nothing to watch it, so it can only be asked at one either. Both
    /// still cost nothing when nothing is listed, and both are bounded by the
    /// same second.
    func nextRefreshDeadline() async -> Date? {
        [
            await usage.nextReadDeadline(),
            terminalReadMembershipGate.nextDeadline(
                now: clock.now(),
                screenIsAvailable: screenAvailability.isAvailable()
            )
        ]
        .compactMap { $0 }
        .min()
    }

    /// The transcripts the quota readings leave in Claude Code's own project
    /// folder. Reported so the user can see them grow and clear them if they
    /// want to; never cleared here.
    ///
    /// Answers from the first refresh, before there is anything to count: this
    /// product always leaves transcripts, so the row is never in doubt even
    /// while the figure in it is.
    func diskFootprint() async -> AgentDiskFootprintReport {
        await usage.transcriptFootprint()
    }

    /// One answer, on the connection its request is still being held on.
    ///
    /// A pass-through, and deliberately nothing more: which bytes a product
    /// will act on is its vocabulary's business (``RequestAnswering``), and
    /// which connection they go down is the registry's. This is the boundary
    /// the store reaches both through.
    func answer(_ answer: AgentAnswer, on handle: AnswerHandle) async -> Bool {
        await hooks.answer(answer, on: handle)
    }

    func setupStatus() async -> IntegrationSetupStatus {
        await hooks.setupStatus()
    }


    /// Writes this build's definitions into `~/.claude/settings.json`.
    ///
    /// A copy of that file as it was goes beside it first — see
    /// ``ManagedHooksFileEditor`` and ADR 0016. Nothing here is Claude Code
    /// specific: the switch in Settings is the same switch Codex has, and it
    /// converges through the same path in ``MonitorStore``.
    func installIntegration() async throws {
        try await hooks.install()
    }

    func removeIntegration() async throws {
        try await hooks.remove()
    }

    func disconnect() async {
        hooks.disconnect()
    }

    /// The process running a session, for navigation.
    ///
    /// The same list the rows come from, asked again at click time. A session
    /// that has ended is no longer in it, so the click fails and the store
    /// corrects the set -- which is the re-confirmation the PRD asks for before
    /// a click, done against the product's own answer rather than against a pid
    /// this app wrote down when the row was drawn.
    func processIdentifier(forThreadID threadID: String) async -> Int32? {
        await sessions.liveSessions()
            .first { $0.sessionID == threadID }?
            .processIdentifier
    }

    // MARK: - Internals

    /// The sessions-directory edge, with the session list told before anyone is
    /// woken by it.
    ///
    /// The order is the entire point, and getting it wrong is what the bug was.
    /// The edge already woke a refresh; what it did not do was tell the list,
    /// so the refresh it caused asked a cache that was up to a ``freshness``
    /// old and got back the answer from before the session existed. Telling the
    /// registry inside the forwarder -- before the yield the consumer is
    /// waiting on -- means the refresh this edge causes is the one that re-reads.
    ///
    /// A yield still happens when the list refuses to re-read that soon: the
    /// edge is also how a row whose session died gets retired, and the
    /// consumer's own reasons for refreshing are none of this function's
    /// business.
    ///
    /// - Parameter directory: The sessions directory, when this edge is the
    ///   directory's own. Given, the forwarder skips ``invalidate()`` for the
    ///   one change that cannot mean anything: the appearance or removal of a
    ///   record belonging to a `claude` **this app launched itself**. The quota
    ///   reading is such a session, so every reading used to buy a `claude
    ///   agents --json` -- a Node launch -- to be re-told about a session the
    ///   registry filters out anyway. See ``ClaudeCommand/ownsSessionRecord(named:)``.
    ///
    ///   Narrow on purpose, and in the safe direction on every other input: an
    ///   edge that changes no name at all, one that changes a name this app
    ///   cannot claim, or a directory that cannot be listed all invalidate
    ///   exactly as before. Only "every name that moved is one of ours" is
    ///   quiet. Nil for the record-file edge, which watches sessions this app
    ///   is drawing rows for and can therefore never be looking at its own.
    nonisolated private static func sessionsChanged(
        _ events: AsyncStream<Void>,
        invalidating sessions: any ClaudeCodeSessionListing,
        in directory: URL? = nil,
        ownedBy isOwnRecord: @escaping @Sendable (String) -> Bool =
            ClaudeCommand.ownsSessionRecord(named:)
    ) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let forwarder = Task {
                var known = directory.map(Self.entryNames(of:)) ?? []
                for await _ in events {
                    var isOursAlone = false
                    if let directory {
                        let current = Self.entryNames(of: directory)
                        let moved = current.symmetricDifference(known)
                        known = current
                        isOursAlone = !moved.isEmpty && moved.allSatisfy(isOwnRecord)
                    }
                    if !isOursAlone {
                        await sessions.invalidate()
                    }
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in forwarder.cancel() }
        }
    }

    /// The names in a directory, and nothing else about it.
    ///
    /// Names, deliberately: a session record's *contents* are a private schema
    /// this app does not read, and the rule that the directory is a change
    /// signal rather than a source of truth still holds -- what sessions exist
    /// still comes only from `claude agents --json`. A name is used here for
    /// one question and it is a question about this app: "did the thing that
    /// moved belong to a process I started?"
    nonisolated private static func entryNames(of directory: URL) -> Set<String> {
        let names = try? FileManager.default.contentsOfDirectory(
            atPath: directory.path
        )
        return Set(names ?? [])
    }

    private func row(
        for turn: HookTurnState,
        in session: ClaudeCodeSession,
        title: String?,
        preview: String?
    ) -> MonitoredSession {
        // Project is the working directory (ADR 0009). The ban on deriving a
        // Project from a path binds Codex only: there a path is an approximation
        // of a grouping the user made, here the directory *is* the grouping --
        // it is what Claude Code itself files transcripts by.
        MonitoredSession(
            agent: .claudeCode,
            threadID: turn.threadID,
            turnID: turn.turnID,
            projectName: projectName(for: session),
            // `Untitled` is the contract's answer for a title that cannot be
            // obtained, and the folder name is never allowed to stand in for
            // one.
            title: title ?? "Untitled",
            // The beginning of the newest message *this turn* printed, and the
            // prompt it started from until it has printed one. The first half
            // reads the same in every state: when a turn stops it is exactly
            // the PRD's "beginning of the final answer", and while it runs it
            // is the opening of whatever it last said — a weaker reading of
            // "latest progress" than Codex's and the deliberate trade, since a
            // rolling tail would track a long answer more closely but would
            // stop being the beginning of it at the moment the turn ends.
            // Messages between tool calls are mostly shorter than the cap, so
            // the two readings usually coincide. A wait shows the words that
            // led up to the question — never the question's own tool arguments,
            // the command being approved, or a path.
            //
            // The second half is the same fallback Codex's `Running` row has
            // always had, and this product went without it: the store is keyed
            // by session, so a turn that had not spoken yet drew either nothing
            // at all (a session's first turn, or the first after this app
            // started listening) or the previous turn's closing words — the row
            // describing finished work as the work in hand. Both are answered
            // by asking the store for *this* turn's text and falling back to
            // what the user just typed.
            preview: preview,
            status: turn.status,
            startedAt: turn.startedAt,
            // What the row says once its own turn has stopped and the thread
            // has not. An `Agent` call returns as soon as the subagent is
            // launched, so a turn can reach `Stop` with work it started still
            // in flight -- measured 2026-08-23 against CLI 2.1.241, with the
            // parent's `Stop` naming that subagent in `background_tasks` and
            // its `SubagentStop` arriving afterwards.
            runningSubagentCount: turn.runningSubagentIDs.count,
            // No routing to subtract here: this product has no equivalent of
            // Codex's automatic reviewer on the path a hook can see, so a
            // `PermissionRequest` that opened over one of this thread's
            // subagents is a person being asked.
            subagentsAwaitingApprovalCount: turn.subagentsAwaitingApprovalCount,
            // What the row says between its subagent stopping and the turn
            // Claude Code opens next. The `Stop` that finished this turn said
            // which of the two terminals it was, and a turn that stopped in
            // order to wait is not a thread that has finished.
            isPausedForBackgroundWork: turn.pausedForBackgroundWork,
            // How long the turn took, for the row that draws it once the clock
            // has stopped. `lastEventAt` is the turn's own last moment and is
            // held there against a subagent's chatter, which is what makes it
            // an end rather than a moving target on the rows this product can
            // leave working after their turn.
            finishedAt: turn.status == .completed ? turn.lastEventAt : nil,
            // No reviewer to subtract on this side: Claude Code has nothing
            // like Codex's `auto_review`, so a wait this reducer holds is a
            // person being asked, full stop.
            request: turn.requestAwaitingAnAnswer
        )
    }

    /// Project is the working directory (ADR 0009). The ban on deriving a
    /// Project from a path binds Codex only: there a path approximates a
    /// grouping the user made, here the directory *is* the grouping -- it is
    /// what Claude Code itself files transcripts by.
    private func projectName(for session: ClaudeCodeSession) -> String {
        let component = session.workingDirectory.lastPathComponent
        return component.isEmpty ? "Untitled folder" : component
    }

    /// Why this app has no reading of Claude Code's sessions, in words a user
    /// can act on.
    ///
    /// Asked only where presence is already `unknown`, and never re-asking it:
    /// presence is read once per refresh so the rows and the mark describe one
    /// instant, and a second reading here could land the other side of one.
    ///
    /// **Two failures reach that one word, and they ask opposite things of the
    /// person reading it.** One is that there is no `claude` on the machine to
    /// run at all -- the ordinary shape of which was a user with Claude Desktop
    /// who never installed the terminal command, invisible until
    /// ``ClaudeExecutableLocator`` learned to fall back to Desktop's own copy,
    /// so reaching this now means neither exists. The other is a `claude` that
    /// is there and will not answer, which is where a command wedged behind an
    /// MCP server lands; telling that user to install what they already have
    /// would send them the wrong way entirely.
    ///
    /// It is a sentence and not a state. Nothing branches on which of the two
    /// it is -- the availability is `.disconnected` either way -- and the card
    /// draws this underneath a headline that claims neither.
    private func unwatchableReason() -> String? {
        if commandIsInstalled() {
            return "Claude Code is registered, but `claude agents --json` is "
                + "not answering, so this app cannot see which sessions are "
                + "open. It is the command Claude Code itself provides; try "
                + "running it in a terminal to see what it says."
        }
        return "Claude Code is registered, but no `claude` command could be "
            + "found to ask which sessions are open — not in ~/.local/bin, "
            + "Homebrew, /usr/local/bin, this app's PATH, or Claude Desktop's "
            + "own copy. Install Claude Code, or set NOTCHLINE_CLAUDE_PATH to "
            + "where it lives."
    }

    /// - Parameter presence: Defaults to `unknown` because the branches that do
    ///   not reach the session list genuinely did not look. Asking would mean
    ///   spawning `claude` on every refresh for a user who has not registered
    ///   the hooks — the exact work the early return exists to skip — and it
    ///   would change nothing: those branches are not `ready`, so the product
    ///   is not connected whatever its presence turns out to be.
    private func snapshot(
        availability: MonitorAvailability,
        sessions: [MonitoredSession],
        setupStatus: IntegrationSetupStatus,
        diagnostic: String?,
        quota: QuotaSnapshot = .unavailable,
        presence: AgentPresence = .unknown
    ) -> AgentSnapshot {
        AgentSnapshot(
            agent: .claudeCode,
            availability: availability,
            sessions: sessions,
            quota: quota,
            diagnostic: diagnostic,
            setupStatus: setupStatus,
            presence: presence
        )
    }
}
