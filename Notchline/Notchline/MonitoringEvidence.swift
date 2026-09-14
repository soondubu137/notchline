import Foundation

/// Measured behaviour selected by an adapter, independent of native event names; not levels.
nonisolated struct MonitoringReductionPolicy: Sendable {
    var infersApprovalRefusalFromActivity = false
    var infersSubagentApprovalRefusalFromActivity = false
    var settlesHeldTurnsFromRecord = false
    var wakesOnToolCallOpened = false

    static let explicit = MonitoringReductionPolicy()
}

/// A positively observed live boundary, interpreted by its source. Event names are diagnostics
/// only; requests are projected values, not JSON.
nonisolated struct MonitoringEvidence: Sendable {
    let signal: MonitoringSignal?
    let threadID: String
    let observedAt: Date
    var turnID: String? = nil
    var agentID: String? = nil
    var toolUseID: String? = nil
    /// The request's own identity where a product names requests apart from calls; nil where the
    /// call's id is the identity (both hook products).
    var requestID: String? = nil
    /// Where the native protocol versions a request separately from its ID.
    var requestRevision: String? = nil
    var toolName: String? = nil
    var prompt: String? = nil
    var finalText: String? = nil
    var workingDirectory: String? = nil
    var namesATranscript: Bool? = nil
    var pausesForBackgroundWork = false
    var request: AgentRequest? = nil
    var answerHandle: AnswerHandle? = nil
    /// What an answer on `answerHandle` may do; meaningless without a handle.
    var answerOperations: AnswerOperations = .readingOnly
    var sourceEvent: String? = nil
}

extension AgentRequest {
    /// Filed on the evidence's connection with its declared operations; unchanged without one.
    nonisolated func answerable(by evidence: MonitoringEvidence) -> AgentRequest {
        guard evidence.answerHandle != nil else { return self }
        return answerable(on: evidence.answerHandle, permitting: evidence.answerOperations)
    }
}

/// Content evidence has no lifecycle authority. The Turn ID is optional for compatibility;
/// adapters should supply it when they can.
nonisolated struct MonitoringProgress: Sendable {
    let threadID: String
    let turnID: String?
    let messageID: String?
    let text: String
    var producerID: String? = nil
}

nonisolated struct MonitoringStatistics: Sendable {
    let hasObservedLiveEvidence: Bool
    let unplacedEvidenceCount: Int
    let announcedCallCount: Int
    let closedCallCount: Int
}

/// Capture when subscribing to a native stream. Resetting observation rejects
/// callbacks still carrying the previous subscription's token.
nonisolated struct MonitoringEpoch: Sendable, Hashable {
    fileprivate let id = UUID()
}

/// Optional boundary bookkeeping; it cannot mutate Turn state (product-generalisation-plan.md
/// package 4).
nonisolated protocol MonitoringBoundaryObserver: Sendable {
    var hasObservedEvidence: Bool { get }
    func didApply(_ evidence: MonitoringEvidence, accepted: Bool)
    /// Evidence an observation reset dropped before any drain; its handles are the boundary's to
    /// let go.
    func didDiscard(_ evidence: [MonitoringEvidence])
    func retainAnswerHandles(_ handles: Set<AnswerHandle>)
    /// Expired handles, let go by the boundary so the reducer can withdraw them from requests.
    func expiredAnswerHandles(at now: Date) -> Set<AnswerHandle>
    /// When the next held window runs out; nil while none is held.
    func nextAnswerHandleExpiry() -> Date?
    func diagnostic(for statistics: MonitoringStatistics) -> String?
    func reset()
}

/// Ordered hand-off from a source's serial delivery queue to the actor.
/// Appending is synchronous; a drain takes the entire prefix atomically.
nonisolated final class MonitoringEvidenceInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [MonitoringEvidence] = []
    private var currentEpoch = MonitoringEpoch()

    var epoch: MonitoringEpoch {
        lock.lock()
        defer { lock.unlock() }
        return currentEpoch
    }

    func append(_ evidence: MonitoringEvidence, in epoch: MonitoringEpoch) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard epoch == currentEpoch else { return false }
        pending.append(evidence)
        return true
    }

    func ifCurrent(_ epoch: MonitoringEpoch, perform operation: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard epoch == currentEpoch else { return }
        operation()
    }

    func take() -> [MonitoringEvidence] {
        lock.lock()
        defer { lock.unlock() }
        let result = pending
        pending.removeAll(keepingCapacity: true)
        return result
    }

    /// Rotates the epoch and returns what was pending, so its handles can be released.
    @discardableResult
    func reset(clearingContent: () -> Void) -> [MonitoringEvidence] {
        lock.lock()
        let dropped = pending
        pending.removeAll()
        currentEpoch = MonitoringEpoch()
        clearingContent()
        lock.unlock()
        return dropped
    }
}
