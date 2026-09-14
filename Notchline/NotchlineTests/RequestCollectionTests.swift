import Foundation
import Testing
@testable import Notchline

/// Package 2 of `docs/product-generalisation-plan.md`: requests keyed by identity, one opened
/// deterministically, each resolved alone.
struct RequestCollectionTests {
    private let t0 = Date(timeIntervalSince1970: 1_757_000_000)

    private enum Kind { case input, approval }

    private func started(_ repository: MonitoringRepository, thread: String = "thread", turn: String = "turn") {
        repository.submit(MonitoringEvidence(
            signal: .turnStarted, threadID: thread, observedAt: t0, turnID: turn
        ), in: repository.observationEpoch)
    }

    private func open(
        _ repository: MonitoringRepository, _ kind: Kind, call: String, at offset: TimeInterval,
        thread: String = "thread", turn: String = "turn", agent: String? = nil,
        requestID: String? = nil, ticket: HookReplyRegistry.Ticket? = nil, body: String? = nil
    ) {
        repository.submit(MonitoringEvidence(
            signal: kind == .input ? .inputWaitOpened : .approvalWaitOpened,
            threadID: thread, observedAt: t0.addingTimeInterval(offset), turnID: turn,
            agentID: agent, toolUseID: call, requestID: requestID, toolName: "Bash",
            request: AgentRequest(
                id: call, toolName: "Bash",
                form: kind == .input ? .question(body ?? call) : .command(body ?? call)
            ),
            answerHandle: ticket.map { AnswerHandle(ticket: $0) },
            // A held connection that declared nothing is reading-only (package 3).
            answerOperations: kind == .input ? .questionAnswers : .decision
        ), in: repository.observationEpoch)
    }

    private func close(_ repository: MonitoringRepository, call: String, at offset: TimeInterval,
                       thread: String = "thread", turn: String = "turn", agent: String? = nil) {
        repository.submit(MonitoringEvidence(
            signal: .toolCallClosed, threadID: thread, observedAt: t0.addingTimeInterval(offset),
            turnID: turn, agentID: agent, toolUseID: call
        ), in: repository.observationEpoch)
    }

    private func turn(_ repository: MonitoringRepository, _ thread: String = "thread") async throws -> MonitoredTurnState {
        try #require(await repository.drainDeliveredEvents().turns.first { $0.threadID == thread })
    }

    @Test func standaloneRequestsNeedNoToolCallAndResolveByTheirOwnIdentity() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        started(repository)
        let epoch = repository.observationEpoch
        for (index, signal) in [MonitoringSignal.inputWaitOpened, .approvalWaitOpened].enumerated() {
            repository.submit(MonitoringEvidence(signal: signal, threadID: "thread",
                observedAt: t0.addingTimeInterval(Double(index + 1)), turnID: "turn",
                requestID: "request-\(index)", request: AgentRequest(id: "native", toolName: nil,
                    form: signal == .inputWaitOpened ? .question("Which region?") : .document("Review this plan"))), in: epoch)
        }
        var state = try await turn(repository)
        #expect(state.waits.openCalls.isEmpty)
        #expect(state.requestsAwaitingAnAnswer.map(\.id) == ["request-0", "request-1"])
        #expect(state.waits.inputs.first?.toolUseID == nil)
        #expect(state.waits.approvals.first?.toolUseID == nil)
        // An unrelated tool result is no resolution of a standalone request.
        close(repository, call: "request-0", at: 3)
        #expect(try await turn(repository).requestsAwaitingAnAnswer.count == 2)
        repository.submit(MonitoringEvidence(signal: .requestResolved, threadID: "thread",
            observedAt: t0.addingTimeInterval(4), turnID: "turn", requestID: "request-0"), in: epoch)
        state = try await turn(repository)
        #expect(state.status == .approvalNeeded)
        #expect(state.requestsAwaitingAnAnswer.map(\.id) == ["request-1"])
        repository.submit(MonitoringEvidence(signal: .turnEnded, threadID: "thread",
            observedAt: t0.addingTimeInterval(5), turnID: "turn"), in: epoch)
        #expect(try await turn(repository).requestsAwaitingAnAnswer.isEmpty)
    }

    @Test func requestOccurrencesSeparateProducersRevisionsAndReopenedIdentities() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        started(repository)
        repository.submit(MonitoringEvidence(signal: .subagentStarted, threadID: "thread",
            observedAt: t0, turnID: "child-turn", agentID: "child"), in: repository.observationEpoch)
        func ask(_ time: Double, producer: String? = nil, revision: String = "v1") {
            repository.submit(MonitoringEvidence(signal: .approvalWaitOpened, threadID: "thread",
                observedAt: t0.addingTimeInterval(time), turnID: producer == nil ? "turn" : "child-turn",
                agentID: producer, requestID: "same", requestRevision: revision,
                request: AgentRequest(id: "same", toolName: nil, form: .document("Identical words"))),
                in: repository.observationEpoch)
        }
        ask(1)
        ask(2, producer: "child")
        var state = try await turn(repository)
        let original = try #require(state.requestsAwaitingAnAnswer.first)
        #expect(state.requestsAwaitingAnAnswer.count == 2)
        #expect(original.asked != state.requestsAwaitingAnAnswer[1].asked)
        #expect(state.subagentSlots["child"]?.openCalls.isEmpty == true)
        ask(3)
        #expect(try await turn(repository).requestsAwaitingAnAnswer.first?.identity == original.identity)
        ask(4, revision: "v2")
        let revised = try #require(try await turn(repository).requestsAwaitingAnAnswer.first)
        #expect(revised.identity != original.identity)
        repository.submit(MonitoringEvidence(signal: .requestResolved, threadID: "thread",
            observedAt: t0.addingTimeInterval(5), turnID: "turn", requestID: "same", requestRevision: "v1"),
            in: repository.observationEpoch)
        #expect(try await turn(repository).requestsAwaitingAnAnswer.first?.identity == revised.identity)
        repository.submit(MonitoringEvidence(signal: .requestResolved, threadID: "thread",
            observedAt: t0.addingTimeInterval(6), turnID: "turn", requestID: "same", requestRevision: "v2"),
            in: repository.observationEpoch)
        _ = try await turn(repository)
        ask(7, revision: "v2")
        state = try await turn(repository)
        #expect(state.requestsAwaitingAnAnswer.first?.identity != revised.identity)
        #expect(state.subagentsAwaitingApprovalCount == 1)
        await repository.resetIntegrationObservation(clearTurns: true)
        started(repository)
        ask(8, revision: "v2")
        #expect(try await turn(repository).requestsAwaitingAnAnswer.first?.identity?.epoch != original.identity?.epoch)
    }

    @Test func anUnreadableStandaloneWaitStillResolvesItsNativeRevision() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        started(repository)
        let epoch = repository.observationEpoch
        repository.submit(MonitoringEvidence(signal: .inputWaitOpened, threadID: "thread",
            observedAt: t0.addingTimeInterval(1), turnID: "turn", requestID: "r", requestRevision: "v2"), in: epoch)
        #expect(try await turn(repository).status == .inputNeeded)
        repository.submit(MonitoringEvidence(signal: .requestResolved, threadID: "thread",
            observedAt: t0.addingTimeInterval(2), turnID: "turn", requestID: "r", requestRevision: "v1"), in: epoch)
        #expect(try await turn(repository).status == .inputNeeded)
        repository.submit(MonitoringEvidence(signal: .requestResolved, threadID: "thread",
            observedAt: t0.addingTimeInterval(3), turnID: "turn", requestID: "r", requestRevision: "v2"), in: epoch)
        #expect(try await turn(repository).status == .running)
    }

    /// The status stands until the last one goes.
    @Test func twoApprovalsOnOneProducerResolveOneAtATime() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        started(repository)
        open(repository, .approval, call: "a", at: 1)
        open(repository, .approval, call: "b", at: 2)
        var state = try await turn(repository)
        #expect(state.status == .approvalNeeded)
        #expect(state.waits.approvals.count == 2)
        #expect(state.requestsAwaitingAnAnswer.map(\.id) == ["a", "b"])
        #expect(state.requestAwaitingAnAnswer?.id == "a")

        close(repository, call: "a", at: 3)
        state = try await turn(repository)
        #expect(state.status == .approvalNeeded, "resolving one request cannot clear another")
        #expect(state.requestsAwaitingAnAnswer.map(\.id) == ["b"])

        close(repository, call: "b", at: 4)
        state = try await turn(repository)
        #expect(state.status == .running)
        #expect(state.requestsAwaitingAnAnswer.isEmpty)
    }

    @Test func twoQuestionsOnOneProducerResolveOneAtATime() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        started(repository)
        open(repository, .input, call: "q1", at: 1)
        open(repository, .input, call: "q2", at: 2)
        var state = try await turn(repository)
        #expect(state.status == .inputNeeded)
        #expect(state.requestsAwaitingAnAnswer.map(\.id) == ["q1", "q2"])
        close(repository, call: "q1", at: 3)
        state = try await turn(repository)
        #expect(state.status == .inputNeeded)
        #expect(state.requestAwaitingAnAnswer?.id == "q2")
        close(repository, call: "q2", at: 4)
        #expect(try await turn(repository).status == .running)
    }

    @Test func aQuestionOutranksAnApprovalAndEachResolvesAlone() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        started(repository)
        open(repository, .approval, call: "a", at: 1)
        open(repository, .input, call: "q", at: 2)
        var state = try await turn(repository)
        #expect(state.status == .inputNeeded)
        #expect(state.requestsAwaitingAnAnswer.map(\.id) == ["q", "a"])
        close(repository, call: "q", at: 3)
        state = try await turn(repository)
        #expect(state.status == .approvalNeeded)
        #expect(state.requestsAwaitingAnAnswer.map(\.id) == ["a"])
        close(repository, call: "elsewhere", at: 4)
        #expect(try await turn(repository).status == .approvalNeeded)
    }

    /// Claude Code's `AskUserQuestion` also files a `PermissionRequest` for the same call; that is
    /// one request, not `Request 1 of 2` (Claude Desktop, 2026-09-12).
    @Test func aQuestionsOwnPermissionPromptIsNotASecondRequest() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        started(repository)
        open(repository, .input, call: "ask", at: 1)
        repository.submit(MonitoringEvidence(
            signal: .approvalWaitInferred, threadID: "thread", observedAt: t0.addingTimeInterval(2),
            turnID: "turn", toolName: "Bash",
            request: AgentRequest(id: "", toolName: "Bash", form: .question("ask")),
            answerHandle: AnswerHandle(ticket: 7), answerOperations: .questionAnswers
        ), in: repository.observationEpoch)
        var state = try await turn(repository)
        #expect(state.status == .inputNeeded)
        #expect(state.requestsAwaitingAnAnswer.map(\.id) == ["ask"])
        #expect(state.requestAwaitingAnAnswer?.answerHandle == AnswerHandle(ticket: 7))
        // An approval about some other call is still a request of its own.
        open(repository, .approval, call: "other", at: 3)
        #expect(try await turn(repository).requestsAwaitingAnAnswer.map(\.id) == ["ask", "other"])
        close(repository, call: "ask", at: 4)
        state = try await turn(repository)
        #expect(state.requestsAwaitingAnAnswer.map(\.id) == ["other"])
    }

    @Test func identicalIdentitiesUnderDifferentProducersAndThreadsStayApart() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        started(repository, thread: "one")
        started(repository, thread: "two")
        repository.submit(MonitoringEvidence(
            signal: .subagentStarted, threadID: "one", observedAt: t0, turnID: "child-turn", agentID: "child"
        ), in: repository.observationEpoch)
        open(repository, .approval, call: "call-main", at: 1, thread: "one", requestID: "r1")
        open(repository, .approval, call: "call-child", at: 2, thread: "one", agent: "child", requestID: "r1")
        open(repository, .approval, call: "call-two", at: 3, thread: "two", requestID: "r1")
        var one = try await turn(repository, "one")
        #expect(one.requestsAwaitingAnAnswer.map(\.id) == ["r1", "r1"], "the turn's own first, then the subagent's")
        #expect(one.subagentsAwaitingApprovalCount == 1)

        repository.submit(MonitoringEvidence(
            signal: .requestResolved, threadID: "one", observedAt: t0.addingTimeInterval(4),
            turnID: "turn", requestID: "r1"
        ), in: repository.observationEpoch)
        one = try await turn(repository, "one")
        #expect(one.waits.approvals.isEmpty, "the turn's own r1 was resolved")
        #expect(one.subagentsAwaitingApprovalCount == 1, "the subagent's r1 was not")
        #expect(one.requestsAwaitingAnAnswer.count == 1)
        #expect(try await turn(repository, "two").requestsAwaitingAnAnswer.count == 1, "nor the other Thread's")
    }

    @Test func duplicateAndOutOfOrderResolutionsChangeNothing() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        started(repository)
        open(repository, .approval, call: "a", at: 2)
        open(repository, .approval, call: "b", at: 3)
        // Dated before the waits opened: rejected as a late event.
        close(repository, call: "a", at: 1)
        #expect(try await turn(repository).requestsAwaitingAnAnswer.map(\.id) == ["a", "b"])
        close(repository, call: "a", at: 4)
        close(repository, call: "a", at: 5)
        close(repository, call: "never-opened", at: 6)
        let state = try await turn(repository)
        #expect(state.requestsAwaitingAnAnswer.map(\.id) == ["b"])
        #expect(state.status == .approvalNeeded)
    }

    @Test func aReplacementWearingAnExistingIdentityTakesItsPlace() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        started(repository)
        open(repository, .approval, call: "a", at: 1, body: "ls")
        open(repository, .approval, call: "b", at: 2, body: "pwd")
        open(repository, .approval, call: "a", at: 3, body: "rm -rf build")
        let state = try await turn(repository)
        #expect(state.waits.approvals.count == 2)
        #expect(state.requestsAwaitingAnAnswer.map(\.id) == ["a", "b"])
        #expect(state.requestsAwaitingAnAnswer.first?.form == .command("rm -rf build"))
    }

    @Test func aRequestResolvedByItsOwnIdentityEndsOnlyThatOne() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        started(repository)
        open(repository, .input, call: "call-1", at: 1, requestID: "req-1")
        open(repository, .input, call: "call-2", at: 2, requestID: "req-2")
        var state = try await turn(repository)
        #expect(state.requestsAwaitingAnAnswer.map(\.id) == ["req-1", "req-2"], "the request carries its own identity")
        repository.submit(MonitoringEvidence(
            signal: .requestResolved, threadID: "thread", observedAt: t0.addingTimeInterval(3),
            turnID: "turn", requestID: "req-1"
        ), in: repository.observationEpoch)
        state = try await turn(repository)
        #expect(state.requestsAwaitingAnAnswer.map(\.id) == ["req-2"])
        #expect(state.status == .inputNeeded)
        // The call it concerned is still open; only the request ended.
        #expect(state.waits.openCalls.map(\.id) == ["call-1", "call-2"])
        close(repository, call: "call-2", at: 4)
        #expect(try await turn(repository).status == .running)
    }

    @Test func anIdlessApprovalAboutTwoOpenCallsOfOneToolIsNotPaired() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        started(repository)
        func announce(_ call: String, at offset: TimeInterval) {
            repository.submit(MonitoringEvidence(
                signal: .toolCallOpened, threadID: "thread", observedAt: t0.addingTimeInterval(offset),
                turnID: "turn", toolUseID: call, toolName: "Bash"
            ), in: repository.observationEpoch)
        }
        func ask(at offset: TimeInterval) {
            repository.submit(MonitoringEvidence(
                signal: .approvalWaitInferred, threadID: "thread", observedAt: t0.addingTimeInterval(offset),
                turnID: "turn", toolName: "Bash",
                request: AgentRequest(id: "", toolName: "Bash", form: .command("rm -rf build"))
            ), in: repository.observationEpoch)
        }
        announce("c1", at: 1)
        announce("c2", at: 2)
        ask(at: 3)
        var state = try await turn(repository)
        #expect(state.status == .running, "two calls it could equally be about: no pairing, no wait")
        #expect(state.waits.approvals.isEmpty)
        #expect(state.waits.openCalls.count == 2, "the calls stay open")

        close(repository, call: "c1", at: 4)
        ask(at: 5)
        state = try await turn(repository)
        #expect(state.status == .approvalNeeded, "one call left: paired")
        #expect(state.requestAwaitingAnAnswer?.id == "c2")

        // A dialogue queued behind a filed one pairs with the call that has no approval yet.
        announce("c3", at: 6)
        ask(at: 7)
        state = try await turn(repository)
        #expect(state.requestsAwaitingAnAnswer.map(\.id) == ["c2", "c3"])
    }

    /// A request answered from here falls behind one still answerable.
    @Test func everyConnectionIsRetainedWhileOneRequestIsDrawn() async throws {
        final class Retained: MonitoringBoundaryObserver, @unchecked Sendable {
            let lock = NSLock()
            var retained: Set<AnswerHandle> = []
            var hasObservedEvidence: Bool { true }
            func didApply(_ evidence: MonitoringEvidence, accepted: Bool) {}
            func didDiscard(_ evidence: [MonitoringEvidence]) {}
            func retainAnswerHandles(_ handles: Set<AnswerHandle>) {
                lock.lock(); retained = handles; lock.unlock()
            }
            func expiredAnswerHandles(at now: Date) -> Set<AnswerHandle> { [] }
            func nextAnswerHandleExpiry() -> Date? { nil }
            func diagnostic(for statistics: MonitoringStatistics) -> String? { nil }
            func reset() {}
        }
        let boundary = Retained()
        let repository = MonitoringRepository(policy: .explicit, boundary: boundary)
        started(repository)
        open(repository, .approval, call: "a", at: 1, ticket: 1)
        open(repository, .approval, call: "b", at: 2, ticket: 2)
        var state = try await turn(repository)
        #expect(Set(state.heldAnswerHandles) == [AnswerHandle(ticket: 1), AnswerHandle(ticket: 2)])
        #expect(state.requestAwaitingAnAnswer?.id == "a")
        boundary.lock.lock()
        let retained = boundary.retained
        boundary.lock.unlock()
        #expect(retained == [AnswerHandle(ticket: 1), AnswerHandle(ticket: 2)], "no connection is let go for not being drawn")

        await repository.withdrawAnswerHandle(AnswerHandle(ticket: 1))
        state = await repository.observedState().turns[0]
        #expect(state.requestsAwaitingAnAnswer.map(\.id) == ["b", "a"])
        #expect(state.requestsAwaitingAnAnswer.map(\.canBeAnswered) == [true, false])
        #expect(state.status == .approvalNeeded)
    }

    @Test func selectionIsStableUnderArrivalsOfEqualOrLowerRank() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        started(repository)
        open(repository, .approval, call: "a", at: 2)
        #expect(try await turn(repository).requestAwaitingAnAnswer?.id == "a")
        open(repository, .approval, call: "b", at: 3)
        #expect(try await turn(repository).requestAwaitingAnAnswer?.id == "a", "a newer approval does not displace the older")
        // Arrival order, whatever the clocks read or the identities sort.
        open(repository, .approval, call: "0", at: 3)
        #expect(try await turn(repository).requestsAwaitingAnAnswer.map(\.id) == ["a", "b", "0"])
        open(repository, .input, call: "q", at: 4)
        #expect(try await turn(repository).requestAwaitingAnAnswer?.id == "q", "the turn's own question outranks its approvals")
    }
}
