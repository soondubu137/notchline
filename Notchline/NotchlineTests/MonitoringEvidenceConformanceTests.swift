import Foundation
import Testing
@testable import Notchline

/// A typed native source (no hooks, vocabulary, JSON or socket) through the shipping runtime
/// and reducer.
struct MonitoringEvidenceConformanceTests {
    private struct LiveSource: MonitoringLifecycleSource {
        let repository: MonitoringRepository
        func gate(productName: String) async -> MonitoringSourceGate { .open(nil) }
        func disconnect() {}
    }

    private struct OpenProduct: ProductPresenceReporting {
        func presence() async -> AgentPresence { .open }
    }

    private let t0 = Date(timeIntervalSince1970: 1_757_000_000)

    private func runtime(_ repository: MonitoringRepository) -> ProductMonitoringRuntime {
        ProductMonitoringRuntime(
            agent: .claudeCode,
            lifecycle: LiveSource(repository: repository),
            sessions: SeparateSessionReading(
                presence: OpenProduct(), admission: AdmitsEveryObservedThread()
            )
        )
    }

    @Test
    func typedLifecycleAndProgressUseTheSharedRowsWithoutInstallingAnything() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        let product = runtime(repository)
        let epoch = repository.observationEpoch
        #expect(!(product is any IntegrationConfiguring))
        #expect(await product.fetchSnapshot().sessions.isEmpty)

        repository.submit(MonitoringEvidence(
            signal: .turnStarted, threadID: "thread", observedAt: t0,
            turnID: "turn", prompt: "Fix the build", workingDirectory: "/Projects/demo"
        ), in: epoch)
        var snapshot = await product.fetchSnapshot()
        let started = try #require(snapshot.sessions.first)
        #expect(started.startedAt == t0)
        #expect(started.title == "Fix the build")
        #expect(started.projectName == "demo")
        #expect(snapshot.isConnected)
        #expect(snapshot.quota == .noneReported)

        repository.recordProgress(MonitoringProgress(
            threadID: "thread", turnID: "turn", messageID: "message", text: "Checking the build"
        ), in: epoch)
        snapshot = await product.fetchSnapshot()
        #expect(snapshot.sessions.first?.preview == "Checking the build")
        repository.submit(MonitoringEvidence(
            signal: .turnEnded, threadID: "thread", observedAt: t0.addingTimeInterval(9),
            turnID: "turn", finalText: "Build repaired"
        ), in: epoch)
        snapshot = await product.fetchSnapshot()
        #expect(snapshot.sessions.first?.status == .completed)
        #expect(snapshot.sessions.first?.finishedAt == t0.addingTimeInterval(9))
        #expect(snapshot.sessions.first?.preview == "Build repaired")
        #expect(await product.nextRefreshDeadline() == nil)
        #expect(await product.fetchSnapshot().sessions.count == 1, "no read evidence retires this row")
        await product.disconnect()
    }

    @Test
    func submissionOrderAndRetiredIdentitiesSurviveIndependentDrainTasks() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        let epoch = repository.observationEpoch
        // No await between submissions: actor scheduling cannot reorder the source's prefix.
        for index in 0..<100 {
            let time = t0.addingTimeInterval(Double(index * 2))
            repository.submit(MonitoringEvidence(
                signal: .turnStarted, threadID: "thread", observedAt: time,
                turnID: "turn-\(index)", prompt: "Request \(index)"
            ), in: epoch)
            repository.submit(MonitoringEvidence(
                signal: .turnEnded, threadID: "thread", observedAt: time.addingTimeInterval(1),
                turnID: "turn-\(index)"
            ), in: epoch)
        }
        repository.submit(MonitoringEvidence(
            signal: .turnStarted, threadID: "other", observedAt: t0, turnID: "independent"
        ), in: epoch)
        repository.submit(MonitoringEvidence(
            signal: .turnStarted, threadID: "thread", observedAt: t0.addingTimeInterval(300),
            turnID: "turn-0", prompt: "A late retired submission"
        ), in: epoch)
        let state = await repository.drainDeliveredEvents()
        let current = try #require(state.turns.first { $0.threadID == "thread" })
        #expect(current.turnID == "turn-99")
        #expect(current.promptPreview == "Request 99")
        #expect(current.status == .completed)
        #expect(state.turns.first { $0.threadID == "other" }?.status == .running)
        #expect(state.didConsumeEvents)
        #expect(await repository.drainDeliveredEvents().didConsumeEvents == false)
    }

    @Test
    func anOldObservationEpochCannotSubmitLifecycleOrProgress() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        let oldEpoch = repository.observationEpoch
        repository.submit(MonitoringEvidence(
            signal: .turnStarted, threadID: "thread", observedAt: t0, turnID: "old"
        ), in: oldEpoch)
        _ = await repository.drainDeliveredEvents()
        await repository.resetIntegrationObservation(clearTurns: true)
        let newEpoch = repository.observationEpoch
        #expect(newEpoch != oldEpoch)
        #expect(!repository.submit(MonitoringEvidence(
            signal: .turnStarted, threadID: "thread", observedAt: t0.addingTimeInterval(10),
            turnID: "old-callback"
        ), in: oldEpoch))
        repository.recordProgress(MonitoringProgress(
            threadID: "thread", turnID: nil, messageID: "old", text: "Stale words"
        ), in: oldEpoch)
        #expect(await repository.drainDeliveredEvents().turns.isEmpty)
        #expect(!((await repository.observedState()).hasObservedLiveEvent))
        repository.submit(MonitoringEvidence(
            signal: .turnStarted, threadID: "thread", observedAt: t0.addingTimeInterval(11),
            turnID: "new"
        ), in: newEpoch)
        let row = try #require(await runtime(repository).fetchSnapshot().sessions.first)
        #expect(row.turnID == "new")
        #expect(row.preview == nil)
    }

    @Test
    func typedRequestProjectionAndMatchingResolutionUseTheSameWaitRules() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        let product = runtime(repository)
        let epoch = repository.observationEpoch
        repository.submit(MonitoringEvidence(
            signal: .turnStarted, threadID: "thread", observedAt: t0, turnID: "turn"
        ), in: epoch)
        repository.submit(MonitoringEvidence(
            signal: .approvalWaitOpened, threadID: "thread", observedAt: t0.addingTimeInterval(1),
            turnID: "turn", toolUseID: "request",
            request: AgentRequest(id: "request", toolName: nil, form: .document("Review the plan"))
        ), in: epoch)
        let waiting = try #require(await product.fetchSnapshot().sessions.first)
        #expect(waiting.status == .approvalNeeded)
        #expect(waiting.request?.form == .document("Review the plan"))
        #expect(waiting.request?.canBeAnswered == false)
        repository.submit(MonitoringEvidence(
            signal: .toolCallClosed, threadID: "thread", observedAt: t0.addingTimeInterval(2),
            turnID: "turn", toolUseID: "unrelated"
        ), in: epoch)
        #expect(await product.fetchSnapshot().sessions.first?.status == .approvalNeeded)
        repository.submit(MonitoringEvidence(
            signal: .toolCallClosed, threadID: "thread", observedAt: t0.addingTimeInterval(3),
            turnID: "turn", toolUseID: "request"
        ), in: epoch)
        let resumed = try #require(await product.fetchSnapshot().sessions.first)
        #expect(resumed.status == .running)
        #expect(resumed.request == nil)
    }

    @Test
    func aSubagentsTurnAndContentCannotReplaceTheParent() async throws {
        let repository = MonitoringRepository(policy: .explicit)
        let epoch = repository.observationEpoch
        repository.submit(MonitoringEvidence(
            signal: .turnStarted, threadID: "thread", observedAt: t0, turnID: "parent"
        ), in: epoch)
        repository.submit(MonitoringEvidence(
            signal: .subagentStarted, threadID: "thread", observedAt: t0.addingTimeInterval(1),
            turnID: "child-turn", agentID: "child"
        ), in: epoch)
        repository.submit(MonitoringEvidence(
            signal: .approvalWaitOpened, threadID: "thread", observedAt: t0.addingTimeInterval(2),
            turnID: "child-turn", agentID: "child", toolUseID: "child-request",
            request: AgentRequest(id: "child-request", toolName: nil, form: .command("make"))
        ), in: epoch)
        repository.recordProgress(MonitoringProgress(
            threadID: "thread", turnID: "parent", messageID: "child-message",
            text: "Not the parent's words", producerID: "child"
        ), in: epoch)
        repository.submit(MonitoringEvidence(
            signal: .turnEnded, threadID: "thread", observedAt: t0.addingTimeInterval(3),
            turnID: "parent"
        ), in: epoch)
        let row = try #require(await runtime(repository).fetchSnapshot().sessions.first)
        #expect(row.turnID == "parent")
        #expect(row.status == .completed)
        #expect(row.runningSubagentCount == 1)
        #expect(row.subagentsAwaitingApprovalCount == 1)
        #expect(row.request?.id == "child-request")
        #expect(row.preview == nil)
    }

    @Test
    func recordConfirmationRedeemsOnlyAnAlreadyObservedHeldStart() async throws {
        let repository = MonitoringRepository(policy: MonitoringReductionPolicy(settlesHeldTurnsFromRecord: true))
        let epoch = repository.observationEpoch
        repository.submit(MonitoringEvidence(
            signal: .turnStarted, threadID: "thread", observedAt: t0, turnID: "first"
        ), in: epoch)
        repository.submit(MonitoringEvidence(
            signal: .turnStarted, threadID: "thread", observedAt: t0.addingTimeInterval(1),
            turnID: "held", prompt: "The next request"
        ), in: epoch)
        #expect(await repository.drainDeliveredEvents().turns.first?.turnID == "first")
        #expect(await repository.adoptTurnsOnRecord([TurnOnRecord(threadID: "thread", turnID: "unknown")]).turns.first?.turnID == "first")
        let adopted = await repository.adoptTurnsOnRecord([TurnOnRecord(threadID: "thread", turnID: "held")])
        #expect(adopted.turns.first?.turnID == "held")
        #expect(adopted.turns.first?.startedAt == t0.addingTimeInterval(1))
        #expect(adopted.turns.first?.promptPreview == "The next request")
    }

    @Test
    func typedCallEvidenceDoesNotInventAStartOrHookTrustDiagnostic() async {
        let repository = MonitoringRepository(policy: .explicit)
        let epoch = repository.observationEpoch
        for index in 0..<3 {
            repository.submit(MonitoringEvidence(
                signal: .toolCallClosed, threadID: "thread", observedAt: t0.addingTimeInterval(Double(index)),
                turnID: "turn", toolUseID: "call"
            ), in: epoch)
        }
        let state = await repository.drainDeliveredEvents()
        #expect(state.turns.isEmpty)
        #expect(state.diagnostic == nil)
    }
}
