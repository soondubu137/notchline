import Foundation
@testable import CodexInNotch

/// A clock the test drives by hand.
///
/// `now()` returns whatever the test last set, and `sleep` suspends until the
/// test advances past its deadline. Together these turn the monitor's chained
/// timing windows into assertions that run instantly and cannot flake.
///
/// `@unchecked Sendable` is carried by the lock: every stored property is
/// touched only while `lock` is held, and continuations are always resumed
/// outside it so a waking task cannot deadlock against `advance`.
final class TestClock: MonitorClock, @unchecked Sendable {
    private struct Sleeper {
        let id: UUID
        let deadline: Date
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    nonisolated(unsafe) private var instant: Date
    nonisolated(unsafe) private var sleepers: [Sleeper] = []
    nonisolated(unsafe) private var requestedSleeps: [TimeInterval] = []

    nonisolated init(now: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.instant = now
    }

    nonisolated func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return instant
    }

    nonisolated func sleep(nanoseconds: UInt64) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                let interval = TimeInterval(nanoseconds) / 1_000_000_000
                requestedSleeps.append(interval)
                let deadline = instant.addingTimeInterval(interval)
                // A zero or already-elapsed delay still suspends once, so a
                // caller cannot starve the test by spinning without a wake-up.
                sleepers.append(
                    Sleeper(id: id, deadline: deadline, continuation: continuation)
                )
                lock.unlock()
            }
        } onCancel: {
            resume(id: id, with: CancellationError())
        }
    }

    /// Moves time forward and wakes everything now due.
    ///
    /// Yields afterwards so the woken tasks reach their next suspension point
    /// before the caller asserts, which is what makes ordering deterministic.
    func advance(by interval: TimeInterval) async {
        // The locked section is a separate synchronous function because NSLock
        // may not be taken across a suspension point. Splitting it also makes
        // the "resume outside the lock" rule structural rather than a comment.
        let due = takeSleepersDue(after: interval)
        for sleeper in due {
            sleeper.continuation.resume()
        }
        await settle()
    }

    private func takeSleepersDue(after interval: TimeInterval) -> [Sleeper] {
        lock.lock()
        defer { lock.unlock() }
        instant = instant.addingTimeInterval(interval)
        let due = sleepers.filter { $0.deadline <= instant }
        sleepers.removeAll { $0.deadline <= instant }
        return due
    }

    /// Number of callers currently waiting, for asserting that a scheduled
    /// piece of work really is parked on the clock rather than lost.
    var sleeperCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sleepers.count
    }

    /// Every interval a caller has asked to sleep for.
    ///
    /// `sleep` suspends even for a zero-length request, which is what keeps the
    /// test deterministic -- and what makes a production busy loop invisible
    /// here, since a caller spinning on `sleep(0)` looks exactly like one parked
    /// on a real delay. Recording the requested interval is the only way a test
    /// can tell the two apart.
    var requestedSleepIntervals: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return requestedSleeps
    }

    /// Lets already-runnable tasks progress without moving time.
    func settle(iterations: Int = 12) async {
        for _ in 0 ..< iterations {
            await Task.yield()
        }
    }

    private nonisolated func resume(id: UUID, with error: Error) {
        lock.lock()
        let index = sleepers.firstIndex { $0.id == id }
        let sleeper = index.map { sleepers.remove(at: $0) }
        lock.unlock()
        sleeper?.continuation.resume(throwing: error)
    }
}
