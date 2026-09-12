import Foundation

/// One product's hook transport, wired once: the managed setup that writes its
/// registration and helper, the reducer its events land in, and the socket
/// listener that hands them over in arrival order.
///
/// Every hook-based product needs exactly these three, connected exactly this
/// way — the listener's delivery closure is the reducer's `deliver`, the
/// socket the listener binds is the one the setup wrote into the helper. Each
/// Provider used to make the three and connect them itself; this is that
/// wiring in one place, so a Provider composes it and a test still injects any
/// of the three (`tiered-support.md` §5.4).
///
/// Not an actor: the three it holds are, and it adds no state of its own.
struct HookLifecycleSource: Sendable {
    let setup: ManagedHooksSetup
    let repository: HookEventRepository
    let listener: AgentHookListener

    init(
        paths: HookIntegrationPaths,
        vocabulary: any AgentHookVocabulary,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard,
        fileManager: FileManager = .default,
        /// A directory whose events are this app's own doing and must not
        /// become rows — Claude Code's quota reading runs a session there.
        ignoredWorkingDirectory: URL? = nil,
        setup: ManagedHooksSetup? = nil,
        repository: HookEventRepository? = nil,
        listener: AgentHookListener? = nil
    ) {
        self.setup = setup ?? ManagedHooksSetup(
            paths: paths,
            vocabulary: vocabulary,
            fileManager: fileManager
        )
        let repository = repository ?? HookEventRepository(
            paths: paths,
            fileManager: fileManager,
            clock: clock,
            timing: timing,
            vocabulary: vocabulary,
            ignoredWorkingDirectory: ignoredWorkingDirectory
        )
        self.repository = repository
        self.listener = listener ?? AgentHookListener(clock: clock) { body, receivedAt, descriptor in
            repository.deliver(body, at: receivedAt, on: descriptor)
        }
    }

    /// The reducer's "ask me again" edge.
    nonisolated func changeEvents() -> AsyncStream<Void> {
        repository.changeEvents()
    }

    /// Puts the helper in place and binds the socket it names. `false` means
    /// the product's events have nowhere to land: the folder is not writable,
    /// or another copy of this app already holds the socket.
    func prepareTransport() async -> Bool {
        guard await setup.prepareHelper() else { return false }
        return listener.start(socketURL: setup.socketURL)
    }

    func setupStatus() async -> IntegrationSetupStatus {
        await setup.status()
    }

    func install() async throws {
        try await setup.install()
    }

    func remove() async throws {
        try await setup.uninstall()
    }

    func answer(_ answer: AgentAnswer, on handle: AnswerHandle) async -> Bool {
        await repository.answer(answer, on: handle.ticket)
    }

    func disconnect() {
        listener.stop()
    }
}
