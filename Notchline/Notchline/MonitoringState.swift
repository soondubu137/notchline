import Foundation

nonisolated enum MonitoringSignal: Sendable, Equatable {
    /// A user submission opened a new turn.
    case turnStarted
    /// A wait for the user's answer opened, carrying its own `tool_use_id`.
    case inputWaitOpened
    /// A wait for the user's approval opened, carrying its own `tool_use_id`.
    case approvalWaitOpened
    /// A wait for the user's approval opened with no id of its own, so it has
    /// to borrow the call that is still open.
    case approvalWaitInferred
    /// An ordinary tool call was announced. Not evidence a turn began.
    case toolCallOpened
    /// A tool call was announced that also **asked the person something**,
    /// without opening a wait for the answer.
    ///
    /// Codex's `request_user_input_async` is the measured instance and the
    /// reason this case exists (2026-09-07 and 2026-09-08, CLI `0.153.4`): the
    /// tool answers the *model* `{"accepted":true}` in 51 ms and the turn runs
    /// on to its own `Stop`, while the *person* is left with a card in Codex
    /// Desktop that outlives the turn. So neither of the two obvious readings
    /// is true — it is not a wait this app could open and close, and it is not
    /// an ordinary tool call either, because a person was asked something and
    /// the row is the only place they may see it.
    ///
    /// What it establishes is exactly one thing: the question's own words, kept
    /// on the turn so the row can draw them instead of losing them under the
    /// next sentence the turn says. It changes no status, because a status this
    /// app cannot retire is worse than one it never showed — the answer arrives
    /// as a *new turn*, and a Skip, a snooze or Desktop's own auto-resolution
    /// arrive as nothing at all.
    case questionAskedWithoutWaiting
    /// An announced call ended, whatever the outcome.
    case toolCallClosed
    /// The turn reached its terminal.
    case turnEnded
    /// A subagent this thread spawned began working.
    ///
    /// Not a turn boundary and deliberately not treated as one. A subagent runs
    /// in a thread of its own with a turn id of its own, and outlives the turn
    /// that spawned it -- measured 2026-08-22, the parent's `Stop` at 22:20:10
    /// and the subagent's finish at 22:21:41. It is a fact about the *thread*,
    /// so it names no turn and ends none.
    case subagentStarted
    /// A subagent this thread spawned finished.
    case subagentStopped
    /// Recognised and consumed, with nothing to say about turn state.
    case inert
}

/// An approval the turn is blocked on, and how it can end.
///
/// `nonisolated` because the project defaults to main-actor isolation, which
/// would isolate the synthesized `Equatable` too — and this is compared inside
/// ``HookEventRepository``, off the main actor. It is a plain `Sendable` value,
/// so there is nothing for the isolation to protect.
nonisolated struct PendingApproval: Sendable, Equatable {
    let toolUseID: String
    /// Whether the id was borrowed from the open call rather than belonging to
    /// an approval tool of its own.
    ///
    /// The two shapes end differently. A `request_permissions` call is always
    /// closed by its own `PostToolUse`, whatever the human answers. A borrowed
    /// one is only closed when the human *approves*: measured 2026-08-15, a
    /// denied Bash command produced no event at all for that call -- 67 seconds
    /// of silence and then the turn's `Stop`. So a borrowed approval also has to
    /// end on any evidence the turn resumed, since Codex sends nothing while it
    /// is genuinely blocked on the prompt.
    let isInferred: Bool
    /// When the event that opened this wait arrived.
    ///
    /// Carried so that evidence which is not a hook event can be held to the
    /// same monotonic rule every hook event is held to. A reading of the
    /// session that *started* before this instant cannot have seen the dialog
    /// this wait is about, so it is not allowed to close it -- see
    /// ``HookEventRepository/endAnsweredApprovalWaits(_:)``. Getting
    /// that backwards would close a dialog the user is still looking at, which
    /// is worse than the delay it exists to fix.
    let openedAt: Date
    /// What the person is being asked to grant, where the event that opened
    /// this wait carried it.
    ///
    /// **A field of the wait rather than a slot beside it**, and that is the
    /// whole of its lifecycle: every `pendingApproval = nil` this reducer
    /// already performs -- the paired close, the inferred resolution, the turn
    /// ending, a session going away, a reading that says the dialog was
    /// answered elsewhere, a subagent stopping, a turn boundary -- clears this
    /// with it, and there is no eighth site to forget. `answer-in-notch.md` §17
    /// proposed a table keyed by `(agent_id, tool_use_id)`, which would need all
    /// seven repeated; a rule that held until one site forgot it is exactly the
    /// shape CR-030 turned out to be.
    ///
    /// `nil` is an ordinary answer: a wait whose payload carried nothing
    /// readable is still a wait, and the row still says a person is wanted.
    let request: AgentRequest?

    /// The same wait, with its request no longer answerable.
    ///
    /// The wait itself stands: §8.1 is that answering does not retire a row.
    nonisolated func withdrawingAnswerHandle() -> PendingApproval {
        PendingApproval(
            toolUseID: toolUseID,
            isInferred: isInferred,
            openedAt: openedAt,
            request: request?.answerable(on: nil)
        )
    }
}

/// A question the turn is blocked on, and what it is asking.
///
/// Replaces the bare `tool_use_id` this used to be, so that a question travels
/// with the wait it belongs to exactly as an approval's request does. Every
/// rule that only ever wanted the id still gets one, from the computed
/// `pendingInputToolUseID` beside each slot.
nonisolated struct PendingInput: Sendable, Equatable {
    /// This event's own `tool_use_id` -- unlike an approval's, never borrowed:
    /// both `AskUserQuestion` and `request_user_input` are ordinary tool calls
    /// and carry one.
    let toolUseID: String
    let openedAt: Date
    /// What is being asked, where the event carried it. See
    /// ``PendingApproval/request`` for why it lives here rather than beside.
    let request: AgentRequest?

    /// The same wait, with its request no longer answerable.
    nonisolated func withdrawingAnswerHandle() -> PendingInput {
        PendingInput(
            toolUseID: toolUseID,
            openedAt: openedAt,
            request: request?.answerable(on: nil)
        )
    }
}

/// A tool call that has been announced and not yet closed.
struct OpenToolUse: Sendable, Equatable {
    let id: String
    /// `tool_name` as the product reported it, used to check that a
    /// `PermissionRequest` is asking about this call and not some other one
    /// still in flight.
    let name: String?
}

/// What one agent has open, and what it is waiting for.
///
/// **A Turn used to hold exactly one of these, inline, and that was the whole
/// reason a subagent's events had to be thrown away.** Both products announce a
/// call and then ask about it in a second event that carries no id of its own
/// (`PermissionRequest`, measured on Codex `0.149.0-alpha.4.1` and Claude Code
/// `2.1.241` on 2026-08-23), so a wait can only be pinned to the call that is
/// still open. With one slot on the turn, a subagent's calls would be a second
/// stream through it: its `PreToolUse` would displace the main agent's open
/// call, and the main agent's `PostToolUse` would close the subagent's wait.
/// One per agent is what makes both streams safe, and it is all that makes them
/// safe.
nonisolated struct AgentWaitSlots: Sendable, Equatable {
    /// The open question, if any.
    var pendingInput: PendingInput?
    /// The call the human is being asked to approve, if any.
    var pendingApproval: PendingApproval?
    /// The most recent call this agent opened and has not yet closed.
    var openToolUse: OpenToolUse?

    /// Whether this agent has anything at all left in it.
    var isEmpty: Bool {
        pendingInput == nil && pendingApproval == nil && openToolUse == nil
    }

    /// The open question's id, for the rules that only ever wanted that.
    var pendingInputToolUseID: String? { pendingInput?.toolUseID }
}

struct MonitoredTurnState: Sendable {
    let threadID: String
    let turnID: String
    var sessionStatus: SessionStatus
    /// The open question, if any.
    var pendingInput: PendingInput?
    /// The call the human is being asked to approve, if any.
    var pendingApproval: PendingApproval?
    /// The most recent tool call this turn opened and has not yet closed.
    ///
    /// Codex asks about an ordinary tool with a `PermissionRequest` that names
    /// the tool but carries no `tool_use_id`. The id has to come from the
    /// `PreToolUse` that announced the same call moments earlier -- see
    /// ``HookEventRepository`` -- so the approval can close on the usual pairing
    /// instead of a timer.
    var openToolUse: OpenToolUse?
    /// The open question's id, for the rules that only ever wanted that.
    var pendingInputToolUseID: String? { pendingInput?.toolUseID }
    var startedAt: Date
    var lastEventAt: Date
    /// Turns this thread has already moved past.
    ///
    /// The redesign proposed deleting this, on the argument that arrival stamps
    /// taken on one serial read queue are monotonic so a late event from a
    /// retired turn cannot exist. That holds for the transport and not for the
    /// executor: ADR 0013 records Claude Code delivering a `Stop` ahead of its
    /// own subagent's `PermissionRequest` under the same `prompt_id`, and the
    /// reducer is shared. The Codex half of the claim is also unmeasured. So it
    /// stays, and it costs one `Set` per tracked thread.
    var retiredTurnIDs: Set<String>
    var promptPreview: String?
    var assistantPreview: String?
    /// The last question this turn asked without waiting for the answer.
    ///
    /// A turn-level fact, reset by the turn boundary like the two previews
    /// above and unlike the thread-level sets below: the answer to a question
    /// asked here arrives as the *next turn*, which is exactly when this stops
    /// being the thing to show.
    ///
    /// **Set only by ``HookSignal/questionAskedWithoutWaiting``**, so it holds
    /// a question nobody is waiting on — never one a row could answer, which
    /// lives on ``pendingInput`` with the wait it opened. The newest wins,
    /// which is also what the product does: Codex Desktop keeps at most one
    /// pending user-input request per conversation and drops the previous one
    /// when a new question arrives.
    ///
    /// Only the words are kept, not the request. A structured question is what
    /// a row draws when it can be answered, and this one cannot be — from here
    /// there is nowhere to send an answer, and no event that would say it had
    /// been sent.
    var questionAskedWithoutWaiting: String?
    /// Subagents this thread has started and not yet seen stop.
    ///
    /// **A fact about the thread, carried on whichever turn it currently
    /// holds.** A subagent outlives the turn that spawned it, so it is copied
    /// across every turn boundary rather than reset by one -- a user replying
    /// while a subagent is still working must not make it disappear. Keyed by
    /// `agent_id`, which is the only identity both `SubagentStart` and
    /// `SubagentStop` carry; their `turn_id` is the subagent's own and names
    /// nothing this reducer holds.
    var runningSubagentIDs: Set<String> = []
    /// When that set last changed, and nothing else.
    ///
    /// **"When the set changed" is literal, and it used not to be.** A
    /// `SubagentStop` naming an agent this thread never counted leaves the set
    /// alone and must leave this alone with it -- both products stamp
    /// `agent_id` on agents that never announced themselves, and Claude Code's
    /// arrive *minutes after* the turn they name has finished. See
    /// ``HookEventRepository/reduceSubagentBoundary(_:agentID:threadID:at:)``.
    ///
    /// **Read by exactly one caller**, ``TerminalUnreadMembershipGate``, and
    /// deliberately not by anything that decides turn identity. It exists
    /// because `lastEventAt` must not move for a subagent -- that stamp is the
    /// reducer's only bound against a subagent's chatter fending off membership
    /// reconciliation -- and yet a finished row whose last subagent has just
    /// stopped needs a settling window measured from *that* instant. Without
    /// one, the window is measured from a main-agent `Stop` that may be minutes
    /// old (91 seconds on the 2026-08-22 measurement) and the row vanishes the
    /// moment it stops saying anything is still working.
    ///
    /// A thread-level fact like the set it stamps, so it survives every turn
    /// boundary the set survives.
    var lastSubagentBoundaryAt: Date?
    /// What each of this thread's subagents has open, keyed by `agent_id`.
    ///
    /// A thread-level fact carried across turn boundaries, exactly like
    /// ``runningSubagentIDs`` and for the same measured reason: a subagent's
    /// permission prompt can open *after* the parent's `Stop` (Claude Code
    /// 2026-08-23, `Stop` at +4.21 s and the dialog at +4.75 s), so a slot reset
    /// by the turn boundary would forget a dialog the user is still looking at.
    ///
    /// Nothing in here decides turn identity. These events carry the
    /// subagent's own `turn_id` on Codex and the parent's `prompt_id` on Claude
    /// Code, and this table reads neither.
    var subagentSlots: [String: AgentWaitSlots] = [:]
    /// Whether this turn's own terminal event said the session was pausing
    /// rather than finishing.
    ///
    /// **The gap this closes is between two facts that are both true.** An
    /// asynchronous subagent's `SubagentStop` empties
    /// ``runningSubagentIDs``, and Claude Code re-enters the parent with a new
    /// prompt of its own -- measured 2026-08-23 against CLI 2.1.241 at 130 ms
    /// under `-p` and 50 ms in a pty. In between, a row whose only evidence was
    /// the count said `Completed`, and then said `Running` again, for a state
    /// the thread was never in. Claude Code's `Stop` had already said which of
    /// the two it was: `background_tasks` is documented as the field that
    /// "lets hooks distinguish 'session is done' from 'session is paused
    /// waiting for background work to wake it'".
    ///
    /// A fact about **this turn**, unlike the two above it, so it is not copied
    /// across a turn boundary: it is written by the turn's own `Stop` and it
    /// cannot outlive the turn that wrote it. The next turn's `Stop` answers
    /// for the next turn, with an empty list when the work is finally done.
    ///
    /// Nothing infers it from elapsed time (`AGENTS.md` §6.2). It is set by one
    /// event and cleared by another, and its failure direction is the old
    /// behaviour: a build that stops sending the field puts the flicker back
    /// and invents nothing.
    var pausedForBackgroundWork: Bool = false
    /// Whether the product says it is writing this thread down nowhere.
    ///
    /// **A fact about the thread**, carried across turn boundaries like the
    /// subagent facts above and unlike the turn's own previews: a thread the
    /// product will not write down is not written down for one turn.
    ///
    /// It answers [ADR 0017](../../docs/adr/0017-a-row-requires-a-thread-the-app-server-vouches-for.md)'s
    /// question a round trip early. A row requires a Thread the App Server
    /// vouches for, and the threads that never get one -- a Codex side chat,
    /// and the internal threads Desktop runs alongside a user's -- are refused
    /// with `-32600 "thread not loaded"` once per metadata interval for as
    /// long as they run. `transcript_path: null` is the same answer from the
    /// product itself, on the thread's first event, so those reads stop being
    /// issued at all.
    ///
    /// **It decides what is asked, never what is drawn.** Whether a row exists
    /// stays with the Thread the App Server hands over, which is ADR 0017
    /// unchanged: this only says the App Server will not be asked, and a
    /// thread nobody asked about has no Thread and therefore no row.
    ///
    /// **Latest wins, and false is the answer with nothing behind it.** A
    /// build that does not send the key leaves it false and every read goes
    /// out exactly as before. An event Codex delivers under this thread's id
    /// that a nested agent produced names *that* agent's file, and the worst
    /// that can do is put the thread back on the ordinary path -- one
    /// `thread/read`, refused, which is where this started.
    var threadHasNoTranscript: Bool = false
    /// A prompt this thread was told about while its own turn was still open.
    ///
    /// **The one thing a nested agent can do that `agent_id` does not label.**
    /// Codex's `--approve-for-me` reviewer is a thread of its own whose rollout
    /// records the *parent* as its `session_id` and its own turn as `turn_id`,
    /// and its `UserPromptSubmit` carries no `agent_id` at all -- so it arrives
    /// looking exactly like the user starting a second turn on this thread.
    /// Adopted as one, it retired the real turn id, and the turn's own `Stop`
    /// was then refused as late: the row said `Running` for ever, its timer
    /// counted from the reviewer's prompt, and the reviewer's instructions
    /// became the row's preview. Reproduced end to end on a Release build,
    /// 2026-08-24 (`docs/tech-design.md` §9.2).
    ///
    /// So a prompt whose turn is not this thread's open one is **held** rather
    /// than adopted, and held is recoverable where retiring is not.
    ///
    /// **On Codex, a prompt arriving after this thread's turn has finished is
    /// held on the same terms.** "A real next turn always lands after `Stop`"
    /// is true of Codex and says nothing about the order two hook processes
    /// reach this app in: a reviewer's prompt landing after the parent's own
    /// `Stop` went through the one branch the hold did not cover and was
    /// adopted outright -- the row re-timed from 0:00, showing *"The following
    /// is the Codex agent history whose request action you are assessing"*,
    /// and `Running` for ever because nothing ends a reviewer's turn under
    /// this thread's id. Reported again 2026-09-08 on a Release build. The
    /// record that redeems a hold is written before the hook, so the user's
    /// own next turn is promoted on the sweep the hold wakes, and a reviewer's
    /// never is. Claude Code keeps adopting at once: it has no such caller,
    /// and no record to hold for.
    ///
    /// **What redeems it used to be "any event arrives under that id", and
    /// that was not evidence.** The sentence it was standing in for is *this
    /// turn was this thread's after all*, and a nested agent's own events
    /// arrive under its own turn id exactly as a resumed turn's do -- so the
    /// test was satisfied word for word by the one caller it was written to
    /// exclude. It held only while the reviewer emitted nothing but its prompt
    /// (measured on CLI `0.149.0-alpha.4.3`, which emitted no hook at all).
    /// A reviewer that runs one read-only check, as its own instructions
    /// permit, walked straight back into the defect above and landed on
    /// whichever assessment was held at the time: a row saying `Working...`
    /// for ever whose preview read *"The following is the Codex agent history
    /// added since your last approval assessment"* -- the reviewer's **second
    /// and later** prompts, one guardian thread running a fresh turn per
    /// assessment (up to 8 per parent turn, measured over 1 970 of them).
    ///
    /// Redemption is now the thread's **own record**: a `turn_context` in this
    /// thread's rollout naming that turn ([ADR 0011](../../docs/adr/0011-a-turn-may-end-on-evidence-that-is-not-a-hook-event.md)'s
    /// evidence, asked about a turn's identity rather than its end), applied by
    /// ``HookEventRepository/adoptTurnsOnRecord(_:)``. A nested agent's turn is
    /// written to a rollout of its **own**, so this thread's record never names
    /// it, and no reading is needed to exclude it -- silence does.
    var heldTurnStart: HeldTurnStart?

    /// Every turn id this thread has ever held back.
    ///
    /// **The refusal has to outlive the candidate above.** That slot holds one
    /// turn start, the newest, because that is the only one a redemption could
    /// ever want -- but a reviewer opens a turn per assessment, so by the time
    /// its third prompt is the candidate its first two are no longer named
    /// anywhere, and an event under either of those would have found the thread
    /// with nothing to refuse it. This set is what refuses them, and it holds
    /// ids rather than starts so that remembering one costs a string.
    ///
    /// Carried across every turn boundary, exactly like ``retiredTurnIDs`` and
    /// bounded by the same thing: the thread leaving ``HookEventRepository``.
    /// A turn proven to be another agent's does not become this thread's
    /// because this thread started a new one.
    var heldTurnIDs: Set<String> = []
    /// The directory the product said the prompt was submitted from (`cwd`),
    /// for a product whose row names its work by that directory's last
    /// component (L2's working-directory Project source, `docs/product-support.md` §2).
    /// Codex ignores it — its Project comes from Desktop — and Claude Code
    /// takes the directory from its own session list. Carried across a Turn
    /// boundary like the subagent facts, because the directory is the
    /// Thread's, not the Turn's.
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

    nonisolated var status: SessionStatus {
        sessionStatus
    }

    /// How many of this thread's subagents are sitting on a permission prompt.
    ///
    /// **Capped by the running set on purpose.** Both products stamp `agent_id`
    /// on events from agents that never announced themselves — Claude Code's
    /// own TUI background agents, and the reviewer Codex spawns for
    /// `--approve-for-me`, which is a nested agent with no `SubagentStart` of
    /// its own (both measured 2026-08-23). A slot is therefore never evidence
    /// that this thread has a subagent; only ``runningSubagentIDs`` is. The
    /// cap also means this count can never outlive the count that draws it:
    /// what clears one clears the other, so the stuck-state risk stays the
    /// single one already accepted in `PRD.md` §6.2.
    ///
    /// A count in the reducer, a flag on the surface, since
    /// `dual-agent-design.md` §10. The badge that draws this thread's trailing
    /// mark carries ``runningSubagentIDs``'s count — waiting subagents
    /// included — and says *whether* any of them is stopped by flipping its
    /// ground rather than by drawing a second figure. The reducer has a real
    /// count here and keeps one; only `> 0` is ever drawn from it.
    nonisolated var subagentsAwaitingApprovalCount: Int {
        subagentSlots.filter { agentID, slots in
            runningSubagentIDs.contains(agentID) && slots.pendingApproval != nil
        }.count
    }

    /// Whether a subagent of this thread is sitting on a permission prompt.
    nonisolated var subagentsAwaitingApproval: Bool {
        subagentsAwaitingApprovalCount > 0
    }

    /// The one request this thread's row can open, out of everything it is
    /// waiting on.
    ///
    /// **One row holds one request**, because a row is
    /// `agent:threadID:turnID` and a subagent has no row of its own. So this
    /// picks, and the order it picks in is the order the surface already reads:
    /// the turn's own question first, then the turn's own approval, then a
    /// subagent's -- which is `PRD.md` §6.2's priority with its stated
    /// exception, *input outranks approval where both are this turn's*, and it
    /// has to agree or a row would say `Approval needed` and open to nothing.
    ///
    /// Among several waiting subagents the **oldest** wins. It has been
    /// blocking longest, and it is the only stable choice: newest-first would
    /// swap an open row's contents under a reader's eye, which is exactly what
    /// `answer-in-notch.md` §6.3 exists to prevent. `runningSubagentIDs` gates
    /// it for the same reason ``subagentsAwaitingApprovalCount`` is gated --
    /// an agent that never announced itself is not this thread's.
    ///
    /// A subagent's *question* is deliberately not offered, exactly as its
    /// count is not drawn: whether one reaches a person at all is unmeasured,
    /// and a request this app cannot vouch for is worse than none.
    /// Every connection this turn is holding open, its subagents' included.
    ///
    /// Deliberately *every* one and not only the request a row can open: a
    /// subagent's approval that is not the one the row is drawing is still a
    /// hook process this app is keeping waiting, and closing it because the
    /// surface has nothing to say about it would answer that subagent's
    /// question by silence.
    nonisolated var heldAnswerHandles: [AnswerHandle] {
        var tickets: [AnswerHandle] = []
        if let ticket = pendingInput?.request?.answerHandle {
            tickets.append(ticket)
        }
        if let ticket = pendingApproval?.request?.answerHandle {
            tickets.append(ticket)
        }
        for slots in subagentSlots.values {
            if let ticket = slots.pendingInput?.request?.answerHandle {
                tickets.append(ticket)
            }
            if let ticket = slots.pendingApproval?.request?.answerHandle {
                tickets.append(ticket)
            }
        }
        return tickets
    }

    nonisolated var requestAwaitingAnAnswer: AgentRequest? {
        if let request = pendingInput?.request { return request }
        if let request = pendingApproval?.request { return request }
        return subagentSlots
            .filter { agentID, _ in runningSubagentIDs.contains(agentID) }
            .compactMap { _, slots in slots.pendingApproval }
            .min { $0.openedAt < $1.openedAt }?
            .request
    }

    /// The instant this turn's own terminal arrived.
    ///
    /// **What every piece of read evidence is dated against**, on both
    /// products, and the reason it is published under a name of its own rather
    /// than read off `lastEventAt` at four call sites. Reading is something a
    /// person does to a turn's *answer*, and the answer landed here: Claude
    /// Desktop's `lastFocusedAt`, its return to the foreground, a controlling
    /// terminal's access time and Codex Desktop's blue dot are all evidence
    /// only if they came after this.
    ///
    /// Deliberately not ``terminalBoundaryAt``, which a subagent pushes past
    /// the answer nobody has read yet -- see there for what that cost.
    ///
    /// Meaningful only once the turn is terminal, exactly like the stamp below
    /// it; on a running turn it is simply the last thing that happened.
    nonisolated var turnEndedAt: Date { lastEventAt }

    /// The instant a finished row's settling window is measured from.
    ///
    /// The later of the turn's own last event and the last subagent boundary,
    /// which for every row without a subagent is simply `lastEventAt`. The two
    /// stamps stay separate because only this one is allowed to slip forward
    /// on a subagent's account; see ``lastSubagentBoundaryAt``.
    ///
    /// **It says when this *thread* stopped working and nothing else, and it
    /// may not be used to date read evidence.** A subagent's `SubagentStop`
    /// was measured 91 seconds after its parent's `Stop` (2026-08-22), and
    /// from `dff7d66` until this was split out both products compared the
    /// user's read against this instant: Codex against the unread file's
    /// `modificationDate`, Claude Code against `lastFocusedAt`, the return to
    /// the foreground and the terminal's access time. A user who read the
    /// answer while the subagent was still working -- which is the ordinary
    /// case, since that is when the row is on the notch -- had their read
    /// dated before the bar and thrown away, and the row then waited on
    /// evidence from a moment nobody was going to act at. See
    /// ``turnEndedAt``.
    nonisolated var terminalBoundaryAt: Date {
        max(lastEventAt, lastSubagentBoundaryAt ?? lastEventAt)
    }
}

/// One Turn the product recorded as interrupted, and when.
///
/// Produced by ``ClaudeCodeTranscriptReader`` and consumed by
/// ``HookEventRepository/endInterruptedTurns(_:)``. It carries a turn identity
/// because the evidence behind it does -- which is the whole difference between
/// this and the session reading beside it, and the reason it can be held to the
/// turn it names.
struct TurnInterruption: Sendable, Equatable {
    let threadID: String
    let turnID: String
    /// When the interrupt was written, as the product stamped it.
    let endedAt: Date
    /// Whether the stop also cut this Turn's subagents off from it.
    ///
    /// **A Turn's subagent set normally outlives the Turn, and that is the
    /// point of it**: a subagent finishes after its parent's `Stop`, the parent
    /// collects the result, and a row reading the count alone is what stops
    /// `Completed` meaning "nothing is happening here" while it does. A stop is
    /// where that stops being true.
    ///
    /// Measured 2026-08-29, CLI `0.151.0-alpha.7.1`, a Codex turn told to spawn
    /// one subagent and wait for it, interrupted 5 s in:
    ///
    /// ```text
    /// PreToolUse   collaborationspawn_agent          -- closes
    /// PostToolUse  collaborationspawn_agent
    /// PreToolUse   collaborationwait_agent           -- never closes
    /// SubagentStart  agent=01a04f6f-8570
    /// ...  turn/interrupt, turn_aborted
    /// PreToolUse   Bash  agent=01a04f6f-8570         -- the subagent works on
    /// PostToolUse  Bash  agent=01a04f6f-8570
    /// SubagentStop       agent=01a04f6f-8570         -- 27 s after the abort
    /// ```
    ///
    /// The subagent is not killed and does eventually report. What the stop
    /// killed is the `wait_agent` the Turn was going to collect it with, so
    /// whatever that subagent produces can never reach this Turn -- it is
    /// written into the rollout as `SubAgentActivity` against a Turn that is
    /// over, and nothing re-enters. Counting it goes on saying *the thread is
    /// working* for as long as the orphan runs, on a Turn the user ended by
    /// hand, and with no bound on how long that is.
    ///
    /// So this is not "guessing the subagent stopped": it is declining to
    /// report work the stopped Turn can no longer receive as that Turn's. A
    /// `SubagentStop` that does arrive afterwards names an agent the thread no
    /// longer counts, which the reducer already treats as changing nothing.
    ///
    /// **Codex only, and only because only Codex was measured this way.**
    /// Claude Code runs a subagent's own `SubagentStop` on an interrupt (its
    /// query loop logs `SubagentStop on interrupted query failed`), so the
    /// count clears itself there and the evidence says nothing more. It
    /// defaults to the answer that changes nothing.
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
/// The mirror of ``TurnInterruption``, and produced from the same file by the
/// same sweep: that one carries what the product wrote down about a Turn
/// **ending**, this one what it wrote down about a Turn **beginning**. Codex
/// writes a `turn_context` at the head of every Turn naming the Turn it opens,
/// in the rollout of the thread that Turn belongs to — so a Turn running under
/// a thread's identity that this thread's rollout does not name belongs to
/// something else running under that identity, which is the whole question
/// ``MonitoredTurnState/heldTurnStart`` exists to ask.
///
/// It is consumed by ``HookEventRepository/adoptTurnsOnRecord(_:)`` and, like
/// the interruption beside it, it may only speak about the Turn it names.
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
/// Lock-protected rather than actor-isolated, and deliberately: deltas are
/// folded on the listener's serial read queue at up to 3.4 a second, and an
/// actor hop there would put the reducer's mailbox on a product's critical
/// path for text that changes no state. Same shape as the transport beside it
/// (`AGENTS.md` §6.3).
nonisolated final class TurnPreviewStore: @unchecked Sendable {
    /// How much of one message is kept.
    ///
    /// Also the memory bound: once the head is full every further delta is
    /// dropped without being stored, so the bytes held per session are decided
    /// by a constant rather than by how much the model said.
    nonisolated static let maximumCharacters = 240

    /// How many sessions' previews are held before the oldest is dropped.
    ///
    /// Previews are pruned to the live session list on every refresh, so this
    /// is a leak stop for text belonging to a session that never appears there
    /// — not a working set.
    nonisolated static let maximumRetained = 64

    private struct SessionPreview {
        /// The turn this message belongs to, as the payload spelled it.
        ///
        /// Nil where the product does not say, and read as "whichever turn is
        /// asking" — the reading that keeps the row's text on a build that
        /// stopped sending the field, rather than blanking it.
        let turnID: String?
        /// Whichever assistant message is currently being printed. When this
        /// changes the text starts again — the newest message is the progress,
        /// and its head is what the row reports.
        let messageID: String?
        var text: String
    }

    private let lock = NSLock()
    nonisolated(unsafe) private var previewsBySessionID: [String: SessionPreview] = [:]
    nonisolated(unsafe) private var order: [String] = []
    /// The sessions the last refresh listed.
    ///
    /// Held only to qualify the edge in ``fold(delta:messageID:turnID:sessionID:)``.
    nonisolated(unsafe) private var listedSessionIDs: Set<String> = []

    nonisolated init() {}

    /// The text this turn is currently printing, if any was collected.
    ///
    /// Read, not consumed. A preview stands until the message it came from is
    /// replaced or the session leaves the live list, because a turn spends most
    /// of its life between events and a row that blanked itself after one
    /// refresh would flicker rather than report.
    ///
    /// **Scoped to the turn asking, which is what makes the row's fallback to
    /// the prompt work at all.** The store is keyed by session and a session
    /// outlives its turns, so the text sitting in it when a turn opens is the
    /// *previous* turn's closing words. Answering with those would describe
    /// work that has finished as the work being done -- the same failure the
    /// Codex side's `turnId` argument names (`tech-design.md` §11) -- and would
    /// leave the prompt fallback reachable only on a session's first turn.
    ///
    /// - Parameter turnID: The turn the row is drawing. Text stamped with a
    ///   different one is not this turn's and is not answered with.
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
        // The stored form keeps its trailing space so the next delta can join
        // onto it; a row never shows one.
        let trimmed = stored.text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Drops previews for sessions that are no longer live.
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
    /// Returns whether the line this session would *draw* moved, and the last
    /// refresh listed it. That is the edge the change stream carries.
    ///
    /// **This used to be the absent-to-present edge only, and a row that is
    /// never blank is exactly the case that got wrong.** Nothing else wakes for
    /// text: ``HookEventRepository/renderedProjection()`` holds no delta, and a
    /// tool call opening and closing leaves every field in it unchanged — so
    /// between two status changes the row kept whichever message happened to be
    /// half-printed at the last refresh, while the session went on to say three
    /// more things. What a user reads as "live progress" was then the step
    /// before the one being worked on, or older.
    ///
    /// **It is still not a 3.4 Hz redraw**, because the head is capped
    /// (``maximumCharacters``): once a message has filled it, every further
    /// delta of that message returns early and wakes nothing at all. Measured
    /// against CLI 2.1.234 — 1561 characters in eleven deltas, mean 142 each —
    /// a message costs two wakes and then goes quiet, however long it runs on.
    /// A short message costs one. The rate is therefore set by how often the
    /// agent starts a new message, which is the rate the row is meant to
    /// follow.
    ///
    /// Whitespace-only growth is not a change: the stored form keeps a trailing
    /// space so the next delta can join onto it (see ``normalized``), and the
    /// row never draws one.
    ///
    /// Without the listed test this is a loop rather than a wake: text from a
    /// session the list does not carry is pruned by the very refresh it asks
    /// for, which makes the next delta a change again — and the row it would
    /// draw is not on screen either way.
    ///
    /// - Parameter turnID: The turn that is speaking, so that
    ///   ``preview(forSession:inTurn:)`` can tell this turn's words from the
    ///   previous one's. A turn change is a change in its own right: the row
    ///   was drawing the prompt and is now drawing text, which is a different
    ///   line even in the one case where the two turns' text matches.
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
        // A new message replaces the old one rather than extending it: the row
        // shows the message being printed now, not the whole turn concatenated.
        // A new turn replaces it for the same reason and more strongly: its
        // words are not a continuation of anything the last turn said.
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
        // Compared as the row reads them, not as they are stored.
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
        // `isFirstSinceEmpty` is checked as well as the comparison, because a
        // prune between the two locks leaves `existing` describing text this
        // store no longer holds: the row is blank again, and putting text back
        // on it is a change whatever that text says. The turn is checked for a
        // narrower reason: the row draws the prompt until its turn has said
        // something, so the first delta of a turn moves the line it draws even
        // when the characters happen to match what the last turn left here.
        let didChange = isFirstSinceEmpty
            || drawn != wasDrawn
            || existing?.turnID != turnID
        let moved = didChange && listedSessionIDs.contains(sessionID)
        lock.unlock()
        return moved
    }

    /// One line, collapsed and cut.
    ///
    /// Control characters dropped, runs of whitespace collapsed to one space,
    /// no leading space, and never longer than ``maximumCharacters``.
    ///
    /// `carried` is seeded rather than rescanned, and the running length is
    /// carried as an `Int`. Both matter: `String.count` walks grapheme breaks,
    /// so rebuilding `carried + delta` and testing `.count` after every
    /// character would be quadratic in the cap and additionally copy the whole
    /// delta. The scan touches only the new delta and stops the moment the head
    /// is full, so a 60 KB delta costs the same as a 120-byte one — measured.
    ///
    /// A single trailing space **is** kept, and the seed relies on it: measured
    /// on CLI 2.1.234, every non-final delta ends on a line break, which
    /// collapses to that trailing space — so the next delta joins onto it and
    /// no separator is invented. Trimming the tail here instead would weld the
    /// last word of one delta onto the first word of the next; the caller trims
    /// it when the text is read.
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
                // Never leading: a message that opens with a newline should not
                // spend its first character on it.
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

/// Fans one change signal out to every subscriber.
///
/// Same shape as ``DirectoryChangeWatcher``'s, and for the same reason: a
/// consumer subscribes once at launch and goes on receiving edges, and more
/// than one may. A single stored `AsyncStream` would have exactly one
/// consumer -- fine for the service that merges it, and a trap for anything
/// that asks a second time.
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
