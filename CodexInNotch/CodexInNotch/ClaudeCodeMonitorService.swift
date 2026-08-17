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
/// Deliberately much smaller than the Codex service. Three of the things that
/// one has to do are simply absent here: there is no app-server subprocess to
/// run and keep alive, because session identity comes from a documented command;
/// there is no helper script to install and upgrade, because the product posts
/// to this app directly; and there is no cold-start blindness to work around,
/// because Claude Code can be asked what exists right now.
///
/// What replaces them is one thing the Codex side never has to think about:
/// this product's registration belongs to the user. The app reads it, reports
/// on it, and cannot repair it — see ADR 0010.
actor ClaudeCodeMonitorService: AgentMonitoring {
    nonisolated let agent = AgentKind.claudeCode
    nonisolated let stateChangeEvents: AsyncStream<Void>

    private let setup: ClaudeCodeHookSetup
    private let hookEvents: HookEventRepository
    private let sessions: any ClaudeCodeSessionListing
    private let listener: AgentHookListener
    private let transcripts: ClaudeCodeTranscriptReader
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
        self.sessions = sessions ?? ClaudeCodeSessionRegistry(clock: clock)
        // The token is not supplied here: it lives in the user's settings, and
        // the listener is told it when it binds.
        self.listener = listener ?? AgentHookListener(
            eventsDirectory: paths.eventsDirectory,
            clock: clock
        )
        self.transcripts = transcripts ?? ClaudeCodeTranscriptReader()
        self.clock = clock

        // Two edges, no cadence. An event arriving means a turn moved; the
        // sessions directory changing means one appeared or went away, which is
        // the only way a row whose session died can be retired now that
        // SessionEnd is not registered.
        let watched = sessionsDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/sessions", isDirectory: true)
        self.stateChangeEvents = DirectoryChangeWatcher.merged([
            repository.changeEvents(),
            DirectoryChangeWatcher(
                directoryURL: watched,
                debounceInterval: timing.unreadStateDebounceInterval
            ).events()
        ])
    }

    // MARK: - AgentMonitoring

    func fetchSnapshot(showsContentPreviews: Bool) async -> AgentSnapshot {
        let status = await setup.status()
        guard status == .active else {
            return snapshot(
                availability: .setupRequired,
                sessions: [],
                setupStatus: status,
                diagnostic: status == .repairRequired
                    ? "Claude Code 的 Hook 注册不完整，缺少的事件不会报错，只会永远不到达。"
                    : "Claude Code 集成尚未注册。"
            )
        }

        // Bind whatever the user's settings name. Their file is the authority,
        // so a port that moved there moves here -- and a port this app cannot
        // take is reported rather than silently swapped, because nothing here
        // may edit their file to agree with it.
        guard let registration = await setup.installedRegistration(),
              await bindListenerIfNeeded(registration) else {
            return snapshot(
                availability: .disconnected,
                sessions: [],
                setupStatus: status,
                diagnostic: "无法在设置文件指定的端口上监听；"
                    + "请改用其他端口，或结束占用它的程序。"
            )
        }

        let hookState = await hookEvents.consumeEvents()
        let live = await sessions.liveSessions()
        let liveByID = Dictionary(
            live.map { ($0.sessionID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        await transcripts.retain(sessionIDs: Set(liveByID.keys))
        var rows: [MonitoredSession] = []
        for turn in hookState.turns {
            // A turn whose session is gone is gone. This is the whole reason
            // the session list is load-bearing rather than a convenience.
            guard let session = liveByID[turn.threadID] else { continue }
            // A title is content, so it is only read when previews are on.
            let title = showsContentPreviews
                ? await transcripts.title(
                    forSession: session.sessionID,
                    workingDirectory: session.workingDirectory
                )
                : nil
            rows.append(row(for: turn, in: session, title: title))
        }
        rows.sort(by: MonitorAggregation.rowOrder)

        return snapshot(
            availability: .ready,
            sessions: rows,
            setupStatus: status,
            diagnostic: hookState.diagnostic
        )
    }

    /// No cadence of its own. Turn changes and session changes both arrive as
    /// edges on ``stateChangeEvents``, and reporting a deadline this refresh
    /// could not advance would be a busy-wait wearing a deadline's clothes.
    func nextRefreshDeadline() async -> Date? { nil }

    func hookSetupStatus() async -> HookSetupStatus {
        await setup.status()
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

    /// Nothing to switch. The listener's decoder has no field for prompt or
    /// answer text, so this side never collects any -- the privacy control has
    /// nothing to turn off here, rather than something it turns off later.
    nonisolated func setContentPreviewsEnabled(_ isEnabled: Bool) {}

    func discardCollectedPreviews() async {
        // Nothing to discard: the listener's decoder has no field for prompt or
        // answer text, so none was ever received.
    }

    func disconnect() async {
        listener.stop()
        boundPort = nil
    }

    // MARK: - Internals

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
        title: String?
    ) -> MonitoredSession {
        // Project is the working directory (ADR 0009). The ban on deriving a
        // Project from a path binds Codex only: there a path is an approximation
        // of a grouping the user made, here the directory *is* the grouping --
        // it is what Claude Code itself files transcripts by.
        let project = session.workingDirectory.lastPathComponent
        return MonitoredSession(
            agent: .claudeCode,
            threadID: turn.threadID,
            turnID: turn.turnID,
            projectName: project.isEmpty ? "Untitled folder" : project,
            // `Untitled` is the contract's answer for a title that cannot be
            // obtained, and the folder name is never allowed to stand in for
            // one. That is also what a row shows with previews off, since a
            // title is as much the user's content as a prompt is.
            title: title ?? "Untitled",
            privacySafeTitle: "Untitled",
            preview: nil,
            status: turn.status,
            startedAt: turn.startedAt
        )
    }

    private func snapshot(
        availability: MonitorAvailability,
        sessions: [MonitoredSession],
        setupStatus: HookSetupStatus,
        diagnostic: String?
    ) -> AgentSnapshot {
        lastDiagnostic = diagnostic
        return AgentSnapshot(
            agent: .claudeCode,
            availability: availability,
            sessions: sessions,
            // Quota arrives with the /usage reading; unavailable is the honest
            // answer until then, and never a zero.
            quota: .unavailable,
            diagnostic: diagnostic,
            setupStatus: setupStatus
        )
    }
}
