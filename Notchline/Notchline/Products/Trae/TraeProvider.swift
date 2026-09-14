import AppKit
import Darwin
import Foundation

/// One composition centre for Trae. Read evidence retires rows through the
/// shared gate; navigation and the reading-only request surface stay separate.
struct TraeProvider: AgentMonitoring, IntegrationConfiguring {
    nonisolated let agent = AgentKind.trae
    private let runtime: ProductMonitoringRuntime
    private let connectionMonitor: ProductConnectionMonitor
    let source: TraeSource
    private let discoversApplication: Bool
    nonisolated var stateChangeEvents: AsyncStream<Void> { runtime.stateChangeEvents }

    init(installation: TraeInstallation? = nil) {
        discoversApplication = installation == nil
        connectionMonitor = ProductInstallationDiscovery.live(.trae)
        let source = TraeSource(installation: installation ?? TraeInstallation())
        self.source = source
        let readEvidence = TraeReadEvidence(screen: ScreenAvailabilityWatcher(),
            foreground: DesktopReadingWatcher(bundleIdentifier: "com.trae.app"), transport: source.transport)
        runtime = ProductMonitoringRuntime(agent: .trae, lifecycle: source, sessions: source,
                                           rowContent: source, readEvidence: readEvidence,
                                           changeEvents: [source.transport.changes.events(), connectionMonitor.changes.events()])
    }
    func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot {
        if discoversApplication {
            await resolveApplication()
        }
        let snapshot = await runtime.fetchSnapshot(dismissedRowIDs: dismissedRowIDs)
        let present = await source.currentPresence()
        let transport = await source.transport.connectionFacts()
        if transport.healthy > 0 { source.confirmActivation() }
        var facts = snapshot.connection
        facts.notice = nil
        facts.activation = transport.healthy > 0 ? .verified
            : await source.needsWindowReload() ? .reloadRequired : .unverified
        facts.health = transport.healthy > 0 ? .available : .checking
        if transport.healthy > 0 && transport.failed > 0 {
            facts.health = .partial
            facts.notice = .init(severity: .warning, scope: .observation,
                                 message: "Some discovered Trae windows could not connect.")
        }
        // Presence comes from the application even when its observation gate is closed.
        let reading = AgentSnapshot(agent: .trae,
            availability: snapshot.availability == .ready && transport.healthy == 0 && present == .open
                ? .disconnected : snapshot.availability,
            sessions: snapshot.sessions, quota: snapshot.quota,
            diagnostic: snapshot.availability == .disconnected ? transport.diagnostic
                : MonitorDiagnostics.combined(transport.diagnostic, snapshot.diagnostic),
            setupStatus: snapshot.setupStatus, presence: present, connection: facts)
        return await connectionMonitor.inspect(reading)
    }
    func recheckConnection() async { await connectionMonitor.invalidate() }
    func nextRefreshDeadline() async -> Date? {
        [await runtime.nextRefreshDeadline(), await connectionMonitor.nextDeadline()].compactMap { $0 }.min()
    }
    func disconnect() async { await connectionMonitor.reset(); await runtime.disconnect() }
    func setupStatus() async -> IntegrationSetupStatus {
        switch source.installation.registration {
        case .unreadable: return .unreadable
        case .absent: return .notInstalled
        case .mismatched: return .repairRequired
        case .current: return await source.transport.reading().0 ? .active : .reviewRequired
        }
    }
    private func resolveApplication() async {
        let reading = await connectionMonitor.installation(presence: await source.currentPresence())
        if case let .found(instances) = reading, instances.count == 1, let instance = instances.first {
            source.useApplication(instance.url)
        }
    }
    func installIntegration() async throws {
        if discoversApplication {
            await connectionMonitor.invalidate()
            let reading = await connectionMonitor.installation(presence: await source.currentPresence())
            guard case let .found(instances) = reading, instances.count == 1, let instance = instances.first else {
                throw TraeBridgeError.installation("A single Trae installation could not be identified. Open the intended Trae application and try again.")
            }
            source.useApplication(instance.url)
        }
        try await source.installation.install()
        await source.recordInstalledIntoOpenApplication()
        await connectionMonitor.invalidate()
    }
    func removeIntegration() async throws {
        await runtime.disconnect()
        try await source.installation.remove()
    }
}

nonisolated final class TraeSource: MonitoringLifecycleSource, ProductSessionReading, RowContentSource, @unchecked Sendable {
    let repository = MonitoringRepository(policy: .explicit)
    private var installedLocation: TraeInstallation
    var installation: TraeInstallation {
        identityLock.lock(); defer { identityLock.unlock() }
        return installedLocation
    }
    func useApplication(_ url: URL) {
        identityLock.lock(); defer { identityLock.unlock() }
        let old = installedLocation
        installedLocation = TraeInstallation(application: url, directory: old.directory,
                                            resources: old.resources, extensionsManifest: old.extensionsManifest)
    }
    let transport: TraeBridgeTransport
    private let identityLock = NSLock()
    private var productPID: Int32?
    private var installedIntoPID: Int32?
    private let presence: RunningApplicationPresence
    @MainActor
    init(installation: TraeInstallation) {
        self.installedLocation = installation
        presence = RunningApplicationPresence(bundleIdentifiers: ["com.trae.app"])
        transport = TraeBridgeTransport(directory: installation.directory, repository: repository)
    }
    func gate(productName: String) async -> MonitoringSourceGate {
        switch installation.registration {
        case .unreadable:
            return .closed(availability: .setupRequired, setupStatus: .unreadable,
                           diagnostic: "Trae’s extension manifest could not be read or its format is unrecognised.")
        case .absent:
            return .closed(availability: .setupRequired, setupStatus: .notInstalled,
                           diagnostic: "Switch Trae on to install its companion extension.")
        case .mismatched:
            return .closed(availability: .setupRequired, setupStatus: .repairRequired,
                           diagnostic: "Trae’s companion installation is incomplete or out of date. "
                               + "Use Repair in Products to reinstall it.")
        case .current:
            break
        }
        switch installation.applicationReading {
        case .notFound:
            return .closed(availability: .disconnected, setupStatus: .reviewRequired, diagnostic: nil)
        case let .unknown(reason):
            return .closed(availability: .disconnected, setupStatus: .reviewRequired, diagnostic: reason)
        case let .found(instances):
            guard instances.first?.version == TraeInstallation.traeVersion else {
                return .closed(availability: .unsupportedVersion, setupStatus: .reviewRequired,
                    diagnostic: "Trae \(instances.first?.version ?? "(version unavailable)") is not supported. This build supports Trae \(TraeInstallation.traeVersion).")
            }
        case .notChecked:
            return .closed(availability: .disconnected, setupStatus: .reviewRequired, diagnostic: nil)
        }
        let pid = await presence.processIdentifier()
        if replaceProcess(pid) {
            transport.stop()
            await repository.resetIntegrationObservation(clearTurns: true)
        }
        guard pid != nil else {
            return .closed(availability: .disconnected, setupStatus: .reviewRequired,
                           diagnostic: nil)
        }
        transport.start()
        return .open(await transport.reading().0 ? .active : .reviewRequired)
    }
    func currentPresence() async -> AgentPresence { await presence.presence() }

    func confirmActivation() { recordInstallationPID(nil) }
    func recordInstalledIntoOpenApplication() async {
        let pid = await presence.processIdentifier()
        recordInstallationPID(pid)
    }
    private func recordInstallationPID(_ pid: Int32?) {
        identityLock.lock(); defer { identityLock.unlock() }; installedIntoPID = pid
    }
    func needsWindowReload() async -> Bool {
        let pid = await presence.processIdentifier()
        return matchesInstallationPID(pid)
    }
    private func matchesInstallationPID(_ pid: Int32?) -> Bool {
        identityLock.lock(); defer { identityLock.unlock() }
        return pid != nil && installedIntoPID == pid
    }

    private func replaceProcess(_ pid: Int32?) -> Bool {
        identityLock.lock(); defer { identityLock.unlock() }
        let changed = productPID != nil && productPID != pid
        productPID = pid
        return changed
    }
    func disconnect() { transport.stop() }
    func stopWatching() async {}
    func read(observing state: MonitoringStateSnapshot) async -> SessionReading {
        let present = await presence.presence()
        if present == .closed { return SessionReading(presence: .closed, admission: .unknown) }
        let (healthy, diagnostic) = await transport.reading()
        return SessionReading(presence: healthy ? .open : .unknown, admission: .unknown,
                              unwatchableReason: diagnostic)
    }
    func content(for turns: [MonitoredTurnState], messages: TurnMessageReading) async -> [String: RowContent] {
        let current = await transport.content()
        var content: [String: RowContent] = [:]
        for turn in turns {
            guard let row = current[turn.threadID], row.turnID == turn.turnID else { continue }
            content[turn.threadID] = RowContent(
                projectName: WorkingDirectoryRowContent.projectName(forWorkingDirectory: row.folder),
                // Empty when Trae has none; ``MonitoredSession/init`` supplies the fallback.
                title: row.title,
                preview: row.preview)
        }
        return content
    }
}

@MainActor
final class TraeNavigator: AgentNavigating {
    private let transport: TraeBridgeTransport
    init(transport: TraeBridgeTransport) { self.transport = transport }
    func open(_ session: MonitoredSession) async throws -> NavigationOutcome {
        guard session.agent == .trae, TraeEvidenceBoundary.validID(session.threadID),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.trae.app").first else {
            throw TraeBridgeError.unavailable
        }
        guard let path = await transport.route(for: session.threadID) else {
            app.activate(); return .raisedApplication(host: "Trae")
        }
        let opened = await Task.detached { Self.navigate(path: path, threadID: session.threadID) }.value
        if !opened { app.activate() }
        return opened ? .openedThread(host: "Trae") : .raisedApplication(host: "Trae")
    }
    nonisolated private static func navigate(path: String, threadID: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var timeout = timeval(tv_sec: 9, tv_usec: 0), noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        guard TraeBridgeTransport.connect(fd, path: path) == 0 else { return false }
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid(),
              let request = try? JSONSerialization.data(withJSONObject: ["op":"navigate", "threadID":threadID]) else { return false }
        let bytes = request + Data([10])
        guard bytes.withUnsafeBytes({ Darwin.write(fd, $0.baseAddress, $0.count) }) == bytes.count else { return false }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 512)
        while data.count < 1024 {
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count > 0 else { return false }
            data.append(contentsOf: buffer.prefix(count))
            if data.contains(10) { break }
        }
        guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Bool] else { return false }
        return result["ok"] == true
    }
}
