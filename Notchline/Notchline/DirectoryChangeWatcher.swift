import Darwin
import Dispatch
import Foundation
import OSLog

/// Coalesced change notifications for one path; a hint, never a source of truth.
///
/// Atomically replaced files (Codex state, the hook queue) report only via their directory;
/// in-place rewrites (Claude Code session records) only via the file
/// (``ClaudeCodeSessionRecordWatcher``). Attachment may fail or go stale (CR-025, CR-018), so
/// it retries on `rename`/`delete` and on ``attachIfNeeded()``, never on its own timer.
final class DirectoryChangeWatcher: @unchecked Sendable {
    nonisolated private static let logger = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "DirectoryChangeWatcher"
    )

    private let lock = NSLock()
    nonisolated private let directoryURL: URL
    private let queue = DispatchQueue(
        label: "com.yinfenglu.notchline.directory-watcher"
    )
    private let debounceInterval: TimeInterval
    /// Whether `ENOENT`/`ENOTDIR` on attach is expected and silent: true for per-member watchers
    /// of a reconciled set (``PathSetChangeWatcher``), where deletion is every session's end.
    nonisolated private let absenceIsExpected: Bool
    nonisolated(unsafe) private var source: DispatchSourceFileSystemObject?
    nonisolated(unsafe) private var continuations: [
        UUID: AsyncStream<Void>.Continuation
    ] = [:]
    nonisolated(unsafe) private var pendingDelivery: DispatchWorkItem?
    nonisolated(unsafe) private var isFinished = false
    nonisolated(unsafe) private var isPaused = false
    /// The last failed attach, keyed on path and reason: a repeat is quiet, a new reason prints.
    nonisolated(unsafe) private var lastAttachFailure: (path: String, code: Int32)?
    nonisolated(unsafe) private var changeCounter: UInt64 = 0

    /// - Parameter absenceIsExpected: See ``absenceIsExpected``. Defaults to `false`.
    nonisolated init(
        directoryURL: URL,
        debounceInterval: TimeInterval,
        absenceIsExpected: Bool = false
    ) {
        self.directoryURL = directoryURL
        self.debounceInterval = debounceInterval
        self.absenceIsExpected = absenceIsExpected
        attachIfNeeded()
    }

    /// Attaches if not already attached; cheap to repeat. Returns whether the low-latency path
    /// is live.
    @discardableResult
    nonisolated func attachIfNeeded() -> Bool {
        lock.lock()
        guard !isFinished, !isPaused else {
            lock.unlock()
            return false
        }
        if source != nil {
            lock.unlock()
            return true
        }

        // `open` under the lock so two callers cannot both create a source: dropping a suspended
        // dispatch source traps in libdispatch.
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // Read first: the unlock and logging below may overwrite `errno`.
            let failure = errno
            let shouldLog = lastAttachFailure?.path != directoryURL.path
                || lastAttachFailure?.code != failure
            lastAttachFailure = (directoryURL.path, failure)
            lock.unlock()
            // Silent only for expected absence; permission and descriptor failures always log.
            let isMissing = failure == ENOENT || failure == ENOTDIR
            if shouldLog, !(absenceIsExpected && isMissing) {
                // Once per path. The path is redacted at OSLog's default privacy; the `strerror` reason is
                // not, and tells absent from unopenable from out of descriptors.
                let reason = String(cString: strerror(failure))
                Self.logger.info(
                    "Directory watcher not attached at \(self.directoryURL.path): \(reason, privacy: .public) (errno \(failure)); falling back to refresh deadlines until it appears"
                )
            }
            return false
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handleFileSystemEvent()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        self.source = source
        lastAttachFailure = nil
        // Attaching counts as a change: anything read before it was read unwatched.
        changeCounter &+= 1
        lock.unlock()

        // Resumed outside the lock: the handler takes the same lock.
        source.resume()
        return true
    }

    nonisolated func pause() {
        lock.lock()
        isPaused = true
        let old = source
        source = nil
        pendingDelivery?.cancel()
        pendingDelivery = nil
        lock.unlock()
        old?.cancel()
    }

    nonisolated func resume() {
        lock.lock()
        isPaused = false
        lock.unlock()
        attachIfNeeded()
    }

    nonisolated var isAttached: Bool {
        lock.lock()
        defer { lock.unlock() }
        return source != nil
    }

    /// How many changes this watcher has seen, readable without waiting. A cache keyed on this
    /// count cannot lose the subscriber-ordering race a cache keyed on edges can (CR-028).
    nonisolated var changeCount: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return changeCounter
    }

    nonisolated func events() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let identifier = UUID()
            lock.lock()
            let isFinished = self.isFinished
            if !isFinished {
                continuations[identifier] = continuation
            }
            lock.unlock()

            // Subscribing while detached is allowed: the watcher may attach later, as on a first run.
            guard !isFinished else {
                continuation.finish()
                return
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(identifier)
            }
        }
    }

    deinit {
        lock.lock()
        isFinished = true
        let source = source
        self.source = nil
        pendingDelivery?.cancel()
        pendingDelivery = nil
        let continuations = Array(continuations.values)
        self.continuations.removeAll()
        lock.unlock()

        continuations.forEach { $0.finish() }
        source?.cancel()
    }

    /// Handles one batch of file system events. `rename`/`delete` re-open by path, surviving a
    /// reinstall or Codex replacing its state directory.
    nonisolated private func handleFileSystemEvent() {
        lock.lock()
        let mask = source?.data ?? []
        lock.unlock()

        if mask.contains(.rename) || mask.contains(.delete) {
            queue.async { [weak self] in
                guard let self else { return }
                self.detach()
                self.attachIfNeeded()
            }
        }
        scheduleDelivery()
    }

    nonisolated private func detach() {
        lock.lock()
        let source = source
        self.source = nil
        lock.unlock()
        source?.cancel()
    }

    // GCD wall time on purpose: this only coalesces events and makes no product timing decision.
    nonisolated private func scheduleDelivery() {
        lock.lock()
        guard !isFinished, !isPaused else {
            lock.unlock()
            return
        }
        pendingDelivery?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.deliver()
        }
        pendingDelivery = workItem
        lock.unlock()
        queue.asyncAfter(
            deadline: .now() + debounceInterval,
            execute: workItem
        )
    }

    nonisolated private func deliver() {
        lock.lock()
        pendingDelivery = nil
        guard !isPaused, !isFinished else { lock.unlock(); return }
        // Counted before yielding, so no consumer is woken by an edge ``changeCount`` does not reflect.
        changeCounter &+= 1
        let continuations = Array(continuations.values)
        lock.unlock()
        continuations.forEach { $0.yield(()) }
    }

    nonisolated private func removeContinuation(_ identifier: UUID) {
        lock.lock()
        continuations.removeValue(forKey: identifier)
        lock.unlock()
    }
}

extension DirectoryChangeWatcher {
    /// Folds several change streams into one refresh trigger; a burst across sources collapses
    /// into one wake-up.
    nonisolated static func merged(
        _ streams: [AsyncStream<Void>]
    ) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let forwarders = streams.map { stream in
                Task {
                    for await _ in stream {
                        continuation.yield(())
                    }
                }
            }
            continuation.onTermination = { _ in
                forwarders.forEach { $0.cancel() }
            }
        }
    }
}
