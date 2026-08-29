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
        let animatedChanges: [AnyPublisher<Void, Never>] = [
            store.$status.map { _ in () }.eraseToAnyPublisher(),
            store.$quota.map { _ in () }.eraseToAnyPublisher(),
            store.$sessions.map { _ in () }.eraseToAnyPublisher(),
            store.$isExpanded.map { _ in () }.eraseToAnyPublisher(),
            // Folding the quota block is a height change like any other: the
            // footer redraws itself, but only the panel can give back the
            // height the rules were occupying.
            store.$isQuotaFolded.map { _ in () }.eraseToAnyPublisher(),
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
            store.$elapsedLayoutRevision.map { _ in () }.eraseToAnyPublisher()
        ]

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

        NSAnimationContext.runAnimationGroup { context in
            context.duration = PanelMotion.duration
            context.timingFunction = PanelMotion.timingFunction
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak panel] in
            panel?.contentView?.layoutSubtreeIfNeeded()
        }

        // Asked of the frame the panel is heading for, not the one it is
        // leaving, and asked now rather than from the completion handler: the
        // destination is already known, and the collapse dwell should then run
        // alongside the resize the way it would have had the pointer walked
        // out. Waiting for the animation would also risk answering for a frame
        // a later update had already superseded.
        reconcilePointer(from: previousFrame, to: targetFrame)
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
    static func frame(
        on screenFrame: NSRect,
        panelSize: CGSize,
        surfaceShoulder: CGFloat = 0,
        trailingAnchor: CGFloat? = nil
    ) -> NSRect {
        let width = panelSize.width + surfaceShoulder * 2
        // Anchored, the trailing edge is arithmetic the panel must land on
        // exactly; centred, it is the midpoint that must survive intact. Each
        // case is written from the thing it has to preserve, because deriving
        // one from the other loses an ulp and a half-open window seam is
        // visible against a black cut-out.
        let x = trailingAnchor.map { $0 + surfaceShoulder - width }
            ?? (screenFrame.midX - width / 2)
        return NSRect(
            x: x,
            y: screenFrame.maxY - panelSize.height,
            width: width,
            height: panelSize.height
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
