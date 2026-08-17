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
    /// The status matrix is a fixed size, not a share of the menu bar.
    ///
    /// Taken from the indicator-to-text ratio at loaders.wtf — a 92pt indicator
    /// beside 72pt text — applied to the label's fixed 13pt: 13 × 1.2778 ≈ 16.6.
    /// Because the label never scaled with the bar either, tying only the
    /// indicator to it left the two drifting apart between a 46pt and a 24pt bar.
    static let statusMatrixSize: CGFloat = 16.6
    /// The notch label renders Light — measure it at the weight it draws at,
    /// or every compact width is over-reserved.
    private static let statusLabelFont = NSFont.systemFont(ofSize: 13, weight: .light)
    /// The elapsed timer uses tabular figures so its width stops changing every
    /// second; measure it with the same metrics.
    private static let timerFont = NSFont.monospacedDigitSystemFont(
        ofSize: 13,
        weight: .light
    )

    /// Compact content leading the notch: padding, the matrix, and — where there
    /// is no physical notch to work around — the status label as well.
    ///
    /// Menu bar height no longer appears here. Neither the indicator nor the
    /// label scales with it, so it governs panel height and corner radius only.
    static func compactLeadingWidth(
        statusReadoutText: String,
        showsStatusText: Bool
    ) -> CGFloat {
        var width = expandedHorizontalPadding + statusMatrixSize
        if showsStatusText {
            width += expandedReadoutSpacing
                + textWidth(statusReadoutText, font: statusLabelFont)
        }
        return width
    }

    /// Compact content trailing the notch, including its own trailing padding.
    ///
    /// Zero unless a turn is being timed. The usage ring used to sit here
    /// unconditionally, which meant an idle notched display rendered a blank
    /// wing that read as a second, fake notch.
    static func compactTrailingWidth(timerText: String?) -> CGFloat {
        guard let timerText else { return 0 }
        return textWidth(timerText, font: timerFont) + expandedHorizontalPadding
    }

    /// How far the compact panel sits from the centre of the display.
    ///
    /// A notched panel is pinned to the notch, not the screen: with no trailing
    /// wing the panel hangs entirely to the left of the notch, so centring it
    /// would slide the real notch out from under the cut-out.
    static func compactHorizontalOffset(
        geometry: DisplayGeometry,
        isExpanded: Bool,
        statusReadoutText: String,
        timerText: String?,
        centerOcclusionWidth: CGFloat
    ) -> CGFloat {
        guard !isExpanded, geometry == .notched, centerOcclusionWidth >= 1 else {
            return 0
        }
        let leading = notchedLeadingWidth(statusReadoutText: statusReadoutText)
        let trailing = notchedTrailingWidth(timerText: timerText)
        return (trailing - leading) / 2
    }

    private static func notchedLeadingWidth(statusReadoutText: String) -> CGFloat {
        compactLeadingWidth(
            statusReadoutText: statusReadoutText,
            showsStatusText: false
        ) + expandedNotchClearance
    }

    private static func notchedTrailingWidth(timerText: String?) -> CGFloat {
        let content = compactTrailingWidth(timerText: timerText)
        return content > 0 ? content + expandedNotchClearance : 0
    }

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
        timerText: String?,
        centerOcclusionWidth: CGFloat,
        compactHeight: CGFloat,
        configuredAgents: Set<AgentKind> = [.codex],
        expandedContentHeight: CGFloat = expandedContentHeight
    ) -> CGSize {
        guard !isExpanded else {
            return CGSize(
                width: expandedWidth(
                    centerOcclusionWidth: centerOcclusionWidth,
                    configuredAgents: configuredAgents
                ),
                height: compactHeight + expandedContentHeight
            )
        }

        switch geometry {
        case .notched:
            guard centerOcclusionWidth >= 1 else {
                // Notched display with no measurable cut-out: nothing to wrap
                // around, so lay it out as an emulated notch instead.
                return CGSize(
                    width: fixedCompactWidth(for: configuredAgents),
                    height: compactHeight
                )
            }
            // A notched panel still wraps the cut-out, so its width is set by
            // the wings around a fixed obstacle rather than by its content.
            let width = notchedLeadingWidth(statusReadoutText: statusReadoutText)
                + centerOcclusionWidth
                + notchedTrailingWidth(timerText: timerText)
            return CGSize(width: ceil(width), height: compactHeight)
        case .noNotch:
            return CGSize(
                width: fixedCompactWidth(for: configuredAgents),
                height: compactHeight
            )
        }
    }

    /// The widest elapsed readout inside a turn that has run for hours. Sizing
    /// the slot for it means the pill does not widen at 1:00:00 either.
    private static let timerSlotTemplate = "1:02:03"

    /// One width for every no-notch compact panel, whatever the state.
    ///
    /// Derived rather than fixed by hand: the widest content any state can
    /// produce, which is the longest compact label that also carries a timer,
    /// plus the timer slot. Reserving that on every state — including the ones
    /// with no timer and a short label — is the point. A pill that measured
    /// itself resized whenever the status changed or a turn started, which on a
    /// menu bar reads as flicker rather than information.
    /// Computed rather than a stored `static let`: a lazily-initialised one runs
    /// its initialiser in a nonisolated context, and this measures text. Ten
    /// cases of measurement per panel update is not worth the isolation dance.
    /// Folded over every state *and* every product the user has configured.
    ///
    /// One label names its product, so what a panel is configured to watch is
    /// what decides how wide it is. Deriving the set from settings rather than
    /// from whichever products currently have rows is the whole point: a width
    /// that followed live membership would resize the pill the moment a second
    /// product connected, which is the flicker this fixed width exists to
    /// prevent.
    static func fixedCompactWidth(
        for configuredAgents: Set<AgentKind>
    ) -> CGFloat {
        let agents: [AgentKind?] = configuredAgents.isEmpty
            ? [nil]
            : configuredAgents.sorted().map { $0 }
        let widest = MonitorStatus.allCases
            .flatMap { status in
                agents.map { compactContentWidth(for: status, agent: $0) }
            }
            .max() ?? 0
        return ceil(compactChromeWidth + widest)
    }

    /// Everything in a compact panel that is not the label or the timer.
    static let compactChromeWidth: CGFloat = expandedHorizontalPadding
        + statusMatrixSize
        + expandedReadoutSpacing
        + expandedHorizontalPadding

    /// What one status needs beside the chrome: its label, plus the timer slot
    /// when that status can be counting.
    static func compactContentWidth(
        for status: MonitorStatus,
        agent: AgentKind?
    ) -> CGFloat {
        let label = textWidth(
            status.compactDisplayName(for: agent),
            font: statusLabelFont
        )
        guard status.canShowElapsed else { return label }
        return label
            + expandedReadoutSpacing
            + textWidth(timerSlotTemplate, font: timerFont)
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
        configuredAgents: Set<AgentKind>
    ) -> CGFloat {
        guard centerOcclusionWidth >= 1 else {
            return expandedBaselineWidth
        }

        // Only the status readout flanks the notch now — the usage readout that
        // used to claim the trailing side moved into the footer.
        let agents: [AgentKind?] = configuredAgents.isEmpty
            ? [nil]
            : configuredAgents.sorted().map { $0 }
        let widestStatusReadout = MonitorStatus.allCases.flatMap { status in
            agents.map { expandedStatusReadoutWidth(status: status, agent: $0) }
        }.max() ?? 0
        let requiredSideWidth = expandedHorizontalPadding
            + widestStatusReadout
            + expandedNotchClearance
        let notchSafeWidth = centerOcclusionWidth + requiredSideWidth * 2

        return ceil(max(expandedBaselineWidth, notchSafeWidth))
    }

    static func expandedStatusReadoutWidth(
        status: MonitorStatus,
        agent: AgentKind?
    ) -> CGFloat {
        statusMatrixSize
            + expandedReadoutSpacing
            + textWidth(status.displayName(for: agent), font: statusLabelFont)
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

struct ConnectionStabilityGate {
    let gracePeriod: TimeInterval
    private var disconnectedSince: Date?

    init(gracePeriod: TimeInterval = MonitorTiming.standard.disconnectGracePeriod) {
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

        // Connecting has no trusted snapshot to preserve. Once the startup
        // attempt confirms that App Server is unresponsive, publish that fact
        // immediately; the grace period only protects an established state.
        guard current != .connecting else {
            disconnectedSince = nil
            return true
        }

        guard let disconnectedSince else {
            self.disconnectedSince = observedAt
            return false
        }

        guard observedAt.timeIntervalSince(disconnectedSince) >= gracePeriod else {
            return false
        }
        // Cleared as it publishes. Leaving it set kept ``nextPublishDeadline``
        // reporting an instant already past until the *next* refresh observed
        // the now-disconnected state and cleared it -- one wake-up spent
        // rediscovering something this call already knew.
        self.disconnectedSince = nil
        return true
    }

    /// When a suppressed disconnect becomes publishable.
    ///
    /// Suppressing without arranging to be asked again is the same mistake as
    /// dropping a refresh request: the grace period only bounds the wait if
    /// something actually looks again when it expires. Nothing did -- the store
    /// slept on the service's deadlines, which know nothing about this gate, so
    /// a real disconnect could sit unpublished until the next unrelated wake-up
    /// or the 60s heartbeat, rather than the 3s the latency budget documents.
    ///
    /// Always clearable: the refresh at this instant either publishes the
    /// disconnect or observes a recovery, and both clear `disconnectedSince`.
    var nextPublishDeadline: Date? {
        disconnectedSince?.addingTimeInterval(gracePeriod)
    }
}

@MainActor
final class MonitorStore: ObservableObject {
    /// Which product the single integration card in Settings belongs to.
    ///
    /// There is one card today, and it is Codex's. The second product's card
    /// arrives with the two-product settings surface; naming the owner here
    /// means installing or removing one product's hooks can never move the
    /// other product's switch.
    static let integrationCardAgent = AgentKind.codex
    private static let liveService = LiveCodexMonitorService()
    private static let claudeCodeService = ClaudeCodeMonitorService()
    static let shared = MonitorStore(
        // Claude Code contributes nothing until its hooks are registered: an
        // unregistered product reports setupRequired, which loses to any
        // product that is ready and to any product that has a row. A user who
        // only runs Codex sees exactly what they saw before.
        services: [liveService, claudeCodeService],
        navigator: AgentNavigationRouter([
            .codex: CodexDesktopNavigator(targetChecker: liveService)
        ]),
        initialSnapshot: .connecting,
        displayPreferences: .standard,
        // Every provider's "ask me again" edges on one stream, so a late
        // answer from any of them wakes the loop.
        refreshEvents: DirectoryChangeWatcher.merged([
            liveService.stateChangeEvents,
            claudeCodeService.stateChangeEvents
        ])
    )

    @Published private(set) var displays: [DisplayOption]
    @Published private(set) var selectedDisplayID: String
    @Published private(set) var status: MonitorStatus
    /// Which product the summary is speaking about, or nil when it speaks for
    /// none — nothing is wrong, or more than one product is equally unhealthy.
    @Published private(set) var statusAgent: AgentKind?
    /// Instructions for every product whose registration the user makes by
    /// hand. Absent for a product this app sets up itself.
    @Published private(set) var manualSetups: [AgentKind: AgentManualSetup] = [:]
    @Published private(set) var availability: MonitorAvailability
    @Published private(set) var quota: QuotaSnapshot
    @Published private(set) var sessions: [MonitoredSession] {
        didSet { updateElapsedTicking() }
    }
    /// Advances once a second while a turn is timed; see `updateElapsedTicking`.
    ///
    /// Deliberately **not** `@Published`. Every publish on this store re-evaluates
    /// the whole overlay — the `GeometryReader`, the custom panel `Shape` and both
    /// AppKit representables — which profiles at roughly 20ms, so a readout
    /// gaining a second used to cost about 4% of a core for as long as a turn ran
    /// or waited on the user. The readouts subscribe to this and redraw their own
    /// layer; nothing in the SwiftUI graph observes it.
    let elapsedTick: CurrentValueSubject<Date, Never>

    /// Bumped when a readout's *reserved width* changes, which is the only thing
    /// SwiftUI actually has to re-measure for.
    ///
    /// The readouts use tabular figures, so width follows the digit count: this
    /// moves when a turn crosses a minute or hour boundary, not every second.
    @Published private(set) var elapsedLayoutRevision = 0
    private var elapsedLayoutSignature: [Int] = []

    /// The instant the readouts are currently showing.
    var timerNow: Date { elapsedTick.value }
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
            // Applied before this setter returns, so the switch cannot land out
            // of order and cannot fail. Everything below is cleanup of text
            // already collected, which is idempotent and may run late.
            services.forEach { $0.setContentPreviewsEnabled(showsContentPreviews) }
            guard !showsContentPreviews else { return }
            sessions = sessions.map { $0.hidingContent() }
            Task { [services] in
                for service in services {
                    await service.discardCollectedPreviews()
                }
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
    private let services: [any AgentMonitoring]
    private let navigator: (any AgentNavigating)?
    private var integrationService: (any AgentMonitoring)? {
        services.first { $0.agent == Self.integrationCardAgent }
    }
    private let displayPreferences: UserDefaults?
    private let clock: any MonitorClock
    private let timing: MonitorTiming
    private var preferredDisplayID: String?
    private var pendingHoverTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var refreshEventTask: Task<Void, Never>?
    private var elapsedTickTask: Task<Void, Never>?
    private let refreshEvents: AsyncStream<Void>?
    private var refreshGate = SingleFlightGate()
    private var refreshTask: Task<Void, Never>?
    /// The switch's desired state, which the convergence task reads each pass.
    private var desiredIntegrationEnabled: Bool?
    private var integrationTask: Task<Void, Never>?
    private var isNavigationInFlight = false
    private var dismissedSessionIDs: Set<String> = []
    /// The latest answer from each product, kept so the merge can be recomputed
    /// without asking anyone again. One product answering must never discard
    /// what another already said.
    private var latestByAgent: [AgentKind: AgentSnapshot] = [:]
    /// One gate per product. Sharing one made a Codex blip suppress a Claude
    /// Code publish, and made the grace period's wake-up a shared resource.
    private var stabilityGates: [AgentKind: ConnectionStabilityGate] = [:]
    /// Integration health per product. The expanded panel shows one card today;
    /// keeping this per product is what stops one product's absence from
    /// switching another product's integration off.
    private var setupStatusByAgent: [AgentKind: HookSetupStatus] = [:]
    private var manualSetupTask: Task<Void, Never>?
    /// Deadlines a provider reported and then failed to clear. A provider that
    /// keeps naming the same overdue instant is not going to advance it, and
    /// letting it into the shared `min` would drag every other provider down to
    /// the refresh floor with it.
    private var stuckDeadlines: [AgentKind: Date] = [:]

    init(
        displays: [DisplayOption]? = nil,
        services: [any AgentMonitoring] = [],
        navigator: (any AgentNavigating)? = nil,
        initialSnapshot: AgentSnapshot? = nil,
        displayPreferences: UserDefaults? = nil,
        refreshEvents: AsyncStream<Void>? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard
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
        self.clock = clock
        self.elapsedTick = CurrentValueSubject(clock.now())
        self.timing = timing
        self.stuckDeadlines = [:]
        self.preferredDisplayID = persistedDisplayID
            ?? (initialDisplayID.isEmpty ? nil : initialDisplayID)
        self.services = services
        self.navigator = navigator
        self.refreshEvents = refreshEvents
        self.latestByAgent = [snapshot.agent: snapshot]
        let merged = AgentSnapshotMerge.merge([snapshot])
        self.availability = merged.availability
        self.quota = merged.quota
        self.sessions = merged.sessions
        self.status = merged.status
        self.statusAgent = merged.availabilityAgent
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

        // Reconcile the switch with what was persisted, rather than trusting
        // the channel's default to match. Previously nothing did this, so a
        // user who had turned previews off got a helper that came back up
        // collecting text until they toggled it again.
        services.forEach { $0.setContentPreviewsEnabled(showsContentPreviews) }

        if !services.isEmpty {
            startMonitoring()
        }
        updateElapsedTicking()
    }

    deinit {
        monitorTask?.cancel()
        refreshEventTask?.cancel()
        pendingHoverTask?.cancel()
        elapsedTickTask?.cancel()
        refreshTask?.cancel()
        integrationTask?.cancel()
    }

    /// Advances the elapsed readout once a second while a turn is being timed.
    ///
    /// The tick still lives here rather than in a view-local timer, because it is
    /// a timing decision and belongs on ``MonitorClock`` like every other window.
    /// What changed is how it leaves: a tick is sent on ``elapsedTick``, which no
    /// SwiftUI view observes, and only a change in the readouts' *reserved width*
    /// bumps ``elapsedLayoutRevision`` and asks SwiftUI to re-measure.
    private func updateElapsedTicking() {
        // Nothing being timed: stop entirely rather than wake once a second to
        // discover there is no work.
        guard longestRunningSessionStart != nil else {
            elapsedTickTask?.cancel()
            elapsedTickTask = nil
            return
        }
        guard elapsedTickTask == nil else { return }

        // The tick has been frozen since the last turn finished, so it is older
        // than the turn that just started. Left stale, the first second of that
        // turn reads as a negative duration -- which the formatter reports as
        // "not timed" -- and the row renders blank until the first tick.
        publishTick(clock.now())

        elapsedTickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard let start = self.longestRunningSessionStart else {
                    // The last timed turn finished between ticks. `sessions`
                    // will have cancelled this task already; clearing the handle
                    // keeps a later turn able to start a new one.
                    self.elapsedTickTask = nil
                    return
                }
                try? await self.clock.sleep(
                    seconds: Self.secondsUntilNextTick(
                        after: start,
                        now: self.clock.now()
                    )
                )
                guard !Task.isCancelled else { return }
                self.publishTick(self.clock.now())
            }
        }
    }

    /// Sends a tick to the readouts, and asks SwiftUI to re-measure only if one
    /// of them changed width.
    ///
    /// The formatter emits digits and colons in tabular figures, so a string's
    /// character count *is* its rendered width; comparing counts is comparing
    /// widths without measuring text once a second.
    private func publishTick(_ now: Date) {
        elapsedTick.send(now)

        var signature = [compactTimerText?.count ?? -1]
        signature.append(contentsOf: sessions.map { elapsedText(for: $0)?.count ?? -1 })
        guard signature != elapsedLayoutSignature else { return }
        elapsedLayoutSignature = signature
        elapsedLayoutRevision &+= 1
    }

    /// Time until the timed turn's next whole second.
    ///
    /// Sleeping a flat second drifts, and a drifting tick eventually crosses two
    /// boundaries in one wake-up and visibly skips a digit. Landing on the turn's
    /// own boundary keeps the ticks a true second apart, so every row -- whatever
    /// its own sub-second phase -- advances exactly once per tick.
    nonisolated private static func secondsUntilNextTick(
        after start: Date,
        now: Date
    ) -> TimeInterval {
        let elapsed = now.timeIntervalSince(start)
        guard elapsed.isFinite else { return 1 }
        return 1 - (elapsed - elapsed.rounded(.down))
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

    /// The products this panel is configured to watch.
    ///
    /// A product counts once its integration has been set up, not merely
    /// because a provider for it exists. Both distinctions matter and they are
    /// different: deriving this from which providers answered would widen the
    /// panel the moment a second product was *shipped*, for a user who never
    /// asked for it; deriving it from which products currently have rows would
    /// resize the panel whenever one connected or went quiet, which is the
    /// flicker a fixed width exists to prevent.
    var configuredAgents: Set<AgentKind> {
        let configured = latestByAgent.values
            .filter { $0.setupStatus != .notInstalled }
            .map(\.agent)
        // Never empty: a panel with nothing set up still has to have a width,
        // and it is the one the first product would have.
        return configured.isEmpty ? [.codex] : Set(configured)
    }

    var statusDisplayName: String {
        status.displayName(for: statusAgent)
    }

    var compactStatusReadoutText: String {
        status.compactDisplayName(for: statusAgent)
    }

    /// The turn the notch is timing.
    ///
    /// A single readout can only speak for one turn, so it follows the
    /// longest-running one — the oldest is the one worth surfacing. Every state
    /// but `completed` is eligible: a turn that has been parked on an approval
    /// for ten minutes is precisely the one the user needs to see, so filtering
    /// this to `running` would hide the timer exactly when it starts to matter.
    var longestRunningSessionStart: Date? {
        sessions
            .filter { $0.status.keepsTiming }
            .compactMap(\.startedAt)
            .min()
    }

    var compactTimerText: String? {
        SessionElapsedFormatter.elapsed(
            since: longestRunningSessionStart,
            now: timerNow
        )
    }

    /// The instant the compact readout counts from, or nil when there is nothing
    /// to draw. The readout advances itself from ``elapsedTick``, so it needs the
    /// start rather than a string that would go stale between re-renders.
    var compactTimerStart: Date? {
        compactTimerText == nil ? nil : longestRunningSessionStart
    }

    /// As ``compactTimerStart``, for one row.
    func elapsedStart(for session: MonitoredSession) -> Date? {
        elapsedText(for: session) == nil ? nil : session.startedAt
    }

    /// The compact timer for VoiceOver, which cannot read `12:34` as a length.
    var spokenLongestElapsedText: String? {
        SessionElapsedFormatter.spokenElapsed(
            since: longestRunningSessionStart,
            now: timerNow
        )
    }

    func elapsedText(for session: MonitoredSession) -> String? {
        guard session.status.keepsTiming else { return nil }
        return SessionElapsedFormatter.elapsed(
            since: session.startedAt,
            now: timerNow
        )
    }

    func spokenElapsedText(for session: MonitoredSession) -> String? {
        guard session.status.keepsTiming else { return nil }
        return SessionElapsedFormatter.spokenElapsed(
            since: session.startedAt,
            now: timerNow
        )
    }

    var expandedFooterText: String {
        UsageSummaryFormatter.summary(
            remainingPercent: quota.remainingPercent,
            todayTokens: quota.todayTokens,
            resetsAt: quota.resetsAt,
            now: clock.now()
        )
    }

    /// 0–1 fill for the footer meter, or nil when quota is unavailable.
    var usageMeterFill: Double? {
        quota.remainingPercent.map { Double($0) / 100 }
    }

    var emptyListMessage: String {
        availability.emptyListMessage(for: statusAgent)
    }

    var expandedContentHeight: CGFloat {
        PanelMetrics.expandedContentHeight(forSessionCount: sessions.count)
    }

    var currentPanelSize: CGSize {
        PanelMetrics.size(
            geometry: geometry,
            isExpanded: isExpanded,
            statusReadoutText: compactStatusReadoutText,
            timerText: compactTimerText,
            centerOcclusionWidth: selectedDisplay?.centerOcclusionWidth ?? 0,
            compactHeight: compactHeight,
            configuredAgents: configuredAgents,
            expandedContentHeight: expandedContentHeight
        )
    }

    /// Horizontal displacement from the centre of the display. Non-zero only
    /// for a notched compact panel, which is pinned to the cut-out.
    var currentPanelHorizontalOffset: CGFloat {
        PanelMetrics.compactHorizontalOffset(
            geometry: geometry,
            isExpanded: isExpanded,
            statusReadoutText: compactStatusReadoutText,
            timerText: compactTimerText,
            centerOcclusionWidth: selectedDisplay?.centerOcclusionWidth ?? 0
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
        case .updateAgent:
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
        scheduleHoverAction(after: timing.hoverExpandDelay) { store in
            store.isExpanded = true
        }
    }

    func pointerExitedPanel() {
        scheduleHoverAction(after: timing.hoverCollapseDelay) { store in
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
            let outcome = try await navigator.open(session)
            collapse()
            // What the navigator actually managed, not what Codex would have.
            lastIntegrationMessage = outcome.message(forTitle: session.title)
            return true
        } catch {
            await refreshAndWait()
            let reason = (error as? LocalizedError)?.errorDescription
                ?? "发生未知错误。"
            lastIntegrationMessage = "无法打开 \(session.title)：\(reason)"
            return false
        }
    }

    func refreshNow() {
        requestRefresh()
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
            agents: Array(latestByAgent.values),
            sessions: []
        )
        lastIntegrationMessage = "已清空 Codex in Notch 会话列表；Codex 会话未被删除。"

        for service in services {
            await service.clearSessions()
        }
        return true
    }

    @discardableResult
    func recheckIntegrationAndWait() async -> HookSetupStatus {
        await refreshAndWait()
        return hookSetupStatus
    }

    func installIntegrationHooks() {
        Task { [weak self] in
            _ = await self?.installIntegrationHooksAndWait()
        }
    }

    /// Records where the user wants the integration, and converges to it.
    ///
    /// The switch used to read its own guard flags before the task that sets
    /// them had started, so flipping it twice quickly could queue an install
    /// and a removal that then completed in whichever order they happened to
    /// finish in -- not the order the user asked for, and not necessarily
    /// ending where they left the switch (CR-017).
    ///
    /// Intent and execution are now separate. This records the desired state
    /// and returns; a single convergence task applies it, re-reading the
    /// desired state after each step so the last flip is the one that decides
    /// where things end up. Intermediate flips are collapsed rather than
    /// replayed -- nobody wants three installs because the switch was tapped
    /// three times.
    func setIntegrationEnabled(_ isEnabled: Bool) {
        guard isEnabled != desiredIntegrationEnabled ?? integrationSwitchIsOn else {
            return
        }

        desiredIntegrationEnabled = isEnabled
        integrationSwitchIsOn = isEnabled
        startIntegrationConvergenceIfNeeded()
    }

    /// Applies the desired integration state, and waits for it to settle.
    @discardableResult
    func setIntegrationEnabledAndWait(_ isEnabled: Bool) async -> Bool {
        setIntegrationEnabled(isEnabled)
        await integrationTask?.value
        return integrationSwitchIsOn == isEnabled
    }

    /// Starts the convergence loop unless one is already running.
    ///
    /// No revision gate here on purpose. ``desiredIntegrationEnabled`` already
    /// records that work is outstanding -- the loop runs until it is nil -- so
    /// a gate alongside it would be a second, redundant copy of the same fact,
    /// and two sources of truth for "is more work pending" is worse than one.
    ///
    /// A plain task handle is safe because both the check and the clear happen
    /// on the main actor with no suspension between the loop's last read of
    /// the desired state and the handle being released.
    private func startIntegrationConvergenceIfNeeded() {
        guard integrationService != nil, integrationTask == nil else { return }
        integrationTask = Task { [weak self] in
            guard let self else { return }
            while self.desiredIntegrationEnabled != nil {
                await self.convergeIntegrationOnce()
            }
            self.integrationTask = nil
        }
    }

    private func convergeIntegrationOnce() async {
        guard let desired = desiredIntegrationEnabled else { return }

        let succeeded = desired
            ? await installIntegrationHooksAndWait()
            : await removeIntegrationAndWait()

        // Someone flipped it again while this was running; that flip owns the
        // switch now, so this outcome must not write over it.
        guard desiredIntegrationEnabled == desired else { return }
        desiredIntegrationEnabled = nil

        if succeeded {
            // Re-read health rather than trusting the requested value: the
            // install may have landed in reviewRequired rather than active.
            if let service = integrationService {
                let status = await service.hookSetupStatus()
                hookSetupStatus = status
                integrationSwitchIsOn = status.isIntegrationEnabled
            }
        } else {
            integrationSwitchIsOn = !desired
        }
    }

    @discardableResult
    func installIntegrationHooksAndWait() async -> Bool {
        guard let service = integrationService, !isInstallingIntegration else {
            return false
        }
        isInstallingIntegration = true
        defer { isInstallingIntegration = false }

        do {
            try await service.installHooks()
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
        guard let service = integrationService, !isRemovingIntegration else {
            return false
        }
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
        refreshEventTask?.cancel()
        let services = services
        Task {
            for service in services {
                await service.disconnect()
            }
        }
    }

    /// Runs one refresh cycle and waits for every product to answer.
    func refreshAndWaitForTesting() async {
        await refreshAndWait()
    }

    /// The instant the loop would next wake for, or nil when only the heartbeat
    /// is left. Exposed so the deadline arithmetic is assertable without
    /// running the loop.
    func nextWakeUpForTesting() async -> Date? {
        (
            await providerDeadlines() + stabilityGates.values.map(\.nextPublishDeadline)
        ).compactMap { $0 }.min()
    }

    /// Feeds one product's answer through the same path a refresh uses, so a
    /// test exercises the merge rather than bypassing it.
    func applyForTesting(
        _ snapshot: AgentSnapshot,
        observedAt: Date? = nil
    ) {
        record(snapshot, observedAt: observedAt ?? clock.now())
    }

    private func scheduleHoverAction(
        after delay: TimeInterval,
        action: @escaping @MainActor (MonitorStore) -> Void
    ) {
        cancelPendingHoverAction()

        pendingHoverTask = Task { [weak self] in
            guard let self else { return }
            try? await clock.sleep(seconds: delay)
            guard !Task.isCancelled else { return }
            action(self)
        }
    }

    private func cancelPendingHoverAction() {
        pendingHoverTask?.cancel()
        pendingHoverTask = nil
    }

    private func startMonitoring() {
        guard !services.isEmpty else { return }

        // Refreshes are driven by the directory watchers below. This loop only
        // sleeps until the next moment the service says its own output could
        // change -- a settling window expiring, a cache going stale -- and
        // otherwise idles until the heartbeat. It samples nothing on a cadence.
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAndWait()
                guard !Task.isCancelled, let self else { return }

                let heartbeat = timing.heartbeatInterval
                // The gates' own deadlines count: a suppressed disconnect has
                // to be re-examined when its grace expires, not whenever some
                // provider happens to want attention next.
                let deadline = (
                    await self.providerDeadlines()
                        + self.stabilityGates.values.map(\.nextPublishDeadline)
                ).compactMap { $0 }.min()
                // An overdue deadline is clamped up to the floor, never down to
                // zero. Sleeping zero here re-runs a full snapshot -- a
                // LaunchServices round trip on the main thread and several stat
                // calls -- against a deadline the refresh cannot move, which is
                // a busy loop, not a catch-up.
                let untilDeadline = deadline.map {
                    max(
                        self.timing.minimumRefreshInterval,
                        $0.timeIntervalSince(self.clock.now())
                    )
                } ?? heartbeat
                try? await clock.sleep(seconds: min(heartbeat, untilDeadline))
            }
        }

        if let refreshEvents {
            refreshEventTask = Task { [weak self] in
                for await _ in refreshEvents {
                    guard !Task.isCancelled else { return }
                    // A watcher signal only has to converge, so it does not
                    // wait -- but it must not be dropped either, which is what
                    // the gate guarantees.
                    self?.requestRefresh()
                }
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
        // Re-aggregated rather than taken from the snapshot: a dismissed row
        // must stop counting towards the summary the moment it stops showing.
        let aggregateStatus = MonitorAggregation.status(
            agents: snapshot.agents,
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
        if statusAgent != snapshot.availabilityAgent {
            statusAgent = snapshot.availabilityAgent
        }
        if lastIntegrationMessage != integrationMessage {
            lastIntegrationMessage = integrationMessage
        }
    }

    /// Records one product's answer and republishes the merge.
    ///
    /// Each product is gated against its *own* previous availability, so a blip
    /// on one cannot suppress another's publish, and a product that is
    /// suppressed keeps its last trusted answer rather than dropping out of the
    /// merge entirely — its rows stay where they were.
    private func record(_ snapshot: AgentSnapshot, observedAt: Date) {
        let agent = snapshot.agent
        var gate = stabilityGates[agent] ?? ConnectionStabilityGate(
            gracePeriod: timing.disconnectGracePeriod
        )
        let shouldPublish = gate.shouldPublish(
            candidate: snapshot.availability,
            current: latestByAgent[agent]?.availability ?? .connecting,
            observedAt: observedAt
        )
        stabilityGates[agent] = gate

        guard shouldPublish else {
            let reason = snapshot.diagnostic ?? "\(agent.displayName) 暂时没有响应。"
            let retryMessage = "检测到瞬时连接异常，正在重试：\(reason)"
            if lastIntegrationMessage != retryMessage {
                lastIntegrationMessage = retryMessage
            }
            return
        }

        latestByAgent[agent] = snapshot
        setupStatusByAgent[agent] = snapshot.setupStatus
        refreshManualSetupIfNeeded(for: agent)
        apply(AgentSnapshotMerge.merge(Array(latestByAgent.values)))
        applyIntegrationHealth(for: agent)
    }

    /// What a product's own boundary reported, before merging.
    func agentAvailability(for agent: AgentKind) -> MonitorAvailability? {
        latestByAgent[agent]?.availability
    }

    /// How far along a product's registration is.
    func setupStatus(for agent: AgentKind) -> HookSetupStatus {
        setupStatusByAgent[agent] ?? .notInstalled
    }

    /// Re-reads the instructions when a product answers.
    ///
    /// Not inline in the refresh: rendering the snippet reads the user's
    /// settings file, and an open panel does not need that once a second.
    private func refreshManualSetupIfNeeded(for agent: AgentKind) {
        guard manualSetupTask == nil,
              let service = services.first(where: { $0.agent == agent }) else {
            return
        }
        manualSetupTask = Task { [weak self] in
            let setup = await service.manualSetup()
            guard let self else { return }
            self.manualSetupTask = nil
            guard self.manualSetups[agent] != setup else { return }
            if let setup {
                self.manualSetups[agent] = setup
            } else {
                self.manualSetups.removeValue(forKey: agent)
            }
        }
    }

    /// Keeps the integration card in step with the product it belongs to.
    private func applyIntegrationHealth(for agent: AgentKind) {
        guard agent == Self.integrationCardAgent,
              let refreshed = setupStatusByAgent[agent] else { return }
        if hookSetupStatus != refreshed {
            hookSetupStatus = refreshed
        }
        if !isInstallingIntegration,
           !isRemovingIntegration,
           integrationSwitchIsOn != refreshed.isIntegrationEnabled {
            integrationSwitchIsOn = refreshed.isIntegrationEnabled
        }
    }

    /// Each provider's next deadline, with providers that cannot advance their
    /// own dropped.
    ///
    /// A provider that reports the same already-overdue instant twice has said
    /// everything it is going to say about it. Leaving it in the shared minimum
    /// would pin the loop to the refresh floor and drag every healthy provider
    /// into a full merged refresh every second alongside it.
    private func providerDeadlines() async -> [Date?] {
        var deadlines: [Date?] = []
        let now = clock.now()
        for service in services {
            let agent = service.agent
            guard let deadline = await service.nextRefreshDeadline() else {
                stuckDeadlines[agent] = nil
                continue
            }
            if deadline <= now, stuckDeadlines[agent] == deadline {
                continue
            }
            stuckDeadlines[agent] = deadline <= now ? deadline : nil
            deadlines.append(deadline)
        }
        return deadlines
    }

    /// Requests a refresh without waiting for it.
    ///
    /// For triggers that only need the state to converge -- the monitor loop,
    /// the directory watchers. If one is already running, this raises the gate
    /// so another follows; it is never dropped.
    private func requestRefresh() {
        refreshGate.request()
        startRefreshRunIfNeeded()
    }

    /// Requests a refresh and waits for one that accounts for this request.
    ///
    /// For the user pressing Recheck. It used to call `performRefresh`, which
    /// returned immediately whenever an automatic refresh happened to be in
    /// flight -- so the button finished instantly and handed back the status it
    /// already had (CR-008). Waiting on the gate's own revision is what makes
    /// "I asked, so tell me what is true now" mean something.
    private func refreshAndWait() async {
        let revision = refreshGate.request()
        startRefreshRunIfNeeded()

        // At most two iterations: a run that begins after this request covers
        // it, and revisions only move forward.
        while !refreshGate.hasCovered(revision) {
            guard let refreshTask else { break }
            await refreshTask.value
        }
    }

    private func startRefreshRunIfNeeded() {
        guard !services.isEmpty, refreshGate.beginRun() else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                await self.performRefresh()
            } while self.refreshGate.endRun()
        }
    }

    /// Asks every product at once and publishes each answer as it lands.
    ///
    /// Publishing per answer rather than after the whole group is what keeps a
    /// slow provider from holding up a fast one: the fast product's rows are on
    /// screen while the slow one is still being asked. The group is still
    /// awaited, so a caller that wants "everyone has answered" — Recheck — gets
    /// exactly that.
    ///
    /// Nothing here cancels a slow fetch. Cancelling throws the work away and
    /// the next cycle starts it again, which is how "slow" turns into "never";
    /// each provider is responsible for bounding its own request instead.
    private func performRefresh() async {
        guard !services.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for service in services {
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    let snapshot = await service.fetchSnapshot(
                        showsContentPreviews: self.showsContentPreviews
                    )
                    guard !Task.isCancelled else { return }
                    // The snapshot already carries the health the same refresh
                    // observed; asking again would consume the Hook queue twice
                    // a cycle.
                    self.record(snapshot, observedAt: self.clock.now())
                }
            }
        }
    }

    private static var previewSnapshot: AgentSnapshot {
        // SwiftUI preview fixture: display data, not a timing decision.
        let now = Date()
        return AgentSnapshot(
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
