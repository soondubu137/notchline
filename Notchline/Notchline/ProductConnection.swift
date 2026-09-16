import AppKit
import Foundation

/// Facts about setup and observation. Neither a saved preference nor a past connection proves
/// that a product is installed or observable now. These values never enter the Turn reducer.
nonisolated enum ProductMonitoringIntent: String, Sendable {
    case enabled, disabled
}

nonisolated struct ProductInstallationInstance: Equatable, Sendable {
    let url: URL
    let version: String?
    let surface: String
}

nonisolated enum ProductInstallationReading: Equatable, Sendable {
    case found([ProductInstallationInstance])
    /// Discovery is bounded; this is not proof that the user uninstalled the product.
    case notFound
    case unknown(String)
    case notChecked
}

nonisolated enum ProductConnectionAction: Equatable, Sendable {
    case repair, recheck, remove
}

nonisolated struct ProductConnectionNotice: Equatable, Sendable {
    enum Severity: Equatable, Sendable { case information, warning }
    enum Scope: Equatable, Sendable { case setup, observation, capability }
    let severity: Severity
    let scope: Scope
    let message: String
}

nonisolated struct ProductConnectionFacts: Equatable, Sendable {
    enum Activation: Equatable, Sendable { case notRequired, unverified, verified, reloadRequired }
    enum Health: Equatable, Sendable {
        case notApplicable, checking, available, connecting, reconnecting, unavailable, partial
    }
    var installation: ProductInstallationReading = .notChecked
    var activation: Activation = .notRequired
    var health: Health = .checking
    var notice: ProductConnectionNotice?
    /// Check provenance is for detail, not an overlay invalidation on every clock tick.
    var checkedAt: Date?

    static func observed(setup: IntegrationSetupStatus, availability: MonitorAvailability,
                         diagnostic: String?) -> Self {
        let health: Health = switch availability {
        case .ready: .available
        case .connecting: .connecting
        case .disconnected: .unavailable
        default: .notApplicable
        }
        return Self(activation: setup == .reviewRequired ? .unverified : .notRequired,
                    health: health, notice: diagnostic.map {
            .init(severity: health == .unavailable ? .warning : .information,
                  scope: health == .available ? .capability : .observation, message: $0)
        })
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.installation == rhs.installation && lhs.activation == rhs.activation
            && lhs.health == rhs.health && lhs.notice == rhs.notice
    }
}

/// Shared, pure presentation rule. Product boundaries supply facts; no view interprets files,
/// process lists, diagnostics or product-specific protocol errors.
nonisolated struct ProductConnectionPresentation: Equatable, Sendable {
    enum Tone: Equatable, Sendable { case neutral, healthy, warning }
    let status: String
    var tone: Tone = .neutral
    var notice: ProductConnectionNotice?
    var action: ProductConnectionAction?

    static func make(snapshot: AgentSnapshot, intent: ProductMonitoringIntent?, configurable: Bool) -> Self {
        let facts = snapshot.connection
        func result(_ status: String, _ tone: Tone = .neutral,
                    _ message: String? = nil, _ action: ProductConnectionAction? = nil,
                    scope: ProductConnectionNotice.Scope = .setup) -> Self {
            Self(status: status, tone: tone,
                 notice: message.map { .init(severity: tone == .warning ? .warning : .information,
                                             scope: scope, message: $0) }, action: action)
        }
        if intent == .disabled { return result("Off") }
        // A running instance is stronger evidence than an incomplete installation search.
        if facts.installation == .notFound && snapshot.presence != .open {
            return result("App not found", .neutral,
                          snapshot.setupStatus.isIntegrationEnabled || snapshot.setupStatus == .repairRequired
                          ? "Notchline setup remains." : intent == .enabled ? "Monitoring remains enabled." : nil, .recheck)
        }
        let enabled = !configurable || intent == .enabled || snapshot.setupStatus.isIntegrationEnabled
        if snapshot.setupStatus == .unreadable {
            return result("Unable to check setup", enabled ? .warning : .neutral,
                          "The setup file could not be read or its format is unrecognised.", .recheck)
        }
        if configurable {
            switch snapshot.setupStatus {
            case .notInstalled:
                return enabled
                    ? result("Setup needs repair", .warning, "Notchline’s settings are missing.", .repair)
                    : result("Not set up")
            case .repairRequired:
                return result("Setup needs repair", enabled ? .warning : .neutral,
                              "Notchline’s settings are incomplete or out of date.", .repair)
            default: break
            }
        }
        if snapshot.availability == .unsupportedVersion || snapshot.availability == .updateAgent {
            return result("Version unsupported", enabled ? .warning : .neutral,
                          snapshot.diagnostic, .recheck)
        }
        // A normal exit is not an observation failure, even if the transport just closed.
        if snapshot.presence == .closed {
            return result(snapshot.agent == .claudeCode ? "Not running" : "Not open")
        }
        if case let .unknown(reason) = facts.installation {
            return result("Unable to check", .neutral, reason, .recheck)
        }
        if facts.activation == .reloadRequired {
            return result("Window reload required", .neutral,
                          "The companion will load when you next reopen the product’s windows.")
        }
        switch facts.health {
        case .checking where facts.notice != nil: return result("Checking…", .neutral, facts.notice?.message)
        case .connecting: return result("Connecting…")
        case .reconnecting: return result("Reconnecting…")
        case .unavailable:
            return result("Connection unavailable", enabled ? .warning : .neutral,
                          facts.notice?.message ?? "The observation connection could not be established.",
                          .recheck, scope: .observation)
        case .partial:
            return result("Partially connected", .warning, facts.notice?.message, .recheck, scope: .observation)
        default: break
        }
        if snapshot.presence == .unknown { return result("Unable to check", .neutral, facts.notice?.message, .recheck) }
        if facts.activation == .unverified {
            return result("Set up · not yet verified", .neutral,
                          snapshot.agent == .codex
                          ? "If the new Hooks have not been trusted, review them under /hooks in Codex."
                          : nil)
        }
        if snapshot.isConnected {
            // Supplementary failures explain a capability, never turn a healthy connection red.
            return Self(status: "Connected", tone: .healthy, notice: facts.notice, action: nil)
        }
        return result("Set up · not yet verified", .neutral, nil, .recheck)
    }
}

/// Provider-owned check policy. Discovery is single-flight, bounded and invalidated explicitly;
/// lifecycle evidence continues to use its existing ordering and expiry rules.
actor ProductConnectionMonitor {
    typealias Discover = @Sendable () async -> ProductInstallationReading
    nonisolated let changes = MonitoringChangeBroadcast()
    private let wakeups: ProductConnectionWakeups?
    private var wakeupTask: Task<Void, Never>?
    private var lastWakeRevision = 0
    private let discover: Discover
    private let clock: any MonitorClock
    private var discovery: (Date, ProductInstallationReading)?
    private var pending: Task<ProductInstallationReading, Never>?
    private var generation = 0
    /// Bumped only by `reset`: a check retired by a newer one joins it, one retired by a disconnect stops.
    private var lifetime = 0
    private var failureSince: Date?
    private var wasConnected = false
    private var lastPresence: AgentPresence?

    init(clock: any MonitorClock = SystemMonitorClock(), wakeups: ProductConnectionWakeups? = nil,
         discover: @escaping Discover) {
        self.clock = clock; self.discover = discover; self.wakeups = wakeups
    }
    deinit { wakeupTask?.cancel() }
    private func receiveEdge() {
        invalidate()
        // Wake/sleep breaks continuity; do not turn time asleep into a connection warning.
        if let wakeups, wakeups.wakeRevision != lastWakeRevision {
            lastWakeRevision = wakeups.wakeRevision
            failureSince = nil
        }
        changes.signal()
    }
    private func startWakeups() {
        guard wakeupTask == nil, let wakeups else { return }
        let events = wakeups.changes.events()
        wakeupTask = Task { [weak self] in
            for await _ in events {
                guard !Task.isCancelled else { break }
                await self?.receiveEdge()
            }
        }
    }
    func invalidate() {
        generation += 1; discovery = nil; pending?.cancel(); pending = nil
    }
    func reset() { invalidate(); lifetime += 1; failureSince = nil; wasConnected = false; lastPresence = nil }
    func nextDeadline() -> Date? {
        guard let since = failureSince else { return nil }
        let end = since.addingTimeInterval(10)
        return end > clock.now() ? end : nil
    }

    func installation(presence: AgentPresence) async -> ProductInstallationReading {
        startWakeups()
        if presence != lastPresence { invalidate(); lastPresence = presence }
        let life = lifetime
        // A retired result is never returned. Reporting it as unknown drew `Unable to check` until
        // the next refresh, so join the check that retired it; a bound stops an edge storm holding it.
        for _ in 0..<3 {
            let epoch = generation
            let now = clock.now()
            if let cached = discovery, now.timeIntervalSince(cached.0) < 30 { return cached.1 }
            let task = pending ?? Task { await discover() }
            pending = task
            let reading = await task.value
            if epoch == generation {
                pending = nil; discovery = (now, reading)
                wakeups?.watchInstallation(reading)
                return reading
            }
            guard life == lifetime, !Task.isCancelled else { break }
        }
        return .unknown("The product changed during the check. Check again.")
    }

    func inspect(_ snapshot: AgentSnapshot) async -> AgentSnapshot {
        let installation = await installation(presence: snapshot.presence)
        let now = clock.now()
        var facts = snapshot.connection
        facts.installation = installation
        facts.checkedAt = now
        if snapshot.setupStatus == .reviewRequired && facts.activation == .notRequired {
            facts.activation = .unverified
        }
        if snapshot.presence == .closed {
            failureSince = nil; wasConnected = false
            facts.health = .notApplicable; facts.notice = nil
        } else if snapshot.availability == .ready {
            failureSince = nil; wasConnected = snapshot.isConnected
            if facts.health != .partial { facts.health = .available }
            if facts.notice == nil, let message = snapshot.diagnostic {
                facts.notice = .init(severity: .information, scope: .capability, message: message)
            }
        } else if snapshot.availability == .connecting {
            facts.health = wasConnected ? .reconnecting : .connecting
        } else if snapshot.availability == .disconnected && snapshot.setupStatus.isIntegrationEnabled {
            // Silence before first use is not evidence of failure. Trae supplies explicit transport
            // failures separately; no peer ever seen simply stays unverified.
            if snapshot.agent == .trae && facts.health == .checking && snapshot.diagnostic == nil {
                if facts.activation != .reloadRequired { facts.activation = .unverified }
            } else {
                if failureSince == nil { failureSince = now }
                let recovering = now.timeIntervalSince(failureSince ?? now) < 10
                facts.health = recovering ? (wasConnected ? .reconnecting : .checking) : .unavailable
                facts.notice = snapshot.diagnostic.map {
                    .init(severity: recovering ? .information : .warning, scope: .observation, message: $0)
                }
            }
        }
        return snapshot.withConnection(facts)
    }
}

extension AgentSnapshot {
    nonisolated func withConnection(_ facts: ProductConnectionFacts, presence: AgentPresence? = nil) -> Self {
        Self(agent: agent, availability: availability, sessions: sessions, quota: quota,
             diagnostic: diagnostic, setupStatus: setupStatus, presence: presence ?? self.presence,
             connection: facts)
    }
}

/// Installation discovery never launches a product, opens a shell or scans unrelated files.
/// Running applications take precedence over Launch Services and conventional locations.
nonisolated enum ProductInstallationDiscovery {
    @MainActor static func application(bundleID: String, name: String) -> ProductInstallationReading {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated }.compactMap(\.bundleURL)
        let candidates = running.isEmpty
            ? [NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
               URL(fileURLWithPath: "/Applications/\(name).app"),
               FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(name).app")].compactMap { $0 }
            : running
        var found: [ProductInstallationInstance] = []
        var uncertainty: String?
        for url in Set(candidates).sorted(by: { $0.path < $1.path }) {
            switch metadata(at: url, bundleID: bundleID) {
            case let .found(instances): found += instances
            case let .unknown(reason): uncertainty = reason
            default: break
            }
        }
        if let uncertainty { return .unknown(uncertainty) }
        return found.isEmpty ? .notFound : .found(found)
    }

    /// Read fresh bytes: Bundle can cache its Info dictionary across an in-place application update.
    static func metadata(at url: URL, bundleID: String) -> ProductInstallationReading {
        do {
            let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
            guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let identifier = root["CFBundleIdentifier"] as? String else {
                return .unknown("The application’s information file has an unrecognised format.")
            }
            guard identifier == bundleID else { return .notFound }
            return .found([.init(url: url, version: root["CFBundleShortVersionString"] as? String, surface: "Desktop")])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return FileManager.default.fileExists(atPath: url.path)
                ? .unknown("The application’s information file is missing.") : .notFound
        }
        catch { return .unknown("The application’s information file could not be read.") }
    }
    static func live(_ agent: AgentKind) -> ProductConnectionMonitor {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let identifiers: Set<String> = switch agent {
        case .codex: [CodexDesktopNavigator.desktopBundleIdentifier]
        case .claudeCode: [ClaudeCodeMonitorService.desktopBundleIdentifier]
        case .antigravity: [AntigravityDesktopApplication.bundleIdentifier]
        case .trae: ["com.trae.app"]
        }
        let setupDirectory: URL = switch agent {
        case .codex: home.appendingPathComponent(".codex")
        case .claudeCode: home.appendingPathComponent(".claude")
        case .antigravity: home.appendingPathComponent(".gemini/config")
        case .trae: home.appendingPathComponent(".trae/extensions")
        }
        let wakeups = ProductConnectionWakeups(bundleIdentifiers: identifiers,
            paths: [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications"), setupDirectory])
        return ProductConnectionMonitor(wakeups: wakeups) {
            switch agent {
            case .codex:
                let desktop = await application(bundleID: CodexDesktopNavigator.desktopBundleIdentifier, name: "Codex")
                let command = await Task.detached { Self.command(named: "codex") }.value
                var instances: [ProductInstallationInstance] = []
                if case let .found(found) = desktop { instances = found }
                if let command { instances.append(.init(url: command, version: nil, surface: "CLI")) }
                if !instances.isEmpty { return .found(instances) }
                return desktop
            case .trae:
                return await application(bundleID: "com.trae.app", name: "Trae")
            case .claudeCode:
                return await Task.detached {
                    guard let url = ClaudeExecutableLocator.locate() else { return ProductInstallationReading.notFound }
                    return .found([.init(url: url, version: nil, surface: "CLI")])
                }.value
            case .antigravity:
                let desktop = await application(bundleID: AntigravityDesktopApplication.bundleIdentifier, name: "Antigravity")
                let command = await Task.detached { Self.command(named: "agy") }.value
                var instances: [ProductInstallationInstance] = []
                if case let .found(found) = desktop { instances = found }
                if let command { instances.append(.init(url: command, version: nil, surface: "CLI")) }
                return instances.isEmpty ? .notFound : .found(instances)
            }
        }
    }

    /// Every directory a CLI this app monitors can be installed into, in the order a tie is
    /// broken. The one list: ``CodexExecutableLocator`` searches it too, so the binary the App
    /// Server runs and the install Settings names cannot come from different searches.
    ///
    /// The first three are where the products' own installers put things. The rest exist because
    /// a CLI shipped on npm lands wherever the user's package or version manager keeps binaries,
    /// and **`PATH` cannot be relied on to find them**: this app is launched by the window server,
    /// not by a login shell, so its `PATH` is the system default and holds none of them. It stays
    /// last as a fallback for the case where it does carry something, and for a debug run from a
    /// terminal.
    ///
    /// The list is necessarily incomplete — nvm- and fnm-style layouts put the binary under a
    /// version directory that changes with every upgrade, and nothing can enumerate those. That is
    /// survivable because **no row depends on it**: a running CLI is identified by what the process
    /// is, not by matching it against this list (``CodexNativeProcesses/localTUI(_:)``).
    static func commandDirectories(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [URL] {
        var directories = [
            home.appendingPathComponent(".local/bin"),
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
            // MacPorts.
            URL(fileURLWithPath: "/opt/local/bin"),
            // Version managers, which shim every tool they manage into one directory.
            home.appendingPathComponent(".local/share/mise/shims"),
            home.appendingPathComponent(".asdf/shims"),
            home.appendingPathComponent(".volta/bin"),
            home.appendingPathComponent(".bun/bin")
        ]
        let known = Set(directories.map(\.path))
        directories += (environment["PATH"] ?? "").split(separator: ":")
            .map { URL(fileURLWithPath: String($0)) }
            .filter { !known.contains($0.path) }
        return directories
    }

    static func command(named name: String) -> URL? {
        commandDirectories().map { $0.appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

nonisolated struct ProductOperationFailure: Equatable, Sendable {
    let status: String
    let message: String
    let action: ProductConnectionAction
}

/// Passive native and file edges; no timer and no private window inventory. Owns its observer
/// tokens, and tears them down with the Provider. Actual evidence is re-read after each edge.
nonisolated final class ProductConnectionWakeups: @unchecked Sendable {
    let files = PathSetChangeWatcher(debounceInterval: 0.1)
    let changes = MonitoringChangeBroadcast()
    private let notifications: NotificationCenter
    private let basePaths: Set<URL>
    private var observers: [NSObjectProtocol] = []
    private var forwarder: Task<Void, Never>?
    private let lock = NSLock()
    private var wakes = 0
    var wakeRevision: Int { lock.lock(); defer { lock.unlock() }; return wakes }

    init(bundleIdentifiers: Set<String>, paths: Set<URL>,
         notifications: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.notifications = notifications
        self.basePaths = paths
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didWakeNotification] {
            observers.append(notifications.addObserver(forName: name, object: nil, queue: nil) { [weak self] note in
                if name != NSWorkspace.didWakeNotification {
                    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          let identifier = app.bundleIdentifier, bundleIdentifiers.contains(identifier) else { return }
                }
                if name == NSWorkspace.didWakeNotification { self?.recordWake() }
                self?.changes.signal()
            })
        }
        let events = files.events()
        files.watch(paths: paths)
        let changes = changes
        forwarder = Task {
            for await _ in events {
                guard !Task.isCancelled else { break }
                changes.signal()
            }
        }
    }
    func watchInstallation(_ reading: ProductInstallationReading) {
        var paths = basePaths
        if case let .found(instances) = reading {
            for instance in instances {
                paths.insert(instance.surface == "Desktop"
                    ? instance.url.appendingPathComponent("Contents/Info.plist") : instance.url)
            }
        }
        files.watch(paths: paths)
    }
    private func recordWake() { lock.lock(); wakes += 1; lock.unlock() }
    deinit {
        observers.forEach { notifications.removeObserver($0) }
        forwarder?.cancel()
    }
}
