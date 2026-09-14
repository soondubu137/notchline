import Foundation

nonisolated struct ReadGateCandidate: Sendable {
    let row: MonitoredSession
    /// The Turn's own terminal instant, never a boundary a subagent moved forward
    /// (``HookTurnState/turnEndedAt``).
    let turnEndedAt: Date
    /// When the thread stopped working, subagents included. Only the settling window uses it.
    let terminalBoundaryAt: Date
}

nonisolated enum ReadGateVerdict: Sendable {
    /// Nothing can ever say whether this row was read. Shown but kept out of the gate
    /// (CR-Fable-036); it leaves on the next submission, when its Thread goes, or by removal.
    case cannotBeAsked
    /// Judged by this reading's unread set, authority and reach past the Turn's end.
    case judged(by: DesktopUnreadStateSnapshot)
}

nonisolated struct ReadEvidenceJudgement: Sendable {
    /// One verdict per row asked about, keyed by ``MonitoredSession/id``.
    let verdicts: [String: ReadGateVerdict]
    /// The readings' own health.
    let diagnostic: String?
}

/// A product's evidence that a finished row was read; ``TerminalUnreadRowFilter`` owns the rest.
protocol ReadEvidenceSource: Sendable {
    /// Whether there is a screen the answer could be read on. A waiting row's re-check is deferred
    /// while there is none; this stream's edge restarts it.
    nonisolated var screen: any ScreenAvailabilityReporting { get }
    /// Asked only when a finished, unremoved row is listed, and only about unremoved rows: the
    /// readings are expensive (CR-Fable-041, CR-Fable-003). `now` is the instant judged at.
    func verdicts(for candidates: [ReadGateCandidate], now: Date) async -> ReadEvidenceJudgement
    /// No finished row is listed: drop whatever evidence is kept across refreshes.
    func forget() async
}

/// The terminal-unread membership gate applied to a refresh's rows, shared by every Provider;
/// only the verdict is per product (`tiered-support.md` §5.4).
///
/// - A removed row is returned but never judged: dropping it makes the store forget the
///   removal (CR-Fable-004); gate entries book a re-check a second (CR-Fable-003).
/// - Nothing is judged unless a finished row is listed (CR-Fable-041).
/// - The gate gets the thread's status, so a finished Turn with a subagent in flight is not
///   erased after its end was read.
/// - The gate is retained to what was judged, so no stale entry reports an unclearable deadline.
nonisolated struct TerminalUnreadRowFilter: Sendable {
    private var gate: TerminalUnreadMembershipGate

    init(timing: MonitorTiming) {
        gate = TerminalUnreadMembershipGate(
            settlingInterval: timing.terminalReadSettlingInterval,
            unreadRecheckInterval: timing.terminalUnreadRecheckInterval
        )
    }

    /// Whether a finished, unremoved row is listed. Uses the row's status (wider than the
    /// thread's), so skipping readings on `false` never skips one a verdict would use.
    static func needsReadEvidence(
        _ rows: [MonitoredSession],
        dismissedRowIDs: Set<String>
    ) -> Bool {
        rows.contains {
            TerminalUnreadMembershipGate.isTerminal($0.status)
                && !dismissedRowIDs.contains($0.id)
        }
    }

    /// The rows to list, in row order.
    ///
    /// - Parameter verdict: Asked only for undismissed rows and only when
    ///   ``needsReadEvidence(_:dismissedRowIDs:)`` holds, so verdicts may be precomputed.
    mutating func rows(
        _ candidates: [ReadGateCandidate],
        dismissedRowIDs: Set<String>,
        now: Date,
        verdict: (ReadGateCandidate) -> ReadGateVerdict
    ) -> [MonitoredSession] {
        guard Self.needsReadEvidence(candidates.map(\.row), dismissedRowIDs: dismissedRowIDs) else {
            gate.reset()
            return candidates.map(\.row).sorted(by: MonitorAggregation.rowOrder)
        }

        var shown: [MonitoredSession] = []
        var judgedRowIDs: Set<String> = []
        for candidate in candidates {
            let row = candidate.row
            guard !dismissedRowIDs.contains(row.id) else {
                shown.append(row)
                continue
            }
            switch verdict(candidate) {
            case .cannotBeAsked:
                shown.append(row)
            case let .judged(by: unreadState):
                judgedRowIDs.insert(row.id)
                if gate.shouldDisplay(
                    sessionID: row.id,
                    threadID: row.threadID,
                    status: MonitorAggregation.effectiveStatus(of: row),
                    turnEndedAt: candidate.turnEndedAt,
                    terminalBoundaryAt: candidate.terminalBoundaryAt,
                    unreadState: unreadState,
                    now: now
                ) {
                    shown.append(row)
                }
            }
        }
        gate.retain(sessionIDs: judgedRowIDs)
        return shown.sorted(by: MonitorAggregation.rowOrder)
    }

    /// Forgets every row, for a refresh that lists nothing, so no entry keeps booking a re-check.
    mutating func reset() {
        gate.reset()
    }

    /// See ``TerminalUnreadMembershipGate/nextDeadline(now:screenIsAvailable:)``.
    func nextDeadline(now: Date, screenIsAvailable: Bool) -> Date? {
        gate.nextDeadline(now: now, screenIsAvailable: screenIsAvailable)
    }
}
