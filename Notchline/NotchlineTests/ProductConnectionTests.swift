import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Notchline

struct ProductConnectionTests {
    private func reading(_ agent: AgentKind = .trae, setup: IntegrationSetupStatus = .active,
                         presence: AgentPresence = .open, availability: MonitorAvailability = .ready,
                         installation: ProductInstallationReading = .notChecked,
                         activation: ProductConnectionFacts.Activation = .verified,
                         health: ProductConnectionFacts.Health = .available,
                         diagnostic: String? = nil) -> AgentSnapshot {
        AgentSnapshot(agent: agent, availability: availability, sessions: [], quota: .noneReported,
            diagnostic: diagnostic, setupStatus: setup, presence: presence,
            connection: .init(installation: installation, activation: activation, health: health))
    }
    private func present(_ snapshot: AgentSnapshot, intent: ProductMonitoringIntent? = .enabled) -> ProductConnectionPresentation {
        .make(snapshot: snapshot, intent: intent, configurable: true)
    }

    @Test func normalChoicesNeverWarnOrAskForAConnection() {
        for agent in AgentKind.allCases {
            let closed = present(reading(agent, presence: .closed, availability: .disconnected,
                                         diagnostic: "An old transport error."))
            #expect(closed.status == (agent == .claudeCode ? "Not running" : "Not open"))
            #expect(closed.tone == .neutral)
            #expect(closed.notice == nil)
            #expect(closed.action == nil)
            let off = present(reading(agent, setup: .repairRequired), intent: .disabled)
            #expect(off.status == "Off")
            #expect(off.notice == nil)
            let absent = present(reading(agent, presence: .unknown, installation: .notFound))
            #expect(absent.status == "App not found")
            #expect(absent.tone == .neutral)
        }
    }
    @Test func missingSetupDependsOnIntentAndUnreadableIsNeverAbsent() {
        let absent = reading(setup: .notInstalled)
        #expect(present(absent, intent: nil).status == "Not set up")
        #expect(present(absent).status == "Setup needs repair")
        #expect(present(absent).action == .repair)
        let unreadable = present(reading(setup: .unreadable))
        #expect(unreadable.status == "Unable to check setup")
        #expect(unreadable.action == .recheck)
        #expect(unreadable.tone == .warning)
        #expect(present(reading(setup: .repairRequired, presence: .closed)).status == "Setup needs repair")
    }
    @Test func connectedRequiresPresenceAndNoUnverifiedActivation() {
        #expect(present(reading()).status == "Connected")
        #expect(present(reading(presence: .unknown)).status == "Unable to check")
        #expect(present(reading(activation: .unverified)).status == "Set up · not yet verified")
        #expect(!reading(activation: .unverified).isConnected)
        #expect(!reading(activation: .reloadRequired).isConnected)
        // A running product outranks a failed bounded installation search.
        #expect(present(reading(installation: .notFound)).status == "Connected")
        #expect(present(reading(activation: .reloadRequired)).status == "Window reload required")
        #expect(present(reading(health: .partial)).status == "Partially connected")
    }
    @Test func closedProductDoesNotSuggestReloadAndRemovedProductDoesNotSuggestRepair() {
        #expect(present(reading(presence: .closed, activation: .reloadRequired)).status == "Not open")
        let removed = present(reading(setup: .repairRequired, presence: .closed, installation: .notFound))
        #expect(removed.status == "App not found")
        #expect(removed.action != .repair)
    }
    @Test func silenceBeforeFirstTraeUseDoesNotBecomeFailure() async {
        let clock = ConnectionClock()
        let checker = ProductConnectionMonitor(clock: clock) { .notChecked }
        let silent = reading(setup: .reviewRequired, availability: .disconnected,
                             activation: .unverified, health: .checking)
        _ = await checker.inspect(silent)
        clock.advance(3600)
        let checked = await checker.inspect(silent)
        #expect(present(checked).status == "Set up · not yet verified")
        #expect(present(checked).tone == .neutral)
    }
    @Test func realConnectionFailureRecoversWithoutRetainingItsWarning() async {
        let clock = ConnectionClock()
        let checker = ProductConnectionMonitor(clock: clock) { .notChecked }
        _ = await checker.inspect(reading())
        let failure = reading(availability: .disconnected, diagnostic: "The socket stopped responding.")
        let retrying = await checker.inspect(failure)
        #expect(retrying.connection.health == .reconnecting)
        #expect(await checker.nextDeadline() == clock.now().addingTimeInterval(10))
        clock.advance(11)
        let failed = await checker.inspect(failure)
        #expect(failed.connection.health == .unavailable)
        #expect(await checker.nextDeadline() == nil, "a consumed warning deadline cannot spin the refresh loop")
        #expect(present(failed).notice?.severity == .warning)
        let restored = await checker.inspect(reading())
        #expect(restored.connection.notice == nil)
        #expect(present(restored).status == "Connected")
        let closed = await checker.inspect(reading(presence: .closed, availability: .disconnected))
        #expect(closed.connection.health == .notApplicable)
    }
    @Test func capabilityDiagnosticsDoNotBreakHealthyObservation() async {
        let checker = ProductConnectionMonitor { .notChecked }
        let checked = await checker.inspect(reading(diagnostic: "Usage is temporarily unavailable."))
        let copy = present(checked)
        #expect(copy.status == "Connected")
        #expect(copy.notice?.scope == .capability)
        #expect(copy.notice?.severity == .information)
    }
    @Test func discoveryCachesAndExplicitRecheckInvalidatesIt() async {
        let counter = DiscoveryCounter()
        let checker = ProductConnectionMonitor { await counter.read() }
        _ = await checker.inspect(reading())
        _ = await checker.inspect(reading())
        #expect(await counter.count == 1)
        await checker.invalidate()
        _ = await checker.inspect(reading())
        #expect(await counter.count == 2)
        _ = await checker.inspect(reading(presence: .closed))
        #expect(await counter.count == 3)
    }
    @Test @MainActor func externalSetupDeletionPreservesIntentAcrossLaunches() throws {
        let name = "Notchline.ConnectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = MonitorStore(services: [], preferences: defaults)
        store.applyForTesting(reading())
        #expect(store.monitoringIntent(for: .trae) == .enabled)
        store.applyForTesting(reading(setup: .notInstalled, availability: .setupRequired))
        #expect(store.integrationSwitchIsOn(for: .trae))
        let restarted = MonitorStore(services: [], preferences: defaults)
        #expect(restarted.monitoringIntent(for: .trae) == .enabled)
        restarted.applyForTesting(reading(setup: .notInstalled, availability: .setupRequired))
        #expect(restarted.integrationSwitchIsOn(for: .trae))
        #expect(present(try #require(restarted.productSnapshot(for: .trae)),
                        intent: restarted.monitoringIntent(for: .trae)).status == "Setup needs repair")
    }
    @Test @MainActor func aFailedRemovalKeepsMonitoringOffAndCanBeRetried() async {
        let service = ConnectionOperationStub()
        let store = MonitorStore(services: [service])
        await store.refreshAndWaitForTesting()
        #expect(await store.setIntegrationEnabledAndWait(false, for: .trae))
        #expect(store.monitoringIntent(for: .trae) == .disabled)
        #expect(store.productOperationFailures[.trae]?.action == .remove)
        let reads = await service.reads
        await store.refreshAndWaitForTesting()
        #expect(await service.reads == reads, "Off must not resume when external settings remain")
        await service.allowRemoval()
        #expect(await store.removeIntegrationAndWait(for: .trae))
        #expect(store.productOperationFailures[.trae] == nil)
        store.stopMonitoring()
    }

    @Test @MainActor func recheckDoesNotRepairExternallyRemovedSettings() async {
        let service = ConnectionOperationStub()
        let store = MonitorStore(services: [service])
        await store.refreshAndWaitForTesting()
        await service.loseSetup()
        await store.recheckIntegrationAndWait()
        #expect(store.integrationSwitchIsOn(for: .trae))
        #expect(store.setupStatus(for: .trae) == .notInstalled)
        #expect(await service.installs == 0)
        store.stopMonitoring()
    }

    @Test func invalidationRejectsAnOlderDiscoveryResult() async {
        let (starts, started) = AsyncStream.makeStream(of: Void.self)
        let discovery = SuspendedDiscovery(started: started)
        let checker = ProductConnectionMonitor { await discovery.read() }
        var iterator = starts.makeAsyncIterator()
        let old = Task { await checker.installation(presence: .open) }
        _ = await iterator.next()
        await checker.invalidate()
        let fresh = Task { await checker.installation(presence: .open) }
        _ = await iterator.next()
        await discovery.finish(index: 1, with: .notFound)
        #expect(await fresh.value == .notFound)
        await discovery.finish(index: 0, with: .found([.init(url: URL(fileURLWithPath: "/old.app"), version: nil, surface: "Desktop")]))
        guard case .unknown = await old.value else { Issue.record("A retired discovery became current"); return }
        #expect(await checker.installation(presence: .open) == .notFound)
    }

    /// Launch leaves the cold first check alone (`invalidationRejectsAnOlderDiscoveryResult`);
    /// coming back to page one rechecks, as opening Products does.
    @Test @MainActor func onboardingRechecksOnlyWhenTheUserReturnsToConnect() async throws {
        let service = RecheckCounter()
        let store = MonitorStore(displays: [], services: [service], preferences: nil)
        defer { store.stopMonitoring() }

        func host(_ page: OnboardingView.Page) -> NSWindow {
            let size = NSSize(width: OnboardingLayout.width, height: OnboardingLayout.height)
            let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -20_000, y: 0), size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: OnboardingView(page: page).environmentObject(store))
            window.orderFront(nil)
            window.contentView?.layoutSubtreeIfNeeded()
            return window
        }
        func settle(until done: () async -> Bool) async throws {
            let deadline = Date().addingTimeInterval(2)
            while await !done(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        }

        let launch = host(.connect)
        try await Task.sleep(for: .milliseconds(300))
        launch.orderOut(nil)
        #expect(await service.rechecks == 0)

        let later = host(.read)
        defer { later.orderOut(nil) }
        let content = try #require(later.contentView)
        // The navigation row ends at x = 556, y = 818 (`figma-design.md` §7); Back sits 16 pt left
        // of Continue. The accessibility tree is empty in this host, so press it by position.
        func size(_ button: some View) -> NSSize { NSHostingView(rootView: button).fittingSize }
        let next = size(Button("Continue") {}.buttonStyle(.borderedProminent).buttonBorderShape(.capsule))
        let previous = size(Button("Back") {}.buttonStyle(.bordered).buttonBorderShape(.capsule))
        let top = CGPoint(x: 556 - next.width - 16 - previous.width / 2, y: 818 - previous.height / 2)
        let point = content.convert(content.isFlipped ? top : CGPoint(x: top.x, y: content.bounds.height - top.y), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: later.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0))
            later.sendEvent(event)
        }
        try await settle { await service.rechecks > 0 }
        #expect(await service.rechecks == 1)
    }

    @Test func applicationMetadataIsFreshAndCorruptionIsNotUninstallation() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("NotchlineMetadata-\(UUID().uuidString).app")
        defer { try? FileManager.default.removeItem(at: app) }
        #expect(ProductInstallationDiscovery.metadata(at: app, bundleID: "com.trae.app") == .notFound)
        let info = app.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(at: info.deletingLastPathComponent(), withIntermediateDirectories: true)
        for version in ["3.5.91", "3.5.92"] {
            let data = try PropertyListSerialization.data(fromPropertyList:
                ["CFBundleIdentifier": "com.trae.app", "CFBundleShortVersionString": version],
                format: .xml, options: 0)
            try data.write(to: info, options: .atomic)
            #expect(ProductInstallationDiscovery.metadata(at: app, bundleID: "com.trae.app")
                == .found([.init(url: app, version: version, surface: "Desktop")]))
        }
        #expect(ProductInstallationDiscovery.metadata(at: app, bundleID: "another.product") == .notFound)
        try Data("not a plist".utf8).write(to: info)
        guard case .unknown = ProductInstallationDiscovery.metadata(at: app, bundleID: "com.trae.app") else {
            Issue.record("Unreadable metadata was reported as an absent application"); return
        }
    }

    @Test func checkTimestampsDoNotInvalidateAnOtherwiseIdenticalSnapshot() {
        var first = ProductConnectionFacts()
        var next = first
        first.checkedAt = Date(timeIntervalSince1970: 1)
        next.checkedAt = Date(timeIntervalSince1970: 2)
        #expect(first == next)
    }
}

private actor DiscoveryCounter {
    var count = 0
    func read() -> ProductInstallationReading { count += 1; return .notFound }
}
private nonisolated final class ConnectionClock: MonitorClock, @unchecked Sendable {
    private let lock = NSLock()
    private var time = Date(timeIntervalSince1970: 100)
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return time }
    func advance(_ seconds: TimeInterval) { lock.lock(); time += seconds; lock.unlock() }
    func sleep(nanoseconds: UInt64) async throws { try await Task.sleep(nanoseconds: nanoseconds) }
}

private actor ConnectionOperationStub: AgentMonitoring, IntegrationConfiguring {
    nonisolated let agent = AgentKind.trae
    nonisolated let stateChangeEvents = AsyncStream<Void> { $0.finish() }
    var reads = 0
    var installs = 0
    private var status = IntegrationSetupStatus.active
    private var fails = true
    func fetchSnapshot(dismissedRowIDs: Set<String>) -> AgentSnapshot {
        reads += 1
        return AgentSnapshot(agent: .trae, availability: status == .notInstalled ? .setupRequired : .ready,
                             sessions: [], quota: .noneReported, diagnostic: nil, setupStatus: status)
    }
    func nextRefreshDeadline() -> Date? { nil }
    func disconnect() {}
    func setupStatus() -> IntegrationSetupStatus { status }
    func installIntegration() { installs += 1; status = .active }
    func loseSetup() { status = .notInstalled }
    func allowRemoval() { fails = false }
    func removeIntegration() throws {
        if fails { throw CocoaError(.fileWriteNoPermission) }
    }
}
private actor RecheckCounter: AgentMonitoring {
    nonisolated let agent = AgentKind.trae
    nonisolated let stateChangeEvents = AsyncStream<Void> { $0.finish() }
    var rechecks = 0
    func fetchSnapshot(dismissedRowIDs: Set<String>) -> AgentSnapshot {
        AgentSnapshot(agent: .trae, availability: .ready, sessions: [], quota: .noneReported, diagnostic: nil)
    }
    func nextRefreshDeadline() -> Date? { nil }
    func disconnect() {}
    func recheckConnection() { rechecks += 1 }
}
private actor SuspendedDiscovery {
    let started: AsyncStream<Void>.Continuation
    private var waiting: [CheckedContinuation<ProductInstallationReading, Never>] = []
    init(started: AsyncStream<Void>.Continuation) { self.started = started }
    func read() async -> ProductInstallationReading {
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
            started.yield(())
        }
    }
    func finish(index: Int, with reading: ProductInstallationReading) { waiting[index].resume(returning: reading) }
}
