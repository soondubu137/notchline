import Foundation
import Testing
@testable import Notchline

/// §9 of `docs/product-generalisation-plan.md`: a product that shares nothing
/// with the shipping protocols -- no Hooks, no JSON, no configuration file, no
/// socket; its own Thread, Turn, request, question and option identities; two
/// simultaneous requests on one producer; identical labels backed by distinct
/// values; a choices-only question beside a free-text one; an asynchronous
/// answer channel that can only say it is unsure; progress read on a deadline
/// of its own; and no quota -- reaching the notch through the shared runtime,
/// reducer, selection, drafts, navigation dispatch and panel forms, with
/// nothing built for it but its adapters. It borrows an `AgentKind` and is
/// registered nowhere.
struct SyntheticProductConformanceTests {
    private struct LiveSource: MonitoringLifecycleSource {
        let repository: MonitoringRepository
        func gate(productName: String) async -> MonitoringSourceGate { .open(nil) }
        func disconnect() {}
    }
    private struct OpenProduct: ProductPresenceReporting {
        func presence() async -> AgentPresence { .open }
    }

    /// Progress read on a deadline of its own, never pushed.
    private actor DeadlineProgress: RowContentSource, ScheduledMonitoringSource {
        private(set) var reads = 0
        func refresh(at now: Date) throws -> Date? {
            reads += 1
            return now.addingTimeInterval(30)
        }
        func content(for turns: [MonitoredTurnState], messages: TurnMessageReading) -> [String: RowContent] {
            Dictionary(uniqueKeysWithValues: turns.map {
                ($0.threadID, RowContent(projectName: "Synthetic", title: $0.promptPreview ?? "Untitled", preview: "Step \(reads)"))
            })
        }
        func stopMonitoring() {}
    }

    /// An answer channel with no descriptor: it mints its own handles, hears
    /// back later, and when it does can only say it is unsure.
    private actor SyntheticChannel {
        let issuer = UUID()
        private var next: HookReplyRegistry.Ticket = 1
        private(set) var answers: [(handle: AnswerHandle, answer: AgentAnswer)] = []
        private var pending: [CheckedContinuation<AnswerOutcome, Never>] = []

        func mint() -> AnswerHandle {
            defer { next += 1 }
            return AnswerHandle(ticket: next, issuer: issuer)
        }
        func answer(_ answer: AgentAnswer, on handle: AnswerHandle) async -> AnswerOutcome {
            guard handle.issuer == issuer else { return .expired(.notHeld) }
            answers.append((handle, answer))
            return await withCheckedContinuation { pending.append($0) }
        }
        var isWaiting: Bool { !pending.isEmpty }
        func hearBack(_ outcome: AnswerOutcome) {
            for continuation in pending { continuation.resume(returning: outcome) }
            pending.removeAll()
        }
    }

    /// The product: the shared runtime, with the synthetic channel beside it.
    private struct SyntheticProduct: AgentMonitoring, AnswerDelivering {
        let runtime: ProductMonitoringRuntime
        let channel: SyntheticChannel
        nonisolated var agent: AgentKind { runtime.agent }
        nonisolated var stateChangeEvents: AsyncStream<Void> { runtime.stateChangeEvents }
        func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot {
            await runtime.fetchSnapshot(dismissedRowIDs: dismissedRowIDs)
        }
        func nextRefreshDeadline() async -> Date? { await runtime.nextRefreshDeadline() }
        func disconnect() async { await runtime.disconnect() }
        func answer(_ answer: AgentAnswer, on handle: AnswerHandle) async -> AnswerOutcome {
            await channel.answer(answer, on: handle)
        }
    }

    @MainActor
    private final class RecordingNavigator: AgentNavigating {
        private(set) var opened: [MonitoredSession] = []
        func open(_ session: MonitoredSession) async throws -> NavigationOutcome {
            opened.append(session)
            return .raisedApplication(host: "Synthetic")
        }
    }

    private let t0 = Date(timeIntervalSince1970: 1_757_000_000)

    private func eventually(
        within seconds: TimeInterval = 5, _ isTrue: @MainActor () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await isTrue() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }

    @Test @MainActor
    func aSyntheticProductReachesTheNotchThroughTheSharedRuntimeStoreAndChannel() async throws {
        let clock = TestClock(now: t0)
        let repository = MonitoringRepository(policy: .explicit, clock: clock)
        let progress = DeadlineProgress()
        let channel = SyntheticChannel()
        let runtime = ProductMonitoringRuntime(
            agent: .claudeCode, lifecycle: LiveSource(repository: repository),
            sessions: SeparateSessionReading(presence: OpenProduct(), admission: AdmitsEveryObservedThread()),
            rowContent: progress, clock: clock
        )
        let product = SyntheticProduct(runtime: runtime, channel: channel)
        let navigator = RecordingNavigator()
        let store = MonitorStore(
            displays: [], services: [product], navigator: navigator,
            initialSnapshot: AgentSnapshot(
                agent: .claudeCode, availability: .ready, sessions: [], quota: .noneReported, diagnostic: nil
            ),
            clock: clock
        )

        // Explicit native identities, typed, in order.
        let epoch = repository.observationEpoch
        repository.submit(MonitoringEvidence(
            signal: .turnStarted, threadID: "conv-7", observedAt: t0, turnID: "run-3",
            prompt: "Choose the database", workingDirectory: "/Projects/demo"
        ), in: epoch)
        // Two simultaneous questions on one producer, each under the product's
        // own request identity: one choices-only with identical labels backed
        // by distinct values, one answered in words.
        let store_ = AgentRequest(
            id: "req-A", toolName: "choose",
            form: .questions([
                AgentQuestion(
                    id: 0, header: "Store", text: "Which store?",
                    options: [
                        AgentQuestionOption(id: 0, label: "Postgres", description: "15", nativeID: "pg-15"),
                        AgentQuestionOption(id: 1, label: "Postgres", description: "16", nativeID: "pg-16")
                    ],
                    allowsSeveralAnswers: false, nativeID: "q-store", acceptsFreeText: false
                )
            ]),
            operations: .questionAnswers
        )
        let region = AgentRequest(
            id: "req-B", toolName: "choose",
            form: .questions([
                AgentQuestion(id: 0, header: "Region", text: "Which region?", options: [],
                              allowsSeveralAnswers: false, nativeID: "q-region")
            ]),
            operations: .questionAnswers
        )
        let handleA = await channel.mint()
        let handleB = await channel.mint()
        repository.submit(MonitoringEvidence(
            signal: .inputWaitOpened, threadID: "conv-7", observedAt: t0.addingTimeInterval(1), turnID: "run-3",
            toolUseID: "call-A", requestID: "req-A", toolName: "choose", request: store_,
            answerHandle: handleA, answerOperations: .questionAnswers
        ), in: epoch)
        repository.submit(MonitoringEvidence(
            signal: .inputWaitOpened, threadID: "conv-7", observedAt: t0.addingTimeInterval(2), turnID: "run-3",
            toolUseID: "call-B", requestID: "req-B", toolName: "choose", request: region,
            answerHandle: handleB, answerOperations: .questionAnswers
        ), in: epoch)

        store.refreshNow()
        #expect(await eventually { store.sessions.first?.requests.map(\.id) == ["req-A", "req-B"] })
        let row = try #require(store.sessions.first)
        #expect(row.status == .inputNeeded)
        #expect(row.title == "Choose the database")
        #expect(row.projectName == "Synthetic")
        #expect(row.preview == "Step 1")
        #expect(await product.fetchSnapshot().quota == .noneReported)

        // Progress on the source's own deadline, booked and consumed.
        #expect(await product.nextRefreshDeadline() == t0.addingTimeInterval(30))
        await clock.advance(by: 30)
        store.refreshNow()
        #expect(await eventually { store.sessions.first?.preview == "Step 2" })

        // The row opens the first request: a choices-only question draws no
        // field, and the second of two identical labels is its own option.
        store.toggleOpenRow(row)
        #expect(store.openRequest?.id == "req-A")
        #expect(store.openAnswerRow?.affirmative == "Submit")
        #expect(store.openAnswerRow?.placeholder == nil)
        #expect(await eventually { store.isAffirmativeArmed })
        #expect(!store.canSubmitCurrentAnswer)
        store.takeAnswer(.option(1))
        #expect(store.canSubmitCurrentAnswer)
        store.takeAnswer(.affirmative)
        #expect(await eventually { await channel.isWaiting })
        #expect(store.isAnswerInFlight)

        // What travelled: the option by its identity, on the channel's own handle.
        let sent = try #require(await channel.answers.first)
        #expect(sent.handle == handleA)
        guard case let .answers(answered) = sent.answer, let one = answered.first else {
            Issue.record("the channel received \(sent.answer) rather than the question's answers")
            return
        }
        #expect(one.selectedOptionIDs == [1])
        #expect(one.selectedOptions?.first?.nativeID == "pg-16")
        #expect(one.question.nativeID == "q-store")
        #expect(one.text == nil)

        // The channel can only say it is unsure: the row says so, keeps what
        // was chosen, and never sends on that handle again.
        await channel.hearBack(.uncertain)
        #expect(await eventually { !store.isAnswerInFlight })
        #expect(store.previewLine(for: row) == "Sent, but not confirmed — check in Claude Code")
        #expect(store.openRowID == nil)
        store.toggleOpenRow(row)
        #expect(store.openRequest?.id == "req-A", "pinned to what the person answered, until the product says so")
        #expect(store.isOptionTicked(1))
        #expect(await eventually { store.isAffirmativeArmed })
        store.takeAnswer(.affirmative)
        #expect(await channel.answers.count == 1)

        // The product resolves the first by its own identity; the row moves on
        // to the second, whose question takes words and draws the field.
        repository.submit(MonitoringEvidence(
            signal: .requestResolved, threadID: "conv-7", observedAt: t0.addingTimeInterval(40), turnID: "run-3",
            requestID: "req-A"
        ), in: epoch)
        store.refreshNow()
        #expect(await eventually { store.openRequest?.id == "req-B" })
        #expect(store.sessions.first?.status == .inputNeeded)
        #expect(store.openAnswerRow?.placeholder == "your answer…")
        #expect(store.sessions.first?.requests.map(\.id) == ["req-B"])

        // A click goes through the store's one navigation dispatch.
        store.open(try #require(store.sessions.first))
        #expect(await eventually { navigator.opened.count == 1 })
        #expect(navigator.opened.first?.threadID == "conv-7")

        await product.disconnect()
    }
}
