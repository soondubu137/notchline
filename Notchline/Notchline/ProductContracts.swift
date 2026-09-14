import Foundation

// Capability contracts: every product implements ``AgentMonitoring``; ``IntegrationConfiguring``,
// ``AnswerDelivering`` and ``DiskFootprintReporting`` are optional (tiered-support.md §5.2).

/// One product's observation boundary, reduced to what the store needs. The one contract every
/// product implements (L1 in `docs/product-support.md` §2).
protocol AgentMonitoring: Sendable {
    nonisolated var agent: AgentKind { get }
    /// Edges that mean "ask me again", merged by the store into one wake-up stream, so a slow
    /// provider does not hold up a fast one.
    nonisolated var stateChangeEvents: AsyncStream<Void> { get }
    /// This product's answer, told which of its rows the user has removed.
    ///
    /// The store owns the removal record (CR-Fable-004); the provider must stop re-checks for
    /// removed rows, which otherwise sample read state every second for life (CR-Fable-003). Ids
    /// are this product's ``MonitoredSession/id``.
    func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot
    /// Earliest moment a refresh could produce different output. The store sleeps until then
    /// instead of polling.
    func nextRefreshDeadline() async -> Date?
    func disconnect() async
}

extension AgentMonitoring {
    /// Nothing removed; the store holds the only removal record.
    func fetchSnapshot() async -> AgentSnapshot {
        await fetchSnapshot(dismissedRowIDs: [])
    }
}

/// A product whose observation has to be put in place (hook registration) and reports how
/// complete it is.
protocol IntegrationConfiguring: Sendable {
    func setupStatus() async -> IntegrationSetupStatus
    func installIntegration() async throws
    func removeIntegration() async throws
}

/// The one way an answer typed on the notch finds its way back to the request it answers.
///
/// Opaque: only the issuing channel (``HookReplyRegistry``) can resolve it, and only while it
/// still holds the connection. A handle from an earlier issuer or already spent addresses
/// nothing, so a stale or repeated click is harmless.
struct AnswerHandle: Hashable, Sendable {
    /// The channel that minted this handle, so another channel's number cannot address a request.
    let issuer: UUID
    /// The issuer's own name for the held connection, meaningless anywhere else.
    let ticket: UInt64

    /// For a fixture that only records what it was handed; addresses nothing on a live channel.
    static let unissued = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    init(ticket: UInt64, issuer: UUID = AnswerHandle.unissued) {
        self.ticket = ticket
        self.issuer = issuer
    }
}

/// A product whose requests can be answered from the notch (L6 for its declared request forms).
protocol AnswerDelivering: Sendable {
    /// Sends one answer down the connection its request arrived on (``AnswerOutcome``). The attempt
    /// spends the handle whatever the outcome, except an operation the channel does not carry.
    func answer(_ answer: AgentAnswer, on handle: AnswerHandle) async -> AnswerOutcome
}

/// A product that reports how much of its limits is left, read on its own clock.
///
/// Composed by the Provider, not read by the store: Claude Code uses ``ClaudeCodeUsageReader``,
/// Codex ``CodexUsageReader``. A product with none publishes ``QuotaSnapshot/noneReported``
/// (`quota-footer-v2.md` §5).
protocol UsageReading: Sendable {
    /// What is known now. Never waits for a read.
    func currentQuota() async -> QuotaSnapshot
    /// Starts a read if the figures are stale and a screen could show them; a landed read
    /// announces itself on the composer's edge.
    func readIfStale() async
    /// When the figures want reading again; nil while nothing a refresh could start is due.
    func nextReadDeadline() async -> Date?
    /// A sentence the user can act on while there are no figures to draw.
    func quotaDiagnostic() async -> String?
}

/// A product whose monitoring leaves files on disk. Reporting only: nothing here deletes them,
/// since the folder can hold the user's own sessions. Answers even before it can measure.
protocol DiskFootprintReporting: Sendable {
    func diskFootprint() async -> AgentDiskFootprintReport
}
