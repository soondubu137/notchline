import Foundation

/// Which product a row came from. Declaration order is display order and never changes: sorting
/// by urgency would swap the matrix marks while they are being read.
enum AgentKind: String, CaseIterable, Codable, Sendable, Comparable {
    case codex
    case claudeCode
    /// Antigravity: `agy` and Antigravity Desktop behind one hooks file (``AntigravitySurface``).
    /// L3 (`docs/product-support.md` §5): progress, no wait detection. The raw value is short
    /// enough for a socket path.
    case antigravity
    case trae

    var displayName: String {
        switch self {
        case .codex:
            "Codex"
        case .claudeCode:
            "Claude Code"
        case .antigravity:
            "Antigravity"
        case .trae:
            "Trae"
        }
    }

    private var rank: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }

    nonisolated static func < (lhs: AgentKind, rhs: AgentKind) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Whether a product is open, as the user would judge it. Not derived from work in flight:
/// presence draws the matrix, the Turn reducer lights it.
enum AgentPresence: String, CaseIterable, Codable, Sendable {
    case open
    case closed
    /// No trustworthy evidence either way: the source's last answer has expired. Drawn like
    /// `closed`, but may not delete state, since nobody answered (``ClaudeCodeMonitorService``
    /// pruning the Hook reducer).
    case unknown

    /// Only `open` is presence. Unknown is not a weak yes.
    var isOpen: Bool { self == .open }
}

enum MonitorStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case connected
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

    /// The one name every surface says for this state, with no shorter form and no product name.
    /// `running` is drawn as `Working...` while the case keeps its name; `Approval needed` is still
    /// the widest, so ``PanelMetrics`` is untouched. See `docs/figma-design.md` §6.4.
    var displayName: String {
        switch self {
        case .connected:
            "Connected"
        case .setupRequired:
            "Set up integration"
        case .connecting:
            "Connecting"
        case .running:
            "Working..."
        case .inputNeeded:
            "Input needed"
        case .approvalNeeded:
            "Approval needed"
        case .completed:
            "Completed"
        case .updateAgent:
            "Update required"
        case .unsupportedVersion:
            "Version unsupported"
        case .disconnected:
            "Disconnected"
        }
    }

    /// Whether the notch can show an elapsed timer: an unfinished turn's aggregate is always one
    /// of these three.
    var canShowElapsed: Bool {
        switch self {
        case .running, .inputNeeded, .approvalNeeded:
            true
        default:
            false
        }
    }

    /// Whether the collapsed surface is reporting that a person is wanted: the aggregate turn state,
    /// not the subagent flip (each badge flips on its own).
    var wantsPerson: Bool {
        self == .inputNeeded || self == .approvalNeeded
    }

    var isRunning: Bool {
        self == .running
    }

    /// The six values the collapsed surface may reach; the other four only appear in the panel and
    /// Settings. See `docs/figma-design.md` §6.4 and §6.6.
    static let collapsedReachable: Set<MonitorStatus> = [
        .connected,
        .disconnected,
        .running,
        .inputNeeded,
        .approvalNeeded,
        .completed
    ]
}

enum SessionStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case running
    case inputNeeded
    case approvalNeeded
    case completed

    var id: Self { self }

    /// Four of ``MonitorStatus/displayName``'s ten, spelled identically (`Working...` included).
    var displayName: String {
        switch self {
        case .running:
            "Working..."
        case .inputNeeded:
            "Input needed"
        case .approvalNeeded:
            "Approval needed"
        case .completed:
            "Completed"
        }
    }

    var isRunning: Bool {
        self == .running
    }

    /// Every state but `completed` counts: a wait on input or approval is the part worth timing.
    var keepsTiming: Bool {
        self != .completed
    }

    /// Whether this turn is stopped on something only a person can answer. The turn's own answer:
    /// rows combine it with ``MonitoredSession/subagentsAwaitingApproval``.
    var wantsPerson: Bool {
        self == .inputNeeded || self == .approvalNeeded
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
        // Approval gives way to input: Codex never closes a denied approval (tech-design §9.2), so the
        // following wait proves the human answered. Sequence within a turn, not rank (PRD §6.2).
        case (.running, .inputNeeded), (.inputNeeded, .inputNeeded),
             (.approvalNeeded, .inputNeeded):
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

    /// The sentence the expanded panel uses; the collapsed status also depends on presence
    /// (``AgentSnapshot/isConnected``). ``emptyListMessage(for:)`` handles `.ready` first.
    var status: MonitorStatus {
        switch self {
        case .setupRequired:
            .setupRequired
        case .connecting:
            .connecting
        case .ready:
            .connected
        case .updateAgent:
            .updateAgent
        case .unsupportedVersion:
            .unsupportedVersion
        case .disconnected:
            .disconnected
        }
    }

    /// Which unhealthy product speaks when none is ready: something to do outranks something to
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

    var emptyListMessage: String {
        switch self {
        case .setupRequired:
            "Set up integration"
        case .ready:
            "No active sessions"
        case .connecting, .updateAgent, .unsupportedVersion, .disconnected:
            // Same sentence as the panel header.
            status.displayName
        }
    }
}

/// What a product's monitoring has left on disk. Reported, never acted on; nil for a product
/// like Codex that writes nothing.
nonisolated struct AgentDiskFootprint: Sendable, Equatable {
    let directory: URL
    let byteCount: Int64

    nonisolated init(directory: URL, byteCount: Int64) {
        self.directory = directory
        self.byteCount = max(0, byteCount)
    }

    /// `43.2 MB`: the size alone.
    nonisolated var summary: String {
        byteCount.formatted(.byteCount(style: .file))
    }
}

/// A footprint, or why there is none yet. Claude Code's folder is located from a reading that
/// takes seconds, and "not measured yet" must differ from "leaves nothing" (CC-020).
nonisolated enum AgentDiskFootprintReport: Sendable, Equatable {
    /// Writes nothing the user could want back, so no row. Codex, permanently.
    case leavesNothing
    /// Leaves files; a reading is out and nothing has returned yet.
    case measuring
    case measured(AgentDiskFootprint)
    /// Leaves files, but this app cannot say where or how much: the attempt failed or never
    /// happens (e.g. no Claude Code installed). Unlike ``measuring``, nothing is on its way.
    case unavailable

    /// The trailing readout; empty only for ``leavesNothing``, which draws no row.
    nonisolated var summary: String {
        switch self {
        case .leavesNothing: ""
        case .measuring: "Calculating…"
        case .measured(let footprint): footprint.summary
        case .unavailable: "Unavailable"
        }
    }

    /// The folder to open; nil also greys the button out.
    nonisolated var directory: URL? {
        guard case .measured(let footprint) = self else { return nil }
        return footprint.directory
    }
}

/// The words this app supplies when a product cannot name its own project, title, or live
/// progress; applied once for every product, in `MonitoredSession`'s initialiser and
/// ``MonitorStore/previewLine(for:)``.
enum RowContentFallback {
    nonisolated static let projectName = "Untitled Project"
    /// A Project the product has but could not be read: fails closed instead of reading as
    /// ``projectName``. Supplied by the product's own resolution, not the initialiser.
    nonisolated static let unavailableProjectName = "Project unavailable"
    nonisolated static let title = "Untitled Session"
    /// Matches ``SessionStatus/displayName`` for `running`.
    nonisolated static let liveProgress = "Working..."
}

struct MonitoredSession: Identifiable, Equatable, Sendable {
    let agent: AgentKind
    let threadID: String
    let turnID: String
    let projectName: String
    let title: String
    let preview: String?
    let status: SessionStatus
    let startedAt: Date?
    /// Subagents this thread started that have not been seen to stop. Row data, not a fifth state:
    /// a subagent outlives its turn, so a Completed row can still have one in flight. Both products
    /// report it (Codex `spawn_agent`, Claude Code's `Agent` tool).
    let runningSubagentCount: Int
    /// How many of those subagents are sitting on a permission prompt. A subagent's
    /// `PermissionRequest` carries its `agent_id` and can arrive either side of the parent turn's
    /// terminal (measured on both products, 2026-08-23). The surface reads only `> 0`
    /// (`dual-agent-design.md` §10).
    let subagentsAwaitingApprovalCount: Int
    /// Whether this row's turn ended by pausing rather than finishing. Covers the 50-130 ms between
    /// an async subagent's `SubagentStop` and Claude Code re-entering the parent (measured
    /// 2026-08-23, CLI 2.1.241), which otherwise flashed `Completed`. Claude Code only, from `Stop`'s
    /// `background_tasks`; always false for Codex.
    let isPausedForBackgroundWork: Bool
    /// When this turn ended; `nil` on unfinished rows. Taken from the turn's last event, which is
    /// immune to subagent chatter (``HookTurnState/lastSubagentBoundaryAt``).
    let finishedAt: Date?
    /// What this row is being asked, where this app can show it: row data, not a fifth state.
    /// `nil` when not waiting or unreadable, which fails closed to the product. The first of
    /// ``requests``.
    let request: AgentRequest?
    /// Every request this row could open, in order (``MonitoredTurnState/requestsAwaitingAnAnswer``);
    /// drawn one at a time.
    let requests: [AgentRequest]

    nonisolated init(
        agent: AgentKind = .codex,
        threadID: String,
        turnID: String,
        projectName: String,
        title: String,
        preview: String?,
        status: SessionStatus,
        startedAt: Date?,
        runningSubagentCount: Int = 0,
        subagentsAwaitingApprovalCount: Int = 0,
        isPausedForBackgroundWork: Bool = false,
        finishedAt: Date? = nil,
        request: AgentRequest? = nil,
        requests: [AgentRequest]? = nil
    ) {
        self.agent = agent
        self.threadID = threadID
        self.turnID = turnID
        self.projectName = projectName.isEmpty ? RowContentFallback.projectName : projectName
        self.title = title.isEmpty ? RowContentFallback.title : title
        self.preview = preview
        self.status = status
        self.startedAt = startedAt
        self.runningSubagentCount = runningSubagentCount
        self.subagentsAwaitingApprovalCount = subagentsAwaitingApprovalCount
        self.isPausedForBackgroundWork = isPausedForBackgroundWork
        self.finishedAt = finishedAt
        self.requests = requests ?? request.map { [$0] } ?? []
        self.request = self.requests.first
    }

    nonisolated var hasRunningSubagent: Bool { runningSubagentCount > 0 }

    nonisolated var subagentsAwaitingApproval: Bool { subagentsAwaitingApprovalCount > 0 }

    /// One badge carrying the whole count; the ground flips when any subagent is stopped on a
    /// question, rather than a second numeral.
    nonisolated var subagentBadge: SubagentBadge {
        SubagentBadge(
            count: runningSubagentCount,
            wantsAttention: subagentsAwaitingApproval
        )
    }

    /// Only once the clock stops: a running row already says the thread is working, and a finished
    /// row with an empty slot would read as done.
    nonisolated var showsSubagentBadge: Bool {
        !status.keepsTiming && hasRunningSubagent
    }

    /// The spoken form of the row's badge, since VoiceOver cannot read a flipped ground: the count,
    /// then the state.
    nonisolated var spokenSubagentSummary: String? {
        guard showsSubagentBadge else { return nil }
        return subagentBadge.spokenSummary
    }

    /// The row's identity (dismissed set, terminal membership gate, SwiftUI). Namespaced by product:
    /// thread and turn ids from two products can collide.
    nonisolated var id: String {
        "\(agent.rawValue):\(threadID):\(turnID)"
    }
}

/// One row that has left the list, and when it left (`expanded-panel-v2.md` §2). Holds the row
/// as last drawn, so navigation needs no lookup. Never persisted; only departures this run
/// watched.
nonisolated struct RecentDeparture: Equatable, Sendable, Identifiable {
    /// What took the row off the list. Not drawn (§2.4 rule 05); kept because it cannot be recovered
    /// later, and deciding it tells a departure from a product that went quiet.
    enum Reason: Equatable, Sendable {
        /// Its product recorded the Turn as read.
        case read
        /// The user waved it away with a secondary click.
        case dismissed
        /// The same, on a Turn that had not finished.
        case dismissedWhileRunning
    }

    let session: MonitoredSession
    /// The instant this list stopped reporting the row; not ``MonitoredSession/finishedAt``. The age
    /// counts from this (§2.4 rule 05).
    let departedAt: Date
    let reason: Reason

    nonisolated init(
        session: MonitoredSession,
        departedAt: Date,
        reason: Reason
    ) {
        self.session = session
        self.departedAt = departedAt
        self.reason = reason
    }

    nonisolated var id: String { Self.key(for: session) }

    /// The queue's key: the Thread, not the Turn, so a Thread that submits again crosses the rule as
    /// the same row (§5), and its live row's arrival removes the queue entry.
    nonisolated static func key(for session: MonitoredSession) -> String {
        "\(session.agent.rawValue):\(session.threadID)"
    }

    nonisolated func age(at now: Date) -> TimeInterval {
        now.timeIntervalSince(departedAt)
    }

    /// The trailing reading: `now`, `2m`, `9m`, `1h`, `4h`. At most three characters: at five hours
    /// the row is gone (`expanded-panel-v2.md` §2.3).
    nonisolated func ageText(at now: Date) -> String {
        let seconds = max(age(at: now), 0)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        return "\(Int(seconds / 3600))h"
    }

    /// The same reading as words for screen readers (`expanded-panel-v2.md` §6).
    nonisolated func spokenAgeText(at now: Date) -> String {
        let seconds = max(age(at: now), 0)
        if seconds < 60 { return "left just now" }
        if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "left \(minutes) minute\(minutes == 1 ? "" : "s") ago"
        }
        let hours = Int(seconds / 3600)
        return "left \(hours) hour\(hours == 1 ? "" : "s") ago"
    }
}

/// What one subagent badge draws (`dual-agent-design.md` §10): ``count`` includes waiting
/// subagents; zero is not drawn. Neutral on a row, tinted per product on the collapsed surface.
nonisolated struct SubagentBadge: Equatable, Sendable {
    var count: Int = 0
    /// Whether any is stopped on an approval or an input: bright ground, dark numeral.
    var wantsAttention: Bool = false

    static let empty = SubagentBadge()

    var isEmpty: Bool { count == 0 }

    /// The spoken form, since VoiceOver cannot read a flipped ground.
    var spokenSummary: String? {
        guard count > 0 else { return nil }
        let subagents = count == 1 ? "1 subagent" : "\(count) subagents"
        return wantsAttention ? "\(subagents), waiting for you" : subagents
    }
}

/// One rate-limit window, and what is left of it. The label is the product's own name for it:
/// Codex publishes a duration, Claude Code `Current session`, `Current week (all models)` and a
/// per-model week.
nonisolated struct QuotaWindow: Equatable, Sendable {
    /// Empty only where the product publishes no name at all.
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

    /// One window with nothing known about it: the footer draws `-- left`.
    nonisolated static let unavailable = QuotaSnapshot(
        remainingPercent: nil,
        resetsAt: nil,
        todayTokens: nil
    )

    /// No windows at all: nothing this app reads and nothing awaited. The footer draws the product
    /// row with no inner lines (`quota-footer-v2.md` §5); ``unavailable`` would draw dashes forever.
    nonisolated static let noneReported = QuotaSnapshot(windows: [])

    nonisolated init(windows: [QuotaWindow], todayTokens: Int64? = nil) {
        self.windows = windows
        self.todayTokens = todayTokens.map { max(0, $0) }
    }

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

struct AgentSnapshot: Equatable, Sendable {
    let agent: AgentKind
    let availability: MonitorAvailability
    let sessions: [MonitoredSession]
    let quota: QuotaSnapshot
    let diagnostic: String?
    /// Integration health from the same refresh, so the store never asks (and drains the Hook
    /// queue) a second time.
    let setupStatus: IntegrationSetupStatus
    /// Whether the product itself is open, independent of observability: Codex from the
    /// running-application list, Claude Code from its live session list.
    let presence: AgentPresence
    let connection: ProductConnectionFacts

    nonisolated init(
        agent: AgentKind = .codex,
        availability: MonitorAvailability,
        sessions: [MonitoredSession],
        quota: QuotaSnapshot,
        diagnostic: String?,
        setupStatus: IntegrationSetupStatus = .active,
        presence: AgentPresence = .open,
        connection: ProductConnectionFacts? = nil
    ) {
        self.agent = agent
        self.availability = availability
        self.sessions = sessions
        self.quota = quota
        self.diagnostic = diagnostic
        self.setupStatus = setupStatus
        self.presence = presence
        self.connection = connection ?? ProductConnectionFacts.observed(
            setup: setupStatus, availability: availability, diagnostic: diagnostic)
    }

    /// Open and observable. Open but unregistered is an ordinary first run and reads disconnected.
    /// `.connecting` is not connected: reporting an unmade connection would be guessing.
    nonisolated var isConnected: Bool {
        presence.isOpen && availability == .ready
            && connection.activation != .unverified && connection.activation != .reloadRequired
    }

    static let connecting = AgentSnapshot(
        availability: .connecting,
        sessions: [],
        quota: .unavailable,
        diagnostic: nil,
        setupStatus: .notInstalled,
        presence: .unknown
    )
}

/// One quota window as the footer's table draws it: three strings, no fill
/// (`quota-footer-v2.md` §1.1).
nonisolated struct FooterWindow: Equatable, Sendable {
    /// The product's own name for this window: `Current session`, `All models`, `Fable`,
    /// `Weekly limit`. Empty only where none is published.
    let label: String
    /// `72% left` or `-- left`, held as two parts because only one can fail.
    let share: ShareReading
    /// `Resets in 4 hours 12 minutes`, `Not started`, or `--`.
    let timer: String
    /// What a screen reader hears instead of ``timer``, keeping the absolute day (§7).
    let spokenTimer: String
}

/// One product's group in the footer's table: products keep Settings' order, windows the
/// reader's; neither sorts (`quota-footer-v2.md` §8.6). A product with no limits draws no inner
/// lines.
nonisolated struct FooterRule: Identifiable, Equatable, Sendable {
    let agent: AgentKind
    /// This product's own tokens for today: `310.1M today`, or `-- today`.
    let today: SpendReading
    let windows: [FooterWindow]

    nonisolated var id: AgentKind { agent }
}

/// One mark on the collapsed surface. A product that is not connected has no mark, not a
/// dimmed one.
nonisolated struct PresenceMark: Equatable, Sendable {
    /// The product this mark belongs to, or nil for the resting grey.
    let agent: AgentKind?
    /// This product's own status; each matrix is an independent readout.
    let status: MonitorStatus
    /// How many rows this product has, drawn as dots beside its matrix: capped at three, the third
    /// stretching into a dash, `5.66` of wing (`dual-agent-design.md` §11). Zero for the resting mark.
    let sessionCount: Int
    /// Every subagent this product has in flight, summed across its rows: per product, since the badge
    /// is tinted.
    let subagents: SubagentBadge
    /// Whether this product's list holds a finished, unread Turn its own matrix is not drawing: the
    /// one state the summary loses, since `.completed` waits until read (`PRD.md` §7). Drives
    /// ``SessionCountDots``. A buried `.inputNeeded` does not set it (`figma-design.md` §4.1). Reads
    /// ``MonitorAggregation/effectiveStatus(of:)``.
    let buriesAFinishedTurn: Bool


    /// Whether this product holds a Turn the user still has to attend to: approval, input, or a
    /// finished unread Turn, including one ``buriesAFinishedTurn`` covers. Not
    /// ``MonitorStatus/wantsPerson`` plus a case. Read only with `Hide Notchline` on
    /// (``MonitorStore/drawsCompactMarks``, ``MonitorStore/tucksCompactPill``).
    var hasATurnToAttendTo: Bool {
        status.wantsPerson || status == .completed || buriesAFinishedTurn
    }

    nonisolated init(
        agent: AgentKind?,
        status: MonitorStatus,
        sessionCount: Int = 0,
        subagents: SubagentBadge = .empty,
        buriesAFinishedTurn: Bool = false
    ) {
        self.agent = agent
        self.status = status
        self.sessionCount = sessionCount
        self.subagents = subagents
        self.buriesAFinishedTurn = buriesAFinishedTurn
    }

    var isResting: Bool { agent == nil }
}

/// Every product's answer, folded into the one thing the UI reads. Views never assemble state
/// from several sources.
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

    /// Ready if any product is watched properly; only when none is does the most actionable unhealthy
    /// one speak.
    nonisolated var availability: MonitorAvailability {
        MonitorAggregation.availability(agents: agents)
    }

    /// The products that are open and reachable, in display order; empty means `Disconnected`.
    nonisolated var connectedAgents: [AgentKind] {
        agents.filter(\.isConnected).map(\.agent)
    }

    /// What the collapsed surface draws, left to right; never empty (the resting mark). Ordered by
    /// ``AgentKind``, never urgency.
    nonisolated var presenceMarks: [PresenceMark] {
        MonitorAggregation.marks(agents: agents, sessions: sessions)
    }

    /// The single quota window for a one-product footer; a two-product footer reads ``agents``.
    nonisolated var quota: QuotaSnapshot {
        agents.first?.quota ?? .unavailable
    }

    nonisolated var diagnostic: String? {
        let reported = agents.compactMap { snapshot in
            snapshot.diagnostic.map { (snapshot.agent, $0) }
        }
        guard let first = reported.first else { return nil }
        // With two products, a diagnostic must say whose it is.
        guard agents.count > 1 else { return first.1 }
        return reported
            .map { "\($0.0.displayName): \($0.1)" }
            .joined(separator: "\n")
    }

    /// The seed before any provider answers: Disconnected, not `Connecting` (§6.7), so a launch draws
    /// nothing on a notched display until a product answers.
    static let connecting = MonitorSnapshot(
        agents: [.connecting],
        sessions: [],
        status: .disconnected
    )
}

/// How several things that went wrong become one line, so the first does not hide later ones
/// (CR-029).
enum MonitorDiagnostics {
    nonisolated static func combined(_ diagnostics: String?...) -> String? {
        combined(diagnostics)
    }

    nonisolated static func combined(_ diagnostics: [String?]) -> String? {
        let messages = diagnostics.compactMap { diagnostic -> String? in
            guard let diagnostic,
                  !diagnostic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return diagnostic
        }
        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }
}

enum AgentSnapshotMerge {
    /// Folds every product's answer into the one snapshot the UI reads. Pure: no actor, clock or I/O.
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

/// What a block heading reads off its block, on the live list or the Recent queue: whose it is,
/// how many rows it heads, and whether one of them wants a person.
nonisolated protocol ProductBlock: Identifiable where ID == AgentKind {
    var agent: AgentKind { get }
    var rowCount: Int { get }
    var wantsAttention: Bool { get }
}

enum MonitorAggregation {
    /// Whether this thread is still working, not the turn status the row draws: a subagent outlives
    /// its turn. Read by the collapsed summary, product marks, row order and terminal membership
    /// gate; identity for rows with no live subagents.
    ///
    /// Must not reach the row's own rendering: the timer would restart and never end if
    /// `SubagentStop` is lost (``SessionStatusControl``).
    nonisolated static func effectiveStatus(
        of session: MonitoredSession
    ) -> SessionStatus {
        // A subagent's approval outranks still-working, but input still wins within one row: a refused
        // approval is never closed, so a later question is more current (as `SessionStatus.transitioned`).
        if session.subagentsAwaitingApproval, session.status != .inputNeeded {
            return .approvalNeeded
        }
        // The pause flag covers the 50-130 ms between a subagent finishing and the parent's next turn
        // (measured 2026-08-23, CLI 2.1.241), when the count already reads zero.
        return session.status == .completed
            && (session.hasRunningSubagent || session.isPausedForBackgroundWork)
            ? .running
            : session.status
    }

    /// Rows first, availability second. Approval leads: the agent cannot proceed past it, and it
    /// decides which pattern a bar holding both shows (`NotchStatusMatrix.swift`). A live turn
    /// outranks another product's unhealthy availability (e.g. `setupRequired`).
    nonisolated static func status(
        agents: [AgentSnapshot],
        sessions: [MonitoredSession]
    ) -> MonitorStatus {
        let priority: [SessionStatus] = [
            .approvalNeeded,
            .inputNeeded,
            .running,
            .completed
        ]
        for status in priority
        where sessions.contains(where: { effectiveStatus(of: $0) == status }) {
            return status.monitorStatus
        }
        // No turns: report presence. The other states speak in the panel and Settings.
        return agents.contains(where: \.isConnected) ? .connected : .disconnected
    }

    /// One mark per connected product, or the single resting mark.
    nonisolated static func marks(
        agents: [AgentSnapshot],
        sessions: [MonitoredSession]
    ) -> [PresenceMark] {
        let connected = agents.filter(\.isConnected)
        guard !connected.isEmpty else {
            return [PresenceMark(agent: nil, status: .disconnected)]
        }
        return connected.map { snapshot in
            // This product's own rows only: another product's turn must not light or count under its mark.
            let own = sessions.filter { $0.agent == snapshot.agent }
            let markStatus = status(agents: [snapshot], sessions: own)
            return PresenceMark(
                agent: snapshot.agent,
                status: markStatus,
                sessionCount: own.count,
                subagents: SubagentBadge(
                    count: own.reduce(0) { $0 + $1.runningSubagentCount },
                    wantsAttention: own.contains { $0.subagentsAwaitingApproval }
                ),
                // Not when the mark is already `.completed`: the column would only repeat it.
                buriesAFinishedTurn: markStatus != .completed
                    && own.contains { effectiveStatus(of: $0) == .completed }
            )
        }
    }

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

    /// One product's block on the live list.
    nonisolated struct SessionGroup: ProductBlock, Equatable, Sendable {
        let agent: AgentKind
        let sessions: [MonitoredSession]
        /// Derived status (`PRD.md` §6.2): a subagent stuck at a dialogue counts, a finished turn
        /// with subagents still working does not.
        let wantsAttention: Bool

        var id: AgentKind { agent }
        var rowCount: Int { sessions.count }
    }

    /// One product's block on the Recent queue (`expanded-panel-v2.md` §4.7). Its rows keep the
    /// queue's newest-first order, so the ages still run in one descent inside a block.
    nonisolated struct RecentGroup: ProductBlock, Equatable, Sendable {
        let agent: AgentKind
        let departures: [RecentDeparture]

        var id: AgentKind { agent }
        var rowCount: Int { departures.count }
        /// Nothing below the seam wants anybody (§2.4 rule 06), whatever the row was last drawn as.
        var wantsAttention: Bool { false }
    }

    /// One block per product that has a row, in `AgentKind` order — never by urgency, because
    /// blocks trading places is movement (`dual-agent-design.md` §3.1). No rows, no block
    /// (`panel-v2.md` §1 rule 2). Rows keep ``rowOrder``, so a row never crosses a header.
    nonisolated static func groups(
        of sessions: [MonitoredSession]
    ) -> [SessionGroup] {
        AgentKind.allCases.compactMap { agent in
            let own = sessions.filter { $0.agent == agent }
            guard !own.isEmpty else { return nil }
            return SessionGroup(
                agent: agent,
                sessions: own,
                wantsAttention: own.contains { effectiveStatus(of: $0).wantsPerson }
            )
        }
    }

    /// The queue's blocks: the live list's order of blocks, each holding its departures in the
    /// order given, which is the queue's own (most recently departed first).
    nonisolated static func groups(
        of departures: [RecentDeparture]
    ) -> [RecentGroup] {
        AgentKind.allCases.compactMap { agent in
            let own = departures.filter { $0.session.agent == agent }
            guard !own.isEmpty else { return nil }
            return RecentGroup(agent: agent, departures: own)
        }
    }

    /// A total order: priority, most recent, product order, identity. Start times arrive as
    /// whole milliseconds, so ties are common; an unstable tie shuffles the list on refresh.
    nonisolated static func rowOrder(
        _ lhs: MonitoredSession,
        _ rhs: MonitoredSession
    ) -> Bool {
        let priority: [SessionStatus: Int] = [
            .approvalNeeded: 0,
            .inputNeeded: 1,
            .running: 2,
            .completed: 3
        ]
        // Derived status, as the summary reads it (`PRD.md` §6.2): a finished row with a subagent
        // still working sorts with the running ones.
        let lhsPriority = priority[effectiveStatus(of: lhs)] ?? Int.max
        let rhsPriority = priority[effectiveStatus(of: rhs)] ?? Int.max
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

/// How long a turn has been running. Always `now - startedAt`, never accumulated, so waits,
/// missed refreshes and sleep count. `now` is a parameter so the format is assertable.
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

    /// Spelled out, because VoiceOver reads `12:34` as a time of day.
    nonisolated static func spokenElapsed(since startedAt: Date?, now: Date) -> String? {
        guard let seconds = elapsedSeconds(since: startedAt, now: now) else {
            return nil
        }

        let (hours, minutes, remainder) = components(of: seconds)
        var parts: [String] = []
        if hours > 0 {
            parts.append("\(hours) \(hours == 1 ? "hour" : "hours")")
        }
        if minutes > 0 {
            parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")")
        }
        if remainder > 0 || parts.isEmpty {
            parts.append("\(remainder) \(remainder == 1 ? "second" : "seconds")")
        }
        return parts.joined(separator: " ")
    }

    /// Nil for a future start (clock skew) or an unobserved one, so no caller renders an
    /// invented number.
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

    /// Time remaining until the quota resets: `Resets in 4 hours 12 minutes` — two units,
    /// largest first, the smaller dropped only when zero. A duration, not calendar days; the
    /// absolute day is in ``spokenResetText(resetsAt:remainingPercent:now:)`` (§7).
    ///
    /// A missing reset on Claude Code's untouched 5-hour window (starts on first request) says
    /// `Not started`; any other missing reset draws `--` (§8.3). A consumed window with no reset
    /// is a sign `/usage` output has moved (`non-public-codex-integration-features.md`).
    nonisolated static func resetText(
        resetsAt: Date?,
        remainingPercent: Int? = nil,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        guard let resetsAt else {
            return remainingPercent == 100 ? "Not started" : unreadable
        }

        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0 else { return "Resets now" }

        let totalMinutes = max(1, Int(remaining / 60))
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60

        let parts: [String?] = if days > 0 {
            [count(days, of: "day"), count(hours, of: "hour")]
        } else if hours > 0 {
            [count(hours, of: "hour"), count(minutes, of: "minute")]
        } else {
            [count(minutes, of: "minute")]
        }
        return "Resets in " + parts.compactMap { $0 }.joined(separator: " ")
    }

    /// Nil for a zero, so the caller drops the unit: two units is a ceiling, not a shape.
    nonisolated private static func count(_ value: Int, of unit: String) -> String? {
        guard value > 0 else { return nil }
        return "\(value) \(unit)\(value == 1 ? "" : "s")"
    }

    /// Spoken: `unavailable` for `--`, and the absolute instant (`resets Friday at 09:00`) where
    /// the column shows a duration (§7).
    nonisolated static func spokenResetText(
        resetsAt: Date?,
        remainingPercent: Int? = nil,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        guard let resetsAt else {
            return remainingPercent == 100 ? "not started" : "unavailable"
        }
        guard resetsAt.timeIntervalSince(now) > 0 else { return "resets now" }

        return "resets \(resetsAt.formatted(weekday(calendar))) "
            + "at \(resetsAt.formatted(clock(calendar)))"
    }

    /// Pinned to `en_GB`, like every user-readable string (`AGENTS.md` §1).
    nonisolated private static let spokenLocale = Locale(identifier: "en_GB")

    nonisolated private static func weekday(_ calendar: Calendar) -> Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.weekday(.wide)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = spokenLocale
        return style
    }

    nonisolated private static func clock(_ calendar: Calendar) -> Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = spokenLocale
        return style
    }

    /// Drawn in place of any field this app could not read, with the field's unit where it has
    /// one; nothing dimmed or announced elsewhere (§8.3).
    nonisolated static let unreadable = "--"

    /// A window's share of what is left: `72% left`, or `-- left`.
    nonisolated static func share(remainingPercent: Int?) -> ShareReading {
        ShareReading(figure: remainingPercent.map { "\($0)%" } ?? unreadable)
    }

    /// A day's spend: `518.7M today`, or `-- today`.
    nonisolated static func today(tokens: Int64?) -> SpendReading {
        SpendReading(figure: tokens.map(compactTokenCount) ?? unreadable)
    }
}

/// A day's spend split into figure and unit: an unreadable total keeps `today` and replaces
/// only the figure (`quota-footer-v2.md` §8.3), and the two parts are drawn in different inks.
nonisolated struct SpendReading: Equatable, Sendable {
    let figure: String
    let unit = "today"

    nonisolated var text: String { "\(figure) \(unit)" }

    nonisolated var spokenText: String {
        figure == UsageSummaryFormatter.unreadable
            ? "Tokens today unavailable"
            : "\(figure) tokens today"
    }
}

/// A window's share, split like ``SpendReading``: the figure in ``NotchPalette/reading``,
/// the words in ``NotchPalette/label``. Role, not value — no figure is drawn differently for
/// being low (`quota-footer-v2.md` §4), and `--` uses the figure's ink (§8.3).
nonisolated struct ShareReading: Equatable, Sendable {
    let figure: String
    let unit = "left"

    nonisolated var text: String { "\(figure) \(unit)" }

    nonisolated var spokenText: String {
        figure == UsageSummaryFormatter.unreadable
            ? "share unavailable"
            : "\(figure) left"
    }
}

// MARK: - Where the headings stand

/// Where each block heading of the grouped live list stands at one scroll offset
/// (`expanded-panel-v2.md` §4.6). A pure function of the offset: no animation or state, so
/// scrolling back reverses every motion.
///
/// - In the flow: scrolling with the rows.
/// - On the top strip (the `16` pt line under the band): the current block's chip at `0`,
///   passed blocks beside it as names at ``PanelMetrics/productTrailBadgeOpacity``. Docking
///   over ``PanelMetrics/productTrailDockingDistance``, `x` eases out faster than `y` so it
///   never crosses the badge already there.
/// - On the foot line (the viewport's last `16`): blocks still to come, nearest first; the
///   next one lifts straight up at its flow `x`.
///
/// A list that fits its viewport pins nothing. The Recent queue lays its blocks out the same way,
/// at its own row height (§4.7).
struct ProductTrailLayout: Equatable, Sendable {
    struct Heading: Equatable, Sendable {
        let agent: AgentKind
        /// The chip's top-left corner, in the viewport's coordinates.
        let x: CGFloat
        let y: CGFloat
        /// Count and rule opacity: `1` in the flow, `0` on either trail.
        let tail: CGFloat
        /// `0` in the flow, `1` on a trail. A badge dims by it, or flips for a block wanting a person.
        let trailed: CGFloat
        /// The chip's flow position; a click on its badge scrolls here.
        let flowChip: CGFloat

        var isOnTrail: Bool { trailed >= 1 }
    }

    let headings: [Heading]
    /// Whether the list is taller than its viewport; otherwise nothing docks or lifts. Does not
    /// decide whether the top strip's ground is drawn (see `ProductTrails`).
    let scrolls: Bool
    /// Whether any block waits on the foot line, which draws its ground and fade.
    let drawsFootLine: Bool

    /// Cubic ease-out: `x` is `87.5%` home at half the travel, clearing the badge before `y`
    /// brings the two within a chip's height; a linear glide crosses it.
    nonisolated static func ease(_ t: CGFloat) -> CGFloat {
        1 - pow(1 - t, 3)
    }

    nonisolated static func laidOut<Block: ProductBlock>(
        groups: [Block],
        badgeWidths: [CGFloat],
        offset: CGFloat,
        viewportHeight: CGFloat,
        contentHeight: CGFloat,
        rowHeight: CGFloat = PanelMetrics.sessionRowHeight
    ) -> ProductTrailLayout {
        let count = groups.count
        guard count > 0, badgeWidths.count == count else {
            return ProductTrailLayout(headings: [], scrolls: false, drawsFootLine: false)
        }
        let dock = PanelMetrics.productTrailDockingDistance
        let line = PanelMetrics.productTrailHeight
        let slack = PanelMetrics.productGroupHeaderSlack
        let inset = PanelMetrics.sessionRowPadding
        let gap = PanelMetrics.productBadgePadding
        let footLine = viewportHeight - line
        // Tolerance so float error does not make an exactly-fitting list scroll.
        let scrolls = contentHeight > viewportHeight + 0.5
        func clamp(_ value: CGFloat, _ low: CGFloat = 0, _ high: CGFloat = 1) -> CGFloat {
            min(max(value, low), high)
        }

        var flowChips: [CGFloat] = []
        var y: CGFloat = 0
        for (index, group) in groups.enumerated() {
            if index > 0 { y += slack }
            flowChips.append(y)
            y += line
            y += CGFloat(group.rowCount) * rowHeight
        }
        let chips = flowChips.map { $0 - offset }

        // The two can never both be under way for one heading: the viewport is taller than twice
        // the docking distance.
        let docked: [CGFloat] = (0..<count).map { index in
            index == 0 ? 1 : (scrolls ? clamp((dock - chips[index]) / dock) : 0)
        }
        let grounded: [CGFloat] = (0..<count).map { index in
            index == 0 || !scrolls ? 0 : clamp((chips[index] - (footLine - dock)) / dock)
        }

        var topX = inset
        var footX = inset
        var anyOnFoot = false
        let headings: [Heading] = (0..<count).map { index in
            let next = index + 1 < count ? docked[index + 1] : 0
            let onFoot = grounded[index]
            var x = inset
            var chipY = index == 0 ? 0 : clamp(chips[index], 0, footLine)
            if docked[index] > 0 {
                if index > 0 {
                    x = inset + (topX - inset) * ease(docked[index])
                } else {
                    chipY = 0
                }
                if docked[index] >= 1 { topX += badgeWidths[index] + gap }
            } else if onFoot > 0 {
                x = footX
                footX += (badgeWidths[index] + gap) * ease(onFoot)
                anyOnFoot = true
            }
            return Heading(
                agent: groups[index].agent,
                x: x,
                y: chipY,
                tail: (1 - next) * (1 - onFoot),
                trailed: max(next, onFoot),
                flowChip: flowChips[index]
            )
        }

        return ProductTrailLayout(
            headings: headings,
            scrolls: scrolls,
            drawsFootLine: anyOnFoot
        )
    }
}
