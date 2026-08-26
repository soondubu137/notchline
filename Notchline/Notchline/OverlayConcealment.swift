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
/// **Two things bound that cost, and neither was here originally.** The
/// comparison happens on the sampling queue rather than on the main actor, so
/// an unchanged reading — which is nearly all of them — never wakes the main
/// run loop at all; and the timer is parked outright whenever there is no
/// screen, because a menu bar nobody can see cannot conceal anything. Together
/// they take this from the single largest steady-state cost in the process —
/// 41% of its CPU, and four main-thread wake-ups a second for the life of the
/// app — to something that runs only while somebody is looking. See
/// ``OverlayConcealmentWatcher/tick()`` and
/// ``OverlayConcealmentWatcher/armOrPark()`` for the measurements.
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
    /// be. It is kept because a sample costs 530µs — 0.21% of one core,
    /// measured in Release — and there is nothing to buy by spending less.
    ///
    /// **The budget is what it costs while somebody is there.** It used to be
    /// what it cost always: the timer was armed in ``start(onChange:)`` and
    /// never stopped, so an idle machine paid the same 0.21% through a locked
    /// night, and a `sample` of the live app put 41% of the whole process's CPU
    /// in this one call. It is now parked whenever there is no screen — see
    /// ``armOrPark()``.
    nonisolated static let defaultInterval: TimeInterval = 0.25

    private let interval: TimeInterval
    private let sampleWindows: @Sendable () -> [ChromeWindow]
    private let boundsOfDisplay: @Sendable (CGDirectDisplayID) -> CGRect
    private let boundsOfActiveDisplays: @Sendable () -> [CGRect]
    private let screenAvailability: any ScreenAvailabilityReporting
    private let queue = DispatchQueue(
        label: "com.yinfenglu.Notchline.overlay-concealment",
        qos: .utility
    )

    private var timer: DispatchSourceTimer?
    private var onChange: ((Bool) -> Void)?
    /// Watches for the screen coming back, which is the only edge that can
    /// un-park the timer. Nothing watches for it going away: that is read at
    /// the tick, because the reading is the one the gate is written in terms of
    /// and a second set of notifications meaning the same thing is how the two
    /// halves drift apart (``ScreenAvailabilityReporting``).
    private var wakeTask: Task<Void, Never>?
    /// How many ticks one second of them is, and never fewer than one.
    /// Resolved once so the timer's queue can read it without a hop.
    private nonisolated let screenReadEveryNTicks: Int

    /// Everything the sampling path decides with, behind one lock.
    ///
    /// **All of it moved off the main actor together, and that is the point.**
    /// The timer used to hop to the main actor on every tick and decide there,
    /// so the main run loop could never sleep longer than the interval — four
    /// wake-ups a second, 345,600 of them in twelve hours, to answer "no
    /// change" almost every time. The reading is now judged on the timer's own
    /// queue and the hop happens only when the answer has actually changed,
    /// which on a normal day is a few times an hour.
    ///
    /// The lock is not for the timer against itself — the queue is serial — but
    /// for the timer against ``sampleNow()``, which the panel calls on the main
    /// actor the moment it moves to another display.
    private let decisionLock = NSLock()
    private nonisolated(unsafe) var state = SamplingState()

    /// The state ``judge(_:ticket:)`` reads and writes, and nothing else.
    private struct SamplingState {
        /// Sequence numbers handed out when a sample is *taken*, so that a
        /// sample which was overtaken on its way to a verdict is discarded
        /// instead of reported.
        ///
        /// Two things sample: the timer, on its own queue, and ``sampleNow()``,
        /// which the panel calls the moment it moves to another display. A
        /// timer reading taken before a display change must not be allowed to
        /// answer for the display after it, or the overlay would blink out and
        /// back for the 250 ms until the next sample corrected it.
        var issuedTickets = 0
        var judgedTicket = 0
        /// Which display the overlay is on. Mirrored here rather than kept on
        /// the main actor because the verdict is now reached off it.
        var observedDisplayID: CGDirectDisplayID?
        var lastReported = false
        var hasReported = false
        /// Ticks since the screen was last read, so it is read at about 1 Hz
        /// however short the sampling interval is. Under the lock with the
        /// rest: the timer's queue counts them and the main actor resets them
        /// when it arms.
        var ticksSinceScreenRead = 0
    }

    private(set) var isConcealed = false

    init(
        interval: TimeInterval = OverlayConcealmentWatcher.defaultInterval,
        sampleWindows: @escaping @Sendable () -> [ChromeWindow] =
            OverlayConcealment.currentWindows,
        boundsOfDisplay: @escaping @Sendable (CGDirectDisplayID) -> CGRect = {
            CGDisplayBounds($0)
        },
        boundsOfActiveDisplays: @escaping @Sendable () -> [CGRect] =
            OverlayConcealment.activeDisplayBounds,
        screenAvailability: any ScreenAvailabilityReporting =
            ScreenAvailabilityWatcher()
    ) {
        self.interval = interval
        self.screenReadEveryNTicks = max(1, Int((1.0 / interval).rounded()))
        self.sampleWindows = sampleWindows
        self.boundsOfDisplay = boundsOfDisplay
        self.boundsOfActiveDisplays = boundsOfActiveDisplays
        self.screenAvailability = screenAvailability
    }

    deinit {
        timer?.cancel()
        wakeTask?.cancel()
    }

    /// Which display the overlay is on. A display this cannot identify — the
    /// fallback path in ``DisplayOption/identifier(for:)`` — reports revealed,
    /// per the fail-open rule on
    /// ``OverlayConcealment/isConcealed(onDisplay:windows:)``.
    func observe(displayID: CGDirectDisplayID?) {
        let changed = decisionLock.withLock { () -> Bool in
            guard state.observedDisplayID != displayID else { return false }
            state.observedDisplayID = displayID
            return true
        }
        guard changed else { return }
        sampleNow()
    }

    func start(onChange: @escaping (Bool) -> Void) {
        guard timer == nil else { return }
        self.onChange = onChange
        // A handler that has never been told anything is not "unchanged": the
        // panel has to be ordered to match the state that already holds, which
        // on a machine that launches into a full-screen app is concealed.
        decisionLock.withLock { state.hasReported = false }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        armOrPark()
        timer.resume()
        observeScreenAvailability()

        sampleNow()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        wakeTask?.cancel()
        wakeTask = nil
        onChange = nil
    }

    /// One sample on the current thread. The timer's path off the main thread
    /// ends in the same ``deliver(_:ticket:)``.
    func sampleNow() {
        deliver(sampleWindows(), ticket: takeTicket())
    }

    /// One reading judged and, when it changed the answer, put on the panel.
    ///
    /// The whole of what a tick does once it has its windows, so that the
    /// ordering rule ``judge(_:ticket:)`` enforces can be asserted directly
    /// rather than through a race with a live timer. `internal` for that
    /// reason and no other.
    func deliver(_ windows: [ChromeWindow], ticket: Int) {
        guard let concealed = judge(windows, ticket: ticket) else { return }
        apply(concealed)
    }

    /// Claims the next sequence number. `internal` because the ordering rule
    /// above is asserted directly rather than through a timer race.
    nonisolated func takeTicket() -> Int {
        decisionLock.withLock {
            state.issuedTickets += 1
            return state.issuedTickets
        }
    }

    // MARK: - Sampling

    /// One tick, entirely on the timer's own queue unless the answer changed.
    ///
    /// **The screen is read about once a second, not on every tick.** The
    /// reading is 107µs against the window list's 530µs (Release, 2026-08-25),
    /// and it is not free in the way that ratio suggests: like the window list
    /// it is a round trip to the window server, so taken four times a second it
    /// was measured adding half again to this process's Mach traffic — 71/s to
    /// 107/s — for a state that changes a few times a day. Sampled at 1 Hz the
    /// surcharge is 0.011% of a core and the park is at most a second late,
    /// which cannot cost anything: there is nothing on screen to be wrong.
    ///
    /// The first tick after arming reads it, so a park is never deferred behind
    /// a counter that has just been reset.
    ///
    /// (The zero-surcharge version is to have
    /// ``ScreenAvailabilityReporting/changeEvents()`` fire in *both*
    /// directions and read only on its edges. It is deliberately not done here:
    /// that stream is shared with both monitor services, and widening its
    /// contract is a change to their refresh behaviour rather than to this
    /// file. This poll is also the fail-safe if a notification is ever missed.)
    nonisolated private func tick() {
        let isDueToReadScreen = decisionLock.withLock { () -> Bool in
            state.ticksSinceScreenRead += 1
            guard state.ticksSinceScreenRead >= screenReadEveryNTicks else {
                return false
            }
            state.ticksSinceScreenRead = 0
            return true
        }
        if isDueToReadScreen, !screenAvailability.isAvailable() {
            hopToMain { $0.armOrPark() }
            return
        }
        // The window list is read here, off the main thread, and so is the
        // verdict. Only a *changed* verdict hops.
        let ticket = takeTicket()
        guard let concealed = judge(sampleWindows(), ticket: ticket) else {
            return
        }
        hopToMain { $0.apply(concealed) }
    }

    /// The one way off this queue, and it is `DispatchQueue.main.async`
    /// rather than a `Task { @MainActor }` deliberately.
    ///
    /// Two `Task`s enqueued from the same serial queue are **not** guaranteed
    /// to run in that order, and what travels this way is a sequence of
    /// verdicts: apply `concealed` and `revealed` the wrong way round and the
    /// panel stays wrong until the next flip. The ticket in
    /// ``judge(_:ticket:)`` cannot save that — it orders the *judging*, and by
    /// here the judging is over. The main queue is FIFO, so it can.
    nonisolated private func hopToMain(
        _ body: @escaping @MainActor (OverlayConcealmentWatcher) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                body(self)
            }
        }
    }

    /// The verdict for one reading, or nil when there is nothing to report.
    ///
    /// Nil covers three cases that all mean "do not disturb the panel": the
    /// reading was overtaken by a later one, the Space is still carrying the
    /// menu bar past, and the answer is the one already reported.
    nonisolated private func judge(
        _ windows: [ChromeWindow],
        ticket: Int
    ) -> Bool? {
        let displayID = decisionLock.withLock { state.observedDisplayID }
        let presence = displayID.map { displayID in
            let displayBounds = boundsOfDisplay(displayID)
            let reading = OverlayConcealment.menuBarPresence(
                onDisplay: displayBounds,
                windows: windows
            )

            // Only a displaced bar can be a neighbour's, so only a displaced
            // bar is worth the display list: `activeDisplayBounds()` costs
            // 214µs against 530µs for the window list itself (Release,
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

        return decisionLock.withLock { () -> Bool? in
            guard ticket > state.judgedTicket else { return nil }

            // A Space carrying the menu bar past is not an answer about
            // concealment. Hold the last one -- except when there is no last
            // one, where the same fail-open rule as an unplaceable display
            // applies and the overlay is left on screen. The ticket is
            // deliberately *not* claimed: this reading answered nothing, so a
            // reading taken before it must still be free to answer.
            if presence == .sliding, state.hasReported { return nil }

            state.judgedTicket = ticket
            let isConcealed = presence == .away
            guard !state.hasReported || isConcealed != state.lastReported else {
                return nil
            }
            state.hasReported = true
            state.lastReported = isConcealed
            return isConcealed
        }
    }

    /// Puts a changed verdict on the panel. The only part still on the main
    /// actor, and the only part that has to be.
    private func apply(_ concealed: Bool) {
        isConcealed = concealed
        onChange?(concealed)
    }

    // MARK: - Screen availability

    /// Arms the timer while there is a screen and parks it while there is not.
    ///
    /// Parked by rescheduling to `.distantFuture` rather than by
    /// `suspend()`: the two have the same effect on wake-ups and only one of
    /// them has to be balanced, and an unbalanced `DispatchSourceTimer` traps
    /// on deallocation.
    private func armOrPark() {
        guard let timer else { return }
        guard screenAvailability.isAvailable() else {
            timer.schedule(deadline: .distantFuture, repeating: .never)
            return
        }
        // The next tick reads the screen rather than waiting out a counter
        // that has just been reset, so a park is never deferred.
        decisionLock.withLock { state.ticksSinceScreenRead = screenReadEveryNTicks }
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            // The deadline is a budget with room in it, so let the system
            // coalesce this against whatever else it is already waking for.
            leeway: .milliseconds(50)
        )
    }

    /// Re-arms on the screen coming back, and samples immediately.
    ///
    /// The sample matters as much as the arming: the display slept on one
    /// arrangement of windows and can wake on another — a full-screen app
    /// entered from another machine over screen sharing, a Space switched by a
    /// lock screen — and waiting a whole interval to notice would show the
    /// overlay over a menu bar that is not there.
    private func observeScreenAvailability() {
        let events = screenAvailability.changeEvents()
        wakeTask = Task { @MainActor [weak self] in
            for await _ in events {
                guard let self, !Task.isCancelled else { return }
                self.armOrPark()
                self.sampleNow()
            }
        }
    }
}
