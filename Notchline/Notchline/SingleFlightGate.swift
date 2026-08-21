import Foundation

/// Serialises an operation and never loses a request made while it runs.
///
/// Three places needed the same three things and each had grown its own
/// half-version: a boolean saying "busy", no memory of requests that arrived
/// while busy, and no way for a caller to wait for a result that reflects its
/// own request. The boolean is the part that looks fine and is not -- dropping
/// a request is only safe when something else is guaranteed to ask again.
///
/// The mechanism is a monotonic revision. A request raises it; a run covers the
/// revision that was current when the run began. A request that arrives
/// mid-run therefore lands above the covered mark, and the gate says so.
///
/// This is a value, not an actor: every owner is already isolated -- an actor
/// or the main actor -- so adding isolation here would only add hops. Its
/// correctness therefore depends on the owner mutating it from one isolation
/// domain, which every caller in this app does.
nonisolated struct SingleFlightGate: Sendable {
    /// Raised by every request, never reset.
    private var requestedRevision: UInt64 = 0
    /// The revision the in-flight run is covering, if one is running.
    private var runningRevision: UInt64?
    /// The highest revision a finished run has actually covered.
    private var completedRevision: UInt64 = 0

    nonisolated init() {}

    /// Records a request and returns the revision it raised.
    ///
    /// The revision is what a caller waits on when it needs to see a result
    /// that accounts for its own request rather than whatever was already
    /// in flight.
    @discardableResult
    nonisolated mutating func request() -> UInt64 {
        requestedRevision &+= 1
        return requestedRevision
    }

    /// Claims the right to run.
    ///
    /// `false` means a run is already going. That run, or the one the gate
    /// will ask for when it ends, covers the request just made -- which is
    /// what makes returning early safe here and unsafe with a bare boolean.
    nonisolated mutating func beginRun() -> Bool {
        guard runningRevision == nil else { return false }
        runningRevision = requestedRevision
        return true
    }

    /// Ends a run and, if more was requested meanwhile, claims the next one.
    ///
    /// Returns whether the caller should run again. The claim is handed
    /// straight over rather than released and re-taken, so no other caller can
    /// slip a second run in between.
    ///
    /// `covered` is whether this run satisfied the request. A run that did not
    /// **never continues on its own**: its request stays outstanding, and
    /// whatever governs retries decides when to try again. Continuing here
    /// would be an unbounded retry loop with no backoff in it -- which this
    /// type did do at first, and which no call site could have been trusted to
    /// notice, because the guard against it lived in the caller.
    nonisolated mutating func endRun(covered: Bool = true) -> Bool {
        if covered, let runningRevision {
            completedRevision = max(completedRevision, runningRevision)
        }
        runningRevision = nil
        guard covered, requestedRevision > completedRevision else { return false }
        runningRevision = requestedRevision
        return true
    }

    /// Whether a finished run has covered `revision`.
    nonisolated func hasCovered(_ revision: UInt64) -> Bool {
        completedRevision >= revision
    }

    /// Whether work has been requested that no finished run has covered.
    ///
    /// True while a run is in flight for it, and true again if that run failed.
    nonisolated var isPending: Bool {
        requestedRevision > completedRevision
    }

    /// Forgets everything, for a teardown that cancels the run in flight.
    ///
    /// Without this a cancelled run leaves the claim held forever and no
    /// later run can ever begin.
    nonisolated mutating func reset() {
        requestedRevision = 0
        runningRevision = nil
        completedRevision = 0
    }
}
