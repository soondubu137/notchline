import Foundation

/// The single Turn reducer and ordered live-evidence entry point.
/// Native decoding and transport ownership live in boundary adapters. A source
/// without configuration, Hooks or sockets constructs this with a policy alone.
actor MonitoringRepository {
    private let clock: any MonitorClock
    private let timing: MonitorTiming
    nonisolated let boundary: (any MonitoringBoundaryObserver)?
    private let policy: MonitoringReductionPolicy
    nonisolated private let inbox = MonitoringEvidenceInbox()
    nonisolated private let previews = TurnPreviewStore()
    nonisolated private let changes = MonitoringChangeBroadcast()
    private var hasObservedLiveEvent = false
    private var didReduceSinceLastReport = false
    private var unplaceableEventCount = 0
    private var announcedCallCount = 0
    private var closedCallCount = 0
    private var didOpenToolCallInThisBatch = false
    private var turnsByThreadID: [String: MonitoredTurnState] = [:]
    private var signalledProjection: [String] = []

    init(
        policy: MonitoringReductionPolicy,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard,
        boundary: (any MonitoringBoundaryObserver)? = nil
    ) {
        self.policy = policy
        self.clock = clock
        self.timing = timing
        self.boundary = boundary
    }

    nonisolated func changeEvents() -> AsyncStream<Void> { changes.events() }
    nonisolated var observationEpoch: MonitoringEpoch { inbox.epoch }

    /// Submit synchronously on the source's serial delivery queue. Tasks only
    /// kick a drain; they never establish event order. No historical replay.
    @discardableResult
    nonisolated func submit(_ evidence: MonitoringEvidence, in epoch: MonitoringEpoch) -> Bool {
        guard inbox.append(evidence, in: epoch) else { return false }
        Task { await self.drainInbox() }
        return true
    }

    /// Bounded content updates bypass the actor, exactly like native streamed
    /// deltas did before extraction. They cannot open or change a Turn.
    nonisolated func recordProgress(_ progress: MonitoringProgress, in epoch: MonitoringEpoch) {
        guard progress.producerID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
            return
        }
        inbox.ifCurrent(epoch) {
            if previews.fold(delta: progress.text, messageID: progress.messageID,
                             turnID: progress.turnID, sessionID: progress.threadID) {
                changes.signal()
            }
        }
    }

    nonisolated func preview(forSession sessionID: String, inTurn turnID: String) -> String? {
        previews.preview(forSession: sessionID, inTurn: turnID)
    }

    nonisolated func retainPreviews(forSessions sessionIDs: Set<String>) {
        previews.retain(forSessions: sessionIDs)
    }

    @discardableResult
    func drainDeliveredEvents() -> MonitoringStateSnapshot {
        drainInbox()
        let result = snapshot(didConsumeEvents: didReduceSinceLastReport)
        didReduceSinceLastReport = false
        return result
    }

    func observedState() -> MonitoringStateSnapshot { snapshot() }

    private func drainInbox() {
        let delivered = inbox.take()
        guard !delivered.isEmpty else { return }
        var didReduce = false
        for event in delivered {
            let accepted = reduce(event)
            boundary?.didApply(event, accepted: accepted)
            if accepted { didReduce = true }
            else { unplaceableEventCount += 1 }
        }
        if didReduce {
            hasObservedLiveEvent = true
            didReduceSinceLastReport = true
        }
        reconcileAnswerHandles()
        let didOpenToolCall = didOpenToolCallInThisBatch
        didOpenToolCallInThisBatch = false
        guard !signalIfProjectionChanged() else { return }
        if didOpenToolCall, policy.wakesOnToolCallOpened { changes.signal() }
    }

    private func reconcileAnswerHandles() {
        guard let boundary else { return }
        boundary.retainAnswerHandles(Set(turnsByThreadID.values.flatMap(\.heldAnswerHandles)))
    }

    func withdrawAnswerHandle(_ handle: AnswerHandle) {
        for (threadID, var turn) in turnsByThreadID {
            var changed = false
            if turn.pendingApproval?.request?.answerHandle == handle {
                turn.pendingApproval = turn.pendingApproval?.withdrawingAnswerHandle()
                changed = true
            }
            if turn.pendingInput?.request?.answerHandle == handle {
                turn.pendingInput = turn.pendingInput?.withdrawingAnswerHandle()
                changed = true
            }
            for (agentID, var slots) in turn.subagentSlots {
                if slots.pendingApproval?.request?.answerHandle == handle {
                    slots.pendingApproval = slots.pendingApproval?.withdrawingAnswerHandle()
                    turn.subagentSlots[agentID] = slots
                    changed = true
                }
                if slots.pendingInput?.request?.answerHandle == handle {
                    slots.pendingInput = slots.pendingInput?.withdrawingAnswerHandle()
                    turn.subagentSlots[agentID] = slots
                    changed = true
                }
            }
            if changed { turnsByThreadID[threadID] = turn }
        }
    }

    // MARK: - Evidence that is not a hook event

    /// Ends the turns of sessions that report they have stopped working.
    ///
    /// **The one thing that ends a turn without a hook event, and why.** A user
    /// interrupt fires nothing at all: measured against 2.1.235, the hook event
    /// registry has no cancel event of any kind, and every abort path in the
    /// CLI returns before its `Stop` hooks run -- so `Esc` leaves a row saying
    /// *Running*, or worse *Approval needed*, until the session's next prompt
    /// (CC-019, #38). A timeout is not the answer to that and never will be
    /// (`AGENTS.md` §6.2): a turn that has been quiet for a while is not a turn
    /// that has ended. What arrives instead is evidence -- the session itself
    /// stops saying it is busy, in the output of the same command that answers
    /// which sessions exist.
    ///
    /// The reducer stays the only thing that computes turn state. This does not
    /// hand the caller a turn to edit; it takes a fact about a *session* and
    /// applies the same rules any event gets, which is why it lives here and
    /// not in the service that reads the list.
    ///
    /// - Parameter observations: Session id to the moment its reading *began*.
    ///   A reading that started before the turn's last event proves nothing
    ///   about it -- the state it describes may predate that event entirely --
    ///   so it is ignored. That guard is what makes a cached list safe to act
    ///   on: an answer read half a minute ago cannot retire a turn that has
    ///   moved since.
    func endTurnsForStoppedSessions(
        _ observations: [String: Date]
    ) -> MonitoringStateSnapshot {
        for (threadID, observedAt) in observations {
            endOpenTurn(ofThread: threadID, named: nil, at: observedAt)
        }
        signalIfProjectionChanged()
        return snapshot()
    }

    /// Ends the turns the product itself recorded as interrupted.
    ///
    /// The other half of ``endTurnsForStoppedSessions(_:)``, for the sessions
    /// that half cannot reach. A session the Claude Code desktop app hosts
    /// publishes no working status at all -- the terminal interface writes that
    /// field and the desktop app runs the CLI without one -- so "the session
    /// stopped saying it was busy" is a sentence those sessions never say, and
    /// their rows went on freezing after the CLI's had stopped (CC-022, #41).
    /// What they do leave is a record in their own transcript, written at the
    /// moment of the abort.
    ///
    /// **This one names the turn, and that changes what it is allowed to do.**
    /// The session-status reading above carries no turn identity anywhere, so it
    /// may only speak about whichever turn is open. This carries the interrupted
    /// turn's `prompt_id`, which is this reducer's own turn identity, so it is
    /// held to it: an observation naming a turn the reducer is not holding does
    /// nothing rather than ending whatever happens to be open. Neither may open,
    /// name or describe a turn; both may only end one.
    func endInterruptedTurns(_ interruptions: [TurnInterruption]) -> MonitoringStateSnapshot {
        for interruption in interruptions {
            endOpenTurn(
                ofThread: interruption.threadID,
                named: interruption.turnID,
                at: interruption.endedAt,
                orphansSubagents: interruption.orphansSubagents
            )
        }
        signalIfProjectionChanged()
        return snapshot()
    }

    /// Gives a thread the Turn its own record says it is on.
    ///
    /// **The only thing that redeems a held prompt, and the reason it is not an
    /// event.** A prompt naming a Turn this thread was not holding is held back
    /// (``MonitoredTurnState/heldTurnStart``) because it may have come from a nested
    /// agent running under this thread's identity. What settles it has to be
    /// something a nested agent cannot produce, and its own events are not that:
    /// they arrive under its own turn id exactly as a resumed Turn's do. Its
    /// **rollout** is: Codex writes each Turn's `turn_context` into the rollout
    /// of the thread that Turn belongs to, and a reviewer's turns are written
    /// to a rollout of its own. So this thread's record naming the held Turn is
    /// the proof, and this thread's record staying silent is the refusal — no
    /// reading has to say "no", and none can.
    ///
    /// **It may only redeem what is already held.** Like
    /// ``endInterruptedTurns(_:)`` it carries a turn identity and is held to it,
    /// and unlike that one it may put a thread onto a Turn rather than take it
    /// off one — so it is deliberately the narrower of the two: it can promote
    /// the one start this thread already took in and set aside, and it cannot
    /// invent a Turn from a record alone.
    ///
    /// The promoted Turn is `Running` because that is what it is: a prompt
    /// opened it and no terminal has arrived for it. It keeps its own start and
    /// its own text, which is the point — the alternative on the resumed-Turn
    /// path is a row timing the Turn the user interrupted.
    func adoptTurnsOnRecord(_ records: [TurnOnRecord]) -> MonitoringStateSnapshot {
        for record in records {
            guard let current = turnsByThreadID[record.threadID],
                  current.turnID != record.turnID,
                  let held = current.heldTurnStart,
                  held.turnID == record.turnID,
                  !current.retiredTurnIDs.contains(record.turnID),
                  // The same monotonic rule every other route obeys: a start
                  // older than the Turn this thread is holding describes a
                  // moment that Turn has already been seen past.
                  held.startedAt > current.lastEventAt else {
                continue
            }
            var retiredTurnIDs = current.retiredTurnIDs
            retiredTurnIDs.insert(current.turnID)
            var heldTurnIDs = current.heldTurnIDs
            heldTurnIDs.remove(record.turnID)
            turnsByThreadID[record.threadID] = MonitoredTurnState(
                threadID: record.threadID,
                turnID: record.turnID,
                sessionStatus: .running,
                pendingInput: nil,
                pendingApproval: nil,
                openToolUse: nil,
                startedAt: held.startedAt,
                lastEventAt: held.startedAt,
                retiredTurnIDs: retiredTurnIDs,
                promptPreview: held.promptPreview,
                assistantPreview: nil,
                // A subagent outlives the Turn that spawned it, so it survives
                // this boundary as it survives every other one.
                runningSubagentIDs: current.runningSubagentIDs,
                lastSubagentBoundaryAt: current.lastSubagentBoundaryAt,
                subagentSlots: current.subagentSlots,
                threadHasNoTranscript: current.threadHasNoTranscript,
                heldTurnIDs: heldTurnIDs,
                workingDirectory: current.workingDirectory
            )
        }
        signalIfProjectionChanged()
        return snapshot()
    }

    /// Ends one open turn on evidence that is not a hook event.
    ///
    /// - Parameter named: The turn the evidence names, when it names one. Nil is
    ///   evidence that names none -- it applies to whichever turn the thread has
    ///   open, which is all a reading of a *session* can ever justify.
    /// - Parameter orphansSubagents: Whether the same evidence says this turn's
    ///   subagents were cut off from it. See ``TurnInterruption/orphansSubagents``
    ///   for the measurement; the default is the answer that changes nothing.
    private func endOpenTurn(
        ofThread threadID: String,
        named turnID: String?,
        at moment: Date,
        orphansSubagents: Bool = false
    ) {
        guard var turn = turnsByThreadID[threadID],
              turnID == nil || turn.turnID == turnID,
              turn.sessionStatus != .completed,
              moment > turn.lastEventAt else {
            return
        }
        turn.sessionStatus = turn.sessionStatus.transitioned(on: .completed)
        turn.pendingInput = nil
        turn.pendingApproval = nil
        turn.openToolUse = nil
        if orphansSubagents, !turn.runningSubagentIDs.isEmpty {
            turn.runningSubagentIDs.removeAll()
            // The waits go with them. A dialogue raised by a subagent of a turn
            // the user stopped is not a question anyone is going to answer on
            // this row, and it is the same rule as the turn's own
            // `pendingApproval` two lines up.
            turn.subagentSlots.removeAll()
            // The set moved, so the stamp that dates the set moves with it --
            // the invariant on ``MonitoredTurnState/lastSubagentBoundaryAt``. It
            // lands on the same instant `lastEventAt` is about to, which is
            // what the settling window should measure from: this is the moment
            // the row stopped saying anything was in flight.
            turn.lastSubagentBoundaryAt = moment
        }
        // Counted as the turn's last moment, so an event that really is older
        // than this evidence cannot reopen what it ended -- the same monotonic
        // rule ``mutateExactTurn(threadID:turnID:at:createWith:adoptContinuationWith:turns:mutation:)``
        // applies to everything else.
        turn.lastEventAt = moment
        turnsByThreadID[threadID] = turn
    }

    /// Ends the approval waits a human has been shown to have answered.
    ///
    /// **No hook fires when a person approves, on either host.** Measured
    /// 2026-08-23 against CLI 2.1.241 with *all thirty-one* hook events
    /// registered: between the `PermissionRequest` that opened the dialog and
    /// the call's own `PostToolUse` twenty-six seconds later, the only event of
    /// any kind was an unrelated agent's `SubagentStop`. `PostToolUse` lands
    /// when the *tool finishes* rather than when the dialog closes, so a row is
    /// right for a command that takes 200 ms and wrong for every second of one
    /// that takes longer -- thirteen seconds of `Approval needed` after the
    /// answer, on the first measurement of this.
    ///
    /// So the wait can only be ended by evidence that is not a hook event, and
    /// the two hosts keep that evidence in different places. **This method is
    /// the one rule both of them feed**, because what they produce is the same
    /// sentence -- *no dialog of this thread was in front of the user at this
    /// instant* -- and only the way they prove it differs:
    ///
    /// * A terminal-hosted session says so itself. `claude agents --json`
    ///   reads `waiting` (`waitingFor: "permission prompt"`) for exactly as
    ///   long as a dialog is up -- including one a *subagent* raised after the
    ///   parent turn's `Stop` -- and `busy` otherwise. `busy` **only**, never
    ///   "not `waiting`": `idle` does not prove the absence of a dialog, since
    ///   `Esc` reaches `idle` with one still drawn (CC-019), and reading a
    ///   wait's end out of an absence would close one the user is still looking
    ///   at.
    /// * A desktop-hosted session publishes no status at all -- the terminal
    ///   interface writes that field and Claude Desktop has no terminal
    ///   interface (CC-022, #41) -- but Claude Desktop logs both ends of every
    ///   dialog it raises. See ``ClaudeDesktopPermissionLogReader``.
    ///
    /// **It may only end a wait, exactly like the two methods above it.**
    /// Neither piece of evidence carries a turn id or an `agent_id`, so neither
    /// can open an approval any more than a session status can open a turn. It
    /// applies to whichever waits the thread is holding -- the turn's own and
    /// every subagent's -- because a session with no dialog open has none of
    /// them in front of the user.
    ///
    /// Each wait is held to its own stamp, so evidence older than a dialog can
    /// never close it. The cost of that strictness is one refresh, and both
    /// hosts have an edge that brings it: the session record is rewritten on
    /// the `waiting` to `busy` flip, and the desktop log is watched for as long
    /// as an answer is what the app is waiting for.
    ///
    /// - Parameter observations: Thread id to the instant no dialog was open.
    ///   For the session reading that is when the command **started running**,
    ///   which is the strictest thing it can be held to; for the desktop log it
    ///   is the instant Desktop stamped on the line saying the human answered.
    func endAnsweredApprovalWaits(
        _ observations: [String: Date]
    ) -> MonitoringStateSnapshot {
        for (threadID, observedAt) in observations {
            endApprovalWaits(ofThread: threadID, at: observedAt)
        }
        signalIfProjectionChanged()
        return snapshot()
    }

    /// Clears every approval wait one thread holds that the evidence outdates.
    ///
    /// Deliberately does not move `lastEventAt`. This is not the turn doing
    /// anything -- it is a reading of the session that happens to prove a
    /// dialog is gone -- and that stamp is the reducer's only bound against a
    /// row fending off membership reconciliation. ``endOpenTurn(ofThread:named:at:)``
    /// moves it because it *ends* the turn and a later event must not reopen
    /// what it closed; there is nothing here for a later event to undo, because
    /// a later `PermissionRequest` is a new dialog and should reopen the wait.
    private func endApprovalWaits(ofThread threadID: String, at moment: Date) {
        guard var turn = turnsByThreadID[threadID] else { return }
        var changed = false

        if let pending = turn.pendingApproval, moment > pending.openedAt {
            turn.pendingApproval = nil
            changed = true
            // The same re-derivation `toolCallClosed` performs, and for the
            // same reason: an input wait outranks the approval that was
            // cleared, and a turn already at `completed` absorbs both.
            turn.sessionStatus = turn.sessionStatus.transitioned(
                on: turn.pendingInputToolUseID != nil ? .inputNeeded : .running
            )
        }

        for (agentID, slots) in turn.subagentSlots {
            guard let pending = slots.pendingApproval, moment > pending.openedAt else {
                continue
            }
            var cleared = slots
            cleared.pendingApproval = nil
            changed = true
            if cleared.isEmpty {
                turn.subagentSlots.removeValue(forKey: agentID)
            } else {
                turn.subagentSlots[agentID] = cleared
            }
        }

        guard changed else { return }
        turnsByThreadID[threadID] = turn
    }

    /// Forgets the threads a listing of what exists no longer names.
    ///
    /// The reducer's own bound, and the only one it has: nothing else here ever
    /// removes a thread, so without this every thread the process has ever
    /// heard from is still being projected and sorted long after its rows
    /// stopped being drawn. Both products call it, from the same refresh that
    /// prunes their previews and caches against the same list.
    ///
    /// **A list is allowed to end a thread only where it can speak for it**,
    /// which is what the two exemptions below are. What "no longer named" means
    /// differs by product and does not have to be spelled out here: a Codex
    /// thread is archived or deleted, a Claude Code session exits or has its id
    /// rotated in place by `/clear`. Either way the caller has read which ones
    /// exist and this is held to that reading.
    ///
    /// - Parameters:
    ///   - listedThreadIDs: Every thread the reading named.
    ///   - snapshotStartedAt: When that reading *began*. A reading that started
    ///     before a Turn's last event cannot have seen what that event
    ///     reported, so it is not evidence against it.
    func removeThreads(
        notIn listedThreadIDs: Set<String>,
        snapshotStartedAt: Date
    ) -> MonitoringStateSnapshot {
        let now = clock.now()
        turnsByThreadID = turnsByThreadID.filter {
            if listedThreadIDs.contains($0.key) {
                return true
            }
            // A list request that began before the latest Hook boundary cannot
            // prove that the new Turn is gone.
            if snapshotStartedAt < $0.value.lastEventAt {
                return true
            }
            // A prompt hook can arrive just before the record that would have
            // listed its thread is written -- Codex's state DB, or the
            // `~/.claude/sessions` entry a desktop-hosted session is born with.
            // Keep a short grace period so reconciliation does not erase a new turn.
            return now.timeIntervalSince($0.value.startedAt)
                < timing.newTurnReconciliationGrace
        }
        signalIfProjectionChanged()
        return snapshot()
    }

    /// Ends every Turn this reducer is holding, and keeps everything else.
    ///
    /// **The one way a Turn ends without its own product saying so, and why it
    /// is not a guess.** Every other route into here reads an event, a list, or
    /// a status; this one reads the *producer*. A Turn is a claim about what one
    /// process is doing, so a caller that knows that process is gone knows the
    /// claim can no longer be true — and, worse, that nothing will ever arrive
    /// to falsify it, because the events that would have ended the Turn were the
    /// dead process's to send. Held rather than retired, such a Turn is
    /// permanent: no hook will name its `turn_id` again, and membership
    /// reconciliation keeps it because its thread is still listed
    /// (CR-Fable-007). Only the caller can hold this evidence, which is why the
    /// decision is not made here.
    ///
    /// The observation flags are deliberately untouched. Those hooks did fire,
    /// and the Settings card must not fall back to "never heard from" because
    /// the user restarted the app the hooks belong to.
    ///
    /// - Parameter didConsumeEvents: carried through from the drain this call
    ///   follows, so the returned snapshot still reports what that refresh took
    ///   off the socket.
    @discardableResult
    func discardTurns(didConsumeEvents: Bool = false) -> MonitoringStateSnapshot {
        guard !turnsByThreadID.isEmpty else {
            return snapshot(didConsumeEvents: didConsumeEvents)
        }
        turnsByThreadID.removeAll()
        signalIfProjectionChanged()
        return snapshot(didConsumeEvents: didConsumeEvents)
    }

    func resetIntegrationObservation(clearTurns: Bool) {
        hasObservedLiveEvent = false
        didReduceSinceLastReport = false
        unplaceableEventCount = 0
        inbox.reset { previews.removeAll() }
        boundary?.reset()
        if clearTurns { turnsByThreadID.removeAll() }
        reconcileAnswerHandles()
        signalledProjection = renderedProjection()
    }

    // MARK: - The reducer

    private func reduce(_ event: MonitoringEvidence) -> Bool {
        guard let threadID = stableIdentifier(event.threadID),
              let signal = event.signal else { return false }

        if signal == .inert {
            // Recognised and consumed. It needs no turn to address, so it
            // answers before the identity gate below.
            return true
        }

        // Both subagent signals are facts about the thread and name no turn
        // this reducer holds, so they answer before the turn identity gate.
        switch signal {
        case .subagentStarted, .subagentStopped:
            guard let agentID = stableIdentifier(event.agentID) else { return false }
            reduceSubagentBoundary(
                signal,
                agentID: agentID,
                threadID: threadID,
                at: event.observedAt
            )
            return true
        default:
            break
        }

        // **An event a subagent produced is not evidence about the thread's
        // turn, and must never be allowed to become one** -- which is why it
        // goes to a slot of the subagent's own rather than through the turn.
        // Codex stamps a subagent's hooks with the parent's `session_id` but
        // the subagent's own `turn_id`, so before these events were separated a
        // subagent's first `PreToolUse` was adopted as a continuation of the
        // row's turn: that retired the real turn id, the parent's own `Stop`
        // was then rejected as late, and nothing could end what was left. The
        // row said *Running* until the user resumed the thread or dismissed it
        // by hand. `reduceSubagentToolEvent` never touches turn identity, so
        // that shape cannot come back.
        //
        // These events were dropped outright until 2026-08-23, and what that
        // cost was the one state this product exists to report: a subagent's
        // own `PermissionRequest` never reached the row, so the row said
        // Running -- or `N subagents` -- while the product sat on a dialog.
        // Measured on both products the same day, and the arrival pattern is
        // identical: `PreToolUse` carrying a `tool_use_id`, then
        // `PermissionRequest` 20-30 ms later carrying `tool_name` and no id at
        // all. See `docs/technical-explorations/subagent-row-consistency/`
        // §6.1 and §6.3.
        if let agentID = stableIdentifier(event.agentID) {
            reduceSubagentToolEvent(
                signal,
                agentID: agentID,
                threadID: threadID,
                event: event,
                at: event.observedAt
            )
            return true
        }

        guard let turnID = stableIdentifier(event.turnID) else {
            return false
        }

        let receivedAt = event.observedAt
        let infersDenials = policy.infersApprovalRefusalFromActivity
        let requestAsked: (String) -> AgentRequest? = { id in
            event.request?.identified(by: id).answerable(on: event.answerHandle)
        }

        switch signal {
        case .turnStarted:
            var retiredTurnIDs = Set<String>()
            // A subagent is not ended by the user typing again, so it survives
            // the turn boundary that its spawning turn does not.
            let runningSubagentIDs = turnsByThreadID[threadID]?.runningSubagentIDs ?? []
            let lastSubagentBoundaryAt = turnsByThreadID[threadID]?
                .lastSubagentBoundaryAt
            // And neither is the dialog one of them is sitting on: the user
            // typing again does not answer it.
            let subagentSlots = turnsByThreadID[threadID]?.subagentSlots ?? [:]
            // A turn this thread once held back stays held back, whatever this
            // thread has done since -- so the set crosses this boundary the way
            // the subagent facts above it do.
            let heldTurnIDs = turnsByThreadID[threadID]?.heldTurnIDs ?? []
            // And so does what the product last said about writing this thread
            // down, which the tail of this reducer restates from this event.
            let threadHasNoTranscript = turnsByThreadID[threadID]?
                .threadHasNoTranscript ?? false
            if let current = turnsByThreadID[threadID] {
                if current.turnID == turnID {
                    guard receivedAt >= current.lastEventAt else { return true }
                    retiredTurnIDs = current.retiredTurnIDs
                } else {
                    guard receivedAt > current.lastEventAt,
                          !current.retiredTurnIDs.contains(turnID),
                          // **And a turn once held may never start one.** It
                          // was held because nothing said it was this thread's,
                          // and nothing since has: the same refusal every other
                          // route applies to a held id, so that a reviewer's
                          // repeated assessment is refused by the set rather
                          // than re-held as the candidate.
                          !(policy.settlesHeldTurnsFromRecord
                            && current.heldTurnIDs.contains(turnID)) else {
                        return true
                    }
                    // **A thread has one agent and one open turn.** A second
                    // turn cannot start on it while the first is still working:
                    // Codex Desktop queues a follow-up until the running turn's
                    // terminal, so a prompt that really is this thread's next
                    // turn always lands after `Stop`. One that lands *during* a
                    // turn came from something else running under this thread's
                    // identity -- see ``MonitoredTurnState/heldTurnStart``, which is
                    // where it goes instead of over the turn.
                    //
                    // **And after `Stop` is not proof either, on the product
                    // whose record can say.** The nested reviewer's prompt
                    // reaches this app through a hook process of its own, and
                    // the parent's `Stop` through another; the one landing
                    // after the other is exactly the takeover the hold exists
                    // to refuse, reached through the one branch it did not
                    // cover -- adopted outright, retiring the real turn, timed
                    // from the reviewer's prompt, showing its instructions,
                    // and `Running` for ever because nothing ever ends a
                    // reviewer's turn under this thread's id. Reported again
                    // 2026-09-08 on a Release build with exactly that face. So
                    // on Codex a finished thread holds the prompt too, and the
                    // thread's own rollout -- written before the hook, and the
                    // reason ``MonitoredTurnState/heldTurnStart`` can be settled at
                    // all -- promotes the user's own next turn on the sweep
                    // this hold wakes. Claude Code has no such reviewer and no
                    // such record, so its next prompt still opens its turn at
                    // once.
                    //
                    // Deliberately not conditioned on the turn sitting on an
                    // approval, which is the only window today's reviewer can
                    // appear in. What is being defended is the identity rule,
                    // not the one caller known to break it, and a narrower test
                    // would have to be widened again by the next nested agent
                    // Codex adds. The stamp is left alone for the same reason
                    // `reduceSubagentToolEvent` leaves it alone: this is not
                    // this turn's activity, so it must not fend off membership
                    // reconciliation.
                    guard current.sessionStatus == .completed,
                          !policy.settlesHeldTurnsFromRecord else {
                        var holder = current
                        holder.heldTurnStart = MonitoredTurnState.HeldTurnStart(
                            turnID: turnID,
                            startedAt: receivedAt,
                            promptPreview: TurnPreviewStore.normalized(event.prompt)
                        )
                        // The candidate is the newest; the refusal is every one
                        // of them. See ``MonitoredTurnState/heldTurnIDs``.
                        holder.heldTurnIDs.insert(turnID)
                        turnsByThreadID[threadID] = holder
                        return true
                    }
                    retiredTurnIDs = current.retiredTurnIDs
                    retiredTurnIDs.insert(current.turnID)
                }
            }
            turnsByThreadID[threadID] = MonitoredTurnState(
                threadID: threadID,
                turnID: turnID,
                sessionStatus: .running,
                pendingInput: nil,
                pendingApproval: nil,
                openToolUse: nil,
                startedAt: receivedAt,
                lastEventAt: receivedAt,
                retiredTurnIDs: retiredTurnIDs,
                promptPreview: TurnPreviewStore.normalized(event.prompt),
                assistantPreview: nil,
                runningSubagentIDs: runningSubagentIDs,
                lastSubagentBoundaryAt: lastSubagentBoundaryAt,
                subagentSlots: subagentSlots,
                threadHasNoTranscript: threadHasNoTranscript,
                heldTurnIDs: heldTurnIDs,
                workingDirectory: event.workingDirectory
            )
        case .approvalWaitInferred:
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .running,
                adoptContinuationWith: .running
            ) { state in
                // Codex asks about an ordinary tool -- a shell command, say -- by
                // announcing the call in `PreToolUse` and then firing this event
                // ~30ms later. This one names the tool but carries no
                // `tool_use_id`, so the wait is pinned to the call that is still
                // open for that tool: `PostToolUse` closes it on the same id, so
                // the wait ends when the human answers and no timer is involved.
                //
                // On its own this event still proves nothing -- an approval
                // pipeline that ran with no call open is not a human waiting --
                // so with nothing to pair against it stays a no-op rather than
                // opening a wait nothing could close.
                guard let openToolUse = state.openToolUse else { return }
                guard event.toolName == nil
                    || openToolUse.name == nil
                    || event.toolName == openToolUse.name else {
                    // Asking about some other call than the one still open: the
                    // pairing would be a guess, so decline to make it.
                    return
                }
                state.pendingApproval = PendingApproval(
                    toolUseID: openToolUse.id,
                    isInferred: true,
                    openedAt: receivedAt,
                    // A `PermissionRequest` that carried nothing readable must
                    // not blank a request the call that opened this wait
                    // already supplied -- and must not carry one across to a
                    // *different* call, which is why this is keyed on the id.
                    //
                    // Re-filed on *this* event's connection: the request may be
                    // the one the opening call supplied, but the connection an
                    // answer travels back on is the one that just arrived.
                    request: requestAsked(openToolUse.id) ?? (
                        state.pendingApproval?.toolUseID == openToolUse.id
                            ? state.pendingApproval?.request?
                                .answerable(on: event.answerHandle)
                            : nil
                    )
                )
                // **The connection belongs to the call, not to the slot it
                // opened.** An `AskUserQuestion` opens the *input* wait on its
                // own `PreToolUse` and then raises this event for the **same
                // call**, and this event is the only connection an answer can
                // travel back on. The row draws the input wait's request --
                // `transitioned(on:)` keeps the status at `Input needed` and
                // ``MonitoredTurnState/requestAwaitingAnAnswer`` follows the status
                // -- so leaving the ticket on the approval slot alone drew a
                // question in full and offered no way to answer it: §11's
                // reading form on a request a person could have settled here.
                //
                // Keyed on the id, which is what makes it safe: a borrowed
                // approval about some *other* call than the one that opened the
                // input wait carries its connection to that other call's slot
                // and never to this one.
                if state.pendingInputToolUseID == openToolUse.id,
                   let waiting = state.pendingInput {
                    state.pendingInput = PendingInput(
                        toolUseID: waiting.toolUseID,
                        openedAt: waiting.openedAt,
                        // Same two rules as the approval above: the newer
                        // request is the one held, and a request that did not
                        // arrive must not blank the one the opening call
                        // already supplied.
                        request: requestAsked(waiting.toolUseID)
                            ?? waiting.request?.answerable(on: event.answerHandle)
                    )
                }
                state.sessionStatus = state.sessionStatus
                    .transitioned(on: .approvalNeeded)
            }
        case .inputWaitOpened:
            announcedCallCount += 1
            guard let toolUseID = stableIdentifier(event.toolUseID) else {
                return false
            }
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .running,
                adoptContinuationWith: .running
            ) {
                Self.resolveInferredApproval(
                    &$0.pendingApproval,
                    activityOn: toolUseID,
                    whenInferring: infersDenials
                )
                $0.pendingInput = PendingInput(
                    toolUseID: toolUseID,
                    openedAt: receivedAt,
                    request: requestAsked(toolUseID)
                )
                $0.openToolUse = OpenToolUse(id: toolUseID, name: event.toolName)
                $0.sessionStatus = $0.sessionStatus.transitioned(on: .inputNeeded)
            }
        case .approvalWaitOpened:
            announcedCallCount += 1
            guard let toolUseID = stableIdentifier(event.toolUseID) else {
                return false
            }
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .running,
                adoptContinuationWith: .running
            ) {
                Self.resolveInferredApproval(
                    &$0.pendingApproval,
                    activityOn: toolUseID,
                    whenInferring: infersDenials
                )
                $0.pendingApproval = PendingApproval(
                    toolUseID: toolUseID,
                    isInferred: false,
                    openedAt: receivedAt,
                    request: requestAsked(toolUseID)
                )
                $0.openToolUse = OpenToolUse(id: toolUseID, name: event.toolName)
                $0.sessionStatus = $0.sessionStatus.transitioned(on: .approvalNeeded)
            }
        case .toolCallOpened, .questionAskedWithoutWaiting:
            // No state change on its own, but it records the open call so an
            // approval that carries no id of its own has something to pair
            // with. It also proves the definition runs.
            announcedCallCount += 1
            guard let toolUseID = stableIdentifier(event.toolUseID) else {
                return true
            }
            // Read before the mutation and deliberately **not** through
            // `requestAsked`, which files the request on this event's reply
            // connection: nothing here is answerable, so nothing here should
            // hold a ticket that says it might be. Only the words survive; see
            // ``MonitoredTurnState/questionAskedWithoutWaiting``.
            let questionAsked: String? = signal == .questionAskedWithoutWaiting
                ? TurnPreviewStore.normalized(
                    event.request?.identified(by: toolUseID).lastQuestionAsked
                )
                : nil
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                // An ordinary tool call is not evidence a turn began, so it
                // never creates one -- it only annotates a turn already known.
                createWith: nil,
                adoptContinuationWith: .running
            ) {
                Self.resolveInferredApproval(
                    &$0.pendingApproval,
                    activityOn: toolUseID,
                    whenInferring: infersDenials
                )
                $0.openToolUse = OpenToolUse(id: toolUseID, name: event.toolName)
                if $0.pendingInputToolUseID == nil, $0.pendingApproval == nil {
                    $0.sessionStatus = $0.sessionStatus.transitioned(on: .running)
                }
                // A question that could not be read leaves the last one it
                // could standing: the alternative is a row that loses the
                // question because the product added a field.
                if let questionAsked {
                    $0.questionAskedWithoutWaiting = questionAsked
                }
                // Recorded inside the mutation rather than beside it, so it is
                // set only where a turn this store holds was actually
                // annotated: a call announced against a retired turn, or one
                // arriving out of order, changes nothing and is worth no wake.
                didOpenToolCallInThisBatch = true
            }
        case .toolCallClosed:
            closedCallCount += 1
            guard let toolUseID = stableIdentifier(event.toolUseID) else {
                return true
            }
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: nil,
                adoptContinuationWith: .running
            ) {
                if $0.pendingInputToolUseID == toolUseID {
                    $0.pendingInput = nil
                }
                if $0.pendingApproval?.toolUseID == toolUseID {
                    $0.pendingApproval = nil
                } else {
                    Self.resolveInferredApproval(
                        &$0.pendingApproval,
                        activityOn: toolUseID,
                        whenInferring: infersDenials
                    )
                }
                if $0.openToolUse?.id == toolUseID {
                    $0.openToolUse = nil
                }
                // Only resume Running once no wait is still open: an unrelated
                // tool finishing must not clear a prompt the human has not
                // answered. The state machine only enters a wait from Running,
                // so at most one of these is ever set.
                if $0.pendingInputToolUseID != nil {
                    $0.sessionStatus = $0.sessionStatus.transitioned(on: .inputNeeded)
                } else if $0.pendingApproval != nil {
                    $0.sessionStatus = $0.sessionStatus.transitioned(on: .approvalNeeded)
                } else {
                    $0.sessionStatus = $0.sessionStatus.transitioned(on: .running)
                }
            }
        case .turnEnded:
            let assistantPreview = TurnPreviewStore.normalized(event.finalText)
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .completed,
                adoptContinuationWith: .completed
            ) {
                // The product intentionally exposes one terminal state. Stop,
                // completed, failed, and interrupted all converge to Completed.
                $0.sessionStatus = $0.sessionStatus.transitioned(on: .completed)
                $0.pendingInput = nil
                $0.pendingApproval = nil
                $0.assistantPreview = assistantPreview
                // And whether that terminal was the session finishing or the
                // session pausing, which only its own payload can say. Assigned
                // rather than or-ed: a turn that stops twice is answered by its
                // latest stop, and an empty list is that answer.
                $0.pausedForBackgroundWork = event.pausesForBackgroundWork
            }
        case .subagentStarted, .subagentStopped, .inert:
            // All three are answered above, before the turn identity gate.
            break
        }
        // What the product says about writing this thread down, restated by
        // every event that carries it. Written here rather than in each arm
        // because it is a fact about the thread and not about any of them, and
        // after the switch rather than before it because two of these arms
        // create the state it is written on.
        //
        // A prompt this thread held back never reaches this line -- that arm
        // returns from inside the switch -- which is right: the file a nested
        // agent's event names is the nested agent's.
        if let namesATranscript = event.namesATranscript {
            turnsByThreadID[threadID]?.threadHasNoTranscript = !namesATranscript
        }
        // A prompt that arrives after the turn opened, which fills a blank
        // title and may never replace one.
        //
        // **For the product that has to read its prompt off disk.** Antigravity
        // CLI puts the prompt in no payload; its translator reads it out of the
        // transcript the payload names, and that file is written by the product
        // moments before the boundary this app opens a Turn on. Every turn
        // measured had it in time, but the race is the product's to win and not
        // this app's, so the translator reads a second time at the turn's end
        // and the answer lands here.
        //
        // A no-op for both shipping products, which name their prompt on the
        // submission event that starts the turn and carry no prompt on any
        // other. Guarded on the turn's own id, because a blank title is not a
        // licence to take the *next* turn's words -- and on the title being
        // blank, because a turn that has already said what it is asking must
        // not have that rewritten by a later reading of a file the user has
        // gone on typing into.
        if let late = TurnPreviewStore.normalized(event.prompt),
           let turn = turnsByThreadID[threadID],
           turn.turnID == turnID,
           turn.promptPreview == nil {
            turnsByThreadID[threadID]?.promptPreview = late
        }
        return true
    }

    /// Records a subagent starting or stopping on a thread.
    ///
    /// **Deliberately not routed through
    /// ``mutateExactTurn(threadID:turnID:at:createWith:adoptContinuationWith:mutation:)``.**
    /// That function's whole job is exact turn identity, and these two events
    /// carry the *subagent's* turn id -- a value this reducer has never held
    /// and must never adopt. What they carry that is useful is `agent_id`,
    /// which pairs a start with its stop across a parent turn boundary.
    ///
    /// It attaches to a turn the thread already has and never creates one: a
    /// subagent is something a turn spawned, so a thread with no turn open has
    /// no row for the mark to appear on. The arrival stamp is deliberately not
    /// taken as `lastEventAt` -- this is not activity by the turn, so it must
    /// not move the stamp where it would let a subagent's chatter fend off the
    /// membership reconciliation that is the reducer's only bound. It is kept
    /// separately as ``MonitoredTurnState/lastSubagentBoundaryAt``, which one caller
    /// reads and nothing about turn identity does.
    ///
    /// **And that stamp moves only when the running set moves.** Both products
    /// send these events for agents this thread never had; see below for what
    /// stamping one of those cost.
    private func reduceSubagentBoundary(
        _ signal: MonitoringSignal,
        agentID: String,
        threadID: String,
        at receivedAt: Date
    ) {
        guard var turn = turnsByThreadID[threadID] else { return }
        // Whether the set the stamp below dates actually moved. **An agent that
        // never announced itself is not a subagent of this thread**, which is
        // the same rule ``MonitoredTurnState/subagentsAwaitingApprovalCount`` is
        // capped by -- and it has to hold for the stamp too, or a thread that
        // never had a subagent gets told when its last one stopped.
        let didChangeTheRunningSet: Bool
        switch signal {
        case .subagentStarted:
            didChangeTheRunningSet = turn.runningSubagentIDs.insert(agentID).inserted
        case .subagentStopped:
            didChangeTheRunningSet = turn.runningSubagentIDs.remove(agentID) != nil
            // The slot goes with it whether or not this thread ever counted the
            // agent, and this is the rule that guarantees nothing is ever left
            // waiting. A *refused* call closes with no event of its own on
            // either product -- Codex measured 2026-08-15 (67 seconds of
            // silence), Claude Code measured 2026-08-23, where
            // `PermissionDenied` turns out to fire only for the auto-mode
            // classifier's own refusals and never for a human's. After a
            // refusal this was the only event that arrived at all.
            turn.subagentSlots.removeValue(forKey: agentID)
        default:
            return
        }
        // **A stop that changed nothing dates nothing, and that is the whole
        // fix.** Claude Code runs internal forks *on a turn that has already
        // ended* -- the prompt suggestion, and the session recap (`/config` ->
        // `Session recap`). Each announces itself with no `SubagentStart` at
        // all and finishes with a `SubagentStop` carrying `agent_type: ""`, an
        // `agent_id` nothing ever named, and the **finished** turn's
        // `prompt_id`. Measured 2026-08-26 against CLI `2.1.246` in a pty with
        // every event registered: the suggestion at `Stop` + 3.79 s carrying
        // the suggested next prompt, and the recap at `Stop` + 183.74 s
        // carrying the summary -- the latter with no user input of any kind,
        // because it fires `min(180 s, 0.8 x prompt-cache TTL)` after the turn
        // ends while the terminal is blurred.
        //
        // Stamped unconditionally, each of those moved `terminalBoundaryAt`
        // minutes past the `Stop`, and that instant is exactly what
        // ``TerminalUnreadMembershipGate`` compares for `endedAgain`. So a
        // Completed row the user had read, and which the gate had hidden for
        // good, was un-hidden and re-judged against a boundary later than the
        // gesture that read it -- it came back unread and stayed until the user
        // went back to that terminal. Hiding is final for the Turn it was
        // decided for (CC-024); an agent this thread never had must not be able
        // to present the same Turn as a new one.
        //
        // Monotonic when it does move, like every other stamp here: a boundary
        // that arrived out of order must not wind a settling window backwards.
        if didChangeTheRunningSet {
            turn.lastSubagentBoundaryAt = max(
                turn.lastSubagentBoundaryAt ?? receivedAt,
                receivedAt
            )
        }
        turnsByThreadID[threadID] = turn
    }

    /// Records what one subagent has open, and what it is waiting for.
    ///
    /// **The same five signals the turn understands, in a slot of the
    /// subagent's own.** It exists because a subagent's approval is a fact the
    /// row has to report -- the product is sitting on a dialog -- and because
    /// routing it through the turn's single slot would let two streams close
    /// each other's waits.
    ///
    /// It borrows nothing from turn identity and gives nothing back to it. Like
    /// ``reduceSubagentBoundary(_:agentID:threadID:at:)`` it attaches to a turn
    /// the thread already has and never creates one, and it deliberately does
    /// not move `lastEventAt`: a subagent's chatter must not fend off the
    /// membership reconciliation that is this reducer's only bound. It does
    /// not move ``MonitoredTurnState/lastSubagentBoundaryAt`` either -- that stamp
    /// belongs to the two boundaries, because what it dates is when this
    /// thread stopped working, and a call in the middle of a subagent's life
    /// says nothing about that.
    ///
    /// - Parameter at: The arrival stamp, kept on the approval it opens and
    ///   nowhere else. It is what lets
    ///   ``endAnsweredApprovalWaits(_:)`` refuse a session reading
    ///   older than the dialog it would be closing; it moves neither of the
    ///   two stamps above.
    private func reduceSubagentToolEvent(
        _ signal: MonitoringSignal,
        agentID: String,
        threadID: String,
        event: MonitoringEvidence,
        at receivedAt: Date
    ) {
        guard var turn = turnsByThreadID[threadID] else { return }
        var slots = turn.subagentSlots[agentID] ?? AgentWaitSlots()

        // **Always infer, whichever product this is.** The turn-level rule asks
        // `reportsApprovalDenials`, and for a subagent the honest answer is
        // "no" on both products: measured 2026-08-23, a human's refusal
        // produces no event whatsoever on Claude Code (its `PermissionDenied`
        // is gated on the auto-mode classifier), which is the shape Codex was
        // already known to have. The reason Claude Code switched the inference
        // off does not reach here either: that was a `Stop` arriving ahead of
        // its own subagent's `PermissionRequest`, and those two now land in
        // different slots, so one stream's activity can no longer end the
        // other's wait.
        let infersDenials = policy.infersSubagentApprovalRefusalFromActivity

        switch signal {
        case .toolCallOpened, .inputWaitOpened, .approvalWaitOpened,
             .questionAskedWithoutWaiting:
            announcedCallCount += 1
            guard let toolUseID = stableIdentifier(event.toolUseID) else { break }
            Self.resolveInferredApproval(
                &slots.pendingApproval,
                activityOn: toolUseID,
                whenInferring: infersDenials
            )
            slots.openToolUse = OpenToolUse(id: toolUseID, name: event.toolName)
            // `.questionAskedWithoutWaiting` lands here as an ordinary call and
            // records nothing, for the same reason the wait below is tracked
            // and not drawn: whether a subagent's question reaches the user at
            // all has not been measured, and the row it would take over belongs
            // to the parent turn, which asked nobody anything.
            switch signal {
            case .inputWaitOpened:
                // Tracked so the pairing is right, and deliberately not drawn:
                // whether a subagent's question reaches the user at all has not
                // been measured, and a hint this product cannot stand behind is
                // worse than no hint.
                slots.pendingInput = PendingInput(
                    toolUseID: toolUseID,
                    openedAt: receivedAt,
                    request: event.request?.identified(by: toolUseID).answerable(on: event.answerHandle)
                )
            case .approvalWaitOpened:
                slots.pendingApproval = PendingApproval(
                    toolUseID: toolUseID,
                    isInferred: false,
                    openedAt: receivedAt,
                    request: event.request?.identified(by: toolUseID).answerable(on: event.answerHandle)
                )
            default:
                break
            }
        case .approvalWaitInferred:
            // The subagent's own open call, never the row's. Measured on both
            // products: `PermissionRequest` carries `tool_name` and no
            // `tool_use_id`, 20-30 ms after the `PreToolUse` that announced the
            // call it is asking about.
            guard let openToolUse = slots.openToolUse else { break }
            guard event.toolName == nil
                || openToolUse.name == nil
                || event.toolName == openToolUse.name else {
                break
            }
            slots.pendingApproval = PendingApproval(
                toolUseID: openToolUse.id,
                isInferred: true,
                openedAt: receivedAt,
                // Same rule as the turn's own borrowed approval: a request that
                // did not arrive must not blank one the call that opened this
                // wait already supplied, and must not travel to another call.
                request: event.request?.identified(by: openToolUse.id).answerable(on: event.answerHandle) ?? (
                    slots.pendingApproval?.toolUseID == openToolUse.id
                        ? slots.pendingApproval?.request?.answerable(on: event.answerHandle)
                        : nil
                )
            )
        case .toolCallClosed:
            closedCallCount += 1
            guard let toolUseID = stableIdentifier(event.toolUseID) else { break }
            if slots.pendingInputToolUseID == toolUseID {
                slots.pendingInput = nil
            }
            if slots.pendingApproval?.toolUseID == toolUseID {
                slots.pendingApproval = nil
            } else {
                Self.resolveInferredApproval(
                    &slots.pendingApproval,
                    activityOn: toolUseID,
                    whenInferring: infersDenials
                )
            }
            if slots.openToolUse?.id == toolUseID {
                slots.openToolUse = nil
            }
        case .turnStarted, .turnEnded, .subagentStarted, .subagentStopped, .inert:
            // A subagent's own turn boundary names nothing this reducer holds,
            // and the two subagent boundaries answered before this was reached.
            return
        }

        if slots.isEmpty {
            turn.subagentSlots.removeValue(forKey: agentID)
        } else {
            turn.subagentSlots[agentID] = slots
        }
        turnsByThreadID[threadID] = turn
    }

    /// Ends an inferred approval as soon as another call shows any activity.
    ///
    /// An approved call closes with its own `PostToolUse`, but a *denied* one is
    /// never closed at all -- measured 2026-08-15: the prompt was followed by 67
    /// seconds of silence and then the turn's `Stop`, with no event whatsoever
    /// for the denied call. `Stop` alone would therefore be the only way out,
    /// which leaves the row claiming the user is still being asked for the whole
    /// rest of a turn that carried on working after the denial.
    ///
    /// Activity on a *different* call is proof the human has answered, because
    /// Codex emits nothing at all while a turn is genuinely blocked on the
    /// prompt. An approval that owns its `tool_use_id` needs none of this and is
    /// left strictly alone: it always gets its closing event.
    /// Takes the wait itself rather than the turn, because a subagent's slot
    /// needs exactly this rule and has no turn of its own to pass.
    nonisolated private static func resolveInferredApproval(
        _ pendingApproval: inout PendingApproval?,
        activityOn toolUseID: String,
        whenInferring infersDenials: Bool
    ) {
        guard infersDenials,
              let pending = pendingApproval,
              pending.isInferred,
              pending.toolUseID != toolUseID else {
            return
        }
        pendingApproval = nil
    }

    private func mutateExactTurn(
        threadID: String,
        turnID: String,
        at date: Date,
        createWith sessionStatus: SessionStatus?,
        adoptContinuationWith continuationStatus: SessionStatus?,
        mutation: (inout MonitoredTurnState) -> Void
    ) {
        var state: MonitoredTurnState
        if let current = turnsByThreadID[threadID] {
            if current.turnID == turnID {
                guard date >= current.lastEventAt else { return }
                state = current
            } else {
                // **A turn this thread held back may never be continued into.**
                // Everything else about an unknown turn id stays as it was: an
                // event naming one is still taken for this thread's own turn,
                // which is what recovers a thread whose `UserPromptSubmit` this
                // app never saw -- it launched mid-turn, or the reducer was
                // emptied under it. What that recovery cannot be allowed to do
                // is finish the job a held prompt started: the prompt is
                // refused at the door and then the same turn's next event walks
                // in through the window. See ``MonitoredTurnState/heldTurnStart``
                // for the reviewer that did exactly this.
                guard let continuationStatus,
                      date > current.lastEventAt,
                      !current.retiredTurnIDs.contains(turnID),
                      !(policy.settlesHeldTurnsFromRecord
                        && current.heldTurnIDs.contains(turnID)) else {
                    return
                }
                var retiredTurnIDs = current.retiredTurnIDs
                retiredTurnIDs.insert(current.turnID)
                // On the product whose held prompts are settled by an event
                // rather than by a record, this is that event, so the start and
                // text it was holding come with it. On the other, a held id
                // never reaches this line at all and this is always nil.
                let redeemed = current.heldTurnStart?.turnID == turnID
                    ? current.heldTurnStart
                    : nil
                var heldTurnIDs = current.heldTurnIDs
                heldTurnIDs.remove(turnID)
                state = MonitoredTurnState(
                    threadID: threadID,
                    turnID: turnID,
                    sessionStatus: continuationStatus,
                    pendingInput: nil,
                    pendingApproval: nil,
                    openToolUse: nil,
                    startedAt: redeemed?.startedAt ?? current.startedAt,
                    lastEventAt: date,
                    retiredTurnIDs: retiredTurnIDs,
                    promptPreview: redeemed?.promptPreview ?? current.promptPreview,
                    assistantPreview: nil,
                    runningSubagentIDs: current.runningSubagentIDs,
                    lastSubagentBoundaryAt: current.lastSubagentBoundaryAt,
                    subagentSlots: current.subagentSlots,
                    threadHasNoTranscript: current.threadHasNoTranscript,
                    heldTurnIDs: heldTurnIDs,
                    workingDirectory: current.workingDirectory
                )
            }
        } else {
            guard let sessionStatus else { return }
            state = MonitoredTurnState(
                threadID: threadID,
                turnID: turnID,
                sessionStatus: sessionStatus,
                pendingInput: nil,
                pendingApproval: nil,
                openToolUse: nil,
                startedAt: date,
                lastEventAt: date,
                retiredTurnIDs: [],
                promptPreview: nil,
                assistantPreview: nil
            )
        }
        mutation(&state)
        state.lastEventAt = max(state.lastEventAt, date)
        turnsByThreadID[threadID] = state
    }

    private func stableIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    // MARK: - What is drawn, and when it is worth saying so

    /// Everything a row draws that this store is the source of.
    ///
    /// Turns only. A streamed delta is not here and is not meant to be: it does
    /// not reach this actor at all, and putting it on the reducer's mailbox at
    /// 3.4 events a second would be the expensive half of the old design
    /// (`AGENTS.md` §7, and the measurement in `system-architecture.md` §6).
    /// The text still has to reach the panel, so it carries an edge of its own,
    /// raised where it is folded and bounded by the head's cap; see
    /// ``TurnPreviewStore/fold``.
    ///
    /// A tool call opening is likewise absent and likewise woken for, on the
    /// one product whose row text is read from somewhere else entirely; see
    /// ``MonitoringReductionPolicy/wakesOnToolCallOpened``.
    private func renderedProjection() -> [String] {
        turnsByThreadID.values
            .map { turn in
                [
                    turn.threadID,
                    turn.turnID,
                    String(describing: turn.sessionStatus),
                    turn.promptPreview ?? "",
                    turn.assistantPreview ?? "",
                    // The row draws how many, so a second one starting is a
                    // change the panel has to be woken for.
                    String(turn.runningSubagentIDs.count),
                    // And whether one of them is waiting on a human, which
                    // changes the collapsed summary as well as the row.
                    String(turn.subagentsAwaitingApproval),
                    // A finished turn that is only paused reads as Running in
                    // the collapsed summary, so the surface has to be woken
                    // when the last subagent stops and this is what is left
                    // holding it there.
                    String(turn.pausedForBackgroundWork),
                    // The request the row can open, **identified rather than
                    // spelled out**: its id, its form, and whether a connection
                    // is being held for it say everything a redraw needs, and a
                    // 54 KiB plan is not string-compared once per arriving
                    // event to discover that it has not changed.
                    //
                    // **Answerability is a term because it moves inside one
                    // wait.** The premise this used to rest on -- one
                    // `tool_use_id` never carries two requests, so the id fixes
                    // it -- is true of the *body* and false of the answer: an
                    // `AskUserQuestion` opens its input wait on a `PreToolUse`
                    // and becomes answerable ~25 ms later, when the
                    // `PermissionRequest` for the same call arrives with the
                    // connection. Without this term the row goes on drawing
                    // `Answer in Claude Code` over a question it could settle.
                    //
                    // It is also the only term that catches one case: with two
                    // subagents waiting, answering the first moves the request
                    // the row draws while `subagentsAwaitingApproval` -- a Bool
                    // -- stands still.
                    turn.requestAwaitingAnAnswer
                        .map {
                            "\($0.id)\u{2}\($0.form.name)\u{2}\($0.canBeAnswered)"
                        } ?? "",
                    // **Not drawn, and here so that it is settled.** A held
                    // prompt changes nothing a row shows, but the sweep that
                    // can redeem it listens on this same edge, and the record
                    // it needs is on disk before the hook that carried the
                    // prompt (``MonitoredTurnState/heldTurnStart``). Without this
                    // term the user's own next turn on a finished thread waited
                    // for the next event, or the interval, to be given its row.
                    turn.heldTurnStart?.turnID ?? ""
                ].joined(separator: "\u{1}")
            }
            .sorted()
    }

    /// Returns whether it signalled.
    @discardableResult
    private func signalIfProjectionChanged() -> Bool {
        let current = renderedProjection()
        guard current != signalledProjection else { return false }
        signalledProjection = current
        changes.signal()
        return true
    }

    private func snapshot(didConsumeEvents: Bool = false) -> MonitoringStateSnapshot {
        let statistics = MonitoringStatistics(
            hasObservedLiveEvidence: hasObservedLiveEvent,
            unplacedEvidenceCount: unplaceableEventCount,
            announcedCallCount: announcedCallCount,
            closedCallCount: closedCallCount
        )
        return MonitoringStateSnapshot(
            hasObservedEvent: hasObservedLiveEvent || (boundary?.hasObservedEvidence ?? false),
            hasObservedLiveEvent: hasObservedLiveEvent,
            turns: turnsByThreadID.values.sorted { $0.startedAt > $1.startedAt },
            didConsumeEvents: didConsumeEvents,
            diagnostic: boundary?.diagnostic(for: statistics)
                ?? (unplaceableEventCount > 0
                    ? "Ignored \(unplaceableEventCount) observations with no stable identity, or of an unsupported kind."
                    : nil)
        )
    }
}
