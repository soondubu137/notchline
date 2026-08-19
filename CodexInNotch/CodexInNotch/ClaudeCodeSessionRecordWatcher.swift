import Foundation

/// Change signals for the session records of the turns still in flight.
///
/// **Why a file and not the directory it sits in.** Every other watcher in this
/// app points at a directory, because the state it wants is replaced atomically
/// and a descriptor on the old inode goes deaf. Claude Code's session records
/// are the opposite case: `~/.claude/sessions/<pid>.json` is rewritten **in
/// place**, and a directory vnode source does not fire for a write inside the
/// directory. Measured 2026-08-18 with the same event mask this app already
/// uses: an in-place rewrite produced no directory event at all, while a
/// create, a delete and an atomic replace produced one each.
///
/// That is why `~/.claude/sessions` reports sessions appearing and going away
/// and nothing else -- and a session that is interrupted neither appears nor
/// goes away, it only stops saying it is busy (CC-019). Without this, that
/// change waited for whatever refresh happened next, up to a whole heartbeat.
///
/// **Signal only, and deliberately.** Nothing here reads a byte of the file.
/// The edge invalidates the session list and wakes a refresh; the answer still
/// comes from `claude agents --json`, which is what keeps the private path a
/// hint rather than a schema this app depends on.
///
/// **Only the records worth watching.** ``watch(processIdentifiers:)`` is given
/// the sessions whose turn is still going -- usually none, sometimes one. A
/// session with no turn in flight needs no edge: the turn it starts next
/// announces itself with a hook.
final class ClaudeCodeSessionRecordWatcher: @unchecked Sendable {
    private struct Watch {
        let watcher: DirectoryChangeWatcher
        let forwarder: Task<Void, Never>
    }

    private let lock = NSLock()
    nonisolated private let directory: URL
    private let debounceInterval: TimeInterval
    nonisolated(unsafe) private var watches: [Int32: Watch] = [:]
    nonisolated(unsafe) private var continuations: [
        UUID: AsyncStream<Void>.Continuation
    ] = [:]
    nonisolated(unsafe) private var isFinished = false

    nonisolated init(directory: URL, debounceInterval: TimeInterval) {
        self.directory = directory
        self.debounceInterval = debounceInterval
    }

    /// The path Claude Code writes a session's record to.
    ///
    /// The name is the session's pid, which the official command reports. This
    /// is the whole of the private knowledge here -- a location, not a schema.
    nonisolated func recordURL(forProcessIdentifier pid: Int32) -> URL {
        directory.appendingPathComponent("\(pid).json")
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

    /// Watches exactly these sessions' records, and no others.
    ///
    /// Reconciled rather than added to: a turn that ended, or a session that
    /// went away, drops its watcher here. Left to accumulate, this would hold a
    /// descriptor per session the app had ever seen work.
    ///
    /// Existing watchers are asked to re-attach, for the reason
    /// ``DirectoryChangeWatcher/attachIfNeeded()`` exists: the record may have
    /// been written for the first time, or replaced, since the last refresh.
    /// One failed `open` per refresh is cheaper than a timer.
    nonisolated func watch(processIdentifiers: Set<Int32>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        let dropped = watches.filter { !processIdentifiers.contains($0.key) }
        for pid in dropped.keys { watches.removeValue(forKey: pid) }
        let existing = Set(watches.keys)
        let added = processIdentifiers.subtracting(existing)
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
        for pid in added {
            let watcher = DirectoryChangeWatcher(
                directoryURL: recordURL(forProcessIdentifier: pid),
                debounceInterval: debounceInterval
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
            let keep = !isFinished && watches[pid] == nil
            if keep { watches[pid] = Watch(watcher: watcher, forwarder: forwarder) }
            lock.unlock()
            if !keep { forwarder.cancel() }
        }
    }

    /// How many records are being watched. For tests and for a future
    /// diagnostic; nothing in the product branches on it.
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
