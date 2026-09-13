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
    var toolName: String? = nil
    var prompt: String? = nil
    var finalText: String? = nil
    var workingDirectory: String? = nil
    var namesATranscript: Bool? = nil
    var pausesForBackgroundWork = false
    var request: AgentRequest? = nil
    var answerHandle: AnswerHandle? = nil
    var sourceEvent: String? = nil
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
nonisolated struct MonitoringEpoch: Sendable, Equatable {
    fileprivate let id = UUID()
}

/// Optional boundary bookkeeping. It cannot mutate Turn state. Hooks use it
/// for installation trust and connection retention, both outside the reducer.
/// Package 4 of product-generalisation-plan.md replaces the ticket-backed
/// handle representation; no descriptor is owned or written by the kernel.
nonisolated protocol MonitoringBoundaryObserver: Sendable {
    var hasObservedEvidence: Bool { get }
    func didApply(_ evidence: MonitoringEvidence, accepted: Bool)
    func retainAnswerHandles(_ handles: Set<AnswerHandle>)
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

    func reset(clearingContent: () -> Void) {
        lock.lock()
        pending.removeAll()
        currentEpoch = MonitoringEpoch()
        clearingContent()
        lock.unlock()
    }
}
