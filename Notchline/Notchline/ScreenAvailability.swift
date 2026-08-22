import AppKit
import Foundation

/// Whether the machine is in a state where a person could read anything, and an
/// edge for the moment it becomes one again.
///
/// **Why this is a dependency rather than a call.** Every route this product
/// has for retiring a finished row ends at somebody looking at a screen: Claude
/// Code's `isInFrontOfThem` and its terminal-gesture route both require
/// ``DesktopReadingWatcher/systemScreenIsAvailable()``, and Codex's unread flag
/// is cleared by the user opening the thread in Desktop. That reading was
/// already made inside each verdict. What was missing is the other half — the
/// verdict is asked once a second by a deadline
/// (``TerminalUnreadMembershipGate/nextDeadline(now:screenIsAvailable:)``), and
/// while the display is asleep or the screen locked the answer is knowably "no"
/// before any of that work is done. A sample taken where no route can fire is
/// not a sample of anything.
///
/// So the same reading is made *before* the deadline is booked, and the row is
/// left waiting on this stream instead. That turns a locked overnight machine
/// from one wake-up a second into none, and costs no latency: the notifications
/// below arrive when the user comes back, ahead of anything they could then do.
///
/// **The reading is the same one, deliberately.** Restating "awake, unlocked,
/// on the console" a second time is how the two halves drift apart. A row is
/// suppressed here only for states the verdict itself would have failed on.
nonisolated protocol ScreenAvailabilityReporting: Sendable {
    /// Whether the display is awake and the login session unlocked and on the
    /// console, right now.
    nonisolated func isAvailable() -> Bool
    /// Fires when that answer may have become true: the display waking, the
    /// screen unlocking, the screensaver stopping, this login session coming
    /// back to the console, or the machine waking from sleep.
    ///
    /// One-way on purpose. Going *un*available needs no edge — nothing is
    /// waiting on it, and the next refresh from any other cause reads the state
    /// directly.
    nonisolated func changeEvents() -> AsyncStream<Void>
}

/// The machine's own answer, through the public workspace and distributed
/// notifications.
///
/// Nothing here polls: the state is read on demand from the same Core Graphics
/// calls ``DesktopReadingWatcher`` uses, and the stream carries only the
/// transitions macOS already publishes. No window is inspected, no title is
/// matched, and nothing is written.
///
/// **Missing an edge keeps a row rather than losing one.** If none of these
/// notifications arrives, the row that was waiting on it stays listed until the
/// next refresh from any other cause — the direction this product prefers
/// everywhere else. The one thing that must not happen is the opposite, and it
/// cannot: no notification here can retire anything by itself.
final class ScreenAvailabilityWatcher: ScreenAvailabilityReporting, @unchecked Sendable {
    /// Posted by `loginwindow` when the screen is unlocked. Distributed rather
    /// than workspace-scoped, and public: `CGSessionCopyCurrentDictionary`
    /// reports the same state, but only when something asks.
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
    ///   - screenIsAvailable: Whether the display is awake and the login
    ///     session unlocked and on the console. Shared with
    ///     ``DesktopReadingWatcher`` rather than restated, and injected so a
    ///     test can put the machine in each of those states without touching
    ///     the real one — a suite left with the real reading would pass or fail
    ///     depending on whether the developer's screen happened to be locked
    ///     while it ran.
    ///   - wakeNotifications: Where waking and session changes are heard. The
    ///     default is the workspace's own centre.
    ///   - unlockNotifications: Where unlocking and the screensaver are heard.
    ///     The default is the distributed centre, which is another process on
    ///     its own schedule and free to coalesce — the same reason
    ///     ``DesktopReadingWatcher`` takes this parameter.
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
            // The display coming back on, which is where most of a locked
            // machine's night is actually spent.
            (wakeNotifications, NSWorkspace.screensDidWakeNotification),
            // The machine itself waking. Timers do not fire through sleep, so
            // this is what re-arms a row that was waiting when the lid closed.
            (wakeNotifications, NSWorkspace.didWakeNotification),
            // Another user was switched in and this session has come back.
            (wakeNotifications, NSWorkspace.sessionDidBecomeActiveNotification),
            (unlockNotifications, Self.screenIsUnlocked),
            (unlockNotifications, Self.screensaverDidStop)
        ]
        for (centre, name) in watched {
            observers.append(
                (centre, centre.addObserver(
                    forName: name,
                    object: nil,
                    // Delivered wherever it was posted rather than hopped onto
                    // the main queue, for the reason
                    // ``DesktopActivationWatcher`` gives: this stream exists so
                    // a row waiting on the user does not wait out a heartbeat,
                    // and the hop would put the main queue's backlog in front
                    // of exactly that.
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
