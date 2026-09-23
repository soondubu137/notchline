import Foundation
import Testing
@testable import Notchline

/// Rules no Provider may apply differently (``TerminalUnreadRowFilter``).
struct TerminalUnreadRowFilterTests {
    private let t0 = Date(timeIntervalSince1970: 1_757_000_000)

    private func candidate(
        _ thread: String,
        status: SessionStatus,
        endedAt: Date,
        runningSubagents: Int = 0
    ) -> ReadGateCandidate {
        ReadGateCandidate(
            row: MonitoredSession(
                agent: .antigravity,
                threadID: thread,
                turnID: "\(thread)-turn",
                projectName: "demo",
                title: "Fix the build",
                preview: nil,
                status: status,
                startedAt: endedAt.addingTimeInterval(-30),
                runningSubagentCount: runningSubagents
            ),
            turnEndedAt: endedAt,
            terminalBoundaryAt: endedAt
        )
    }

    private func unread(_ threads: Set<String>, at now: Date) -> DesktopUnreadStateSnapshot {
        DesktopUnreadStateSnapshot(unreadThreadIDs: threads, source: .current, currentAsOf: now)
    }

    /// The removal is the store's record; the re-check is the product's cost (CR-Fable-003,
    /// CR-Fable-004).
    @Test
    func aDismissedRowIsReportedButNeverJudged() {
        var filter = TerminalUnreadRowFilter(timing: .standard)
        let finished = candidate("t1", status: .completed, endedAt: t0)
        let now = t0.addingTimeInterval(1)
        var asked: [String] = []

        let rows = filter.rows([finished], dismissedRowIDs: [finished.row.id], now: now) {
            asked.append($0.row.threadID)
            return .judged(by: unread(["t1"], at: now))
        }

        #expect(rows.map(\.id) == [finished.row.id])
        #expect(asked.isEmpty)
        #expect(filter.nextDeadline(now: now, screenIsAvailable: true) == nil)
    }

    /// A gate entry left from an earlier refresh must not go on booking a re-check.
    @Test
    func aListOfRunningRowsAsksNothingAndEmptiesTheGate() {
        var filter = TerminalUnreadRowFilter(timing: .standard)
        let now = t0.addingTimeInterval(1)
        _ = filter.rows([candidate("t1", status: .completed, endedAt: t0)], dismissedRowIDs: [], now: now) { _ in
            .judged(by: unread(["t1"], at: now))
        }
        #expect(filter.nextDeadline(now: now, screenIsAvailable: true) != nil)

        var asked = 0
        let rows = filter.rows([candidate("t1", status: .running, endedAt: t0)], dismissedRowIDs: [], now: now) { _ in
            asked += 1
            return .judged(by: unread([], at: now))
        }

        #expect(rows.count == 1)
        #expect(asked == 0)
        #expect(filter.nextDeadline(now: now, screenIsAvailable: true) == nil)
    }

    /// No re-check for a question with no possible answer (CR-Fable-036).
    @Test
    func aRowNothingCanAnswerForIsShownAndBooksNothing() {
        var filter = TerminalUnreadRowFilter(timing: .standard)
        let now = t0.addingTimeInterval(60)

        let rows = filter.rows([candidate("t1", status: .completed, endedAt: t0)], dismissedRowIDs: [], now: now) { _ in
            .cannotBeAsked
        }

        #expect(rows.count == 1)
        #expect(filter.nextDeadline(now: now, screenIsAvailable: true) == nil)
    }

    /// Hiding is final for the Turn, not the row: Trae's rows draw nothing while its companion
    /// reconnects, and a read row came back unread afterwards (2026-09-16).
    @Test
    func aReadTurnThatDrawsNoRowForARefreshIsStillReadWhenItReturns() {
        var filter = TerminalUnreadRowFilter(timing: .standard)
        let read = candidate("t1", status: .completed, endedAt: t0)
        let other = candidate("t2", status: .completed, endedAt: t0)
        let held: Set = [read.row.id, other.row.id]
        let now = t0.addingTimeInterval(60)
        let judgedRead: (ReadGateCandidate) -> ReadGateVerdict = { _ in .judged(by: self.unread([], at: now)) }
        #expect(filter.rows([read], dismissedRowIDs: [], now: now, heldRowIDs: held, verdict: judgedRead).isEmpty)

        // Nothing listed at all, then another finished row listed alone: the read Turn is in neither.
        _ = filter.rows([], dismissedRowIDs: [], now: now, heldRowIDs: held, verdict: judgedRead)
        let stillUnread: (ReadGateCandidate) -> ReadGateVerdict = { _ in .judged(by: self.unread(["t1", "t2"], at: now)) }
        #expect(filter.rows([other], dismissedRowIDs: [], now: now, heldRowIDs: held, verdict: stillUnread).map(\.threadID) == ["t2"])
        filter.reset(keepingReadAmong: held)

        // Back, with a reading that knows nothing of the earlier one.
        #expect(filter.rows([read, other], dismissedRowIDs: [], now: now, heldRowIDs: held, verdict: stillUnread)
            .map(\.threadID) == ["t2"])
    }

    /// Only a read verdict outlives its row, so an absent unread row books no re-check; and only
    /// while the reducer holds the Turn.
    @Test
    func onlyAHeldReadTurnKeepsItsEntryWhileUnlisted() {
        var filter = TerminalUnreadRowFilter(timing: .standard)
        let read = candidate("t1", status: .completed, endedAt: t0)
        let unreadRow = candidate("t2", status: .completed, endedAt: t0)
        let now = t0.addingTimeInterval(60)
        _ = filter.rows([read, unreadRow], dismissedRowIDs: [], now: now) {
            .judged(by: self.unread($0.row.threadID == "t2" ? ["t2"] : [], at: now))
        }
        #expect(filter.nextDeadline(now: now, screenIsAvailable: true) != nil)

        _ = filter.rows([], dismissedRowIDs: [], now: now, heldRowIDs: [read.row.id, unreadRow.row.id]) { _ in
            .cannotBeAsked
        }
        #expect(filter.nextDeadline(now: now, screenIsAvailable: true) == nil)

        // The reducer let the read Turn go; it is a stranger if it is ever listed again.
        _ = filter.rows([], dismissedRowIDs: [], now: now, heldRowIDs: []) { _ in .cannotBeAsked }
        #expect(filter.rows([read], dismissedRowIDs: [], now: now) { _ in
            .judged(by: self.unread(["t1"], at: now))
        }.count == 1)
    }

    /// A finished Turn with a subagent still working stays listed however read.
    @Test
    func theGateJudgesTheThreadsStatusNotTheRows() {
        var filter = TerminalUnreadRowFilter(timing: .standard)
        let now = t0.addingTimeInterval(60)
        let working = candidate("t1", status: .completed, endedAt: t0, runningSubagents: 1)
        let done = candidate("t2", status: .completed, endedAt: t0)

        let rows = filter.rows([working, done], dismissedRowIDs: [], now: now) { _ in
            .judged(by: unread([], at: now))
        }

        #expect(rows.map(\.threadID) == ["t1"])
    }
}
