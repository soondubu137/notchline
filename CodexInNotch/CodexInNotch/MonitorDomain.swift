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

enum UsageSummaryFormatter {
    nonisolated private static let compactNumberStyle = FloatingPointFormatStyle<Double>
        .number
        .notation(.compactName)
        .precision(.significantDigits(1 ... 3))
        .locale(Locale(identifier: "en_US"))

    nonisolated static func compactTokenCount(_ tokenCount: Int64) -> String {
        Double(max(0, tokenCount)).formatted(compactNumberStyle)
    }

    nonisolated static func resetText(
        resetsAt: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        guard let resetsAt else { return "Reset unavailable" }

        let today = calendar.startOfDay(for: now)
        let resetDay = calendar.startOfDay(for: resetsAt)
        let dayCount = max(
            0,
            calendar.dateComponents([.day], from: today, to: resetDay).day ?? 0
        )

        switch dayCount {
        case 0:
            return "Resets today"
        case 1:
            return "Resets in 1 day"
        default:
            return "Resets in \(dayCount) days"
        }
    }

    nonisolated static func summary(
        todayTokens: Int64?,
        resetsAt: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        let usageText = todayTokens.map(compactTokenCount) ?? "--"
        return "\(usageText) • \(resetText(resetsAt: resetsAt, now: now, calendar: calendar))"
    }
}
