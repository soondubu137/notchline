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

/// Why the overlay is off screen, or `nil` when it belongs on screen.
nonisolated enum OverlayConcealmentReason: Equatable, Sendable {
    /// The display's menu bar is not drawn: a full-screen window has taken the
    /// whole display, or the user has the menu bar set to hide automatically.
    case menuBarHidden
    /// Mission Control — or one of its relatives, App Exposé and the Spaces
    /// switcher — has covered the display.
    case missionControl
}

/// Whether the overlay should be on a given display right now.
///
/// The overlay sits at `.statusBar`, one level above the menu bar, so the
/// window server never takes it away: it stayed in the notch over full-screen
/// video and floated over Mission Control's zoomed-out desktops. The rule the
/// product wants is "be present exactly where the menu bar is present", and it
/// has to be enforced here because **nothing publishes it**. Every obvious API
/// was measured on macOS 26.5 and reports the asking process's own state, not
/// the system's:
///
/// | Signal | Another app full-screen | Mission Control |
/// | --- | --- | --- |
/// | `NSApp.currentSystemPresentationOptions` | `0`, unchanged | `0`, unchanged |
/// | `NSMenu.menuBarVisible()` | `true`, unchanged | `true`, unchanged |
/// | `NSScreen.visibleFrame` / `.safeAreaInsets` / `.auxiliaryTopLeftArea` | unchanged | unchanged |
/// | `NSWorkspace.activeSpaceDidChangeNotification` | never fired | never fired |
/// | Window Server's own menu bar window | **leaves the on-screen list** | present |
/// | Dock's full-display covers below dock level | absent | **appear, one per display** |
///
/// The last two rows are the only two that move, which is why this reads the
/// window list. The right-hand column is also the correction to the premise:
/// **Mission Control does not hide the menu bar.** It is drawn over the zoomed
/// desktops exactly as usual, so a rule written only as "follow the menu bar"
/// leaves the overlay floating over Mission Control — the case that prompted
/// the change. It gets its own clause.
nonisolated enum OverlayConcealment {
    /// The window server's own process, as it names itself in the window list.
    static let windowServerOwner = "Window Server"
    static let dockOwner = "Dock"
    /// `24` and `20`. The menu bar window sits at the level named for it; the
    /// Dock's own backing window sits at the Dock's.
    static let menuBarLayer = Int(CGWindowLevelForKey(.mainMenuWindow))
    static let dockLayer = Int(CGWindowLevelForKey(.dockWindow))
    /// Point tolerance when matching a window against a display.
    ///
    /// These rects come from the same window server that placed the display, so
    /// they agree exactly; this only absorbs a fractional scale conversion.
    static let matchTolerance: CGFloat = 1

    static func reason(
        onDisplay displayBounds: CGRect,
        windows: [ChromeWindow]
    ) -> OverlayConcealmentReason? {
        // Fail open. A display with no usable bounds is one this cannot judge,
        // and of the two ways to be wrong — an overlay that lingers over a
        // film, and an overlay that is simply gone with no way to ask for it
        // back — only the second loses the product.
        guard displayBounds.width >= 1, displayBounds.height >= 1 else {
            return nil
        }

        let hasMenuBar = windows.contains { window in
            window.owner == windowServerOwner
                && window.layer == menuBarLayer
                && matches(
                    origin: window.bounds,
                    displayBounds: displayBounds
                )
                && abs(window.bounds.width - displayBounds.width)
                    <= matchTolerance
        }

        guard hasMenuBar else { return .menuBarHidden }

        // Mission Control lays one Dock-owned window over each display, below
        // the Dock's own level (measured at 18, which has no name in
        // `CGWindowLevelKey`). The bound is written as "under the Dock" rather
        // than as that number because the Dock's *own* window is the one thing
        // that has to be excluded here: it is also Dock-owned and also the size
        // of its display, and it is there the whole time.
        let isCovered = windows.contains { window in
            window.owner == dockOwner
                && window.layer > 0
                && window.layer < dockLayer
                && matches(
                    origin: window.bounds,
                    displayBounds: displayBounds
                )
                && abs(window.bounds.width - displayBounds.width)
                    <= matchTolerance
                && abs(window.bounds.height - displayBounds.height)
                    <= matchTolerance
        }

        return isCovered ? .missionControl : nil
    }

    private static func matches(
        origin: CGRect,
        displayBounds: CGRect
    ) -> Bool {
        abs(origin.minX - displayBounds.minX) <= matchTolerance
            && abs(origin.minY - displayBounds.minY) <= matchTolerance
    }

    /// The on-screen windows, as this process can see them.
    ///
    /// `.excludeDesktopElements` drops the wallpaper and backstop windows,
    /// which neither clause consults; it costs 583µs against 723µs for the
    /// unfiltered list, measured in Release with 61 windows on screen.
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
/// no workspace, distributed or application notification fires for either
/// transition, so an edge-triggered version of this would simply never fire.
///
/// The cost is one `CGWindowListCopyWindowInfo` per interval, on a utility
/// queue, and **nothing downstream re-renders**: the report is compared against
/// the last one and dropped when equal, and the only thing a change does is
/// order a window in or out. Neither the store nor any SwiftUI view sees the
/// tick, which is what keeps this outside the rule in `AGENTS.md` §7.
@MainActor
final class OverlayConcealmentWatcher {
    /// 250 ms.
    ///
    /// This is a latency budget, not a sampling rate: it is how long the
    /// overlay may still be on screen after Mission Control starts to open —
    /// the tighter of the two cases, since its zoom-out runs about 350 ms and
    /// the menu bar's own fade is slower than that. At 583µs a sample it costs
    /// 0.23% of one core, measured in Release.
    nonisolated static let defaultInterval: TimeInterval = 0.25

    private let interval: TimeInterval
    private let sampleWindows: @Sendable () -> [ChromeWindow]
    private let boundsOfDisplay: @Sendable (CGDirectDisplayID) -> CGRect
    private let queue = DispatchQueue(
        label: "com.yinfenglu.Notchline.overlay-concealment",
        qos: .utility
    )

    private var timer: DispatchSourceTimer?
    private var observedDisplayID: CGDirectDisplayID?
    private var lastReported: OverlayConcealmentReason?
    private var hasReported = false
    private var onChange: ((OverlayConcealmentReason?) -> Void)?

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

    private(set) var reason: OverlayConcealmentReason?

    init(
        interval: TimeInterval = OverlayConcealmentWatcher.defaultInterval,
        sampleWindows: @escaping @Sendable () -> [ChromeWindow] =
            OverlayConcealment.currentWindows,
        boundsOfDisplay: @escaping @Sendable (CGDirectDisplayID) -> CGRect = {
            CGDisplayBounds($0)
        }
    ) {
        self.interval = interval
        self.sampleWindows = sampleWindows
        self.boundsOfDisplay = boundsOfDisplay
    }

    deinit {
        timer?.cancel()
    }

    /// Which display the overlay is on. A display this cannot identify — the
    /// fallback path in ``DisplayOption/identifier(for:)`` — reports revealed,
    /// per the fail-open rule on ``OverlayConcealment/reason(onDisplay:windows:)``.
    func observe(displayID: CGDirectDisplayID?) {
        guard observedDisplayID != displayID else { return }
        observedDisplayID = displayID
        sampleNow()
    }

    func start(onChange: @escaping (OverlayConcealmentReason?) -> Void) {
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

        let reason = observedDisplayID.flatMap { displayID in
            OverlayConcealment.reason(
                onDisplay: boundsOfDisplay(displayID),
                windows: windows
            )
        }

        guard !hasReported || reason != lastReported else { return }
        hasReported = true
        lastReported = reason
        self.reason = reason
        onChange?(reason)
    }
}
