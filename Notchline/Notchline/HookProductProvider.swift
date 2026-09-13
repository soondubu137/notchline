import Foundation

/// A Hooks composition of ProductMonitoringRuntime. Setup and answer methods
/// belong here; a source without those capabilities uses the runtime directly.
struct HookProductProvider: AgentMonitoring, IntegrationConfiguring, AnswerDelivering, DiskFootprintReporting {
    nonisolated let agent: AgentKind
    private let hooks: HookLifecycleSource
    private let runtime: ProductMonitoringRuntime
    nonisolated var stateChangeEvents: AsyncStream<Void> { runtime.stateChangeEvents }
    nonisolated var repository: MonitoringRepository { hooks.repository }

    /// A product whose presence and admission are two separate answers.
    init(
        agent: AgentKind,
        paths: HookIntegrationPaths,
        vocabulary: any AgentHookVocabulary,
        presence: any ProductPresenceReporting,
        admission: any ThreadAdmitting = AdmitsEveryObservedThread(),
        readEvidence: (any ReadEvidenceSource)? = nil,
        usage: (any UsageReading)? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard,
        fileManager: FileManager = .default,
        changeEvents: [AsyncStream<Void>] = []
    ) {
        self.init(
            agent: agent,
            hooks: HookLifecycleSource(
                paths: paths,
                vocabulary: vocabulary,
                clock: clock,
                timing: timing,
                fileManager: fileManager
            ),
            sessions: SeparateSessionReading(presence: presence, admission: admission),
            readEvidence: readEvidence,
            usage: usage,
            clock: clock,
            timing: timing,
            changeEvents: changeEvents
        )
    }

    /// A product whose own list answers presence and admission together.
    init(
        agent: AgentKind,
        paths: HookIntegrationPaths,
        vocabulary: any AgentHookVocabulary,
        sessions: any ProductSessionReading,
        readEvidence: (any ReadEvidenceSource)? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard,
        fileManager: FileManager = .default,
        changeEvents: [AsyncStream<Void>] = []
    ) {
        self.init(
            agent: agent,
            hooks: HookLifecycleSource(
                paths: paths,
                vocabulary: vocabulary,
                clock: clock,
                timing: timing,
                fileManager: fileManager
            ),
            sessions: sessions,
            readEvidence: readEvidence,
            clock: clock,
            timing: timing,
            changeEvents: changeEvents
        )
    }

    init(
        agent: AgentKind,
        hooks: HookLifecycleSource,
        sessions: any ProductSessionReading,
        turnEvidence: [any TurnEvidenceSource] = [],
        rowContent: any RowContentSource = WorkingDirectoryRowContent(),
        readEvidence: (any ReadEvidenceSource)? = nil,
        usage: (any UsageReading)? = nil,
        footprint: (any DiskFootprintReporting)? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard,
        changeEvents: [AsyncStream<Void>] = []
    ) {
        self.agent = agent
        self.hooks = hooks
        runtime = ProductMonitoringRuntime(
            agent: agent, lifecycle: hooks, sessions: sessions,
            turnEvidence: turnEvidence, rowContent: rowContent,
            readEvidence: readEvidence, usage: usage, footprint: footprint,
            clock: clock, timing: timing, changeEvents: changeEvents
        )
    }

    @discardableResult
    nonisolated func deliver(_ body: Data, at receivedAt: Date) -> AgentHookListener.Disposition {
        hooks.deliver(body, at: receivedAt)
    }
    func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot {
        await runtime.fetchSnapshot(dismissedRowIDs: dismissedRowIDs)
    }
    func nextRefreshDeadline() async -> Date? { await runtime.nextRefreshDeadline() }
    func disconnect() async { await runtime.disconnect() }
    func answer(_ answer: AgentAnswer, on handle: AnswerHandle) async -> Bool {
        await hooks.answer(answer, on: handle)
    }
    func setupStatus() async -> IntegrationSetupStatus { await hooks.setupStatus() }
    func installIntegration() async throws { try await hooks.install() }
    func removeIntegration() async throws {
        try await hooks.remove()
        await hooks.repository.resetIntegrationObservation(clearTurns: true)
        await runtime.disconnect()
    }
    func diskFootprint() async -> AgentDiskFootprintReport { await runtime.diskFootprint() }
    nonisolated static func projectName(forWorkingDirectory path: String?) -> String {
        WorkingDirectoryRowContent.projectName(forWorkingDirectory: path)
    }
}
