import Foundation
@testable import Notchline

/// A clock the test drives by hand. `@unchecked Sendable`: state is touched only under `lock`,
/// and continuations resume outside it so a waking task cannot deadlock against `advance`.
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
                // A zero delay still suspends once, so a spinning caller cannot starve the test.
                sleepers.append(
                    Sleeper(id: id, deadline: deadline, continuation: continuation)
                )
                lock.unlock()
            }
        } onCancel: {
            resume(id: id, with: CancellationError())
        }
    }

    /// Then yields so woken tasks reach their next suspension point before the caller asserts.
    func advance(by interval: TimeInterval) async {
        // Synchronous: NSLock may not be held across a suspension point.
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

    /// To assert scheduled work is parked on the clock rather than lost.
    var sleeperCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sleepers.count
    }

    /// `sleep(0)` suspends too, so only the requested intervals reveal a busy loop.
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
