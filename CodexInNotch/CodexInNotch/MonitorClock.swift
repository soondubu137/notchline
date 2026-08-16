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
///   and probe timeout (5s) + `disconnectGracePeriod` (3s) ≈ 26s worst case.
/// - **A finished turn is read in Desktop → its row disappears.**
///   The unread watcher's 250ms debounce + `terminalReadSettlingInterval` (2s)
///   ≈ 2.25s worst case.
///
/// Neither total includes a poll interval any more: refreshes are driven by the
/// directory watchers and by wake-ups scheduled at the deadline that actually
/// matters. `heartbeatInterval` only bounds how long a *missed* trigger can go
/// unnoticed, so it never appears in a latency budget.
///
/// Changing any single value moves those totals, so they are asserted directly
/// rather than left as arithmetic in a comment.
nonisolated struct MonitorTiming: Sendable {
    /// Upper bound on how long a missed trigger can go unnoticed.
    ///
    /// This is a safety net for mechanisms that fail silently -- a watcher that
    /// never re-attaches (CR-018), a scheduled wake-up that was dropped -- not a
    /// work interval. Nothing may depend on it for latency, and shortening it is
    /// never the right fix for a slow update.
    var heartbeatInterval: TimeInterval = 60
    /// Floor on the gap between two refreshes.
    ///
    /// `nextRefreshDeadline` reports when output could next change, and the
    /// store sleeps until then. A deadline that is *already past* when the store
    /// wakes means the refresh it just ran did not clear it -- so running
    /// another one immediately does not clear it either, and the loop becomes a
    /// busy loop rather than a late wake-up. This bounds that failure to the 1 Hz
    /// the poll used to cost instead of letting it consume a whole core.
    ///
    /// It is a backstop, not a cadence: a service reporting honest deadlines
    /// never reaches it. Nothing may depend on it for latency.
    var minimumRefreshInterval: TimeInterval = 1
    /// How long a cached installation scan is trusted without re-reading disk.
    ///
    /// Installation health changes only when this app writes the configuration,
    /// when the user repairs it, or when something outside edits it. The first
    /// two invalidate the cache directly; this bounds the third.
    var installationRevalidationInterval: TimeInterval = 60
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
    /// Trailing debounce on the Hook event queue directory.
    var hookEventDebounceInterval: TimeInterval = 0.1
    /// Pointer dwell before the panel expands.
    var hoverExpandDelay: TimeInterval = 0.15
    /// Pointer dwell before the panel collapses.
    var hoverCollapseDelay: TimeInterval = 0.25

    init() {}

    static let standard = MonitorTiming()
}
