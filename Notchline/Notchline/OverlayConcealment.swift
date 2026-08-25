import AppKit

/// One on-screen window, reduced to the three fields that say who owns the top
/// of a display.
///
/// `bounds` is in the window server's global, y-flipped coordinate space — the
/// one `CGWindowListCopyWindowInfo` and `CGDisplayBounds` share, and *not*
/// `NSScreen.frame`'s. Mixing the two silently matches the wrong display on any
/// multi-display Mac whose screens are not all at y = 0.
nonisolated struct ChromeWindow: Equatable, Sendable {
    let owner: String
    let layer: Int
    let bounds: CGRect
}

/// What the window server is doing with a display's menu bar.
///
/// Three states and not two, because a Space switch is neither: for the ~850 ms
/// it takes -- and for as long as the user holds an interactive swipe, 3.5 s
/// measured -- the menu bar is still drawn and is simply somewhere else.
nonisolated enum MenuBarPresence: Equatable, Sendable {
    /// Drawn on the display it belongs to. The overlay belongs there with it.
    case drawn
    /// Drawn, but carried off the display by a Space transition. Nothing has
    /// been settled yet, so nothing should move.
    case sliding
    /// Not drawn at all: a full-screen window has taken the display, or the
    /// menu bar is set to hide automatically and is currently away.
    case away
}

/// Whether the overlay should be on a given display right now.
///
/// The overlay sits at `.statusBar`, one level above the menu bar, so the
/// window server never takes it away: it stayed in the notch over full-screen
/// video. The rule the product wants is "be present exactly where the menu bar
/// is present", and it has to be enforced here because **nothing publishes
/// it**. Every obvious API was measured on macOS 26.5 and reports the asking
/// process's own state, not the system's:
///
/// | Signal | Another app full-screen | Mission Control | Switching Space |
/// | --- | --- | --- | --- |
/// | `NSApp.currentSystemPresentationOptions` | `0`, unchanged | `0`, unchanged | not measured |
/// | `NSMenu.menuBarVisible()` | `true`, unchanged | `true`, unchanged | not measured |
/// | `NSScreen.visibleFrame` / `.safeAreaInsets` / `.auxiliaryTopLeftArea` | unchanged | unchanged | unchanged |
/// | `NSApplication.didChangeScreenParametersNotification` | not measured | not measured | never fired |
/// | `NSWorkspace.activeSpaceDidChangeNotification` | never fired | never fired | fires, but only once the switch is **over** |
/// | Window Server's own menu bar window | **leaves the on-screen list** | present | present, **slid sideways** |
/// | Dock's full-display covers below dock level | absent | appear, one per display | absent |
///
/// Only the last three rows move, which is why this reads the window list; of
/// the three, only the menu bar row is consulted, and it is read for **where**
/// the bar is rather than merely whether it is listed.
///
/// **A Space switch does not hide the menu bar. It slides it.** Measured on
/// 2026-08-24: through a switch the display's menu bar window keeps its top
/// edge and its width and travels horizontally -- `x: 0 → -1864` on an 1800pt
/// display -- until the incoming Space's own bar arrives at the origin. The
/// overlay is carried by the *same* offset, because the window server moves
/// both, so an overlay left alone slides out with the old desktop and back in
/// with the new one. That is precisely what the menu bar it follows does.
/// Insisting the bar be at the display's origin read all ~850 ms of that as
/// "the menu bar is gone" and ordered the overlay off screen and back on for
/// every switch; an interactive swipe held it off for as long as the finger was
/// down.
///
/// The `activeSpaceDidChange` row is the reason that is fixed here rather than
/// by subscribing: the notification arrives with the incoming bar, at the end
/// of a transition this has to survive from its first frame.
///
/// Mission Control does not hide the menu bar either. It is drawn over the
/// zoomed-out desktops exactly as usual, and the product wants the overlay
/// drawn there with it -- Mission Control is a place the user goes to look at
/// what is running, which is what this overlay is for. So this is still one
/// clause: the overlay follows the menu bar, and nothing else.
nonisolated enum OverlayConcealment {
    /// The window server's own process, as it names itself in the window list.
    static let windowServerOwner = "Window Server"
    /// `24`. The menu bar window sits at the level named for it.
    static let menuBarLayer = Int(CGWindowLevelForKey(.mainMenuWindow))
    /// Point tolerance when matching a window against a display.
    ///
    /// These rects come from the same window server that placed the display, so
    /// they agree exactly; this only absorbs a fractional scale conversion.
    static let matchTolerance: CGFloat = 1

    /// Where this display's menu bar is, as the window list shows it.
    ///
    /// A candidate is a menu bar window that shares this display's top edge and
    /// width. Landing on the display's own origin makes it ``drawn``; anywhere
    /// else it is ``sliding``, and none at all is ``away``.
    ///
    /// - Parameter otherDisplays: the bounds of every active display. A bar
    ///   resting on a *neighbour's* origin is that neighbour's own, not this
    ///   display's mid-slide: two displays of the same width whose top edges
    ///   share a y are otherwise indistinguishable by geometry, and reading the
    ///   neighbour's bar as this one's would leave the overlay sitting on top
    ///   of a full-screen film with nothing to move it. Passing this display's
    ///   own bounds in the list is harmless -- a bar at this display's origin
    ///   has already answered ``drawn``.
    static func menuBarPresence(
        onDisplay displayBounds: CGRect,
        windows: [ChromeWindow],
        otherDisplays: [CGRect] = []
    ) -> MenuBarPresence {
        // Fail open. A display with no usable bounds is one this cannot judge,
        // and of the two ways to be wrong -- an overlay that lingers over a
        // film, and an overlay that is simply gone with no way to ask for it
        // back -- only the second loses the product.
        guard displayBounds.width >= 1, displayBounds.height >= 1 else {
            return .drawn
        }

        var isSliding = false

        for window in windows {
            guard window.owner == windowServerOwner,
                  window.layer == menuBarLayer,
                  abs(window.bounds.minY - displayBounds.minY) <= matchTolerance,
                  abs(window.bounds.width - displayBounds.width)
                    <= matchTolerance else {
                continue
            }

            if abs(window.bounds.minX - displayBounds.minX) <= matchTolerance {
                return .drawn
            }

            let restsOnAnotherDisplay = otherDisplays.contains { other in
                abs(window.bounds.minX - other.minX) <= matchTolerance
                    && abs(window.bounds.minY - other.minY) <= matchTolerance
            }

            if !restsOnAnotherDisplay {
                isSliding = true
            }
        }

        return isSliding ? .sliding : .away
    }

    /// Every active display's bounds, in the window server's own coordinate
    /// space -- the one ``ChromeWindow/bounds`` is already in.
    ///
    /// This exists so that ``menuBarPresence(onDisplay:windows:otherDisplays:)``
    /// can tell a neighbour's resting menu bar from this display's sliding one.
    /// `NSScreen.screens` would answer the same question in AppKit coordinates
    /// and is exactly the mix-up ``ChromeWindow`` warns about.
    static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }

        var identifiers = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &identifiers, &count) == .success
        else {
            return []
        }

        return identifiers.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    /// The on-screen windows, as this process can see them.
    ///
    /// `.excludeDesktopElements` drops the wallpaper and backstop windows,
    /// which the menu bar clause does not consult; it costs 583µs against 723µs
    /// for the unfiltered list, measured in Release with 61 windows on screen.
    ///
    /// This reads only `kCGWindowOwnerName`, `kCGWindowLayer` and
    /// `kCGWindowBounds`. None of the three is redacted without Screen
    /// Recording permission — `kCGWindowName` is, which is why the menu bar is
    /// matched by owner and level rather than by its name, "Menubar".
    static func currentWindows() -> [ChromeWindow] {
        let listed = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]]

        return (listed ?? []).compactMap { entry in
            guard let owner = entry[kCGWindowOwnerName as String] as? String,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let boundsEntry = entry[kCGWindowBounds as String]
                    as? NSDictionary else {
                return nil
            }

            var bounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(
                boundsEntry as CFDictionary,
                &bounds
            ) else {
                return nil
            }

            return ChromeWindow(owner: owner, layer: layer, bounds: bounds)
        }
    }
}

/// Polls ``OverlayConcealment`` for one display and reports only the changes.
///
/// **It polls because there is nothing to subscribe to.** The table on
/// ``OverlayConcealment`` is also a list of the notifications that were tried:
/// no workspace, distributed or application notification fires when another
/// app takes the display full-screen, so an edge-triggered version of this
/// would simply never fire.
///
/// The cost is one `CGWindowListCopyWindowInfo` per interval, on a utility
/// queue, and **nothing downstream re-renders**: the report is compared against
/// the last one and dropped when equal, and the only thing a change does is
/// order a window in or out. Neither the store nor any SwiftUI view sees the
/// tick, which is what keeps this outside the rule in `AGENTS.md` §7.
///
/// A ``MenuBarPresence/sliding`` sample is not an answer and is not reported:
/// the last answer stands until the Space has finished arriving. That is what
/// keeps a desktop switch from ordering the overlay out and back in -- the
/// overlay rides the transition with the menu bar instead.
@MainActor
final class OverlayConcealmentWatcher {
    /// 250 ms.
    ///
    /// This is a latency budget, not a sampling rate: it is how long the
    /// overlay may still be on screen after the menu bar starts to go. It was
    /// picked against Mission Control's 350 ms zoom-out, the tighter of the two
    /// cases when Mission Control was still judged here; the menu bar's own
    /// fade is slower than that, so the budget is now looser than it needs to
    /// be. It is kept because a sample costs 583µs — 0.23% of one core,
    /// measured in Release — and there is nothing to buy by spending less.
    nonisolated static let defaultInterval: TimeInterval = 0.25

    private let interval: TimeInterval
    private let sampleWindows: @Sendable () -> [ChromeWindow]
    private let boundsOfDisplay: @Sendable (CGDirectDisplayID) -> CGRect
    private let boundsOfActiveDisplays: @Sendable () -> [CGRect]
    private let queue = DispatchQueue(
        label: "com.yinfenglu.Notchline.overlay-concealment",
        qos: .utility
    )

    private var timer: DispatchSourceTimer?
    private var observedDisplayID: CGDirectDisplayID?
    private var lastReported = false
    private var hasReported = false
    private var onChange: ((Bool) -> Void)?

    /// Sequence numbers handed out when a sample is *taken*, so that a sample
    /// which was overtaken on its way to the main actor is discarded instead of
    /// reported.
    ///
    /// Two things sample: the timer, on its own queue, and ``sampleNow()``,
    /// which the panel calls the moment it moves to another display. The
    /// timer's reading is minutes old by main-actor standards — it was taken
    /// before the hop — so without this, a display change could be answered
    /// with the previous display's menu bar, and the overlay would blink out
    /// and back for the 250 ms until the next sample corrected it.
    private let ticketLock = NSLock()
    private nonisolated(unsafe) var issuedTickets = 0
    private var lastConsumedTicket = 0

    private(set) var isConcealed = false

    init(
        interval: TimeInterval = OverlayConcealmentWatcher.defaultInterval,
        sampleWindows: @escaping @Sendable () -> [ChromeWindow] =
            OverlayConcealment.currentWindows,
        boundsOfDisplay: @escaping @Sendable (CGDirectDisplayID) -> CGRect = {
            CGDisplayBounds($0)
        },
        boundsOfActiveDisplays: @escaping @Sendable () -> [CGRect] =
            OverlayConcealment.activeDisplayBounds
    ) {
        self.interval = interval
        self.sampleWindows = sampleWindows
        self.boundsOfDisplay = boundsOfDisplay
        self.boundsOfActiveDisplays = boundsOfActiveDisplays
    }

    deinit {
        timer?.cancel()
    }

    /// Which display the overlay is on. A display this cannot identify — the
    /// fallback path in ``DisplayOption/identifier(for:)`` — reports revealed,
    /// per the fail-open rule on
    /// ``OverlayConcealment/isConcealed(onDisplay:windows:)``.
    func observe(displayID: CGDirectDisplayID?) {
        guard observedDisplayID != displayID else { return }
        observedDisplayID = displayID
        sampleNow()
    }

    func start(onChange: @escaping (Bool) -> Void) {
        guard timer == nil else { return }
        self.onChange = onChange
        // A handler that has never been told anything is not "unchanged": the
        // panel has to be ordered to match the state that already holds, which
        // on a machine that launches into a full-screen app is concealed.
        hasReported = false

        let sampleWindows = self.sampleWindows
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            // The deadline is a budget with room in it, so let the system
            // coalesce this against whatever else it is already waking for.
            leeway: .milliseconds(50)
        )
        timer.setEventHandler { [weak self] in
            // The window list is read here, off the main thread; only the
            // comparison and the window order hop back.
            guard let ticket = self?.takeTicket() else { return }
            let windows = sampleWindows()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.consume(windows, ticket: ticket)
                }
            }
        }
        self.timer = timer
        timer.resume()

        sampleNow()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        onChange = nil
    }

    /// One sample on the current thread. The timer's path off the main thread
    /// ends in the same ``consume(_:ticket:)``.
    func sampleNow() {
        let ticket = takeTicket()
        consume(sampleWindows(), ticket: ticket)
    }

    /// Claims the next sequence number. `internal` because the ordering rule
    /// above is asserted directly rather than through a timer race.
    nonisolated func takeTicket() -> Int {
        ticketLock.lock()
        defer { ticketLock.unlock() }
        issuedTickets += 1
        return issuedTickets
    }

    func consume(_ windows: [ChromeWindow], ticket: Int) {
        guard ticket > lastConsumedTicket else { return }
        lastConsumedTicket = ticket

        let presence = observedDisplayID.map { displayID in
            let displayBounds = boundsOfDisplay(displayID)
            let reading = OverlayConcealment.menuBarPresence(
                onDisplay: displayBounds,
                windows: windows
            )

            // Only a displaced bar can be a neighbour's, so only a displaced
            // bar is worth the display list: `activeDisplayBounds()` costs
            // 214µs against 583µs for the window list itself (Release,
            // 3 displays), and asking on every tick would spend it four times a
            // second to answer a question that arises for a handful of samples
            // per Space switch.
            guard reading == .sliding else { return reading }

            return OverlayConcealment.menuBarPresence(
                onDisplay: displayBounds,
                windows: windows,
                otherDisplays: boundsOfActiveDisplays()
            )
        } ?? .drawn

        // A Space carrying the menu bar past is not an answer about
        // concealment. Hold the last one -- except when there is no last one,
        // where the same fail-open rule as an unplaceable display applies and
        // the overlay is left on screen.
        if presence == .sliding, hasReported { return }

        let isConcealed = presence == .away

        guard !hasReported || isConcealed != lastReported else { return }
        hasReported = true
        lastReported = isConcealed
        self.isConcealed = isConcealed
        onChange?(isConcealed)
    }
}
