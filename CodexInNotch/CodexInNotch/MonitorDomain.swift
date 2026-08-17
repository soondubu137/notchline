import Foundation

/// Which product a row came from.
///
/// Declaration order is display order, and it never changes: Codex leads the
/// matrix pair and wins ties in the row list whatever either product is doing.
/// Once the two hues are learned, position is the only thing identifying a
/// matrix — sorting the pair by urgency would swap the marks under the user's
/// eye at the exact moment they are being read.
enum AgentKind: String, CaseIterable, Codable, Sendable, Comparable {
    case codex
    case claudeCode

    var displayName: String {
        switch self {
        case .codex:
            "Codex"
        case .claudeCode:
            "Claude Code"
        }
    }

    /// Where this product sits in the fixed order.
    private var rank: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }

    nonisolated static func < (lhs: AgentKind, rhs: AgentKind) -> Bool {
        lhs.rank < rhs.rank
    }
}

enum MonitorStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case idle
    case setupRequired
    case connecting
    case running
    case inputNeeded
    case approvalNeeded
    case completed
    case updateAgent
    case unsupportedVersion
    case disconnected

    var id: Self { self }

    /// The panel's full sentence for this state.
    ///
    /// Four of these name a product, so they are told which one rather than
    /// spelling Codex into the enum. Adding a case per product would have been
    /// the other way to do it, and it is the wrong way: every panel width is
    /// derived by folding over `allCases`, so a `.updateClaudeCode` case would
    /// widen the pill for a user who has never installed Claude Code.
    ///
    /// A `nil` product means no single one owns the state — either nothing is
    /// wrong, or more than one product is unhealthy and naming just one of them
    /// would be a lie.
    func displayName(for agent: AgentKind?) -> String {
        switch self {
        case .idle:
            "Idle"
        case .setupRequired:
            "Set up integration"
        case .connecting:
            agent.map { "Connecting to \($0.displayName)" } ?? "Connecting"
        case .running:
            "Running"
        case .inputNeeded:
            "Input needed"
        case .approvalNeeded:
            "Approval needed"
        case .completed:
            "Completed"
        case .updateAgent:
            agent.map { "Update \($0.displayName)" } ?? "Update required"
        case .unsupportedVersion:
            agent.map { "\($0.displayName) version unsupported" }
                ?? "Version unsupported"
        case .disconnected:
            agent.map { "\($0.displayName) disconnected" } ?? "Disconnected"
        }
    }

    /// The name the notch shows, which is shorter than ``displayName``.
    ///
    /// The matrix beside it already says a turn wants the user, so the label
    /// only has to say which kind — "needed" repeats the indicator. Dropping
    /// "Codex" costs nothing in the app's own menu bar item either. The panel
    /// still shows the full sentence, so this is a shorter form, not less
    /// information.
    ///
    /// Only one of these names a product, and it is the one that sets the
    /// widest compact label — so the product a panel is configured for is what
    /// decides how wide that panel is.
    func compactDisplayName(for agent: AgentKind?) -> String {
        switch self {
        case .idle:
            "Idle"
        case .setupRequired:
            "Set up"
        case .connecting:
            "Connecting"
        case .running:
            "Running"
        case .inputNeeded:
            "Input"
        case .approvalNeeded:
            "Approval"
        case .completed:
            "Completed"
        case .updateAgent:
            agent.map { "Update \($0.displayName)" } ?? "Update"
        case .unsupportedVersion:
            "Unsupported"
        case .disconnected:
            "Disconnected"
        }
    }

    /// Whether the notch can show an elapsed timer beside this status.
    ///
    /// The notch times the longest unfinished turn, and the aggregate of an
    /// unfinished turn is always one of these three.
    var canShowElapsed: Bool {
        switch self {
        case .running, .inputNeeded, .approvalNeeded:
            true
        default:
            false
        }
    }

    func controlTitle(for agent: AgentKind?) -> String {
        let product = agent?.displayName ?? "智能体"
        switch self {
        case .idle:
            return "空闲"
        case .setupRequired:
            return "设置 \(product) 集成"
        case .connecting:
            return "正在连接"
        case .running:
            return "运行中"
        case .inputNeeded:
            return "需要输入"
        case .approvalNeeded:
            return "等待批准"
        case .completed:
            return "已完成"
        case .updateAgent:
            return "需要更新 \(product)"
        case .unsupportedVersion:
            return "\(product) 版本不受支持"
        case .disconnected:
            return "连接中断"
        }
    }

    var isRunning: Bool {
        self == .running
    }
}

enum SessionStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case running
    case inputNeeded
    case approvalNeeded
    case completed

    var id: Self { self }

    var displayName: String {
        switch self {
        case .running:
            "Running"
        case .inputNeeded:
            "Input needed"
        case .approvalNeeded:
            "Approval needed"
        case .completed:
            "Completed"
        }
    }

    var controlTitle: String {
        switch self {
        case .running:
            "运行中"
        case .inputNeeded:
            "需要输入"
        case .approvalNeeded:
            "等待批准"
        case .completed:
            "已完成"
        }
    }

    var isRunning: Bool {
        self == .running
    }

    /// Whether the turn's clock is still counting.
    ///
    /// Every state but `completed` counts. A turn parked on input or approval
    /// is still occupying the user's attention -- that wait is the part worth
    /// seeing -- so the timer deliberately does not pause for it.
    var keepsTiming: Bool {
        self != .completed
    }

    var monitorStatus: MonitorStatus {
        switch self {
        case .running:
            .running
        case .inputNeeded:
            .inputNeeded
        case .approvalNeeded:
            .approvalNeeded
        case .completed:
            .completed
        }
    }

    nonisolated func transitioned(on signal: SessionStatusSignal) -> SessionStatus {
        if self == .completed {
            return .completed
        }
        if case .completed = signal { return .completed }

        switch (self, signal) {
        case (_, .running):
            return .running
        case (.running, .inputNeeded), (.inputNeeded, .inputNeeded):
            return .inputNeeded
        case (.running, .approvalNeeded), (.approvalNeeded, .approvalNeeded):
            return .approvalNeeded
        default:
            return self
        }
    }
}

enum SessionStatusSignal: Sendable {
    case running
    case inputNeeded
    case approvalNeeded
    case completed
}

enum MonitorAvailability: Equatable, Sendable {
    case setupRequired
    case connecting
    case ready
    case updateAgent
    case unsupportedVersion
    case disconnected

    var status: MonitorStatus {
        switch self {
        case .setupRequired:
            .setupRequired
        case .connecting:
            .connecting
        case .ready:
            .idle
        case .updateAgent:
            .updateAgent
        case .unsupportedVersion:
            .unsupportedVersion
        case .disconnected:
            .disconnected
        }
    }

    /// How much this state asks of the user, for choosing which unhealthy
    /// product speaks when none is ready. Something to do outranks something to
    /// wait for.
    var actionRank: Int {
        switch self {
        case .ready:
            0
        case .connecting:
            1
        case .disconnected:
            2
        case .unsupportedVersion:
            3
        case .updateAgent:
            4
        case .setupRequired:
            5
        }
    }

    func emptyListMessage(for agent: AgentKind?) -> String {
        switch self {
        case .setupRequired:
            "Set up integration"
        case .ready:
            "No active turns"
        case .connecting, .updateAgent, .unsupportedVersion, .disconnected:
            // The same sentence the panel header shows, so the two cannot drift.
            status.displayName(for: agent)
        }
    }
}

/// What a user has to do by hand to register a product's hooks.
///
/// Only exists for a product this app will not set up for them, which today is
/// Claude Code alone: its settings file holds their whole install, and the
/// blast radius of a bad edit is why the app reads that file and never writes
/// it (ADR 0010).
nonisolated struct AgentManualSetup: Sendable, Equatable {
    let agent: AgentKind
    /// The file to edit.
    let settingsURL: URL
    /// The block to add to it.
    let configurationSnippet: String
}

struct MonitoredSession: Identifiable, Equatable, Sendable {
    let agent: AgentKind
    let threadID: String
    let turnID: String
    let projectName: String
    let title: String
    let privacySafeTitle: String
    let preview: String?
    let status: SessionStatus
    let startedAt: Date?

    nonisolated init(
        agent: AgentKind = .codex,
        threadID: String,
        turnID: String,
        projectName: String,
        title: String,
        privacySafeTitle: String? = nil,
        preview: String?,
        status: SessionStatus,
        startedAt: Date?
    ) {
        self.agent = agent
        self.threadID = threadID
        self.turnID = turnID
        self.projectName = projectName
        self.title = title
        self.privacySafeTitle = privacySafeTitle ?? title
        self.preview = preview
        self.status = status
        self.startedAt = startedAt
    }

    /// The row's identity, and the key for the dismissed set, the terminal
    /// membership gate and SwiftUI's row identity.
    ///
    /// Namespaced by product because thread and turn ids are each product's own
    /// invention: nothing stops Claude Code from minting a session id that a
    /// Codex thread already uses, and an id collision between two products
    /// would silently make one row dismiss, hide or re-render the other.
    nonisolated var id: String {
        "\(agent.rawValue):\(threadID):\(turnID)"
    }

    func hidingContent() -> MonitoredSession {
        MonitoredSession(
            agent: agent,
            threadID: threadID,
            turnID: turnID,
            projectName: projectName,
            title: privacySafeTitle,
            privacySafeTitle: privacySafeTitle,
            preview: nil,
            status: status,
            startedAt: startedAt
        )
    }
}

/// One rate-limit window, and what is left of it.
///
/// A window has a label because a product can have more than one. Codex has a
/// single primary window and its rule spans the footer unlabelled; Claude Code
/// reports a 5-hour session window and a 7-day one, and the footer halves for
/// them -- not to fit them in, but because that side genuinely has two.
nonisolated struct QuotaWindow: Equatable, Sendable {
    /// Empty when the product has only one window to draw.
    let label: String
    let remainingPercent: Int?
    let resetsAt: Date?

    nonisolated init(label: String = "", remainingPercent: Int?, resetsAt: Date?) {
        self.label = label
        self.remainingPercent = remainingPercent.map { min(max($0, 0), 100) }
        self.resetsAt = resetsAt
    }
}

struct QuotaSnapshot: Equatable, Sendable {
    let windows: [QuotaWindow]
    let todayTokens: Int64?

    nonisolated static let unavailable = QuotaSnapshot(
        remainingPercent: nil,
        resetsAt: nil,
        todayTokens: nil
    )

    nonisolated init(windows: [QuotaWindow], todayTokens: Int64? = nil) {
        self.windows = windows
        self.todayTokens = todayTokens.map { max(0, $0) }
    }

    /// The single-window form, which is what one product's quota looks like.
    nonisolated init(
        remainingPercent: Int?,
        resetsAt: Date?,
        todayTokens: Int64? = nil
    ) {
        self.init(
            windows: [
                QuotaWindow(remainingPercent: remainingPercent, resetsAt: resetsAt)
            ],
            todayTokens: todayTokens
        )
    }

    /// The first window, for every surface that draws one rule.
    nonisolated var remainingPercent: Int? { windows.first?.remainingPercent }
    nonisolated var resetsAt: Date? { windows.first?.resetsAt }
}

/// What one product's provider observed on one refresh.
struct AgentSnapshot: Equatable, Sendable {
    let agent: AgentKind
    let availability: MonitorAvailability
    let sessions: [MonitoredSession]
    let quota: QuotaSnapshot
    let diagnostic: String?
    /// Integration health as observed by the same refresh that built this
    /// snapshot. It rides along so the store never has to ask a second time --
    /// asking used to consume the Hook queue a second time per cycle.
    let setupStatus: HookSetupStatus

    nonisolated init(
        agent: AgentKind = .codex,
        availability: MonitorAvailability,
        sessions: [MonitoredSession],
        quota: QuotaSnapshot,
        diagnostic: String?,
        setupStatus: HookSetupStatus = .active
    ) {
        self.agent = agent
        self.availability = availability
        self.sessions = sessions
        self.quota = quota
        self.diagnostic = diagnostic
        self.setupStatus = setupStatus
    }

    static let connecting = AgentSnapshot(
        availability: .connecting,
        sessions: [],
        quota: .unavailable,
        diagnostic: nil,
        setupStatus: .notInstalled
    )
}

/// Every product's answer, folded into the one thing the UI reads.
///
/// Keeping this a single type is the architectural constraint that survives
/// adding a product: views render a snapshot and never assemble state from
/// several sources themselves.
struct MonitorSnapshot: Equatable, Sendable {
    /// Ordered by ``AgentKind``, so Codex always leads.
    let agents: [AgentSnapshot]
    /// Every product's rows, merged and totally ordered.
    let sessions: [MonitoredSession]
    let status: MonitorStatus

    nonisolated init(
        agents: [AgentSnapshot],
        sessions: [MonitoredSession],
        status: MonitorStatus
    ) {
        self.agents = agents.sorted { $0.agent < $1.agent }
        self.sessions = sessions
        self.status = status
    }

    nonisolated func agent(_ kind: AgentKind) -> AgentSnapshot? {
        agents.first { $0.agent == kind }
    }

    /// The availability the surface speaks with.
    ///
    /// Ready if any product is being watched properly — a product that is
    /// unhealthy and has nothing to show is indistinguishable from a product
    /// that simply has nothing to show, and for the user the conclusion is the
    /// same. Only when no product is ready does an unhealthy one get to speak,
    /// and then it is the most actionable of them.
    nonisolated var availability: MonitorAvailability {
        MonitorAggregation.availability(agents: agents)
    }

    /// Whose problem the summary is describing, or `nil` when it is nobody's.
    ///
    /// The status label has to name a product to say "Codex disconnected", and
    /// it has to *not* name one when two products are equally unhealthy —
    /// naming just one of them would be a lie about the other.
    nonisolated var availabilityAgent: AgentKind? {
        let availability = self.availability
        guard availability != .ready else { return nil }
        let owners = agents
            .filter { $0.availability == availability }
            .map(\.agent)
        return owners.count == 1 ? owners.first : nil
    }

    /// The single quota window the footer draws while one product is running.
    /// A two-product footer reads ``agents`` directly, because it has one rule
    /// per product rather than one rule.
    nonisolated var quota: QuotaSnapshot {
        agents.first?.quota ?? .unavailable
    }

    nonisolated var diagnostic: String? {
        let reported = agents.compactMap { snapshot in
            snapshot.diagnostic.map { (snapshot.agent, $0) }
        }
        guard let first = reported.first else { return nil }
        // One product's diagnostic has to say whose it is once there are two,
        // or "disconnected" reads as a statement about the whole surface.
        guard agents.count > 1 else { return first.1 }
        return reported
            .map { "\($0.0.displayName)：\($0.1)" }
            .joined(separator: "\n")
    }

    static let connecting = MonitorSnapshot(
        agents: [.connecting],
        sessions: [],
        status: .connecting
    )
}

enum AgentSnapshotMerge {
    /// Folds every product's answer into the one snapshot the UI reads.
    ///
    /// Pure by design: no actor, no clock, no I/O. Everything about how two
    /// products combine is decided here, where it can be tested as a value.
    nonisolated static func merge(_ snapshots: [AgentSnapshot]) -> MonitorSnapshot {
        let agents = snapshots.sorted { $0.agent < $1.agent }
        let sessions = agents.flatMap(\.sessions).sorted(by: MonitorAggregation.rowOrder)
        return MonitorSnapshot(
            agents: agents,
            sessions: sessions,
            status: MonitorAggregation.status(agents: agents, sessions: sessions)
        )
    }
}

enum MonitorAggregation {
    /// Rows first, availability second.
    ///
    /// A live turn always outranks another product's unhealthy availability.
    /// Without that, a user who has merely seen the second product's settings
    /// row — and therefore has one agent reporting `setupRequired` — would find
    /// the notch reading "Set up integration" while the first product is
    /// perfectly happily running a turn.
    nonisolated static func status(
        agents: [AgentSnapshot],
        sessions: [MonitoredSession]
    ) -> MonitorStatus {
        let priority: [SessionStatus] = [
            .inputNeeded,
            .approvalNeeded,
            .running,
            .completed
        ]
        for status in priority where sessions.contains(where: { $0.status == status }) {
            return status.monitorStatus
        }
        return availability(agents: agents).status
    }

    /// Ready if any product is being watched properly; otherwise the most
    /// actionable of the unhealthy ones.
    nonisolated static func availability(
        agents: [AgentSnapshot]
    ) -> MonitorAvailability {
        guard !agents.isEmpty else { return .connecting }
        if agents.contains(where: { $0.availability == .ready }) {
            return .ready
        }
        return agents
            .map(\.availability)
            .max { $0.actionRank < $1.actionRank } ?? .connecting
    }

    /// The order rows appear in, and a total one.
    ///
    /// Priority, then most recent, then the fixed product order, then identity.
    /// The last two matter because ties stop being rare with a second product:
    /// its start times arrive as whole milliseconds and a batch of sessions can
    /// share one. Two rows that compare equal both ways may be placed either
    /// way round on each refresh, which reads as a list shuffling itself while
    /// it is being looked at.
    nonisolated static func rowOrder(
        _ lhs: MonitoredSession,
        _ rhs: MonitoredSession
    ) -> Bool {
        let priority: [SessionStatus: Int] = [
            .inputNeeded: 0,
            .approvalNeeded: 1,
            .running: 2,
            .completed: 3
        ]
        let lhsPriority = priority[lhs.status] ?? Int.max
        let rhsPriority = priority[rhs.status] ?? Int.max
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        let lhsStart = lhs.startedAt ?? .distantPast
        let rhsStart = rhs.startedAt ?? .distantPast
        if lhsStart != rhsStart {
            return lhsStart > rhsStart
        }
        if lhs.agent != rhs.agent {
            return lhs.agent < rhs.agent
        }
        return lhs.id < rhs.id
    }
}

/// How long a turn has been running, for the notch and the session rows.
///
/// The value is always `now - startedAt` recomputed from scratch, never a total
/// accumulated tick by tick. That is what makes it wall-clock: a wait on input
/// or approval, a missed refresh and a sleeping Mac all land in the elapsed time
/// without the timer having to observe them.
///
/// `now` is a parameter rather than a `Date()` read so the format is assertable
/// at every boundary, the same way ``UsageSummaryFormatter`` takes one.
enum SessionElapsedFormatter {
    nonisolated static func elapsed(since startedAt: Date?, now: Date) -> String? {
        guard let seconds = elapsedSeconds(since: startedAt, now: now) else {
            return nil
        }

        let (hours, minutes, remainder) = components(of: seconds)
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }

    /// The same duration spelled out, because VoiceOver reads `12:34` as a time
    /// of day rather than a length.
    nonisolated static func spokenElapsed(since startedAt: Date?, now: Date) -> String? {
        guard let seconds = elapsedSeconds(since: startedAt, now: now) else {
            return nil
        }

        let (hours, minutes, remainder) = components(of: seconds)
        var parts: [String] = []
        if hours > 0 {
            parts.append("\(hours) 小时")
        }
        if minutes > 0 {
            parts.append("\(minutes) 分")
        }
        if remainder > 0 || parts.isEmpty {
            parts.append("\(remainder) 秒")
        }
        return parts.joined(separator: " ")
    }

    /// Whole seconds elapsed, or nil when there is nothing trustworthy to count.
    ///
    /// A start time in the future is clock skew, not a negative duration, and a
    /// turn whose start was never observed has no duration at all. Both read as
    /// "not timed" so no caller can render an invented number.
    nonisolated private static func elapsedSeconds(
        since startedAt: Date?,
        now: Date
    ) -> Int? {
        guard let startedAt else { return nil }
        let interval = now.timeIntervalSince(startedAt)
        guard interval >= 0, interval < TimeInterval(Int.max) else { return nil }
        return Int(interval)
    }

    nonisolated private static func components(
        of seconds: Int
    ) -> (hours: Int, minutes: Int, seconds: Int) {
        (seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
}

enum UsageSummaryFormatter {
    nonisolated private static let compactNumberStyle = FloatingPointFormatStyle<Double>
        .number
        .notation(.compactName)
        .precision(.significantDigits(1 ... 3))
        .locale(Locale(identifier: "en_US"))

    nonisolated static func compactTokenCount(_ tokenCount: Int64) -> String {
        Double(max(0, tokenCount)).formatted(compactNumberStyle)
    }

    /// Time remaining until the quota resets, as days and hours.
    ///
    /// This reads the remaining *duration*, not calendar days: "Resets today"
    /// was true at both 00:30 and 23:30 and told you nothing about which.
    nonisolated static func resetText(
        resetsAt: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        guard let resetsAt else { return "Reset unavailable" }

        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0 else { return "Resets now" }

        let totalHours = Int(remaining / 3600)
        let days = totalHours / 24
        let hours = totalHours % 24

        switch (days, hours) {
        case (0, 0):
            return "Resets in under an hour"
        case (0, _):
            return "Resets in \(hours) \(plural(hours, "hour"))"
        case (_, 0):
            return "Resets in \(days) \(plural(days, "day"))"
        default:
            return "Resets in \(days) \(plural(days, "day")) "
                + "\(hours) \(plural(hours, "hour"))"
        }
    }

    nonisolated private static func plural(_ count: Int, _ noun: String) -> String {
        count == 1 ? noun : noun + "s"
    }

    /// The footer line: everything about quota now lives here, so it carries the
    /// remaining share as well as today's spend and the reset window.
    nonisolated static func summary(
        remainingPercent: Int?,
        todayTokens: Int64?,
        resetsAt: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        let remainingText = remainingPercent.map { "\($0)% left" } ?? "-- left"
        let usageText = todayTokens.map { "\(compactTokenCount($0)) today" }
            ?? "-- today"
        let reset = resetText(resetsAt: resetsAt, now: now, calendar: calendar)
        return "\(remainingText) · \(usageText) · \(reset)"
    }
}
