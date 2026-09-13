import Foundation
import Testing
@testable import Notchline

@MainActor
struct TraeReadEvidenceTests {
    private let end = Date(timeIntervalSince1970: 1_789_270_000)
    private func candidate(_ n: Int = 1, turn: Int = 2, status: SessionStatus = .completed) -> ReadGateCandidate {
        ReadGateCandidate(row: MonitoredSession(agent: .trae, threadID: String(repeating: String(n), count: 24),
            turnID: String(repeating: String(turn), count: 24), projectName: "Test", title: "Test", preview: nil,
            status: status, startedAt: end.addingTimeInterval(-10)), turnEndedAt: end, terminalBoundaryAt: end)
    }
    private func proof(_ c: ReadGateCandidate, window: Int = 1, at: Date? = nil) -> TraeReadProof {
        TraeReadProof(windowID: window, threadID: c.row.threadID, turnID: c.row.turnID,
                     messageID: String(repeating: "3", count: 24), observedAt: (at ?? end.addingTimeInterval(3)).timeIntervalSince1970)
    }
    private struct Screen: ScreenAvailabilityReporting {
        let available: Bool
        func isAvailable() -> Bool { available }
        func changeEvents() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    }
    private actor Focus: DesktopReadingReporting {
        var values: [Bool]
        init(_ values: [Bool]) { self.values = values }
        func isInFrontOfTheUser() -> Bool { values.count > 1 ? values.removeFirst() : values[0] }
    }
    private actor Reader: TraeReadReporting {
        var proofs: [TraeReadProof]
        var calls = 0
        init(_ proofs: [TraeReadProof]) { self.proofs = proofs }
        func readCompletions() -> [TraeReadProof] { calls += 1; return proofs }
    }
    private func shown(_ c: [ReadGateCandidate], _ j: ReadEvidenceJudgement, at: Date,
                       filter: inout TerminalUnreadRowFilter) -> [MonitoredSession] {
        filter.rows(c, dismissedRowIDs: [], now: at) { j.verdicts[$0.row.id] ?? .cannotBeAsked }
    }

    @Test func proofFromAnotherWindowOnlyRetiresTheMatchingCompletedTurn() async {
        let a = candidate(), b = candidate(4, turn: 5)
        let reader = Reader([proof(b, window: 2)])
        let source = TraeReadEvidence(screen: Screen(available: true), foreground: Focus([true]), transport: reader)
        let now = end.addingTimeInterval(3)
        var filter = TerminalUnreadRowFilter(timing: .standard)
        let j = await source.verdicts(for: [a,b], now: now)
        #expect(shown([a,b],j,at:now,filter:&filter).map(\.id) == [a.row.id])
        #expect(await reader.calls == 1)
        let unavailable = ReadEvidenceJudgement(verdicts: [b.row.id:.judged(by:.unavailable("peer closed"))], diagnostic:nil)
        #expect(shown([b],unavailable,at:now,filter:&filter).isEmpty, "A retired Turn does not reappear after losing focus")
    }
    @Test func backgroundLockedAndInFlightFocusLossCannotRead() async {
        for (screen, focus) in [(false,[true]), (true,[false]), (true,[true,false])] {
            let c = candidate(), reader = Reader([proof(candidate())])
            let source = TraeReadEvidence(screen: Screen(available: screen), foreground: Focus(focus), transport: reader)
            var filter = TerminalUnreadRowFilter(timing: .standard)
            let now = end.addingTimeInterval(3), j = await source.verdicts(for: [c], now: now)
            #expect(shown([c],j,at:now,filter:&filter).count == 1)
            #expect(await reader.calls == (focus.count == 2 ? 1 : 0))
            if !screen { #expect(filter.nextDeadline(now: now, screenIsAvailable: false) == nil) }
        }
    }
    @Test func activeStatusesDoNotQueryOrRetireAndNewerTurnCannotUseOldProof() async {
        let reader = Reader([proof(candidate())])
        let source = TraeReadEvidence(screen: Screen(available: true), foreground: Focus([true]), transport: reader)
        for status in [SessionStatus.running,.approvalNeeded,.inputNeeded] {
            let c = candidate(status:status)
            #expect(await source.verdicts(for:[c],now:end).verdicts.isEmpty)
        }
        #expect(await reader.calls == 0)
        let c = candidate(turn:8), now = end.addingTimeInterval(3)
        let j = await source.verdicts(for:[c],now:now)
        var filter = TerminalUnreadRowFilter(timing:.standard)
        #expect(shown([c],j,at:now,filter:&filter).count == 1)
    }
    @Test func renderPendingDoesNotBypassTheTwoSecondSettlingInterval() async {
        let c = candidate(), missing = Reader([])
        var filter = TerminalUnreadRowFilter(timing:.standard)
        let pending = TraeReadEvidence(screen:Screen(available:true),foreground:Focus([true]),transport:missing)
        let initial = await pending.verdicts(for:[c],now:end)
        #expect(shown([c],initial,at:end,filter:&filter).count == 1)
        let early = end.addingTimeInterval(0.1)
        let ready = TraeReadEvidence(screen:Screen(available:true),foreground:Focus([true]),transport:Reader([proof(c,at:early)]))
        let j = await ready.verdicts(for:[c],now:early)
        #expect(shown([c],j,at:early,filter:&filter).count == 1)
        #expect(shown([c],j,at:end.addingTimeInterval(2),filter:&filter).isEmpty)
    }
    @Test func proofBoundaryRejectsWrongMessageStaleFutureAndNonterminalData() {
        let c = candidate(), p = proof(c)
        let turn = TraeDisplayedTurn(threadID:c.row.threadID,turnID:c.row.turnID,messageID:p.messageID,
            userMessageID:String(repeating:"4",count:24),title:"Test",folder:nil,status:"completed",startedAt:nil,
            endedAt:end.timeIntervalSince1970,historical:false,preview:nil,requests:[])
        let requested = end.addingTimeInterval(2.9), received = end.addingTimeInterval(3.1)
        #expect(p.matches(turn,requestedAt:requested,receivedAt:received))
        #expect(!p.matches(turn,requestedAt:received,receivedAt:received))
        #expect(!p.matches(turn,requestedAt:requested,receivedAt:requested))
        #expect(!p.matches(turn,requestedAt:end,receivedAt:received))
        let wrong = TraeReadProof(windowID:1,threadID:p.threadID,turnID:p.turnID,messageID:String(repeating:"9",count:24),observedAt:p.observedAt)
        #expect(!wrong.matches(turn,requestedAt:requested,receivedAt:received))
    }
}
