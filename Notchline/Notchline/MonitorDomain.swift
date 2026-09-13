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
    /// Antigravity: its CLI, `agy`, and Antigravity Desktop, one engine behind
    /// one hooks file (``AntigravitySurface``). L3 (`docs/product-support.md` §5):
    /// progress monitoring, without wait detection. The raw value names its
    /// folder under this app's support directory, so it is short enough for a
    /// socket path.
    case antigravity

    var displayName: String {
        switch self {
        case .codex:
            "Codex"
        case .claudeCode:
            "Claude Code"
        case .antigravity:
            "Antigravity"
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

    /// The one name every surface says for this state.
    ///
    /// **There is no shorter form any more.** The collapsed pill used to draw
    /// its own abbreviations — `Approval` for `Approval needed`, `Input` for
    /// `Input needed` — on the argument that the matrix beside them already
    /// said a turn wanted the user, so "needed" was only repeating the mark.
    /// The mark does say it, but it says it in a pattern; the label is the one
    /// thing on that surface that says it in words, and dropping the verb left
    /// it naming a thing rather than a state. The pill is also the surface with
    /// the least context to supply the difference — no panel, no row, no
    /// caption, and a menu bar full of other applications' icons around it — so
    /// it is the last place to economise on the word. It costs `35` of pill
    /// width (``PanelMetrics/widestCompactLabelWidth``), paid once and in every
    /// state, which is what the word is worth.
    ///
    /// No product argument. Four of these used to name the product they were
    /// about — `Connecting to Codex`, `Claude Code disconnected` — and none of
    /// them do any more: which product is unhealthy is not what the notch is
    /// for, and Settings already lists every product with its own state beside
    /// it. Dropping the names costs the user nothing they cannot see one click
    /// away, and it buys back the width the longest of them reserved on every
    /// panel, connected or not.
    ///
    /// **`running` is drawn as `Working...`, and the case keeps its name.** The
    /// state is `Running` everywhere in this code, in `CONTEXT.md`'s vocabulary
    /// and in every document that reasons about the state machine; only the
    /// word on the surface changed. `Running` is what the *machine* is doing —
    /// a process, a turn, a thread — where the other three names say what is
    /// happening to the person reading them, and the one state that is nobody's
    /// business but the agent's is the one the notch spends most of its life
    /// in. `Working...` says the same fact in the user's terms, and the
    /// trailing ellipsis is the only mark in the vocabulary that carries "and
    /// it has not finished" in the word itself, which is exactly what
    /// distinguishes this state from `Completed`.
    ///
    /// It costs `12` of drawn width (`48.99` → `60.22`) and **nothing at all**
    /// where the pill is reserved: `Approval needed` at `101.56` is still the
    /// widest thing the working set can say, so ``PanelMetrics``'s reservations
    /// are untouched. See `docs/figma-design.md` §6.4.
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

    /// Whether the collapsed surface is reporting that a person is wanted.
    ///
    /// What the bar's own reading answers with its ground. Deliberately the
    /// aggregate turn state and not the subagent flip beside it: each badge on
    /// that bar already flips on its own product's account, and the reading is
    /// the one thing there that speaks for the turns.
    var wantsPerson: Bool {
        self == .inputNeeded || self == .approvalNeeded
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

    /// The same vocabulary the aggregate says, for one row.
    ///
    /// Four of ``MonitorStatus/displayName``'s ten, spelled identically — a row
    /// and the bar above it naming one state two ways is the drift this
    /// duplicate exists to avoid, `running` drawn as `Working...` included.
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

    /// Whether the turn's clock is still counting.
    ///
    /// Every state but `completed` counts. A turn parked on input or approval
    /// is still occupying the user's attention -- that wait is the part worth
    /// seeing -- so the timer deliberately does not pause for it.
    var keepsTiming: Bool {
        self != .completed
    }

    /// Whether this turn is stopped on something only a person can answer.
    ///
    /// The attention channel, in one place rather than spelled out at each of
    /// the surfaces that reads it. Brightness is what this surface says it
    /// with -- a reading's ground flips to white here and stays dim otherwise.
    ///
    /// This is the turn's own answer only. A row can want a person on its
    /// subagents' account while its turn is in neither of these states, so the
    /// row combines this with ``MonitoredSession/subagentsAwaitingApproval``
    /// rather than reading it alone.
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
        // Approval gives way to input. A denied approval is never closed by
        // Codex -- no event ever names that `tool_use_id` again (tech-design
        // §9.2) -- so the wait that follows it is the only thing that proves
        // the human answered. Without this pair the row keeps saying Approval
        // needed while the agent is asking a question, which is the one fact
        // the product exists to get right. This is a rule about *sequence*
        // within one turn, not about rank: across rows, aggregation ranks
        // approval above input (PRD §6.2).
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
    /// When this turn ended, for the rows that have ended.
    ///
    /// **The one fact a finished row still owns.** Its slot used to draw
    /// nothing at all, which made `Completed` findable only by checking the
    /// rows around it for a timer this one lacked; it now draws how long the
    /// turn took, which needs an end as well as a ``startedAt``.
    ///
    /// Taken from the turn's own last event rather than from a stamp of its
    /// own. That stamp is deliberately immune to a subagent's chatter -- see
    /// ``HookTurnState/lastSubagentBoundaryAt`` -- which is exactly the
    /// property this reading depends on: a finished turn whose subagents are
    /// still working must not go on counting.
    ///
    /// `nil` on every unfinished row, where the clock is still running and the
    /// reading comes from ``startedAt`` and the tick instead.
    let finishedAt: Date?
    /// What this row is being asked, where it is being asked something this app
    /// can show.
    ///
    /// **Row data, like ``runningSubagentCount`` and
    /// ``isPausedForBackgroundWork``, and not a fifth state.** The four states
    /// already say a person is wanted; this says what they are wanted *for*, and
    /// it changes nothing about which state the row is in or how it sorts.
    ///
    /// `nil` on every row that is not waiting, and on a waiting row whose
    /// payload carried nothing this app could read -- which is a row that opens
    /// nothing and sends the person to the product, exactly as every row does
    /// today. That is the fail-closed direction: an absent request is a row that
    /// behaves as it always has, never a row that draws an empty body.
    ///
    /// The first of ``requests``.
    let request: AgentRequest?
    /// Every request this row could open, in the order it opens them
    /// (``MonitoredTurnState/requestsAwaitingAnAnswer``). The row draws one at
    /// a time; the rest are what it opens next, and what the store pins the
    /// open one against while a person reads it.
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
        self.projectName = projectName
        self.title = title
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

/// One row that has left the list, and when it left.
///
/// **Memory rather than history** (`expanded-panel-v2.md` §2, `PRD.md` §2 goal
/// 9). It holds the row exactly as the list last drew it, which is what lets it
/// be navigated with no second lookup — both navigators read only ``agent`` and
/// ``threadID`` — plus the instant it left and what took it out. Nothing here
/// is persisted and nothing is ever re-read: a departure this run did not watch
/// cannot become one of these.
nonisolated struct RecentDeparture: Equatable, Sendable, Identifiable {
    /// What took the row off the list.
    ///
    /// **Not drawn.** Nothing below the seam claims a status, because the
    /// rule's meaning is that the list stops there (§2.4 rule 05). This is
    /// kept because it is the one fact about a departure that cannot be
    /// recovered afterwards, and because deciding it is how the detector tells
    /// a departure from a product that merely went quiet.
    enum Reason: Equatable, Sendable {
        /// Its product recorded the Turn as read, so the list stopped
        /// reporting it.
        case read
        /// The user waved it away with a secondary click.
        case dismissed
        /// The same, on a Turn that had not finished.
        case dismissedWhileRunning
    }

    let session: MonitoredSession
    /// The instant this list stopped reporting the row.
    ///
    /// **Not the Turn's end**, which is ``MonitoredSession/finishedAt`` and is
    /// a different fact: a row dismissed while running never has one, and a row
    /// read an hour after it finished left an hour after that. This is the only
    /// one of the three moments the app itself observed, and it is the one the
    /// age counts (§2.4 rule 05).
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

    /// The queue's key: the **Thread**, not the Turn.
    ///
    /// ``MonitoredSession/id`` names a Turn, and a Thread that submits again
    /// gets a new one. Keyed on the Turn, a Thread that came back would draw
    /// twice — once above the seam as its new Turn and once below it as its old
    /// — where §5 says it crosses the rule as the same row. Keyed on the
    /// Thread, the live row's arrival takes the queue's entry out by itself,
    /// which is also what repairs a departure booked in error.
    nonisolated static func key(for session: MonitoredSession) -> String {
        "\(session.agent.rawValue):\(session.threadID)"
    }

    /// How long ago this left, at `now`.
    nonisolated func age(at now: Date) -> TimeInterval {
        now.timeIntervalSince(departedAt)
    }

    /// The trailing reading: `now`, `2m`, `9m`, `1h`, `4h`.
    ///
    /// **Never more than three characters, and never more than one digit of
    /// hours**, which is the window agreeing with the reading rather than a
    /// coincidence: nothing can read `5h`, because at five hours the row is
    /// gone (`expanded-panel-v2.md` §2.3). Without it the column would have to
    /// hold `12h` and eventually `3d`. The figures are tabular, so it is steady
    /// at its widest rather than steady at every value.
    ///
    /// A bare age cannot be confused with a bare Running reading: it is one
    /// line tall, under a rule, and counting the other way.
    nonisolated func ageText(at now: Date) -> String {
        let seconds = max(age(at: now), 0)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        return "\(Int(seconds / 3600))h"
    }

    /// The same reading as words, because a screen reader cannot be shown a
    /// column (`expanded-panel-v2.md` §6).
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

/// One rate-limit window, and what is left of it.
///
/// A window has a label because a product can have more than one, and the label
/// is the product's own name for it rather than this app's paraphrase. Codex
/// publishes a duration per window and names the limit only when the account is
/// capped on one model; Claude Code writes `Current session`, `Current week
/// (all models)` and a per-model week whose name changes with the model.
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

    /// One window, with nothing known about it: the product has limits and
    /// this app cannot read them right now. The footer draws a `-- left` line
    /// for it, which is the honest thing to draw for a window that exists.
    nonisolated static let unavailable = QuotaSnapshot(
        remainingPercent: nil,
        resetsAt: nil,
        todayTokens: nil
    )

    /// No windows at all: this product publishes no quota this app reads, and
    /// none is being waited for.
    ///
    /// The distinction is the footer's, and the third product is the first to
    /// need it. `quota-footer-v2.md` §5: *a product with no limits still gets
    /// its row — an outer row and no inner ones*, because the absence of lines
    /// is what says there is nothing to report. Given ``unavailable`` instead,
    /// a product that will never have a window draws one line of dashes under
    /// its name on every render, for ever, which reads as a reading that has
    /// not come back yet.
    nonisolated static let noneReported = QuotaSnapshot(windows: [])

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
    let setupStatus: IntegrationSetupStatus
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
        setupStatus: IntegrationSetupStatus = .active,
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

/// One quota window as the footer's table draws it: a line of three columns.
///
/// **Three strings and no fill.** It carried a `0–1` share for the `496 × 3`
/// rule that used to stand above the caption; the rule is gone
/// (`quota-footer-v2.md` §1.1) — it drew as a length exactly what the caption
/// two points to its right printed as a figure — and what is left is the three
/// things that were in the caption, each now with a column of its own.
nonisolated struct FooterWindow: Equatable, Sendable {
    /// What the product calls this window, in the product's own words:
    /// `Current session`, `All models`, `Fable`, `Weekly limit`. Empty only
    /// where a product publishes no name for the window at all.
    let label: String
    /// `72% left`, or `-- left` where the reading could not be made — held as
    /// its two parts, because only one of them can fail.
    let share: ShareReading
    /// The countdown to the reset — `Resets in 4 hours 12 minutes`,
    /// `Resets in 5 days 2 hours` — or `Not started`, or `--`.
    let timer: String
    /// What a screen reader hears in place of ``timer``, which keeps the
    /// absolute day the column trades away (§7).
    let spokenTimer: String
}

/// One product's group in the footer's table: the product outside, its windows
/// inside.
///
/// **The two levels were always in this type.** Version 3.0 of the footer
/// flattened them into one sorted list of windows; grouping is both truer to
/// the data and what lets products keep Settings' order while windows keep the
/// reader's (`quota-footer-v2.md` §8.6). Neither level sorts.
///
/// A product with no limits keeps its group and draws no inner lines — its
/// spend is attributed, and the absence says there is nothing to report.
nonisolated struct FooterRule: Identifiable, Equatable, Sendable {
    let agent: AgentKind
    /// This product's own tokens for today: `310.1M today`, or `-- today`.
    let today: SpendReading
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
    /// Whether this product's list holds a finished, unread Turn that its own
    /// matrix is not drawing.
    ///
    /// **The one state the summary can lose.** The collapsed surface draws the
    /// most urgent status and nothing else, and three of the four survive that:
    /// approval outranks everything, input loses only to approval and the mark
    /// still says a person is wanted, and a running turn that loses asks for
    /// nobody and ends by itself. Only `.completed` both loses and waits — it
    /// is in the list at all only while the product still believes it is unread
    /// (`PRD.md` §7), so it clears when someone reads it and never on its own.
    ///
    /// So this is true exactly when the mark beside the column is telling part
    /// of the truth: a row here has ended and gone unread, and the matrix is
    /// drawing something other than lull. It is what ``SessionCountDots``
    /// breathes on, and it is deliberately **not** a general answer to "the
    /// summary hides things" — a buried `.inputNeeded` does not set it, because
    /// approval and input are the same kind of thing at two ranks and the mark
    /// says a person is wanted either way (`figma-design.md` §4.1).
    ///
    /// Both halves read ``MonitorAggregation/effectiveStatus(of:)``, like the
    /// summary and the sort, so a finished turn whose subagents are still in
    /// flight counts as running and is spoken for by its badge rather than
    /// twice over.
    let buriesAFinishedTurn: Bool


    /// Whether this product is holding a Turn the user still has to attend to.
    ///
    /// The three states that wait on a person, against the one that does not:
    /// approval and input are stopped until they are answered, a finished Turn
    /// is stopped until it is read (`CONTEXT.md`, *unread terminal state*), and
    /// a running Turn asks for nobody and ends by itself. It is deliberately
    /// **not** ``MonitorStatus/wantsPerson`` plus a case: that property answers
    /// what the *reading's ground* says, which is about being asked something,
    /// while this one answers whether there is anything here for the user at
    /// all.
    ///
    /// **Both halves of "has a finished Turn", because the summary can lose
    /// one.** ``status`` is this product's most urgent row, so a Turn that
    /// finished under a running one is spoken for by ``buriesAFinishedTurn``
    /// and by nothing else -- the same asymmetry the breathing column exists
    /// for. Both read ``MonitorAggregation/effectiveStatus(of:)``, so a
    /// finished Turn whose subagents are still working counts as running here
    /// too: that Thread is still working, and nothing is waiting on the user
    /// yet.
    ///
    /// Read by the collapsed surface with `Hide the wings` on, where it decides
    /// which matrices come out from behind the cut-out
    /// (``MonitorStore/compactDrawnMarks``). Nothing else reads it: with the
    /// wings drawn, every mark is drawn whatever it is saying.
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
        // needs the user. Input still wins here, and that is not the table
        // being contradicted: the table ranks approval first (`PRD.md` §6.2)
        // but it ranks *two rows* against each other, and this is one row
        // against itself. A refused approval is never closed by either product,
        // so a question that arrived afterwards is the more current fact about
        // the same thread — reporting the approval would be reporting a dialog
        // the user has already answered. Same rule, same reason, as
        // `SessionStatus.transitioned`.
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
    /// **Approval leads the table.** Both waits stop the product, but they ask
    /// for different things: an input wait is a question the user answers when
    /// they get to it, an approval wait is a decision the agent cannot proceed
    /// past and one the user may not want made. Now that the mark draws the two
    /// with different patterns — the knock against the advance
    /// (`NotchStatusMatrix.swift`) — the order also decides which of them a bar
    /// holding both shows, so it has to be the one worth interrupting for.
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
            .approvalNeeded,
            .inputNeeded,
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
            let markStatus = status(agents: [snapshot], sessions: own)
            return PresenceMark(
                agent: snapshot.agent,
                status: markStatus,
                sessionCount: own.count,
                subagents: SubagentBadge(
                    count: own.reduce(0) { $0 + $1.runningSubagentCount },
                    wantsAttention: own.contains { $0.subagentsAwaitingApproval }
                ),
                // Both clauses, and both on the derived status. The second is
                // what keeps the column quiet when it would only be repeating
                // the mark: with every row finished the matrix is already on
                // lull, and a signal that fires when nothing is wrong stops
                // being read.
                buriesAFinishedTurn: markStatus != .completed
                    && own.contains { effectiveStatus(of: $0) == .completed }
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

    /// One product's block on the live list: its rows, and whether anything in
    /// them is stopped waiting on a person.
    ///
    /// **The list is grouped and the queue is not**, and that is the whole of
    /// the asymmetry: a live row carries a status, a project, a title and a
    /// preview, of which the product is one more fact among several; a retired
    /// row carries a breadcrumb and an age, and the age is doing nearly all of
    /// the work. Today the queue's ages run in one descent down the column —
    /// `refreshRecentDepartures` sorts on `departedAt` descending precisely so
    /// they cannot flap — and grouping would restart that sequence at every
    /// header, putting the newest thing on the surface fourth. Product is the
    /// useful division of "who is waiting for me"; time is the useful division
    /// of "what did I just finish".
    struct SessionGroup: Identifiable, Equatable, Sendable {
        let agent: AgentKind
        let sessions: [MonitoredSession]
        /// Whether one of these rows is stopped waiting for a person.
        ///
        /// **Derived status, like the summary and the sort** (`PRD.md` §6.2),
        /// so a subagent stuck at a dialogue counts and a finished turn whose
        /// subagents are still working does not.
        let wantsAttention: Bool

        var id: AgentKind { agent }
    }

    /// The live list as blocks, one per product that has a row, in the fixed
    /// product order and never in one the state can move.
    ///
    /// **The order is `AgentKind`'s own**, which is the order the collapsed
    /// marks kept before they folded into one aggregate and the order
    /// `MonitorStore.footerRules` still hands the quota table. Ordering the
    /// blocks by their most urgent member was written and rejected for the
    /// reason `dual-agent-design.md` §3.1 rejected it for the marks: the
    /// objection to an order is not that it indicates something, it is that it
    /// **moves**, and two blocks trading places is a much larger movement than
    /// two marks doing it.
    ///
    /// **A product with no rows gets no block**, so it draws no header —
    /// nothing is drawn while it has nothing to say (`panel-v2.md` §1 rule 2),
    /// and the band above already counts what is running. Rows keep the order
    /// they arrive in, which is ``rowOrder``'s, so a status change re-sorts a
    /// row inside its own block and it never crosses a header.
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
            .approvalNeeded: 0,
            .inputNeeded: 1,
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

    /// Time remaining until the quota resets, written out.
    ///
    /// **`Resets in 34 minutes`, `Resets in 4 hours 12 minutes`,
    /// `Resets in 5 days 2 hours` — two units, in words.** It was `47m`, `2h`,
    /// `3d 12h`, on the argument that the words were repeated once a window
    /// down a column where every line is a countdown. Two things overturned
    /// that, and both arrived with the same change. The column beside this one
    /// now holds each window's own name — `Current session`, `All models`,
    /// `5h limit` — so a bare `4h` stood next to a `5h` that was a window
    /// length rather than a countdown, and the two read as the same kind of
    /// thing. And the row stopped being a rank of bare figures the moment it
    /// carried a phrase, so the verb costs width the line has and buys back
    /// what the abbreviation was eliding.
    ///
    /// **Minutes survive an hour now.** `2h` was drawn for anything between two
    /// hours and two hours fifty-nine, which made this the one reading on the
    /// footer less precise than the figure it read — a share is drawn to the
    /// percent beside it. The rule is two units, largest first, and the smaller
    /// is dropped only when it is zero rather than written as `0 minutes`.
    ///
    /// This reads the remaining *duration*, not calendar days: "Resets today"
    /// was true at both 00:30 and 23:30 and told you nothing about which. The
    /// absolute day survives in ``spokenResetText(resetsAt:remainingPercent:now:)``
    /// for anyone who wants Friday rather than four days (§7).
    ///
    /// A missing reset has two meanings and this tells them apart by what else
    /// the window knows. Claude Code's 5-hour window starts on the first
    /// request, so until one is made there is no instant to count down to --
    /// an untouched window, not a failed reading, and it says `Not started`.
    /// **Any other missing reset draws `--`**, which is the general rule for a
    /// field this app could not read: replace the figure in its own place and
    /// mark it in no other way (§8.3). It said `Reset unavailable`, which read
    /// as the quota display being broken -- the one thing it was not.
    ///
    /// **The signal that rode the old wording survives the change.**
    /// `non-public-codex-integration-features.md` lists a *consumed* window
    /// showing a percentage but no reset among the signs that Claude Code's
    /// `/usage` output has moved. What distinguishes it was never the words: it
    /// is a spent window with no reset, against an unspent one at `100% left`
    /// that reads `Not started`. After this it is a percentage beside a `--`.
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

    /// `1 day`, `5 days`, and nothing at all for a zero.
    ///
    /// A zero returns nil rather than `0 hours` so the caller drops the unit
    /// instead of drawing it: `Resets in 5 days` is the whole reading when the
    /// hours are none, and two units is a ceiling rather than a shape.
    nonisolated private static func count(_ value: Int, of unit: String) -> String? {
        guard value > 0 else { return nil }
        return "\(value) \(unit)\(value == 1 ? "" : "s")"
    }

    /// The same reset, spoken.
    ///
    /// `--` is a reading for the eye; a screen reader gets the word
    /// `unavailable`, and gets the absolute instant where the column shows a
    /// duration — `resets Friday at 09:00` beside a drawn `4d 6h` (§7).
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

    /// `Friday`, and `09:00`, in the app's own language.
    ///
    /// Pinned to `en_GB` rather than left to the system locale for the same
    /// reason every other user-readable string in this app is (`AGENTS.md` §1):
    /// the sentence around it is British English, and half a sentence in
    /// another language is worse than either.
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

    /// What every field this app could not read draws in its own place.
    ///
    /// Two characters, with the field's unit beside them where it has one:
    /// `-- today`, `-- left`, and the timer's bare `--` because a countdown has
    /// no unit to keep. Nothing is dimmed, no icon is drawn, and nothing
    /// appears anywhere else on the panel to announce it (§8.3).
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

/// A day's spend, in the two parts it is drawn in.
///
/// **The unit is not the part that could not be read**, which is why they are
/// held apart: an unreadable total draws `-- today`, keeping the word and
/// replacing only the figure (`quota-footer-v2.md` §8.3). It is also how the
/// line is drawn — the figure in `#C7C7CC` and `today` in `#7C7C80` — so the
/// split the fallback needs and the split the drawing needs are one split.
nonisolated struct SpendReading: Equatable, Sendable {
    /// `518.7M`, or `--`.
    let figure: String
    /// `today`, always: this reading has one unit and it never changes.
    let unit = "today"

    /// The whole line, which is what a test and a screen reader read.
    nonisolated var text: String { "\(figure) \(unit)" }

    /// What the line says out loud — never the two characters, and never zero.
    nonisolated var spokenText: String {
        figure == UsageSummaryFormatter.unreadable
            ? "Tokens today unavailable"
            : "\(figure) tokens today"
    }
}

/// A window's share of what is left, in the two parts it is drawn in.
///
/// The same split ``SpendReading`` makes, for the same reason and now under one
/// rule: **on this footer the figure is ``NotchPalette/reading`` and the words
/// around it are ``NotchPalette/label``.** The resting line already drew it —
/// `518.7M` bright, `today` grey — and it was the only line that did, so `96%`
/// used to be drawn at exactly the value of the word `left` beside it. The one
/// number a person opens the table to read had no emphasis at all.
///
/// **It says nothing about value.** The split is identical at `2%` and at
/// `98%`, so `quota-footer-v2.md` §4 holds as written: no quota figure on this
/// surface is drawn differently for being low. What changed is role, not
/// value — and a `--` that could not be read is a figure like any other, drawn
/// in the figure's own ink rather than dimmed (§8.3).
nonisolated struct ShareReading: Equatable, Sendable {
    /// `96%`, or `--`.
    let figure: String
    /// `left`, always: this reading has one unit and it never changes.
    let unit = "left"

    /// The whole reading, which is what a test reads.
    nonisolated var text: String { "\(figure) \(unit)" }

    /// What the line says out loud — never the two characters.
    nonisolated var spokenText: String {
        figure == UsageSummaryFormatter.unreadable
            ? "share unavailable"
            : "\(figure) left"
    }
}

// MARK: - Where the headings stand

/// Where every block heading of the grouped live list stands at one scroll
/// offset — in the flow, docked on the top strip, or waiting on the foot line
/// (`expanded-panel-v2.md` §4.6).
///
/// **A function of the offset and of nothing else.** There is no animation
/// here and no state: scrolling back plays every motion in reverse because
/// the same offset always gives the same drawing. The view asks this once per
/// scroll change and draws what it is told; the tests ask it directly.
///
/// Three positions, and a heading is always in exactly one, or between two:
///
/// - **In the flow** — where the list's own geometry puts it: its slack, its
///   chip, its count and its rule, scrolling with the rows.
/// - **On the top strip** — the one `16` pt line under the band. The block
///   you are in holds it with its chip at `0` and its rule under it, and the
///   blocks you have passed stand beside that chip in register order, names
///   only, at ``PanelMetrics/productTrailBadgeOpacity``. A heading *docks*
///   over ``PanelMetrics/productTrailDockingDistance`` of travel: it slides
///   right into its slot faster than it rises — `x` on a cubic ease-out, `y`
///   following the flow — so it never crosses the badge already there, and
///   the count and rule of the heading it replaces fade over the same travel.
/// - **On the foot line** — the viewport's last `16`, where the blocks still
///   to come wait as names alone, nearest first. The next block's badge is
///   always first on that line, so its slot is the flow's own `x`: it *lifts*
///   straight up at that `x` while its count and rule fade in, and the badges
///   behind it slide left to close the gap on the same ease.
///
/// A list that fits its viewport pins nothing: every position here is then
/// the flow position, and the drawing is the one the list has always made.
struct ProductTrailLayout: Equatable, Sendable {
    struct Heading: Equatable, Sendable {
        let agent: AgentKind
        /// The chip's top-left corner, in the viewport's coordinates.
        let x: CGFloat
        let y: CGFloat
        /// How much of the count and the rule is drawn: `1` in the flow, `0`
        /// on either trail, and between the two while docking or lifting.
        let tail: CGFloat
        /// How far onto a trail this heading is: `0` in the flow, `1` when it
        /// is a name on the top strip or the foot line. What a badge dims by,
        /// or — for a block that wants a person — flips by.
        let trailed: CGFloat
        /// Where this heading's chip stands in the list's own flow, which is
        /// the offset a click on its badge scrolls to.
        let flowChip: CGFloat

        var isOnTrail: Bool { trailed >= 1 }
    }

    let headings: [Heading]
    /// Whether the list is taller than its viewport at all. Nothing docks or
    /// lifts otherwise: every heading past the leading one stands at its flow
    /// position, and the leading chip stands where it always stands.
    ///
    /// **It no longer says whether the top strip's ground is drawn**, which it
    /// did until 2026-09-10: a heading's `16` of black travels with the
    /// heading and is drawn whatever the list is doing. The reasoning, and the
    /// fault that produced it, are in `ProductTrails`.
    let scrolls: Bool
    /// Whether any block is waiting on the foot line — which is when the foot
    /// draws its ground and the fade above it.
    let drawsFootLine: Bool

    /// The one easing on this surface: fast out of the slot, settling into it.
    ///
    /// A straight glide from under one badge to beside it crosses that badge
    /// for the middle third of the travel; `x` on this curve is `87.5%` home at
    /// half the travel, which clears a chip of any name before `y` has brought
    /// the two within a chip's height of each other.
    nonisolated static func ease(_ t: CGFloat) -> CGFloat {
        1 - pow(1 - t, 3)
    }

    /// Lay the headings out for one offset.
    ///
    /// - Parameters:
    ///   - groups: The blocks, in the order the list draws them.
    ///   - badgeWidths: How wide each block's badge draws, one per group —
    ///     ``PanelMetrics/productBadgeWidth(_:)``, measured off the name.
    ///   - offset: The scroll view's content offset.
    ///   - viewportHeight: What the list is drawn in.
    ///   - contentHeight: What the list asks for.
    nonisolated static func laidOut(
        groups: [MonitorAggregation.SessionGroup],
        badgeWidths: [CGFloat],
        offset: CGFloat,
        viewportHeight: CGFloat,
        contentHeight: CGFloat
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
        // A hair of tolerance: a list exactly as tall as its viewport does not
        // scroll, and floating arithmetic should not be what decides that.
        let scrolls = contentHeight > viewportHeight + 0.5
        func clamp(_ value: CGFloat, _ low: CGFloat = 0, _ high: CGFloat = 1) -> CGFloat {
            min(max(value, low), high)
        }

        // The flow: the first heading is its chip alone, every other one its
        // slack and then its chip, and a block's rows follow its chip.
        var flowChips: [CGFloat] = []
        var y: CGFloat = 0
        for (index, group) in groups.enumerated() {
            if index > 0 { y += slack }
            flowChips.append(y)
            y += line
            y += CGFloat(group.sessions.count) * PanelMetrics.sessionRowHeight
        }
        let chips = flowChips.map { $0 - offset }

        // How far each heading has docked onto the top strip, and how far it
        // sits on the foot line. The first heading is the top strip's from the
        // start; the two can never both be under way for one heading, because
        // the viewport is taller than twice the docking distance.
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
