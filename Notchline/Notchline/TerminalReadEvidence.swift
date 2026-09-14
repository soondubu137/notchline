import Foundation

/// Whether the user has been at the terminal a product's Thread runs in: the terminal half of
/// read state (`tiered-support.md` §5.4). Read means a gesture after the Turn ended, at a
/// terminal whose application was in front.
///
/// - No controlling terminal, or `tmux`/`screen`/`ssh` with no app in the ancestry, is
///   `cannotBeAsked` and kept out of the gate (CR-Fable-036).
/// - Antigravity CLI 1.2.2 enables no focus or mouse reporting (measured 2026-09-12), so only
///   a keystroke or paste retires its rows; Claude Code's pointer motion is fenced by the front.
struct TerminalReadEvidence: ReadEvidenceSource {
    let sessions: any SessionProcessLocating
    let gestures: any ControllingTerminalGestureReporting
    /// Not used by the verdict; the deadline waits on it (``ScreenAvailabilityReporting``).
    let screen: any ScreenAvailabilityReporting

    init(
        sessions: any SessionProcessLocating,
        gestures: any ControllingTerminalGestureReporting =
            ControllingTerminalGestureReader(),
        screen: any ScreenAvailabilityReporting = ScreenAvailabilityWatcher()
    ) {
        self.sessions = sessions
        self.gestures = gestures
        self.screen = screen
    }

    enum Verdict: Equatable, Sendable {
        /// Nothing can ever answer for this row. Keep it out of the gate.
        case cannotBeAsked
        /// The user was at this Thread's terminal after the Turn ended.
        case read
        /// Askable, and the answer is no; worth asking again a second later.
        case unread
    }

    /// A thread still working is shown without a reading.
    func verdicts(for candidates: [ReadGateCandidate], now: Date) async -> ReadEvidenceJudgement {
        var verdicts: [String: ReadGateVerdict] = [:]
        for candidate in candidates {
            guard TerminalUnreadMembershipGate.isTerminal(
                MonitorAggregation.effectiveStatus(of: candidate.row)
            ) else {
                verdicts[candidate.row.id] = .judged(by: Self.reading(unread: [], at: now))
                continue
            }
            switch await verdict(
                forThreadID: candidate.row.threadID,
                turnEndedAt: candidate.turnEndedAt
            ) {
            case .cannotBeAsked:
                verdicts[candidate.row.id] = .cannotBeAsked
            case .read:
                verdicts[candidate.row.id] = .judged(by: Self.reading(unread: [], at: now))
            case .unread:
                verdicts[candidate.row.id] = .judged(
                    by: Self.reading(unread: [candidate.row.threadID], at: now)
                )
            }
        }
        return ReadEvidenceJudgement(verdicts: verdicts, diagnostic: nil)
    }

    /// Every verdict is a fresh kernel reading.
    func forget() async {}

    /// Authoritative and current. Not a desktop product's authority: without Claude Desktop that
    /// source reports `unavailable`, leaving every terminal row ungated.
    nonisolated static func reading(unread: Set<String>, at now: Date) -> DesktopUnreadStateSnapshot {
        DesktopUnreadStateSnapshot(unreadThreadIDs: unread, source: .current, currentAsOf: now)
    }

    /// - Parameter turnEndedAt: As ``ReadGateCandidate/turnEndedAt``.
    func verdict(
        forThreadID threadID: String,
        turnEndedAt: Date
    ) async -> Verdict {
        guard let pid = await sessions.processIdentifier(forThreadID: threadID),
              let reading = await gestures.reading(forProcessIdentifier: pid),
              reading.hostCanEverBeInFrontOfTheUser else {
            return .cannotBeAsked
        }
        guard reading.hostIsInFrontOfTheUser,
              reading.lastGesture >= turnEndedAt else {
            return .unread
        }
        return .read
    }
}
