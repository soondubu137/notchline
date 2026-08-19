import AppKit
import Foundation

/// When a product's application last came to the front.
///
/// **A transition, never a state.** This reports the instant the application
/// *became* frontmost, and deliberately not whether it is frontmost now. The
/// difference is the whole safety argument: a user who walks away leaving
/// Claude Desktop in front is not reading anything, and a rule built on "is
/// frontmost" would retire a finished row seconds after it appeared -- the one
/// failure this product cannot afford. A transition can only be produced by
/// somebody at the keyboard.
///
/// It also only knows about activations that happened while this app was
/// running. That is the honest reading of the signal: nothing here is
/// reconstructed from before launch.
nonisolated protocol DesktopActivationReporting: Sendable {
    /// The most recent activation, or nil if the application has not come to
    /// the front since this app started observing.
    func lastActivation() async -> Date?
    /// Fires on each activation, so a row waiting on one does not have to wait
    /// out a re-check.
    nonisolated func changeEvents() -> AsyncStream<Void>
}

/// Watches one application's activations through the public workspace
/// notification.
///
/// `NSWorkspace.didActivateApplicationNotification` is a public macOS API and
/// carries the activated application, so nothing here matches on a window
/// title, drives the UI, or asks for Accessibility. The bundle identifier is
/// the only product knowledge involved.
final class DesktopActivationWatcher: DesktopActivationReporting, @unchecked Sendable {
    private let lock = NSLock()
    private let clock: any MonitorClock
    nonisolated(unsafe) private var lastActivatedAt: Date?
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    nonisolated(unsafe) private var continuations: [
        UUID: AsyncStream<Void>.Continuation
    ] = [:]

    nonisolated init(
        bundleIdentifier: String,
        clock: any MonitorClock = SystemMonitorClock()
    ) {
        self.clock = clock
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication,
                application.bundleIdentifier == bundleIdentifier else {
                return
            }
            self?.recordActivation()
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        lock.lock()
        let continuations = Array(self.continuations.values)
        self.continuations.removeAll()
        lock.unlock()
        continuations.forEach { $0.finish() }
    }

    nonisolated func lastActivation() async -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return lastActivatedAt
    }

    nonisolated func changeEvents() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let identifier = UUID()
            lock.lock()
            continuations[identifier] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.lock()
                continuations.removeValue(forKey: identifier)
                lock.unlock()
            }
        }
    }

    nonisolated private func recordActivation() {
        lock.lock()
        lastActivatedAt = clock.now()
        let continuations = Array(self.continuations.values)
        lock.unlock()
        continuations.forEach { $0.yield(()) }
    }
}
