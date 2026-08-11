import AppKit
import Testing
@testable import CodexInNotch

struct CodexInNotchTests {
    @Test @MainActor
    func fallbackWorkingBaselineMatchesFigma() {
        let size = PanelMetrics.size(
            geometry: .noNotch,
            isExpanded: false,
            status: .running,
            tokenText: "72%",
            compactHeight: PanelMetrics.referenceCompactHeight
        )

        #expect(size.width == 168)
        #expect(size.height == 46)
    }

    @Test @MainActor
    func fallbackWidthGrowsForLongerStatus() {
        let workingWidth = PanelMetrics.fallbackCompactWidth(
            status: .running,
            tokenText: "72%"
        )
        let waitingWidth = PanelMetrics.fallbackCompactWidth(
            status: .waitingApproval,
            tokenText: "72%"
        )

        #expect(waitingWidth > workingWidth)
    }

    @Test @MainActor
    func expandedSizeIsSharedByBothGeometries() {
        for geometry in DisplayGeometry.allCases {
            let size = PanelMetrics.size(
                geometry: geometry,
                isExpanded: true,
                status: .running,
                tokenText: "72%",
                compactHeight: PanelMetrics.referenceCompactHeight
            )

            #expect(size.width == 444)
            #expect(size.height == 390)
        }
    }

    @Test @MainActor
    func selectingDisplayAdaptsGeometryAndMenuBarHeight() {
        let notchedDisplay = makeDisplay(
            id: "notched",
            ordinal: 1,
            menuBarHeight: 38,
            hasNotch: true
        )
        let externalDisplay = makeDisplay(
            id: "external",
            ordinal: 2,
            menuBarHeight: 24,
            hasNotch: false
        )
        let store = DemoStore(displays: [notchedDisplay, externalDisplay])

        #expect(store.selectedDisplayID == notchedDisplay.id)
        #expect(store.geometry == .notched)
        #expect(store.currentPanelSize.height == 38)

        store.selectDisplay(id: externalDisplay.id)

        #expect(store.selectedDisplayID == externalDisplay.id)
        #expect(store.geometry == .noNotch)
        #expect(store.currentPanelSize.height == 24)
    }

    @Test @MainActor
    func removedDisplayFallsBackToPrimaryDisplay() {
        let primaryDisplay = makeDisplay(
            id: "primary",
            ordinal: 1,
            menuBarHeight: 38,
            hasNotch: true
        )
        let externalDisplay = makeDisplay(
            id: "external",
            ordinal: 2,
            menuBarHeight: 24,
            hasNotch: false
        )
        let store = DemoStore(displays: [primaryDisplay, externalDisplay])
        store.selectDisplay(id: externalDisplay.id)
        store.isExpanded = true

        store.refreshDisplays([primaryDisplay])

        #expect(store.selectedDisplayID == primaryDisplay.id)
        #expect(store.geometry == .notched)
        #expect(!store.isExpanded)
    }

    @Test @MainActor
    func unavailableMenuBarMeasurementUsesSystemFallback() {
        let display = makeDisplay(
            id: "auto-hidden-menu-bar",
            ordinal: 1,
            menuBarHeight: 0,
            hasNotch: false
        )
        let store = DemoStore(displays: [display])

        #expect(store.geometry == .noNotch)
        #expect(store.compactHeight == 22)
    }

    @Test
    func panelFramesStayTopAttachedAndCentered() {
        let screenFrame = NSRect(x: 1_440.5, y: -120, width: 1_919, height: 1_080)
        let compactSize = CGSize(width: 348, height: 46)
        let expandedSize = CGSize(width: 444, height: 390)

        for step in 0 ... 20 {
            let progress = CGFloat(step) / 20
            let size = CGSize(
                width: compactSize.width
                    + (expandedSize.width - compactSize.width) * progress,
                height: compactSize.height
                    + (expandedSize.height - compactSize.height) * progress
            )
            let frame = OverlayPanelLayout.frame(
                on: screenFrame,
                panelSize: size
            )

            #expect(frame.midX == screenFrame.midX)
            #expect(frame.maxY == screenFrame.maxY)
        }
    }

    @Test @MainActor
    func hoverExpandsAndCollapsesBothGeometries() async throws {
        let displays = [
            makeDisplay(
                id: "notched",
                ordinal: 1,
                menuBarHeight: 38,
                hasNotch: true
            ),
            makeDisplay(
                id: "external",
                ordinal: 2,
                menuBarHeight: 24,
                hasNotch: false
            )
        ]

        for display in displays {
            let store = DemoStore(displays: [display])

            store.pointerEnteredPanel()
            try await Task.sleep(nanoseconds: 200_000_000)
            #expect(store.isExpanded)

            store.pointerExitedPanel()
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(!store.isExpanded)
        }
    }

    private func makeDisplay(
        id: String,
        ordinal: Int,
        menuBarHeight: CGFloat,
        hasNotch: Bool
    ) -> DisplayOption {
        let frame = NSRect(x: CGFloat(ordinal - 1) * 1_920, y: 0, width: 1_920, height: 1_080)
        let auxiliaryHeight = hasNotch ? menuBarHeight : 0

        return DisplayOption(
            id: id,
            ordinal: ordinal,
            name: "Display \(ordinal)",
            frame: frame,
            visibleFrame: NSRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width,
                height: frame.height - menuBarHeight
            ),
            safeAreaInsets: NSEdgeInsets(
                top: auxiliaryHeight,
                left: 0,
                bottom: 0,
                right: 0
            ),
            auxiliaryTopLeftArea: hasNotch
                ? NSRect(x: frame.minX, y: frame.maxY - menuBarHeight, width: 800, height: menuBarHeight)
                : nil,
            auxiliaryTopRightArea: hasNotch
                ? NSRect(x: frame.maxX - 800, y: frame.maxY - menuBarHeight, width: 800, height: menuBarHeight)
                : nil,
            fallbackMenuBarHeight: 22
        )
    }
}
