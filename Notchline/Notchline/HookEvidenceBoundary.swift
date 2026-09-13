import Foundation

/// Hooks compatibility facade over the shared repository. Only this boundary
/// knows native JSON, registration trust, file paths and held descriptors.
/// The alias HookEventRepository names this same repository for older callers.
extension MonitoringRepository {
    init(
        paths: HookIntegrationPaths = .live(),
        fileManager: FileManager = .default,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard,
        vocabulary: any AgentHookVocabulary = CodexHookVocabulary(),
        ignoredWorkingDirectory: URL? = nil
    ) {
        self.init(
            policy: MonitoringReductionPolicy(
                infersApprovalRefusalFromActivity: !vocabulary.reportsApprovalDenials,
                infersSubagentApprovalRefusalFromActivity: true,
                settlesHeldTurnsFromRecord: vocabulary.settlesHeldTurnsFromRecord,
                wakesOnToolCallOpened: vocabulary.wakesOnToolCallOpened
            ),
            clock: clock, timing: timing,
            boundary: HookEvidenceBoundary(paths: paths, vocabulary: vocabulary,
                ignoredWorkingDirectory: ignoredWorkingDirectory,
                fileManager: fileManager, clock: clock)
        )
    }

    @discardableResult
    nonisolated func deliver(
        _ body: Data,
        at receivedAt: Date,
        on descriptor: Int32? = nil
    ) -> AgentHookListener.Disposition {
        guard let hooks = boundary as? HookEvidenceBoundary else {
            preconditionFailure("Raw hook bytes require a Hooks boundary; use submit for typed evidence")
        }
        let vocabulary = hooks.vocabulary
        let epoch = observationEpoch
        let ignoredWorkingDirectory = hooks.ignoredWorkingDirectory
        guard let payload = HookPayload.distilled(
            from: body,
            admittingRequestWhere: vocabulary.carriesRequest(forEvent:toolName:)
        ),
              let eventName = payload.hookEventName,
              payload.sessionID != nil else {
            // Nothing here can be placed: nothing at all, or not JSON, or
            // JSON without the event name or the session this app keys
            // everything on. It is still dropped — there is nowhere to
            // quarantine it to, and the quarantine was itself unread litter —
            // but it is dropped *aloud*. This is the one report that says the
            // transport is delivering and the store is not understanding,
            // which is what every silent failure this integration is designed
            // around looks like from in here (CR-029). No drain is kicked for
            // it: nothing rendered changed, and the refresh path drains every
            // cycle anyway.
            hooks.recordUnreadablePayload()
            return .close
        }
        // Our own quota reading is a real session firing real hooks.
        // Compared as paths rather than URLs: a URL built from a payload string
        // is not marked as a directory, and URL equality counts that, so two
        // spellings of the same folder would not match.
        if let ignoredWorkingDirectory, let cwd = payload.workingDirectory,
           URL(fileURLWithPath: cwd).standardizedFileURL.path
            == ignoredWorkingDirectory.standardizedFileURL.path {
            return .close
        }

        // Assistant text stops here. Folding it costs one bounded scan and
        // reaches the reducer's mailbox not at all, which is why a talking turn
        // never reduces anything. It does wake the panel when the line the row
        // draws moves -- that is the whole point of the line -- and the head's
        // cap is what keeps that to about one wake per message rather than one
        // per delta. See ``HookSessionPreviewStore/fold``.
        if let deltaEvent = vocabulary.messageDeltaEventName, eventName == deltaEvent {
            guard let delta = payload.delta, let sessionID = payload.sessionID else {
                return .close
            }
            // A subagent's words are not the row's answer, and this is the one
            // path a subagent's event could reach the user by: the fold happens
            // here, before the reducer, so the `agent_id` gate down there never
            // sees it. Written from the schema rather than from an observation:
            // `agent_id` is on the base every Claude Code hook input extends,
            // and two `-p` probes on 2026-08-23 (CLI 2.1.241) produced
            // `MessageDisplay` for the main thread only -- but `-p` displays no
            // subagent text at all, and the event's own description is "while
            // assistant message text is displayed", so a session with a screen
            // is exactly the case those probes could not reach. One comparison
            // is not a price worth paying to find that out from a user.
            if let agentID = payload.agentID,
               !agentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .close
            }
            recordProgress(MonitoringProgress(
                threadID: sessionID, turnID: payload.promptID,
                messageID: payload.messageID, text: delta,
                producerID: payload.agentID
            ), in: epoch)
            return .close
        }

        // The one event per product whose connection an answer travels back on.
        // Held here rather than after the reduce, because this is the only
        // moment at which the payload and its descriptor are both in hand — and
        // held *by handing it away*, so this queue, whose serialness is what
        // preserves arrival order, never waits on anybody.
        //
        // A ticket that the reducer then does not attach to a wait is closed by
        // the reconciliation after the drain, so this cannot leak by admitting
        // too much.
        // The old reducer normalised event names before vocabulary lookup.
        // Keep that interpretation here; raw transport framing is unchanged.
        let interpretedName = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        var ticket: HookReplyRegistry.Ticket?
        // What the product will act on down this connection, declared with
        // the connection and carried on the evidence beside it. Nothing is
        // declared where nothing is held.
        var operations = AnswerOperations.readingOnly
        if let descriptor, eventName == vocabulary.answeringEventName {
            operations = vocabulary.answerOperations(forEvent: interpretedName, toolName: payload.toolName)
            ticket = hooks.replies.hold(descriptor, answering: payload.toolInput, permitting: operations)
        }
        let projected = vocabulary.carriesRequest(forEvent: interpretedName, toolName: payload.toolName)
            ? vocabulary.request(
            forEvent: interpretedName, toolName: payload.toolName,
            toolInput: payload.toolInput, permissionSuggestions: payload.permissionSuggestions,
            openedBy: payload.toolUseID ?? ""
        ) : nil
        let admitted = submit(MonitoringEvidence(
            signal: vocabulary.signal(forEvent: interpretedName, toolName: payload.toolName),
            threadID: payload.sessionID!, observedAt: receivedAt,
            turnID: payload.turnID, agentID: payload.agentID,
            toolUseID: payload.toolUseID, toolName: payload.toolName,
            prompt: vocabulary.carriesPromptText ? payload.prompt : nil,
            finalText: vocabulary.carriesFinalAnswerText ? payload.lastAssistantMessage : nil,
            workingDirectory: payload.workingDirectory,
            namesATranscript: payload.namesATranscript,
            pausesForBackgroundWork: payload.pausesForBackgroundWork,
            request: projected, answerHandle: ticket.map(AnswerHandle.init),
            answerOperations: operations,
            sourceEvent: eventName
        ), in: epoch)
        if !admitted, let ticket { hooks.replies.release(ticket) }
        return ticket == nil ? .close : .held
    }

    /// Native output and socket writes stay outside the shared reducer.
    ///
    /// **The connection's declaration is checked here as well as on the
    /// surface.** A row offers only what ``AgentRequest/operations`` permits,
    /// but the row is not the only caller and a check that lives in one layer
    /// is a check one layer can forget: an answer the connection was never
    /// declared for is refused before any bytes are composed, and the
    /// connection stays held for the answer it does accept.
    func answer(_ answer: AgentAnswer, on ticket: HookReplyRegistry.Ticket) -> Bool {
        guard let hooks = boundary as? HookEvidenceBoundary else { return false }
        guard let permitted = hooks.replies.operations(for: ticket) else {
            // Nothing is held under this ticket any more, so the request
            // stops claiming a connection it does not have.
            withdrawAnswerHandle(AnswerHandle(ticket: ticket))
            return false
        }
        guard permitted.permits(answer),
              let body = hooks.vocabulary.answering?.hookOutput(
                for: answer, updating: hooks.replies.input(for: ticket)
              ) else { return false }
        let delivered = hooks.replies.answer(ticket, with: body)
        withdrawAnswerHandle(AnswerHandle(ticket: ticket))
        return delivered
    }
}

/// Boundary observation can be updated on the ordered reduction actor and
/// read on the source queue. The lock protects bookkeeping, never Turn state.
nonisolated final class HookEvidenceBoundary: MonitoringBoundaryObserver, @unchecked Sendable {
    let vocabulary: any AgentHookVocabulary
    let ignoredWorkingDirectory: URL?
    let replies = HookReplyRegistry()
    private let paths: HookIntegrationPaths
    private let fileManager: FileManager
    private let clock: any MonitorClock
    private let lock = NSLock()
    private var observed: Bool
    private var eventsAwaitingTrust: Set<String>
    private var didRecordEventThisLaunch = false
    private var unreadablePayloadCount = 0

    init(paths: HookIntegrationPaths, vocabulary: any AgentHookVocabulary,
         ignoredWorkingDirectory: URL?, fileManager: FileManager, clock: any MonitorClock) {
        self.paths = paths
        self.vocabulary = vocabulary
        self.ignoredWorkingDirectory = ignoredWorkingDirectory
        self.fileManager = fileManager
        self.clock = clock
        let record = HookInstallStateFile.read(at: paths.installState)
        observed = record.lastEventAt != nil
        eventsAwaitingTrust = Set(record.eventsAwaitingTrust ?? [])
    }

    var hasObservedEvidence: Bool {
        lock.lock()
        defer { lock.unlock() }
        return observed
    }

    func recordUnreadablePayload() {
        lock.lock()
        unreadablePayloadCount += 1
        lock.unlock()
    }

    func didApply(_ evidence: MonitoringEvidence, accepted: Bool) {
        // Applied, accepted or not, so the connection it arrived with is now
        // the reducer's to keep or let go at the reconciliation that follows.
        if let ticket = evidence.answerHandle?.ticket { replies.markReduced(ticket) }
        lock.lock()
        defer { lock.unlock() }
        // Delivery proves a definition fired even if its evidence cannot be placed.
        if let name = evidence.sourceEvent?.trimmingCharacters(in: .whitespacesAndNewlines),
           eventsAwaitingTrust.remove(name) != nil {
            let remaining = eventsAwaitingTrust.sorted()
            HookInstallStateFile.update(at: paths.installState, fileManager: fileManager) {
                $0.eventsAwaitingTrust = remaining.isEmpty ? nil : remaining
            }
        }
        guard accepted else { return }
        observed = true
        guard !didRecordEventThisLaunch else { return }
        didRecordEventThisLaunch = true
        HookInstallStateFile.update(at: paths.installState, fileManager: fileManager) {
            $0.lastEventAt = self.clock.now()
        }
    }

    func didDiscard(_ evidence: [MonitoringEvidence]) {
        replies.release(evidence.compactMap { $0.answerHandle?.ticket })
    }

    func retainAnswerHandles(_ handles: Set<AnswerHandle>) {
        replies.retain(only: Set(handles.map(\.ticket)))
    }

    func reset() {
        lock.lock()
        observed = false
        didRecordEventThisLaunch = false
        unreadablePayloadCount = 0
        lock.unlock()
    }

    func diagnostic(for statistics: MonitoringStatistics) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let undelivered: String? = statistics.announcedCallCount == 0 && statistics.closedCallCount >= 3
            ? "\(vocabulary.agent.displayName) is not running the PreToolUse hook, "
                + "so Input needed and Approval needed cannot be shown. "
                + vocabulary.restoreDefinitionAdvice
            : nil
        let untrusted: String? = statistics.hasObservedLiveEvidence && !eventsAwaitingTrust.isEmpty
            ? "\(vocabulary.agent.displayName) may not be running the "
                + "\(eventsAwaitingTrust.sorted().joined(separator: ", ")) hook: Notchline changed that definition and cannot "
                + "confirm it was trusted again. " + vocabulary.restoreDefinitionAdvice
            : nil
        let sentences = [
            unreadablePayloadCount > 0
                ? "Ignored \(Self.payloadCount(unreadablePayloadCount)) that could not be read." : nil,
            statistics.unplacedEvidenceCount > 0
                ? "Ignored \(Self.payloadCount(statistics.unplacedEvidenceCount)) with no stable identity, or of an unsupported kind." : nil,
            undelivered, untrusted
        ].compactMap { $0 }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    private static func payloadCount(_ count: Int) -> String {
        count == 1 ? "1 hook payload" : "\(count) hook payloads"
    }
}
