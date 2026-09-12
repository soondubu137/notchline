import Foundation

/// Whether the user has been at the terminal one of a product's Threads is
/// running in.
///
/// **The read evidence a terminal product gets for naming its processes, and
/// nothing else.** `tiered-support.md` §5.4 lists the terminal half of read
/// state as the one `ReadEvidenceSource` every CLI product shares: Claude Code
/// reaches it through `claude agents --json`, Antigravity CLI through the
/// presence lock its `agy` process holds, and neither product is asked
/// anything about reading. What a product supplies is
/// ``SessionProcessLocating`` — which process is running this Thread — and the
/// kernel answers the rest.
///
/// The reading itself, its measurements and everything it cannot see belong to
/// ``ControllingTerminalGestureReporting``. This composes it into the one
/// verdict a Provider needs per finished row, so that a second CLI product
/// does not re-derive the pairing: **a gesture after the Turn ended, at a
/// terminal whose application was in front of the user when it was taken.**
///
/// **The verdict is deliberately three-valued.** "Cannot be asked" is not
/// "unread": a session with no controlling terminal, or one under `tmux`,
/// `screen` or `ssh` whose ancestry never passes through an application, has
/// no answer available on any later look — so its row is kept out of the
/// unread gate entirely rather than parked there with a permanently false
/// verdict, which is what booked a refresh a second for the life of such a
/// session (CR-Fable-036).
///
/// **What each product's terminal contract makes of this differs, and the
/// difference is measured rather than assumed.** Claude Code enables focus
/// reporting *and* all-motion mouse reporting, so coming back to the tab
/// retires its row and a pointer crossing the window is a gesture that has to
/// be fenced off by the front. Antigravity CLI 1.2.2 enables neither —
/// measured 2026-09-12 on a pty: the TUI writes `?1049h`, `?25l` and `?2004h`
/// and nothing else — so its rows are retired by a keystroke or a paste and
/// not by a return to the tab, and the pointer cannot retire one at all. Both
/// degrade towards keeping the row, which is the direction this product
/// prefers everywhere.
struct TerminalReadEvidence: ReadEvidenceSource {
    /// Which process is running a Thread, from the product's own live list.
    let sessions: any SessionProcessLocating
    /// What that process's controlling terminal says about the user being at
    /// it.
    let gestures: any ControllingTerminalGestureReporting
    /// Whether there is a screen the answer could have been read on.
    ///
    /// Not consulted by the verdict — the reading already fails closed on a
    /// sleeping display or a locked screen. It is here because the *deadline*
    /// needs it: a row waiting on the user books nothing while nobody can see
    /// it, and waits on this stream instead (``ScreenAvailabilityReporting``).
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

    /// What this Thread's own terminal says about one finished Turn.
    enum Verdict: Equatable, Sendable {
        /// Nothing can ever answer for this row. Keep it out of the gate.
        case cannotBeAsked
        /// The user was at this Thread's terminal after the Turn ended.
        case read
        /// It could be asked and the answer is no, which is a question worth
        /// asking again a second later.
        case unread
    }

    /// A verdict for every candidate: the terminal's for a finished Turn, and
    /// for a thread still working the answer that shows it and drops its
    /// entry, with no reading taken — nothing a terminal says can withhold a
    /// row that is still running.
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

    /// Nothing is held across refreshes: every verdict is a kernel reading
    /// taken on the spot.
    func forget() async {}

    /// A terminal verdict as the gate reads one: authoritative and current by
    /// construction, because it was computed in this refresh from a kernel
    /// reading that cannot be a generation behind. A reading that failed
    /// answered `cannotBeAsked` and took its row out of the gate rather than
    /// into it with a stale verdict.
    ///
    /// It carries its own authority rather than any desktop product's, and the
    /// difference is not cosmetic: a user who has never opened Claude Desktop
    /// has no tree at all, which reports `unavailable`, and a non-authoritative
    /// snapshot may hide nothing -- so borrowing that source would leave every
    /// terminal row permanently ungated, on exactly the machines this route
    /// exists for.
    nonisolated static func reading(unread: Set<String>, at now: Date) -> DesktopUnreadStateSnapshot {
        DesktopUnreadStateSnapshot(unreadThreadIDs: unread, source: .current, currentAsOf: now)
    }

    /// - Parameter turnEndedAt: The Turn's own terminal instant, never a
    ///   boundary a subagent moved forward: reading is done to an answer, and
    ///   the answer landed there (``HookTurnState/turnEndedAt``).
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
