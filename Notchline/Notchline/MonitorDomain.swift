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

/// Whether a product is open, as the user would judge it by glancing at their
/// own machine.
///
/// Deliberately not derived from whether the product has work in flight.
/// ``ClaudeCodeSessionListing`` answers "which sessions exist" and the Turn
/// reducer answers "what are they doing"; presence draws the matrix and the
/// reducer lights it. Re-merging the two would put the mark back to reporting
/// our own plumbing instead of something the user can check for themselves.
enum AgentPresence: String, CaseIterable, Codable, Sendable {
    /// Open, on evidence.
    case open
    /// Not open, on evidence.
    case closed
    /// No trustworthy evidence either way — the only source has been failing
    /// long enough that its last answer has expired. It joins `closed` in every
    /// decision about what to *draw*; it stays a separate value because the
    /// reason differs, and because a source that can never say this is a source
    /// that believes a stale answer forever.
    ///
    /// Where the decision is what to **forget**, the two part company, and that
    /// is the one place the distinction earns its keep. `closed` is the source
    /// answering that nothing is running, so a Turn it does not name has ended;
    /// this is nobody having answered at all, which is not evidence about any
    /// session and may not delete state — see
    /// ``ClaudeCodeMonitorService`` pruning the Hook reducer.
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

    /// The panel's full sentence for this state.
    ///
    /// No product argument. Four of these used to name the product they were
    /// about — `Connecting to Codex`, `Claude Code disconnected` — and none of
    /// them do any more: which product is unhealthy is not what the notch is
    /// for, and Settings already lists every product with its own state beside
    /// it. Dropping the names costs the user nothing they cannot see one click
    /// away, and it buys back the width the longest of them reserved on every
    /// panel, connected or not.
    var displayName: String {
        switch self {
        case .connected:
            "Connected"
        case .setupRequired:
            "Set up integration"
        case .connecting:
            "Connecting"
        case .running:
            "Running"
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

    /// The name the notch shows, which is shorter than ``displayName``.
    ///
    /// The matrix beside it already says a turn wants the user, so the label
    /// only has to say which kind — "needed" repeats the indicator. Dropping
    /// "Codex" costs nothing in the app's own menu bar item either. The panel
    /// still shows the full sentence, so this is a shorter form, not less
    /// information.
    ///
    /// Nothing here names a product either, for the same reason ``displayName``
    /// does not — and the collapsed surface had the stronger case: its width is
    /// already computed from the unattributed names, so an `Update Codex` drawn
    /// where `Update` was reserved was a label wider than its own pill.
    var compactDisplayName: String {
        switch self {
        case .connected:
            "Connected"
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
            "Update"
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

    var isRunning: Bool {
        self == .running
    }

    /// The values the collapsed surface is allowed to reach.
    ///
    /// Six, not ten: two system values plus the four session ones. The other
    /// four stay in the enum because the expanded panel and Settings still say
    /// them, but they no longer appear beside the notch — the collapsed mark
    /// reports whether the user has an agent open, not how our own plumbing is
    /// doing. See `docs/figma-design.md` §6.4 and §6.6.
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
        // Approval gives way to input. A denied approval is never closed by
        // Codex -- no event ever names that `tool_use_id` again (tech-design
        // §9.2) -- so the wait that follows it is the only thing that proves
        // the human answered. Without this pair the row keeps saying Approval
        // needed while the agent is asking a question, which is the one fact
        // the product exists to get right, and aggregation ranks it below the
        // Input it actually is (PRD §6.2).
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

    /// The sentence the *expanded* panel uses for this availability.
    ///
    /// No longer the collapsed status: that one is decided by presence as well
    /// (``AgentSnapshot/isConnected``), so availability alone can no longer
    /// name it. `.ready` maps to `.connected` for coherence only —
    /// ``emptyListMessage(for:)`` answers "No active sessions" for that case
    /// before ever reaching here.
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

    var emptyListMessage: String {
        switch self {
        case .setupRequired:
            "Set up integration"
        case .ready:
            "No active sessions"
        case .connecting, .updateAgent, .unsupportedVersion, .disconnected:
            // The same sentence the panel header shows, so the two cannot drift.
            status.displayName
        }
    }
}

/// What a product's monitoring has left lying on disk.
///
/// Reported, never acted on. Only a product whose monitoring writes files the
/// user might one day want back answers with one of these — Codex does not, so
/// it answers nil.
nonisolated struct AgentDiskFootprint: Sendable, Equatable {
    /// The folder to open when the user wants to look at them.
    let directory: URL
    let byteCount: Int64

    nonisolated init(directory: URL, byteCount: Int64) {
        self.directory = directory
        self.byteCount = max(0, byteCount)
    }

    /// `43.2 MB`.
    ///
    /// The size alone. This used to read `43.2 MB · 1,284 files`, and the count
    /// was the half nobody could act on: the question the row answers is
    /// whether the residue is worth going and clearing, and how many files it
    /// is spread across does not change that answer. The folder is one button
    /// away for anyone who does want to count them.
    nonisolated var summary: String {
        byteCount.formatted(.byteCount(style: .file))
    }
}

/// A footprint, or the reason there is no figure to draw yet.
///
/// The row exists before the measurement does, and that is the whole point of
/// this type. Claude Code's transcripts are *found* rather than derived — the
/// folder is named by a rule this app does not know, so it is located from a
/// reading that has already happened (see ``ClaudeCodeUsageTranscripts``), and
/// a reading takes seconds. Reported as an optional footprint, "not measured
/// yet" and "this product leaves nothing" were the same nil, so Settings drew
/// no row at all until the first reading landed and then grew one under the
/// pointer. They are different answers and this says which (CC-020).
nonisolated enum AgentDiskFootprintReport: Sendable, Equatable {
    /// This product's monitoring writes nothing the user could ever want back,
    /// so there is no row. Codex is here permanently: its quota arrives over
    /// the app server and leaves no files anywhere.
    case leavesNothing
    /// It does leave files, a reading that will say where they are is out, and
    /// nothing has come back from one yet.
    case measuring
    case measured(AgentDiskFootprint)
    /// It leaves files and this app cannot say where they are or what they
    /// weigh. Distinct from ``measuring``: that one is an answer genuinely on
    /// its way, and a word that means "in progress" must stop saying so once
    /// the attempt behind it has finished and failed -- or when there was never
    /// going to be an attempt at all, which is where a machine with no Claude
    /// Code installed sits for the life of the process.
    case unavailable

    /// The trailing readout. Empty only for ``leavesNothing``, which draws no
    /// row to put it in.
    nonisolated var summary: String {
        switch self {
        case .leavesNothing: ""
        case .measuring: "Calculating…"
        case .measured(let footprint): footprint.summary
        case .unavailable: "Unavailable"
        }
    }

    /// The folder to open, and nil whenever there is no folder to open — which
    /// is also what greys the button out. A button that reveals nowhere is
    /// worse than one that is plainly not ready.
    nonisolated var directory: URL? {
        guard case .measured(let footprint) = self else { return nil }
        return footprint.directory
    }
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
    /// Subagents this thread started that have not been seen to stop.
    ///
    /// **Row data, not a fifth state.** It follows the terminal reason exactly
    /// (`CONTEXT.md`'s 终态原因): the row's one mark stays the timer, and what
    /// qualifies it is said in words instead. A subagent outlives the turn that spawned it,
    /// so a Completed row can still have one in flight — that is the case the
    /// count exists for, and the row would otherwise read as finished while the
    /// thread is still working. **Both products report it**, from the same two
    /// events under the same names: Codex spawns through `spawn_agent` and
    /// Claude Code through its `Agent` tool, whose call returns as soon as the
    /// subagent is launched.
    let runningSubagentCount: Int
    /// How many of those subagents are sitting on a permission prompt.
    ///
    /// **The one thing a subagent can do that this product exists to report.**
    /// A count says work is in flight, which is a hint; this says the product
    /// is stopped and waiting for the person, which is the state everything
    /// else here is built around. Measured on both products on 2026-08-23: a
    /// subagent's `PermissionRequest` reaches the thread's hooks with the
    /// subagent's `agent_id`, and it can arrive either side of the parent
    /// turn's terminal — so this is true of finished rows and running ones
    /// alike.
    ///
    /// **A count in the model, a flag on the surface, since
    /// `dual-agent-design.md` §10.** The badge that draws it carries
    /// ``runningSubagentCount`` — every subagent, waiting ones included — and
    /// says *whether* any of them is stopped by flipping its ground rather
    /// than by drawing a second figure. So only `> 0` is ever read for
    /// drawing. It stays a count because the reducers genuinely have one and
    /// because it is what ``subagentsAwaitingApproval`` is derived from, which
    /// the status and ordering rules below do read.
    let subagentsAwaitingApprovalCount: Int
    /// Whether this row's turn ended by pausing rather than by finishing.
    ///
    /// **Row data, not a fifth state, and not a second count.** Like
    /// ``runningSubagentCount`` it answers "is this thread still working" and
    /// leaves "what did this turn do" alone -- but it answers it for the
    /// moment the count cannot: an asynchronous subagent's `SubagentStop`
    /// empties the count, and Claude Code re-enters the parent 50-130 ms later
    /// with a turn of its own (measured 2026-08-23, CLI 2.1.241). Between those
    /// two the count says nothing is running and the thread is about to run,
    /// so a row reading the count alone showed `Completed` for a tenth of a
    /// second and then `Running` again.
    ///
    /// **Claude Code only**, because only it says so: its `Stop` carries
    /// `background_tasks`, documented as the field that "lets hooks distinguish
    /// 'session is done' from 'session is paused waiting for background work to
    /// wake it'". Codex has no equivalent and is false here always, which makes
    /// every rule below an identity transform on that product -- exactly what
    /// ``runningSubagentCount`` was on this one until its two boundaries were
    /// registered.
    let isPausedForBackgroundWork: Bool

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
        isPausedForBackgroundWork: Bool = false
    ) {
        self.agent = agent
        self.threadID = threadID
        self.turnID = turnID
        self.projectName = projectName
        self.title = title
        self.preview = preview
        self.status = status
        self.startedAt = startedAt
        self.runningSubagentCount = runningSubagentCount
        self.subagentsAwaitingApprovalCount = subagentsAwaitingApprovalCount
        self.isPausedForBackgroundWork = isPausedForBackgroundWork
    }

    /// Whether the row says work is still in flight beside its own turn.
    nonisolated var hasRunningSubagent: Bool { runningSubagentCount > 0 }

    /// Whether one of those subagents is sitting on a permission prompt.
    nonisolated var subagentsAwaitingApproval: Bool { subagentsAwaitingApprovalCount > 0 }

    /// What the row's badge draws: every subagent in flight, and whether any
    /// of them is stopped on a question.
    ///
    /// One badge carrying the whole count, never two. Splitting the waiting
    /// ones onto a badge of their own put two numerals on exactly the rows
    /// that need a person — the moment a row is hardest to read quickly —
    /// and the ground already carries that fact for nothing.
    nonisolated var subagentBadge: SubagentBadge {
        SubagentBadge(
            count: runningSubagentCount,
            wantsAttention: subagentsAwaitingApproval
        )
    }

    /// Whether the row draws its subagent badge in place of its timer.
    ///
    /// `false` while the turn is still timing. The row's one mark is the
    /// elapsed readout and this does not displace it: a running row already
    /// says the thread is working, so the badge would only be a second mark
    /// saying the same thing. Once the clock stops, the slot the timer had is
    /// where it goes — a finished row that draws nothing there reads as
    /// finished, and with a subagent still working that is not what happened.
    nonisolated var showsSubagentBadge: Bool {
        !status.keepsTiming && hasRunningSubagent
    }

    /// The spoken form of the row's badge, since VoiceOver cannot read a
    /// flipped ground.
    ///
    /// `nil` under the same guard as ``showsSubagentBadge``. Speaks the count
    /// the badge draws and then the state its ground draws, in that order,
    /// because that is the order the badge answers them in.
    nonisolated var spokenSubagentSummary: String? {
        guard showsSubagentBadge else { return nil }
        return subagentBadge.spokenSummary
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
}

/// What one subagent badge draws, wherever it is drawn.
///
/// One badge, one number, one flip (`dual-agent-design.md` §10). ``count`` is
/// every subagent in flight — the ones stopped on a question included, because
/// they have not finished either — and ``wantsAttention`` is the only other
/// thing the mark says. A badge whose count is zero is not drawn at all: an
/// empty badge would be a mark that means nothing.
///
/// The same value serves both places the badge appears. A session row draws it
/// neutral, because the row already names its product a line above; the
/// collapsed surface draws one per product, tinted, because a bar has no
/// caption line and hue is the only thing there that can say whose.
nonisolated struct SubagentBadge: Equatable, Sendable {
    /// Every subagent this badge speaks for, waiting ones included.
    var count: Int = 0
    /// Whether any one of them is stopped on an approval or an input. Draws
    /// the bright ground and the dark numeral; false draws the dark ground and
    /// the bright numeral.
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

/// One product's badge, kept with the product whose ink it draws in.
///
/// The collapsed surface draws these in ``AgentKind`` order and never in
/// urgency's, exactly as the matrices at the other end of the bar are ordered:
/// once the two hues are learned, position is the other half of what
/// identifies a mark, and re-sorting would swap them under the eye reading
/// them.
nonisolated struct AgentSubagentBadge: Equatable, Sendable {
    let agent: AgentKind
    let badge: SubagentBadge
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
    /// Whether the product itself is open, independent of whether we can watch
    /// it. Sourced per product: Codex from the running-application list, Claude
    /// Code from its live session list.
    let presence: AgentPresence

    nonisolated init(
        agent: AgentKind = .codex,
        availability: MonitorAvailability,
        sessions: [MonitoredSession],
        quota: QuotaSnapshot,
        diagnostic: String?,
        setupStatus: HookSetupStatus = .active,
        presence: AgentPresence = .open
    ) {
        self.agent = agent
        self.availability = availability
        self.sessions = sessions
        self.quota = quota
        self.diagnostic = diagnostic
        self.setupStatus = setupStatus
        self.presence = presence
    }

    /// Whether this product counts as connected: open *and* observable.
    ///
    /// The two halves are independent facts that can contradict each other.
    /// Neither product is registered until the user turns its switch on, so
    /// "open but not reachable" is an ordinary first run rather than an edge
    /// case, and it reads as disconnected — which is what the word means. You cannot
    /// be disconnected from something you never opened; you certainly are from
    /// something open that you cannot reach.
    ///
    /// `.connecting` is not connected. It is the state of not having
    /// established the observation contract yet, and reporting a connection we
    /// have not made would be guessing at business state — the one thing
    /// recovery logic is never allowed to do. On a notched display the cost is
    /// nil anyway: at rest a disconnected surface draws nothing, so a product
    /// still being reached shows no mark rather than a wrong one, and the mark
    /// arrives when the contract does.
    nonisolated var isConnected: Bool {
        presence.isOpen && availability == .ready
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

/// How a row says which product it came from.
///
/// The first three live on the row's existing 11pt caption line, so none of them
/// adds a stroke to the panel. ``colourBar`` does add one, and was left out for
/// exactly that reason until the footer could fold its rules away — see
/// `dual-agent-design.md` §4. A per-row matrix is still not offered: it puts a
/// second mark on a row that is meant to carry one.
enum ProductAttributionStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    /// The caption is prefixed `Codex ·` in that product's lit colour. The
    /// prefix alone takes the colour; the Project after it stays the ordinary
    /// caption grey, because the prefix is the whole of what the colour is
    /// about. Default: the only option that adds nothing, and the only one
    /// where hue reinforces the signal rather than being all of it — remove the
    /// colour and the words still say it.
    case nameAndColour
    /// The same words in the ordinary caption grey. Geometry is identical, so
    /// switching moves nothing, and it depends on colour not at all.
    case nameOnly
    /// A small badge: the matrix's unlit colour as the ground, its lit colour as
    /// the text.
    case badge
    /// A rail down the row block's leading edge, in the product's lit colour,
    /// and nothing on the caption at all.
    ///
    /// The only option that costs no caption room, and the only one that groups
    /// — consecutive rows of one product read as a run rather than as three
    /// separate rows. It is last rather than default because it is the only one
    /// that is purely hue: nothing is left when the colour cannot be seen.
    case colourBar

    nonisolated var id: Self { self }

    var displayName: String {
        switch self {
        case .nameAndColour: "Name and colour"
        case .nameOnly: "Name only"
        case .badge: "Badge"
        case .colourBar: "Colour bar"
        }
    }

    /// Whether the caption carries the product name.
    ///
    /// ``badge`` moves it into its own block and ``colourBar`` off the caption
    /// entirely, so both leave the caption as the bare project name.
    var namesProductInCaption: Bool {
        self == .nameAndColour || self == .nameOnly
    }

    /// Whether the product name on the caption is drawn in that product's
    /// colour.
    ///
    /// The name and nothing else: the Project beside it keeps the ordinary
    /// caption grey under every style. The colour answers "which product", and
    /// the Project is this row's own subject rather than a second saying of
    /// that — colouring it too made the whole line read as the mark.
    var tintsProductName: Bool {
        self == .nameAndColour
    }
}

/// One quota window as the footer draws it: a rule and the caption under it.
nonisolated struct FooterWindow: Equatable, Sendable {
    /// 0–1 remaining, or nil when the reading is unavailable.
    let fill: Double?
    let caption: String
}

/// One product's row of quota rules.
///
/// Codex spans the full width because it has one window; Claude Code is halved
/// because it genuinely has two, a 5-hour session window and a 7-day one. The
/// halving is not to make them fit — it is what having two windows looks like.
nonisolated struct FooterRule: Identifiable, Equatable, Sendable {
    let agent: AgentKind
    let windows: [FooterWindow]

    nonisolated var id: AgentKind { agent }
}

/// One mark on the collapsed surface.
///
/// The marks *are* the presence channel: a product that is not connected has no
/// mark at all rather than a dimmed one. Dimming it would be advertising a tool
/// the user does not open, which is the whole reason the resting matrix went
/// away.
nonisolated struct PresenceMark: Equatable, Sendable {
    /// The product this mark belongs to, or nil for the resting grey.
    let agent: AgentKind?
    /// This product's own status. Each matrix runs its own curve — the pair is
    /// two independent readouts, not one aggregate drawn twice.
    let status: MonitorStatus
    /// How many rows this product has, drawn as dots beside its matrix.
    ///
    /// **The count that costs almost no width.** A numeral beside the matrix
    /// was drawn first and lengthened the leading wing by `44` for the pair.
    /// What replaced it is a column of dots standing on the matrix's own row
    /// pitch, packed from the top edge, capped at three with the third
    /// stretching into a dash past that — `5.66` of wing, and no height at all
    /// (`dual-agent-design.md` §11).
    ///
    /// Zero for the resting mark, which has no product and therefore no rows.
    let sessionCount: Int
    /// Every subagent this product has in flight, and whether any of them is
    /// stopped on a question.
    ///
    /// Summed across this product's rows: the collapsed surface speaks for the
    /// whole list the way the summary status and the one timer already do, but
    /// per product rather than across both, because the badge that draws it is
    /// tinted and a mixed total could not honestly take either ink.
    let subagents: SubagentBadge

    /// Whether this mark has a session column to stand beside it.
    ///
    /// The column is the count's, not the matrix's: a product with nothing open
    /// packs to its matrix alone so the pair keeps the `6` that binds it. The
    /// resting grey never has one. Surfaces that hold the column open anyway
    /// are the fixed-width ones — see ``MonitorStore/reservesSessionColumns``.
    var drawsSessionColumn: Bool { agent != nil && sessionCount > 0 }

    nonisolated init(
        agent: AgentKind?,
        status: MonitorStatus,
        sessionCount: Int = 0,
        subagents: SubagentBadge = .empty
    ) {
        self.agent = agent
        self.status = status
        self.sessionCount = sessionCount
        self.subagents = subagents
    }

    var isResting: Bool { agent == nil }
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

    /// The products that are open and reachable, in display order.
    ///
    /// Empty means the surface is `Disconnected` and draws the grey resting
    /// mark instead of any product's.
    nonisolated var connectedAgents: [AgentKind] {
        agents.filter(\.isConnected).map(\.agent)
    }

    /// What the collapsed surface draws, left to right.
    ///
    /// Never empty: with nothing connected it is the single resting mark, which
    /// takes the one slot rather than adding one. Order is fixed by
    /// ``AgentKind`` and never by urgency — once the two hues are learned,
    /// position is the only thing identifying a mark, and re-sorting would swap
    /// them under the user's eye at the moment they are being read.
    nonisolated var presenceMarks: [PresenceMark] {
        MonitorAggregation.marks(agents: agents, sessions: sessions)
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
            .map { "\($0.0.displayName): \($0.1)" }
            .joined(separator: "\n")
    }

    /// The seed the store holds before any provider has answered.
    ///
    /// Disconnected, not `Connecting`: we have not reached anything yet, and
    /// that is exactly what the word now means (§6.7). It also means a launch
    /// draws nothing on a notched display until a product actually answers,
    /// instead of flashing a state about ourselves.
    static let connecting = MonitorSnapshot(
        agents: [.connecting],
        sessions: [],
        status: .disconnected
    )
}

/// How several things that went wrong become one line.
///
/// Hoisted out of the Codex provider when the Claude Code one needed it too:
/// that side reported `hookDiagnostic ?? read.diagnostic`, which was harmless
/// while a hook diagnostic lasted one refresh and is not now that it stands for
/// the run — the first sentence would have hidden every later one behind it
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
    /// Whether this thread is still working — which is not the same question
    /// as the one the row draws.
    ///
    /// The row's status is its **turn's** status, and `CONTEXT.md` defines it
    /// that way: the main agent's `Stop` really did arrive, the preview really
    /// is the final answer, and the clock really should stop. But a subagent
    /// outlives the turn that spawned it, so `.completed` stops being an answer
    /// to "is anything still running on this thread". Every rule that was
    /// asking *that* while reading `SessionStatus` reads this instead — the
    /// collapsed summary, the product marks, the row order and the terminal
    /// membership gate.
    ///
    /// The identity everywhere else, and for the overwhelming majority of rows
    /// on both products: a row that never spawned anything, or whose subagents
    /// have all stopped, is passed through untouched.
    ///
    /// **It must not reach the row's own rendering.** A row drawn from this
    /// would restart its timer and never take the final answer as its preview,
    /// which is the shape `65e63ab` removed: with `SubagentStop` lost, nothing
    /// could ever end it. What the row draws is in ``SessionStatusControl``.
    nonisolated static func effectiveStatus(
        of session: MonitoredSession
    ) -> SessionStatus {
        // Someone is being asked something, which outranks whether anything is
        // still working — a thread can be both at once, and only one of them
        // needs the user. Input still outranks approval, exactly as it does
        // within a turn (`PRD.md` §6.2, and `SessionStatus.transitioned`):
        // a refused approval is never closed by either product, so the question
        // that follows it is the more current fact.
        if session.subagentsAwaitingApproval, session.status != .inputNeeded {
            return .approvalNeeded
        }
        // Two readings of the same sentence, and the row needs both. The
        // count is continuous and says a subagent is in flight; the pause flag
        // is a single stamp from the turn's own terminal event and says the
        // session stopped in order to wait rather than because it was done. A
        // subagent that finishes clears the first 50-130 ms before the parent's
        // next turn opens (measured 2026-08-23, CLI 2.1.241), and for that
        // tenth of a second the second one is the only thing that still knows
        // the thread is working.
        return session.status == .completed
            && (session.hasRunningSubagent || session.isPausedForBackgroundWork)
            ? .running
            : session.status
    }

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
        for status in priority
        where sessions.contains(where: { effectiveStatus(of: $0) == status }) {
            return status.monitorStatus
        }
        // No turns: the surface reports presence rather than our own plumbing.
        // Six thin states used to live here, four of which the user could do
        // nothing about and one of which — `Connecting` — existed only to
        // explain a wait. They now speak in the expanded panel and in Settings,
        // where there is room to say what to do about them.
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
            // This product's own rows only. A Codex turn must not light Claude
            // Code's mark, and it must not be counted under one either.
            let own = sessions.filter { $0.agent == snapshot.agent }
            return PresenceMark(
                agent: snapshot.agent,
                status: status(agents: [snapshot], sessions: own),
                sessionCount: own.count,
                subagents: SubagentBadge(
                    count: own.reduce(0) { $0 + $1.runningSubagentCount },
                    wantsAttention: own.contains { $0.subagentsAwaitingApproval }
                )
            )
        }
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
        // The same derived answer the summary reads, because `PRD.md` §6.2
        // says these are one rule: "the list sorts by the same priority". A
        // finished row with a subagent still working therefore sorts with the
        // running ones -- otherwise the only row carrying the evidence that
        // anything is still in flight is the first one pushed out of the
        // three-row viewport.
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
    ///
    /// A missing reset has two meanings and this tells them apart by what else
    /// the window knows. Claude Code's 5-hour window starts on the first
    /// request, so until one is made there is no instant to count down to and
    /// the line simply omits it -- an untouched window, not a failed reading.
    /// Reported as "Reset unavailable" it read as the quota display being
    /// broken, which is the one thing it was not. A window with nothing spent
    /// and no reset has not started; any other missing reset is still a reading
    /// this app could not make, and keeps saying so -- a *partly spent* window
    /// with no reset is the documented signal that the output's wording moved.
    nonisolated static func resetText(
        resetsAt: Date?,
        remainingPercent: Int? = nil,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        guard let resetsAt else {
            return remainingPercent == 100 ? "Not started" : "Reset unavailable"
        }

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
        let reset = resetText(
            resetsAt: resetsAt,
            remainingPercent: remainingPercent,
            now: now,
            calendar: calendar
        )
        return "\(remainingText) · \(usageText) · \(reset)"
    }
}
