import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayPanelController {
    private let store: MonitorStore
    private let panel: OverlayPanel
    private var cancellables = Set<AnyCancellable>()
    private var localEventMonitor: Any?
    private var screenParametersObserver: NSObjectProtocol?
    private var pendingFrameUpdate: DispatchWorkItem?
    private var pendingFrameUpdateShouldAnimate: Bool?
    private var hasShownPanel = false

    init(store: MonitorStore) {
        self.store = store
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
        installEventMonitors()
        observeScreenChanges()
    }

    deinit {
        pendingFrameUpdate?.cancel()
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
    }

    func show() {
        updatePanelFrame(animated: false)
        panel.orderFrontRegardless()
        hasShownPanel = true
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
            store.$reduceMotion.map { _ in () }.eraseToAnyPublisher(),
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

        guard animated, hasShownPanel else {
            panel.setFrame(targetFrame, display: true)
            panel.contentView?.layoutSubtreeIfNeeded()
            if hasShownPanel {
                panel.orderFrontRegardless()
            }
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = PanelMotion.duration(
                reduceMotion: store.reduceMotion
            )
            context.timingFunction = PanelMotion.timingFunction(
                reduceMotion: store.reduceMotion
            )
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak panel] in
            panel?.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func installEventMonitors() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown, event.keyCode == 53, self.store.isExpanded {
                self.store.collapse()
                return nil
            }

            return event
        }
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
