import Foundation

/// Registers this app's lifecycle hooks in the user's Claude Code settings.
///
/// Simpler than the Codex installer in one way and more delicate in another.
/// Simpler because there is no helper script: Claude Code posts to this app
/// directly, so there is nothing to write, upgrade, hash or leave dangling.
/// More delicate because `~/.claude/settings.json` is where a user keeps
/// everything about their install — theme, environment, permissions, their own
/// hooks — where `~/.codex/hooks.json` holds hooks and little else. Both go
/// through ``ManagedHooksFileEditor``, which refuses rather than coerces.
actor ClaudeCodeHookInstaller {
    /// The path inside the hook URL that identifies this app's handler.
    ///
    /// Deliberately not the whole URL: the port is allowed to move when the one
    /// in the settings is already taken, and a handler that became
    /// unrecognisable on a rebind could neither be replaced nor removed.
    static let hookPath = "/codex-in-notch/hook"

    private let paths: HookIntegrationPaths
    private let vocabulary: any AgentHookVocabulary
    private let fileManager: FileManager

    init(
        paths: HookIntegrationPaths,
        vocabulary: any AgentHookVocabulary = ClaudeCodeHookVocabulary(),
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.vocabulary = vocabulary
        self.fileManager = fileManager
    }

    /// What the installed configuration says, so a listener can try to keep the
    /// port the user's file already names.
    struct Registration: Sendable, Equatable {
        let port: UInt16
        let token: String
    }

    /// Registers the hooks against a listener that is already bound.
    ///
    /// The port comes from the live listener rather than being chosen here,
    /// because a port that cannot be bound is worse than one that moved: the
    /// configuration would name somewhere nothing is listening and no event
    /// would ever arrive.
    func install(port: UInt16, token: String) throws {
        try fileManager.createDirectory(
            at: paths.agentDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try editor(port: port, token: token).install()
        try writeRegistration(Registration(port: port, token: token))
    }

    func uninstall() throws {
        // Any port and token: the handler is found by its path, so removal does
        // not depend on knowing what it was installed with.
        try editor(port: 0, token: "").remove()
        for url in [paths.installMarker, paths.eventsDirectory]
        where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Whether every managed definition is registered against this listener.
    func isInstalled(port: UInt16, token: String) -> Bool {
        editor(port: port, token: token).isInstalled()
    }

    /// The port and token the installed configuration names, if any.
    ///
    /// Read from this app's own marker rather than parsed back out of the
    /// user's settings: the settings are the thing being written, and treating
    /// them as the source of truth for what we wrote makes a corrupted edit
    /// self-confirming.
    func installedRegistration() -> Registration? {
        guard let data = try? Data(contentsOf: paths.installMarker),
              let marker = try? JSONDecoder().decode(Marker.self, from: data),
              let port = marker.port, port != 0, let token = marker.token else {
            return nil
        }
        return Registration(port: port, token: token)
    }

    private struct Marker: Codable {
        let managedBy: String
        let port: UInt16?
        let token: String?
    }

    private func writeRegistration(_ registration: Registration) throws {
        let marker = Marker(
            managedBy: "codex-in-notch",
            port: registration.port,
            token: registration.token
        )
        let data = try JSONEncoder().encode(marker)
        try data.write(to: paths.installMarker, options: .atomic)
        // The token is a nonce guarding a loopback socket rather than a
        // credential, but it is still ours and nobody else's business.
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: paths.installMarker.path
        )
    }

    private func editor(port: UInt16, token: String) -> ManagedHooksFileEditor {
        ManagedHooksFileEditor(
            url: paths.hooksConfiguration,
            recoveryCopyURL: paths.hooksBackup,
            configuration: .loopbackPost(
                port: port,
                path: Self.hookPath,
                token: token,
                definitions: vocabulary.managedDefinitions,
                descriptionForNewFiles: "User-level Claude Code lifecycle hooks."
            ),
            fileManager: fileManager
        )
    }
}

extension HookIntegrationPaths {
    /// Where Claude Code keeps the settings this app registers hooks in.
    nonisolated static func liveClaudeCode(
        fileManager: FileManager = .default
    ) -> HookIntegrationPaths {
        let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("CodexInNotch", isDirectory: true)
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/CodexInNotch")

        return HookIntegrationPaths(
            supportDirectory: support,
            hooksConfiguration: fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/settings.json"),
            agent: .claudeCode
        )
    }
}
