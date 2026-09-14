import Foundation
import Testing
@testable import Notchline

/// Package 4 of `docs/product-generalisation-plan.md`: the Hooks answer channel.
struct AnswerChannelTests {
    private struct LiveSource: MonitoringLifecycleSource {
        let repository: MonitoringRepository
        func gate(productName: String) async -> MonitoringSourceGate { .open(nil) }
        func disconnect() {}
    }
    private struct OpenProduct: ProductPresenceReporting {
        func presence() async -> AgentPresence { .open }
    }

    private let t0 = Date(timeIntervalSince1970: 1_757_000_000)

    private func repository(clock: any MonitorClock) -> (MonitoringRepository, URL) {
        let root = URL(fileURLWithPath: "/tmp").appendingPathComponent("cin-chan-\(UUID().uuidString.prefix(8))")
        let repository = MonitoringRepository(
            paths: HookIntegrationPaths(
                supportDirectory: root.appendingPathComponent("AS"),
                hooksConfiguration: root.appendingPathComponent("settings.json"),
                agent: .claudeCode
            ),
            clock: clock,
            vocabulary: ClaudeCodeHookVocabulary()
        )
        return (repository, root)
    }

    private func holdApproval(
        in repository: MonitoringRepository, at time: Date, on pair: AnsweringSocketPair
    ) async throws -> AgentRequest {
        func deliver(_ object: [String: Any], on descriptor: Int32? = nil) throws {
            _ = repository.deliver(try JSONSerialization.data(withJSONObject: object), at: time, on: descriptor)
        }
        try deliver(["hook_event_name": "UserPromptSubmit", "session_id": "s-1", "prompt_id": "t-1"])
        try deliver([
            "hook_event_name": "PreToolUse", "session_id": "s-1", "prompt_id": "t-1",
            "tool_name": "Bash", "tool_use_id": "call-1", "tool_input": ["command": "ls"]
        ])
        try deliver([
            "hook_event_name": "PermissionRequest", "session_id": "s-1", "prompt_id": "t-1",
            "tool_name": "Bash", "tool_input": ["command": "ls"]
        ], on: pair.app)
        return try #require(await repository.drainDeliveredEvents().turns.first?.requestAwaitingAnAnswer)
    }

    /// A fully written, closed write is `sent` and nothing stronger: no status moves, and the
    /// request stops offering an answer.
    @Test func aWrittenAnswerIsSentAndNoMore() async throws {
        let (repository, root) = repository(clock: TestClock(now: t0))
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try AnsweringSocketPair()
        defer { pair.closePeer() }
        let request = try await holdApproval(in: repository, at: t0, on: pair)
        let handle = try #require(request.answerHandle)
        #expect(handle.issuer != AnswerHandle.unissued)

        #expect(await repository.answer(.grant, on: handle) == .sent)
        let sent = try #require(pair.readFromPeer())
        #expect(String(decoding: sent, as: UTF8.self).contains(#""behavior":"allow""#))
        let after = try #require(await repository.observedState().turns.first)
        #expect(after.sessionStatus == .approvalNeeded, "no optimistic lifecycle transition")
        #expect(after.requestAwaitingAnAnswer?.canBeAnswered == false)
        #expect(after.requestAwaitingAnAnswer?.form == request.form, "the request stays readable")
    }

    /// A peer gone before the write is `expired(.peerGone)`, and nothing was sent.
    @Test func aPeerThatWentAwayExpiresTheHandle() async throws {
        let (repository, root) = repository(clock: TestClock(now: t0))
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try AnsweringSocketPair()
        let request = try await holdApproval(in: repository, at: t0, on: pair)
        let handle = try #require(request.answerHandle)
        pair.closePeer()

        #expect(await repository.answer(.grant, on: handle) == .expired(.peerGone))
        #expect(await repository.observedState().turns.first?.requestAwaitingAnAnswer?.canBeAnswered == false)
        #expect(await repository.answer(.grant, on: handle) == .expired(.notHeld))
    }

    @Test func aHandleIsSpentByOneAttempt() async throws {
        let (repository, root) = repository(clock: TestClock(now: t0))
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try AnsweringSocketPair()
        defer { pair.closePeer() }
        let handle = try #require(await holdApproval(in: repository, at: t0, on: pair).answerHandle)
        #expect(await repository.answer(.refuse(nil), on: handle) == .sent)
        #expect(await repository.answer(.grant, on: handle) == .expired(.notHeld))
        let sent = try #require(pair.readFromPeer())
        #expect(String(decoding: sent, as: UTF8.self).components(separatedBy: "hookEventName").count == 2)
        #expect(pair.readFromPeer() == nil)
    }

    /// A handle another channel minted addresses nothing here, even if its number matches.
    @Test func aHandleFromAnotherIssuerAddressesNothing() async throws {
        let (first, firstRoot) = repository(clock: TestClock(now: t0))
        let (second, secondRoot) = repository(clock: TestClock(now: t0))
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }
        let firstPair = try AnsweringSocketPair()
        let secondPair = try AnsweringSocketPair()
        defer {
            firstPair.closePeer()
            secondPair.closePeer()
        }
        let ours = try #require(await holdApproval(in: first, at: t0, on: firstPair).answerHandle)
        let theirs = try #require(await holdApproval(in: second, at: t0, on: secondPair).answerHandle)
        #expect(ours.ticket == theirs.ticket, "both channels counted to the same number")
        #expect(ours != theirs)

        #expect(await first.answer(.grant, on: theirs) == .expired(.notHeld))
        #expect(await first.answer(.grant, on: AnswerHandle(ticket: ours.ticket)) == .expired(.notHeld))
        #expect(!firstPair.peerHasInput(), "the connection this channel holds is untouched")
        #expect(await first.observedState().turns.first?.requestAwaitingAnAnswer?.canBeAnswered == true)
        #expect(await first.answer(.grant, on: ours) == .sent)
    }

    /// The product's window running out withdraws the handle and keeps the request; the refresh
    /// is booked as a deadline and consumed by it.
    @Test func aWindowThatRanOutWithdrawsTheHandleAndKeepsTheRequest() async throws {
        let clock = TestClock(now: t0)
        let (repository, root) = repository(clock: clock)
        defer { try? FileManager.default.removeItem(at: root) }
        let pair = try AnsweringSocketPair()
        defer { pair.closePeer() }
        let request = try await holdApproval(in: repository, at: t0, on: pair)
        let handle = try #require(request.answerHandle)
        let window = TimeInterval(ClaudeCodeHookVocabulary().answerWindowSeconds)
        #expect(repository.nextAnswerExpiry() == t0.addingTimeInterval(window))

        let runtime = ProductMonitoringRuntime(
            agent: .claudeCode, lifecycle: LiveSource(repository: repository),
            sessions: SeparateSessionReading(presence: OpenProduct(), admission: AdmitsEveryObservedThread()),
            clock: clock
        )
        #expect(await runtime.fetchSnapshot().sessions.first?.request?.canBeAnswered == true)
        #expect(await runtime.nextRefreshDeadline() == t0.addingTimeInterval(window))

        await clock.advance(by: window)
        let expired = try #require(await runtime.fetchSnapshot().sessions.first)
        #expect(expired.status == .approvalNeeded)
        #expect(expired.request?.form == request.form)
        #expect(expired.request?.canBeAnswered == false)
        #expect(repository.nextAnswerExpiry() == nil)
        #expect(await runtime.nextRefreshDeadline() == nil, "the deadline was consumed by the refresh that withdrew the handle")
        #expect(pair.peerHasInput(), "the connection was let go")
        #expect(pair.readFromPeer() == nil, "and nothing was written on it")
        #expect(await repository.answer(.grant, on: handle) == .expired(.notHeld))
        await runtime.disconnect()
    }

    @Test func onlyAcceptedAndSentMeanTheAnswerArrived() {
        #expect(AnswerOutcome.accepted.answerArrived)
        #expect(AnswerOutcome.sent.answerArrived)
        for outcome in [
            AnswerOutcome.expired(.peerGone), .expired(.timedOut), .expired(.notHeld),
            .rejected("no"), .unsupportedOperation, .uncertain
        ] {
            #expect(!outcome.answerArrived)
        }
    }
}
