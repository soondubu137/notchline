// Shared application state and display geometry for the Codex monitor.
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

enum PanelMetrics {
    static let referenceCompactHeight: CGFloat = 46
    static let nativeNotchMenuBarHeight: CGFloat = 38
    static let maximumSurfaceCornerRadius: CGFloat = 10
    static let notchCompactWidth: CGFloat = 348
    static let fallbackBaselineWidth: CGFloat = 166
    static let expandedBaselineWidth: CGFloat = 520
    static let sessionRowHeight: CGFloat = 80
    static let maximumVisibleSessionCount = 3
    static let expandedSessionViewportHeight = sessionRowHeight
        * CGFloat(maximumVisibleSessionCount)
    static let expandedHorizontalPadding: CGFloat = 24
    static let expandedReadoutSpacing: CGFloat = 12
    static let expandedNotchClearance: CGFloat = 8
    static let expandedFooterHeight: CGFloat = 40
    static let thinExpandedBodyHeight: CGFloat = 48
    static let expandedContentHeight: CGFloat = expandedSessionViewportHeight
        + expandedFooterHeight
    static let thinExpandedContentHeight: CGFloat = thinExpandedBodyHeight
        + expandedFooterHeight
    private static let fallbackFixedContentWidth: CGFloat = 114
    private static let statusDotWidth: CGFloat = 8
    private static let usageRingWidth: CGFloat = 18

    static func surfaceCornerRadius(
        geometry: DisplayGeometry,
        menuBarHeight: CGFloat
    ) -> CGFloat {
        guard geometry == .noNotch else {
            return maximumSurfaceCornerRadius
        }

        let proportionalRadius = maximumSurfaceCornerRadius
            * max(0, menuBarHeight)
            / nativeNotchMenuBarHeight
        return min(maximumSurfaceCornerRadius, proportionalRadius)
    }

    static func size(
        geometry: DisplayGeometry,
        isExpanded: Bool,
        statusReadoutText: String,
        expandedUsageReadoutText: String,
        centerOcclusionWidth: CGFloat,
        compactHeight: CGFloat,
        expandedContentHeight: CGFloat = expandedContentHeight
    ) -> CGSize {
        guard !isExpanded else {
            return CGSize(
                width: expandedWidth(
                    centerOcclusionWidth: centerOcclusionWidth,
                    usageReadoutText: expandedUsageReadoutText
                ),
                height: compactHeight + expandedContentHeight
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
        let font = NSFont.systemFont(ofSize: 13, weight: .bold)
        let measuredWidth = fallbackFixedContentWidth + textWidth(statusReadoutText, font: font)
        return ceil(max(fallbackBaselineWidth, measuredWidth))
    }

    static func expandedHeight(compactHeight: CGFloat) -> CGFloat {
        compactHeight + expandedContentHeight
    }

    static func sessionViewportHeight(forSessionCount sessionCount: Int) -> CGFloat {
        sessionRowHeight * CGFloat(min(max(sessionCount, 0), maximumVisibleSessionCount))
    }

    static func expandedContentHeight(forSessionCount sessionCount: Int) -> CGFloat {
        guard sessionCount > 0 else {
            return thinExpandedContentHeight
        }
        return sessionViewportHeight(forSessionCount: sessionCount)
            + expandedFooterHeight
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
                MonitorStatus.allCases.map {
                    expandedStatusReadoutWidth(status: $0)
                }.max() ?? 0,
                expandedUsageReadoutWidth(text: usageReadoutText)
            )
            + expandedNotchClearance
        let notchSafeWidth = centerOcclusionWidth + requiredSideWidth * 2

        return ceil(max(expandedBaselineWidth, notchSafeWidth))
    }

    static func expandedStatusReadoutWidth(status: MonitorStatus) -> CGFloat {
        statusDotWidth
            + expandedReadoutSpacing
            + textWidth(
                status.displayName,
                font: NSFont.systemFont(ofSize: 13, weight: .bold)
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

struct ConnectionStabilityGate {
    static let defaultGracePeriod: TimeInterval = 3

    let gracePeriod: TimeInterval
    private var disconnectedSince: Date?

    init(gracePeriod: TimeInterval = Self.defaultGracePeriod) {
        self.gracePeriod = gracePeriod
    }

    mutating func shouldPublish(
        candidate: MonitorAvailability,
        current: MonitorAvailability,
        observedAt: Date
    ) -> Bool {
        guard candidate == .disconnected, current != .disconnected else {
            disconnectedSince = nil
            return true
        }

        guard let disconnectedSince else {
            self.disconnectedSince = observedAt
            return false
        }

        return observedAt.timeIntervalSince(disconnectedSince) >= gracePeriod
    }
}

@MainActor
final class MonitorStore: ObservableObject {
    private static let liveService = LiveCodexMonitorService()
    static let shared = MonitorStore(
        service: liveService,
        navigator: CodexDesktopNavigator(targetChecker: liveService),
        initialSnapshot: .connecting,
        displayPreferences: .standard
    )

    @Published private(set) var displays: [DisplayOption]
    @Published private(set) var selectedDisplayID: String
    @Published private(set) var status: MonitorStatus
    @Published private(set) var availability: MonitorAvailability
    @Published private(set) var quota: QuotaSnapshot
    @Published private(set) var sessions: [MonitoredSession]
    @Published private(set) var hookSetupStatus: HookSetupStatus = .notInstalled
    @Published private(set) var integrationSwitchIsOn = false
    @Published var isExpanded = false
    @Published var reduceMotion = false
    @Published var showsContentPreviews: Bool {
        didSet {
            UserDefaults.standard.set(
                showsContentPreviews,
                forKey: Self.contentPreviewDefaultsKey
            )
            if !showsContentPreviews {
                sessions = sessions.map { $0.hidingContent() }
            }
            guard let service else { return }
            Task {
                await service.updateHookSettings(
                    showsContentPreviews: showsContentPreviews
                )
            }
        }
    }
    @Published private(set) var lastIntegrationMessage: String
    @Published private(set) var isInstallingIntegration = false
    @Published private(set) var isRemovingIntegration = false
    @Published private(set) var isClearingSessions = false
    @Published private(set) var hasCompletedOnboarding: Bool

    private static let contentPreviewDefaultsKey = "showsContentPreviews"
    private static let onboardingDefaultsKey = "hasCompletedOnboarding"
    private static let selectedDisplayDefaultsKey = "selectedDisplayID"
    private let service: (any CodexMonitoring)?
    private let navigator: (any CodexNavigating)?
    private let displayPreferences: UserDefaults?
    private var preferredDisplayID: String?
    private var pendingHoverAction: DispatchWorkItem?
    private var monitorTask: Task<Void, Never>?
    private var isRefreshInFlight = false
    private var isNavigationInFlight = false
    private var dismissedSessionIDs: Set<String> = []
    private var connectionStabilityGate = ConnectionStabilityGate()

    init(
        displays: [DisplayOption]? = nil,
        service: (any CodexMonitoring)? = nil,
        navigator: (any CodexNavigating)? = nil,
        initialSnapshot: MonitorSnapshot? = nil,
        displayPreferences: UserDefaults? = nil
    ) {
        let resolvedDisplays = displays ?? DisplayOption.currentDisplays()
        let snapshot = initialSnapshot ?? Self.previewSnapshot
        let persistedDisplayID = displayPreferences?.string(
            forKey: Self.selectedDisplayDefaultsKey
        )
        let initialDisplayID = persistedDisplayID.flatMap { persistedID in
            resolvedDisplays.first { $0.id == persistedID }?.id
        } ?? resolvedDisplays.first?.id ?? ""
        self.displays = resolvedDisplays
        self.selectedDisplayID = initialDisplayID
        self.displayPreferences = displayPreferences
        self.preferredDisplayID = persistedDisplayID
            ?? (initialDisplayID.isEmpty ? nil : initialDisplayID)
        self.service = service
        self.navigator = navigator
        self.availability = snapshot.availability
        self.quota = snapshot.quota
        self.sessions = snapshot.sessions
        self.status = MonitorAggregation.status(
            availability: snapshot.availability,
            sessions: snapshot.sessions
        )
        self.showsContentPreviews = UserDefaults.standard.object(
            forKey: Self.contentPreviewDefaultsKey
        ) as? Bool ?? true
        self.hasCompletedOnboarding = UserDefaults.standard.bool(
            forKey: Self.onboardingDefaultsKey
        )
        self.lastIntegrationMessage = snapshot.diagnostic ?? "等待 Codex 数据"
        if !showsContentPreviews {
            self.sessions = snapshot.sessions.map { $0.hidingContent() }
        }

        if service != nil {
            startMonitoring()
        }
    }

    deinit {
        monitorTask?.cancel()
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

    var tokenRemainingPercent: Int? {
        quota.remainingPercent
    }

    var tokenText: String {
        tokenRemainingPercent.map { "\($0)%" } ?? "--"
    }

    var compactStatusReadoutText: String {
        status.displayName
    }

    var expandedUsageReadoutText: String {
        tokenText
    }

    var expandedFooterText: String {
        UsageSummaryFormatter.summary(
            todayTokens: quota.todayTokens,
            resetsAt: quota.resetsAt
        )
    }

    var emptyListMessage: String {
        availability.emptyListMessage
    }

    var expandedContentHeight: CGFloat {
        PanelMetrics.expandedContentHeight(forSessionCount: sessions.count)
    }

    var currentPanelSize: CGSize {
        PanelMetrics.size(
            geometry: geometry,
            isExpanded: isExpanded,
            statusReadoutText: compactStatusReadoutText,
            expandedUsageReadoutText: expandedUsageReadoutText,
            centerOcclusionWidth: selectedDisplay?.centerOcclusionWidth ?? 0,
            compactHeight: compactHeight,
            expandedContentHeight: expandedContentHeight
        )
    }

    var integrationSummary: String {
        switch availability {
        case .setupRequired:
            "Codex 集成尚未设置"
        case .connecting:
            "正在连接 Codex App Server"
        case .ready:
            "Codex 实时监视已连接"
        case .updateCodex:
            "需要更新 Codex"
        case .unsupportedVersion:
            "当前 Codex 版本不支持所需协议"
        case .disconnected:
            "Codex 实时监视未连接"
        }
    }

    func selectDisplay(id: String) {
        guard displays.contains(where: { $0.id == id }) else { return }

        if preferredDisplayID != id {
            preferredDisplayID = id
            displayPreferences?.set(id, forKey: Self.selectedDisplayDefaultsKey)
        }

        guard selectedDisplayID != id else { return }

        cancelPendingHoverAction()
        selectedDisplayID = id
    }

    func refreshDisplays(_ refreshedDisplays: [DisplayOption]? = nil) {
        let resolvedDisplays = refreshedDisplays ?? DisplayOption.currentDisplays()
        let previousSelection = selectedDisplayID
        displays = resolvedDisplays

        let restoredPreference = preferredDisplayID.flatMap { preferredID in
            resolvedDisplays.first { $0.id == preferredID }?.id
        }
        let nextSelection = restoredPreference
            ?? resolvedDisplays.first { $0.id == previousSelection }?.id
            ?? resolvedDisplays.first?.id
            ?? ""
        guard nextSelection != previousSelection else { return }

        cancelPendingHoverAction()
        isExpanded = false
        selectedDisplayID = nextSelection
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

    func collapse() {
        cancelPendingHoverAction()
        isExpanded = false
    }

    func open(_ session: MonitoredSession) {
        Task { [weak self] in
            _ = await self?.openAndWait(session)
        }
    }

    @discardableResult
    func openAndWait(_ session: MonitoredSession) async -> Bool {
        guard !isNavigationInFlight else { return false }
        guard let navigator else {
            lastIntegrationMessage = "会话导航仅在真实 Codex 集成中可用。"
            return false
        }

        isNavigationInFlight = true
        defer { isNavigationInFlight = false }

        do {
            try await navigator.open(threadID: session.threadID)
            collapse()
            lastIntegrationMessage = "已在 Codex Desktop 中打开：\(session.title)"
            return true
        } catch {
            await performRefresh()
            let reason = (error as? LocalizedError)?.errorDescription
                ?? "发生未知错误。"
            lastIntegrationMessage = "无法打开 \(session.title)：\(reason)"
            return false
        }
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.performRefresh()
        }
    }

    func clearSessions() {
        Task { [weak self] in
            _ = await self?.clearSessionsAndWait()
        }
    }

    @discardableResult
    func clearSessionsAndWait() async -> Bool {
        guard !isClearingSessions else { return false }

        isClearingSessions = true
        defer { isClearingSessions = false }

        dismissedSessionIDs.formUnion(sessions.map(\.id))
        sessions = []
        status = MonitorAggregation.status(
            availability: availability,
            sessions: []
        )
        lastIntegrationMessage = "已清空 Codex in Notch 会话列表；Codex 会话未被删除。"

        await service?.clearSessions()
        return true
    }

    @discardableResult
    func recheckIntegrationAndWait() async -> HookSetupStatus {
        await performRefresh()
        return hookSetupStatus
    }

    func installIntegrationHooks() {
        Task { [weak self] in
            _ = await self?.installIntegrationHooksAndWait()
        }
    }

    func setIntegrationEnabled(_ isEnabled: Bool) {
        guard !isInstallingIntegration, !isRemovingIntegration else { return }
        let previousValue = integrationSwitchIsOn
        guard isEnabled != previousValue else { return }

        integrationSwitchIsOn = isEnabled
        Task { [weak self] in
            guard let self else { return }
            let succeeded = isEnabled
                ? await installIntegrationHooksAndWait()
                : await removeIntegrationAndWait()
            if !succeeded {
                integrationSwitchIsOn = previousValue
            }
        }
    }

    @discardableResult
    func installIntegrationHooksAndWait() async -> Bool {
        guard let service, !isInstallingIntegration else { return false }
        isInstallingIntegration = true
        defer { isInstallingIntegration = false }

        do {
            try await service.installHooks(
                showsContentPreviews: showsContentPreviews
            )
            hookSetupStatus = await service.hookSetupStatus()
            integrationSwitchIsOn = hookSetupStatus.isIntegrationEnabled
            lastIntegrationMessage = "Hooks 已安装；请在 Codex 中打开 /hooks 并信任新增定义。"
            return true
        } catch {
            lastIntegrationMessage = "Hooks 安装失败：\(error.localizedDescription)"
            return false
        }
    }

    func removeIntegration() {
        Task { [weak self] in
            _ = await self?.removeIntegrationAndWait()
        }
    }

    @discardableResult
    func removeIntegrationAndWait() async -> Bool {
        guard let service, !isRemovingIntegration else { return false }
        isRemovingIntegration = true
        defer { isRemovingIntegration = false }

        do {
            try await service.removeHooks()
            sessions = []
            quota = .unavailable
            availability = .setupRequired
            status = .setupRequired
            hookSetupStatus = .notInstalled
            integrationSwitchIsOn = false
            lastIntegrationMessage = "Codex in Notch 管理的 Hooks 已移除。"
            return true
        } catch {
            lastIntegrationMessage = "移除集成失败：\(error.localizedDescription)"
            return false
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: Self.onboardingDefaultsKey)
        refreshNow()
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        guard let service else { return }
        Task {
            await service.disconnect()
        }
    }

    func applyForTesting(
        _ snapshot: MonitorSnapshot,
        observedAt: Date = Date()
    ) {
        publish(snapshot, observedAt: observedAt)
    }

    private func scheduleHoverAction(
        after delay: TimeInterval,
        action: @escaping @MainActor (MonitorStore) -> Void
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

    private func startMonitoring() {
        guard service != nil else { return }

        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.performRefresh()
                guard !Task.isCancelled else { return }
                let retryDelay: UInt64 = self?.hookSetupStatus == .active
                    ? 1_000_000_000
                    : 5_000_000_000
                try? await Task.sleep(nanoseconds: retryDelay)
            }
        }
    }

    private func apply(_ snapshot: MonitorSnapshot) {
        let upstreamSessionIDs = Set(snapshot.sessions.map(\.id))
        dismissedSessionIDs.formIntersection(upstreamSessionIDs)
        let undismissedSessions = snapshot.sessions.filter {
            !dismissedSessionIDs.contains($0.id)
        }
        let visibleSessions = showsContentPreviews
            ? undismissedSessions
            : undismissedSessions.map { $0.hidingContent() }
        let aggregateStatus = MonitorAggregation.status(
            availability: snapshot.availability,
            sessions: undismissedSessions
        )
        let integrationMessage = snapshot.diagnostic ?? "Codex 数据已刷新"

        if availability != snapshot.availability {
            availability = snapshot.availability
        }
        if quota != snapshot.quota {
            quota = snapshot.quota
        }
        if sessions != visibleSessions {
            sessions = visibleSessions
        }
        if status != aggregateStatus {
            status = aggregateStatus
        }
        if lastIntegrationMessage != integrationMessage {
            lastIntegrationMessage = integrationMessage
        }
    }

    private func publish(_ snapshot: MonitorSnapshot, observedAt: Date) {
        guard connectionStabilityGate.shouldPublish(
            candidate: snapshot.availability,
            current: availability,
            observedAt: observedAt
        ) else {
            let reason = snapshot.diagnostic ?? "Codex App Server 暂时没有响应。"
            let retryMessage = "检测到瞬时连接异常，正在重试：\(reason)"
            if lastIntegrationMessage != retryMessage {
                lastIntegrationMessage = retryMessage
            }
            return
        }

        apply(snapshot)
    }

    private func performRefresh() async {
        guard let service, !isRefreshInFlight else { return }
        isRefreshInFlight = true
        defer { isRefreshInFlight = false }

        let snapshot = await service.fetchSnapshot(
            showsContentPreviews: showsContentPreviews
        )
        guard !Task.isCancelled else { return }
        publish(snapshot, observedAt: Date())
        let refreshedHookSetupStatus = await service.hookSetupStatus()
        if hookSetupStatus != refreshedHookSetupStatus {
            hookSetupStatus = refreshedHookSetupStatus
        }
        if !isInstallingIntegration,
           !isRemovingIntegration,
           integrationSwitchIsOn != refreshedHookSetupStatus.isIntegrationEnabled {
            integrationSwitchIsOn = refreshedHookSetupStatus.isIntegrationEnabled
        }
    }

    private static var previewSnapshot: MonitorSnapshot {
        let now = Date()
        return MonitorSnapshot(
            availability: .ready,
            sessions: [
                MonitoredSession(
                    threadID: "preview-input",
                    turnID: "turn-input",
                    projectName: "codex-in-notch",
                    title: "Confirm the final overlay interaction details",
                    preview: "Please choose whether the panel should remain open after a click.",
                    status: .inputNeeded,
                    startedAt: now.addingTimeInterval(-72)
                ),
                MonitoredSession(
                    threadID: "preview-running",
                    turnID: "turn-running",
                    projectName: "codex-in-notch",
                    title: "Implement the Codex status event adapter",
                    preview: "Checking event order, status mapping, and reconnect behavior…",
                    status: .running,
                    startedAt: now.addingTimeInterval(-384)
                )
            ],
            quota: QuotaSnapshot(
                remainingPercent: 72,
                resetsAt: Calendar.current.date(
                    byAdding: .day,
                    value: 3,
                    to: now
                ),
                todayTokens: 87_500_000
            ),
            diagnostic: "Preview data"
        )
    }
}
