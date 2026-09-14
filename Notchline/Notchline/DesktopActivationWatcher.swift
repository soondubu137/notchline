import AppKit
import Foundation

/// When a product's application last came to the front.
///
/// A transition, never a state: a user who walks away leaving the app in front is not reading,
/// and must not have a finished row retired. Only activations seen since launch count.
nonisolated protocol DesktopActivationReporting: Sendable {
    /// The most recent activation, or nil if none since this app started observing.
    func lastActivation() async -> Date?
    /// Fires on each activation, so a waiting row need not wait out a re-check.
    nonisolated func changeEvents() -> AsyncStream<Void>
}

/// Watches one application's activations through the public
/// `NSWorkspace.didActivateApplicationNotification`: no window titles, UI driving or
/// Accessibility.
final class DesktopActivationWatcher: DesktopActivationReporting, @unchecked Sendable {
    private let lock = NSLock()
    private let clock: any MonitorClock
    private let notifications: NotificationCenter
    nonisolated(unsafe) private var lastActivatedAt: Date?
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    nonisolated(unsafe) private var continuations: [
        UUID: AsyncStream<Void>.Continuation
    ] = [:]

    /// - Parameter notifications: Where activations are heard. Injectable because the workspace
    ///   centre is process-wide, so a staged activation reaches every live watcher.
    nonisolated init(
        bundleIdentifier: String,
        clock: any MonitorClock = SystemMonitorClock(),
        notifications: NotificationCenter =
            NSWorkspace.shared.notificationCenter
    ) {
        self.clock = clock
        self.notifications = notifications
        // Delivered where posted, not hopped to main: the main queue's backlog delayed exactly the
        // rows this stream exists to wake. The state is a `Date?` under a lock.
        observer = notifications.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
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
            notifications.removeObserver(observer)
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
