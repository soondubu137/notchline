import Darwin
import Dispatch
import Foundation
import OSLog

/// Coalesced change notifications for one path.
///
/// **Which path is the whole decision, and it goes both ways.** Codex's state
/// files and this app's own hook queue are rewritten by atomic replace: the
/// inode changes, a descriptor on the file goes deaf after the first write, and
/// only the containing directory keeps reporting. Claude Code's session records
/// are the opposite -- rewritten in place -- and a directory vnode source does
/// not fire for a write *inside* the directory, so there only the file itself
/// reports (see ``ClaudeCodeSessionRecordWatcher``, which points instances of
/// this at files for exactly that reason). A trailing debounce collapses the
/// burst either produces into one signal.
///
/// The stream is a low-latency hint, never a source of truth: a caller that
/// misses an event still converges on its next refresh.
///
/// **Attachment is not assumed to succeed, and not assumed to last.** It used
/// to be attempted exactly once, in `init`, and a failure was permanent: on a
/// first run the Hook event directory does not exist yet -- it is created by
/// the installer, minutes later -- so the watcher was dead for the rest of the
/// process and every turn waited out a refresh deadline instead (CR-025). The
/// same applied after the directory was replaced or deleted, since a descriptor
/// keeps pointing at the old inode (CR-018).
///
/// Re-attaching is driven by two things and no timer of its own: the source
/// itself reports `rename`/`delete`, and callers invoke ``attachIfNeeded()`` on
/// work they were already doing. A watcher that cannot attach therefore costs
/// one failed `open` per refresh rather than a wake-up of its own -- which
/// matters, because idle cost is a product constraint here.
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
    /// Whether a path that is not there is news.
    ///
    /// It is news for a watcher built once and left: `~/.claude/sessions` does
    /// not exist until Claude Code has run, and the Hook event directory is
    /// created by the installer minutes after launch, so the line saying so is
    /// what explains a product waiting out refresh deadlines instead of
    /// reacting to edges. Those watchers say so.
    ///
    /// It is not news for a watcher built per member of a set that is
    /// reconciled while the app runs -- see ``PathSetChangeWatcher``. There a
    /// missing path is the session whose record it is having ended, which is
    /// how every one of them is expected to finish, and the owner drops the
    /// watch at its next reconcile. The message those watchers were printing
    /// -- "until it appears" -- was untrue of them twice over: it will not
    /// appear, and nothing is waiting for it to.
    ///
    /// One line per session exit is what that cost. A record's deletion is
    /// reported to the source as `delete`, which re-opens by path (see
    /// ``handleFileSystemEvent()``) and finds nothing there, so this is not a
    /// race that a busy machine loses occasionally -- it fires every time a
    /// watched session ends. Once every listed session's record was watched
    /// rather than only the ones with a Turn in flight, that was the ordinary
    /// churn of the machine, and it buried the case above in its own noise.
    ///
    /// **Only the expected failure is quiet.** This suppresses `ENOENT` and
    /// `ENOTDIR` and nothing else: a path this app is not allowed to open, or
    /// one it has no descriptor left for, is reported here exactly as it was.
    /// Those are the failures worth a line, and telling them apart is what
    /// `errno` is read for.
    nonisolated private let absenceIsExpected: Bool
    nonisolated(unsafe) private var source: DispatchSourceFileSystemObject?
    nonisolated(unsafe) private var continuations: [
        UUID: AsyncStream<Void>.Continuation
    ] = [:]
    nonisolated(unsafe) private var pendingDelivery: DispatchWorkItem?
    nonisolated(unsafe) private var isFinished = false
    /// The last failed attach, so one path does not print the same line every
    /// refresh -- and so a path that starts failing a *different* way still
    /// prints. Keyed on the reason as well as the path because the reasons
    /// want opposite responses: a record that is merely gone is silent for a
    /// reconciled set, and if that same path later cannot be opened for a
    /// reason that is not absence, the silence must not carry over to it.
    nonisolated(unsafe) private var lastAttachFailure: (path: String, code: Int32)?
    nonisolated(unsafe) private var changeCounter: UInt64 = 0

    /// - Parameter absenceIsExpected: Whether a path that cannot be opened is
    ///   an ordinary end rather than something to report. See
    ///   ``absenceIsExpected``. Defaults to `false`, so a caller has to say it.
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

    /// Attaches if not already attached. Cheap and safe to call repeatedly.
    ///
    /// Returns whether the watcher is attached when it returns, so a caller can
    /// tell "low-latency path is live" from "falling back to refresh deadlines".
    @discardableResult
    nonisolated func attachIfNeeded() -> Bool {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return false
        }
        if source != nil {
            lock.unlock()
            return true
        }

        // `open` happens under the lock so two callers cannot both create a
        // source. A dispatch source starts suspended, and dropping a suspended
        // source without resuming it traps in libdispatch, so losing a race
        // here is not something that can be cleaned up after the fact.
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // Read before anything else runs. `errno` is the thread's, and the
            // unlock and the logging below are entitled to overwrite it.
            let failure = errno
            let shouldLog = lastAttachFailure?.path != directoryURL.path
                || lastAttachFailure?.code != failure
            lastAttachFailure = (directoryURL.path, failure)
            lock.unlock()
            // Silent only for the one failure this path is *expected* to end
            // with, and only where it is expected. Everything else -- a folder
            // this app is not allowed to open, a process out of descriptors --
            // is reported wherever it happens, because those are the failures
            // that look identical in a product that has simply gone quiet.
            let isMissing = failure == ENOENT || failure == ENOTDIR
            if shouldLog, !(absenceIsExpected && isMissing) {
                // Once per path, not once per attempt.
                //
                // The path is interpolated at OSLog's default privacy, so it
                // is redacted in `log show` unless private data is enabled.
                // The reason is not: `strerror` names a kind of failure and no
                // user data, and which kind it is decides whether the line is
                // worth reading at all. Without it a path that is simply not
                // there yet is indistinguishable from one this app cannot open
                // or has run out of descriptors for -- and the three want
                // opposite responses.
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
        // Attaching counts as a change: until this moment nothing was watching
        // this path, so anything a caller read before it was read blind.
        changeCounter &+= 1
        lock.unlock()

        // Resumed outside the lock: the handler takes the same lock.
        source.resume()
        return true
    }

    nonisolated var isAttached: Bool {
        lock.lock()
        defer { lock.unlock() }
        return source != nil
    }

    /// How many changes this watcher has seen, readable without waiting for one.
    ///
    /// The stream says *when* something changed; this says *whether* anything
    /// has changed since a caller last looked, which is a different question and
    /// the one a cache needs answered. One edge wakes every subscriber in an
    /// unspecified order, so a cached reading that one subscriber drops and
    /// another re-reads is a race the scheduler settles -- and it can settle it
    /// the wrong way round, leaving the stale value cached with no further edge
    /// coming to correct it (CR-028). A caller that remembers this count
    /// alongside whatever it derived from the file has no ordering left to lose:
    /// the change is counted here before it is delivered anywhere.
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

            // Subscribing is no longer refused just because the watcher is
            // currently detached. It may attach later -- on a first run it
            // always does, once the installer creates the directory -- and a
            // stream finished at subscription time could never deliver that.
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

    /// Handles one batch of file system events.
    ///
    /// A `rename` or `delete` means the descriptor no longer refers to the
    /// directory at this path -- the inode is still open, but nothing will ever
    /// be written to it again. Re-opening by path is what keeps the watcher
    /// alive across an uninstall/reinstall, or across Codex replacing its state
    /// directory wholesale.
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

    // The debounce below stays on GCD wall time deliberately: it coalesces
    // filesystem events on the watcher's own queue and makes no product timing
    // decision, so routing it through MonitorClock would buy nothing.
    nonisolated private func scheduleDelivery() {
        lock.lock()
        guard !isFinished else {
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
        // Counted before it is yielded, so no consumer can be woken by an edge
        // that ``changeCount`` does not already reflect.
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
