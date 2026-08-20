import Foundation

/// Why an integration cannot be switched on from inside the app.
enum AgentSetupError: LocalizedError, Equatable {
    /// This product's registration is made by the user, by hand.
    case manualRegistrationRequired(AgentKind)

    var errorDescription: String? {
        switch self {
        case let .manualRegistrationRequired(agent):
            "\(agent.displayName) 的 Hook 注册需要你自己写入设置文件；"
                + "本应用只显示要粘贴的内容，不修改该文件。"
        }
    }
}

/// Watches Claude Code, and is one of the products the notch summarises.
///
/// Deliberately much smaller than the Codex service. Two of the things that one
/// has to do are simply absent here: there is no app-server subprocess to run
/// and keep alive, because session identity comes from a documented command;
/// and there is no helper script to install and upgrade, because the product
/// posts to this app directly.
///
/// What replaces the two is one thing the Codex side never has to think about:
/// this product's registration belongs to the user. The app reads it, reports
/// on it, and cannot repair it — see ADR 0010.
///
/// The startup boundary, though, is the same on both sides: nothing that
/// happened before this app launched is ever shown. Claude Code's transcript
/// can name a turn already in flight and this service used to read it, which
/// was the one place the two products genuinely differed in what they could
/// know. It was removed. A turn waiting on the user writes nothing at all, so
/// the reconstruction could only ever say Running -- a session parked on a
/// permission prompt when the app started was drawn as working, and telling a
/// wait from work is precisely what the product is for.
actor ClaudeCodeMonitorService: AgentMonitoring {
    nonisolated let agent = AgentKind.claudeCode
    nonisolated let stateChangeEvents: AsyncStream<Void>

    /// Claude Desktop's bundle identifier, used only to recognise the
    /// application in the workspace's activation notification. It is not
    /// promised by any official contract -- see the registry.
    nonisolated static let desktopBundleIdentifier = "com.anthropic.claudefordesktop"

    private let setup: ClaudeCodeHookSetup
    private let hookEvents: HookEventRepository
    private let sessions: any ClaudeCodeSessionListing
    private let listener: AgentHookListener
    private let transcripts: ClaudeCodeTranscriptReader
    private let usage: ClaudeCodeUsageReader
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
    /// Which sessions the user has already read, when anything can say.
    private let readState: any ClaudeCodeReadStateProviding
    /// When Claude Desktop last came to the front.
    ///
    /// The second of the two routes to "read", and the one that covers the
    /// ordinary way people use this product: you leave a session running, go
    /// somewhere else, and come back to the same session. Claude Desktop stamps
    /// a focus when it *puts* a session on screen and writes nothing at all
    /// when its window regains focus over a session already there -- measured
    /// 2026-08-19 across the whole application-support tree, zero files touched
    /// -- so the file alone can never see that reading happen.
    private let activations: any DesktopActivationReporting
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
    /// When the user was last at a session's own terminal.
    ///
    /// The answer for the half of this product Claude Desktop cannot speak for
    /// at all. It is not the same claim as any of the three above — nothing
    /// here says which tab is on screen, which is the question a terminal
    /// cannot answer and this app does not ask. It says that *this* session's
    /// terminal handed it something, which no other tab, window or application
    /// can cause: a key, or that surface gaining or losing the front. See
    /// ``ControllingTerminalGestureReporting``.
    private let terminalGestures: any ControllingTerminalGestureReporting
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
    /// Keeps a finished row listed until it has been read, and retires it the
    /// moment it has been.
    ///
    /// The same gate the Codex side uses, given the same shape of answer: this
    /// product's evidence is a focus instant rather than a blue dot, so the
    /// unread set handed over is computed per refresh from those instants and
    /// each Turn's own last moment -- see
    /// ``ClaudeCodeReadStateSnapshot/readState(forSession:terminalBoundaryAt:)``.
    private var terminalReadMembershipGate: TerminalUnreadMembershipGate
    private let clock: any MonitorClock
    private var boundPort: UInt16?
    private var lastDiagnostic: String?

    init(
        paths: HookIntegrationPaths = .liveClaudeCode(),
        setup: ClaudeCodeHookSetup? = nil,
        hookEvents: HookEventRepository? = nil,
        sessions: (any ClaudeCodeSessionListing)? = nil,
        listener: AgentHookListener? = nil,
        transcripts: ClaudeCodeTranscriptReader? = nil,
        usage: ClaudeCodeUsageReader? = nil,
        readState: (any ClaudeCodeReadStateProviding)? = nil,
        activations: (any DesktopActivationReporting)? = nil,
        reading: (any DesktopReadingReporting)? = nil,
        terminalGestures: (any ControllingTerminalGestureReporting)? = nil,
        sessionsDirectory: URL? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard
    ) {
        let resolvedSetup = setup ?? ClaudeCodeHookSetup(paths: paths)
        self.setup = resolvedSetup
        let repository = hookEvents ?? HookEventRepository(
            paths: paths,
            clock: clock,
            timing: timing,
            vocabulary: ClaudeCodeHookVocabulary()
        )
        self.hookEvents = repository
        // The one folder this app's own quota reading runs in, named once and
        // given to everything that has to be able to tell that reading apart
        // from a session the user started. It reaches the app by two routes and
        // both of them need it: the reading is listed by `claude agents --json`
        // like any other session, and it is a session that could fire hooks.
        // Before this the directory was only ever spelled out where the reading
        // was pinned to it -- the listener was handed nothing, and the registry
        // had no notion that such a session existed.
        let quotaDirectory = paths.quotaWorkingDirectory
        let resolvedSessions = sessions ?? ClaudeCodeSessionRegistry(
            clock: clock,
            ignoringWorkingDirectory: quotaDirectory
        )
        self.sessions = resolvedSessions
        // A row's third line arriving where there was none. Assistant deltas
        // are kept off this stream on purpose -- see ``AgentHookListener`` --
        // but a session that has *nothing* to show is not a stale row waiting
        // for a tidier moment, and the moments that would otherwise carry it
        // belong to the session rather than to this app: a turn that talks for
        // a minute between tool calls fires nothing at all. Without this, text
        // collected after the user turned content previews back on sat unread
        // until some unrelated edge or the 60-second heartbeat.
        let (previewsAppeared, previewLanded) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        // The token is not supplied here: it lives in the user's settings, and
        // the listener is told it when it binds.
        let resolvedListener = listener ?? AgentHookListener(
            eventsDirectory: paths.eventsDirectory,
            ignoredWorkingDirectory: quotaDirectory,
            clock: clock
        )
        resolvedListener.setOnPreviewAppeared { previewLanded.yield() }
        self.listener = resolvedListener
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
        self.activations = resolvedActivations
        // No change stream of its own, deliberately. Waking a display and
        // unlocking a screen do have notifications, but the front, the lock and
        // the display are three states that have to agree, and a row waiting on
        // the user already books a re-check every
        // ``MonitorTiming/terminalUnreadRecheckInterval``. That second is the
        // cadence this reading is sampled at and the bound on how late the row
        // leaves; nothing listed means nothing sampled.
        self.reading = reading ?? DesktopReadingWatcher(
            bundleIdentifier: Self.desktopBundleIdentifier
        )
        // No change stream of its own either, and for a sharper reason than
        // the reading above: a device's access time moves in the kernel and
        // leaves nothing a file-system watcher can attach to. It is sampled at
        // the same re-check a row waiting on the user already books, so the
        // bound on how late such a row leaves is
        // ``MonitorTiming/terminalUnreadRecheckInterval`` -- one `sysctl` and
        // one `stat` per listed terminal row per second, and nothing at all
        // when no such row is listed.
        self.terminalGestures = terminalGestures ?? ControllingTerminalGestureReader()
        self.terminalReadMembershipGate = TerminalUnreadMembershipGate(
            settlingInterval: timing.terminalReadSettlingInterval,
            unreadRecheckInterval: timing.terminalUnreadRecheckInterval
        )

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
        let recordWatcher = ClaudeCodeSessionRecordWatcher(
            directory: watched,
            debounceInterval: timing.unreadStateDebounceInterval
        )
        self.recordWatcher = recordWatcher
        let transcriptWatcher = PathSetChangeWatcher(
            debounceInterval: timing.unreadStateDebounceInterval
        )
        self.transcriptWatcher = transcriptWatcher
        self.stateChangeEvents = DirectoryChangeWatcher.merged([
            repository.changeEvents(),
            Self.sessionsChanged(
                sessionsWatcher.events(),
                invalidating: resolvedSessions
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
            quotaUpdates,
            previewsAppeared
        ])
    }

    // MARK: - AgentMonitoring

    func fetchSnapshot(showsContentPreviews: Bool) async -> AgentSnapshot {
        let status = await setup.status()
        guard status == .active else {
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
            sessionsSeenOnScreenSinceTheirTurnEnded.removeAll()
            return snapshot(
                availability: .setupRequired,
                sessions: [],
                setupStatus: status,
                diagnostic: status == .repairRequired
                    ? "Claude Code 的 Hook 注册与本版本需要的不一致，请在设置里重新粘贴："
                        + "缺少的事件不会报错，只会永远不到达；"
                        + "形状过时的 handler（例如少了 `async`）会让会话等待本应用响应。"
                    : "Claude Code 集成尚未注册。"
            )
        }

        // `~/.claude/sessions` does not exist until Claude Code has run once,
        // so the attach made in `init` fails for a user who registered the
        // hooks first. Retried here, on work this refresh was doing anyway, for
        // the reason the Hook queue's watcher is: nothing else would ever ask
        // again, and one failed `open` per refresh is cheaper than a timer.
        sessionsWatcher.attachIfNeeded()

        // Bind whatever the user's settings name. Their file is the authority,
        // so a port that moved there moves here -- and a port this app cannot
        // take is reported rather than silently swapped, because nothing here
        // may edit their file to agree with it.
        guard let registration = await setup.installedRegistration(),
              await bindListenerIfNeeded(registration) else {
            recordWatcher.watch(processIdentifiers: [])
            transcriptWatcher.watch(paths: [])
            // Nothing is listed, so nothing is waiting to be read. Left alone,
            // the gate would go on reporting a re-check deadline for rows this
            // branch is not going to publish, and a session that was on screen
            // when the integration was switched off would still be holding a
            // claim to have been seen there when it comes back.
            terminalReadMembershipGate.reset()
            sessionsSeenOnScreenSinceTheirTurnEnded.removeAll()
            return snapshot(
                availability: .disconnected,
                sessions: [],
                setupStatus: status,
                diagnostic: "无法在设置文件指定的端口上监听；"
                    + "请改用其他端口，或结束占用它的程序。"
            )
        }

        let consumed = await hookEvents.consumeEvents()
        // Presence first, and once. It is asked before the list rather than
        // after it so both come from the same reading: asked afterwards, the
        // two calls could land either side of a refresh and describe different
        // instants.
        let presence = await sessions.presence()
        let live = await sessions.liveSessions()
        let liveByID = Dictionary(
            live.map { ($0.sessionID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

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
        // What draining the queue had to say about it survives whichever of
        // those calls ran, none of which knows anything about the files this
        // refresh read: a corrupt event is reported on the refresh that found
        // it, whether or not a turn also ended in the same one.
        let hookDiagnostic = consumed.diagnostic ?? hookState.diagnostic

        await transcripts.retain(sessionIDs: Set(liveByID.keys))
        // Text belonging to a session that has ended does not outlive the row
        // that showed it. Pruned against the same set as the titles.
        listener.retainPreviews(forSessions: Set(liveByID.keys))

        func title(for session: ClaudeCodeSession) async -> String? {
            // A title is content, so it is only read when previews are on.
            guard showsContentPreviews else { return nil }
            return await transcripts.title(
                forSession: session.sessionID,
                workingDirectory: session.workingDirectory
            )
        }

        /// What the session is currently saying, from `MessageDisplay`.
        ///
        /// Two switches, not one, and both are load-bearing. Collection is off
        /// at the listener when the setting is off, so nothing is held; this
        /// one is the render-time half, and it is what makes the setting take
        /// effect on the first refresh rather than on the next message.
        func preview(for session: ClaudeCodeSession) -> String? {
            guard showsContentPreviews else { return nil }
            return listener.preview(forSession: session.sessionID)
        }

        var rows: [MonitoredSession] = []
        // Each row's last moment, keyed the way the rows are. Only a finished
        // row uses it, and for that row it is the instant the Turn ended -- the
        // event that ended it, or the reading that found the session no longer
        // working. That is the left-hand side of "has this been read": a focus
        // recorded before it cannot have shown the user this answer.
        var boundaryByRowID: [String: Date] = [:]
        for turn in hookState.turns {
            // A turn whose session is gone is gone. This is the whole reason
            // the session list is load-bearing rather than a convenience.
            guard let session = liveByID[turn.threadID] else { continue }
            let built = row(
                for: turn,
                in: session,
                title: await title(for: session),
                preview: preview(for: session)
            )
            boundaryByRowID[built.id] = turn.lastEventAt
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
            // Which process each row belongs to, from the same list that
            // proved the session exists. It is the only way to reach a
            // terminal session's read state: the answer is a property of the
            // device that process is attached to, and nothing in the row
            // carries it.
            processIdentifierByThreadID: liveByID.mapValues(\.processIdentifier)
        )
        let visibleRows = read.rows

        // Watch the records of exactly the turns that are still going -- and
        // watch them from `rows` rather than from what is about to be reported,
        // because a row withheld for presence is a turn this app still holds
        // and still has to be able to end.
        //
        // The cost of an edge is one `claude agents --json`, so what is watched
        // matters. A session with no turn in flight is not watched at all: the
        // turn it starts next announces itself with a hook, and its record
        // flips `busy` in the same moment, which would have bought a launch for
        // an answer already on its way. What is left is the flip that nothing
        // else reports -- `busy` or `waiting` to `idle` with no `Stop` behind
        // it -- and the registry's own `edgeFloor` caps a burst of them.
        recordWatcher.watch(
            processIdentifiers: Set(
                rows
                    .filter { $0.status.keepsTiming }
                    .compactMap { liveByID[$0.threadID]?.processIdentifier }
            )
        )

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

        return snapshot(
            availability: .ready,
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
            diagnostic: hookDiagnostic ?? read.diagnostic,
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
    /// **Five routes to "read", answering five different ways of reading it.**
    /// The first is the file's own and lives in the provider: Claude Desktop
    /// put the session on screen after the Turn ended, or the user archived it.
    /// The other four are decided here, because each needs a fact the file
    /// does not hold, and a decision spanning sources belongs in the
    /// orchestrator (`AGENTS.md` §6.1):
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
    private func rowsStillWorthShowing(
        _ rows: [MonitoredSession],
        boundaryByRowID: [String: Date],
        processIdentifierByThreadID: [String: Int32]
    ) async -> (rows: [MonitoredSession], diagnostic: String?) {
        let readState = await readState.snapshot()
        let activatedAt = await activations.lastActivation()
        let desktopIsInFrontOfTheUser = await reading.isInFrontOfTheUser()
        var unreadThreadIDs: Set<String> = []
        /// A judged row, and whether the terminal reading is what decides it.
        ///
        /// The two sources carry different authority and one snapshot cannot
        /// hold both -- see where they are built below.
        var judged: [(
            row: MonitoredSession,
            boundary: Date,
            restsOnTerminal: Bool
        )] = []
        var shown: [MonitoredSession] = []

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
            guard sessionID == readState.mostRecentlyDisplayedSessionID,
                  let activatedAt else {
                return false
            }
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
            sessionID == readState.mostRecentlyDisplayedSessionID
                && desktopIsInFrontOfTheUser
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
        func movedOnFrom(_ sessionID: String) -> Bool {
            guard sessionsSeenOnScreenSinceTheirTurnEnded.contains(sessionID),
                  let displayed = readState.mostRecentlyDisplayedSessionID else {
                return false
            }
            return displayed != sessionID
        }

        /// When the user was last at this session's own terminal.
        ///
        /// Read once per row per refresh rather than lazily inside the switch,
        /// so a row's verdict and its gate entry come from one reading. Only a
        /// session with a controlling terminal answers at all.
        var lastGestureByThreadID: [String: Date] = [:]
        for row in rows {
            guard let pid = processIdentifierByThreadID[row.threadID],
                  let at = await terminalGestures
                    .lastUserGesture(forProcessIdentifier: pid) else {
                continue
            }
            lastGestureByThreadID[row.threadID] = at
        }

        /// Whether the user was at this session's own terminal after it
        /// finished.
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
        func wereAtItsTerminal(_ threadID: String, since boundary: Date) -> Bool {
            guard let at = lastGestureByThreadID[threadID] else { return false }
            return at >= boundary
        }

        for row in rows {
            // Every row carries one: rows come only from the reducer, and
            // the reducer stamps every turn with its last event. The fallback
            // is a fail-closed default rather than a case -- an unknown
            // boundary is read as "ended just now", so nothing can be judged
            // already read on a boundary nobody supplied.
            let boundary = boundaryByRowID[row.id] ?? clock.now()
            let state = readState.readState(
                forSession: row.threadID,
                terminalBoundaryAt: boundary
            )
            // Kept up to date here rather than anywhere else, because this is
            // the one place that knows both halves at once: which session
            // Claude Desktop has on screen, and whether this row's Turn is over.
            // A row that is running again drops its membership -- it belongs to
            // the finished Turn that was on screen, not to the session, and a
            // new Turn has to earn it again.
            if row.status == .completed,
               row.threadID == readState.mostRecentlyDisplayedSessionID {
                sessionsSeenOnScreenSinceTheirTurnEnded.insert(row.threadID)
            } else if row.status != .completed {
                sessionsSeenOnScreenSinceTheirTurnEnded.remove(row.threadID)
            }
            // Whether a reading that cannot be a generation behind is what
            // decides this row -- see where the two snapshots are built.
            let terminalCanSpeak = lastGestureByThreadID[row.threadID] != nil
            let terminalSaysRead = wereAtItsTerminal(row.threadID, since: boundary)
            switch state {
            case .unknown:
                // Claude Desktop cannot speak for this session, so only its
                // terminal can. A gesture *after* the Turn ended is what makes
                // it evidence of reading rather than of having been there at
                // some point — the same shape as every rule above.
                guard terminalCanSpeak else {
                    // Nothing anywhere can speak for it. Kept out of the gate
                    // entirely rather than reported unread, so it books no
                    // re-check for a question with no possible answer.
                    shown.append(row)
                    break
                }
                if !terminalSaysRead {
                    unreadThreadIDs.insert(row.threadID)
                }
                judged.append((row, boundary, true))
            case .unread:
                if comingBackShowedIt(row.threadID, since: boundary)
                    || isInFrontOfThem(row.threadID)
                    || movedOnFrom(row.threadID)
                    || terminalSaysRead {
                    judged.append((row, boundary, terminalSaysRead))
                } else {
                    unreadThreadIDs.insert(row.threadID)
                    judged.append((row, boundary, false))
                }
            case .read:
                judged.append((row, boundary, false))
            }
        }
        // A session nobody is listing any more takes its membership with it, so
        // a session that comes back cannot be retired on what it did last time.
        sessionsSeenOnScreenSinceTheirTurnEnded.formIntersection(
            Set(rows.map(\.threadID))
        )

        let desktopUnreadState = DesktopUnreadStateSnapshot(
            unreadThreadIDs: unreadThreadIDs,
            // A reading that is not current may not hide anything, exactly as
            // on the Codex side. It matters less here -- a focus instant older
            // than the Turn cannot claim the Turn was read, whatever generation
            // it came from -- but the rule is the product's, not the schema's.
            source: readState.source.isAuthoritative ? .current : .lastKnownGood
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
            source: .current
        )
        let now = clock.now()
        for (row, boundary, restsOnTerminal) in judged
        where terminalReadMembershipGate.shouldDisplay(
            sessionID: row.id,
            threadID: row.threadID,
            status: row.status,
            terminalBoundaryAt: boundary,
            unreadState: restsOnTerminal ? terminalUnreadState : desktopUnreadState,
            now: now
        ) {
            shown.append(row)
        }
        terminalReadMembershipGate.retain(sessionIDs: Set(judged.map(\.row.id)))

        // Sorted again: the two halves above are appended in the order they
        // were judged, not in row order.
        return (shown.sorted(by: MonitorAggregation.rowOrder), readState.diagnostic)
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
    /// ``TerminalUnreadMembershipGate/nextDeadline(now:)`` on the Codex side.
    /// A row nothing can ever clear never reaches the gate, so it never books
    /// one of these.
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
            terminalReadMembershipGate.nextDeadline(now: clock.now())
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

    func hookSetupStatus() async -> HookSetupStatus {
        await setup.status()
    }


    func manualSetup() async -> AgentManualSetup? {
        AgentManualSetup(
            agent: agent,
            settingsURL: setup.settingsURL,
            configurationSnippet: await setup.configurationSnippet()
        )
    }

    /// Registration is the user's to make, so this always refuses.
    ///
    /// Refusing loudly rather than doing nothing: a switch that silently
    /// achieves nothing is worse than one that explains why it is not a switch.
    func installHooks() async throws {
        throw AgentSetupError.manualRegistrationRequired(agent)
    }

    func removeHooks() async throws {
        throw AgentSetupError.manualRegistrationRequired(agent)
    }

    func clearSessions() async {
        await hookEvents.clearTurnsPreservingObservation()
    }

    /// Stops the listener retaining assistant text, and drops what it holds.
    ///
    /// This was an empty implementation for as long as this side collected
    /// nothing, and its emptiness was the privacy claim. Since CC-015 it is a
    /// real switch again: `MessageDisplay` is registered, so text does arrive,
    /// and "not received" has become "not retained while this is off". The
    /// weaker claim is the honest one, and it is the same one the Codex side
    /// has always made.
    ///
    /// Synchronous, `nonisolated`, and an in-memory flag, for the reasons on
    /// the protocol: a control routed through an unheld `Task` is reorderable
    /// and one routed to a file is failable — see CR-012.
    nonisolated func setContentPreviewsEnabled(_ isEnabled: Bool) {
        listener.setAcceptsText(isEnabled)
    }

    func discardCollectedPreviews() async {
        listener.discardPreviews()
    }

    func disconnect() async {
        listener.stop()
        boundPort = nil
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
    nonisolated private static func sessionsChanged(
        _ events: AsyncStream<Void>,
        invalidating sessions: any ClaudeCodeSessionListing
    ) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let forwarder = Task {
                for await _ in events {
                    await sessions.invalidate()
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in forwarder.cancel() }
        }
    }

    private func bindListenerIfNeeded(
        _ registration: ClaudeCodeHookRegistration
    ) async -> Bool {
        if boundPort == registration.port { return true }
        listener.stop()
        let bound = listener.start(
            preferredPort: registration.port,
            token: registration.token
        )
        // An ephemeral fallback is useless here: the user's settings name a
        // port, and nothing would ever post to a different one.
        guard bound == registration.port else {
            listener.stop()
            boundPort = nil
            return false
        }
        boundPort = bound
        return true
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
            // one. That is also what a row shows with previews off, since a
            // title is as much the user's content as a prompt is.
            title: title ?? "Untitled",
            privacySafeTitle: "Untitled",
            // The same text whatever the status, unlike Codex, which swaps
            // between the prompt and the answer. There is one source here and
            // it reads the same in every state: the beginning of the newest
            // message printed. When a turn stops, that is exactly the PRD's
            // "beginning of the final answer"; while it runs it is the opening
            // of whatever it last said, which is a weaker reading of "latest
            // progress" than Codex's and is the deliberate trade — a rolling
            // tail would track a long answer more closely but would stop being
            // the beginning of it at the moment the turn ends. Messages between
            // tool calls are mostly shorter than the cap, so the two readings
            // usually coincide. A wait shows the words that led up to the
            // question — never the question's own tool arguments, the command
            // being approved, or a path.
            preview: preview,
            status: turn.status,
            startedAt: turn.startedAt
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

    /// - Parameter presence: Defaults to `unknown` because the branches that do
    ///   not reach the session list genuinely did not look. Asking would mean
    ///   spawning `claude` on every refresh for a user who has not registered
    ///   the hooks — the exact work the early return exists to skip — and it
    ///   would change nothing: those branches are not `ready`, so the product
    ///   is not connected whatever its presence turns out to be.
    private func snapshot(
        availability: MonitorAvailability,
        sessions: [MonitoredSession],
        setupStatus: HookSetupStatus,
        diagnostic: String?,
        quota: QuotaSnapshot = .unavailable,
        presence: AgentPresence = .unknown
    ) -> AgentSnapshot {
        lastDiagnostic = diagnostic
        return AgentSnapshot(
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
