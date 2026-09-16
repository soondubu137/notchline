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
    /// The application whose keyboard this panel borrowed while a row is open, so it gets its keys
    /// back (§9.4).
    private var applicationToRestore: NSRunningApplication?

    /// Non-nil while one `mouseEntered` is owed — see ``armPointerReentry()``.
    private var pointerReentryMonitor: Any?
    /// Armed only while a row is open; see ``setLatched(_:)``.
    private var outsideClickMonitor: Any?
    private let concealmentWatcher: OverlayConcealmentWatcher
    /// Whether the panel is off screen because its display's menu bar is. Not on ``MonitorStore``:
    /// publishing it would re-evaluate the whole overlay to draw nothing new (`AGENTS.md` §7).
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
        // Must be `false` (`answer-in-notch.md` §10): `true` makes AppKit refuse
        // `makeKeyAndOrderFront` (measured 2026-09-05). ``OverlayPanel/canBecomeKey`` gates key status.
        panel.becomesKeyOnlyIfNeeded = false
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
        // Latching: while a row is open the panel is key; the key goes back on `⎋`, a click outside,
        // and when the row closes.
        store.$openRowID
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] openRowID in
                self?.setLatched(openRowID != nil)
            }
            .store(in: &cancellables)

        panel.handleEscape = { [weak self] in
            guard let self else { return }
            if store.openRowID != nil {
                store.closeOpenRow()
            } else {
                store.collapse()
            }
        }

        // The press that opens a covered panel (`cover-the-words.md` §6). On the window, because a
        // view catcher never gets a primary press: it is hit-tested before `NSApp.currentEvent` is
        // set (measured 2026-09-10). ``MonitorStore/openFromCollapsed()`` guards, so this is
        // unconditional.
        panel.handlePrimaryPress = { [weak self] in
            guard let self else { return }
            store.openFromCollapsed()
        }

        // Keys reaching the window with no caret holder (`answer-in-notch.md` §9.2); their meaning is
        // ``MonitorStore/takeKey(_:)``.
        panel.handleKey = { [weak self] event in
            guard let self, let key = Self.panelKey(for: event) else { return false }
            return store.takeKey(key)
        }

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

        // Follows the menu bar of the display the overlay is on. @Published emits from willSet, so the
        // new selection is read a turn later.
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
    /// Enumerated rather than `store.objectWillChange`: the window is recomputed on layout changes
    /// only (`AGENTS.md` §7). Nothing catches a missing entry: a new control that moves the size
    /// needs its publish here and its mutation in
    /// `everyChangeThatMovesThePanelReachesTheWindow`, in the same change. Internal for that test.
    static func frameChangingPublishers(
        of store: MonitorStore
    ) -> [AnyPublisher<Void, Never>] {
        [
            store.$status.map { _ in () }.eraseToAnyPublisher(),
            store.$quota.map { _ in () }.eraseToAnyPublisher(),
            store.$sessions.map { _ in () }.eraseToAnyPublisher(),
            store.$isExpanded.map { _ in () }.eraseToAnyPublisher(),
            store.$isQuotaExpanded.map { _ in () }.eraseToAnyPublisher(),
            // Hidden products change the open table's height without republishing it.
            store.$productsHiddenFromQuotaTable.map { _ in () }.eraseToAnyPublisher(),
            // The Recent seam moves only the bottom edge; nothing else republishes.
            store.$isRecentExpanded.map { _ in () }.eraseToAnyPublisher(),
            // Queue members age out and leave by click without republishing the session list.
            store.$recentDepartures.map { _ in () }.eraseToAnyPublisher(),
            // An open row grows from `80` up to the whole viewport.
            store.$openRowID.map { _ in () }.eraseToAnyPublisher(),
            // About replaces the body at a fixed height and leaves `expandsToPillOnly` (width too).
            store.$isShowingAbout.map { _ in () }.eraseToAnyPublisher(),
            // Each question in a set can change the body height, and a draft the field's height
            // (`answer-in-notch.md` §7.1); row identity moves for neither.
            store.$answerRevision.map { _ in () }.eraseToAnyPublisher(),
            // `Hide Notchline` changes the notched width or the pill's height; nothing else republishes.
            store.$hidesNotchline.map { _ in () }.eraseToAnyPublisher(),
            // Fires only when an elapsed readout changes width; the readouts tick outside SwiftUI.
            store.$elapsedLayoutRevision.map { _ in () }.eraseToAnyPublisher(),
            // Collapsed forms are measured from the marks; a product with no rows moves nothing else.
            store.$presenceMarks.map { _ in () }.eraseToAnyPublisher()
        ]
    }

    /// Takes or returns the keyboard and, only while latched, watches globally for a click outside.
    private func setLatched(_ isLatched: Bool) {
        // A `.nonactivatingPanel` can be key without its app active, but keys still go to the active
        // app (measured 2026-09-05, Release): the panel activates while a row is open and hands the
        // application back on `⎋`, send and a click outside (`answer-in-notch.md` §9.4). Hover never
        // latches.
        if isLatched, !NSApp.isActive {
            let frontmost = NSWorkspace.shared.frontmostApplication
            applicationToRestore = frontmost?.processIdentifier
                == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
            NSApp.activate()
        }
        panel.latches = isLatched
        if !isLatched {
            // If that application has gone, the system picks focus.
            let restoring = applicationToRestore
            applicationToRestore = nil
            restoring?.activate()
        }
        outsideClickMonitor.map(NSEvent.removeMonitor)
        outsideClickMonitor = nil
        guard isLatched else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            // Global monitors see only events this app did not receive, so this is outside the panel.
            Task { @MainActor [weak self] in self?.store.closeOpenRow() }
        }
    }

    /// What one key press means to a panel whose field does not have the caret. Bare keys only
    /// (`⌥1`, `⌘←` are not bound); §9.3's chord is declined.
    static func panelKey(for event: NSEvent) -> PanelKey? {
        guard event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad])
            .isEmpty
        else { return nil }
        switch event.keyCode {
        case 36: return .submit
        case 123: return .step(-1)
        case 124: return .step(1)
        default:
            guard let digit = event.charactersIgnoringModifiers.flatMap({ Int($0) }),
                  digit >= 1, digit <= 4
            else { return nil }
            return .option(digit)
        }
    }

    private func schedulePanelFrameUpdate(animated: Bool) {
        // @Published emits from willSet. Defer until the next main-queue turn so
        // selectedDisplayID, geometry and isExpanded all describe the new state.
        if let existingAnimationChoice = pendingFrameUpdateShouldAnimate {
            // A screen change stays immediate even if another change lands in the same turn.
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
        // A run-loop hop, not a delay, so MonitorClock has nothing to control.
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
            // Cancel a pending wing close, or it would drag the panel back towards a superseded target.
            pendingFrameAnimation?.cancel()
            pendingFrameAnimation = nil
            panel.setFrame(targetFrame, display: true)
            panel.contentView?.layoutSubtreeIfNeeded()
            // A concealed panel tracks its frame but must not be ordered back over the full-screen window.
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

        // Asked of the destination frame, now rather than on completion, so the collapse dwell runs
        // alongside the resize and never answers for a superseded frame.
        reconcilePointer(from: previousFrame, to: targetFrame)
    }

    /// The window's half of ``PanelMotion/slot(isOpening:)``. AppKit animations have no delay, so a
    /// closing wing is scheduled; the held work item lets a later change supersede it.
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

    /// Re-answers "is the pointer on the panel?" after a move. `.onHover`'s `NSTrackingArea` speaks
    /// only on pointer movement, so a resize away from a still pointer delivers no exit (the store
    /// is told to collapse) and swallows the next entry (``armPointerReentry()``).
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

    /// Delivers the one `mouseEntered` the tracking area will swallow; without it the first pass
    /// over the notch after a fold does nothing.
    ///
    /// A global monitor, since no event of this window's reports the return and a timer would be
    /// polling (`AGENTS.md` §7). Measured: it does see moves over this non-key panel. Armed only
    /// until the pointer arrives back.
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

    /// Puts the panel where the current concealment says it belongs. Collapses on the way out: a
    /// window ordered out from under the pointer never gets the exit, and would return expanded.
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
    /// Whether `pointer` is over the part of `windowFrame` that answers to hover: the window inset
    /// by `surfaceShoulder` each side, matching `NotchOverlayView`'s hover region.
    ///
    /// Edges are inclusive: a pointer on the screen's top pixel row sits on the panel's top edge,
    /// and an exclusive test would collapse a panel the user is holding open.
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

    /// Whether a resize has moved the panel off a pointer that did not move. Both halves matter: a
    /// pointer that walked out is already known to the tracking area.
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

    /// How long the window waits before closing over a wing whose contents are still leaving.
    ///
    /// A collapsed surface is as wide as what it draws, so its edge keeps the slot's timing:
    /// closing waits ``PanelMotion/closingDelay`` for the mark to fade first. Only a narrower frame
    /// at the same height waits; an expand or collapse changes height and is not delayed.
    static func closingDelay(from previousFrame: NSRect, to targetFrame: NSRect) -> TimeInterval {
        guard targetFrame.height == previousFrame.height,
              targetFrame.width < previousFrame.width else {
            return 0
        }
        return PanelMotion.slotDelay(isOpening: false)
    }

    /// The window frame that puts a panel body of `panelSize` where it belongs.
    ///
    /// - The window is one `surfaceShoulder` wider each side for `PanelContour`'s shoulders
    ///   (`PanelMetrics.surfaceShoulderRadius`).
    /// - `trailingAnchor` pins the body's trailing edge on the cut-out's in screen coordinates;
    ///   `nil` centres.
    /// - Whole points: `NSWindow` truncates its frame, so a fractional target never compares equal
    ///   in `updatePanelFrame` and every publish restarts a 200 ms `setFrame`. Measured 2026-08-29
    ///   (Release): the bar's right edge jittered `357 → 358 → 357` while a Turn ran. The shoulder
    ///   (`menuBarHeight / 8`) and the anchor (elapsed width, `55.78` for `0:00`) are fractional.
    /// - The trailing edge takes `ceil`: out by a point is black on black; inside leaves a seam
    ///   beside the notch. The remainder falls in the leading wing, as in `PanelMetrics.size(...)`.
    static func frame(
        on screenFrame: NSRect,
        panelSize: CGSize,
        surfaceShoulder: CGFloat = 0,
        trailingAnchor: CGFloat? = nil
    ) -> NSRect {
        let width = (panelSize.width + surfaceShoulder * 2).rounded(.up)
        let height = panelSize.height.rounded(.up)
        // Each case is rounded from what it must preserve (anchored: trailing edge; centred:
        // midpoint); deriving one from the other loses the half point.
        let x = trailingAnchor.map { ($0 + surfaceShoulder).rounded(.up) - width }
            ?? (screenFrame.midX - width / 2).rounded()
        return NSRect(
            x: x,
            // Up, like the trailing edge: erring inwards would show wallpaper above the panel.
            y: (screenFrame.maxY - height).rounded(.up),
            width: width,
            height: height
        )
    }
}

final class OverlayPanel: NSPanel {
    /// Whether this panel may hold the keyboard: false except while a row is open
    /// (`answer-in-notch.md` §9.4). Hover never latches.
    var latches = false {
        didSet {
            guard latches != oldValue else { return }
            if latches {
                makeKeyAndOrderFront(nil)
            } else if isKeyWindow {
                // Handed back to whoever it came from; if that window has gone, the system decides (§9.4).
                resignKey()
                orderFront(nil)
            }
        }
    }

    /// What `⎋` does, and what a click outside does.
    var handleEscape: (() -> Void)?

    /// A key that reached the window because the field does not have focus (`⏎`, `1`–`4`, `←`,
    /// `→`; `answer-in-notch.md` §9.2). Returns whether anything happened, for the store's tests;
    /// the window stops every key either way.
    var handleKey: ((NSEvent) -> Bool)?

    /// A primary press anywhere on this window (`cover-the-words.md` §6). Noticed before dispatch
    /// and passed on regardless; the store's guard decides whether it means anything.
    var handlePrimaryPress: (() -> Void)?

    override var canBecomeKey: Bool { latches }
    override var canBecomeMain: Bool { false }

    /// `⎋`, AppKit's cancel action: gives the key back (§9.2). The row keeps what was typed and
    /// nothing is sent.
    override func cancelOperation(_ sender: Any?) {
        handleEscape?()
    }

    /// `⎋`, the panel's own three keys, and silence for everything else. Nothing is passed on: the
    /// last responder beeps on an unhandled `keyDown`, and §9.2's unbound keys must be quiet.
    /// `⌘`-key equivalents are offered to the chain before this.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            handleEscape?()
            return
        }
        _ = handleKey?(event)
    }

    /// A click anywhere but the field takes the caret out of it (§6.6). Here because only the
    /// window sees every press; taken before dispatch so the target gets its click unfocused. A
    /// click outside the panel is the controller's global monitor instead.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown,
           firstResponder is AnswerFieldView,
           contentView?.hitTest(event.locationInWindow).map(Self.isAnswerField) != true {
            makeFirstResponder(nil)
        }
        if event.type == .leftMouseDown {
            handlePrimaryPress?()
        }
        super.sendEvent(event)
    }

    private static func isAnswerField(_ view: NSView) -> Bool {
        var candidate: NSView? = view
        while let current = candidate {
            if current is AnswerFieldView || current is AnswerFieldBox { return true }
            candidate = current.superview
        }
        return false
    }

    override func constrainFrameRect(
        _ frameRect: NSRect,
        to screen: NSScreen?
    ) -> NSRect {
        // This panel intentionally occupies the menu-bar/notch region. NSWindow's
        // default constraint uses visibleFrame and would push it below the menu bar.
        frameRect
    }
}
