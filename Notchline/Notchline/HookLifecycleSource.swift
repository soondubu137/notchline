import Foundation

/// What writes a product's hook registration and the helper it names, as the
/// transport sees it.
///
/// Two conformers, one per trust policy: ``ManagedHooksSetup`` for a product
/// whose hooks run as registered, and ``CodexHookRegistrar`` for one whose
/// definitions are content-hashed and trusted one by one (ADR 0014). P2 kept
/// them as two actors rather than one over a flags value; this is the one
/// shape both present to the transport, so neither Provider wires its hooks
/// by hand (`tiered-support.md` §5.4).
protocol HookRegistrationSetup: Sendable {
    /// Where the helper hands each payload, and where the listener binds.
    nonisolated var socketURL: URL { get }
    /// Puts the helper in place for a refresh about to bind the socket, and
    /// says whether the socket is worth binding.
    ///
    /// Each policy decides what that costs: a managed setup compares the
    /// helper's bytes on every refresh because the comparison is one read,
    /// and Codex's registrar compares once per launch and again only when a
    /// `stat` says the file has gone.
    func prepareHelperForTransport() async -> Bool
    /// How complete the registration is.
    ///
    /// - Parameter repository: The reducer this product's events land in, for
    ///   a policy whose status is projected against delivery evidence — a
    ///   trust step is complete only once a definition has been seen to fire.
    ///   A product with no trust step does not ask it anything.
    func status(observedBy repository: HookEventRepository) async -> IntegrationSetupStatus
    func install() async throws
    func uninstall() async throws
}

/// What a refresh may do with a product's hooks, decided before anything is
/// drained.
nonisolated enum HookTransportGate: Sendable {
    /// The registration is complete and the socket is bound.
    case open(IntegrationSetupStatus)
    /// Nothing can be listed, and the sentence the settings card says about
    /// why.
    case closed(
        availability: MonitorAvailability,
        setupStatus: IntegrationSetupStatus,
        diagnostic: String
    )
}

/// One product's hook transport, wired once: the setup that writes its
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
    let setup: any HookRegistrationSetup
    let repository: HookEventRepository
    let listener: AgentHookListener
    /// What stands between the socket and the reducer for a product whose
    /// payloads are not spelled the reducer's way; nil for the two that are.
    let translator: (any HookPayloadTranslating)?

    init(
        paths: HookIntegrationPaths,
        vocabulary: any AgentHookVocabulary,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard,
        fileManager: FileManager = .default,
        /// A directory whose events are this app's own doing and must not
        /// become rows — Claude Code's quota reading runs a session there.
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

    /// The three already made, for a product whose setup is not a managed one
    /// and whose reducer is built with defaults of its own — Codex's.
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

    /// One payload, as the helper delivered it, into the reducer — through the
    /// product's translator where it has one. The listener's delivery closure
    /// and a test that hands payloads over without a socket both go this way,
    /// so neither can reach the reducer with bytes the other would not.
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

    /// The reducer's "ask me again" edge.
    nonisolated func changeEvents() -> AsyncStream<Void> {
        repository.changeEvents()
    }

    /// Puts the helper in place and binds the socket it names. `false` means
    /// the product's events have nowhere to land: the folder is not writable,
    /// or another copy of this app already holds the socket.
    ///
    /// Both on every refresh, and cheap on both counts: the helper is at most
    /// one read and a string comparison, and
    /// ``AgentHookListener/start(socketURL:)`` returns immediately once it
    /// holds that socket. Repeating it is what repairs a support folder a user
    /// emptied while the app was running.
    @discardableResult
    func prepareTransport() async -> Bool {
        guard await setup.prepareHelperForTransport() else { return false }
        return listener.start(socketURL: setup.socketURL)
    }

    /// The registration checked and the socket bound, for a product whose
    /// hooks run as registered — the order every such product refreshes in.
    ///
    /// **The helper goes in before the status is read**, not after. It has to
    /// exist from the moment the user *could* have registered the definitions
    /// naming it, and that moment is not the moment this app decides the
    /// registration is complete: a registration made while this app was
    /// closed is live in the product's next session either way, and a missing
    /// helper there prints the one line CC-021 is about. Cheap enough to
    /// repeat — one read and a string comparison once the file is right.
    ///
    /// Codex does not refresh this way: its status is projected against the
    /// events the refresh has just drained, so it reads the pieces itself.
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

    func answer(_ answer: AgentAnswer, on handle: AnswerHandle) async -> Bool {
        await repository.answer(answer, on: handle.ticket)
    }

    func disconnect() {
        listener.stop()
    }
}
