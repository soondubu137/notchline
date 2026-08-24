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
/// - **Codex Desktop dies → `Disconnected` appears.**
///   `backgroundThreadListTimeout` (15s) + the transport's liveness grace (3s)
///   and probe timeout (5s) + `disconnectGracePeriod` (3s) ≈ 26s worst case.
/// - **A finished turn is read in Desktop → its row disappears.**
///   `unreadStateDebounceInterval` (50ms) once the watcher edge lands, which is
///   the normal case — measured end to end on the live app at 224ms from
///   Desktop's write to the row leaving the model. `terminalUnreadRecheckInterval`
///   (1s) is the bound when that edge does not land.
///
/// The second total is the only one with a term that exists purely to bound a
/// *missed* signal, and it is deliberate: the watcher is a hint, so the row it
/// governs needs a floor under it. `heartbeatInterval` is not that floor — it
/// covers mechanisms that fail silently, and nothing may depend on it for
/// latency.
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
    /// Cool-off before a failed App Server launch is attempted again.
    ///
    /// Separate from ``requestRetryInterval`` because it bounds a *spawn*, not
    /// a write to a transport that already exists: a `codex` that launches and
    /// exits -- a version mismatch after an update, a half-installed app --
    /// fails the connect in milliseconds, so with no cool-off the fork-and-exec
    /// rate is simply the refresh rate. Every refresh reason in the app reaches
    /// every product, so a Claude Code row waiting on the user at 1 Hz was
    /// enough to fork `codex app-server` once a second until the app was
    /// restarted (CR-Fable-014).
    ///
    /// Sized to the transport's own `initialize` timeout, which is already the
    /// floor under the *hanging* version of this failure. A binary that fails
    /// fast should not cost more than one that fails slowly.
    ///
    /// Deliberately not published by `nextRefreshDeadline`: it parks no work,
    /// so it is a floor on the next attempt rather than a reason to wake --
    /// the distinction ``LiveCodexMonitorService/deferred(_:by:)`` draws. A
    /// repaired Codex is picked up by whatever refresh comes next, and in the
    /// worst case by ``heartbeatInterval``, which exists for mechanisms that
    /// fail silently.
    var connectRetryInterval: TimeInterval = 15
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
    /// covering Desktop's persistence delay -- measured at 583ms between a Turn
    /// finishing and Desktop recording the thread as unread.
    var terminalReadSettlingInterval: TimeInterval = 2
    /// How often a listed terminal Turn is re-examined while it waits on the
    /// user rather than on time.
    ///
    /// This is the floor under the unread watcher, not a sampling cadence: the
    /// watcher normally answers first and this never comes due. It exists
    /// because the row it governs has no other bounded signal -- see
    /// ``TerminalUnreadMembershipGate/nextDeadline(now:screenIsAvailable:)``.
    /// One snapshot costs 1-7ms measured in Release on the live app, so the
    /// state this covers runs under 1% of a core and only while such a row is
    /// actually listed -- and only while there is a screen it could be read on,
    /// which is what stops it running through a locked night.
    var terminalUnreadRecheckInterval: TimeInterval = 1
    /// Trailing debounce on the Desktop state directory.
    ///
    /// Sized to the burst an atomic replace produces, measured at 3-14ms across
    /// real Desktop writes. The previous 250ms was 18-80x that, and every
    /// millisecond of it landed on the one path where a user is watching for a
    /// row to leave.
    var unreadStateDebounceInterval: TimeInterval = 0.05
    /// How long `disconnected` must persist before it replaces a trusted state.
    var disconnectGracePeriod: TimeInterval = 3
    /// Pointer dwell before the panel expands.
    var hoverExpandDelay: TimeInterval = 0.15
    /// Pointer dwell before the panel collapses.
    var hoverCollapseDelay: TimeInterval = 0.25

    init() {}

    static let standard = MonitorTiming()
}
