import Foundation

/// What writes a product's hook registration and helper: ``ManagedHooksSetup``, or
/// ``CodexHookRegistrar`` for content-hashed trust (ADR 0014).
protocol HookRegistrationSetup: Sendable {
    /// Where the helper hands each payload, and where the listener binds.
    nonisolated var socketURL: URL { get }
    /// Says whether the socket is worth binding. Codex compares the helper once per launch.
    func prepareHelperForTransport() async -> Bool
    /// - Parameter repository: for a policy whose trust step is complete only once a definition
    ///   has been seen to fire.
    func status(observedBy repository: HookEventRepository) async -> IntegrationSetupStatus
    func install() async throws
    func uninstall() async throws
}

typealias HookTransportGate = MonitoringSourceGate

/// One product's hook transport, wired once: setup, reducer and socket listener
/// (`tiered-support.md` §5.4). Not an actor: the three it holds are.
struct HookLifecycleSource: MonitoringLifecycleSource {
    let setup: any HookRegistrationSetup
    let repository: HookEventRepository
    let listener: AgentHookListener
    /// nil for products whose payloads are already spelled the reducer's way.
    let translator: (any HookPayloadTranslating)?

    init(
        paths: HookIntegrationPaths,
        vocabulary: any AgentHookVocabulary,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard,
        fileManager: FileManager = .default,
        /// Events from here are this app's own (Claude Code's quota reading) and must not become rows.
        ignoredWorkingDirectory: URL? = nil,
        setup: (any HookRegistrationSetup)? = nil,
        repository: HookEventRepository? = nil,
        listener: AgentHookListener? = nil
    ) {
        self.init(
            setup: setup ?? ManagedHooksSetup(
                paths: paths,
                vocabulary: vocabulary,
                fileManager: fileManager
            ),
            repository: repository ?? HookEventRepository(
                paths: paths,
                fileManager: fileManager,
                clock: clock,
                timing: timing,
                vocabulary: vocabulary,
                ignoredWorkingDirectory: ignoredWorkingDirectory
            ),
            translator: vocabulary.payloadTranslator,
            listener: listener,
            clock: clock
        )
    }

    /// The three already made, for Codex, whose setup is not a managed one.
    init(
        setup: any HookRegistrationSetup,
        repository: HookEventRepository,
        translator: (any HookPayloadTranslating)? = nil,
        listener: AgentHookListener? = nil,
        clock: any MonitorClock = SystemMonitorClock()
    ) {
        self.setup = setup
        self.repository = repository
        self.translator = translator
        self.listener = listener ?? AgentHookListener(clock: clock) { body, receivedAt, descriptor in
            Self.deliver(body, at: receivedAt, on: descriptor, through: translator, to: repository)
        }
    }

    /// Through the translator where there is one; the listener and socketless tests both use it.
    @discardableResult
    nonisolated func deliver(
        _ body: Data,
        at receivedAt: Date,
        on descriptor: Int32? = nil
    ) -> AgentHookListener.Disposition {
        Self.deliver(body, at: receivedAt, on: descriptor, through: translator, to: repository)
    }

    nonisolated private static func deliver(
        _ body: Data,
        at receivedAt: Date,
        on descriptor: Int32?,
        through translator: (any HookPayloadTranslating)?,
        to repository: HookEventRepository
    ) -> AgentHookListener.Disposition {
        guard let translator else {
            return repository.deliver(body, at: receivedAt, on: descriptor)
        }
        guard let canonical = translator.canonicalPayload(from: body, receivedAt: receivedAt) else {
            return .close
        }
        return repository.deliver(canonical, at: receivedAt, on: descriptor)
    }

    nonisolated func changeEvents() -> AsyncStream<Void> {
        repository.changeEvents()
    }

    /// Every refresh, which repairs a support folder emptied at run time. `false`: the folder is
    /// not writable, or another copy of this app holds the socket.
    @discardableResult
    func prepareTransport() async -> Bool {
        guard await setup.prepareHelperForTransport() else { return false }
        return listener.start(socketURL: setup.socketURL)
    }

    /// The helper goes in before the status is read: a registration made while the app was
    /// closed is already live, and a missing helper prints the CC-021 line.
    func gate(productName: String) async -> HookTransportGate {
        let helperIsReady = await setup.prepareHelperForTransport()
        let status = await setupStatus()
        guard status == .active else {
            return .closed(
                availability: .setupRequired,
                setupStatus: status,
                diagnostic: status == .repairRequired
                    ? "The \(productName) hook registration is not what this "
                        + "version writes; turn its switch on in Settings to rewrite it."
                    : "The \(productName) integration is not registered yet."
            )
        }
        guard helperIsReady, listener.start(socketURL: setup.socketURL) else {
            return .closed(
                availability: .disconnected,
                setupStatus: status,
                diagnostic: "Cannot open the hook helper or bind its socket in this "
                    + "app's support folder. Either the folder is not writable, or "
                    + "another copy of this app is already running and receiving the "
                    + "events — only one copy can."
            )
        }
        return .open(status)
    }

    func setupStatus() async -> IntegrationSetupStatus {
        await setup.status(observedBy: repository)
    }

    func install() async throws {
        try await setup.install()
    }

    func remove() async throws {
        try await setup.uninstall()
    }

    func answer(_ answer: AgentAnswer, on handle: AnswerHandle) async -> AnswerOutcome {
        await repository.answer(answer, on: handle)
    }

    func disconnect() {
        listener.stop()
    }
}
