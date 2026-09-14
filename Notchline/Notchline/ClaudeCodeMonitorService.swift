import Foundation

/// Watches Claude Code by composing its sources into the shared ``HookProductProvider``
/// runtime (`tiered-support.md` §5.4).
///
/// - A Turn can reach `Stop` with a subagent still in flight (CLI 2.1.241, 2026-08-23).
/// - No reviewer is visible to hooks, so a held wait is a person being asked.
/// - Nothing from before launch is shown: a Turn waiting on the user writes nothing, so a
///   transcript reconstruction could only say Running.
nonisolated struct ClaudeCodeMonitorService: AgentMonitoring, IntegrationConfiguring,
    AnswerDelivering, DiskFootprintReporting, SessionProcessLocating {
    let agent = AgentKind.claudeCode

    /// Used only to recognise Claude Desktop's activation; not promised by any official contract.
    static let desktopBundleIdentifier = "com.anthropic.claudefordesktop"

    private let runtime: HookProductProvider
    private let sessionSource: ClaudeCodeSessionSource
    private let turnEvidence: ClaudeCodeTurnEvidence

    var stateChangeEvents: AsyncStream<Void> { runtime.stateChangeEvents }

    /// Exposed for tests; see ``ClaudeCodeSessionSource/recordWatcher``.
    var recordWatcher: ClaudeCodeSessionRecordWatcher { sessionSource.recordWatcher }

    /// See ``ClaudeCodeTurnEvidence/transcriptWatcher``.
    var transcriptWatcher: PathSetChangeWatcher { turnEvidence.transcriptWatcher }

    /// See ``ClaudeCodeTurnEvidence/permissionLogWatcher``.
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
        /// Which entries belong to a `claude` this app launched; injected for tests.
        ownsSessionRecord: (@Sendable (String) -> Bool)? = nil,
        /// Whether a `claude` executable exists; injected so tests ignore the developer's install.
        commandIsInstalled: (@Sendable () -> Bool)? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard
    ) {
        // The quota reading's own folder: `claude agents --json` lists that reading and it could
        // fire hooks, so everything that must tell it from a user session gets this.
        let quotaDirectory = paths.quotaWorkingDirectory
        // Resolved first: the session list and quota reading also skip work no screen can show.
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
        // Its own directory is all that separates this reading from user sessions (`kind:
        // "interactive"`). `-p "/usage"` fires no hooks (2.1.234, 2026-08-18); filtered anyway.
        let usage = usage ?? ClaudeCodeUsageReader(
            clock: clock,
            workingDirectory: quotaDirectory,
            screenIsAvailable: screen.isAvailable,
            tokens: ClaudeCodeTokenCounter(clock: clock),
            transcripts: ClaudeCodeUsageTranscripts(clock: clock)
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
            // No change stream: front, lock and display must agree, so it is sampled at the
            // ``MonitorTiming/terminalUnreadRecheckInterval`` re-check; the runtime merges the screen
            // coming back (CR-Fable-018).
            reading: reading ?? DesktopReadingWatcher(
                bundleIdentifier: Self.desktopBundleIdentifier
            ),
            // No change stream: the transition only this reader sees (leaving for a composer) can only
            // keep a row, and a listed row re-checks every second.
            displayed: displayed ?? ClaudeDesktopFocusLogReader(),
            // No change stream: a device's access time moves in the kernel with nothing to watch.
            // Sampled at the re-check: one `sysctl` and one `stat` per listed terminal row per second.
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
            timing: timing
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

    func answer(_ answer: AgentAnswer, on handle: AnswerHandle) async -> AnswerOutcome {
        await runtime.answer(answer, on: handle)
    }

    func setupStatus() async -> IntegrationSetupStatus {
        await runtime.setupStatus()
    }

    /// Writes this build's definitions into `~/.claude/settings.json`, backing the file up
    /// first (``ManagedHooksFileEditor``, ADR 0016).
    func installIntegration() async throws {
        try await runtime.installIntegration()
    }

    func removeIntegration() async throws {
        try await runtime.removeIntegration()
    }

    /// See ``ClaudeCodeTranscriptFootprint``.
    func diskFootprint() async -> AgentDiskFootprintReport {
        await runtime.diskFootprint()
    }

    /// The session's process, asked of the list again at click time.
    func processIdentifier(forThreadID threadID: String) async -> Int32? {
        await sessionSource.processIdentifier(forThreadID: threadID)
    }
}

/// The transcripts Claude Code's quota readings leave in its project folder; reported, never
/// cleared here. Answers from the first refresh, since this product always leaves some.
nonisolated struct ClaudeCodeTranscriptFootprint: DiskFootprintReporting {
    let usage: ClaudeCodeUsageReader

    func diskFootprint() async -> AgentDiskFootprintReport {
        await usage.transcriptFootprint()
    }
}
