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
struct TerminalReadEvidence: Sendable {
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
