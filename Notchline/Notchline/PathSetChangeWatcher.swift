import Foundation

/// Change signals for a set of paths that is reconciled while the app runs.
///
/// ``DirectoryChangeWatcher/merged(_:)`` is fixed when built; these sets (session records of
/// in-flight turns, Claude Desktop account folders) change, while consumers subscribe once at
/// launch. A path leaving the set drops its watcher. Existing watchers re-attach on every
/// reconcile (see ``DirectoryChangeWatcher/attachIfNeeded()``).
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

    /// The paths currently watched. Reporting only, for tests; see
    /// ``ClaudeCodeMonitorService/transcriptWatcher`` and ``LiveCodexMonitorService/rolloutWatcher``.
    nonisolated var watchedPaths: Set<URL> {
        lock.lock()
        defer { lock.unlock() }
        return Set(watches.keys)
    }

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

        // Outside the lock: attaching opens a descriptor, and cancelling a forwarder can run
        // arbitrary continuation work.
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
                // A missing path here is an ended session, an unwritten transcript or a removed account
                // folder, not a diagnostic. See ``DirectoryChangeWatcher/absenceIsExpected``.
                absenceIsExpected: true
            )
            let events = watcher.events()
            let forwarder = Task { [weak self] in
                for await _ in events {
                    self?.deliver()
                }
            }
            lock.lock()
            // A reconcile or teardown that ran meanwhile has seen something newer, so it wins.
            let keep = !isFinished && watches[path] == nil
            if keep { watches[path] = Watch(watcher: watcher, forwarder: forwarder) }
            lock.unlock()
            if !keep { forwarder.cancel() }
        }
    }

    /// How many paths are being watched. For tests; nothing in the product branches on it.
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
