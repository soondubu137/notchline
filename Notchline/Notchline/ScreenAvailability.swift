import AppKit
import Foundation

/// Whether a person could read the screen now, and an edge for when that becomes true again.
///
/// Read before the gate books its once-a-second deadline, so a sleeping or locked machine books
/// none and waits on this stream. Same reading as
/// ``DesktopReadingWatcher/systemScreenIsAvailable()``, so the two cannot drift.
nonisolated protocol ScreenAvailabilityReporting: Sendable {
    /// Display awake, session unlocked and on the console.
    nonisolated func isAvailable() -> Bool
    /// Display wake, unlock, screensaver stop, session return or system wake. One-way: going
    /// unavailable needs no edge.
    nonisolated func changeEvents() -> AsyncStream<Void>
}

/// On-demand Core Graphics reads plus macOS's published transitions; nothing polls. A missed
/// notification only keeps a row until the next refresh.
final class ScreenAvailabilityWatcher: ScreenAvailabilityReporting, @unchecked Sendable {
    /// Posted by `loginwindow` on unlock (distributed, public).
    nonisolated private static let screenIsUnlocked = Notification.Name(
        "com.apple.screenIsUnlocked"
    )
    nonisolated private static let screensaverDidStop = Notification.Name(
        "com.apple.screensaver.didstop"
    )

    private let lock = NSLock()
    private let screenIsAvailable: @Sendable () -> Bool
    nonisolated(unsafe) private var observers: [
        (NotificationCenter, NSObjectProtocol)
    ] = []
    nonisolated(unsafe) private var continuations: [
        UUID: AsyncStream<Void>.Continuation
    ] = [:]

    /// - Parameters:
    ///   - screenIsAvailable: Injected so tests do not depend on the developer's screen lock.
    ///   - unlockNotifications: The distributed centre, another process free to coalesce.
    nonisolated init(
        screenIsAvailable: @escaping @Sendable () -> Bool =
            DesktopReadingWatcher.systemScreenIsAvailable,
        wakeNotifications: NotificationCenter =
            NSWorkspace.shared.notificationCenter,
        unlockNotifications: NotificationCenter =
            DistributedNotificationCenter.default()
    ) {
        self.screenIsAvailable = screenIsAvailable
        let watched: [(NotificationCenter, Notification.Name)] = [
            (wakeNotifications, NSWorkspace.screensDidWakeNotification),
            // Timers do not fire through sleep, so this re-arms a waiting row.
            (wakeNotifications, NSWorkspace.didWakeNotification),
            (wakeNotifications, NSWorkspace.sessionDidBecomeActiveNotification),
            (unlockNotifications, Self.screenIsUnlocked),
            (unlockNotifications, Self.screensaverDidStop)
        ]
        for (centre, name) in watched {
            observers.append(
                (centre, centre.addObserver(
                    forName: name,
                    object: nil,
                    // Posting queue, not main: a hop would queue behind the main queue's backlog.
                    queue: nil
                ) { [weak self] _ in
                    self?.announce()
                })
            )
        }
    }

    deinit {
        for (centre, observer) in observers {
            centre.removeObserver(observer)
        }
        lock.lock()
        let continuations = Array(self.continuations.values)
        self.continuations.removeAll()
        lock.unlock()
        continuations.forEach { $0.finish() }
    }

    nonisolated func isAvailable() -> Bool {
        screenIsAvailable()
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

    nonisolated private func announce() {
        lock.lock()
        let continuations = Array(self.continuations.values)
        lock.unlock()
        continuations.forEach { $0.yield(()) }
    }
}
