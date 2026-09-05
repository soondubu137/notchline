import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayPanelController {
    private let store: MonitorStore
    private let panel: OverlayPanel
    private var cancellables = Set<AnyCancellable>()
    private var screenParametersObserver: NSObjectProtocol?
    private var pendingFrameUpdate: DispatchWorkItem?
    private var pendingFrameUpdateShouldAnimate: Bool?
    /// A frame animation waiting out a closing wing's lead-out — see
    /// ``animateFrame(to:delay:)``.
    private var pendingFrameAnimation: DispatchWorkItem?
    private var hasShownPanel = false
    /// Non-nil while one `mouseEntered` is owed — see ``armPointerReentry()``.
    private var pointerReentryMonitor: Any?
    private let concealmentWatcher: OverlayConcealmentWatcher
    /// Whether the panel is off screen because its display's menu bar is.
    ///
    /// Held here rather than on ``MonitorStore`` on purpose. Concealment is not
    /// something the panel *draws* — the view tree is identical either side of
    /// it — so publishing it would re-evaluate the whole overlay to change
    /// nothing, which is the cost `AGENTS.md` §7 exists to keep out. The only
    /// effect is `orderOut`/`orderFrontRegardless` on this window.
    private var isConcealed = false

    init(
        store: MonitorStore,
        concealmentWatcher: OverlayConcealmentWatcher? = nil
    ) {
        self.store = store
        self.concealmentWatcher = concealmentWatcher ?? OverlayConcealmentWatcher()
        self.panel = OverlayPanel(
            contentRect: NSRect(
                origin: .zero,
                size: store.currentPanelSize
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        bindStore()
        observeScreenChanges()
        observeConcealment()
    }

    deinit {
        pendingFrameUpdate?.cancel()
        pendingFrameAnimation?.cancel()
        if let pointerReentryMonitor {
            NSEvent.removeMonitor(pointerReentryMonitor)
        }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
    }

    func show() {
        updatePanelFrame(animated: false)
        hasShownPanel = true
        orderPanelToMatchConcealment()
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        // Setting isFloatingPanel resets an NSPanel to the floating level (3).
        // Apply statusBar last so the compact UI stays above the menu bar (24).
        panel.level = .statusBar
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        panel.animationBehavior = .none

        let hostingView = NSHostingView(
            rootView: NotchOverlayView()
                .environmentObject(store)
        )
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: store.currentPanelSize)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
    }

    private func bindStore() {
        let animatedChanges = Self.frameChangingPublishers(of: store)

        Publishers.MergeMany(animatedChanges)
            .dropFirst(animatedChanges.count)
            .sink { [weak self] in
                self?.schedulePanelFrameUpdate(animated: true)
            }
            .store(in: &cancellables)

        store.$selectedDisplayID
            .dropFirst()
            .sink { [weak self] _ in
                self?.schedulePanelFrameUpdate(animated: false)
            }
            .store(in: &cancellables)

        store.$displays
            .dropFirst()
            .sink { [weak self] _ in
                self?.schedulePanelFrameUpdate(animated: false)
            }
            .store(in: &cancellables)

        // The overlay follows the menu bar of the display it is actually on, so
        // a full-screen film on one screen leaves the other two alone. Both
        // publishers can move the panel to a different display, and @Published
        // emits from willSet, so the new selection is read a turn later.
        Publishers.Merge(
            store.$selectedDisplayID.map { _ in () },
            store.$displays.map { _ in () }
        )
        .dropFirst(2)
        .sink { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.concealmentWatcher.observe(
                    displayID: self.store.selectedDisplay?.displayID
                )
            }
        }
        .store(in: &cancellables)
    }

    /// Every publish that can move ``MonitorStore/currentPanelSize``.
    ///
    /// **Enumerated rather than taken from `store.objectWillChange`**, because
    /// the window is recomputed when the *layout* changed and not when the
    /// content did (`AGENTS.md` §7): the size is measured from the elapsed
    /// string and the mark count, and asking for it on every publish would put
    /// that measurement on the path of every state this store holds, most of
    /// which no edge answers to.
    ///
    /// **The enumeration is what goes wrong, and it has four times now** — the
    /// wings, the marks, the quota table and the Recent queue each drew
    /// themselves into a window still sized for the state before, because each
    /// is a control nothing else republishes behind. It is not a list anybody
    /// can be trusted to keep, so the suite drives it instead: every state that
    /// moves the size has to arrive here, and
    /// `everyChangeThatMovesThePanelReachesTheWindow` fails on the first one
    /// that does not.
    ///
    /// Internal rather than private for that test alone.
    static func frameChangingPublishers(
        of store: MonitorStore
    ) -> [AnyPublisher<Void, Never>] {
        [
            store.$status.map { _ in () }.eraseToAnyPublisher(),
            store.$quota.map { _ in () }.eraseToAnyPublisher(),
            store.$sessions.map { _ in () }.eraseToAnyPublisher(),
            store.$isExpanded.map { _ in () }.eraseToAnyPublisher(),
            // Opening the quota table is a height change like any other: the
            // footer redraws itself, but only the panel can find the height the
            // table needs and give it back afterwards.
            store.$isQuotaExpanded.map { _ in () }.eraseToAnyPublisher(),
            // Opening what the list has let go of is the same kind of height
            // change, and it was the one publish this list forgot. The seam is
            // the only control on the surface that moves the panel's bottom
            // edge without moving anything else -- no status, no session, no
            // quota -- so the rows were drawn into a window still sized for the
            // folded queue, and the only way to see them was to close the panel
            // and open it again. Folding it left the same emptiness behind.
            store.$isRecentExpanded.map { _ in () }.eraseToAnyPublisher(),
            // And the queue's membership, which decides whether a seam is drawn
            // at all and how tall the open list is. It moves on its own twice:
            // a member ages out of the window under the store's tick, and a row
            // is taken out of the queue by its own click. Neither republishes
            // the session list, so neither would resize without this.
            store.$recentDepartures.map { _ in () }.eraseToAnyPublisher(),
            // Giving up the wings collapses the compact body to the cut-out and
            // takes them back again. Nothing else republishes when it is
            // toggled -- no status, no session, no quota moves -- so without
            // this the panel keeps whatever width it had until the next
            // unrelated change happened to resize it.
            store.$hidesCompactWings.map { _ in () }.eraseToAnyPublisher(),
            // The compact width is measured from the elapsed string, so the
            // panel has to re-measure when it gains a digit -- but only then.
            // The readouts advance themselves off a tick no SwiftUI view
            // observes; this fires when one of them changes width.
            store.$elapsedLayoutRevision.map { _ in () }.eraseToAnyPublisher(),
            // Both collapsed forms are measured from the marks -- the pill from
            // how many there are, the notched bar from how many are drawing a
            // session column -- and a product opening or closing with no rows
            // moves neither the status nor the session list. Without this the
            // second matrix is drawn into a window still sized for one, until
            // some unrelated publish happens to resize it.
            store.$presenceMarks.map { _ in () }.eraseToAnyPublisher()
        ]
    }

    private func schedulePanelFrameUpdate(animated: Bool) {
        // @Published emits from willSet. Defer until the next main-queue turn so
        // selectedDisplayID, geometry and isExpanded all describe the new state.
        if let existingAnimationChoice = pendingFrameUpdateShouldAnimate {
            // A screen change must stay immediate even if another visual change
            // lands in the same run-loop turn.
            pendingFrameUpdateShouldAnimate = existingAnimationChoice && animated
        } else {
            pendingFrameUpdateShouldAnimate = animated
        }
        guard pendingFrameUpdate == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let shouldAnimate = self.pendingFrameUpdateShouldAnimate ?? false
            self.pendingFrameUpdate = nil
            self.pendingFrameUpdateShouldAnimate = nil
            self.updatePanelFrame(animated: shouldAnimate)
        }
        pendingFrameUpdate = workItem
        // A run-loop hop, not a delay: this coalesces same-turn @Published
        // emissions and waits on no duration, so there is nothing for
        // MonitorClock to control.
        DispatchQueue.main.async(execute: workItem)
    }

    private func updatePanelFrame(animated: Bool) {
        guard let selectedDisplay = store.selectedDisplay else {
            return
        }

        let size = store.currentPanelSize
        let targetFrame = OverlayPanelLayout.frame(
            on: selectedDisplay.frame,
            panelSize: size,
            surfaceShoulder: store.surfaceShoulderRadius,
            trailingAnchor: store.currentPanelTrailingAnchor
        )

        guard panel.frame != targetFrame else {
            return
        }

        let previousFrame = panel.frame

        guard animated, hasShownPanel else {
            // An immediate move overtakes a wing that was still waiting to
            // close: that animation would otherwise fire afterwards and drag
            // the panel back towards a target this frame has superseded.
            pendingFrameAnimation?.cancel()
            pendingFrameAnimation = nil
            panel.setFrame(targetFrame, display: true)
            panel.contentView?.layoutSubtreeIfNeeded()
            // A concealed panel still tracks its frame — it has to be in the
            // right place the moment it comes back — but re-ordering it here
            // would put it back on screen over the full-screen window that
            // took the menu bar away.
            if hasShownPanel, !isConcealed {
                panel.orderFrontRegardless()
            }
            reconcilePointer(from: previousFrame, to: targetFrame)
            return
        }

        animateFrame(
            to: targetFrame,
            delay: OverlayPanelLayout.closingDelay(from: previousFrame, to: targetFrame)
        )

        // Asked of the frame the panel is heading for, not the one it is
        // leaving, and asked now rather than from the completion handler: the
        // destination is already known, and the collapse dwell should then run
        // alongside the resize the way it would have had the pointer walked
        // out. Waiting for the animation would also risk answering for a frame
        // a later update had already superseded. It is asked before any closing
        // delay for the same reason — the pointer's question is about where the
        // panel is going, not about when it sets off.
        reconcilePointer(from: previousFrame, to: targetFrame)
    }

    /// The window's half of ``PanelMotion/slot(isOpening:)``.
    ///
    /// AppKit's animation context has a duration and a curve but no delay, so a
    /// closing wing is scheduled rather than declared. The work item is held so
    /// a change arriving inside the delay supersedes it instead of firing a
    /// second animation towards a target that has already moved.
    private func animateFrame(to targetFrame: NSRect, delay: TimeInterval) {
        pendingFrameAnimation?.cancel()
        pendingFrameAnimation = nil

        let run = { [weak self] in
            guard let panel = self?.panel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = PanelMotion.duration
                context.timingFunction = PanelMotion.timingFunction
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(targetFrame, display: true)
            } completionHandler: { [weak panel] in
                panel?.contentView?.layoutSubtreeIfNeeded()
            }
        }

        guard delay > 0 else {
            run()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingFrameAnimation = nil
            run()
        }
        pendingFrameAnimation = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Re-answer "is the pointer on the panel?" now that the panel has moved.
    ///
    /// Two things go wrong when the window resizes away from a pointer that is
    /// standing still, and they are the same fact seen from either side.
    /// `.onHover` is an `NSTrackingArea`, which speaks only when the pointer
    /// *moves*: the exit is never delivered, so the store still thinks the
    /// panel is hovered, and the tracking area still thinks the pointer is
    /// inside it, so the next real entry is not reported either. The store is
    /// told to collapse, and the swallowed entry is made good by
    /// ``armPointerReentry()``.
    private func reconcilePointer(from previousFrame: NSRect, to targetFrame: NSRect) {
        let pointer = NSEvent.mouseLocation

        if OverlayPanelLayout.resizeStrandedPointer(
            pointer,
            from: previousFrame,
            to: targetFrame,
            surfaceShoulder: store.surfaceShoulderRadius
        ) {
            armPointerReentry()
        }

        store.panelResized(to: targetFrame, pointerAt: pointer)
    }

    /// Deliver the one `mouseEntered` the tracking area is going to swallow.
    ///
    /// The area's own idea of where the pointer is says "inside" while the
    /// pointer is in fact outside, so the next crossing back in changes nothing
    /// it can see and it stays silent. It resyncs on the crossing *out* after
    /// that, which is one hover too late: the first pass over the notch after a
    /// fold does nothing at all, and the panel only opens on the second.
    ///
    /// A global monitor is what the situation leaves. The pointer is somewhere
    /// this window is not, so no event of this window's can say when it comes
    /// back, and a timer would be the polling `AGENTS.md` §7 exists to keep
    /// out. Measured: the monitor does see moves over this panel, because a
    /// non-activating panel that never becomes key is not where a mouse-moved
    /// event is delivered. It runs one rectangle test and draws nothing, and it
    /// is armed only between a resize that stranded the pointer and the pointer
    /// arriving back — after which there is a live tracking area again.
    private func armPointerReentry() {
        guard pointerReentryMonitor == nil else { return }

        pointerReentryMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .mouseMoved
        ) { [weak self] _ in
            guard let self else { return }
            guard OverlayPanelLayout.bodyContainsPointer(
                NSEvent.mouseLocation,
                windowFrame: self.panel.frame,
                surfaceShoulder: self.store.surfaceShoulderRadius
            ) else { return }

            self.disarmPointerReentry()
            self.store.pointerEnteredPanel()
        }
    }

    private func disarmPointerReentry() {
        guard let pointerReentryMonitor else { return }
        NSEvent.removeMonitor(pointerReentryMonitor)
        self.pointerReentryMonitor = nil
    }

    private func observeConcealment() {
        concealmentWatcher.observe(displayID: store.selectedDisplay?.displayID)
        concealmentWatcher.start { [weak self] isConcealed in
            guard let self else { return }
            self.isConcealed = isConcealed
            self.orderPanelToMatchConcealment()
        }
    }

    /// Put the panel where the current concealment says it belongs.
    ///
    /// Collapsing on the way out is not tidiness. The panel expands on pointer
    /// dwell and collapses on pointer exit, and a window ordered out from under
    /// the pointer never gets the exit — so an overlay hidden while expanded
    /// comes back expanded, over nothing, until the pointer visits and leaves
    /// again.
    private func orderPanelToMatchConcealment() {
        guard hasShownPanel else { return }

        guard !isConcealed else {
            store.collapse()
            panel.orderOut(nil)
            return
        }

        updatePanelFrame(animated: false)
        panel.orderFrontRegardless()
    }

    private func observeScreenChanges() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.store.refreshDisplays()
            }
        }
    }
}

enum OverlayPanelLayout {
    /// Whether `pointer` is over the part of `windowFrame` that answers to hover.
    ///
    /// Not the window: that is one `surfaceShoulder` wider than the panel body
    /// on each side, and the shoulders pass the pointer through to the menu bar
    /// items they overhang. `NotchOverlayView` insets its hover region by
    /// exactly that much, and this has to describe the same rectangle.
    ///
    /// Every edge counts as inside. The panel hangs from the top of the
    /// display, so its top edge *is* the screen's, and a pointer parked on the
    /// first row of pixels reports a `y` sitting on that boundary — an
    /// exclusive test would read it as gone and collapse a panel the user is
    /// holding open.
    static func bodyContainsPointer(
        _ pointer: NSPoint,
        windowFrame: NSRect,
        surfaceShoulder: CGFloat
    ) -> Bool {
        let body = windowFrame.insetBy(dx: surfaceShoulder, dy: 0)
        return pointer.x >= body.minX
            && pointer.x <= body.maxX
            && pointer.y >= body.minY
            && pointer.y <= body.maxY
    }

    /// Whether a resize has moved the panel off a pointer that did not move.
    ///
    /// The condition for one swallowed `mouseEntered`, and the reason it has to
    /// be both halves rather than "the pointer is outside now": a pointer that
    /// was already outside left the tracking area by walking out of it, so the
    /// area knows where it is and will report the way back in by itself.
    static func resizeStrandedPointer(
        _ pointer: NSPoint,
        from previousFrame: NSRect,
        to targetFrame: NSRect,
        surfaceShoulder: CGFloat
    ) -> Bool {
        bodyContainsPointer(
            pointer,
            windowFrame: previousFrame,
            surfaceShoulder: surfaceShoulder
        ) && !bodyContainsPointer(
            pointer,
            windowFrame: targetFrame,
            surfaceShoulder: surfaceShoulder
        )
    }

    /// How long the window waits before it starts closing over a wing whose
    /// contents are still leaving.
    ///
    /// **A collapsed surface is exactly as wide as what it draws** -- the
    /// notched bar on both wings, the notch-less pill on its trailing slot --
    /// so the panel's own edge *is* the slot that opens and closes around a
    /// session dot, a subagent badge or the elapsed reading, and it has to keep
    /// that slot's timing or it stops being one movement. Opening it leads, and the
    /// mark fades in behind it (``PanelMotion/fade(isArriving:)``); closing it
    /// waits ``PanelMotion/closingDelay`` for the mark to go first, because an
    /// edge seen shutting over something still lit reads as that thing being
    /// crushed rather than dismissed.
    ///
    /// **Narrower is the whole test, and only while the height holds.** Two
    /// edges move independently and one `setFrame` carries both, so the panel's
    /// own width is the honest question to ask of the pair: a wing giving room
    /// back is what the delay is for, and a bar that nets wider has made room
    /// first whatever else left. An expand or a collapse changes the height as
    /// well and is excluded by that clause — hovering out is an answer to the
    /// pointer, and holding it back `50 ms` would read as the panel being slow
    /// rather than as its contents leaving first.
    static func closingDelay(from previousFrame: NSRect, to targetFrame: NSRect) -> TimeInterval {
        guard targetFrame.height == previousFrame.height,
              targetFrame.width < previousFrame.width else {
            return 0
        }
        return PanelMotion.slotDelay(isOpening: false)
    }

    /// The window frame that puts a panel body of `panelSize` where it belongs.
    ///
    /// Two things separate the window from the panel it carries.
    ///
    /// `surfaceShoulder` is the concave shoulder `PanelContour` draws on each
    /// side of the body — one upper fillet wide (see
    /// `PanelMetrics.surfaceShoulderRadius`). The window is that much wider so
    /// the shoulders have somewhere to live and the body's own edges land where
    /// they were asked to.
    ///
    /// `trailingAnchor` pins the body's trailing edge in screen coordinates. A
    /// notched compact panel needs it: that edge has to sit on the cut-out's,
    /// and deriving the position from the display centre instead both assumes
    /// the cut-out is centred and rounds the panel against the display's
    /// midpoint rather than against the edge it has to meet. Everything else
    /// passes `nil` and is centred.
    ///
    /// **The rect is whole points, and that is not cosmetic.** `NSWindow` keeps
    /// its frame on the point grid: hand it `x = 713.784` and it stores `713`.
    /// A fractional frame therefore describes a window that can never exist,
    /// so `updatePanelFrame`'s "nothing moved, do nothing" guard
    /// (`panel.frame != targetFrame`) is true forever and *every* publish —
    /// each status, session list, quota and elapsed-width change — starts
    /// another 200 ms animated `setFrame` towards a target the window is
    /// already as close to as it can get. Mid-animation the panel is drawn at
    /// the fractional offset, which lands its trailing edge a point further
    /// out, and it snaps back when the animation ends: the collapsed bar's
    /// right edge visibly jitters by one point for as long as anything is
    /// happening. Measured on a Release build 2026-08-29 as `357 → 358 → 357`
    /// once or twice a second while a Turn ran. Rounding here is what makes an
    /// unchanged layout compare equal and stand still.
    ///
    /// Two terms are fractional on real hardware, so neither edge can be
    /// assumed whole: the shoulder is `menuBarHeight / 8` (`4.75` under a `38`
    /// pt bar) and the trailing anchor carries the measured width of the
    /// elapsed reading (`55.78` for `0:00`).
    ///
    /// **Where the slack lands.** The trailing edge takes `ceil`, never
    /// `round`: it is the edge that meets the cut-out, and the two directions
    /// are not equally cheap. Out by up to a point is black laid over the
    /// hardware's own black; back inside is a point of the cut-out's right
    /// edge with no panel on it, which on a lit wallpaper is a seam beside the
    /// notch. Everything else is
    /// derived from that edge and a ceiled width, so the remainder falls in the
    /// leading wing, which is padding and can take it — the same rule
    /// `PanelMetrics.size(...)` already ceils its body width under.
    static func frame(
        on screenFrame: NSRect,
        panelSize: CGSize,
        surfaceShoulder: CGFloat = 0,
        trailingAnchor: CGFloat? = nil
    ) -> NSRect {
        let width = (panelSize.width + surfaceShoulder * 2).rounded(.up)
        let height = panelSize.height.rounded(.up)
        // Anchored, the trailing edge is the thing that must land where it was
        // asked to; centred, it is the midpoint that must survive. Each case is
        // written from what it has to preserve, because deriving one from the
        // other loses the half point it was rounded by.
        let x = trailingAnchor.map { ($0 + surfaceShoulder).rounded(.up) - width }
            ?? (screenFrame.midX - width / 2).rounded()
        return NSRect(
            x: x,
            // Up, for the same reason the trailing edge goes up: the panel
            // hangs from the very top of the display, so erring outwards
            // clips a sliver against the screen edge while erring inwards
            // would open a line of wallpaper above it. A no-op on every real
            // screen, whose frames are whole points already.
            y: (screenFrame.maxY - height).rounded(.up),
            width: width,
            height: height
        )
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(
        _ frameRect: NSRect,
        to screen: NSScreen?
    ) -> NSRect {
        // This panel intentionally occupies the menu-bar/notch region. NSWindow's
        // default constraint uses visibleFrame and would push it below the menu bar.
        frameRect
    }
}
