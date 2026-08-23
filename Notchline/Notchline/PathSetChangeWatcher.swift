import Foundation

/// Change signals for a set of paths that is reconciled while the app runs.
///
/// ``DirectoryChangeWatcher/merged(_:)`` cannot serve this: that merge is fixed
/// at the moment it is built, and both callers here hand over a set that
/// changes afterwards -- the session records of the turns still in flight, and
/// the account folders Claude Desktop keeps its session state in. A consumer
/// still subscribes exactly once, at launch, and goes on receiving edges as the
/// set underneath it is replaced.
///
/// Reconciled rather than added to: a path that leaves the set drops its
/// watcher here. Left to accumulate, this would hold a descriptor per path the
/// app had ever been interested in.
///
/// Existing watchers are asked to re-attach on every reconcile, for the reason
/// ``DirectoryChangeWatcher/attachIfNeeded()`` exists: the path may have been
/// created for the first time, or replaced, since the last one. One failed
/// `open` per refresh is cheaper than a timer.
final class PathSetChangeWatcher: @unchecked Sendable {
    private struct Watch {
        let watcher: DirectoryChangeWatcher
        let forwarder: Task<Void, Never>
    }

    private let lock = NSLock()
    private let debounceInterval: TimeInterval
    nonisolated(unsafe) private var watches: [URL: Watch] = [:]
    nonisolated(unsafe) private var continuations: [
        UUID: AsyncStream<Void>.Continuation
    ] = [:]
    nonisolated(unsafe) private var isFinished = false

    nonisolated init(debounceInterval: TimeInterval) {
        self.debounceInterval = debounceInterval
    }

    nonisolated func events() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let identifier = UUID()
            lock.lock()
            let isFinished = self.isFinished
            if !isFinished { continuations[identifier] = continuation }
            lock.unlock()

            guard !isFinished else {
                continuation.finish()
                return
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(identifier)
            }
        }
    }

    /// Watches exactly these paths, and no others.
    nonisolated func watch(paths: Set<URL>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        let dropped = watches.filter { !paths.contains($0.key) }
        for path in dropped.keys { watches.removeValue(forKey: path) }
        let existing = Set(watches.keys)
        let added = paths.subtracting(existing)
        let retained = watches.values.map(\.watcher)
        lock.unlock()

        // Outside the lock: attaching opens a descriptor, and cancelling a
        // forwarder can run arbitrary continuation work.
        for watch in dropped.values {
            watch.forwarder.cancel()
        }
        for watcher in retained {
            watcher.attachIfNeeded()
        }
        for path in added {
            let watcher = DirectoryChangeWatcher(
                directoryURL: path,
                debounceInterval: debounceInterval,
                // Every path here belongs to a set this app reconciles, so one
                // that is simply not there is not a diagnostic: it is the
                // session whose record it is having ended, a transcript not
                // written yet, or an account folder that went away. The watch
                // is dropped at the next reconcile either way, and a failure
                // that is *not* absence still gets its line. See
                // ``DirectoryChangeWatcher/absenceIsExpected``.
                absenceIsExpected: true
            )
            let events = watcher.events()
            let forwarder = Task { [weak self] in
                for await _ in events {
                    self?.deliver()
                }
            }
            lock.lock()
            // A reconcile that ran while this one was building the watcher
            // wins, and so does a teardown: both have seen something newer
            // than this call has.
            let keep = !isFinished && watches[path] == nil
            if keep { watches[path] = Watch(watcher: watcher, forwarder: forwarder) }
            lock.unlock()
            if !keep { forwarder.cancel() }
        }
    }

    /// How many paths are being watched. For tests and for a future diagnostic;
    /// nothing in the product branches on it.
    nonisolated var watchedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return watches.count
    }

    deinit {
        lock.lock()
        isFinished = true
        let watches = Array(self.watches.values)
        self.watches.removeAll()
        let continuations = Array(self.continuations.values)
        self.continuations.removeAll()
        lock.unlock()

        watches.forEach { $0.forwarder.cancel() }
        continuations.forEach { $0.finish() }
    }

    nonisolated private func deliver() {
        lock.lock()
        let continuations = Array(self.continuations.values)
        lock.unlock()
        continuations.forEach { $0.yield(()) }
    }

    nonisolated private func removeContinuation(_ identifier: UUID) {
        lock.lock()
        continuations.removeValue(forKey: identifier)
        lock.unlock()
    }
}
