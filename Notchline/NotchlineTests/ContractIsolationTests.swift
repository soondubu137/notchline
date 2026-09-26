import Foundation
import Testing
@testable import Notchline

/// Every contract a runtime or Provider calls across actors is a `nonisolated protocol`, so an actor
/// outside the app module can implement it (`system-architecture.md` §7). Left unmarked, Swift 6.4
/// exports such a protocol from this MainActor-default module as MainActor-isolated, and this file
/// stops compiling. The actor doubles in the other suites pin the rest of the family, except
/// `AgentHookVocabulary`, whose conformers are values.
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
}
