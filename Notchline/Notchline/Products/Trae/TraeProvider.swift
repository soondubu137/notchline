import AppKit
import Darwin
import Foundation

/// One composition centre for Trae. Read evidence retires rows through the
/// shared gate; navigation and the reading-only request surface stay separate.
struct TraeProvider: AgentMonitoring, IntegrationConfiguring {
    nonisolated let agent = AgentKind.trae
    private let runtime: ProductMonitoringRuntime
    let source: TraeSource
    nonisolated var stateChangeEvents: AsyncStream<Void> { runtime.stateChangeEvents }

    init(installation: TraeInstallation = TraeInstallation()) {
        let source = TraeSource(installation: installation)
        self.source = source
        let readEvidence = TraeReadEvidence(screen: ScreenAvailabilityWatcher(),
            foreground: DesktopReadingWatcher(bundleIdentifier: "com.trae.app"), transport: source.transport)
        runtime = ProductMonitoringRuntime(agent: .trae, lifecycle: source, sessions: source,
                                           rowContent: source, readEvidence: readEvidence,
                                           changeEvents: [source.transport.changes.events()])
    }
    func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot {
        await runtime.fetchSnapshot(dismissedRowIDs: dismissedRowIDs)
    }
    func nextRefreshDeadline() async -> Date? { await runtime.nextRefreshDeadline() }
    func disconnect() async { await runtime.disconnect() }
    func setupStatus() async -> IntegrationSetupStatus {
        switch source.installation.registration {
        case .absent: return .notInstalled
        case .mismatched: return .repairRequired
        case .current: return await source.transport.reading().0 ? .active : .reviewRequired
        }
    }
    func installIntegration() async throws { try await source.installation.install() }
    func removeIntegration() async throws {
        await runtime.disconnect()
        try await source.installation.remove()
    }
}

nonisolated final class TraeSource: MonitoringLifecycleSource, ProductSessionReading, RowContentSource, @unchecked Sendable {
    let repository = MonitoringRepository(policy: .explicit)
    let installation: TraeInstallation
    let transport: TraeBridgeTransport
    private let identityLock = NSLock()
    private var productPID: Int32?
    private let presence: RunningApplicationPresence
    @MainActor
    init(installation: TraeInstallation) {
        self.installation = installation
        presence = RunningApplicationPresence(bundleIdentifiers: ["com.trae.app"])
        transport = TraeBridgeTransport(directory: installation.directory, repository: repository)
    }
    func gate(productName: String) async -> MonitoringSourceGate {
        switch installation.registration {
        case .absent:
            return .closed(availability: .setupRequired, setupStatus: .notInstalled,
                           diagnostic: "Switch Trae on to install its companion extension.")
        case .mismatched:
            return .closed(availability: .setupRequired, setupStatus: .repairRequired,
                           diagnostic: "Trae has a different version of the companion installed. "
                               + "Turn the switch off, then on, to reinstall it.")
        case .current:
            break
        }
        guard installation.compatible else {
            return .closed(availability: .unsupportedVersion, setupStatus: .reviewRequired,
                           diagnostic: TraeBridgeError.version.localizedDescription)
        }
        let pid = await presence.processIdentifier()
        if replaceProcess(pid) {
            transport.stop()
            await repository.resetIntegrationObservation(clearTurns: true)
        }
        guard pid != nil else {
            return .closed(availability: .disconnected, setupStatus: .reviewRequired,
                           diagnostic: "Open Trae to connect its companion.")
        }
        transport.start()
        return .open(await transport.reading().0 ? .active : .reviewRequired)
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
                              unwatchableReason: diagnostic ?? TraeBridgeError.unavailable.localizedDescription)
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
