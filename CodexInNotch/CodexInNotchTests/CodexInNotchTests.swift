import AppKit
import Testing
@testable import CodexInNotch

struct CodexInNotchTests {
    @Test @MainActor
    func fallbackWorkingBaselineMatchesFigma() {
        let size = PanelMetrics.size(
            geometry: .noNotch,
            isExpanded: false,
            statusReadoutText: "6m 24s",
            expandedUsageReadoutText: "6m 24s",
            centerOcclusionWidth: 0,
            compactHeight: PanelMetrics.referenceCompactHeight
        )

        #expect(size.width == 166)
        #expect(size.height == 46)
    }

    @Test @MainActor
    func fallbackWidthGrowsForLongerStatus() {
        let workingWidth = PanelMetrics.fallbackCompactWidth(statusReadoutText: "6m 24s")
        let waitingWidth = PanelMetrics.fallbackCompactWidth(statusReadoutText: "Approval needed")

        #expect(waitingWidth > workingWidth)
        #expect(PanelMetrics.fallbackCompactWidth(statusReadoutText: "Input needed") == 198)
    }

    @Test @MainActor
    func expandedSizeUsesWiderBaselineAndKeepsCompactHeaderHeight() {
        let noNotchSize = PanelMetrics.size(
            geometry: .noNotch,
            isExpanded: true,
            statusReadoutText: "6m 24s",
            expandedUsageReadoutText: "6m 24s",
            centerOcclusionWidth: 0,
            compactHeight: 24
        )
        let notchedSize = PanelMetrics.size(
            geometry: .notched,
            isExpanded: true,
            statusReadoutText: "6m 24s",
            expandedUsageReadoutText: "6m 24s",
            centerOcclusionWidth: 200,
            compactHeight: 38
        )

        #expect(noNotchSize.width == 520)
        #expect(notchedSize.width == 520)
        #expect(noNotchSize.height == 24 + PanelMetrics.expandedContentHeight)
        #expect(notchedSize.height == 38 + PanelMetrics.expandedContentHeight)
    }

    @Test
    func expandedWidthKeepsEveryStatusNameClearOfWideNotch() {
        let centerOcclusionWidth: CGFloat = 220
        let width = PanelMetrics.expandedWidth(
            centerOcclusionWidth: centerOcclusionWidth,
            usageReadoutText: "1h 02m 05s"
        )
        let availableSideWidth = (width - centerOcclusionWidth) / 2

        for status in DemoStatus.allCases {
            let requiredWidth = PanelMetrics.expandedHorizontalPadding
                + PanelMetrics.expandedStatusReadoutWidth(status: status)
                + PanelMetrics.expandedNotchClearance
            #expect(requiredWidth <= availableSideWidth)
        }

        let requiredUsageWidth = PanelMetrics.expandedHorizontalPadding
            + PanelMetrics.expandedUsageReadoutWidth(text: "1h 02m 05s")
            + PanelMetrics.expandedNotchClearance
        #expect(requiredUsageWidth <= availableSideWidth)
    }

    @Test @MainActor
    func usageThresholdsMatchTheFigmaContract() {
        #expect(UsageLevel(remainingPercent: 51) == .healthy)
        #expect(UsageLevel(remainingPercent: 50) == .warning)
        #expect(UsageLevel(remainingPercent: 15) == .warning)
        #expect(UsageLevel(remainingPercent: 14) == .critical)
    }

    @Test
    func runtimeFormattingRemainsPreciseToTheSecond() {
        #expect(DurationFormatter.displayText(seconds: 9) == "9s")
        #expect(DurationFormatter.displayText(seconds: 384) == "6m 24s")
        #expect(DurationFormatter.displayText(seconds: 3_725) == "1h 02m 05s")
    }

    @Test @MainActor
    func expandedHeaderShowsLongestRuntimeOnlyWhileAConversationRuns() {
        let display = makeDisplay(
            id: "notched",
            ordinal: 1,
            menuBarHeight: 38,
            hasNotch: true
        )
        let store = DemoStore(displays: [display])

        #expect(store.sessions.count == 4)
        #expect(store.longestRunningDurationText == "6m 24s")
        #expect(store.expandedUsageReadoutText == "6m 24s")

        store.status = .inputNeeded

        #expect(store.sessions.count == 3)
        #expect(store.longestRunningDurationText == nil)
        #expect(store.expandedUsageReadoutText == "72%")
    }

    @Test
    func statusSetCoversEveryFigmaVariant() {
        #expect(DemoStatus.allCases.count == 8)
        #expect(DemoStatus.inputNeeded.displayName == "Input needed")
        #expect(DemoStatus.approvalNeeded.displayName == "Approval needed")
        #expect(DemoStatus.disconnected.displayName == "Disconnected")
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
        #expect(notchedDisplay.centerOcclusionWidth == 200)
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
        let expandedSize = CGSize(
            width: 520,
            height: PanelMetrics.expandedHeight(compactHeight: 46)
        )

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
        let auxiliaryWidth = hasNotch ? (frame.width - 200) / 2 : 0

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
                ? NSRect(
                    x: frame.minX,
                    y: frame.maxY - menuBarHeight,
                    width: auxiliaryWidth,
                    height: menuBarHeight
                )
                : nil,
            auxiliaryTopRightArea: hasNotch
                ? NSRect(
                    x: frame.maxX - auxiliaryWidth,
                    y: frame.maxY - menuBarHeight,
                    width: auxiliaryWidth,
                    height: menuBarHeight
                )
                : nil,
            fallbackMenuBarHeight: 22
        )
    }
}
