import Foundation

/// Installs Claude Code's hook registration, and the helper it names.
///
/// **Two files, two owners, and this app now writes both.**
/// `~/.claude/settings.json` still belongs to the user; what changed with
/// ADR 0016 is that the app is allowed to add and remove its own `hooks` keys
/// in it rather than print a block for the user to paste. The edit goes through
/// the same ``ManagedHooksFileEditor`` the Codex side has always used — only
/// this app's own keys are touched, anything it cannot positively identify is
/// refused rather than coerced, the bytes are proved unchanged across the
/// read-modify-write, and the result is read back before success is reported.
/// One thing is added for this file in particular: the copy at
/// ``HookIntegrationPaths/hooksBackup`` is refreshed immediately before every
/// write, so `settings.json.notchline-backup` always holds the file as it was
/// just before this app last changed it.
///
/// The asymmetry ADR 0010 recorded is therefore gone. It cost one thing only —
/// installation friction on the product whose users are least likely to accept
/// it — and the mechanism that was said to be missing turned out to have been
/// written and tested the whole time. What replaced the ADR's safety argument
/// is not confidence, it is the backup and the strictness above.
///
/// **There is no longer a port, and that is the other change this type carries.**
/// The registration used to be an `http` handler naming `127.0.0.1:51741`,
/// which had two faults no registration could fix. When the app is not running
/// nothing owns the port, so every event prints `connect ECONNREFUSED` in the
/// user's session — measured 9 lines for a two-tool turn against CLI 2.1.237,
/// and the renderer suppresses that line only for `Stop` and `SubagentStop`,
/// with no setting or environment variable that reaches it. And an unowned port
/// inside the ephemeral range can be taken by any local process, which then
/// receives the prompt and can answer with `permissionDecision` (CC-021,
/// CC-014).
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
    /// Kept so that a user who pasted the old block has it *replaced* rather
    /// than added to. Before ADR 0016 being recognised was the whole of what
    /// this app could do about it; now the same marker is what lets
    /// ``ManagedHooksConfiguration/installing(into:isNewFile:)`` strip the dead
    /// handler out on the way to writing the current one.
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

    /// The file the registration is written into.
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

    /// Writes the helper if it is missing or not what this build installs.
    ///
    /// Idempotent and cheap: one read and a string comparison in the ordinary
    /// case, because the script is a constant in this process and there is
    /// nothing to hash. Called on the path that binds the socket, for the
    /// reason the sessions watcher is re-attached there — a user may have
    /// registered the hooks before this app had a directory at all, and nothing
    /// else would think to ask again.
    ///
    /// Failure is reported rather than thrown: ``install()`` turns it into a
    /// refusal, and the refresh path's only recourse is to say so in the
    /// settings card. There is exactly one way this matters to a user — the
    /// registration names a script that is not there, so every event prints the
    /// one thing this whole transport exists to avoid.
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

    // MARK: - Reading what is registered

    /// How complete the registration is, read-only.
    ///
    /// The same reading the Codex registrar makes of its own file, projected
    /// through the same two facts. This product has no delivery evidence to
    /// project against -- Claude Code has no trust step, so "registered but
    /// never trusted" is not a state it can reach -- and a complete
    /// registration is reported as connected directly.
    func status() -> HookSetupStatus {
        HookSetupStatus.card(
            registration: configuration.registration(in: readSettings()),
            hasObservedEvent: true
        )
    }

    // MARK: - Writing the registration

    /// Adds this build's definitions to the user's settings, keeping a copy of
    /// the file as it was.
    ///
    /// The helper goes first and a failure to write it stops the whole install:
    /// a registration naming a script that is not there prints
    /// `ENOENT: ... posix_spawn` once per event, which is the same line moving
    /// off a port was meant to remove, arrived at from the other side.
    func install() throws {
        guard prepareHelper() else {
            throw ManagedHooksConfigurationError.verificationFailed
        }
        try configurationEditor.install()
    }

    /// Takes every trace of this app out of the user's settings again.
    ///
    /// The helper and the socket are deliberately left where they are. They
    /// live in this app's own support directory, nothing runs the helper once
    /// the registration naming it is gone, and the refresh loop's
    /// `prepareTransport()` would write both back within the second — so
    /// deleting them here would be churn that claims a tidiness it does not
    /// achieve. They go when the app does.
    func uninstall() throws {
        try configurationEditor.remove()
    }

    // MARK: - Internals

    private var configuration: ManagedHooksConfiguration {
        .command(
            paths.hookHelper.path,
            arguments: [],
            legacyCommands: [Self.legacyHookPath],
            definitions: vocabulary.managedDefinitions,
            // No `description` key, even on a file this app creates: Claude
            // Code validates this file's keys, and inventing one would make
            // this app's first act putting something unrecognised in it.
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
        guard let data = try? Data(contentsOf: paths.hooksConfiguration),
              !data.isEmpty,
              let decoded = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return decoded as? [String: Any]
    }
}

extension HookIntegrationPaths {
    /// Where Claude Code keeps the settings the hooks are registered in.
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
