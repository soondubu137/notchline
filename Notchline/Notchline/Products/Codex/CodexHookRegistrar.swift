import Foundation

/// Registers this app's definitions in `~/.codex/hooks.json` and installs their helper.
///
/// The definition is never rewritten after first install. Codex keys trust by content hash
/// in `config.toml`, and silently stops running a changed definition until re-trusted
/// (`PreToolUse` dead two turns, 2026-08-15). Versioning lives in the unhashed script.
/// The key is `[hooks.state."…/hooks.json:pre_tool_use:0:0"]`, group and handler by index
/// (2026-08-20), so removing a middle group drops later groups' trust
/// (``ManagedHooksConfiguration`` appends at the tail).
actor CodexHookRegistrar: HookRegistrationSetup {
    /// From the vocabulary, so the registrar never registers a hook whose events are discarded.
    nonisolated private static let managedDefinitions =
        CodexHookVocabulary().managedDefinitions

    private let paths: HookIntegrationPaths
    private let fileManager: FileManager
    nonisolated private let configurationWatcher: DirectoryChangeWatcher
    /// Kept with the change count taken at read time; apart, they race.
    private var cachedRegistration: (changeCount: UInt64, health: HookRegistration)?

    init(
        paths: HookIntegrationPaths = .live(),
        fileManager: FileManager = .default,
        timing: MonitorTiming = .standard
    ) {
        self.paths = paths
        self.fileManager = fileManager
        // Health changes only when we or the user write the file, so it is re-read on that edge.
        self.configurationWatcher = DirectoryChangeWatcher(
            directoryURL: paths.hooksConfiguration,
            debounceInterval: timing.unreadStateDebounceInterval
        )
    }

    nonisolated var integrationPaths: HookIntegrationPaths { paths }

    nonisolated var socketURL: URL {
        paths.hookSocket
    }

    nonisolated func changeEvents() -> AsyncStream<Void> {
        configurationWatcher.events()
    }

    /// Read from `hooks.json` only, cached until our own writes or a file change, never a timer.
    /// The watcher's change count is compared across the read rather than subscribing to the
    /// edge, which raced a second consumer and cached a stale reading (CR-028).
    func registration() -> HookRegistration {
        // On a first run `hooks.json` did not exist at `init`, so the attach is retried per ask.
        configurationWatcher.attachIfNeeded()
        // Read after the attach: an attach counts as a change.
        let changeCount = configurationWatcher.changeCount
        if let cachedRegistration, cachedRegistration.changeCount == changeCount {
            return cachedRegistration.health
        }
        let scanned = paths.readRegistration(configuration: managedConfiguration, fileManager: fileManager)
        cachedRegistration = (changeCount, scanned)
        return scanned
    }

    func invalidateRegistration() {
        cachedRegistration = nil
    }

    /// A `stat`, the one helper question a refresh may ask: a user can empty the support folder,
    /// and `/bin/sh` on a missing path is a hook error in the session (ADR 0013).
    var isHelperInstalled: Bool {
        fileManager.isExecutableFile(atPath: paths.hookHelper.path)
    }

    /// Writes the helper if it differs from this build's. Called at launch, on install, and when
    /// ``isHelperInstalled`` says it is gone; never per refresh.
    @discardableResult
    func prepareHelper() -> Bool {
        didCompareHelperThisLaunch = true
        return AgentHookHelper.prepare(
            at: paths,
            answerWindowSeconds: CodexHookVocabulary().answerWindowSeconds,
            fileManager: fileManager
        ) != .failed
    }

    private var didCompareHelperThisLaunch = false

    /// Binds the socket on every refresh; compares the helper once per launch and again only if
    /// the `stat` fails. The socket is bound whatever the write says: a helper already on disk
    /// still delivers.
    func prepareHelperForTransport() -> Bool {
        if !didCompareHelperThisLaunch || !isHelperInstalled {
            prepareHelper()
        }
        return true
    }

    /// Legacy setup status from registration and delivery. The Codex Provider refines it with
    /// public `hooks/list` activation evidence on servers supporting that method.
    func status(observedBy repository: HookEventRepository) async -> IntegrationSetupStatus {
        IntegrationSetupStatus.card(
            registration: registration(),
            hasObservedEvent: await repository.observedState().hasObservedEvent
        )
    }

    func install() throws {
        // A no-op install writes nothing: a rewrite reformats a file this app does not own, and the
        // trust key's index-based group component makes it risky for the user's definitions.
        guard registration() != .complete else { return }

        try fileManager.createDirectory(
            at: paths.agentDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard prepareHelper() else {
            throw ManagedHooksConfigurationError.verificationFailed
        }
        // Read before the write, because the question is what changed.
        let rewritten = managedConfiguration.eventsWhoseDefinitionChanges(
            comparedTo: readConfigurationRoot()
        )
        try configurationEditor.install()
        removeRetiredArtifacts()
        HookInstallStateFile.update(at: paths.installState, fileManager: fileManager) {
            $0.installedAt = Date()
            $0.eventsAwaitingTrust = rewritten.isEmpty ? nil : rewritten
        }
        cachedRegistration = nil
    }

    func uninstall() throws {
        cachedRegistration = nil
        try configurationEditor.remove()

        for url in [paths.hookHelper, paths.installState, paths.hookSocket] {
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }
        removeRetiredArtifacts()
        // Only this product's directory, then the shared ones if empty.
        removeDirectoryIfEmpty(paths.agentDirectory)
        removeDirectoryIfEmpty(paths.agentDirectory.deletingLastPathComponent())
        removeDirectoryIfEmpty(paths.supportDirectory)
    }

    // MARK: - Internals

    private func readConfigurationRoot() -> [String: Any]? {
        paths.readConfigurationRoot(fileManager: fileManager)
    }

    private func removeRetiredArtifacts() {
        for url in paths.retiredArtifacts
        where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func removeDirectoryIfEmpty(_ url: URL) {
        guard let remaining = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ), remaining.isEmpty else { return }
        try? fileManager.removeItem(at: url)
    }

    /// The one string this app registers, and never rewrites. A script file, not an inlined
    /// helper, so behaviour can change without touching the hashed definition.
    nonisolated static func command(forHelper helper: URL) -> String {
        AgentHookHelper.shellCommandLine(forHelper: helper)
    }

    private var managedConfiguration: ManagedHooksConfiguration {
        .command(
            Self.command(forHelper: paths.hookHelper),
            legacyCommands: CodexHookVocabulary().legacyCommandMarkers,
            definitions: Self.managedDefinitions,
            descriptionForNewFiles: "User-level Codex lifecycle hooks."
        )
    }

    private var configurationEditor: ManagedHooksFileEditor {
        ManagedHooksFileEditor(
            url: paths.hooksConfiguration,
            recoveryCopyURL: paths.hooksBackup,
            configuration: managedConfiguration,
            fileManager: fileManager
        )
    }
}
