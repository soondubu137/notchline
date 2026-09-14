import Foundation

/// Serialises an operation and never loses a request made while it runs: a request raises a
/// monotonic revision, and a run covers the revision current when it began. Not an actor;
/// owners must mutate it from one isolation domain.
nonisolated struct SingleFlightGate: Sendable {
    /// Raised by every request, never reset.
    private var requestedRevision: UInt64 = 0
    private var runningRevision: UInt64?
    /// The highest revision a finished run has actually covered.
    private var completedRevision: UInt64 = 0

    nonisolated init() {}

    /// Returns the revision a caller waits on to see its own request covered.
    @discardableResult
    nonisolated mutating func request() -> UInt64 {
        requestedRevision &+= 1
        return requestedRevision
    }

    /// `false` means a run is going; it or its follow-up covers the request just made.
    nonisolated mutating func beginRun() -> Bool {
        guard runningRevision == nil else { return false }
        runningRevision = requestedRevision
        return true
    }

    /// Returns whether to run again, handing the claim straight over. A run with `covered: false`
    /// never continues on its own, which would be an unbounded retry loop without backoff.
    nonisolated mutating func endRun(covered: Bool = true) -> Bool {
        if covered, let runningRevision {
            completedRevision = max(completedRevision, runningRevision)
        }
        runningRevision = nil
        guard covered, requestedRevision > completedRevision else { return false }
        runningRevision = requestedRevision
        return true
    }

    nonisolated func hasCovered(_ revision: UInt64) -> Bool {
        completedRevision >= revision
    }

    /// True while a run is in flight for the request, and again if that run failed.
    nonisolated var isPending: Bool {
        requestedRevision > completedRevision
    }

    /// For a teardown that cancels the in-flight run; otherwise the claim is held forever.
    nonisolated mutating func reset() {
        requestedRevision = 0
        runningRevision = nil
        completedRevision = 0
    }
}
