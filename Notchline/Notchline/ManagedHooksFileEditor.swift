import Foundation

/// Edits one product's hooks configuration, which is a file this app does not
/// own.
///
/// Every rule here was written for `~/.codex/hooks.json` and every one of them
/// matters more for `~/.claude/settings.json`, which this type now also edits
/// (ADR 0016), because that file is where a user keeps everything else about
/// their Claude Code install — theme, environment, permissions, their own
/// hooks. The read-modify-write below touches only this app's own keys, refuses
/// rather than coerces anything it does not understand, proves the file has not
/// moved underneath it, keeps a copy of what it is about to replace, and reads
/// back to check before reporting success.
nonisolated struct ManagedHooksFileEditor: Sendable {
    let url: URL
    /// Where the file is copied, immediately before every change this app
    /// makes to it.
    let recoveryCopyURL: URL
    let configuration: ManagedHooksConfiguration
    let fileManager: FileManager

    nonisolated init(
        url: URL,
        recoveryCopyURL: URL,
        configuration: ManagedHooksConfiguration,
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.recoveryCopyURL = recoveryCopyURL
        self.configuration = configuration
        self.fileManager = fileManager
    }

    // MARK: - Install

    func install() throws {
        // Already exactly right, so there is nothing to write. Writing anyway
        // would reformat a file this app does not own, and it would renumber
        // the groups under every event it touches: Codex keys hook trust by
        // `<path>:<event>:<group index>:<handler index>` — measured on
        // 2026-08-20 — so a rewrite that moves a group moves the *user's* own
        // definitions out from under their trust. `remove()` has had this guard
        // for the same reason; `install()` did not, so turning the integration
        // switch on over a correct configuration rewrote it.
        if isInstalled() { return }

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let isNewFile = !fileManager.fileExists(atPath: url.path)
        let read = try readConfiguration()
        let updated = try configuration.installing(into: read.root, isNewFile: isNewFile)

        try write(updated, replacing: read.bytes)

        // Read back rather than trust the write. This file is the user's, and
        // the only thing standing between a bad edit and their configuration
        // is that we notice before reporting success.
        guard configuration.isFullyInstalled(in: try readConfiguration().root) else {
            throw ManagedHooksConfigurationError.verificationFailed
        }
    }

    // MARK: - Remove

    func remove() throws {
        guard fileManager.fileExists(atPath: url.path) else { return }

        let read = try readConfiguration()
        let updated = try configuration.removing(from: read.root)

        // Nothing of ours was in there, so there is nothing to write. Rewriting
        // anyway would reformat a file this app does not own for no reason.
        guard (updated as NSDictionary) != (read.root as NSDictionary) else { return }

        try write(updated, replacing: read.bytes)

        guard configuration.isFullyRemoved(from: try readConfiguration().root) else {
            throw ManagedHooksConfigurationError.verificationFailed
        }
    }

    /// Whether every managed definition is currently registered.
    func isInstalled() -> Bool {
        guard let read = try? readConfiguration() else { return false }
        return configuration.isFullyInstalled(in: read.root)
    }

    // MARK: - Reading and writing

    /// The configuration as read, with the exact bytes it was decoded from.
    private struct ConfigurationRead {
        let root: [String: Any]
        /// `nil` when the file did not exist at read time.
        let bytes: Data?
    }

    /// Reads the configuration root, refusing anything that is not an object.
    ///
    /// Malformed JSON already threw here. What did not was *valid* JSON whose
    /// root was, say, an array: it was coerced to an empty dictionary and the
    /// user's file was then written over with only our definitions in it.
    private func readConfiguration() throws -> ConfigurationRead {
        guard fileManager.fileExists(atPath: url.path) else {
            return ConfigurationRead(root: [:], bytes: nil)
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            return ConfigurationRead(root: [:], bytes: data)
        }
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard let root = decoded as? [String: Any] else {
            throw ManagedHooksConfigurationError.rootIsNotObject
        }
        return ConfigurationRead(root: root, bytes: data)
    }

    /// Writes the merged document, but only onto the bytes it was derived from.
    ///
    /// Everything above is a read-modify-write on a file this app does not own.
    /// If the product or the user rewrites it in that window -- Codex's
    /// `/hooks` trusting a definition, Claude Code's own settings watcher --
    /// writing anyway would silently drop their change. This cannot make the
    /// sequence atomic, but it does turn a lost edit into a visible failure the
    /// caller reports and the user can retry.
    private func write(_ root: [String: Any], replacing expectedBytes: Data?) throws {
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )

        let currentBytes: Data? = fileManager.fileExists(atPath: url.path)
            ? try Data(contentsOf: url)
            : nil
        guard currentBytes == expectedBytes else {
            throw ManagedHooksConfigurationError.changedWhileEditing
        }

        try preserveRecoveryCopy(of: currentBytes)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    /// Keeps a copy of the file as it was immediately before this write.
    ///
    /// **Refreshed on every write, not kept from the first one, for both
    /// products.** The copy used to be written once and never again, on the
    /// argument that a state predating every edit of ours is the only one worth
    /// keeping. That argument was made when this type only edited
    /// `~/.codex/hooks.json`, and it does not survive either file.
    ///
    /// It fails on `~/.claude/settings.json` because that file holds the whole
    /// of a user's Claude Code install: somebody who turned this on months ago
    /// and has since kept their theme, permissions, environment and MCP servers
    /// there would find `settings.json.notchline-backup` predating all of it,
    /// and restoring it would be a data loss this app caused.
    ///
    /// It fails on `~/.codex/hooks.json` for a sharper reason, and this is why
    /// the rule is not split per product. Codex keys hook trust by
    /// `<path>:<event>:<group index>:<handler index>` — the same measurement
    /// that makes ``ManagedHooksConfiguration`` append at the tail. Restoring a
    /// copy taken before this app's first edit does not merely lose the
    /// definitions the user has added since; it renumbers the groups of the
    /// ones that remain, so their trust silently stops applying and Codex stops
    /// running their hooks with nothing anywhere reporting it. A stale copy of
    /// that file is more dangerous than a stale copy of the other one, not
    /// less. On a file this app created the once-only rule was not even
    /// coherent: it skipped the write that created the file and then froze on
    /// the state before this app's *second* edit, which is a version nothing
    /// can name.
    ///
    /// So the copy means exactly one thing, in both files, and refreshing is
    /// what keeps that meaning true: the user's file as it was immediately
    /// before this app's most recent change to it. An older copy left by a
    /// build that wrote once is replaced by the newer meaning on the next
    /// write, deliberately.
    ///
    /// The bytes are the ones ``write(_:replacing:)`` has just read and compared,
    /// rather than a `copyItem` of the path — one less read, and no window in
    /// which the copy could catch a different version than the one being
    /// replaced. Written atomically, so a crash mid-write leaves the previous
    /// copy intact rather than no copy at all.
    private func preserveRecoveryCopy(of currentBytes: Data?) throws {
        // Nothing there yet: this write creates the file, so there is no
        // earlier version to keep and an empty copy would only be misleading.
        guard let currentBytes else { return }
        try currentBytes.write(to: recoveryCopyURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: recoveryCopyURL.path
        )
    }
}
