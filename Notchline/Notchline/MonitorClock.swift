import Foundation

/// The single source of "what time is it" and "wait a while", so chained windows
/// (``MonitorTiming``) are testable.
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

/// Every timing window the monitor observes. They compose into user-visible latencies, asserted
/// directly: Codex Desktop dies → `Disconnected` ≈ 26s worst case; a finished turn read in
/// Desktop → row leaves in 224ms measured, bounded by `terminalUnreadRecheckInterval` (1s).
nonisolated struct MonitorTiming: Sendable {
    /// Upper bound on how long a missed trigger goes unnoticed (a watcher that never re-attaches,
    /// CR-018; a dropped wake-up). Not a work interval; never shorten it to fix a slow update.
    var heartbeatInterval: TimeInterval = 60
    /// Floor on the gap between two refreshes. A deadline already past on wake means the refresh
    /// did not clear it; this bounds that busy loop to 1 Hz. A backstop, not a cadence: nothing may
    /// depend on it for latency.
    var minimumRefreshInterval: TimeInterval = 1
    /// How long a full membership reconciliation stays fresh.
    var threadListRefreshInterval: TimeInterval = 30
    /// How long one thread's cached metadata stays fresh.
    var threadMetadataRefreshInterval: TimeInterval = 10
    var accountRefreshInterval: TimeInterval = 30
    var quotaRefreshInterval: TimeInterval = 60
    /// Cool-off before retrying a background read that failed outright.
    var requestRetryInterval: TimeInterval = 60
    /// Cool-off before a failed App Server launch is retried. A `codex` that launches and exits
    /// fails in milliseconds, so without it every refresh forked `codex app-server`, once a second
    /// (CR-Fable-014). Sized to the `initialize` timeout. Not published by `nextRefreshDeadline`:
    /// a floor on the next attempt, not a reason to wake.
    var connectRetryInterval: TimeInterval = 15
    /// Budget for a read on the snapshot path, where latency is user-visible.
    var coreRequestTimeout: TimeInterval = 5
    /// Budget for the paginated membership read, which runs in the background.
    var backgroundThreadListTimeout: TimeInterval = 15
    var threadMetadataTimeout: TimeInterval = 5
    /// Budget for one running turn's live-progress read; shortest here, since a fresher read soon
    /// supersedes it and a failure falls back to the prompt.
    var turnProgressTimeout: TimeInterval = 3
    /// Grace before a membership reconciliation may retire a brand-new Turn,
    /// covering a prompt Hook that beat Codex's own state write.
    var newTurnReconciliationGrace: TimeInterval = 10
    /// How long a finished Turn stays listed before unread evidence can hide it; Desktop recorded
    /// unread 583ms after a Turn finished (measured).
    var terminalReadSettlingInterval: TimeInterval = 2
    /// Re-examination interval for a listed terminal Turn waiting on the user: the floor under the
    /// unread watcher, not a cadence (``TerminalUnreadMembershipGate/nextDeadline(now:screenIsAvailable:)``).
    /// 1-7ms per snapshot (Release), only while such a row is listed and a screen is available.
    var terminalUnreadRecheckInterval: TimeInterval = 1
    /// Trailing debounce on the Desktop state directory, sized to an atomic replace's 3-14ms burst.
    var unreadStateDebounceInterval: TimeInterval = 0.05
    /// How long `disconnected` must persist before it replaces a trusted state.
    var disconnectGracePeriod: TimeInterval = 3
    var hoverExpandDelay: TimeInterval = 0.15
    var hoverCollapseDelay: TimeInterval = 0.25

    init() {}

    static let standard = MonitorTiming()
}
