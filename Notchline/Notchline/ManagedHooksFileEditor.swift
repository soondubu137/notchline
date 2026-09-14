import Foundation

/// Edits one product's hooks configuration, a file this app does not own (including
/// `~/.claude/settings.json`, ADR 0016). Touches only this app's keys, refuses what it does not
/// understand, checks the file did not move underneath it, keeps a recovery copy, and reads
/// back before reporting success.
nonisolated struct ManagedHooksFileEditor: Sendable {
    let url: URL
    /// Where the file is copied immediately before every change this app makes.
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
        // Already exactly right: rewriting would reformat the file and renumber groups, and Codex keys
        // hook trust by `<path>:<event>:<group index>:<handler index>` (measured 2026-08-20).
        if isInstalled() { return }

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let isNewFile = !fileManager.fileExists(atPath: url.path)
        let read = try readConfiguration()
        let updated = try configuration.installing(into: read.root, isNewFile: isNewFile)

        try write(updated, replacing: read.bytes)

        // Read back rather than trust the write: this file is the user's.
        guard configuration.isFullyInstalled(in: try readConfiguration().root) else {
            throw ManagedHooksConfigurationError.verificationFailed
        }
    }

    // MARK: - Remove

    func remove() throws {
        guard fileManager.fileExists(atPath: url.path) else { return }

        let read = try readConfiguration()
        let updated = try configuration.removing(from: read.root)

        // Nothing of ours was there; do not reformat a file this app does not own.
        guard (updated as NSDictionary) != (read.root as NSDictionary) else { return }

        try write(updated, replacing: read.bytes)

        guard configuration.isFullyRemoved(from: try readConfiguration().root) else {
            throw ManagedHooksConfigurationError.verificationFailed
        }
    }

    func isInstalled() -> Bool {
        guard let read = try? readConfiguration() else { return false }
        return configuration.isFullyInstalled(in: read.root)
    }

    // MARK: - Reading and writing

    private struct ConfigurationRead {
        let root: [String: Any]
        /// `nil` when the file did not exist at read time.
        let bytes: Data?
    }

    /// Refuses valid JSON whose root is not an object rather than coercing it to empty.
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

    /// Writes the merged document only onto the bytes it was derived from, so a concurrent rewrite
    /// (Codex's `/hooks` trust, Claude Code's settings watcher) becomes a visible, retryable failure
    /// instead of a lost edit. Not atomic.
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

    /// Keeps the file as it was immediately before this app's most recent change, refreshed on every
    /// write: an old `settings.json` copy loses the user's later settings, and an old `hooks.json`
    /// renumbers groups, silently voiding Codex trust. Uses the bytes ``write(_:replacing:)`` just
    /// compared; atomic, so a crash keeps the previous copy.
    private func preserveRecoveryCopy(of currentBytes: Data?) throws {
        // This write creates the file: nothing earlier to keep.
        guard let currentBytes else { return }
        try currentBytes.write(to: recoveryCopyURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: recoveryCopyURL.path
        )
    }
}
