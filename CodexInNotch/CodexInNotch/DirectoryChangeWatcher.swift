import Darwin
import Dispatch
import Foundation

/// Coalesced change notifications for one directory.
///
/// Both state sources this app reads are rewritten by atomic replace, so the
/// target inode changes and watching the file itself would stop working after
/// the first write. Watching the containing directory survives that, and a
/// trailing debounce collapses the burst a replace produces into one signal.
///
/// The stream is a low-latency hint, never a source of truth: a caller that
/// misses an event still converges on its next poll.
final class DirectoryChangeWatcher: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(
        label: "com.yinfenglu.codex-in-notch.directory-watcher"
    )
    private let debounceInterval: TimeInterval
    nonisolated(unsafe) private var source: DispatchSourceFileSystemObject?
    nonisolated(unsafe) private var continuations: [
        UUID: AsyncStream<Void>.Continuation
    ] = [:]
    nonisolated(unsafe) private var pendingDelivery: DispatchWorkItem?

    nonisolated init(directoryURL: URL, debounceInterval: TimeInterval) {
        self.debounceInterval = debounceInterval
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleDelivery()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        self.source = source
        source.resume()
    }

    nonisolated func events() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let identifier = UUID()
            lock.lock()
            let isAvailable = source != nil
            if isAvailable {
                continuations[identifier] = continuation
            }
            lock.unlock()

            guard isAvailable else {
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

    // The debounce below stays on GCD wall time deliberately: it coalesces
    // filesystem events on the watcher's own queue and makes no product timing
    // decision, so routing it through MonitorClock would buy nothing.
    nonisolated private func scheduleDelivery() {
        lock.lock()
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
    /// Folds several change streams into one refresh trigger.
    ///
    /// The consumer only ever reacts by taking a fresh snapshot, so which
    /// source fired carries no information worth preserving. Buffering the
    /// newest element collapses a burst across sources into a single wake-up.
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
