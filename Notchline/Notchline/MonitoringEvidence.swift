import Foundation

/// Measured behaviour selected by an adapter, independent of native event
/// names. These preserve the existing reduction policies; they are not levels.
nonisolated struct MonitoringReductionPolicy: Sendable {
    var infersApprovalRefusalFromActivity = false
    var infersSubagentApprovalRefusalFromActivity = false
    var settlesHeldTurnsFromRecord = false
    var wakesOnToolCallOpened = false

    static let explicit = MonitoringReductionPolicy()
}

/// A positively observed live boundary, already interpreted by its source.
/// Source event names are optional provenance for boundary diagnostics only;
/// the reducer never interprets them. Requests are projected values, not JSON.
nonisolated struct MonitoringEvidence: Sendable {
    let signal: MonitoringSignal?
    let threadID: String
    let observedAt: Date
    var turnID: String? = nil
    var agentID: String? = nil
    var toolUseID: String? = nil
    /// The request's own identity, for a product that names requests apart
    /// from the calls they concern; nil where the call's id is the identity,
    /// as on both hook products. A resolution names the same identity.
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
    /// What an answer on `answerHandle` may do. Read only beside a handle:
    /// evidence holding no connection declares nothing about one.
    var answerOperations: AnswerOperations = .readingOnly
    var sourceEvent: String? = nil
}

extension AgentRequest {
    /// This request filed on the connection one piece of evidence carries,
    /// permitting what that evidence declares -- and left as it was where the
    /// evidence carries no connection, so a body read off an event that holds
    /// nothing keeps its form's own operations until the event that holds one
    /// says otherwise.
    nonisolated func answerable(by evidence: MonitoringEvidence) -> AgentRequest {
        guard evidence.answerHandle != nil else { return self }
        return answerable(on: evidence.answerHandle, permitting: evidence.answerOperations)
    }
}

/// Content evidence has no lifecycle authority. A missing native Turn ID is
/// retained for compatibility with existing message sources; adapters should
/// supply it whenever their source can establish it.
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

/// Optional boundary bookkeeping. It cannot mutate Turn state. Hooks use it
/// for installation trust and connection retention, both outside the reducer.
/// Package 4 of product-generalisation-plan.md replaces the ticket-backed
/// handle representation; no descriptor is owned or written by the kernel.
nonisolated protocol MonitoringBoundaryObserver: Sendable {
    var hasObservedEvidence: Bool { get }
    func didApply(_ evidence: MonitoringEvidence, accepted: Bool)
    /// Evidence an observation reset dropped before any drain took it; the
    /// handles it carried will never be reconciled and are the boundary's to
    /// let go.
    func didDiscard(_ evidence: [MonitoringEvidence])
    func retainAnswerHandles(_ handles: Set<AnswerHandle>)
    /// The handles whose answer window has run out, let go by the boundary
    /// and returned so the reducer can withdraw them from their requests.
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

    /// Rotates the epoch and returns whatever was pending, so its handles can
    /// be released rather than waiting on a drain that will never take them.
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
