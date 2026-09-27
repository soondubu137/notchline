import Foundation
import Testing
@testable import Notchline

/// Every contract a runtime or Provider calls across actors is a `nonisolated protocol`, so an actor
/// outside the app module can implement it (`system-architecture.md` §7). Left unmarked, Swift 6.4
/// exports such a protocol from this MainActor-default module as MainActor-isolated, and this file
/// stops compiling. The actor doubles in the other suites pin the rest of the family, except
/// `AgentHookVocabulary`, whose conformers are values. The mark does not reach a protocol's
/// extensions, so their defaults are marked one by one and pinned at run time below.
struct ContractIsolationTests {
    private struct Screen: ScreenAvailabilityReporting {
        func isAvailable() -> Bool { true }
        func changeEvents() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    }

    /// One actor for each contract no other suite gives an actor double.
    private actor OutsideSources: MonitoringLifecycleSource, ClaudeCodeSessionListing, ThreadAdmitting,
        ReadEvidenceSource, HookRegistrationSetup {
        nonisolated let repository: MonitoringRepository
        nonisolated let screen: any ScreenAvailabilityReporting = Screen()
        nonisolated let socketURL = URL(fileURLWithPath: "/dev/null")
        private let admitted: Set<String>
        private let readAt: Date

        init(repository: MonitoringRepository, admitted: Set<String>, readAt: Date) {
            self.repository = repository
            self.admitted = admitted
            self.readAt = readAt
        }

        func gate(productName: String) -> MonitoringSourceGate { .open(nil) }
        nonisolated func disconnect() {}
        func liveSessions() -> [ClaudeCodeSession] { [] }
        func presence() -> AgentPresence { .open }
        func invalidate() {}
        func listReadStartedAt() -> Date { .distantFuture }
        func admission() -> ThreadAdmission { .exactly(admitted, readAt: readAt) }
        func verdicts(for candidates: [ReadGateCandidate], now: Date) -> ReadEvidenceJudgement {
            ReadEvidenceJudgement(verdicts: [:], diagnostic: nil)
        }
        func forget() {}
        func prepareHelperForTransport() -> Bool { true }
        func status(observedBy repository: HookEventRepository) -> IntegrationSetupStatus { .active }
        func install() {}
        func uninstall() {}
    }

    @MainActor
    @Test func aRuntimeComposesSourcesThatAreActorsOutsideTheAppModule() async {
        let clock = TestClock()
        let grace = MonitorTiming.standard.newTurnReconciliationGrace
        let repository = MonitoringRepository(policy: .explicit, clock: clock)
        for thread in ["listed", "gone"] {
            repository.submit(MonitoringEvidence(signal: .turnStarted, threadID: thread,
                observedAt: clock.now(), turnID: thread), in: repository.observationEpoch)
        }
        let sources = OutsideSources(repository: repository, admitted: ["listed"],
                                     readAt: clock.now().addingTimeInterval(grace + 1))
        let runtime = ProductMonitoringRuntime(agent: .claudeCode, lifecycle: sources,
            sessions: SeparateSessionReading(presence: sources, admission: sources),
            readEvidence: sources, clock: clock)

        #expect(await runtime.fetchSnapshot().sessions.count == 2, "a new Turn outlives one reading")
        await clock.advance(by: grace + 1)
        let snapshot = await runtime.fetchSnapshot()
        #expect(snapshot.presence == .open)
        #expect(snapshot.sessions.map(\.threadID) == ["listed"],
                "the actor's admission retires the Thread it no longer lists")
        #expect(await HookLifecycleSource(setup: sources, repository: repository).setupStatus() == .active)
        await runtime.disconnect()
    }

    /// Leans on every default an extension of these contracts supplies. Not an actor, and nothing
    /// in it suspends, so a default that calls back into it does not queue on the cooperative pool.
    private final class ReliesOnEveryDefault: AgentMonitoring, ClaudeCodeSessionListing,
        ManagedMonitoringSource, CodexAppServerCommunicating {
        let agent = AgentKind.claudeCode
        let stateChangeEvents = AsyncStream<Void> { $0.finish() }

        func fetchSnapshot(dismissedRowIDs: Set<String>) -> AgentSnapshot {
            AgentSnapshot(agent: .claudeCode, availability: .ready, sessions: [], quota: .noneReported,
                          diagnostic: nil)
        }
        func nextRefreshDeadline() -> Date? { nil }
        func disconnect() {}
        func liveSessions() -> [ClaudeCodeSession] { [] }
        func invalidate() {}
        func listReadStartedAt() -> Date { .distantFuture }
        func stopMonitoring() {}
        func connect() {}
        func request(method: String, params: JSONValue?, timeoutNanoseconds: UInt64?) -> JSONValue { .null }
    }

    /// The `nonisolated` on a protocol does not reach its extensions, whose members took the app's
    /// MainActor default. Each call to one hopped to the main thread and waited there: every Codex
    /// quota read through `request(method:params:)`, and the runtime's empty `releaseEndedRows` and
    /// `startMonitoring`. No warning says so. This holds the main thread while every default is
    /// called elsewhere; one that needs the main actor cannot finish until the hold ends.
    ///
    /// The calls run on a queue of their own, not the cooperative pool: in the suite's opening burst
    /// the pool made them wait 1-3 s, and holding the main thread that long starved the tests beside it.
    @MainActor
    @Test func theContractsDefaultsDoNotWaitForTheMainActor() async {
        let reliant = ReliesOnEveryDefault()
        let calls: [(String, @Sendable () async -> Void)] = [
            ("AgentMonitoring.recheckConnection", { await (reliant as any AgentMonitoring).recheckConnection() }),
            ("AgentMonitoring.fetchSnapshot", { _ = await (reliant as any AgentMonitoring).fetchSnapshot() }),
            ("ClaudeCodeSessionListing.presence", { _ = await (reliant as any ClaudeCodeSessionListing).presence() }),
            ("ManagedMonitoringSource.startMonitoring", {
                await (reliant as any ManagedMonitoringSource).startMonitoring()
            }),
            ("RowContentSource.releaseEndedRows", {
                await (WorkingDirectoryRowContent() as any RowContentSource).releaseEndedRows([:])
            }),
            ("CodexAppServerCommunicating.request", {
                _ = try? await (reliant as any CodexAppServerCommunicating).request(method: "probe", params: nil)
            })
        ]
        let executor = QueueExecutor()
        let finished = FinishedCalls()
        let tasks = calls.map { name, call in
            Task.detached(executorPreference: executor) {
                await call()
                finished.insert(name)
            }
        }
        // Held on purpose: nothing below yields until every call is in or the limit passes.
        let limit = Date().addingTimeInterval(2)
        while finished.count < calls.count, Date() < limit { usleep(100) }
        let waiting = calls.map(\.0).filter { !finished.contains($0) }
        for task in tasks { await task.value }

        #expect(waiting.isEmpty, "these defaults waited for the main actor: \(waiting)")
    }
}

/// Runs a task's nonisolated work on a serial queue of its own.
private final class QueueExecutor: TaskExecutor {
    private let queue = DispatchQueue(label: "com.yinfenglu.Notchline.tests.contract-defaults")

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        queue.async { job.runSynchronously(on: self.asUnownedTaskExecutor()) }
    }
}

private final class FinishedCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var names: Set<String> = []

    var count: Int { lock.withLock { names.count } }
    func insert(_ name: String) { lock.withLock { _ = names.insert(name) } }
    func contains(_ name: String) -> Bool { lock.withLock { names.contains(name) } }
}
