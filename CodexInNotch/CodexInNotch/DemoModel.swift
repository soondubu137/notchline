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
    case running
    case waitingApproval
    case completed
    case failed

    var id: Self { self }

    var fallbackTitle: String {
        switch self {
        case .running:
            "Working"
        case .waitingApproval:
            "Waiting for Approval"
        case .completed:
            "Completed"
        case .failed:
            "Failed"
        }
    }

    var controlTitle: String {
        switch self {
        case .running:
            "运行中"
        case .waitingApproval:
            "等待批准"
        case .completed:
            "已完成"
        case .failed:
            "失败"
        }
    }
}

struct DemoSession: Identifiable, Equatable {
    let id: UUID
    let title: String
    let preview: String
    let status: DemoStatus
    let isHighlighted: Bool

    init(
        id: UUID = UUID(),
        title: String,
        preview: String,
        status: DemoStatus,
        isHighlighted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.status = status
        self.isHighlighted = isHighlighted
    }
}

enum PanelMetrics {
    static let referenceCompactHeight: CGFloat = 46
    static let notchCompactWidth: CGFloat = 348
    static let fallbackBaselineWidth: CGFloat = 168
    static let expandedWidth: CGFloat = 444
    static let expandedHeight: CGFloat = 390

    static func size(
        geometry: DisplayGeometry,
        isExpanded: Bool,
        status: DemoStatus,
        tokenText: String,
        compactHeight: CGFloat
    ) -> CGSize {
        guard !isExpanded else {
            return CGSize(width: expandedWidth, height: expandedHeight)
        }

        switch geometry {
        case .notched:
            return CGSize(width: notchCompactWidth, height: compactHeight)
        case .noNotch:
            return CGSize(
                width: fallbackCompactWidth(status: status, tokenText: tokenText),
                height: compactHeight
            )
        }
    }

    static func fallbackCompactWidth(status: DemoStatus, tokenText: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .bold)
        let baselineStatusWidth = textWidth("Working", font: font)
        let baselineTokenWidth = textWidth("72%", font: font)
        let statusDelta = textWidth(status.fallbackTitle, font: font) - baselineStatusWidth
        let tokenDelta = textWidth(tokenText, font: font) - baselineTokenWidth

        return ceil(max(132, fallbackBaselineWidth + statusDelta + tokenDelta))
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

    let sessions: [DemoSession] = [
        DemoSession(
            title: "验证 macOS 刘海窗口定位",
            preview: "需要在本机运行窗口定位测试。",
            status: .waitingApproval
        ),
        DemoSession(
            title: "实现 Codex 状态事件适配器",
            preview: "正在核对事件顺序与状态映射……",
            status: .running,
            isHighlighted: true
        ),
        DemoSession(
            title: "更新产品需求文档",
            preview: "已更新收起与展开状态的产品要求。",
            status: .completed
        ),
        DemoSession(
            title: "同步本地任务事件",
            preview: "连接已中断，正在等待重新连接。",
            status: .failed
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

    var currentPanelSize: CGSize {
        PanelMetrics.size(
            geometry: geometry,
            isExpanded: isExpanded,
            status: status,
            tokenText: tokenText,
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
