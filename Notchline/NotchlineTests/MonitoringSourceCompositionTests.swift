import Foundation
import Testing
@testable import Notchline

struct MonitoringSourceCompositionTests {
    private func eventually(_ predicate: () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(5)
        while Date() < end {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
    private func refreshed(_ runtime: ProductMonitoringRuntime) async -> AgentSnapshot {
        _ = await runtime.fetchSnapshot()
        #expect(await eventually { await runtime.nextRefreshDeadline() != nil })
        return await runtime.fetchSnapshot()
    }

    private struct Live: MonitoringLifecycleSource {
        let repository: MonitoringRepository
        func gate(productName: String) async -> MonitoringSourceGate { .open(nil) }
        func disconnect() {}
    }
    private struct Open: ProductPresenceReporting {
        func presence() async -> AgentPresence { .open }
    }
    private actor TimedContent: RowContentSource, ScheduledMonitoringSource {
        nonisolated let changes = MonitoringChangeBroadcast()
        nonisolated var sourceChanges: [AsyncStream<Void>] { [changes.events()] }
        var reads = 0
        var starts = 0
        var stops = 0
        var fail = false
        var returnsPast = false
        var text = "No reading"
        func startMonitoring() { starts += 1 }
        func stopMonitoring() { stops += 1 }
        func setFailure(_ value: Bool) { fail = value }
        func usePastDeadline() { returnsPast = true }
        func refresh(at now: Date) throws -> Date? {
            reads += 1
            if fail { throw CocoaError(.fileReadCorruptFile) }
            text = "Progress \(reads)"
            return returnsPast ? now : now.addingTimeInterval(10)
        }
        func content(for turns: [MonitoredTurnState], messages: TurnMessageReading) -> [String: RowContent] {
            Dictionary(uniqueKeysWithValues: turns.map {
                ($0.threadID, RowContent(projectName: "Project", title: "Thread", preview: text))
            })
        }
    }
    private func product(_ source: TimedContent, clock: TestClock) -> (ProductMonitoringRuntime, MonitoringRepository) {
        let repository = MonitoringRepository(policy: .explicit, clock: clock)
        let runtime = ProductMonitoringRuntime(agent: .claudeCode, lifecycle: Live(repository: repository),
            sessions: SeparateSessionReading(presence: Open(), admission: AdmitsEveryObservedThread()),
            rowContent: source, clock: clock)
        repository.submit(MonitoringEvidence(signal: .turnStarted, threadID: "thread",
            observedAt: clock.now(), turnID: "turn"), in: repository.observationEpoch)
        return (runtime, repository)
    }

    @Test func aNoSetupProductHasNoManagedControlsOrHookCopy() async {
        let clock = TestClock()
        let (runtime, _) = product(TimedContent(), clock: clock)
        let descriptor = ProductDescriptor(kind: .claudeCode, settingsTitle: "Native SDK", setup: .none,
            make: { preconditionFailure("The Settings projection does not build a product") })
        let snapshot = await refreshed(runtime)
        #expect(snapshot.setupStatus == .notRequired)
        #expect(descriptor.setup.managedHooks == nil)
        let copy = ProductSettingsCopy(descriptor: descriptor, setup: snapshot.setupStatus,
            availability: snapshot.availability, diagnostic: nil)
        #expect(copy.status == "Connected")
        let disconnected = ProductSettingsCopy(descriptor: descriptor, setup: .notRequired,
            availability: .disconnected, diagnostic: "Stream unavailable")
        #expect(!disconnected.status.contains("Registered"))
        #expect(disconnected.diagnostic == "Stream unavailable")
        await runtime.disconnect()
    }

    @Test func aTimedSourceAdvancesTheSameRowsAndParksWhenDisconnected() async {
        let clock = TestClock()
        let source = TimedContent()
        let (runtime, repository) = product(source, clock: clock)
        #expect(await refreshed(runtime).sessions.first?.preview == "Progress 1")
        #expect(await runtime.nextRefreshDeadline() == clock.now().addingTimeInterval(10))
        _ = await refreshed(runtime)
        #expect(await source.reads == 1, "an unrelated refresh does not poll a fresh source")
        await clock.advance(by: 10)
        #expect(await refreshed(runtime).sessions.first?.preview == "Progress 2")
        let oldEpoch = repository.observationEpoch
        await runtime.disconnect()
        #expect(await runtime.nextRefreshDeadline() == nil)
        #expect(await source.stops == 1)
        #expect(!repository.submit(MonitoringEvidence(signal: .turnStarted, threadID: "old",
            observedAt: clock.now()), in: oldEpoch))
        #expect(await refreshed(runtime).sessions.isEmpty, "reconnect does not replay old Turns")
        #expect(await source.starts == 2)
        await runtime.disconnect()
    }

    @Test func failedReadsBackOffWithoutErasingTheTurnOrLastContent() async {
        let clock = TestClock()
        let source = TimedContent()
        let (runtime, _) = product(source, clock: clock)
        _ = await refreshed(runtime)
        await clock.advance(by: 10)
        await source.setFailure(true)
        let failed = await refreshed(runtime)
        #expect(failed.sessions.first?.preview == "Progress 1")
        #expect(failed.sessions.first?.status == .running)
        #expect(failed.diagnostic?.contains("could not be read") == true)
        #expect(await runtime.nextRefreshDeadline() == clock.now().addingTimeInterval(5))
        for _ in 0..<10 { _ = await refreshed(runtime) }
        #expect(await source.reads == 2)
        await clock.advance(by: 5)
        _ = await refreshed(runtime)
        #expect(await runtime.nextRefreshDeadline() == clock.now().addingTimeInterval(10))
        await source.setFailure(false)
        await clock.advance(by: 10)
        #expect(await refreshed(runtime).diagnostic == nil)
        await runtime.disconnect()
    }

    @Test func aConsumedDeadlineCannotSpinAndAnInstanceIsOwnedOnce() async {
        let source = TimedContent()
        await source.usePastDeadline()
        let now = Date(timeIntervalSince1970: 1000)
        let composition = MonitoringSourceComposition([source, source], clock: TestClock(now: now))
        await composition.refresh(at: now)
        #expect(await eventually { await composition.nextDeadline() == now.addingTimeInterval(5) })
        #expect(await source.starts == 1)
        #expect(await source.reads == 1)
        #expect(await composition.nextDeadline() == now.addingTimeInterval(5))
        await composition.stop()
        #expect(await source.stops == 1)
        #expect(await composition.nextDeadline() == nil)
    }

    private actor SlowContent: RowContentSource, ScheduledMonitoringSource {
        nonisolated let changes = MonitoringChangeBroadcast()
        nonisolated var sourceChanges: [AsyncStream<Void>] { [changes.events()] }
        var reads = 0
        var stops = 0
        var continuation: CheckedContinuation<Void, Never>?
        func refresh(at now: Date) async -> Date? {
            reads += 1
            await withCheckedContinuation { continuation = $0 }
            return now.addingTimeInterval(30)
        }
        func content(for turns: [MonitoredTurnState], messages: TurnMessageReading) -> [String: RowContent] {
            Dictionary(uniqueKeysWithValues: turns.map {
                ($0.threadID, RowContent(projectName: "Demo", title: "Held metadata", preview: "Last trustworthy text"))
            })
        }
        func release() { continuation?.resume(); continuation = nil }
        func stopMonitoring() { stops += 1 }
    }

    @Test func aSlowScheduledReadCannotHoldLifecycleOrRestoreDeadlinesAfterDisconnect() async {
        let source = SlowContent()
        let repository = MonitoringRepository(policy: .explicit)
        let runtime = ProductMonitoringRuntime(agent: .claudeCode, lifecycle: Live(repository: repository),
            sessions: SeparateSessionReading(presence: Open(), admission: AdmitsEveryObservedThread()), rowContent: source)
        let now = Date()
        repository.submit(MonitoringEvidence(signal: .turnStarted, threadID: "thread", observedAt: now,
            turnID: "turn"), in: repository.observationEpoch)
        let started = Task { await runtime.fetchSnapshot() }
        #expect(await eventually { await source.reads == 1 })
        // Bounded observation: the snapshot must land while the reader is held.
        let recorder = SnapshotRecorder()
        let observed = Task { await recorder.set(started.value) }
        let returned = await eventually { await recorder.value != nil }
        #expect(returned)
        if !returned { await source.release() }
        #expect(await recorder.value?.sessions.first?.status == .running)
        repository.submit(MonitoringEvidence(signal: .turnEnded, threadID: "thread", observedAt: now.addingTimeInterval(1),
            turnID: "turn"), in: repository.observationEpoch)
        #expect(await runtime.fetchSnapshot().sessions.first?.status == .completed)
        #expect(await source.reads == 1)
        #expect(await runtime.nextRefreshDeadline() == nil)
        await runtime.disconnect()
        await source.release()
        await observed.value
        #expect(await source.stops == 1)
        #expect(await runtime.nextRefreshDeadline() == nil)
    }

    private actor SnapshotRecorder {
        var value: AgentSnapshot?
        func set(_ snapshot: AgentSnapshot) { value = snapshot }
    }

    private actor SuspendedSessions: ProductSessionReading, ManagedMonitoringSource {
        var entered = false
        var stopped = false
        var continuation: CheckedContinuation<Void, Never>?
        func read(observing state: MonitoringStateSnapshot) async -> SessionReading {
            entered = true
            await withCheckedContinuation { continuation = $0 }
            return SessionReading(presence: .open, admission: .everyObservedThread)
        }
        func release() { continuation?.resume(); continuation = nil }
        func stopWatching() { stopped = true }
        func stopMonitoring() { stopWatching() }
    }

    @Test func aReadReturningAfterDisconnectCannotPublishOrRestartSources() async {
        let repository = MonitoringRepository(policy: .explicit)
        let sessions = SuspendedSessions()
        let source = TimedContent()
        let runtime = ProductMonitoringRuntime(agent: .claudeCode, lifecycle: Live(repository: repository),
            sessions: sessions, rowContent: source)
        let pending = Task { await runtime.fetchSnapshot() }
        while !(await sessions.entered) { await Task.yield() }
        await runtime.disconnect()
        await sessions.release()
        let late = await pending.value
        #expect(late.availability == .disconnected)
        #expect(late.sessions.isEmpty)
        #expect(await sessions.stopped)
        #expect(await source.stops == 1)
        #expect(await runtime.nextRefreshDeadline() == nil)
    }

    @Test func stoppingOneProductLeavesAnotherProductsRowsAndDeadlineAlone() async {
        let clock = TestClock()
        let (first, _) = product(TimedContent(), clock: clock)
        let (second, _) = product(TimedContent(), clock: clock)
        _ = await refreshed(first)
        _ = await refreshed(second)
        await first.disconnect()
        #expect(await second.fetchSnapshot().sessions.count == 1)
        #expect(await second.nextRefreshDeadline() == clock.now().addingTimeInterval(10))
        await second.disconnect()
    }

    @Test func aSourceEdgeRefreshesBeforeItsDeadlineThroughTheSharedStream() async {
        let clock = TestClock()
        let source = TimedContent()
        let (runtime, _) = product(source, clock: clock)
        _ = await refreshed(runtime)
        var iterator = runtime.stateChangeEvents.makeAsyncIterator()
        // Consume the initial Turn's edge before testing the source's edge.
        #expect(await iterator.next() != nil)
        source.changes.signal()
        #expect(await iterator.next() != nil)
        // The source counter advances before its wake reaches the store.
        #expect(await eventually {
            _ = await runtime.fetchSnapshot()
            let reads = await source.reads
            let deadline = await runtime.nextRefreshDeadline()
            return reads == 2 && deadline == clock.now().addingTimeInterval(10)
        })
        await runtime.disconnect()
    }

    private actor UsageRead {
        var entered = false
        var continuation: CheckedContinuation<String?, Never>?
        func read() async -> String? {
            entered = true
            return await withCheckedContinuation { continuation = $0 }
        }
        func release() { continuation?.resume(returning: "Total cost: $0.00"); continuation = nil }
    }

    @Test func aCancelledUsageReadCannotMutateHealthOrBookAnotherRead() async {
        let read = UsageRead()
        let reader = ClaudeCodeUsageReader(read: { await read.read() }, readConfiguration: { nil })
        let pending = Task { await reader.quota() }
        while !(await read.entered) { await Task.yield() }
        await reader.stopMonitoring()
        await read.release()
        _ = await pending.value
        #expect(await reader.nextReadDeadline() == nil)
        #expect(await reader.quotaDiagnostic() == nil)
    }

    @Test func aPausedDirectoryWatcherReleasesItsDescriptorAndCanResume() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: path) }
        let watcher = DirectoryChangeWatcher(directoryURL: path, debounceInterval: 0.01)
        #expect(watcher.isAttached)
        watcher.pause()
        #expect(!watcher.isAttached)
        #expect(!watcher.attachIfNeeded(), "queued reattachment cannot undo a pause")
        watcher.resume()
        #expect(watcher.isAttached)
        watcher.pause()
    }


    private actor SuspendedEvidence: TurnEvidenceSource {
        var entered = false
        var continuation: CheckedContinuation<TurnEvidenceBatch, Never>?
        func observations(in state: MonitoringStateSnapshot, phase: TurnEvidencePhase) async -> TurnEvidenceBatch {
            entered = true
            return await withCheckedContinuation { continuation = $0 }
        }
        func release(at time: Date) {
            continuation?.resume(returning: TurnEvidenceBatch(interruptions: [
                TurnInterruption(threadID: "thread", turnID: "turn", endedAt: time)
            ]))
            continuation = nil
        }
        func watch(openTurnsIn state: MonitoringStateSnapshot) {}
        func stopWatching() {}
    }

    @Test func anOldSupplementaryReadingCannotRetireAReusedIdentityAfterReset() async {
        let repository = MonitoringRepository(policy: .explicit)
        let source = SuspendedEvidence()
        let now = Date(timeIntervalSince1970: 1000)
        repository.submit(MonitoringEvidence(signal: .turnStarted, threadID: "thread",
            observedAt: now, turnID: "turn"), in: repository.observationEpoch)
        let state = await repository.drainDeliveredEvents()
        let pending = Task { await SupplementaryEvidenceApplication.settle(source, from: state, in: repository) }
        while !(await source.entered) { await Task.yield() }
        await repository.resetIntegrationObservation(clearTurns: true)
        repository.submit(MonitoringEvidence(signal: .turnStarted, threadID: "thread",
            observedAt: now.addingTimeInterval(1), turnID: "turn"), in: repository.observationEpoch)
        _ = await repository.drainDeliveredEvents()
        await source.release(at: now.addingTimeInterval(10))
        #expect(await pending.value.turns.first?.status == .running)
    }

}
