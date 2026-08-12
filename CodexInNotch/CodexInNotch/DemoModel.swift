import AppKit
import Combine

enum DisplayGeometry: String, CaseIterable, Identifiable {
    case notched
    case noNotch

    var id: Self { self }

    var title: String {
        switch self {
        case .notched:
            "Notch 屏"
        case .noNotch:
            "非 Notch 屏"
        }
    }
}

struct DisplayOption: Identifiable {
    let id: String
    let ordinal: Int
    let name: String
    let frame: NSRect
    let visibleFrame: NSRect
    let safeAreaInsets: NSEdgeInsets
    let auxiliaryTopLeftArea: NSRect?
    let auxiliaryTopRightArea: NSRect?
    let fallbackMenuBarHeight: CGFloat

    var pickerTitle: String {
        "\(ordinal). \(name)"
    }

    var geometry: DisplayGeometry {
        let hasTopInset = safeAreaInsets.top >= 1
        let hasAuxiliaryArea = [auxiliaryTopLeftArea, auxiliaryTopRightArea]
            .compactMap { $0 }
            .contains { !$0.isEmpty }
        return hasTopInset && hasAuxiliaryArea ? .notched : .noNotch
    }

    var menuBarHeight: CGFloat {
        let occupiedTopHeight = max(0, frame.maxY - visibleFrame.maxY)
        let measuredHeight = max(occupiedTopHeight, safeAreaInsets.top)
        return measuredHeight >= 1
            ? measuredHeight
            : max(1, fallbackMenuBarHeight)
    }

    var centerOcclusionWidth: CGFloat {
        guard geometry == .notched,
              let auxiliaryTopLeftArea,
              let auxiliaryTopRightArea else {
            return 0
        }

        return max(0, auxiliaryTopRightArea.minX - auxiliaryTopLeftArea.maxX)
    }

    var configurationSummary: String {
        "\(geometry.title) · 菜单栏 \(Int(menuBarHeight.rounded())) pt"
    }

    static func currentDisplays() -> [DisplayOption] {
        NSScreen.screens.enumerated().map { index, screen in
            DisplayOption(
                id: identifier(for: screen),
                ordinal: index + 1,
                name: screen.localizedName,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                safeAreaInsets: screen.safeAreaInsets,
                auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
                auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
                fallbackMenuBarHeight: NSStatusBar.system.thickness
            )
        }
    }

    static func identifier(for screen: NSScreen) -> String {
        if let displayID = screen.cgDirectDisplayID {
            return "display-\(displayID)"
        }

        if let screenNumber = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber {
            return "display-\(screenNumber.uint32Value)"
        }

        let frame = screen.frame
        return "frame-\(frame.minX)-\(frame.minY)-\(frame.width)-\(frame.height)"
    }
}

enum DemoStatus: String, CaseIterable, Identifiable {
    case idle
    case running
    case inputNeeded
    case approvalNeeded
    case completed
    case error
    case cancelled
    case disconnected

    var id: Self { self }

    var displayName: String {
        switch self {
        case .idle:
            "Idle"
        case .running:
            "Running"
        case .inputNeeded:
            "Input needed"
        case .approvalNeeded:
            "Approval needed"
        case .completed:
            "Completed"
        case .error:
            "Error"
        case .cancelled:
            "Cancelled"
        case .disconnected:
            "Disconnected"
        }
    }

    var controlTitle: String {
        switch self {
        case .idle:
            "空闲"
        case .running:
            "运行中"
        case .inputNeeded:
            "需要输入"
        case .approvalNeeded:
            "等待批准"
        case .completed:
            "已完成"
        case .error:
            "发生错误"
        case .cancelled:
            "已取消"
        case .disconnected:
            "连接中断"
        }
    }

    var isRunning: Bool {
        self == .running
    }
}

struct DemoSession: Identifiable, Equatable {
    let id: UUID
    let projectName: String
    let title: String
    let preview: String
    let status: DemoStatus
    let runtimeSeconds: Int?

    init(
        id: UUID = UUID(),
        projectName: String,
        title: String,
        preview: String,
        status: DemoStatus,
        runtimeSeconds: Int? = nil
    ) {
        self.id = id
        self.projectName = projectName
        self.title = title
        self.preview = preview
        self.status = status
        self.runtimeSeconds = runtimeSeconds
    }

    var runtimeText: String? {
        runtimeSeconds.map(DurationFormatter.displayText)
    }
}

enum DurationFormatter {
    nonisolated static func displayText(seconds: Int) -> String {
        let clampedSeconds = max(0, seconds)
        let hours = clampedSeconds / 3_600
        let minutes = (clampedSeconds % 3_600) / 60
        let remainingSeconds = clampedSeconds % 60

        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, remainingSeconds)
        }
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, remainingSeconds)
        }
        return "\(remainingSeconds)s"
    }
}

enum UsageLevel: Equatable {
    case healthy
    case warning
    case critical

    init(remainingPercent: Int) {
        switch remainingPercent {
        case 51 ... Int.max:
            self = .healthy
        case 15 ... 50:
            self = .warning
        default:
            self = .critical
        }
    }
}

enum PanelMetrics {
    static let referenceCompactHeight: CGFloat = 46
    static let notchCompactWidth: CGFloat = 348
    static let fallbackBaselineWidth: CGFloat = 166
    static let expandedBaselineWidth: CGFloat = 520
    static let expandedSessionViewportHeight: CGFloat = 240
    static let expandedHorizontalPadding: CGFloat = 24
    static let expandedReadoutSpacing: CGFloat = 12
    static let expandedNotchClearance: CGFloat = 8
    static let expandedContentHeight: CGFloat = expandedSessionViewportHeight + 16
    private static let fallbackFixedContentWidth: CGFloat = 114
    private static let statusDotWidth: CGFloat = 8
    private static let usageRingWidth: CGFloat = 18

    static func size(
        geometry: DisplayGeometry,
        isExpanded: Bool,
        statusReadoutText: String,
        expandedUsageReadoutText: String,
        centerOcclusionWidth: CGFloat,
        compactHeight: CGFloat
    ) -> CGSize {
        guard !isExpanded else {
            return CGSize(
                width: expandedWidth(
                    centerOcclusionWidth: centerOcclusionWidth,
                    usageReadoutText: expandedUsageReadoutText
                ),
                height: expandedHeight(compactHeight: compactHeight)
            )
        }

        switch geometry {
        case .notched:
            return CGSize(width: notchCompactWidth, height: compactHeight)
        case .noNotch:
            return CGSize(
                width: fallbackCompactWidth(statusReadoutText: statusReadoutText),
                height: compactHeight
            )
        }
    }

    static func fallbackCompactWidth(statusReadoutText: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let measuredWidth = fallbackFixedContentWidth + textWidth(statusReadoutText, font: font)
        return ceil(max(fallbackBaselineWidth, measuredWidth))
    }

    static func expandedHeight(compactHeight: CGFloat) -> CGFloat {
        compactHeight + expandedContentHeight
    }

    static func expandedWidth(
        centerOcclusionWidth: CGFloat,
        usageReadoutText: String
    ) -> CGFloat {
        guard centerOcclusionWidth >= 1 else {
            return expandedBaselineWidth
        }

        let requiredSideWidth = expandedHorizontalPadding
            + max(
                DemoStatus.allCases.map {
                    expandedStatusReadoutWidth(status: $0)
                }.max() ?? 0,
                expandedUsageReadoutWidth(text: usageReadoutText)
            )
            + expandedNotchClearance
        let notchSafeWidth = centerOcclusionWidth + requiredSideWidth * 2

        return ceil(max(expandedBaselineWidth, notchSafeWidth))
    }

    static func expandedStatusReadoutWidth(status: DemoStatus) -> CGFloat {
        statusDotWidth
            + expandedReadoutSpacing
            + textWidth(
                status.displayName,
                font: NSFont.systemFont(ofSize: 13, weight: .semibold)
            )
    }

    static func expandedUsageReadoutWidth(text: String) -> CGFloat {
        textWidth(
            text,
            font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        )
            + expandedReadoutSpacing
            + usageRingWidth
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

@MainActor
final class DemoStore: ObservableObject {
    static let shared = DemoStore()

    @Published private(set) var displays: [DisplayOption]
    @Published private(set) var selectedDisplayID: String
    @Published var status: DemoStatus = .running
    @Published var tokenRemainingPercent = 72
    @Published var isExpanded = false
    @Published var reduceMotion = false
    @Published var lastDemoAction = "尚未选择会话"

    private let runningSessions: [DemoSession] = [
        DemoSession(
            projectName: "codex-in-notch",
            title: "Confirm the final overlay interaction details",
            preview: "Please choose whether the panel should remain open after a click.",
            status: .inputNeeded
        ),
        DemoSession(
            projectName: "codex-in-notch",
            title: "Implement the Codex status event adapter",
            preview: "Checking event order, status mapping, and reconnect behavior…",
            status: .running,
            runtimeSeconds: 384
        ),
        DemoSession(
            projectName: "design-system",
            title: "Update product requirements",
            preview: "The compact and expanded interaction requirements are now aligned.",
            status: .completed
        ),
        DemoSession(
            projectName: "local-event-bridge",
            title: "Reconnect the local task event stream",
            preview: "The connection was interrupted and is waiting to retry.",
            status: .disconnected
        )
    ]

    private let nonRunningSessions: [DemoSession] = [
        DemoSession(
            projectName: "codex-in-notch",
            title: "Confirm the final overlay interaction details",
            preview: "Please choose whether the panel should remain open after a click.",
            status: .inputNeeded
        ),
        DemoSession(
            projectName: "design-system",
            title: "Update product requirements",
            preview: "The compact and expanded interaction requirements are now aligned.",
            status: .completed
        ),
        DemoSession(
            projectName: "release-checks",
            title: "Validate the signed application bundle",
            preview: "The validation command exited before the bundle could be inspected.",
            status: .error
        )
    ]

    private var pendingHoverAction: DispatchWorkItem?

    init(displays: [DisplayOption]? = nil) {
        let resolvedDisplays = displays ?? DisplayOption.currentDisplays()
        self.displays = resolvedDisplays
        self.selectedDisplayID = resolvedDisplays.first?.id ?? ""
    }

    var selectedDisplay: DisplayOption? {
        displays.first { $0.id == selectedDisplayID } ?? displays.first
    }

    var geometry: DisplayGeometry {
        selectedDisplay?.geometry ?? .noNotch
    }

    var compactHeight: CGFloat {
        selectedDisplay?.menuBarHeight ?? PanelMetrics.referenceCompactHeight
    }

    var tokenText: String {
        "\(tokenRemainingPercent)%"
    }

    var sessions: [DemoSession] {
        status.isRunning ? runningSessions : nonRunningSessions
    }

    var longestRunningDurationText: String? {
        sessions
            .filter { $0.status.isRunning }
            .compactMap(\.runtimeSeconds)
            .max()
            .map(DurationFormatter.displayText)
    }

    var compactStatusReadoutText: String {
        status.isRunning
            ? longestRunningDurationText ?? status.displayName
            : status.displayName
    }

    var expandedUsageReadoutText: String {
        longestRunningDurationText ?? tokenText
    }

    var currentPanelSize: CGSize {
        PanelMetrics.size(
            geometry: geometry,
            isExpanded: isExpanded,
            statusReadoutText: compactStatusReadoutText,
            expandedUsageReadoutText: expandedUsageReadoutText,
            centerOcclusionWidth: selectedDisplay?.centerOcclusionWidth ?? 0,
            compactHeight: compactHeight
        )
    }

    func selectDisplay(id: String) {
        guard displays.contains(where: { $0.id == id }) else { return }
        guard selectedDisplayID != id else { return }

        cancelPendingHoverAction()
        selectedDisplayID = id
    }

    func refreshDisplays(_ refreshedDisplays: [DisplayOption]? = nil) {
        let resolvedDisplays = refreshedDisplays ?? DisplayOption.currentDisplays()
        let previousSelection = selectedDisplayID
        displays = resolvedDisplays

        if !resolvedDisplays.contains(where: { $0.id == previousSelection }) {
            cancelPendingHoverAction()
            isExpanded = false
            selectedDisplayID = resolvedDisplays.first?.id ?? ""
        }
    }

    func pointerEnteredPanel() {
        scheduleHoverAction(after: 0.15) { store in
            store.isExpanded = true
        }
    }

    func pointerExitedPanel() {
        scheduleHoverAction(after: 0.25) { store in
            store.isExpanded = false
        }
    }

    func toggleFromDebugWindow() {
        cancelPendingHoverAction()
        isExpanded.toggle()
    }

    func collapse() {
        cancelPendingHoverAction()
        isExpanded = false
    }

    func simulateOpening(_ session: DemoSession) {
        lastDemoAction = "模拟打开 Codex：\(session.title)"
    }

    private func scheduleHoverAction(
        after delay: TimeInterval,
        action: @escaping @MainActor (DemoStore) -> Void
    ) {
        cancelPendingHoverAction()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            action(self)
        }
        pendingHoverAction = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelPendingHoverAction() {
        pendingHoverAction?.cancel()
        pendingHoverAction = nil
    }
}
