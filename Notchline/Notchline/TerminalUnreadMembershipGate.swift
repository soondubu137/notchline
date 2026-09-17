import Foundation

struct DesktopUnreadStateSnapshot: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case current
        case backup
        case lastKnownGood
        case unavailable

        nonisolated var isAuthoritative: Bool {
            if case .current = self {
                return true
            }
            return false
        }
    }

    let unreadThreadIDs: Set<String>
    let source: Source
    /// The instant this reading is a complete account up to.
    ///
    /// A thread's absence from the set means "read" only if the reading reaches past the Turn
    /// (``TerminalUnreadMembershipGate``). Codex Desktop writes `.codex-global-state.json` through
    /// a trailing 500 ms debounce with no maximum wait, shared by every persisted atom including
    /// the per-keystroke composer draft: 165 typed characters produced one write, 45.4 s after the
    /// previous (Desktop `26.820.60940`, 2026-08-26). A snapshot built in memory answers `now`.
    let currentAsOf: Date
    let diagnostic: String?

    nonisolated init(
        unreadThreadIDs: Set<String>,
        source: Source,
        currentAsOf: Date,
        diagnostic: String? = nil
    ) {
        self.unreadThreadIDs = unreadThreadIDs
        self.source = source
        self.currentAsOf = currentAsOf
        self.diagnostic = diagnostic
    }

    /// A reading with no data that reaches no further than the beginning of time, so it judges
    /// no Turn.
    nonisolated static func unavailable(_ diagnostic: String) -> Self {
        Self(
            unreadThreadIDs: [],
            source: .unavailable,
            currentAsOf: .distantPast,
            diagnostic: diagnostic
        )
    }

    /// Keeps the data and its `currentAsOf`: demotion to a non-hiding source does not move it forward.
    nonisolated func retainingData(
        source: Source,
        diagnostic: String
    ) -> Self {
        Self(
            unreadThreadIDs: unreadThreadIDs,
            source: source,
            currentAsOf: currentAsOf,
            diagnostic: diagnostic
        )
    }
}

struct TerminalUnreadMembershipGate: Sendable {
    private struct Entry: Sendable {
        /// When this Turn's own terminal arrived; unread readings are dated against this, not
        /// ``terminalObservedAt``, which a subagent pushes forward.
        var turnEndedAt: Date
        /// When this thread stopped working, subagents included. Only the settling window uses it.
        var terminalObservedAt: Date
        var hasObservedUnread: Bool
        var isHidden: Bool
        /// Whether waiting, and nothing else, could still hide this row. False for an unreadable
        /// state, a reading taken before the Turn ended, or a row Desktop still reports unread.
        /// See ``nextDeadline(now:screenIsAvailable:)``.
        var canHideByWaiting: Bool
        /// Whether only the *user* can hide this row (Desktop reports it unread), which needs a
        /// visible screen; a row waiting on the file does not. See ``nextDeadline(now:screenIsAvailable:)``.
        var waitsOnTheUser: Bool
    }

    private let settlingInterval: TimeInterval
    private let unreadRecheckInterval: TimeInterval
    private var entries: [String: Entry] = [:]

    nonisolated init(
        settlingInterval: TimeInterval = 2,
        unreadRecheckInterval: TimeInterval = 1
    ) {
        self.settlingInterval = settlingInterval
        self.unreadRecheckInterval = unreadRecheckInterval
    }

    /// - Parameters:
    ///   - turnEndedAt: When this Turn's own terminal arrived; the unread reading is dated
    ///     against it.
    ///   - terminalBoundaryAt: When this *thread* stopped working, subagents included. Only the
    ///     settling window uses it: dating the reading against it (a `SubagentStop` 91 s after
    ///     `Stop`, 2026-08-22) discarded the write recording the user reading the thread.
    nonisolated mutating func shouldDisplay(
        sessionID: String,
        threadID: String,
        status: SessionStatus,
        turnEndedAt: Date,
        terminalBoundaryAt: Date,
        unreadState: DesktopUnreadStateSnapshot,
        now: Date
    ) -> Bool {
        guard Self.isTerminal(status) else {
            entries.removeValue(forKey: sessionID)
            return true
        }

        var entry = entries[sessionID] ?? Entry(
            turnEndedAt: turnEndedAt,
            terminalObservedAt: terminalBoundaryAt,
            hasObservedUnread: false,
            isHidden: false,
            canHideByWaiting: false,
            waitsOnTheUser: false
        )
        // Only a *newer* Turn ending may bring a hidden row back; read before folding in the stamp.
        // Covers a Turn that started and ended between two refreshes. Uses the Turn's own terminal,
        // not `terminalBoundaryAt`: a subagent stopping is not a Turn ending (cf.
        // ``HookEventRepository/reduceSubagentBoundary(_:agentID:threadID:at:)``).
        let endedAgain = turnEndedAt > entry.turnEndedAt
        entry.turnEndedAt = max(entry.turnEndedAt, turnEndedAt)
        entry.terminalObservedAt = max(
            entry.terminalObservedAt,
            terminalBoundaryAt
        )
        if endedAgain {
            entry.isHidden = false
            entry.hasObservedUnread = false
        }
        let isCurrentlyUnread = unreadState.unreadThreadIDs.contains(threadID)
        // Needs an authoritative source *and* a reading that reaches this Turn's end; an earlier
        // reading's silence is not evidence. Desktop's debounce kept a finished Turn out of the file
        // for 45.4 s while the user typed elsewhere, and the row was hidden for good (2026-08-26).
        // No settling interval bounds that. Same rule as ADR 0012 第一条.
        let canAnswer = unreadState.source.isAuthoritative
            && unreadState.currentAsOf >= entry.turnEndedAt
        entry.canHideByWaiting = canAnswer && !isCurrentlyUnread
        entry.waitsOnTheUser = canAnswer && isCurrentlyUnread

        guard canAnswer else {
            entries[sessionID] = entry
            return !entry.isHidden
        }

        // Hiding is final for this Turn: sources written by other apps disagree routinely, and a
        // provisional hide flashed retired rows back (CC-024). A running row drops its entry above.
        if isCurrentlyUnread {
            entry.hasObservedUnread = true
        } else if entry.hasObservedUnread
                    || now.timeIntervalSince(entry.terminalObservedAt)
                        >= settlingInterval {
            entry.isHidden = true
        }

        entries[sessionID] = entry
        return !entry.isHidden
    }

    /// When a still-visible terminal row should next be looked at again. Every such row reports:
    ///
    /// - Inside its settling window: the instant the window expires.
    /// - Unread, unreadable, or read before this Turn ended: a re-check measured from `now`. The
    ///   watcher is only a hint; without this a late edge left rows listed (8 s, traced live).
    ///   Never a stale `terminalObservedAt + settlingInterval`: clamped to the 1 s floor, that is
    ///   a busy loop.
    ///
    /// - Parameter screenIsAvailable: Whether the display is awake and the session unlocked and
    ///   on the console. A row waiting on the *user* books nothing while false, since every route
    ///   that retires it needs the screen; ungated it woke every second all night on battery
    ///   (CR-Fable-018). It waits on ``ScreenAvailabilityReporting/changeEvents()`` instead.
    ///   Rows waiting on the file are unaffected. Defaults to `true` for tests.
    nonisolated func nextDeadline(
        now: Date,
        screenIsAvailable: Bool = true
    ) -> Date? {
        entries.values
            .filter { !$0.isHidden }
            .compactMap { entry -> Date? in
                if entry.canHideByWaiting {
                    return entry.terminalObservedAt
                        .addingTimeInterval(settlingInterval)
                }
                guard screenIsAvailable || !entry.waitsOnTheUser else {
                    return nil
                }
                return now.addingTimeInterval(unreadRecheckInterval)
            }
            .min()
    }

    /// - Parameter heldSessionIDs: Turns the reducer still holds. Their hidden entries stay too, since
    ///   hiding is final for a Turn, not for a row: a read Trae row absent for one refresh while its
    ///   companion reconnected came back unread (2026-09-16). A hidden entry books no re-check.
    nonisolated mutating func retain(sessionIDs: Set<String>, keepingReadAmong heldSessionIDs: Set<String> = []) {
        entries = entries.filter {
            sessionIDs.contains($0.key) || ($0.value.isHidden && heldSessionIDs.contains($0.key))
        }
    }

    /// Whether this gate has anything to say about a row in this status. Internal so a caller can
    /// skip assembling expensive read state when no such row is listed.
    nonisolated static func isTerminal(_ status: SessionStatus) -> Bool {
        status == .completed
    }
}
