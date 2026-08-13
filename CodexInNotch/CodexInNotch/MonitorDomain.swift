import Foundation

enum MonitorStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case idle
    case setupRequired
    case connecting
    case running
    case inputNeeded
    case approvalNeeded
    case completed
    case error
    case cancelled
    case unknown
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
        case .error:
            "Error"
        case .cancelled:
            "Cancelled"
        case .unknown:
            "Unknown"
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
        case .error:
            "发生错误"
        case .cancelled:
            "已取消"
        case .unknown:
            "状态未知"
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
    let status: MonitorStatus
    let startedAt: Date?

    nonisolated init(
        threadID: String,
        turnID: String,
        projectName: String,
        title: String,
        privacySafeTitle: String? = nil,
        preview: String?,
        status: MonitorStatus,
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

    var id: String {
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

    nonisolated static let unavailable = QuotaSnapshot(
        remainingPercent: nil,
        resetsAt: nil
    )

    nonisolated init(remainingPercent: Int?, resetsAt: Date?) {
        self.remainingPercent = remainingPercent.map {
            min(max($0, 0), 100)
        }
        self.resetsAt = resetsAt
    }
}

struct MonitorSnapshot: Equatable, Sendable {
    let availability: MonitorAvailability
    let sessions: [MonitoredSession]
    let quota: QuotaSnapshot
    let diagnostic: String?

    static let connecting = MonitorSnapshot(
        availability: .connecting,
        sessions: [],
        quota: .unavailable,
        diagnostic: nil
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

        let priority: [MonitorStatus] = [
            .inputNeeded,
            .approvalNeeded,
            .running,
            .error,
            .completed,
            .cancelled,
            .unknown
        ]

        for status in priority where sessions.contains(where: { $0.status == status }) {
            return status
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
