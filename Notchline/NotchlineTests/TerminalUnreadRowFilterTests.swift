import Foundation
import Testing
@testable import Notchline

/// The rules every Provider shares about which finished rows stay listed until
/// they have been read (``TerminalUnreadRowFilter``). Each product's own suite
/// still pins its verdicts; these pin what no product may do differently.
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

    /// A row the user removed is still reported, never asked about, and books
    /// nothing — the removal is the store's record and the re-check is the
    /// product's cost (CR-Fable-003, CR-Fable-004).
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

    /// With no finished row listed, nothing is asked and the gate is emptied:
    /// an entry left from an earlier refresh must not go on booking a re-check.
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

    /// A row nothing can speak for is shown and kept out of the gate, so it
    /// books no re-check for a question with no possible answer
    /// (CR-Fable-036).
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

    /// The gate is asked about the thread, not the row: a finished Turn with a
    /// subagent still working stays listed however read its answer is, and a
    /// finished one with nothing running and no unread mark leaves once the
    /// settling window has passed.
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
