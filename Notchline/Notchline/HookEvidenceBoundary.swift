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
            // Unplaceable (empty, not JSON, or no event name or session): dropped aloud, as the one
            // report that the transport delivers but the store does not understand (CR-029). No drain.
            hooks.recordUnreadablePayload()
            return .close
        }
        // Our own quota reading fires real hooks. Paths, not URLs: URL equality counts the
        // directory flag.
        if let ignoredWorkingDirectory, let cwd = payload.workingDirectory,
           URL(fileURLWithPath: cwd).standardizedFileURL.path
            == ignoredWorkingDirectory.standardizedFileURL.path {
            return .close
        }

        // Assistant text stops here, never reaching the reducer; see ``HookSessionPreviewStore/fold``.
        if let deltaEvent = vocabulary.messageDeltaEventName, eventName == deltaEvent {
            guard let delta = payload.delta, let sessionID = payload.sessionID else {
                return .close
            }
            // A subagent's words are not the row's answer, and this fold runs before the reducer's
            // `agent_id` gate. From the schema: `-p` probes (2026-08-23, CLI 2.1.241) display no
            // subagent text, so they could not show it.
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

        // Held here, the only moment payload and descriptor are both in hand, by handing it away so
        // this serial queue never waits; an unattached ticket is closed at reconciliation.
        let interpretedName = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        var handle: AnswerHandle?
        // Operations are declared with the connection; none where nothing is held.
        var operations = AnswerOperations.readingOnly
        if let descriptor, eventName == vocabulary.answeringEventName {
            operations = vocabulary.answerOperations(forEvent: interpretedName, toolName: payload.toolName)
            handle = hooks.replies.hold(
                descriptor, answering: payload.toolInput, permitting: operations,
                // The helper's own `nc -w` window, measured from arrival: past
                // it the product has carried on without this app's answer.
                expiringAt: receivedAt.addingTimeInterval(TimeInterval(vocabulary.answerWindowSeconds))
            )
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
            request: projected, answerHandle: handle,
            answerOperations: operations,
            sourceEvent: eventName
        ), in: epoch)
        if !admitted, let handle { hooks.replies.release(handle) }
        return handle == nil ? .close : .held
    }

    /// Native output and socket writes stay outside the shared reducer. The connection's
    /// ``AgentRequest/operations`` are re-checked here: an undeclared answer is refused before
    /// any bytes are composed, and the connection stays held.
    func answer(_ answer: AgentAnswer, on handle: AnswerHandle) -> AnswerOutcome {
        guard let hooks = boundary as? HookEvidenceBoundary else { return .expired(.notHeld) }
        guard let permitted = hooks.replies.operations(for: handle) else {
            // Nothing is held under this handle any more (spent, another channel, or expired).
            withdrawAnswerHandle(handle)
            return .expired(.notHeld)
        }
        guard permitted.permits(answer),
              let body = hooks.vocabulary.answering?.hookOutput(
                for: answer, updating: hooks.replies.input(for: handle)
              ) else { return .unsupportedOperation }
        let outcome = hooks.replies.answer(handle, with: body)
        withdrawAnswerHandle(handle)
        return outcome
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
    private var unattributedPayloadCount = 0

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

    /// A readable payload whose sender a product boundary could not tie to a supported execution.
    /// Separate from an unreadable one: the bytes were fine and the definition fired, so the
    /// remedy is the mode or home the product is running in, not the hook installation.
    func recordUnattributedPayload() {
        lock.lock()
        unattributedPayloadCount += 1
        lock.unlock()
    }

    func didApply(_ evidence: MonitoringEvidence, accepted: Bool) {
        // Accepted or not, the connection is now the reducer's to keep or release at reconciliation.
        if let handle = evidence.answerHandle { replies.markReduced(handle) }
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
        replies.release(evidence.compactMap(\.answerHandle))
    }

    func retainAnswerHandles(_ handles: Set<AnswerHandle>) {
        replies.retain(only: handles)
    }

    func expiredAnswerHandles(at now: Date) -> Set<AnswerHandle> {
        replies.expire(at: now)
    }

    func nextAnswerHandleExpiry() -> Date? {
        replies.nextExpiry()
    }

    func reset() {
        lock.lock()
        observed = false
        didRecordEventThisLaunch = false
        unreadablePayloadCount = 0
        unattributedPayloadCount = 0
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
            unattributedPayloadCount > 0
                ? "Ignored \(Self.payloadCount(unattributedPayloadCount)) Notchline could not attribute to a "
                    + "supported \(vocabulary.agent.displayName) process, such as one run under a custom home, "
                    + "an excluded mode or a terminal multiplexer." : nil,
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
