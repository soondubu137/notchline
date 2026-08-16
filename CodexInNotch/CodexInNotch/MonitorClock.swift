import Foundation

/// The single source of "what time is it" and "wait a while".
///
/// Every timing decision in the monitor goes through this so the composed
/// behaviour is observable. Reading `Date()` directly makes a window untestable
/// on its own, and these windows are chained — see ``MonitorTiming`` — so the
/// user-visible latency is a sum that nothing could previously assert.
nonisolated protocol MonitorClock: Sendable {
    func now() -> Date
    func sleep(nanoseconds: UInt64) async throws
}

struct SystemMonitorClock: MonitorClock {
    nonisolated init() {}

    nonisolated func now() -> Date {
        Date()
    }

    nonisolated func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

extension MonitorClock {
    nonisolated func sleep(seconds: TimeInterval) async throws {
        try await sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

/// Every timing window the monitor observes, declared together.
///
/// They were previously spread across four files, which hid the fact that they
/// compose into user-visible latencies no single constant explains:
///
/// - **Codex Desktop dies → `Codex disconnected` appears.**
///   `backgroundThreadListTimeout` (15s) + the transport's liveness grace (3s)
///   and probe timeout (5s) + `disconnectGracePeriod` (3s) + one
///   `activePollInterval` (1s) ≈ 27s worst case.
/// - **A finished turn is read in Desktop → its row disappears.**
///   The unread watcher's 250ms debounce + `terminalReadSettlingInterval` (2s)
///   + one `activePollInterval` (1s) ≈ 3.25s worst case.
///
/// Changing any single value moves those totals, so they are asserted directly
/// rather than left as arithmetic in a comment.
struct MonitorTiming: Sendable {
    /// How often a snapshot is taken while Hook events are arriving.
    var activePollInterval: TimeInterval = 1
    /// How often a snapshot is retried while no integration is connected.
    var idlePollInterval: TimeInterval = 5
    /// How long a full membership reconciliation stays fresh.
    var threadListRefreshInterval: TimeInterval = 30
    /// How long one thread's cached metadata stays fresh.
    var threadMetadataRefreshInterval: TimeInterval = 10
    /// How long a resolved account identity stays fresh.
    var accountRefreshInterval: TimeInterval = 30
    /// How long a quota reading stays fresh.
    var quotaRefreshInterval: TimeInterval = 60
    /// Cool-off before retrying a background read that failed outright.
    var requestRetryInterval: TimeInterval = 60
    /// Budget for a read on the snapshot path, where latency is user-visible.
    var coreRequestTimeout: TimeInterval = 5
    /// Budget for the paginated membership read, which runs in the background.
    var backgroundThreadListTimeout: TimeInterval = 15
    /// Budget for a single thread's metadata read.
    var threadMetadataTimeout: TimeInterval = 5
    /// Grace before a membership reconciliation may retire a brand-new Turn,
    /// covering a prompt Hook that beat Codex's own state write.
    var newTurnReconciliationGrace: TimeInterval = 10
    /// How long a finished Turn stays listed before unread evidence can hide it,
    /// covering Desktop's ~500ms persistence delay.
    var terminalReadSettlingInterval: TimeInterval = 2
    /// How long `disconnected` must persist before it replaces a trusted state.
    var disconnectGracePeriod: TimeInterval = 3
    /// Pointer dwell before the panel expands.
    var hoverExpandDelay: TimeInterval = 0.15
    /// Pointer dwell before the panel collapses.
    var hoverCollapseDelay: TimeInterval = 0.25

    nonisolated init() {}

    nonisolated static let standard = MonitorTiming()
}
