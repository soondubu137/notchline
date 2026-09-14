import Foundation

/// Installs a product's hook registration and the helper it names, for any product whose file
/// this app may write and whose hooks need no trust step (`tiered-support.md` §5.4).
///
/// - Codex uses ``CodexHookRegistrar``: its definitions are trusted one by one (ADR 0014).
/// - The settings file stays the user's (ADR 0016); edits go through ``ManagedHooksFileEditor``.
/// - A `command` handler, not an `http` port: an unowned port printed `connect ECONNREFUSED` per
///   event and could be taken by any local process (CC-021, CC-014). 6.3 ms per event.
actor ManagedHooksSetup: HookRegistrationSetup {
    private let paths: HookIntegrationPaths
    private let vocabulary: any AgentHookVocabulary
    private let fileManager: FileManager

    init(
        paths: HookIntegrationPaths,
        vocabulary: any AgentHookVocabulary,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.vocabulary = vocabulary
        self.fileManager = fileManager
    }

    nonisolated var settingsURL: URL {
        paths.hooksConfiguration
    }

    /// Where that file is copied before every change this app makes to it.
    nonisolated var settingsBackupURL: URL {
        paths.hooksBackup
    }

    /// Where the helper hands each payload, and where the listener binds.
    nonisolated var socketURL: URL {
        paths.hookSocket
    }

    // MARK: - The helper

    /// Writes the helper if it is missing or stale (one read, a string compare). Called where the
    /// socket binds, since hooks may predate this app's directory. Reports failure, not throws.
    @discardableResult
    func prepareHelper() -> Bool {
        switch AgentHookHelper.prepare(
            at: paths,
            answerWindowSeconds: vocabulary.answerWindowSeconds,
            announcesEvent: vocabulary.registrationDialect.eventNameArrivesAsArgument,
            fileManager: fileManager
        ) {
        case .current:
            return true
        case .written:
            // A fresh helper is the moment to clear what earlier builds left; nothing else is deleted.
            for url in paths.retiredArtifacts
            where fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
            return true
        case .failed:
            return false
        }
    }

    /// Every refresh: cheap, and a missing or stale helper must never stay while registered.
    func prepareHelperForTransport() -> Bool {
        prepareHelper()
    }

    // MARK: - Reading what is registered

    /// How complete the registration is, read-only. No trust step, so a complete registration
    /// reports connected directly.
    func status() -> IntegrationSetupStatus {
        IntegrationSetupStatus.card(
            registration: paths.readRegistration(configuration: configuration, fileManager: fileManager),
            hasObservedEvent: true
        )
    }

    func status(observedBy repository: HookEventRepository) -> IntegrationSetupStatus {
        status()
    }

    // MARK: - Writing the registration

    /// Adds this build's definitions to the user's settings, keeping a copy of the file. A helper
    /// write failure stops the install: a missing script prints `ENOENT: ... posix_spawn` per event.
    func install() throws {
        guard prepareHelper() else {
            throw ManagedHooksConfigurationError.verificationFailed
        }
        try configurationEditor.install()
    }

    /// Takes every trace of this app out of the user's settings. The helper and socket stay in the
    /// support directory: nothing runs them, and `prepareTransport()` would recreate them.
    func uninstall() throws {
        try configurationEditor.remove()
    }

    // MARK: - Internals

    /// The definitions and handlers this build writes. Not private: test fixtures read it so they
    /// cannot drift from what the product writes.
    nonisolated var configuration: ManagedHooksConfiguration {
        let dialect = vocabulary.registrationDialect
        return .command(
            dialect.handlersAreShellCommandLines
                ? AgentHookHelper.shellCommandLine(forHelper: paths.hookHelper)
                : paths.hookHelper.path,
            arguments: dialect.handlersAreShellCommandLines ? nil : [],
            containerKey: dialect.containerKey,
            legacyCommands: vocabulary.legacyCommandMarkers,
            definitions: vocabulary.managedDefinitions,
            // No `description`: Claude Code validates this file's keys, and Antigravity CLI would read one
            // as a hook named `description` and refuse the file.
            descriptionForNewFiles: nil
        )
    }

    private var configurationEditor: ManagedHooksFileEditor {
        ManagedHooksFileEditor(
            url: paths.hooksConfiguration,
            recoveryCopyURL: paths.hooksBackup,
            configuration: configuration,
            fileManager: fileManager
        )
    }

    private func readSettings() -> [String: Any]? {
        paths.readConfigurationRoot(fileManager: fileManager)
    }
}

extension HookIntegrationPaths {
    nonisolated static func liveClaudeCode(
        fileManager: FileManager = .default
    ) -> HookIntegrationPaths {
        live(for: .claudeCode, fileManager: fileManager)
    }
}
