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
            store.$reduceMotion.map { _ in () }.eraseToAnyPublisher(),
            // The compact width is measured from the elapsed string, so the
            // panel has to re-measure when it gains a digit. Most ticks resolve
            // to an unchanged frame and are dropped by updatePanelFrame.
            store.$timerNow.map { _ in () }.eraseToAnyPublisher()
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
            horizontalOffset: store.currentPanelHorizontalOffset
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
            context.duration = store.reduceMotion ? 0.08 : 0.20
            context.timingFunction = store.reduceMotion
                ? CAMediaTimingFunction(name: .easeOut)
                : CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
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
    /// `horizontalOffset` displaces the panel from the centre of the display.
    /// A notched compact panel needs it: with no trailing wing it hangs to the
    /// left of the cut-out, and centring would slide the notch out from under it.
    static func frame(
        on screenFrame: NSRect,
        panelSize: CGSize,
        horizontalOffset: CGFloat = 0
    ) -> NSRect {
        NSRect(
            x: screenFrame.midX - panelSize.width / 2 + horizontalOffset,
            y: screenFrame.maxY - panelSize.height,
            width: panelSize.width,
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
