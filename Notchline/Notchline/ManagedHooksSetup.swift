import Foundation

/// Installs a product's hook registration and the helper it names — for any
/// product whose file this app may write and whose hooks run as registered,
/// with no trust step after the write.
///
/// Written for Claude Code and named after it until 2026-09-11; nothing in it
/// was Claude Code's except the vocabulary handed in, so it is now the setup a
/// hook-based product gets by default (`tiered-support.md` §5.4). Codex keeps
/// ``CodexHookRegistrar``: its definitions are content-hashed and trusted one
/// by one, so it never rewrites a complete registration ([ADR 0014](../../docs/adr/0014-the-codex-hook-definition-is-never-rewritten.md))
/// and records which definitions still await trust. The two share the helper
/// (``AgentHookHelper/prepare(at:answerWindowSeconds:fileManager:)``), the
/// editor and the configuration value; what differs is that policy.
///
/// **Two files, two owners, and this app writes both.** The product's settings
/// file (`~/.claude/settings.json` for Claude Code) still belongs to the user;
/// what changed with ADR 0016 is that the app is allowed to add and remove its
/// own `hooks` keys in it rather than print a block for the user to paste. The
/// edit goes through the same ``ManagedHooksFileEditor`` the Codex side has
/// always used — only this app's own keys are touched, anything it cannot
/// positively identify is refused rather than coerced, the bytes are proved
/// unchanged across the read-modify-write, and the result is read back before
/// success is reported. The copy at ``HookIntegrationPaths/hooksBackup`` is
/// refreshed immediately before every write, so the `.notchline-backup` always
/// holds the file as it was just before this app last changed it.
///
/// The asymmetry ADR 0010 recorded is therefore gone. It cost one thing only —
/// installation friction on the product whose users are least likely to accept
/// it — and the mechanism that was said to be missing turned out to have been
/// written and tested the whole time. What replaced the ADR's safety argument
/// is not confidence, it is the backup and the strictness above.
///
/// **There is no port, and that is the other thing this type carries.**
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
actor ManagedHooksSetup {
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
        switch AgentHookHelper.prepare(
            at: paths,
            answerWindowSeconds: vocabulary.answerWindowSeconds,
            fileManager: fileManager
        ) {
        case .current:
            return true
        case .written:
            // A fresh helper is the moment to clear what earlier builds left
            // beside it; nothing else is deleted on this product's behalf.
            for url in paths.retiredArtifacts
            where fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
            return true
        case .failed:
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
    func status() -> IntegrationSetupStatus {
        IntegrationSetupStatus.card(
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

    /// The definitions and handlers this build writes.
    ///
    /// Not private, and the reason is a fixture: the test harness used to
    /// hand-write "the same handler for every definition", which was true until
    /// one definition stopped being the same as the rest and then quietly
    /// registered a shape this build calls `mismatched`. A fixture that asks
    /// the product what it writes cannot drift from it.
    nonisolated var configuration: ManagedHooksConfiguration {
        .command(
            paths.hookHelper.path,
            arguments: [],
            legacyCommands: vocabulary.legacyCommandMarkers,
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
