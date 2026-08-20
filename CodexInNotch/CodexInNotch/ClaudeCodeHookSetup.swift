import Foundation

/// Prepares Claude Code's hook registration, and installs the helper it names.
///
/// **Two files, two owners.** `~/.claude/settings.json` belongs to the user and
/// is never written (ADR 0010): this type renders the block to paste and
/// reports whether what is there is what this build understands. The helper
/// that block names belongs to this app, lives in this app's own support
/// directory, and is written here — which ADR 0010 has nothing to say about,
/// since the decision it records is about the user's file.
///
/// The Codex side edits `~/.codex/hooks.json` itself, and that is a file which
/// holds hooks and little else. `~/.claude/settings.json` is not comparable: it
/// is where a user keeps their theme, environment, permissions, MCP servers and
/// their own hooks. The asymmetry is deliberate and worth stating, because it
/// will look like an oversight later: two products, two install stories. The
/// reason is the blast radius of a bad edit, not a difference in what is
/// technically possible.
///
/// **There is no longer a port, and that is the change this type exists to
/// carry.** The registration used to be an `http` handler naming
/// `127.0.0.1:51741`, which had two faults no registration could fix. When the
/// app is not running nothing owns the port, so every event prints
/// `connect ECONNREFUSED` in the user's session — measured 9 lines for a
/// two-tool turn against CLI 2.1.237, and the renderer suppresses that line
/// only for `Stop` and `SubagentStop`, with no setting or environment variable
/// that reaches it. And an unowned port inside the ephemeral range can be taken
/// by any local process, which then receives the prompt and can answer with
/// `permissionDecision` (CC-021, CC-014).
///
/// A `command` handler has neither fault. The helper exits 0 whether or not the
/// app is running, so nothing is ever printed; and it hands the payload to a
/// Unix domain socket in a directory this app owns, which nothing else can
/// bind. What it costs is a process per event: 6.3 ms measured, against 1.2 ms
/// for the loopback POST it replaces, and against the 30 ms the Codex helper on
/// the other side of this app has always cost.
actor ClaudeCodeHookSetup {
    /// The marker an HTTP-era registration is recognised by.
    ///
    /// Kept so that a user who pasted the old block is told to paste the new
    /// one, rather than being told nothing is installed. This app cannot remove
    /// it for them — that is the same ADR 0010 — so being recognised is the
    /// whole of what it can do.
    static let legacyHookPath = "/codex-in-notch/hook"

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

    /// Where the helper hands each payload, and where the listener binds.
    nonisolated var socketURL: URL {
        paths.hookSocket
    }

    // MARK: - The helper

    /// Writes the helper if it is missing or not what this build installs.
    ///
    /// Idempotent and cheap: one read and a string comparison in the ordinary
    /// case, because the script is a constant in this process and there is
    /// nothing to hash. Called on the path that binds the socket, for the
    /// reason the sessions watcher is re-attached there — a user may register
    /// the hooks before this app has ever had a directory, and nothing else
    /// would think to ask again.
    ///
    /// Failure is reported rather than thrown: the caller's only recourse is to
    /// say so in the settings card, and there is exactly one way this matters
    /// to a user — the block they pasted names a script that is not there, so
    /// every event prints the one thing this whole transport exists to avoid.
    @discardableResult
    func prepareHelper() -> Bool {
        let desired = AgentHookHelper.script(socketPath: paths.hookSocket.path)
        if let installed = try? String(contentsOf: paths.hookHelper, encoding: .utf8),
           installed == desired,
           fileManager.isExecutableFile(atPath: paths.hookHelper.path) {
            return true
        }
        do {
            try fileManager.createDirectory(
                at: paths.agentDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try desired.write(to: paths.hookHelper, atomically: true, encoding: .utf8)
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: paths.hookHelper.path
            )
            // Whatever the queue-era install left in this folder. Nothing here
            // is read or branched on -- it is a delete list, so an upgraded
            // install does not keep an events directory and two state files
            // nothing will ever open again.
            for url in paths.retiredArtifacts
            where fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Reading what the user has done

    /// How complete the registration is, read-only.
    ///
    /// The same reading the Codex registrar makes of its own file, projected
    /// through the same two facts. This product has no delivery evidence to
    /// project against -- it cannot write the user's file (ADR 0010), so
    /// "registered but never trusted" is not a state it can reach -- and a
    /// complete registration is reported as connected directly.
    func status() -> HookSetupStatus {
        HookSetupStatus.card(
            registration: configuration.registration(in: readSettings()),
            hasObservedEvent: true
        )
    }

    // MARK: - Telling the user what to add

    /// The exact text to paste, as a whole `hooks` block.
    ///
    /// Rendered from the same definitions the reducer consumes, so instructions
    /// cannot drift from what the app actually understands. Nothing in it is
    /// minted any more — the helper's path is derived from this app's own
    /// support directory — so the same machine produces the same block every
    /// time, and a user can tell at a glance whether what they pasted is still
    /// current.
    func configurationSnippet() -> String {
        // Never show a path this app has not created. The block names the
        // helper, and a user who pasted it while the helper was missing would
        // get `ENOENT: ... posix_spawn` printed once per event -- the same line
        // this transport exists to remove, arrived at from the other side.
        prepareHelper()
        guard let data = try? JSONSerialization.data(
            withJSONObject: ["hooks": configuration.hooksBlock()],
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Internals

    private var configuration: ManagedHooksConfiguration {
        .command(
            paths.hookHelper.path,
            arguments: [],
            legacyCommands: [Self.legacyHookPath],
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
}

extension HookIntegrationPaths {
    /// Where Claude Code keeps the settings the user registers hooks in.
    nonisolated static func liveClaudeCode(
        fileManager: FileManager = .default
    ) -> HookIntegrationPaths {
        HookIntegrationPaths(
            supportDirectory: supportDirectory(fileManager: fileManager),
            hooksConfiguration: fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/settings.json"),
            agent: .claudeCode
        )
    }
}
