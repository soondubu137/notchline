import Foundation

enum MonitorStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case idle
    case setupRequired
    case connecting
    case running
    case inputNeeded
    case approvalNeeded
    case completed
    case updateCodex
    case unsupportedVersion
    case disconnected

    var id: Self { self }

    var displayName: String {
        switch self {
        case .idle:
            "Idle"
        case .setupRequired:
            "Set up integration"
        case .connecting:
            "Connecting to Codex"
        case .running:
            "Running"
        case .inputNeeded:
            "Input needed"
        case .approvalNeeded:
            "Approval needed"
        case .completed:
            "Completed"
        case .updateCodex:
            "Update Codex"
        case .unsupportedVersion:
            "Codex version unsupported"
        case .disconnected:
            "Codex disconnected"
        }
    }

    /// The name the notch shows, which is shorter than ``displayName``.
    ///
    /// The matrix beside it already says a turn wants the user, so the label
    /// only has to say which kind — "needed" repeats the indicator. Dropping
    /// "Codex" costs nothing in the app's own menu bar item either. The panel
    /// still shows the full sentence, so this is a shorter form, not less
    /// information.
    var compactDisplayName: String {
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
        case .updateCodex:
            "Update Codex"
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

    var controlTitle: String {
        switch self {
        case .idle:
            "空闲"
        case .setupRequired:
            "设置 Codex 集成"
        case .connecting:
            "正在连接"
        case .running:
            "运行中"
        case .inputNeeded:
            "需要输入"
        case .approvalNeeded:
            "等待批准"
        case .completed:
            "已完成"
        case .updateCodex:
            "需要更新 Codex"
        case .unsupportedVersion:
            "Codex 版本不受支持"
        case .disconnected:
            "连接中断"
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
    case updateCodex
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
        case .updateCodex:
            .updateCodex
        case .unsupportedVersion:
            .unsupportedVersion
        case .disconnected:
            .disconnected
        }
    }

    var emptyListMessage: String {
        switch self {
        case .setupRequired:
            "Set up integration"
        case .connecting:
            "Connecting to Codex"
        case .ready:
            "No active turns"
        case .updateCodex:
            "Update Codex"
        case .unsupportedVersion:
            "Codex version unsupported"
        case .disconnected:
            "Codex disconnected"
        }
    }
}

struct MonitoredSession: Identifiable, Equatable, Sendable {
    let threadID: String
    let turnID: String
    let projectName: String
    let title: String
    let privacySafeTitle: String
    let preview: String?
    let status: SessionStatus
    let startedAt: Date?

    nonisolated init(
        threadID: String,
        turnID: String,
        projectName: String,
        title: String,
        privacySafeTitle: String? = nil,
        preview: String?,
        status: SessionStatus,
        startedAt: Date?
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.projectName = projectName
        self.title = title
        self.privacySafeTitle = privacySafeTitle ?? title
        self.preview = preview
        self.status = status
        self.startedAt = startedAt
    }

    nonisolated var id: String {
        "\(threadID):\(turnID)"
    }

    func hidingContent() -> MonitoredSession {
        MonitoredSession(
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

struct QuotaSnapshot: Equatable, Sendable {
    let remainingPercent: Int?
    let resetsAt: Date?
    let todayTokens: Int64?

    nonisolated static let unavailable = QuotaSnapshot(
        remainingPercent: nil,
        resetsAt: nil,
        todayTokens: nil
    )

    nonisolated init(
        remainingPercent: Int?,
        resetsAt: Date?,
        todayTokens: Int64? = nil
    ) {
        self.remainingPercent = remainingPercent.map {
            min(max($0, 0), 100)
        }
        self.resetsAt = resetsAt
        self.todayTokens = todayTokens.map { max(0, $0) }
    }
}

struct MonitorSnapshot: Equatable, Sendable {
    let availability: MonitorAvailability
    let sessions: [MonitoredSession]
    let quota: QuotaSnapshot
    let diagnostic: String?
    /// Integration health as observed by the same refresh that built this
    /// snapshot. It rides along so the store never has to ask a second time --
    /// asking used to consume the Hook queue a second time per cycle.
    let setupStatus: HookSetupStatus

    nonisolated init(
        availability: MonitorAvailability,
        sessions: [MonitoredSession],
        quota: QuotaSnapshot,
        diagnostic: String?,
        setupStatus: HookSetupStatus = .active
    ) {
        self.availability = availability
        self.sessions = sessions
        self.quota = quota
        self.diagnostic = diagnostic
        self.setupStatus = setupStatus
    }

    static let connecting = MonitorSnapshot(
        availability: .connecting,
        sessions: [],
        quota: .unavailable,
        diagnostic: nil,
        setupStatus: .notInstalled
    )
}

enum MonitorAggregation {
    static func status(
        availability: MonitorAvailability,
        sessions: [MonitoredSession]
    ) -> MonitorStatus {
        guard availability == .ready else {
            return availability.status
        }

        let priority: [SessionStatus] = [
            .inputNeeded,
            .approvalNeeded,
            .running,
            .completed
        ]

        for status in priority where sessions.contains(where: { $0.status == status }) {
            return status.monitorStatus
        }
        return .idle
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
