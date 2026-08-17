import Foundation

nonisolated struct ClaudeCodeHookRegistration: Sendable, Equatable {
    let port: UInt16
    let token: String
}

/// Prepares Claude Code's hook registration, and never writes it.
///
/// The Codex side edits `~/.codex/hooks.json` itself, and that is a file which
/// holds hooks and little else. `~/.claude/settings.json` is not comparable: it
/// is where a user keeps their theme, environment, permissions, MCP servers and
/// their own hooks. This product does not edit it. It shows the user exactly
/// what to add, and the user adds it.
///
/// The asymmetry is deliberate and worth stating, because it will look like an
/// oversight later: two products, two install stories. The reason is the blast
/// radius of a bad edit, not a difference in what is technically possible.
///
/// It also settles a question the writing version had to answer awkwardly.
/// The hook URL names a port, so a writing installer that could not bind the
/// port it had chosen would have to rewrite the user's file. Here the direction
/// reverses: **the user's file is authoritative and the app follows it.** The
/// registration is read out of their settings and the listener binds that port.
/// A proposal is minted only when there is nothing there to follow.
actor ClaudeCodeHookSetup {
    /// The path inside the hook URL that identifies this app's handler.
    ///
    /// Identity has to survive the port, because the port is the part a user is
    /// free to change — they own the file now.
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

    /// Where the user has to make the change.
    nonisolated var settingsURL: URL {
        paths.hooksConfiguration
    }

    // MARK: - Reading what the user has done

    /// The registration the user's settings actually name, if any.
    ///
    /// This is the authority. Whatever this app once proposed, what is in the
    /// file is what Claude Code will POST to, so it is what the listener binds.
    func installedRegistration() -> ClaudeCodeHookRegistration? {
        guard let root = readSettings() else { return nil }
        return Self.registration(in: root, path: Self.hookPath)
    }

    /// How complete the registration is, read-only.
    func status() -> HookSetupStatus {
        guard let root = readSettings() else { return .notInstalled }
        guard let registration = Self.registration(in: root, path: Self.hookPath) else {
            return .notInstalled
        }
        let configuration = self.configuration(for: registration)
        if configuration.isFullyInstalled(in: root) {
            return .active
        }
        // Some of ours is there and some is not: a partial paste, or a version
        // of this app that registered a different set of events. Either way the
        // user has to be told, because the missing events fail silently — no
        // error, just a state the notch never learns about.
        return .repairRequired
    }

    // MARK: - Telling the user what to add

    /// The registration to offer when the settings name none.
    ///
    /// Minted once and remembered, so the instructions do not change every time
    /// the panel is opened — a snippet that keeps moving is one the user cannot
    /// trust they have already applied.
    func proposedRegistration() -> ClaudeCodeHookRegistration {
        if let existing = installedRegistration() { return existing }
        if let remembered = rememberedProposal() { return remembered }

        let proposal = ClaudeCodeHookRegistration(
            // A high fixed port, because the user's file names it and this app
            // cannot move it for them. Collisions are surfaced rather than
            // worked around; see `ClaudeCodeMonitorService`.
            port: 51_741,
            token: Self.freshToken()
        )
        rememberProposal(proposal)
        return proposal
    }

    /// The exact text to paste, as a whole `hooks` block.
    ///
    /// Rendered from the same definitions the reducer consumes, so instructions
    /// cannot drift from what the app actually understands.
    func configurationSnippet() -> String {
        let registration = proposedRegistration()
        let hooks = configuration(for: registration).hooksBlock()
        guard let data = try? JSONSerialization.data(
            withJSONObject: ["hooks": hooks],
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Internals

    private func configuration(
        for registration: ClaudeCodeHookRegistration
    ) -> ManagedHooksConfiguration {
        .loopbackPost(
            port: registration.port,
            path: Self.hookPath,
            token: registration.token,
            definitions: vocabulary.managedDefinitions
        )
    }

    private func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: paths.hooksConfiguration),
              !data.isEmpty,
              let decoded = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return decoded as? [String: Any]
    }

    /// Finds this app's handler anywhere in a settings document and reads the
    /// port and token back out of it.
    nonisolated static func registration(
        in value: Any,
        path: String
    ) -> ClaudeCodeHookRegistration? {
        switch value {
        case let object as [String: Any]:
            if let url = object["url"] as? String, url.contains(path),
               let components = URLComponents(string: url),
               let port = components.port.flatMap({ UInt16(exactly: $0) }) {
                let headers = object["headers"] as? [String: String] ?? [:]
                let token = (headers["Authorization"] ?? "")
                    .replacingOccurrences(of: "Bearer ", with: "")
                if !token.isEmpty {
                    return ClaudeCodeHookRegistration(port: port, token: token)
                }
            }
            return object.values.lazy
                .compactMap { registration(in: $0, path: path) }
                .first
        case let array as [Any]:
            return array.lazy
                .compactMap { registration(in: $0, path: path) }
                .first
        default:
            return nil
        }
    }

    private struct Proposal: Codable {
        let port: UInt16
        let token: String
    }

    private func rememberedProposal() -> ClaudeCodeHookRegistration? {
        guard let data = try? Data(contentsOf: paths.installMarker),
              let stored = try? JSONDecoder().decode(Proposal.self, from: data) else {
            return nil
        }
        return ClaudeCodeHookRegistration(port: stored.port, token: stored.token)
    }

    private func rememberProposal(_ registration: ClaudeCodeHookRegistration) {
        guard let data = try? JSONEncoder().encode(
            Proposal(port: registration.port, token: registration.token)
        ) else { return }
        try? fileManager.createDirectory(
            at: paths.agentDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? data.write(to: paths.installMarker, options: .atomic)
        try? fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: paths.installMarker.path
        )
    }

    private static func freshToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

extension HookIntegrationPaths {
    /// Where Claude Code keeps the settings the user registers hooks in.
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
