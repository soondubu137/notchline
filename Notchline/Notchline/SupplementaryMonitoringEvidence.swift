import Foundation

nonisolated enum TurnEvidencePhase: Sendable { case identity, lifecycle, afterLifecycle }

/// Narrow authority: these facts can redeem an observed held start, retire a
/// Turn or resolve an existing wait. They cannot submit a Turn or write text.
nonisolated struct TurnEvidenceBatch: Sendable {
    var onRecord: [TurnOnRecord] = []
    var stopped: [String: Date] = [:]
    var interruptions: [TurnInterruption] = []
    var answeredApprovals: [String: Date] = [:]
}

extension TurnEvidenceSource {
    nonisolated var phases: [TurnEvidencePhase] { [.lifecycle] }
}

nonisolated enum SupplementaryEvidenceApplication {
    static func settle(_ source: any TurnEvidenceSource, from initial: MonitoringStateSnapshot,
                       in repository: MonitoringRepository) async -> MonitoringStateSnapshot {
        var state = initial
        let epoch = repository.observationEpoch
        for phase in source.phases {
            let evidence = await source.observations(in: state, phase: phase)
            state = await repository.applying(evidence, in: epoch)
            guard repository.observationEpoch == epoch else { return state }
        }
        return state
    }
}

extension MonitoringRepository {
    func applying(_ evidence: TurnEvidenceBatch, in epoch: MonitoringEpoch) -> MonitoringStateSnapshot {
        guard observationEpoch == epoch else { return observedState() }
        if !evidence.onRecord.isEmpty { _ = adoptTurnsOnRecord(evidence.onRecord) }
        if !evidence.stopped.isEmpty { _ = endTurnsForStoppedSessions(evidence.stopped) }
        if !evidence.interruptions.isEmpty { _ = endInterruptedTurns(evidence.interruptions) }
        if !evidence.answeredApprovals.isEmpty { _ = endAnsweredApprovalWaits(evidence.answeredApprovals) }
        return observedState()
    }

    nonisolated var messageReader: TurnMessageReading {
        TurnMessageReading { self.preview(forSession: $0, inTurn: $1) }
    }
}

/// Read-only content access. A row-content source cannot obtain the repository
/// by downcasting a protocol existential and acquire lifecycle authority.
nonisolated struct TurnMessageReading: Sendable {
    private let read: @Sendable (String, String) -> String?
    init(read: @escaping @Sendable (String, String) -> String?) { self.read = read }
    func preview(forSession threadID: String, inTurn turnID: String) -> String? {
        read(threadID, turnID)
    }
}
