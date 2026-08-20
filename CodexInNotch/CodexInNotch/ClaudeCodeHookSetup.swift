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
        // Our own leaving, from when there was something to remember. The
        // marker held the minted port and token so the instructions would not
        // change every time the panel was opened; the helper's path is derived
        // rather than minted, so nothing on this side has anything to remember
        // any more. Removing it also takes a stale token off the disk. This
        // app's own file, in this app's own directory -- the Codex installer
        // still writes its own under `agents/codex/`, which this cannot reach.
        try? fileManager.removeItem(at: paths.installMarker)

        let desired = Self.helperScript(socketPath: paths.hookSocket.path)
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
            return true
        } catch {
            return false
        }
    }

    /// The helper, with its socket baked in.
    ///
    /// Deliberately the smallest thing that can carry one payload:
    ///
    /// - **It never speaks.** `exec >/dev/null 2>&1` covers the whole script,
    ///   including the shell's own "not found" if `nc` is ever absent. Claude
    ///   Code parses a hook's stdout for directives and prints its stderr, so
    ///   silence on both streams is not tidiness — a helper that reported "the
    ///   app is not running" would be exactly the noise this transport removes.
    /// - **It always succeeds.** A non-zero exit is rendered as
    ///   `<event> hook error` in an interactive session, so the `exit 0` is
    ///   load-bearing on every path: no socket (the app is closed), a stale
    ///   socket file, a refused connection, a missing `nc`.
    /// - **It cannot hang.** `-w 1` bounds the case where this app has accepted
    ///   the connection but wedged before reading it; without it `nc` waits for
    ///   the peer indefinitely and the CLI's own `timeout` is all that ends it.
    ///   Measured: 6.3 ms when the app is listening, 17 ms when it is not,
    ///   1 s in the wedged case.
    ///
    /// `nc -U` rather than a compiled helper of our own because it is already
    /// on every macOS and needs no target, no signing and no upgrade path. The
    /// cost of the extra process is the difference between 6.3 ms and the
    /// 4.1 ms a compiled equivalent measured — nothing, next to what it saves.
    nonisolated static func helperScript(socketPath: String) -> String {
        """
        #!/bin/sh
        # Codex in Notch — hands one Claude Code hook payload to the running app.
        #
        # Says nothing on any stream and always exits 0. Both are required: the
        # CLI prints a line in the user's session for every hook that fails or
        # writes to stderr, and no setting suppresses it.
        exec >/dev/null 2>&1
        /usr/bin/nc -U -w 1 \(Self.singleQuoted(socketPath))
        exit 0

        """
    }

    /// Wraps a path for `sh`, including one with a quote in it.
    ///
    /// A home directory is a user-chosen string and this one is pasted into a
    /// script, so the escape is not decoration: `O'Brien` would otherwise end
    /// the quoting and leave the rest of the path as shell words.
    nonisolated static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Reading what the user has done

    /// How complete the registration is, read-only.
    func status() -> HookSetupStatus {
        guard let root = readSettings() else { return .notInstalled }
        if configuration.isFullyInstalled(in: root) { return .active }
        // Some of ours is there and some is not: a partial paste, a version of
        // this app that registered a different set of events, or — for anyone
        // who installed before this change — the `http` handler that named a
        // port. Either way the user has to be told, because the missing events
        // fail silently: no error, just a state the notch never learns about.
        if ManagedHooksConfiguration.containsAnyMarker(of: configuration, in: root) {
            return .repairRequired
        }
        return .notInstalled
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
