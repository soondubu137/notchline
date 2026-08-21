import AppKit
import CoreGraphics
import Foundation

/// Whether a product's own application is in front of the user right now.
///
/// **Why this exists.** ``DesktopActivationReporting`` answers "the user came
/// back to that application", and Claude Desktop's own record answers "that
/// session was put on screen". Between them they miss the most ordinary shape
/// of all: the session was *already* on screen when its Turn ended and the user
/// never left. No file changes -- measured across the whole application-support
/// tree, zero -- and no activation happens, because the application never lost
/// the front. See [ADR 0012](../../docs/adr/0012-read-state-is-answered-per-product-or-not-at-all.md).
///
/// **This is a state, and that is a deliberate reversal.** Every other read
/// signal in this app is a transition, precisely so that somebody who walks
/// away cannot have a row retired for them. This one is not, and it cannot be:
/// at the instant a Turn ends, the user watching it finish and the user who
/// submitted and walked away have done exactly the same last thing, so no
/// transition separates them. The product's answer is to stop trying to
/// separate them and instead ask a narrower question honestly -- *is that
/// answer on a screen somebody could be looking at* -- accepting that a user
/// who stepped away with the window in front loses the row. The guards below
/// are what keep "could be looking at" from meaning "the machine is on".
nonisolated protocol DesktopReadingReporting: Sendable {
    /// Whether that application holds the front, on a screen that is actually
    /// showing something to somebody.
    func isInFrontOfTheUser() async -> Bool
}

/// One application's hold on the front, minus the states where holding it means
/// nothing.
///
/// Holding the front comes from `NSWorkspace.didActivateApplicationNotification`
/// -- the same public notification ``DesktopActivationWatcher`` uses, and the
/// same bundle identifier. On its own it is a poor proxy for "somebody is
/// looking", because an application goes on holding the front through a locked
/// screen, a sleeping display, a screensaver and a switched-away login session.
/// Three public readings take those back out:
///
/// - **The display is awake** (`CGDisplayIsAsleep`). A dark screen shows nobody
///   anything, and this is where most walked-away time actually ends up.
/// - **The login session is unlocked and on the console**
///   (`CGSessionCopyCurrentDictionary`). Locked, or another user switched in,
///   means that window is not on any screen the user can see.
/// - **No screensaver is running** (the public `com.apple.screensaver.didstart`
///   / `didstop` distributed notifications). Least load-bearing of the three:
///   the default is to lock with the screensaver, which the reading above
///   already catches, and unlike the other two this one is a notification that
///   could be missed rather than a state that can be read. It is here for the
///   configuration that runs a screensaver without locking.
///
/// **What no reading covers.** The window can hold the front while being
/// somewhere the user is not looking: on another display, on another Space, or
/// minimised with the application still active. Answering those needs window
/// geometry, and the bans on window inspection stand. A finished Turn in one of
/// those states is retired unseen -- that is the accepted cost of the rule, not
/// an oversight.
///
/// Hiding the application is deliberately *not* a fourth reading: hiding makes
/// it resign the front, so `holdsTheFront` already covers it. Minimising does
/// not, and nothing here can see that.
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
    ///   - screenIsAvailable: Whether the display is awake and the login
    ///     session unlocked and on the console. Injected so a test can put the
    ///     machine in each of those states without touching the real one.
    ///   - frontNotifications: Where activations are heard. The default is the
    ///     workspace's own centre, which is process-wide: a test that posts
    ///     into it is heard by every other watcher alive at the time, this
    ///     suite's included.
    ///   - screensaverNotifications: Where the screensaver is heard. The
    ///     default is the distributed centre, and this is the parameter that
    ///     earns the pair. The screensaver is the third of the three machine
    ///     states above, and it was the only one a test could not stage: the
    ///     other two are read on demand, while this one arrives from
    ///     `distnoted` -- another process, on its own schedule, free to
    ///     coalesce. Asking a test to wait for that round trip is asking it to
    ///     assert a latency nothing promises (CC-024).
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
        // Read once, because the front is a state and this app has to know it
        // before the first transition arrives -- a user already in Claude
        // Desktop when this app starts never generates an activation for it.
        isFrontmost = NSWorkspace.shared.frontmostApplication?
            .bundleIdentifier == bundleIdentifier
        // Delivered wherever it was posted rather than hopped onto the main
        // queue. Both readings are two booleans behind a lock, read from
        // whichever executor asks, so the hop protected nothing and only ever
        // widened the window in which this answers with the state before the
        // notification -- and the window it widens belongs to the one rule in
        // the product that retires a row without a gesture. The distributed
        // centre still delivers on the main run loop with no queue asked for
        // (measured 2026-08-20), so this changes which hop happens, not which
        // thread arrives.
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

    /// The display is awake, and the login session is unlocked and on the
    /// console.
    ///
    /// A session dictionary that cannot be read at all answers `false`: this
    /// rule is the one place in the product that retires a row without a
    /// gesture, so the reading that guards it fails towards keeping the row.
    nonisolated static func systemScreenIsAvailable() -> Bool {
        guard CGDisplayIsAsleep(CGMainDisplayID()) == 0,
              let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        // Absent while unlocked, which is why this reads "not true" rather than
        // requiring `false`.
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
