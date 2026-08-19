import AppKit
import CoreGraphics
import Foundation

/// When the user last did something to a product's own application that only
/// somebody reading it does.
///
/// **Why this exists.** ``DesktopActivationReporting`` answers "the user came
/// back to that application", and Claude Desktop's own record answers "that
/// session was put on screen". Between them they miss the most ordinary shape
/// of all: the session was *already* on screen when its Turn ended and the user
/// never left. No file changes -- measured across the whole application-support
/// tree, zero -- and no activation happens, because the application never lost
/// the front. See [ADR 0012](../../docs/adr/0012-read-state-is-answered-per-product-or-not-at-all.md).
///
/// **What cannot be done, and why this is not it.** There is no way to retire
/// the row at the instant the Turn ends. At that instant the user who is
/// watching and the user who submitted and walked away are observationally
/// identical -- the last thing either of them did was submit the prompt -- so a
/// rule that fired there would retire the row for exactly the user this product
/// exists for. What *is* available is the first thing a reader does afterwards.
nonisolated protocol DesktopReadingReporting: Sendable {
    /// The last moment the user typed or scrolled into that application, or nil
    /// when this app cannot say that they did.
    func lastReadingGesture() async -> Date?
}

/// Keystrokes and scrolls delivered to one application, and nothing else about
/// them.
///
/// Two public facts, and the rule needs both:
///
/// 1. **That application holds the front**, tracked through
///    `NSWorkspace.didActivateApplicationNotification` -- the same public
///    notification ``DesktopActivationWatcher`` uses, and the same bundle
///    identifier.
/// 2. **A keystroke or a scroll happened**, from
///    `CGEventSource.secondsSinceLastEventType`. That call reports *how long
///    ago* the last event of one type was and nothing else: no key, no
///    character, no position, no window. It needs no entitlement and prompts
///    for nothing -- it is not an event tap.
///
/// Holding the front is never load-bearing on its own. The rule that consumes
/// this also requires the gesture to fall *after* the Turn ended, so a user who
/// leaves the window in front and walks away produces nothing: their idle time
/// only grows, and the row stays. That is ADR 0012's objection to
/// "frontmost means read", answered rather than overridden.
///
/// **Mouse movement is deliberately not one of the gestures.** Keystrokes and
/// scrolls are delivered to whichever application holds the front, so observing
/// one while Claude Desktop holds it says the user typed or scrolled *into
/// Claude Desktop*. Movement is delivered to whatever is under the pointer,
/// which on a second display need not be that window at all -- counting it
/// would let a nudge of the mouse somewhere else retire the row. Clicks are
/// left out for a different reason: this app's own overlay can take one without
/// the front changing, and ADR 0012 refuses to let a Notch interaction stand in
/// for reading the answer in Claude Desktop.
final class DesktopReadingWatcher: DesktopReadingReporting, @unchecked Sendable {
    /// The gestures that are delivered to the application holding the front.
    nonisolated private static let gestures: [CGEventType] = [.keyDown, .scrollWheel]

    private let lock = NSLock()
    private let bundleIdentifier: String
    private let clock: any MonitorClock
    private let secondsSinceLastGesture: @Sendable () -> TimeInterval
    nonisolated(unsafe) private var isFrontmost: Bool
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    /// - Parameter secondsSinceLastGesture: How long ago the user last made one
    ///   of the gestures. Injected so a test can place one either side of a
    ///   Turn's last moment without synthesising HID events.
    nonisolated init(
        bundleIdentifier: String,
        clock: any MonitorClock = SystemMonitorClock(),
        secondsSinceLastGesture: @escaping @Sendable () -> TimeInterval =
            DesktopReadingWatcher.systemSecondsSinceLastGesture
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.clock = clock
        self.secondsSinceLastGesture = secondsSinceLastGesture
        // Read once, to know who holds the front before the first transition
        // arrives. Without it the very first parked read after launch could
        // never be seen: the user who is already in Claude Desktop when this app
        // starts never generates an activation for it. This is not the
        // "is it frontmost now" test ADR 0012 rejects -- on its own the flag
        // retires nothing, because the gesture still has to land after the Turn
        // ended.
        isFrontmost = NSWorkspace.shared.frontmostApplication?
            .bundleIdentifier == bundleIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else {
                return
            }
            self?.frontChanged(
                to: application.bundleIdentifier == bundleIdentifier
            )
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    nonisolated func lastReadingGesture() async -> Date? {
        guard holdsTheFront() else { return nil }

        let seconds = secondsSinceLastGesture()
        // A machine that has never seen one of these reports something enormous
        // rather than an error, and an enormous reading is simply a gesture too
        // old to clear anything.
        guard seconds.isFinite, seconds >= 0 else { return nil }
        return clock.now().addingTimeInterval(-seconds)
    }

    /// The smaller of the two idle readings: the user made *a* gesture that
    /// recently, whichever kind it was.
    nonisolated static func systemSecondsSinceLastGesture() -> TimeInterval {
        gestures
            .map {
                CGEventSource.secondsSinceLastEventType(
                    .combinedSessionState,
                    eventType: $0
                )
            }
            .min() ?? .infinity
    }

    nonisolated private func holdsTheFront() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isFrontmost
    }

    nonisolated private func frontChanged(to isFrontmost: Bool) {
        lock.lock()
        self.isFrontmost = isFrontmost
        lock.unlock()
    }
}
