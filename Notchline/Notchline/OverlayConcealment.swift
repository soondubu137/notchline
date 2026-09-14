import AppKit

/// `bounds` is in the window server's y-flipped global space (`CGWindowListCopyWindowInfo`,
/// `CGDisplayBounds`), not `NSScreen.frame`'s, which mismatch displays not all at y = 0.
nonisolated struct ChromeWindow: Equatable, Sendable {
    let owner: String
    let layer: Int
    let bounds: CGRect
}

/// What the window server is doing with a display's menu bar. A Space switch slides it for
/// ~850 ms (3.5 s in a held swipe, measured).
nonisolated enum MenuBarPresence: Equatable, Sendable {
    /// On its own display; the overlay belongs there too.
    case drawn
    /// Carried off the display by a Space transition. Nothing is settled, so nothing moves.
    case sliding
    /// Not drawn: a full-screen window has the display, or an auto-hiding menu bar is away.
    case away
}

/// Whether the overlay should be on a given display right now: exactly where the menu bar is.
///
/// The overlay is at `.statusBar`, so the window server never hides it, and nothing publishes the
/// bar's state (macOS 26.5): `currentSystemPresentationOptions`, `menuBarVisible()` and `NSScreen`
/// frames stay unchanged under another app's full-screen and Mission Control, and
/// `activeSpaceDidChangeNotification` fires only once a switch is over. The Window Server's menu
/// bar window leaves the on-screen list under full-screen; a Space switch only slides it
/// (`x: 0 → -1864` on an 1800pt display, 2026-08-24) with the overlay, so a slide is not hidden.
/// Mission Control keeps the bar, and the overlay.
nonisolated enum OverlayConcealment {
    static let windowServerOwner = "Window Server"
    /// `24`.
    static let menuBarLayer = Int(CGWindowLevelForKey(.mainMenuWindow))
    /// Absorbs only fractional scale conversion; both rects come from the window server.
    static let matchTolerance: CGFloat = 1

    /// A menu bar window sharing this display's top edge and width: ``drawn`` at its origin,
    /// ``sliding`` elsewhere, ``away`` if none.
    ///
    /// - Parameter otherDisplays: a bar at a neighbour's origin is the neighbour's, not this one
    ///   mid-slide. Including this display is harmless.
    static func menuBarPresence(
        onDisplay displayBounds: CGRect,
        windows: [ChromeWindow],
        otherDisplays: [CGRect] = []
    ) -> MenuBarPresence {
        // Fail open: an overlay lingering over a film is better than one gone with no way back.
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

    /// Window-server coordinates, not `NSScreen.screens` (see ``ChromeWindow``), so
    /// ``menuBarPresence(onDisplay:windows:otherDisplays:)`` can recognise a neighbour's bar.
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

    /// `.excludeDesktopElements`: 583µs vs 723µs (Release, 61 windows). Owner, layer and bounds are
    /// readable without Screen Recording; `kCGWindowName` is not, so the bar is matched by owner/level.
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

/// Polls ``OverlayConcealment`` for one display and reports only changes: no notification fires
/// when another app goes full-screen.
///
/// Compared off the main actor and nothing re-renders (`AGENTS.md` §7); parks with no screen and
/// fails open, restoring the overlay (``OverlayConcealmentWatcher/park()``). A
/// ``MenuBarPresence/sliding`` sample is not reported, so the overlay rides a Space switch.
@MainActor
final class OverlayConcealmentWatcher {
    /// 250 ms: how long the overlay may linger after the menu bar goes. 530µs a sample (0.21% of a
    /// core, Release), paid only while a screen exists (``park()``).
    nonisolated static let defaultInterval: TimeInterval = 0.25

    /// 60 s fail-safe for a missed screen-return notification (two of five are distributed).
    /// 107µs a minute.
    nonisolated static let defaultParkedInterval: TimeInterval = 60

    private let interval: TimeInterval
    private let parkedInterval: TimeInterval
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
    /// Watches for the screen coming back, the only edge that un-parks. Going away is read at the
    /// tick, so both halves share one reading (``ScreenAvailabilityReporting``).
    private var wakeTask: Task<Void, Never>?
    /// Ticks per second, at least one. Resolved once so the timer's queue reads it without a hop.
    private nonisolated let screenReadEveryNTicks: Int

    /// Everything the sampling path decides with, behind one lock.
    ///
    /// Judged on the timer's queue so the main actor wakes only when the answer changes (a hop
    /// per tick was 4 wake-ups/s). The lock guards the timer against ``sampleNow()``.
    private let decisionLock = NSLock()
    private nonisolated(unsafe) var state = SamplingState()

    private struct SamplingState {
        /// Issued when a sample is taken, so an overtaken sample is discarded: a timer reading from
        /// before a display change must not blink the overlay out for 250 ms.
        var issuedTickets = 0
        var judgedTicket = 0
        /// Mirrored here because the verdict is reached off the main actor.
        var observedDisplayID: CGDirectDisplayID?
        var lastReported = false
        var hasReported = false
        /// Ticks since the screen was last read, so it is read at ~1 Hz whatever the interval.
        var ticksSinceScreenRead = 0
        /// Read on the timer's queue so a parked tick can tell when the screen is back.
        var isParked = false
    }

    /// The ticket of the last verdict put on the panel, so an overtaken one is dropped.
    ///
    /// ``sampleNow()`` judges and applies inline, ahead of a timer hop already queued. Without
    /// this the older verdict lands last against a ``SamplingState/lastReported`` describing the
    /// newer one, and the overlay stays gone for the life of the process (hit at the wake edge).
    private var lastAppliedTicket = 0

    private(set) var isConcealed = false

    init(
        interval: TimeInterval = OverlayConcealmentWatcher.defaultInterval,
        parkedInterval: TimeInterval =
            OverlayConcealmentWatcher.defaultParkedInterval,
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
        self.parkedInterval = parkedInterval
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

    /// A display this cannot identify reports revealed (fail-open, see
    /// ``OverlayConcealment/isConcealed(onDisplay:windows:)``).
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
        // Never-reported is not "unchanged": the panel must match the current state, which is
        // concealed when launching into a full-screen app.
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

    /// One sample on the current thread. A screen nobody can see is not sampled (see ``park()``).
    func sampleNow() {
        guard screenAvailability.isAvailable() else {
            armOrPark()
            return
        }
        deliver(sampleWindows(), ticket: takeTicket())
    }

    /// One reading judged and, when the answer changed, applied. `internal` so the ordering rule
    /// can be tested without a live timer.
    func deliver(_ windows: [ChromeWindow], ticket: Int) {
        guard let concealed = verdict(for: windows, ticket: ticket) else {
            return
        }
        apply(concealed, ticket: ticket)
    }

    /// Claims the next sequence number. `internal` for the ordering tests.
    nonisolated func takeTicket() -> Int {
        decisionLock.withLock {
            state.issuedTickets += 1
            return state.issuedTickets
        }
    }

    // MARK: - Sampling

    /// One tick, on the timer's queue unless the answer changed.
    ///
    /// - The screen is read at ~1 Hz, not per tick: 107µs vs the window list's 530µs (Release,
    ///   2026-08-25), but at 4 Hz it raised Mach traffic from 71/s to 107/s.
    /// - The first tick after arming reads it, so a park is never deferred.
    /// - A parked tick reads only the screen, once per ``defaultParkedInterval``: the fail-safe
    ///   for a missed notification.
    /// - Reading only on ``ScreenAvailabilityReporting/changeEvents()`` edges would widen that
    ///   stream's contract, shared with both monitor services; not done.
    nonisolated private func tick() {
        let (isParked, isDueToReadScreen) = decisionLock
            .withLock { () -> (Bool, Bool) in
                state.ticksSinceScreenRead += 1
                // A parked tick is the screen reading, so it never waits out the counter.
                let isDue = state.isParked
                    || state.ticksSinceScreenRead >= screenReadEveryNTicks
                if isDue { state.ticksSinceScreenRead = 0 }
                return (state.isParked, isDue)
            }

        if isDueToReadScreen {
            let isScreenAvailable = screenAvailability.isAvailable()
            // Only a crossing changes the schedule; a parked tick still without a screen stays off main.
            if isScreenAvailable == isParked {
                hopToMain { $0.armOrPark() }
            }
            guard isScreenAvailable else { return }
        }

        // Window list and verdict are read off the main thread; only a changed verdict hops.
        let ticket = takeTicket()
        guard let concealed = verdict(for: sampleWindows(), ticket: ticket)
        else {
            return
        }
        hopToMain { $0.apply(concealed, ticket: ticket) }
    }

    /// `DispatchQueue.main.async`, not `Task { @MainActor }`: two `Task`s from one serial queue
    /// are not guaranteed to run in order, and swapped verdicts leave the panel wrong until the
    /// next flip. Verdicts reached on the main actor do not queue behind these; see
    /// ``lastAppliedTicket``.
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

    /// The verdict for one reading, or nil when overtaken, when the Space is carrying the menu
    /// bar past, or when unchanged. `internal` so the gap before ``apply(_:ticket:)`` is testable.
    nonisolated func verdict(
        for windows: [ChromeWindow],
        ticket: Int
    ) -> Bool? {
        let displayID = decisionLock.withLock { state.observedDisplayID }
        let presence = displayID.map { displayID in
            let displayBounds = boundsOfDisplay(displayID)
            let reading = OverlayConcealment.menuBarPresence(
                onDisplay: displayBounds,
                windows: windows
            )

            // Only a displaced bar needs the display list: `activeDisplayBounds()` costs 214µs vs 530µs
            // for the window list (Release, 3 displays).
            guard reading == .sliding else { return reading }

            return OverlayConcealment.menuBarPresence(
                onDisplay: displayBounds,
                windows: windows,
                otherDisplays: boundsOfActiveDisplays()
            )
        } ?? .drawn

        return decisionLock.withLock { () -> Bool? in
            guard ticket > state.judgedTicket else { return nil }

            // `.sliding` answers nothing: hold the last verdict (fail-open if none) and leave the ticket
            // unclaimed so an earlier reading can still answer.
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

    /// Puts a changed verdict on the panel unless a later one is already there. `internal` for
    /// tests.
    func apply(_ concealed: Bool, ticket: Int) {
        guard ticket > lastAppliedTicket else { return }
        lastAppliedTicket = ticket
        isConcealed = concealed
        onChange?(concealed)
    }

    // MARK: - Screen availability

    private func armOrPark() {
        guard timer != nil else { return }
        if screenAvailability.isAvailable() {
            arm()
        } else {
            park()
        }
    }

    private func arm() {
        guard let timer else { return }
        decisionLock.withLock {
            state.isParked = false
            // Read the screen on the next tick so a park is never deferred.
            state.ticksSinceScreenRead = screenReadEveryNTicks
        }
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(50)
        )
    }

    /// Drops the timer to the heartbeat, forgets the last verdict, and reveals the overlay.
    ///
    /// - Reveals on the way out: a `concealed` held into a dark or locked screen can leave the
    ///   overlay gone with no Dock tile, menu bar item or window to summon it. Fail-open, at the
    ///   cost of one sample over a full-screen window after wake.
    /// - Forgets ``SamplingState/lastReported`` so the first sample after waking into a
    ///   full-screen app is not taken as unchanged.
    /// - Reschedules rather than `suspend()`: an unbalanced `DispatchSourceTimer` traps on
    ///   deallocation.
    private func park() {
        guard let timer else { return }
        decisionLock.withLock {
            state.isParked = true
            state.hasReported = false
        }
        timer.schedule(
            deadline: .now() + parkedInterval,
            repeating: parkedInterval,
            leeway: .seconds(15)
        )
        guard isConcealed else { return }
        apply(false, ticket: takeTicket())
    }

    /// Re-arms on the screen coming back and samples immediately: windows may have changed while
    /// the display slept.
    ///
    /// Arms without consulting the reading: `screensDidWake` arrives while the session is still
    /// locked, and an unlock is posted by `loginwindow`, not the session dictionary behind
    /// ``ScreenAvailabilityReporting/isAvailable()``. The first tick re-parks if needed.
    private func observeScreenAvailability() {
        let events = screenAvailability.changeEvents()
        wakeTask = Task { @MainActor [weak self] in
            for await _ in events {
                guard let self, !Task.isCancelled else { return }
                self.arm()
                self.sampleNow()
            }
        }
    }
}
