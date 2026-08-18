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
    private let usage: ClaudeCodeUsageReader
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
        // The quota's own edge. Nothing waits for the reading any more, so the
        // reading has to say when it landed -- otherwise a figure read at
        // second five would not be drawn until whatever happened to refresh
        // next, which is the wait this stopped blocking to avoid.
        let (quotaUpdates, quotaLanded) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        // Pinned to a directory of its own: the reading is a real session that
        // fires real hooks, and the working directory is what keeps its events
        // out of the row list.
        self.usage = usage ?? ClaudeCodeUsageReader(
            clock: clock,
            workingDirectory: paths.agentDirectory
                .appendingPathComponent("usage", isDirectory: true),
            tokens: ClaudeCodeTokenCounter(clock: clock),
            transcripts: ClaudeCodeUsageTranscripts(clock: clock),
            onUpdate: { quotaLanded.yield() }
        )
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
            ).events(),
            quotaUpdates
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
                    ? "Claude Code 的 Hook 注册与本版本需要的不一致，请在设置里重新粘贴："
                        + "缺少的事件不会报错，只会永远不到达；"
                        + "形状过时的 handler（例如少了 `async`）会让会话等待本应用响应。"
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
        var accountedFor: Set<String> = []
        for turn in hookState.turns {
            // A turn whose session is gone is gone. This is the whole reason
            // the session list is load-bearing rather than a convenience.
            guard let session = liveByID[turn.threadID] else { continue }
            accountedFor.insert(turn.threadID)
            rows.append(
                row(
                    for: turn,
                    in: session,
                    title: await title(for: session),
                    preview: preview(for: session)
                )
            )
        }

        // Sessions the reducer has never heard of: either they were running
        // before this app was, or their hooks were registered after they
        // started. Codex has no way to ask about those and shows nothing; here
        // the transcript can be read, which is the one place the two products
        // genuinely differ in what they can know.
        //
        // The reducer always wins where it has an opinion, including when that
        // opinion is Completed — a real event outranks a reconstruction.
        for session in liveByID.values where !accountedFor.contains(session.sessionID) {
            guard let reconstructed = await transcripts.currentTurn(
                forSession: session.sessionID,
                workingDirectory: session.workingDirectory
            ) else { continue }
            rows.append(
                MonitoredSession(
                    agent: .claudeCode,
                    threadID: session.sessionID,
                    // The same id the hooks use, so the first real event
                    // addresses this turn rather than opening a second one.
                    turnID: reconstructed.turnID,
                    projectName: projectName(for: session),
                    title: await title(for: session) ?? "Untitled",
                    privacySafeTitle: "Untitled",
                    // A reconstructed turn started before this app did, so the
                    // deltas that would have described it were never sent. It
                    // gets a preview from the first message printed after we
                    // began listening, and nothing before then.
                    preview: preview(for: session),
                    // Only ever Running. Nothing is written while a turn waits
                    // on the user, so a reconstruction cannot tell a wait from
                    // work -- and guessing which would be inventing a state.
                    status: .running,
                    startedAt: reconstructed.startedAt
                )
            )
        }
        rows.sort(by: MonitorAggregation.rowOrder)

        return snapshot(
            availability: .ready,
            sessions: rows,
            setupStatus: status,
            diagnostic: hookState.diagnostic,
            // Whatever is known right now. Awaiting the reading here is what
            // made a hook event's row wait on a `claude` launch.
            quota: await usage.currentQuota(),
            // Not `rows.isEmpty`: a session with no turn in flight is still an
            // open Claude Code. The list answers which sessions exist and the
            // reducer answers what they are doing — presence draws the matrix,
            // the reducer lights it, and merging the two would put the mark
            // back to reporting turns instead of openness.
            presence: await sessions.presence()
        )
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
    func nextRefreshDeadline() async -> Date? {
        await usage.nextReadDeadline()
    }

    /// The transcripts the quota readings leave in Claude Code's own project
    /// folder. Reported so the user can see them grow and clear them if they
    /// want to; never cleared here.
    func diskFootprint() async -> AgentDiskFootprint? {
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
