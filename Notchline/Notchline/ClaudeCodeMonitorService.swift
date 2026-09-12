import Foundation

/// Watches Claude Code, and is one of the products the notch summarises.
///
/// **A composition, not an orchestrator of its own.** Until 2026-09-12 this was
/// an actor of some eighteen hundred lines running its own refresh; it is now
/// the place Claude Code's sources are made and handed to the runtime every
/// hook-based product shares (``HookProductProvider``, `tiered-support.md`
/// §5.4). Each source carries its measurements with it:
///
/// - ``ClaudeCodeSessionSource`` — the session list, read once per refresh, and
///   the two edges that keep it honest;
/// - ``ClaudeCodeTurnEvidence`` — interrupts and answered dialogs no hook
///   reports;
/// - ``ClaudeCodeRowContent`` — the working directory, the transcript's title,
///   and what the Turn has said;
/// - ``ClaudeCodeReadEvidence`` — the five routes to "read";
/// - ``ClaudeCodeUsageReader`` — the quota, and the transcripts its readings
///   leave.
///
/// The row itself is the runtime's, unchanged: a Turn can reach `Stop` with a
/// subagent still in flight (measured 2026-08-23 against CLI 2.1.241, the
/// parent's `Stop` naming it in `background_tasks` and its `SubagentStop`
/// arriving afterwards), and there is no reviewer to subtract on this side --
/// Claude Code has nothing like Codex's `auto_review` on the path a hook can
/// see, so a wait the reducer holds is a person being asked, full stop.
///
/// The startup boundary is the same as every product's: nothing that happened
/// before this app launched is ever shown. Claude Code's transcript can name a
/// turn already in flight and this product used to read it; that was removed,
/// because a turn waiting on the user writes nothing at all, so the
/// reconstruction could only ever say Running.
nonisolated struct ClaudeCodeMonitorService: AgentMonitoring, IntegrationConfiguring,
    AnswerDelivering, DiskFootprintReporting, SessionProcessLocating {
    let agent = AgentKind.claudeCode

    /// Claude Desktop's bundle identifier, used only to recognise the
    /// application in the workspace's activation notification. It is not
    /// promised by any official contract -- see the registry.
    static let desktopBundleIdentifier = "com.anthropic.claudefordesktop"

    private let runtime: HookProductProvider
    private let sessionSource: ClaudeCodeSessionSource
    private let turnEvidence: ClaudeCodeTurnEvidence

    var stateChangeEvents: AsyncStream<Void> { runtime.stateChangeEvents }

    /// The records of the listed sessions, watched by the session source.
    ///
    /// Exposed so a test can read how many records are being watched -- see
    /// ``ClaudeCodeSessionSource/recordWatcher``.
    var recordWatcher: ClaudeCodeSessionRecordWatcher { sessionSource.recordWatcher }

    /// The transcripts of the turns still going in a session that reports no
    /// status of its own -- see ``ClaudeCodeTurnEvidence/transcriptWatcher``.
    var transcriptWatcher: PathSetChangeWatcher { turnEvidence.transcriptWatcher }

    /// Claude Desktop's own log, while a dialog it raised is still open -- see
    /// ``ClaudeCodeTurnEvidence/permissionLogWatcher``.
    var permissionLogWatcher: PathSetChangeWatcher { turnEvidence.permissionLogWatcher }

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
        /// one — see ``ClaudeCodeSessionSource``.
        ownsSessionRecord: (@Sendable (String) -> Bool)? = nil,
        /// Whether a `claude` executable can be found at all. Injected for the
        /// reason the readers above are: left with the default, a test would
        /// answer with whatever the developer happens to have installed.
        commandIsInstalled: (@Sendable () -> Bool)? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard
    ) {
        // The one folder this app's own quota reading runs in, named once and
        // given to everything that has to be able to tell that reading apart
        // from a session the user started. It reaches the app by two routes and
        // both of them need it: the reading is listed by `claude agents --json`
        // like any other session, and it is a session that could fire hooks.
        let quotaDirectory = paths.quotaWorkingDirectory
        // Resolved first, because the session list and the quota reading take
        // it as well as the read gate: a `claude` launched for a figure nobody
        // can look at is the same waste as a re-check booked for a row nobody
        // can read.
        let screen = screenAvailability ?? ScreenAvailabilityWatcher()
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
        let sessionSource = ClaudeCodeSessionSource(
            listing: sessions ?? ClaudeCodeSessionRegistry(
                clock: clock,
                ignoringWorkingDirectory: quotaDirectory,
                screenIsAvailable: screen.isAvailable
            ),
            sessionsDirectory: sessionsDirectory,
            ownsSessionRecord: ownsSessionRecord,
            commandIsInstalled: commandIsInstalled,
            timing: timing
        )
        self.sessionSource = sessionSource
        let transcripts = transcripts ?? ClaudeCodeTranscriptReader()
        // The quota's own edge. Nothing waits for the reading, so the reading
        // has to say when it landed -- otherwise a figure read at second five
        // would not be drawn until whatever happened to refresh next.
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
        let usage = usage ?? ClaudeCodeUsageReader(
            clock: clock,
            workingDirectory: quotaDirectory,
            screenIsAvailable: screen.isAvailable,
            tokens: ClaudeCodeTokenCounter(clock: clock),
            transcripts: ClaudeCodeUsageTranscripts(clock: clock),
            onUpdate: { quotaLanded.yield() }
        )
        let readState = readState ?? ClaudeCodeDesktopReadStateRepository(
            changeDebounceInterval: timing.unreadStateDebounceInterval
        )
        let activations = activations ?? DesktopActivationWatcher(
            bundleIdentifier: Self.desktopBundleIdentifier,
            clock: clock
        )
        let turnEvidence = ClaudeCodeTurnEvidence(
            sessions: sessionSource,
            transcripts: transcripts,
            permissions: permissions
                ?? ClaudeDesktopPermissionLogReader(logURL: permissionLogURL),
            permissionLogURL: permissionLogURL,
            readState: readState,
            timing: timing
        )
        self.turnEvidence = turnEvidence
        let readEvidence = ClaudeCodeReadEvidence(
            sessions: sessionSource.listedProcesses,
            readState: readState,
            activations: activations,
            // No change stream of its own: the front, the lock and the display
            // are three states that have to agree, so a notification for any
            // one of them says nothing on its own, and the reading is sampled
            // at the re-check a row waiting on the user books every
            // ``MonitorTiming/terminalUnreadRecheckInterval``. The screen coming
            // back is the one edge that matters, and the runtime merges it
            // (CR-Fable-018).
            reading: reading ?? DesktopReadingWatcher(
                bundleIdentifier: Self.desktopBundleIdentifier
            ),
            // No change stream of its own either: the transition only this
            // reader can see -- a session leaving the screen for a composer --
            // can only ever *keep* a row, and a listed row books a re-check
            // every second anyway. Every transition that can retire one arrives
            // on an edge that already exists, because Desktop writes the record
            // of whatever it put on screen instead.
            displayed: displayed ?? ClaudeDesktopFocusLogReader(),
            // No change stream of its own either, and for a sharper reason: a
            // device's access time moves in the kernel and leaves nothing a
            // file-system watcher can attach to. It is sampled at the same
            // re-check, so the bound on how late such a row leaves is
            // ``MonitorTiming/terminalUnreadRecheckInterval`` -- one `sysctl`
            // and one `stat` per listed terminal row per second, and nothing at
            // all when no such row is listed.
            terminalGestures: terminalGestures ?? ControllingTerminalGestureReader(),
            screen: screen
        )
        runtime = HookProductProvider(
            agent: .claudeCode,
            hooks: hooks,
            sessions: sessionSource,
            turnEvidence: [turnEvidence],
            rowContent: ClaudeCodeRowContent(sessions: sessionSource, transcripts: transcripts),
            readEvidence: readEvidence,
            usage: usage,
            footprint: ClaudeCodeTranscriptFootprint(usage: usage),
            clock: clock,
            timing: timing,
            changeEvents: sessionSource.changeEvents + turnEvidence.changeEvents + [
                // Claude Desktop writing a session's record. It is the
                // low-latency half of retiring a finished row: the write that
                // stamps a focus is an atomic replace inside the account folder,
                // so this edge lands on the same gesture that reads the answer.
                // Nothing here invalidates the session list -- that file says
                // who has read what, not which sessions exist.
                readState.changeEvents(),
                // Claude Desktop coming to the front. It is an edge rather than
                // a deadline for the same reason the record write is: a row
                // waiting to be read should leave on the gesture that reads it,
                // not on the next re-check after it.
                activations.changeEvents(),
                quotaUpdates
            ]
        )
    }

    func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot {
        await runtime.fetchSnapshot(dismissedRowIDs: dismissedRowIDs)
    }

    func nextRefreshDeadline() async -> Date? {
        await runtime.nextRefreshDeadline()
    }

    func disconnect() async {
        await runtime.disconnect()
    }

    func answer(_ answer: AgentAnswer, on handle: AnswerHandle) async -> Bool {
        await runtime.answer(answer, on: handle)
    }

    func setupStatus() async -> IntegrationSetupStatus {
        await runtime.setupStatus()
    }

    /// Writes this build's definitions into `~/.claude/settings.json`, with a
    /// copy of that file as it was beside it first — see
    /// ``ManagedHooksFileEditor`` and ADR 0016.
    func installIntegration() async throws {
        try await runtime.installIntegration()
    }

    func removeIntegration() async throws {
        try await runtime.removeIntegration()
    }

    /// The transcripts the quota readings leave in Claude Code's own project
    /// folder -- see ``ClaudeCodeTranscriptFootprint``.
    func diskFootprint() async -> AgentDiskFootprintReport {
        await runtime.diskFootprint()
    }

    /// The process running a session, for navigation, asked of the list again
    /// at click time (``ClaudeCodeSessionSource/processIdentifier(forThreadID:)``).
    func processIdentifier(forThreadID threadID: String) async -> Int32? {
        await sessionSource.processIdentifier(forThreadID: threadID)
    }
}

/// The transcripts Claude Code's quota readings leave in its own project
/// folder. Reported so the user can see them grow and clear them if they want
/// to; never cleared here.
///
/// Answers from the first refresh, before there is anything to count: this
/// product always leaves transcripts, so the row is never in doubt even while
/// the figure in it is.
nonisolated struct ClaudeCodeTranscriptFootprint: DiskFootprintReporting {
    let usage: ClaudeCodeUsageReader

    func diskFootprint() async -> AgentDiskFootprintReport {
        await usage.transcriptFootprint()
    }
}
