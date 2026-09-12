import Foundation

// The contracts a product's module implements. A product implements only the
// ones it has the capability for: every product observes (``AgentMonitoring``),
// and beyond that a product that registers something implements
// ``IntegrationConfiguring``, one whose requests can be answered from the notch
// implements ``AnswerDelivering``, and one that leaves files behind implements
// ``DiskFootprintReporting``. Before the split, one protocol required all of
// them, so a product observed through anything but Hooks would have had to
// implement four meaningless methods (tiered-support.md §5.2).

/// One product's observation boundary, reduced to what the store needs.
///
/// The shape was always general — nothing in it names Codex — so a second
/// product does not widen it, it just means there is more than one of them.
/// This is the one contract every product implements (L1 in
/// `docs/product-support.md` §2); the others below are optional.
protocol AgentMonitoring: Sendable {
    /// Which product this provider speaks for.
    nonisolated var agent: AgentKind { get }
    /// Edges that mean "ask me again", merged by the store into one wake-up
    /// stream. A provider whose answer arrives late reports it here rather than
    /// through a deadline, which is what lets a slow provider not hold up a
    /// fast one.
    nonisolated var stateChangeEvents: AsyncStream<Void> { get }
    /// This product's answer, told which of its rows the user has already taken
    /// off the list.
    ///
    /// A removed row is still this product's row -- nothing was deleted, and
    /// the record of the removal belongs to the store, which is the only layer
    /// that can tell "the user waved it away" from "the Turn is over"
    /// (CR-Fable-004). What changes here is that the row is no longer waiting
    /// for anything, and only the provider can act on that: an entry in the
    /// terminal gate books a re-check once a second, and it does so for a row
    /// nobody can see as readily as for one on the notch. Removal used to stop
    /// at the top layer, so both products went on sampling read state for a row
    /// the user had already dismissed, for as long as its session lived
    /// (CR-Fable-003).
    ///
    /// Ids are ``MonitoredSession/id``, and only this product's.
    func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot
    /// Earliest moment a refresh could produce different output.
    ///
    /// The store sleeps until this instead of sampling on a fixed cadence, so a
    /// quiet monitor does no work at all and a due window is served exactly when
    /// it comes due.
    func nextRefreshDeadline() async -> Date?
    func disconnect() async
}

extension AgentMonitoring {
    /// Nothing removed, which is what a caller with no removal record of its
    /// own is saying. The store holds the only one there is.
    func fetchSnapshot() async -> AgentSnapshot {
        await fetchSnapshot(dismissedRowIDs: [])
    }
}

/// A product whose observation has to be put in place — today, both products
/// register hooks in a file of their own and report how complete that
/// registration is. A product with nothing to configure does not conform, and
/// the store then has no switch to operate for it.
protocol IntegrationConfiguring: Sendable {
    func setupStatus() async -> IntegrationSetupStatus
    func installIntegration() async throws
    func removeIntegration() async throws
}

/// The one way an answer typed on the notch finds its way back to the request
/// it answers.
///
/// Opaque outside the hook transport: the surface and the store carry it and
/// compare it, and only the repository that minted it knows it is a held
/// connection. A future transport binds its own kind of handle here without the
/// domain learning a new name for it. A handle no longer held answers nothing,
/// which is what makes a stale click harmless.
struct AnswerHandle: Hashable, Sendable {
    let ticket: HookReplyRegistry.Ticket
}

/// A product whose requests can be answered from the notch (L6 for its declared request forms).
protocol AnswerDelivering: Sendable {
    /// Sends one answer back down the connection its request arrived on.
    ///
    /// Returns whether the whole answer reached the product. `false` is an
    /// ordinary outcome rather than a bug — the product may have been answered
    /// in its own window and killed the hook process, and this is the only
    /// moment that can be discovered (``HookReplyRegistry``). It is
    /// [`answer-in-notch.md`](../../docs/answer-in-notch.md) §8's *not
    /// delivered*, and the row says so.
    ///
    /// **The handle rather than the row**, because the connection is what an
    /// answer travels on and a row is only where it was typed.
    func answer(_ answer: AgentAnswer, on handle: AnswerHandle) async -> Bool
}

/// A product that reports how much of its limits is left, read on a clock of
/// its own rather than on an edge.
///
/// A capability, not a contract the store reads: the Provider that composes a
/// reader publishes what it holds on the product's snapshot, books the
/// reader's deadline among its own, and says the reader's sentence in its
/// diagnostic. Claude Code reads its windows off `/usage` and its tokens off
/// the transcripts (``ClaudeCodeUsageReader``); Codex reads both over the App
/// Server (``CodexUsageReader``). A product with none publishes
/// ``QuotaSnapshot/noneReported`` — no windows at all, rather than one it
/// could not read (`quota-footer-v2.md` §5).
protocol UsageReading: Sendable {
    /// What is known now. Never waits for a read.
    func currentQuota() async -> QuotaSnapshot
    /// Starts a read behind the held figures if they have gone stale and
    /// there is a screen they could be drawn on. A read that lands announces
    /// itself on the edge its composer handed the reader.
    func readIfStale() async
    /// When the figures want reading again; nil while nothing is due that a
    /// refresh could start.
    func nextReadDeadline() async -> Date?
    /// A sentence the user can act on while there are no figures to draw.
    func quotaDiagnostic() async -> String?
}

/// A product whose monitoring leaves files on disk that the user may want to
/// find. Reporting only: nothing in this app deletes them — the folder they go
/// to can hold a user's own sessions as well, so the decision is theirs. A
/// product that leaves files answers even before it can measure them, so that
/// Settings can draw the row it is going to draw anyway.
protocol DiskFootprintReporting: Sendable {
    func diskFootprint() async -> AgentDiskFootprintReport
}
