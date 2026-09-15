import Foundation

/// The single Turn reducer and ordered live-evidence entry point; native decoding and transport
/// live in boundary adapters.
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

    /// Submit synchronously on the source's serial delivery queue; tasks only kick a drain and
    /// never establish order. No historical replay.
    @discardableResult
    nonisolated func submit(_ evidence: MonitoringEvidence, in epoch: MonitoringEpoch) -> Bool {
        guard inbox.append(evidence, in: epoch) else { return false }
        Task { await self.drainInbox() }
        return true
    }

    /// Bounded content updates bypass the actor. They cannot open or change a Turn.
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
        // An expired window is not an event, so it is checked on the refresh.
        withdrawExpiredAnswerHandles()
        signalIfProjectionChanged()
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
            var changed = turn.waits.withdraw(handle)
            for (agentID, var slots) in turn.subagentSlots where slots.withdraw(handle) {
                turn.subagentSlots[agentID] = slots
                changed = true
            }
            if changed { turnsByThreadID[threadID] = turn }
        }
    }

    /// Withdraws expired handles from their requests; the requests stay readable and say `Read`.
    func withdrawExpiredAnswerHandles() {
        guard let boundary else { return }
        for handle in boundary.expiredAnswerHandles(at: clock.now()) {
            withdrawAnswerHandle(handle)
        }
    }

    /// When the next held answer window runs out; nil while none is held.
    nonisolated func nextAnswerExpiry() -> Date? {
        boundary?.nextAnswerHandleExpiry()
    }

    // MARK: - Evidence that is not a hook event

    /// Ends the turns of sessions that report they have stopped working.
    ///
    /// A user interrupt fires no hook: 2.1.235 has no cancel event and every abort path returns
    /// before `Stop`, so `Esc` leaves a row *Running* or *Approval needed* (CC-019, #38). No
    /// timeout (`AGENTS.md` §6.2); the evidence is the session no longer saying it is busy.
    ///
    /// - Parameter observations: Session id to the moment its reading *began*. A reading that
    ///   began before the turn's last event is ignored, which makes a cached list safe to act on.
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
    /// Covers desktop-hosted sessions, which publish no working status (CC-022, #41) but leave
    /// an abort record in their transcript. It carries the turn's `prompt_id`, so an observation
    /// naming a turn the reducer is not holding does nothing. Neither route may open a turn.
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
    /// The only redemption for a held prompt (``MonitoredTurnState/heldTurnStart``): Codex writes
    /// each Turn's `turn_context` into its own thread's rollout and a reviewer's elsewhere, so this
    /// thread's record naming the Turn is the proof. It only promotes a start already held, as
    /// `Running` with its own start and text.
    func adoptTurnsOnRecord(_ records: [TurnOnRecord]) -> MonitoringStateSnapshot {
        for record in records {
            guard let current = turnsByThreadID[record.threadID],
                  current.turnID != record.turnID,
                  let held = current.heldTurnStart,
                  held.turnID == record.turnID,
                  !current.retiredTurnIDs.contains(record.turnID),
                  // Same monotonic rule as every other route.
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
                // A subagent outlives the Turn that spawned it.
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
    /// - Parameter named: The turn the evidence names; nil applies to whichever turn is open.
    /// - Parameter orphansSubagents: See ``TurnInterruption/orphansSubagents``.
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
        turn.waits.clearAll()
        if orphansSubagents, !turn.runningSubagentIDs.isEmpty {
            turn.runningSubagentIDs.removeAll()
            // A dialogue raised by a subagent of a stopped turn goes too, like `pendingApproval`.
            turn.subagentSlots.removeAll()
            // The set moved, so its stamp moves (``MonitoredTurnState/lastSubagentBoundaryAt``), to the
            // same instant as `lastEventAt`, where the settling window measures from.
            turn.lastSubagentBoundaryAt = moment
        }
        // So an event older than this evidence cannot reopen what it ended.
        turn.lastEventAt = moment
        turnsByThreadID[threadID] = turn
    }

    /// Ends the approval waits a human has been shown to have answered.
    ///
    /// No hook fires when a person approves (CLI 2.1.241, all 31 events, 2026-08-23), and
    /// `PostToolUse` lands when the tool finishes. Both hosts feed this one rule:
    ///
    /// - Terminal-hosted: `claude agents --json` reads `waiting` while any dialog is up. Only
    ///   `busy` counts, never "not `waiting`": `Esc` reaches `idle` with a dialog drawn (CC-019).
    /// - Desktop-hosted: no status (CC-022, #41); see ``ClaudeDesktopPermissionLogReader``.
    ///
    /// It only ends waits (the turn's and every subagent's), each held to its own stamp.
    ///
    /// - Parameter observations: Thread id to the instant no dialog was open: when the session
    ///   command **started running**, or the instant Desktop stamped on the answer line.
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
    /// Does not move `lastEventAt`, the only bound against a row fending off membership
    /// reconciliation. Unlike ``endOpenTurn(ofThread:named:at:)`` nothing here can be undone by a
    /// later event: a later `PermissionRequest` is a new dialog.
    private func endApprovalWaits(ofThread threadID: String, at moment: Date) {
        guard var turn = turnsByThreadID[threadID] else { return }
        var changed = false

        if turn.waits.endApprovals(before: moment) {
            changed = true
            turn.deriveStatus()
        }

        for (agentID, var slots) in turn.subagentSlots where slots.endApprovals(before: moment) {
            changed = true
            if slots.isEmpty {
                turn.subagentSlots.removeValue(forKey: agentID)
            } else {
                turn.subagentSlots[agentID] = slots
            }
        }

        guard changed else { return }
        turnsByThreadID[threadID] = turn
    }

    /// Forgets the threads a listing of what exists no longer names.
    ///
    /// The reducer's only bound on threads; both products call it from the refresh that prunes
    /// their previews and caches against the same list.
    ///
    /// - Parameters:
    ///   - listedThreadIDs: Every thread the reading named.
    ///   - snapshotStartedAt: When that reading *began*. A reading that began before a Turn's
    ///     last event is not evidence against it.
    func removeThreads(
        notIn listedThreadIDs: Set<String>,
        snapshotStartedAt: Date
    ) -> MonitoringStateSnapshot {
        let now = clock.now()
        turnsByThreadID = turnsByThreadID.filter {
            if listedThreadIDs.contains($0.key) {
                return true
            }
            if snapshotStartedAt < $0.value.lastEventAt {
                return true
            }
            // A prompt hook can arrive before the record that lists its thread (Codex's state DB, or a
            // desktop session's `~/.claude/sessions` entry), so a new turn gets a grace period.
            return now.timeIntervalSince($0.value.startedAt)
                < timing.newTurnReconciliationGrace
        }
        signalIfProjectionChanged()
        return snapshot()
    }

    /// Ends every Turn this reducer is holding, and keeps everything else.
    ///
    /// For a caller that knows the producing process is gone: nothing else would ever end such a
    /// Turn (CR-Fable-007). Observation flags stay.
    ///
    /// - Parameter didConsumeEvents: Carried through from the drain this call follows.
    @discardableResult
    func discardTurns(didConsumeEvents: Bool = false) -> MonitoringStateSnapshot {
        guard !turnsByThreadID.isEmpty else {
            return snapshot(didConsumeEvents: didConsumeEvents)
        }
        turnsByThreadID.removeAll()
        signalIfProjectionChanged()
        return snapshot(didConsumeEvents: didConsumeEvents)
    }

    /// Native execution ownership, unlike a metadata listing, needs no new-Turn grace.
    /// Called after draining the inbox and reading all currently live owners.
    func retainOwnedThreads(_ threadIDs: Set<String>, didConsumeEvents: Bool) -> MonitoringStateSnapshot {
        turnsByThreadID = turnsByThreadID.filter { threadIDs.contains($0.key) }
        reconcileAnswerHandles()
        signalIfProjectionChanged()
        return snapshot(didConsumeEvents: didConsumeEvents)
    }

    /// A channel restart ends live observation without revoking facts about
    /// unchanged native setup. Removal/repair also resets boundary bookkeeping.
    func resetIntegrationObservation(clearTurns: Bool, preserveBoundaryObservation: Bool = false) {
        hasObservedLiveEvent = false
        didReduceSinceLastReport = false
        unplaceableEventCount = 0
        let dropped = inbox.reset { previews.removeAll() }
        if !dropped.isEmpty { boundary?.didDiscard(dropped) }
        if !preserveBoundaryObservation { boundary?.reset() }
        if clearTurns { turnsByThreadID.removeAll() }
        reconcileAnswerHandles()
        signalledProjection = renderedProjection()
    }

    // MARK: - The reducer

    private func reduce(_ event: MonitoringEvidence) -> Bool {
        guard let threadID = stableIdentifier(event.threadID),
              let signal = event.signal else { return false }

        if signal == .inert {
            // Needs no turn, so it answers before the identity gate.
            return true
        }

        // Subagent signals name no turn, so they answer before the turn identity gate.
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

        // A subagent's event goes to its own slot, never through the turn: Codex stamps its hooks
        // with the parent's `session_id` but its own `turn_id`, and adopting one retired the real
        // turn. See `docs/technical-explorations/subagent-row-consistency/` §6.1 and §6.3.
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
        // The product's own request id where it has one, else the call's.
        let requestIdentity: (String?) -> String? = { callID in
            self.stableIdentifier(event.requestID) ?? callID
        }
        let requestAsked: (String?) -> AgentRequest? = { callID in
            guard let id = requestIdentity(callID) else { return nil }
            let waits = self.turnsByThreadID[threadID]?.waits
            let previous = waits?.inputs.first { $0.requestID == id }?.request
                ?? waits?.approvals.first { $0.requestID == id }?.request
            return event.request?.identified(by: id).answerable(by: event).scoped(
                AgentRequest.Identity(epoch: self.observationEpoch, threadID: threadID,
                    turnID: event.turnID, producerID: nil, requestID: id, nativeRevision: event.requestRevision),
                preserving: previous)
        }

        switch signal {
        case .turnStarted:
            var retiredTurnIDs = Set<String>()
            // A subagent is not ended by the user typing again.
            let runningSubagentIDs = turnsByThreadID[threadID]?.runningSubagentIDs ?? []
            let lastSubagentBoundaryAt = turnsByThreadID[threadID]?
                .lastSubagentBoundaryAt
            // Nor is a dialog one of them is sitting on.
            let subagentSlots = turnsByThreadID[threadID]?.subagentSlots ?? [:]
            // A turn once held back stays held back.
            let heldTurnIDs = turnsByThreadID[threadID]?.heldTurnIDs ?? []
            // Restated from this event by the tail of this reducer.
            let threadHasNoTranscript = turnsByThreadID[threadID]?
                .threadHasNoTranscript ?? false
            if let current = turnsByThreadID[threadID] {
                if current.turnID == turnID {
                    guard receivedAt >= current.lastEventAt else { return true }
                    retiredTurnIDs = current.retiredTurnIDs
                } else {
                    guard receivedAt > current.lastEventAt,
                          !current.retiredTurnIDs.contains(turnID),
                          // A held turn may never start one: the set refuses a
                          // reviewer's repeated assessment.
                          !(policy.settlesHeldTurnsFromRecord
                            && current.heldTurnIDs.contains(turnID)) else {
                        return true
                    }
                    // One thread, one open turn: Codex Desktop queues follow-ups, so a
                    // prompt *during* a turn is something else under this identity and
                    // is held (``MonitoredTurnState/heldTurnStart``). On Codex a completed
                    // thread holds it too: a reviewer's prompt can land after `Stop`
                    // (reported 2026-09-08); the rollout promotes the real next turn.
                    // Claude Code opens its turn at once. The stamp is not moved.
                    guard current.sessionStatus == .completed,
                          !policy.settlesHeldTurnsFromRecord else {
                        var holder = current
                        holder.heldTurnStart = MonitoredTurnState.HeldTurnStart(
                            turnID: turnID,
                            startedAt: receivedAt,
                            promptPreview: TurnPreviewStore.normalized(event.prompt)
                        )
                        // The candidate is the newest; every one is refused.
                        // See ``MonitoredTurnState/heldTurnIDs``.
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
                // Codex announces a call in `PreToolUse` and fires this ~30ms later with the tool name but
                // no `tool_use_id`, so the wait pins to the open call for that tool and `PostToolUse` closes
                // it. With no call, or an ambiguous one, to pair against it is a no-op
                // (``ProducerWaits/callToBorrow(forTool:)``).
                guard let openToolUse = state.waits.callToBorrow(forTool: event.toolName) else { return }
                state.waits.open(PendingApproval(
                    toolUseID: openToolUse.id,
                    isInferred: true,
                    openedAt: receivedAt,
                    // An unreadable request must not blank the opening call's, nor carry
                    // one to a different call. Re-filed on this event's connection, which
                    // is the one an answer travels back on.
                    request: requestAsked(openToolUse.id)
                        ?? state.waits.approvals.first { $0.toolUseID == openToolUse.id }?
                            .request?.answerable(by: event),
                    requestID: requestIdentity(openToolUse.id), nativeRevision: event.requestRevision
                ))
                // The connection belongs to the call, not the slot: `AskUserQuestion` opens the input wait
                // and then raises this for the same call, and the row draws the input wait's request
                // (``MonitoredTurnState/requestsAwaitingAnAnswer``). Keyed on the id.
                if let waiting = state.waits.inputs.first(where: { $0.toolUseID == openToolUse.id }) {
                    state.waits.open(PendingInput(
                        toolUseID: waiting.toolUseID,
                        openedAt: waiting.openedAt,
                        // Same two rules as the approval above.
                        request: requestAsked(waiting.toolUseID)
                            ?? waiting.request?.answerable(by: event),
                        requestID: waiting.requestID
                    ))
                }
                state.deriveStatus()
            }
        case .inputWaitOpened:
            let toolUseID = stableIdentifier(event.toolUseID)
            guard stableIdentifier(event.requestID) != nil || toolUseID != nil else { return false }
            if toolUseID != nil { announcedCallCount += 1 }
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .running,
                adoptContinuationWith: .running
            ) {
                if let toolUseID { $0.waits.resolveInferredApprovals(exceptCall: toolUseID, whenInferring: infersDenials) }
                $0.waits.open(PendingInput(
                    toolUseID: toolUseID,
                    openedAt: receivedAt,
                    request: requestAsked(toolUseID),
                    requestID: requestIdentity(toolUseID), nativeRevision: event.requestRevision
                ))
                if let toolUseID { $0.waits.announce(OpenToolUse(id: toolUseID, name: event.toolName)) }
                $0.deriveStatus()
            }
        case .approvalWaitOpened:
            let toolUseID = stableIdentifier(event.toolUseID)
            guard stableIdentifier(event.requestID) != nil || toolUseID != nil else { return false }
            if toolUseID != nil { announcedCallCount += 1 }
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .running,
                adoptContinuationWith: .running
            ) {
                if let toolUseID { $0.waits.resolveInferredApprovals(exceptCall: toolUseID, whenInferring: infersDenials) }
                $0.waits.open(PendingApproval(
                    toolUseID: toolUseID,
                    isInferred: false,
                    openedAt: receivedAt,
                    request: requestAsked(toolUseID),
                    requestID: requestIdentity(toolUseID), nativeRevision: event.requestRevision
                ))
                if let toolUseID { $0.waits.announce(OpenToolUse(id: toolUseID, name: event.toolName)) }
                $0.deriveStatus()
            }
        case .toolCallOpened, .questionAskedWithoutWaiting:
            // Records the open call so an id-less approval can pair with it.
            announcedCallCount += 1
            guard let toolUseID = stableIdentifier(event.toolUseID) else {
                return true
            }
            // Not through `requestAsked`: nothing here is answerable, so no reply ticket. See
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
                // A tool call never creates a turn.
                createWith: nil,
                adoptContinuationWith: .running
            ) {
                $0.waits.resolveInferredApprovals(exceptCall: toolUseID, whenInferring: infersDenials)
                $0.waits.announce(OpenToolUse(id: toolUseID, name: event.toolName))
                $0.deriveStatus()
                // An unreadable question leaves the last readable one standing.
                if let questionAsked {
                    $0.questionAskedWithoutWaiting = questionAsked
                }
                // Set inside the mutation, so a call against a retired or out-of-order turn is worth no wake.
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
                // Resolving one request cannot clear another; an inferred approval about another call ends
                // on this activity only where refusals are inferred.
                $0.waits.closeCall(toolUseID)
                $0.waits.resolveInferredApprovals(exceptCall: toolUseID, whenInferring: infersDenials)
                $0.deriveStatus()
            }
        case .requestResolved:
            // Ends this one request, by its own identity.
            guard let requestID = stableIdentifier(event.requestID ?? event.toolUseID) else {
                return false
            }
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: nil,
                adoptContinuationWith: .running
            ) {
                $0.waits.resolve(requestID: requestID, revision: event.requestRevision)
                $0.deriveStatus()
            }
        case .turnInterrupted:
            endOpenTurn(ofThread: threadID, named: turnID, at: receivedAt)
        case .turnEnded:
            let assistantPreview = TurnPreviewStore.normalized(event.finalText)
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .completed,
                adoptContinuationWith: .completed
            ) {
                // Stop, completed, failed, and interrupted all converge to Completed.
                $0.sessionStatus = $0.sessionStatus.transitioned(on: .completed)
                $0.waits.clearWaits()
                $0.assistantPreview = assistantPreview
                // Assigned, not or-ed: the latest stop answers, and an empty list is that answer.
                $0.pausedForBackgroundWork = event.pausesForBackgroundWork
            }
        case .subagentStarted, .subagentStopped, .inert:
            break
        }
        // After the switch because two arms create the state. A held prompt returns before this: the
        // transcript it names is the nested agent's.
        if let namesATranscript = event.namesATranscript {
            turnsByThreadID[threadID]?.threadHasNoTranscript = !namesATranscript
        }
        // A late prompt fills a blank title, never replaces one: Antigravity CLI's translator re-reads
        // the prompt from the transcript at turn end. Guarded on the turn's own id.
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
    /// Not via `mutateExactTurn`: these carry the subagent's turn id, which must never be adopted;
    /// `agent_id` pairs start and stop. Never creates a turn or moves `lastEventAt`.
    private func reduceSubagentBoundary(
        _ signal: MonitoringSignal,
        agentID: String,
        threadID: String,
        at receivedAt: Date
    ) {
        guard var turn = turnsByThreadID[threadID] else { return }
        // An agent that never announced itself is not this thread's subagent, so it moves no stamp.
        let didChangeTheRunningSet: Bool
        switch signal {
        case .subagentStarted:
            didChangeTheRunningSet = turn.runningSubagentIDs.insert(agentID).inserted
        case .subagentStopped:
            didChangeTheRunningSet = turn.runningSubagentIDs.remove(agentID) != nil
            // The slot always goes: a refused call closes with no event on either product (Codex
            // 2026-08-15; Claude Code 2026-08-23, `PermissionDenied` is classifier-only).
            turn.subagentSlots.removeValue(forKey: agentID)
        default:
            return
        }
        // A stop that changed nothing dates nothing. Claude Code's internal forks (prompt suggestion,
        // session recap at `Stop` + 183.74 s) send an unannounced `SubagentStop` on the finished turn
        // (CLI `2.1.246`); stamping it made ``TerminalUnreadMembershipGate`` un-hide a read row
        // (CC-024). Monotonic when it does move.
        if didChangeTheRunningSet {
            turn.lastSubagentBoundaryAt = max(
                turn.lastSubagentBoundaryAt ?? receivedAt,
                receivedAt
            )
        }
        turnsByThreadID[threadID] = turn
    }

    /// Records what one subagent has open, and what it is waiting for, in its own slot so two
    /// streams cannot close each other's waits. Never creates a turn; moves no stamp.
    ///
    /// - Parameter at: Kept only on the approval it opens, for
    ///   ``endAnsweredApprovalWaits(_:)``.
    private func reduceSubagentToolEvent(
        _ signal: MonitoringSignal,
        agentID: String,
        threadID: String,
        event: MonitoringEvidence,
        at receivedAt: Date
    ) {
        guard var turn = turnsByThreadID[threadID] else { return }
        var slots = turn.subagentSlots[agentID] ?? ProducerWaits()
        let requestIdentity: (String?) -> String? = { callID in
            self.stableIdentifier(event.requestID) ?? callID
        }
        let requestAsked: (String?) -> AgentRequest? = { callID in
            guard let id = requestIdentity(callID) else { return nil }
            let previous = slots.inputs.first { $0.requestID == id }?.request
                ?? slots.approvals.first { $0.requestID == id }?.request
            return event.request?.identified(by: id).answerable(by: event).scoped(
                AgentRequest.Identity(epoch: self.observationEpoch, threadID: threadID,
                    turnID: event.turnID, producerID: agentID, requestID: id, nativeRevision: event.requestRevision),
                preserving: previous)
        }

        // Always infer: a human's refusal of a subagent's call produces no event on either product
        // (2026-08-23), and Claude Code's turn-level opt-out does not apply across slots.
        let infersDenials = policy.infersSubagentApprovalRefusalFromActivity

        switch signal {
        case .toolCallOpened, .inputWaitOpened, .approvalWaitOpened,
             .questionAskedWithoutWaiting:
            let toolUseID = stableIdentifier(event.toolUseID)
            let isWait = signal == .inputWaitOpened || signal == .approvalWaitOpened
            guard toolUseID != nil || (isWait && stableIdentifier(event.requestID) != nil) else { break }
            if let toolUseID {
                announcedCallCount += 1
                slots.resolveInferredApprovals(exceptCall: toolUseID, whenInferring: infersDenials)
                slots.announce(OpenToolUse(id: toolUseID, name: event.toolName))
            }
            // Records nothing: whether a subagent's question reaches the user is unmeasured.
            switch signal {
            case .inputWaitOpened:
                // Tracked for pairing, not drawn (see ``MonitoredTurnState/requestsAwaitingAnAnswer``).
                slots.open(PendingInput(
                    toolUseID: toolUseID,
                    openedAt: receivedAt,
                    request: requestAsked(toolUseID),
                    requestID: requestIdentity(toolUseID), nativeRevision: event.requestRevision
                ))
            case .approvalWaitOpened:
                slots.open(PendingApproval(
                    toolUseID: toolUseID,
                    isInferred: false,
                    openedAt: receivedAt,
                    request: requestAsked(toolUseID),
                    requestID: requestIdentity(toolUseID), nativeRevision: event.requestRevision
                ))
            default:
                break
            }
        case .approvalWaitInferred:
            // The subagent's own open call; ambiguity means no pairing.
            guard let openToolUse = slots.callToBorrow(forTool: event.toolName) else { break }
            slots.open(PendingApproval(
                toolUseID: openToolUse.id,
                isInferred: true,
                openedAt: receivedAt,
                // Same rule as the turn's own borrowed approval.
                request: requestAsked(openToolUse.id)
                    ?? slots.approvals.first { $0.toolUseID == openToolUse.id }?
                        .request?.answerable(by: event),
                requestID: requestIdentity(openToolUse.id), nativeRevision: event.requestRevision
            ))
        case .toolCallClosed:
            closedCallCount += 1
            guard let toolUseID = stableIdentifier(event.toolUseID) else { break }
            slots.closeCall(toolUseID)
            slots.resolveInferredApprovals(exceptCall: toolUseID, whenInferring: infersDenials)
        case .requestResolved:
            guard let requestID = stableIdentifier(event.requestID ?? event.toolUseID) else { break }
            slots.resolve(requestID: requestID, revision: event.requestRevision)
        case .turnStarted, .turnEnded, .turnInterrupted, .subagentStarted, .subagentStopped, .inert:
            return
        }

        if slots.isEmpty {
            turn.subagentSlots.removeValue(forKey: agentID)
        } else {
            turn.subagentSlots[agentID] = slots
        }
        turnsByThreadID[threadID] = turn
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
                // A held turn may never be continued into, though an unknown turn id otherwise is
                // (``MonitoredTurnState/heldTurnStart``).
                guard let continuationStatus,
                      date > current.lastEventAt,
                      !current.retiredTurnIDs.contains(turnID),
                      !(policy.settlesHeldTurnsFromRecord
                        && current.heldTurnIDs.contains(turnID)) else {
                    return
                }
                var retiredTurnIDs = current.retiredTurnIDs
                retiredTurnIDs.insert(current.turnID)
                // Where held prompts settle by event, this is that event and brings the held start and text;
                // otherwise a held id never reaches here and this is nil.
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

    /// Everything a row draws that this store is the source of. Streamed deltas bypass this actor
    /// (``TurnPreviewStore/fold``, `AGENTS.md` §7); tool calls opening wake via
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
                    String(turn.runningSubagentIDs.count),
                    // Changes the collapsed summary as well as the row.
                    String(turn.subagentsAwaitingApproval),
                    // A paused finished turn reads as Running in the collapsed
                    // summary, so this wakes when the last subagent stops.
                    String(turn.pausedForBackgroundWork),
                    // Identified, not spelled out: a 54 KiB plan is not compared per
                    // event. Answerability moves inside one wait (`AskUserQuestion`,
                    // ~25 ms later). Every live request counts: the next is worth a wake.
                    turn.requestsAwaitingAnAnswer
                        .map { "\($0.id)\u{2}\($0.identity?.occurrence.uuidString ?? "")\u{2}\($0.form.name)\u{2}\($0.canBeAnswered)" }
                        .joined(separator: "\u{3}"),
                    // Not drawn: the sweep that redeems a held prompt listens on this
                    // edge (``MonitoredTurnState/heldTurnStart``).
                    turn.heldTurnStart?.turnID ?? ""
                ].joined(separator: "\u{1}")
            }
            .sorted()
    }

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
