import AppKit
import CoreGraphics
import Foundation

/// Whether a product's own application is in front of the user right now: covers a session
/// already on screen when its Turn ended, which changes no file and fires no activation
/// (ADR 0012). A deliberate state, so a user who walks away with the window in front loses
/// the row.
nonisolated protocol DesktopReadingReporting: Sendable {
    /// Whether that application holds the front, on a screen that is actually
    /// showing something to somebody.
    func isInFrontOfTheUser() async -> Bool
}

/// One application's hold on the front (`NSWorkspace.didActivateApplicationNotification`),
/// minus: a sleeping display (`CGDisplayIsAsleep`), a locked or off-console session
/// (`CGSessionCopyCurrentDictionary`), and a running screensaver
/// (`com.apple.screensaver.didstart` / `didstop`). Another display, another Space or a
/// minimised window still count: an accepted cost, as window geometry is banned.
final class DesktopReadingWatcher: DesktopReadingReporting, @unchecked Sendable {
    nonisolated private static let screensaverDidStart = Notification.Name(
        "com.apple.screensaver.didstart"
    )
    nonisolated private static let screensaverDidStop = Notification.Name(
        "com.apple.screensaver.didstop"
    )

    private let lock = NSLock()
    private let bundleIdentifier: String
    private let screenIsAvailable: @Sendable () -> Bool
    nonisolated(unsafe) private var isFrontmost: Bool
    nonisolated(unsafe) private var isRunningScreensaver = false
    nonisolated(unsafe) private var observers: [
        (NotificationCenter, NSObjectProtocol)
    ] = []

    /// - Parameters:
    ///   - frontNotifications: Injectable; the workspace centre is process-wide.
    ///   - screensaverNotifications: Injectable so a test can stage the screensaver, which
    ///     otherwise arrives from `distnoted` with no promised latency (CC-024).
    nonisolated init(
        bundleIdentifier: String,
        screenIsAvailable: @escaping @Sendable () -> Bool =
            DesktopReadingWatcher.systemScreenIsAvailable,
        frontNotifications: NotificationCenter =
            NSWorkspace.shared.notificationCenter,
        screensaverNotifications: NotificationCenter =
            DistributedNotificationCenter.default()
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.screenIsAvailable = screenIsAvailable
        // Seeded once: a user already in Claude Desktop at launch fires no activation.
        isFrontmost = NSWorkspace.shared.frontmostApplication?
            .bundleIdentifier == bundleIdentifier
        // Delivered where posted, not hopped to main: both readings are booleans under a lock, and
        // the hop only widened the stale window for the one rule that retires a row without a
        // gesture. The distributed centre still delivers on the main run loop (measured 2026-08-20).
        observers.append(
            (frontNotifications, frontNotifications.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard let application = notification.userInfo?[
                    NSWorkspace.applicationUserInfoKey
                ] as? NSRunningApplication else {
                    return
                }
                self?.set { $0.isFrontmost = application
                    .bundleIdentifier == bundleIdentifier
                }
            })
        )
        for (name, isRunning) in [
            (Self.screensaverDidStart, true),
            (Self.screensaverDidStop, false)
        ] {
            observers.append(
                (screensaverNotifications, screensaverNotifications.addObserver(
                    forName: name,
                    object: nil,
                    queue: nil
                ) { [weak self] _ in
                    self?.set { $0.isRunningScreensaver = isRunning }
                })
            )
        }
    }

    deinit {
        for (centre, observer) in observers {
            centre.removeObserver(observer)
        }
    }

    nonisolated func isInFrontOfTheUser() async -> Bool {
        guard holdsTheFrontUnobscured() else { return false }
        return screenIsAvailable()
    }

    /// The display is awake, and the login session is unlocked and on the console. An unreadable
    /// session dictionary answers `false`, which keeps the row.
    nonisolated static func systemScreenIsAvailable() -> Bool {
        guard CGDisplayIsAsleep(CGMainDisplayID()) == 0,
              let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        // Absent while unlocked, so this tests "not true" rather than requiring `false`.
        if flag(session, "CGSSessionScreenIsLocked") == true { return false }
        return flag(session, kCGSessionOnConsoleKey as String) == true
    }

    /// The values in the session dictionary are `CFBoolean`, which bridges to
    /// `NSNumber` rather than to `Bool`.
    nonisolated private static func flag(
        _ session: [String: Any],
        _ key: String
    ) -> Bool? {
        (session[key] as? NSNumber)?.boolValue
    }

    nonisolated private func holdsTheFrontUnobscured() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isFrontmost && !isRunningScreensaver
    }

    nonisolated private func set(_ change: (DesktopReadingWatcher) -> Void) {
        lock.lock()
        change(self)
        lock.unlock()
    }
}
