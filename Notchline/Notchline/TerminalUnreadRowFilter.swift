import Foundation

/// One row a refresh built, with the two instants the gate dates it against.
nonisolated struct ReadGateCandidate: Sendable {
    let row: MonitoredSession
    /// The Turn's own terminal instant, never a boundary a subagent moved
    /// forward: reading is done to an answer, and the answer landed there
    /// (``HookTurnState/turnEndedAt``).
    let turnEndedAt: Date
    /// When the *thread* stopped working, a subagent outliving the Turn
    /// included. Only the settling window is measured from it.
    let terminalBoundaryAt: Date
}

/// What a product's read evidence says about one row.
nonisolated enum ReadGateVerdict: Sendable {
    /// Nothing can ever say whether this row was read — no desktop record and
    /// no terminal whose host could hold the front. Shown, and kept out of the
    /// gate, so it books no re-check for a question with no possible answer
    /// (CR-Fable-036). Such a row leaves on its Thread's next submission, when
    /// the Thread goes away, or when the user removes it.
    case cannotBeAsked
    /// Judged by the gate against this reading. The gate asks the reading
    /// whether the row's Thread is unread, whether it is authoritative, and
    /// whether it reaches forward past the Turn's end.
    case judged(by: DesktopUnreadStateSnapshot)
}

/// The terminal-unread membership gate applied to a refresh's rows: which
/// finished rows stay listed until they have been read, and when to look at
/// them again.
///
/// **Every Provider ran this loop, and each wrote it by hand.** Codex's
/// service, Claude Code's and ``HookProductProvider`` each walked their rows,
/// passed the dismissed ones through unjudged, kept rows nothing could answer
/// for out of the gate, asked the gate about the rest, retained the gate to
/// what was judged and sorted the result — three copies of rules whose every
/// clause is a closed defect. What differs between products is only the
/// verdict, which is the product's read evidence (`tiered-support.md` §5.4);
/// this is the part that is not.
///
/// **The rules it holds**, and the defect each one closed:
///
/// - **A row the user has removed is judged by nobody.** It is still returned,
///   because what a product lists is what it knows about, and a Provider that
///   stopped listing a Turn would be telling the store the Turn had ended —
///   the one thing that makes the store forget a removal (CR-Fable-004). It
///   never enters the gate, whose entries book a re-check a second whether or
///   not the row is on the notch (CR-Fable-003).
/// - **Nothing is judged unless a finished row is listed.** A list of running
///   rows would show every row and drop every entry, so the pass collapses to
///   emptying the gate — and ``needsReadEvidence(_:dismissedRowIDs:)`` lets a
///   product skip assembling evidence that could change none of it
///   (CR-Fable-041).
/// - **The gate is given the thread's status, not the row's.** A finished Turn
///   with a subagent still in flight takes the running path, so the one row
///   carrying the evidence that anything is still running cannot be erased a
///   settling interval after an end the user has already read.
/// - **The gate is retained to what was judged**, so an entry for a row that
///   stopped being evaluated — a sub-agent thread, a dismissed row, a Thread
///   that went away — cannot freeze mid-window and report a deadline no
///   refresh can clear.
nonisolated struct TerminalUnreadRowFilter: Sendable {
    private var gate: TerminalUnreadMembershipGate

    init(timing: MonitorTiming) {
        gate = TerminalUnreadMembershipGate(
            settlingInterval: timing.terminalReadSettlingInterval,
            unreadRecheckInterval: timing.terminalUnreadRecheckInterval
        )
    }

    /// Whether any row could be withheld by read evidence: a finished row the
    /// user has not taken off the list.
    ///
    /// Asked of the row's own status rather than the thread's, which is the
    /// wider of the two, so a product that skips its readings on `false`
    /// never skips one the verdicts below would have used — a finished Turn
    /// with a subagent running still records what its product can see about
    /// it (Claude Code's on-screen membership is one such record).
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
    /// - Parameter verdict: Asked only for rows that are not dismissed, and
    ///   only when ``needsReadEvidence(_:dismissedRowIDs:)`` holds, so a
    ///   product may compute its verdicts ahead of the call and look them up
    ///   here.
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

    /// Forgets every row. For a refresh that lists nothing, so nothing is
    /// waiting to be read and no entry may go on booking a re-check.
    mutating func reset() {
        gate.reset()
    }

    /// The settling window's end, or the re-check a row waiting on the user
    /// books — see
    /// ``TerminalUnreadMembershipGate/nextDeadline(now:screenIsAvailable:)``.
    func nextDeadline(now: Date, screenIsAvailable: Bool) -> Date? {
        gate.nextDeadline(now: now, screenIsAvailable: screenIsAvailable)
    }
}
