import Foundation

/// Edits one product's hooks configuration, which is a file this app does not
/// own.
///
/// Every rule here was written for `~/.codex/hooks.json` and every one of them
/// matters more for `~/.claude/settings.json`, because that file is where a
/// user keeps everything else about their Claude Code install — theme,
/// environment, permissions, their own hooks. The read-modify-write below
/// touches only this app's own keys, refuses rather than coerces anything it
/// does not understand, proves the file has not moved underneath it, and reads
/// back to check before reporting success.
nonisolated struct ManagedHooksFileEditor: Sendable {
    let url: URL
    /// Where the file is copied once, before this app first changes it.
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

        try preserveRecoveryCopyIfNeeded()
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    /// Keeps one copy of the file as it was before this app first touched it.
    ///
    /// Written once and never refreshed: its value is that it predates every
    /// edit of ours, so overwriting it with a later state would destroy the
    /// only version worth keeping.
    private func preserveRecoveryCopyIfNeeded() throws {
        guard fileManager.fileExists(atPath: url.path),
              !fileManager.fileExists(atPath: recoveryCopyURL.path) else {
            return
        }
        try fileManager.copyItem(at: url, to: recoveryCopyURL)
    }
}
