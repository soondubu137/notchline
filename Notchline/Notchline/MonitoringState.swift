import Foundation

nonisolated enum MonitoringSignal: Sendable, Equatable {
    case turnStarted
    case inputWaitOpened
    case approvalWaitOpened
    /// An approval wait with no id of its own; it borrows the open call.
    case approvalWaitInferred
    /// An ordinary tool call was announced. Not evidence a turn began.
    case toolCallOpened
    /// A tool call that also asked the person something, without opening a wait.
    ///
    /// Codex's `request_user_input_async` (CLI `0.153.4`) answers the model in 51 ms while
    /// Desktop's card outlives the turn. Only the words are kept; no status, since the answer
    /// arrives as a new turn and a Skip arrives as nothing.
    case questionAskedWithoutWaiting
    case toolCallClosed
    /// The product no longer asks one request, keyed by ``MonitoringEvidence/requestID`` or the
    /// call's id. Ends that one wait; products whose requests end with their calls send
    /// ``toolCallClosed`` instead.
    case requestResolved
    case turnEnded
    /// A subagent this thread spawned began working.
    ///
    /// Not a turn boundary: a subagent has its own turn id and outlives the spawning turn
    /// (measured 2026-08-22: parent `Stop` 22:20:10, subagent finish 22:21:41).
    case subagentStarted
    case subagentStopped
    case inert
}

/// An approval the turn is blocked on, and how it can end.
///
/// `nonisolated` so the synthesized `Equatable` works off the main actor in
/// ``HookEventRepository``.
nonisolated struct PendingApproval: Sendable, Equatable {
    let toolUseID: String?
    /// Whether the id was borrowed from the open call. A borrowed approval closes only when
    /// approved (a denied Bash command sent no event, 2026-08-15), so it also ends on any
    /// evidence the turn resumed.
    let isInferred: Bool
    /// When the event that opened this wait arrived.
    ///
    /// A session reading that started before this cannot close the wait; see
    /// ``HookEventRepository/endAnsweredApprovalWaits(_:)``.
    let openedAt: Date
    /// What the person is being asked to grant. A field of the wait, so every site that clears
    /// the wait clears it (cf. CR-030). `nil` is still a wait.
    let request: AgentRequest?
    /// The request's own identity where the product has one, else the call's id. What a
    /// replacement replaces and a resolution resolves.
    let requestID: String
    let nativeRevision: String?

    nonisolated init(
        toolUseID: String?,
        isInferred: Bool,
        openedAt: Date,
        request: AgentRequest?,
        requestID: String? = nil,
        nativeRevision: String? = nil
    ) {
        self.toolUseID = toolUseID
        self.isInferred = isInferred
        self.openedAt = openedAt
        self.request = request
        guard let identity = requestID ?? toolUseID else {
            preconditionFailure("A wait requires a request identity or a tool call identity")
        }
        self.requestID = identity
        self.nativeRevision = nativeRevision
    }

    /// The same wait, with its request no longer answerable. The wait stands (§8.1).
    nonisolated func withdrawingAnswerHandle() -> PendingApproval {
        PendingApproval(
            toolUseID: toolUseID,
            isInferred: isInferred,
            openedAt: openedAt,
            request: request?.answerable(on: nil),
            requestID: requestID, nativeRevision: nativeRevision
        )
    }
}

/// A question the turn is blocked on, and what it is asking.
nonisolated struct PendingInput: Sendable, Equatable {
    /// An associated native tool call, if the request belongs to one.
    /// Standalone native questions require only their own request identity.
    let toolUseID: String?
    let openedAt: Date
    /// What is being asked, where the event carried it. See ``PendingApproval/request``.
    let request: AgentRequest?
    /// See ``PendingApproval/requestID``.
    let requestID: String
    let nativeRevision: String?

    nonisolated init(
        toolUseID: String?,
        openedAt: Date,
        request: AgentRequest?,
        requestID: String? = nil,
        nativeRevision: String? = nil
    ) {
        self.toolUseID = toolUseID
        self.openedAt = openedAt
        self.request = request
        guard let identity = requestID ?? toolUseID else {
            preconditionFailure("A wait requires a request identity or a tool call identity")
        }
        self.requestID = identity
        self.nativeRevision = nativeRevision
    }

    nonisolated func withdrawingAnswerHandle() -> PendingInput {
        PendingInput(
            toolUseID: toolUseID,
            openedAt: openedAt,
            request: request?.answerable(on: nil),
            requestID: requestID, nativeRevision: nativeRevision
        )
    }
}

struct OpenToolUse: Sendable, Equatable {
    let id: String
    /// `tool_name` as reported, to check a `PermissionRequest` is about this call.
    let name: String?
}

/// What one agent has open and is waiting for, in arrival order.
///
/// One per agent, since an id-less `PermissionRequest` pins to the open call (2026-08-23), and
/// collections keyed by request identity, since one slot let a second approval overwrite the
/// first (`docs/product-generalisation-plan.md` package 2). Status derives from what is left.
nonisolated struct ProducerWaits: Sendable, Equatable {
    private(set) var openCalls: [OpenToolUse] = []
    private(set) var inputs: [PendingInput] = []
    private(set) var approvals: [PendingApproval] = []

    nonisolated init() {}

    var isEmpty: Bool { openCalls.isEmpty && inputs.isEmpty && approvals.isEmpty }

    var pendingInput: PendingInput? { inputs.first }
    var pendingApproval: PendingApproval? { approvals.first }
    var openToolUse: OpenToolUse? { openCalls.last }
    var pendingInputToolUseID: String? { pendingInput?.toolUseID }

    /// Records a call as open; re-announcing keeps its place.
    mutating func announce(_ call: OpenToolUse) {
        if let index = openCalls.firstIndex(where: { $0.id == call.id }) {
            openCalls[index] = call
        } else {
            openCalls.append(call)
        }
    }

    /// The one open call an approval carrying no id of its own is about.
    ///
    /// Ambiguity fails closed: paired by tool name against open calls; several candidates is no
    /// pairing unless exactly one has no approval filed yet (a queued dialogue). A wait under the
    /// wrong call is closed by the wrong `PostToolUse`.
    func callToBorrow(forTool toolName: String?) -> OpenToolUse? {
        let candidates = openCalls.filter {
            toolName == nil || $0.name == nil || $0.name == toolName
        }
        if candidates.count == 1 { return candidates[0] }
        let unasked = candidates.filter { call in !approvals.contains { $0.toolUseID == call.id } }
        return unasked.count == 1 ? unasked[0] : nil
    }

    mutating func open(_ input: PendingInput) {
        if let index = inputs.firstIndex(where: { $0.requestID == input.requestID }) {
            inputs[index] = input
        } else {
            inputs.append(input)
        }
    }

    mutating func open(_ approval: PendingApproval) {
        if let index = approvals.firstIndex(where: { $0.requestID == approval.requestID }) {
            approvals[index] = approval
        } else {
            approvals.append(approval)
        }
    }

    /// Closes a call and ends every wait about it. Returns whether anything was there.
    @discardableResult
    mutating func closeCall(_ id: String) -> Bool {
        let before = self
        openCalls.removeAll { $0.id == id }
        inputs.removeAll { $0.toolUseID == id }
        approvals.removeAll { $0.toolUseID == id }
        return self != before
    }

    @discardableResult
    mutating func resolve(requestID: String, revision: String? = nil) -> Bool {
        let before = self
        inputs.removeAll { $0.requestID == requestID && (revision == nil || $0.nativeRevision == revision) }
        approvals.removeAll { $0.requestID == requestID && (revision == nil || $0.nativeRevision == revision) }
        return self != before
    }

    /// Ends every inferred approval about a call other than `id`, where refusals are inferred.
    ///
    /// A denied call is never closed (measured 2026-08-15: 67 s of silence, then `Stop`), and
    /// Codex emits nothing while blocked on a prompt, so activity on another call proves an
    /// answer. Approvals owning their `tool_use_id` always get a closing event and are left alone.
    @discardableResult
    mutating func resolveInferredApprovals(exceptCall id: String, whenInferring infersDenials: Bool) -> Bool {
        guard infersDenials else { return false }
        let before = approvals.count
        approvals.removeAll { $0.isInferred && $0.toolUseID != id }
        return approvals.count != before
    }

    /// Ends every approval older than a reading that says no dialogue was open. See
    /// ``MonitoringRepository/endAnsweredApprovalWaits(_:)``.
    @discardableResult
    mutating func endApprovals(before moment: Date) -> Bool {
        let before = approvals.count
        approvals.removeAll { moment > $0.openedAt }
        return approvals.count != before
    }

    /// The turn's own terminal: every wait ends, the calls stay recorded.
    mutating func clearWaits() {
        inputs.removeAll()
        approvals.removeAll()
    }

    /// Everything, for a turn ended on evidence that is not an event.
    mutating func clearAll() {
        openCalls.removeAll()
        clearWaits()
    }

    @discardableResult
    mutating func withdraw(_ handle: AnswerHandle) -> Bool {
        var changed = false
        for index in inputs.indices where inputs[index].request?.answerHandle == handle {
            inputs[index] = inputs[index].withdrawingAnswerHandle()
            changed = true
        }
        for index in approvals.indices where approvals[index].request?.answerHandle == handle {
            approvals[index] = approvals[index].withdrawingAnswerHandle()
            changed = true
        }
        return changed
    }

    var heldAnswerHandles: [AnswerHandle] {
        inputs.compactMap { $0.request?.answerHandle } + approvals.compactMap { $0.request?.answerHandle }
    }
}

struct MonitoredTurnState: Sendable {
    let threadID: String
    let turnID: String
    var sessionStatus: SessionStatus
    /// What the turn's own agent has open and is waiting for (``ProducerWaits``). Open calls are
    /// what an id-less `PermissionRequest` borrows its id from (see ``MonitoringRepository``).
    var waits = ProducerWaits()
    var pendingInput: PendingInput? { waits.pendingInput }
    var pendingApproval: PendingApproval? { waits.pendingApproval }
    var openToolUse: OpenToolUse? { waits.openToolUse }
    var pendingInputToolUseID: String? { pendingInput?.toolUseID }
    var startedAt: Date
    var lastEventAt: Date
    /// Turns this thread has already moved past.
    ///
    /// Needed despite a serial read queue: ADR 0013 records Claude Code delivering a `Stop` ahead
    /// of its own subagent's `PermissionRequest` under the same `prompt_id`.
    var retiredTurnIDs: Set<String>
    var promptPreview: String?
    var assistantPreview: String?
    /// The last question this turn asked without waiting for the answer.
    ///
    /// Turn-level: the answer arrives as the next turn. Set only by
    /// ``HookSignal/questionAskedWithoutWaiting``; newest wins, as Codex Desktop keeps one pending
    /// user-input request per conversation. Words only: there is nowhere to send an answer.
    var questionAskedWithoutWaiting: String?
    /// Subagents this thread has started and not yet seen stop, keyed by `agent_id`.
    ///
    /// A thread fact carried across turn boundaries: a subagent outlives the turn that spawned it.
    /// Their `turn_id` is the subagent's own.
    var runningSubagentIDs: Set<String> = []
    /// When that set last changed, and nothing else.
    ///
    /// Read only by ``TerminalUnreadMembershipGate``: `lastEventAt` must not move for a subagent,
    /// yet a finished row needs a settling window from its last subagent stopping (91 s after
    /// `Stop`, 2026-08-22). An uncounted agent's `SubagentStop` must not move it.
    var lastSubagentBoundaryAt: Date?
    /// What each of this thread's subagents has open, keyed by `agent_id`.
    ///
    /// Carried across turn boundaries: a subagent's prompt can open after the parent's `Stop`
    /// (Claude Code 2026-08-23, `Stop` +4.21 s, dialog +4.75 s). Decides no turn identity.
    var subagentSlots: [String: ProducerWaits] = [:]
    /// Whether this turn's own terminal event said the session was pausing rather than finishing.
    ///
    /// Claude Code re-enters the parent 50–130 ms after a background subagent stops (CLI 2.1.241),
    /// so the count alone flickered `Completed`/`Running`; `Stop`'s `background_tasks` tells done
    /// from paused. Turn-level. No time inference (`AGENTS.md` §6.2).
    var pausedForBackgroundWork: Bool = false
    /// Whether the product says it is writing this thread down nowhere.
    ///
    /// Thread-level. `transcript_path: null` skips App Server reads refused with
    /// `-32600 "thread not loaded"` (side chats, Desktop's internal threads); a row still needs a
    /// vouched Thread
    /// ([ADR 0017](../../docs/adr/0017-a-row-requires-a-thread-the-app-server-vouches-for.md)).
    /// Latest wins; absent reads as false.
    var threadHasNoTranscript: Bool = false
    /// A prompt this thread was told about while its own turn was still open.
    ///
    /// Codex's `--approve-for-me` reviewer uses the parent's `session_id` and no `agent_id`, so its
    /// `UserPromptSubmit` looks like a second turn; adopted, the row said `Running` for ever
    /// (2026-08-24, `docs/tech-design.md` §9.2). On Codex a prompt after `Stop` is held too.
    ///
    /// Redeemed only by a `turn_context` in this thread's rollout
    /// ([ADR 0011](../../docs/adr/0011-a-turn-may-end-on-evidence-that-is-not-a-hook-event.md)),
    /// never by an event under that id; see ``HookEventRepository/adoptTurnsOnRecord(_:)``.
    var heldTurnStart: HeldTurnStart?

    /// Every turn id this thread has ever held back.
    ///
    /// Outlives the single candidate above: a reviewer opens a turn per assessment, so earlier ids
    /// must still be refused. Carried across turn boundaries like ``retiredTurnIDs``, bounded by
    /// the thread leaving ``HookEventRepository``.
    var heldTurnIDs: Set<String> = []
    /// The prompt's `cwd`, for a product whose row names its Project by the directory's last
    /// component (`docs/product-support.md` §2). Unused by Codex and Claude Code. Thread-level.
    var workingDirectory: String? = nil

    /// A turn start waiting for this thread's own record to name it.
    nonisolated struct HeldTurnStart: Sendable, Equatable {
        let turnID: String
        let startedAt: Date
        let promptPreview: String?

        nonisolated init(turnID: String, startedAt: Date, promptPreview: String?) {
            self.turnID = turnID
            self.startedAt = startedAt
            self.promptPreview = promptPreview
        }
    }

    nonisolated init(
        threadID: String,
        turnID: String,
        sessionStatus: SessionStatus,
        pendingInput: PendingInput? = nil,
        pendingApproval: PendingApproval? = nil,
        openToolUse: OpenToolUse? = nil,
        startedAt: Date,
        lastEventAt: Date,
        retiredTurnIDs: Set<String>,
        promptPreview: String?,
        assistantPreview: String?,
        runningSubagentIDs: Set<String> = [],
        lastSubagentBoundaryAt: Date? = nil,
        subagentSlots: [String: ProducerWaits] = [:],
        threadHasNoTranscript: Bool = false,
        heldTurnIDs: Set<String> = [],
        workingDirectory: String? = nil
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.sessionStatus = sessionStatus
        if let openToolUse { waits.announce(openToolUse) }
        if let pendingInput { waits.open(pendingInput) }
        if let pendingApproval { waits.open(pendingApproval) }
        self.startedAt = startedAt
        self.lastEventAt = lastEventAt
        self.retiredTurnIDs = retiredTurnIDs
        self.promptPreview = promptPreview
        self.assistantPreview = assistantPreview
        self.runningSubagentIDs = runningSubagentIDs
        self.lastSubagentBoundaryAt = lastSubagentBoundaryAt
        self.subagentSlots = subagentSlots
        self.threadHasNoTranscript = threadHasNoTranscript
        self.heldTurnIDs = heldTurnIDs
        self.workingDirectory = workingDirectory
    }

    nonisolated var status: SessionStatus {
        sessionStatus
    }

    /// Puts the status where the turn's own unresolved waits say it is.
    ///
    /// Derived, not stepped, so resolving one approval of two leaves `Approval needed`. A question
    /// outranks an approval (Codex never closes a denied approval, so the following question is
    /// the proof of an answer); a finished turn absorbs everything.
    nonisolated mutating func deriveStatus() {
        guard sessionStatus != .completed else { return }
        sessionStatus = !waits.inputs.isEmpty
            ? .inputNeeded
            : (!waits.approvals.isEmpty ? .approvalNeeded : .running)
    }

    /// How many of this thread's subagents are sitting on a permission prompt.
    ///
    /// Capped by ``runningSubagentIDs``: both products stamp `agent_id` on unannounced agents
    /// (2026-08-23), so a slot is not evidence of a subagent (`PRD.md` §6.2). Only `> 0` is drawn.
    nonisolated var subagentsAwaitingApprovalCount: Int {
        subagentSlots.filter { agentID, slots in
            runningSubagentIDs.contains(agentID) && slots.pendingApproval != nil
        }.count
    }

    nonisolated var subagentsAwaitingApproval: Bool {
        subagentsAwaitingApprovalCount > 0
    }

    /// Every connection this turn is holding open, its subagents' included; closing one the row
    /// is not drawing would answer that subagent by silence.
    nonisolated var heldAnswerHandles: [AnswerHandle] {
        waits.heldAnswerHandles + subagentSlots.values.flatMap(\.heldAnswerHandles)
    }

    /// Every request this thread's row could open, in the order it opens them.
    ///
    /// Deterministic and stable under arrivals: the turn's questions, its approvals, then running
    /// subagents' approvals (`PRD.md` §6.2). Within a rank, answerable before readable, then
    /// arrival order (a replacement keeps its place; subagents by open instant, then agent), then
    /// identity. A newer arrival of equal or lower rank never moves the one on screen.
    nonisolated var requestsAwaitingAnAnswer: [AgentRequest] {
        struct Ranked {
            let request: AgentRequest
            let order: Double
            let producer: String
        }
        func sorted(_ entries: [Ranked]) -> [AgentRequest] {
            entries.sorted { lhs, rhs in
                if lhs.request.canBeAnswered != rhs.request.canBeAnswered { return lhs.request.canBeAnswered }
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                if lhs.producer != rhs.producer { return lhs.producer < rhs.producer }
                return lhs.request.id < rhs.request.id
            }.map(\.request)
        }
        let ownInputs = waits.inputs.enumerated().compactMap { index, wait in
            wait.request.map { Ranked(request: $0, order: Double(index), producer: "") }
        }
        // An approval about a call this turn asks as a question is that question's prompt, not a
        // second request: Claude Code's `AskUserQuestion` files both, which drew `Request 1 of 2`
        // (Claude Desktop, 2026-09-12). The approval stays filed to mark the call as asked.
        let questionCalls = Set(waits.inputs.compactMap(\.toolUseID))
        let ownApprovals = waits.approvals.enumerated().compactMap { index, wait -> Ranked? in
            if let call = wait.toolUseID, questionCalls.contains(call) { return nil }
            return wait.request.map { Ranked(request: $0, order: Double(index), producer: "") }
        }
        // A subagent's question is not offered. Claude Code gives subagents no `AskUserQuestion`
        // (measured 2026-09-12, Desktop 2.1.266 and CLI 2.1.270); on Codex it is unmeasured whether
        // one reaches a person. If Claude Code grants the tool, measure before hiding it.
        let subagents = subagentSlots
            .filter { agentID, _ in runningSubagentIDs.contains(agentID) }
            .flatMap { agentID, slots in
                slots.approvals.compactMap { wait in
                    wait.request.map {
                        Ranked(request: $0, order: wait.openedAt.timeIntervalSinceReferenceDate, producer: agentID)
                    }
                }
            }
        return sorted(ownInputs) + sorted(ownApprovals) + sorted(subagents)
    }

    nonisolated var requestAwaitingAnAnswer: AgentRequest? {
        requestsAwaitingAnAnswer.first
    }

    /// The instant this turn's own terminal arrived.
    ///
    /// What all read evidence is dated against on both products (Claude Desktop's
    /// `lastFocusedAt`, foregrounding, terminal access time, Codex Desktop's blue dot). Not
    /// ``terminalBoundaryAt``, which a subagent pushes past the unread answer. Meaningful only
    /// once terminal.
    nonisolated var turnEndedAt: Date { lastEventAt }

    /// The instant a finished row's settling window is measured from: the later of `lastEventAt`
    /// and ``lastSubagentBoundaryAt``.
    ///
    /// Never for dating read evidence: a `SubagentStop` came 91 s after `Stop` (2026-08-22), and
    /// reads taken while the subagent worked were discarded. Use ``turnEndedAt``.
    nonisolated var terminalBoundaryAt: Date {
        max(lastEventAt, lastSubagentBoundaryAt ?? lastEventAt)
    }
}

/// One Turn the product recorded as interrupted, and when.
///
/// From ``ClaudeCodeTranscriptReader`` to ``HookEventRepository/endInterruptedTurns(_:)``.
/// Unlike the session reading it carries a turn identity and is held to it.
struct TurnInterruption: Sendable, Equatable {
    let threadID: String
    let turnID: String
    let endedAt: Date
    /// Whether the stop also cut this Turn's subagents off from it.
    ///
    /// Codex only (CLI `0.151.0-alpha.7.1`, 2026-08-29): an interrupt kills the Turn's `wait_agent`
    /// but the subagent works on (`SubagentStop` 27 s later) and its output can never reach the
    /// Turn, so its count is dropped. Claude Code runs the subagent's `SubagentStop` on interrupt.
    let orphansSubagents: Bool

    nonisolated init(
        threadID: String,
        turnID: String,
        endedAt: Date,
        orphansSubagents: Bool = false
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.endedAt = endedAt
        self.orphansSubagents = orphansSubagents
    }
}

/// One Turn a thread's own record says is that thread's.
///
/// The beginning-of-Turn mirror of ``TurnInterruption``, from the same sweep: Codex writes a
/// `turn_context` naming each Turn into its own thread's rollout, so a Turn not named there
/// belongs to something else (``MonitoredTurnState/heldTurnStart``). Consumed by
/// ``HookEventRepository/adoptTurnsOnRecord(_:)``; speaks only about the Turn it names.
struct TurnOnRecord: Sendable, Equatable {
    let threadID: String
    let turnID: String

    nonisolated init(threadID: String, turnID: String) {
        self.threadID = threadID
        self.turnID = turnID
    }
}

struct MonitoringStateSnapshot: Sendable {
    let hasObservedEvent: Bool
    let hasObservedLiveEvent: Bool
    let turns: [MonitoredTurnState]
    let didConsumeEvents: Bool
    let diagnostic: String?

    nonisolated init(
        hasObservedEvent: Bool,
        hasObservedLiveEvent: Bool,
        turns: [MonitoredTurnState],
        didConsumeEvents: Bool = false,
        diagnostic: String? = nil
    ) {
        self.hasObservedEvent = hasObservedEvent
        self.hasObservedLiveEvent = hasObservedLiveEvent
        self.turns = turns
        self.didConsumeEvents = didConsumeEvents
        self.diagnostic = diagnostic
    }
}

/// The assistant text one session is currently printing.
///
/// Lock-protected, not an actor: deltas fold on the listener's serial read queue at up to
/// 3.4/s, and an actor hop would put the reducer's mailbox on the product's critical path
/// (`AGENTS.md` §6.3).
nonisolated final class TurnPreviewStore: @unchecked Sendable {
    /// How much of one message is kept; also the memory bound, since deltas past it are dropped.
    nonisolated static let maximumCharacters = 240

    /// Sessions held before the oldest is dropped: a leak stop, since previews are pruned to the
    /// live session list every refresh.
    nonisolated static let maximumRetained = 64

    private struct SessionPreview {
        /// The turn this message belongs to; nil reads as "whichever turn is asking", so a build that
        /// stops sending the field keeps its text.
        let turnID: String?
        /// The message being printed; when it changes the text starts again.
        let messageID: String?
        var text: String
    }

    private let lock = NSLock()
    nonisolated(unsafe) private var previewsBySessionID: [String: SessionPreview] = [:]
    nonisolated(unsafe) private var order: [String] = []
    /// The sessions the last refresh listed, held only to qualify the edge in
    /// ``fold(delta:messageID:turnID:sessionID:)``.
    nonisolated(unsafe) private var listedSessionIDs: Set<String> = []

    nonisolated init() {}

    /// The text this turn is currently printing, if any was collected.
    ///
    /// Read, not consumed: a preview stands until its message is replaced or the session leaves
    /// the list, or the row would flicker.
    ///
    /// - Parameter turnID: The turn the row is drawing. Text from another turn (the previous turn's
    ///   closing words) is not answered with, so the prompt fallback works (`tech-design.md` §11).
    nonisolated func preview(
        forSession sessionID: String,
        inTurn turnID: String
    ) -> String? {
        lock.lock()
        let stored = previewsBySessionID[sessionID]
        lock.unlock()
        guard let stored, stored.turnID == nil || stored.turnID == turnID else {
            return nil
        }
        let trimmed = stored.text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated func retain(forSessions sessionIDs: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        previewsBySessionID = previewsBySessionID.filter { sessionIDs.contains($0.key) }
        order.removeAll { !sessionIDs.contains($0) }
        listedSessionIDs = sessionIDs
    }

    nonisolated func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        previewsBySessionID.removeAll()
        order.removeAll()
        listedSessionIDs.removeAll()
    }

    /// Folds one delta into the session's preview.
    ///
    /// Returns whether the drawn line moved and the last refresh listed the session; nothing else
    /// wakes for text. The head cap (``maximumCharacters``) limits a message to one or two wakes
    /// (CLI 2.1.234). The listed check prevents a wake loop for a session the refresh prunes.
    ///
    /// - Parameter turnID: The turn speaking; a turn change is a change in its own right.
    @discardableResult
    nonisolated func fold(
        delta: String,
        messageID: String?,
        turnID: String?,
        sessionID: String
    ) -> Bool {
        lock.lock()
        let existing = previewsBySessionID[sessionID]
        lock.unlock()

        guard !delta.isEmpty else { return false }
        // A new message or turn replaces the text rather than extending it.
        let continuesMessage = existing?.messageID == messageID
            && existing?.turnID == turnID
        let carried = continuesMessage ? (existing?.text ?? "") : ""
        let carriedLength = carried.count
        guard carriedLength < Self.maximumCharacters else { return false }
        let text = Self.normalized(
            appending: delta,
            to: carried,
            carriedLength: carriedLength
        )
        guard !text.isEmpty else { return false }
        let drawn = text.trimmingCharacters(in: .whitespaces)
        let wasDrawn = existing?.text.trimmingCharacters(in: .whitespaces)

        lock.lock()
        let isFirstSinceEmpty = previewsBySessionID[sessionID] == nil
        if isFirstSinceEmpty {
            order.append(sessionID)
        }
        previewsBySessionID[sessionID] = SessionPreview(
            turnID: turnID,
            messageID: messageID,
            text: text
        )
        while order.count > Self.maximumRetained {
            previewsBySessionID.removeValue(forKey: order.removeFirst())
        }
        // `isFirstSinceEmpty` too: a prune between the two locks leaves `existing` stale. And a
        // turn's first delta replaces the prompt even if the characters match.
        let didChange = isFirstSinceEmpty
            || drawn != wasDrawn
            || existing?.turnID != turnID
        let moved = didChange && listedSessionIDs.contains(sessionID)
        lock.unlock()
        return moved
    }

    /// One line, collapsed and cut: no control characters, single spaces, no leading space, at
    /// most ``maximumCharacters``.
    ///
    /// Seeded `carried` and an `Int` length avoid quadratic `String.count`; a 60 KB delta costs as
    /// much as a 120-byte one (measured). One trailing space is kept so the next delta joins
    /// (non-final deltas end on a line break, CLI 2.1.234); the caller trims.
    nonisolated static func normalized(
        appending delta: String,
        to carried: String,
        carriedLength: Int
    ) -> String {
        var normalized = carried
        normalized.reserveCapacity(maximumCharacters)
        var length = carriedLength
        var pendingSpace = !normalized.isEmpty && !normalized.hasSuffix(" ")

        for character in delta {
            if character.isWhitespace {
                pendingSpace = !normalized.isEmpty
                continue
            }
            guard !character.unicodeScalars.contains(
                where: CharacterSet.controlCharacters.contains
            ) else { continue }

            if pendingSpace {
                normalized.append(" ")
                pendingSpace = false
                length += 1
                if length >= maximumCharacters { return normalized }
            }
            normalized.append(character)
            length += 1
            if length >= maximumCharacters { return normalized }
        }

        if pendingSpace { normalized.append(" ") }
        return normalized
    }

    /// One string, collapsed and cut the same way, for text that arrives whole.
    nonisolated static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let folded = normalized(appending: text, to: "", carriedLength: 0)
            .trimmingCharacters(in: .whitespaces)
        return folded.isEmpty ? nil : folded
    }
}

/// Fans one change signal out to every subscriber, like ``DirectoryChangeWatcher``: a single
/// stored `AsyncStream` would allow only one consumer.
nonisolated final class MonitoringChangeBroadcast: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    nonisolated init() {}

    nonisolated func events() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let identifier = UUID()
            lock.lock()
            continuations[identifier] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.lock()
                continuations.removeValue(forKey: identifier)
                lock.unlock()
            }
        }
    }

    nonisolated func signal() {
        lock.lock()
        let current = Array(continuations.values)
        lock.unlock()
        for continuation in current {
            continuation.yield(())
        }
    }
}
