import Darwin
import Foundation
import os

/// Whether the user has read a Claude Code session, and when: what retires a finished row
/// (`未读终态`). See ``ClaudeCodeDesktopReadStateRepository`` for the source and its gaps.
nonisolated protocol ClaudeCodeReadStateProviding: Sendable {
    func snapshot() async -> ClaudeCodeReadStateSnapshot
    nonisolated func changeEvents() -> AsyncStream<Void>
}

/// Which sessions have been read, keyed by the hooks' id (Claude Desktop records it beside its
/// own `local_<uuid>`).
struct ClaudeCodeReadStateSnapshot: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        /// When Claude Desktop last put this session on screen; absent can only mean unread.
        let lastFocusedAt: Date?
        let isArchived: Bool

        nonisolated init(lastFocusedAt: Date?, isArchived: Bool) {
            self.lastFocusedAt = lastFocusedAt
            self.isArchived = isArchived
        }
    }

    /// How far this snapshot may be trusted to hide a row; it never decides whether one is shown.
    /// A stale reading can only keep a read row, which is the preferred failure.
    enum Source: Equatable, Sendable {
        case current
        case lastKnownGood
        case unavailable

        nonisolated var isAuthoritative: Bool {
            if case .current = self { return true }
            return false
        }
    }

    enum SessionReadState: Equatable, Sendable {
        case read
        case unread
        /// Claude Desktop has no record of this session: every terminal-started session, permanently.
        case unknown
    }

    private let entries: [String: Entry]
    /// The CLI session id filed under each Claude Desktop id (`local_<uuid>`), for Desktop's log
    /// (``DesktopDisplayedSessionReporting``). A missing id joins to nothing.
    private let cliSessionIDsByDesktopID: [String: String]
    /// The reverse join, derived so the two cannot disagree. Answers only whether the name on
    /// screen is a different session's.
    private let desktopIDsByCLISessionID: [String: String]
    let source: Source
    let diagnostic: String?
    /// The session Claude Desktop most recently put on screen, not necessarily on screen now:
    /// Desktop never records hiding one, so ``ClaudeCodeMonitorService`` also requires
    /// ``DesktopDisplayedSessionReporting`` to agree.
    let mostRecentlyDisplayedSessionID: String?

    nonisolated init(
        entries: [String: Entry],
        source: Source,
        diagnostic: String? = nil,
        cliSessionIDsByDesktopID: [String: String] = [:]
    ) {
        self.entries = entries
        self.cliSessionIDsByDesktopID = cliSessionIDsByDesktopID
        // A session two Desktop ids claim answers nothing rather than picking.
        var desktopIDs: [String: String] = [:]
        var ambiguous: Set<String> = []
        for (desktopID, cliSessionID) in cliSessionIDsByDesktopID {
            if let existing = desktopIDs[cliSessionID], existing != desktopID {
                ambiguous.insert(cliSessionID)
                continue
            }
            desktopIDs[cliSessionID] = desktopID
        }
        for cliSessionID in ambiguous { desktopIDs.removeValue(forKey: cliSessionID) }
        self.desktopIDsByCLISessionID = desktopIDs
        self.source = source
        self.diagnostic = diagnostic
        // Ties broken by id so the answer cannot flap between same-millisecond stamps.
        var displayed: (id: String, at: Date)?
        for (id, entry) in entries {
            guard let at = entry.lastFocusedAt else { continue }
            guard let current = displayed else {
                displayed = (id, at)
                continue
            }
            if at > current.at || (at == current.at && id > current.id) {
                displayed = (id, at)
            }
        }
        self.mostRecentlyDisplayedSessionID = displayed?.id
    }

    nonisolated static func unavailable(_ diagnostic: String? = nil) -> Self {
        Self(entries: [:], source: .unavailable, diagnostic: diagnostic)
    }

    nonisolated func retainingData(
        source: Source,
        diagnostic: String
    ) -> Self {
        Self(
            entries: entries,
            source: source,
            diagnostic: diagnostic,
            cliSessionIDsByDesktopID: cliSessionIDsByDesktopID
        )
    }

    nonisolated func entry(forSession sessionID: String) -> Entry? {
        entries[sessionID]
    }

    /// The hooks' session id for `desktopSessionID`, when the records say.
    nonisolated func cliSessionID(forDesktopSessionID desktopSessionID: String) -> String? {
        cliSessionIDsByDesktopID[desktopSessionID]
    }

    /// Claude Desktop's id for the hooks' `sessionID`; `nil` without a record or its own id.
    nonisolated func desktopSessionID(forSession sessionID: String) -> String? {
        desktopIDsByCLISessionID[sessionID]
    }

    /// Whether the user has read what ended at `terminalBoundaryAt`.
    ///
    /// Compared with the Turn's own end, not Desktop's `lastActivityAt`, so a lagging Desktop
    /// cannot make a Turn look read; only a later focus can. Archiving counts as reading
    /// (`已读、归档、删除后移除`).
    nonisolated func readState(
        forSession sessionID: String,
        terminalBoundaryAt: Date
    ) -> SessionReadState {
        guard let entry = entries[sessionID] else { return .unknown }
        if entry.isArchived { return .read }
        guard let lastFocusedAt = entry.lastFocusedAt else { return .unread }
        return lastFocusedAt >= terminalBoundaryAt ? .read : .unread
    }
}

/// Claude Desktop's own record of which sessions it has shown the user (CC-013).
///
/// - Reads `~/Library/Application Support/Claude/claude-code-sessions/<org>/<account>/`
///   `local_<uuid>.json`: only `cliSessionId`, `sessionId`, `lastFocusedAt`, `isArchived`.
/// - Written by atomic replace when a session is displayed, so the watcher sees it.
/// - Terminal-started sessions have no file and no read state (checked on 2.1.235) and report
///   ``ClaudeCodeReadStateSnapshot/SessionReadState/unknown``. No guessing from focus or a
///   timer (`AGENTS.md` §6.2).
/// - Fail closed: any failure reports `unknown`, keeping rows listed.
actor ClaudeCodeDesktopReadStateRepository: ClaudeCodeReadStateProviding, ManagedMonitoringSource {
    private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "ClaudeCodeDesktopReadState"
    )

    /// Override for tests and unusual installs: Claude Desktop's application-support directory,
    /// like `NOTCHLINE_CODEX_HOME`.
    nonisolated static let homeOverrideKey = "NOTCHLINE_CLAUDE_DESKTOP_HOME"

    nonisolated private static let sessionsDirectoryName = "claude-code-sessions"
    nonisolated private static let recordPrefix = "local_"
    nonisolated private static let recordSuffix = ".json"
    nonisolated private static let maximumRecordSize = 4 * 1_024 * 1_024
    /// Records opened per reading, newest first; the tail answers `unknown` and keeps its row.
    nonisolated private static let maximumScannedRecords = 512
    /// One bulk attribute read; an ordinary tree fits in one call, a larger one loops.
    nonisolated private static let attributeBufferSize = 64 * 1_024

    private struct FileRevision: Equatable {
        let size: UInt64
        let modificationDate: Date?
        let fileNumber: UInt64?
    }

    private struct Record: Decodable {
        let cliSessionID: String
        /// Claude Desktop's own id, `local_<uuid>` (the file name and the id its log names). Without
        /// it the record still answers, but the session cannot be joined and keeps its row.
        let desktopSessionID: String?
        let lastFocusedAt: Date?
        let isArchived: Bool

        private enum CodingKeys: String, CodingKey {
            case cliSessionID = "cliSessionId"
            case desktopSessionID = "sessionId"
            case lastFocusedAt
            case isArchived
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.cliSessionID) else {
                throw ReadStateError.incompatibleSchema
            }
            let sessionID = try container.decode(String.self, forKey: .cliSessionID)
            guard !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ReadStateError.incompatibleSchema
            }
            cliSessionID = sessionID
            desktopSessionID = try container
                .decodeIfPresent(String.self, forKey: .desktopSessionID)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }
            // Milliseconds since the epoch, like every timestamp in these files.
            lastFocusedAt = try container
                .decodeIfPresent(Double.self, forKey: .lastFocusedAt)
                .map { Date(timeIntervalSince1970: $0 / 1_000) }
            isArchived = try container
                .decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        }
    }

    private enum ReadStateError: LocalizedError {
        case incompatibleSchema
        case oversizedFile(Int)
        case unsafeFile

        var errorDescription: String? {
            switch self {
            case .incompatibleSchema:
                "The Claude Desktop session state schema is not compatible."
            case let .oversizedFile(size):
                "The Claude Desktop session state file is implausibly large (\(size) bytes)."
            case .unsafeFile:
                "The Claude Desktop session state file is not a regular file owned by the current user."
            }
        }
    }

    private let stateDirectoryURL: URL
    private let fileManager: FileManager
    nonisolated private let watcher: PathSetChangeWatcher
    /// Parsed records keyed by file and revision; each reading reopens only changed records.
    private var cachedRecords: [URL: (revision: FileRevision, record: Record?)] = [:]
    private var lastKnownGood: ClaudeCodeReadStateSnapshot?
    private var monitoringPaused = false

    /// Claude Desktop's application-support root. One override moves both the session records
    /// and the `claude-code/<version>` CLI copy ``ClaudeExecutableLocator`` falls back to.
    nonisolated static func liveHomeURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let configured = environment[homeOverrideKey], !configured.isEmpty {
            return URL(
                fileURLWithPath: (configured as NSString).expandingTildeInPath,
                isDirectory: true
            )
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Claude",
                isDirectory: true
            )
    }

    nonisolated static func liveStateDirectoryURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        liveHomeURL(environment: environment, fileManager: fileManager)
            .appendingPathComponent(sessionsDirectoryName, isDirectory: true)
    }

    init(
        stateDirectoryURL: URL = ClaudeCodeDesktopReadStateRepository
            .liveStateDirectoryURL(),
        fileManager: FileManager = .default,
        changeDebounceInterval: TimeInterval =
            MonitorTiming.standard.unreadStateDebounceInterval
    ) {
        self.stateDirectoryURL = stateDirectoryURL
        self.fileManager = fileManager
        self.watcher = PathSetChangeWatcher(debounceInterval: changeDebounceInterval)
        // Only the root until the first reading finds account folders; it also reports a new
        // account folder, which the reconcile cannot find.
        watcher.watch(paths: [stateDirectoryURL])
    }

    func startMonitoring() { monitoringPaused = false; watcher.watch(paths: [stateDirectoryURL]) }
    func stopMonitoring() { monitoringPaused = true; watcher.watch(paths: []) }

    nonisolated func changeEvents() -> AsyncStream<Void> {
        watcher.events()
    }

    func snapshot() async -> ClaudeCodeReadStateSnapshot {
        // Pooled: the pass autoreleases bridged `NSURL`s, dictionaries and decoder output, and runs
        // once a second while any finished row is listed (CR-Fable-041).
        autoreleasepool { currentSnapshot() }
    }

    private func currentSnapshot() -> ClaudeCodeReadStateSnapshot {
        guard !monitoringPaused else { return .unavailable() }
        guard let accountDirectories = accountDirectories() else {
            // No tree: ordinary for terminal-only users, so no diagnostic.
            watcher.watch(paths: [stateDirectoryURL])
            return .unavailable()
        }
        watcher.watch(paths: Set([stateDirectoryURL] + accountDirectories))

        let recordURLs = recordURLs(in: accountDirectories)
        var entries: [String: ClaudeCodeReadStateSnapshot.Entry] = [:]
        var cliSessionIDsByDesktopID: [String: String] = [:]
        /// Desktop ids two records disagree about, which nothing may join.
        var ambiguousDesktopIDs: Set<String> = []
        var refreshed: [URL: (revision: FileRevision, record: Record?)] = [:]
        var failures = 0

        for (url, revision) in recordURLs {
            let record: Record?
            if let cached = cachedRecords[url], cached.revision == revision {
                record = cached.record
            } else {
                do {
                    record = try loadRecord(from: url)
                } catch {
                    record = nil
                    Self.log.debug(
                        "unreadable Claude Desktop session record: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            refreshed[url] = (revision, record)
            guard let record else {
                failures += 1
                continue
            }
            entries[record.cliSessionID] = Self.merging(
                entries[record.cliSessionID],
                with: ClaudeCodeReadStateSnapshot.Entry(
                    lastFocusedAt: record.lastFocusedAt,
                    isArchived: record.isArchived
                )
            )
            // One Desktop id in two accounts joins to nothing; both rows stay listed.
            if let desktopID = record.desktopSessionID {
                if let existing = cliSessionIDsByDesktopID[desktopID],
                   existing != record.cliSessionID {
                    ambiguousDesktopIDs.insert(desktopID)
                }
                cliSessionIDsByDesktopID[desktopID] = record.cliSessionID
            }
        }
        for desktopID in ambiguousDesktopIDs {
            cliSessionIDsByDesktopID.removeValue(forKey: desktopID)
        }
        cachedRecords = refreshed

        // All unreadable means a schema change; one unreadable record may just be mid-write.
        guard entries.isEmpty == false || failures == 0 else {
            let diagnostic = ReadStateError.incompatibleSchema.localizedDescription
                + " Finished Claude Code rows have been kept, to be safe."
            if let lastKnownGood {
                return lastKnownGood.retainingData(
                    source: .lastKnownGood,
                    diagnostic: diagnostic
                )
            }
            return .unavailable(diagnostic)
        }

        let snapshot = ClaudeCodeReadStateSnapshot(
            entries: entries,
            source: .current,
            cliSessionIDsByDesktopID: cliSessionIDsByDesktopID
        )
        lastKnownGood = snapshot
        return snapshot
    }

    /// Merges two records naming one session conservatively: earlier focus wins and archiving
    /// must be unanimous, so a duplicate can only keep a row longer.
    nonisolated private static func merging(
        _ existing: ClaudeCodeReadStateSnapshot.Entry?,
        with entry: ClaudeCodeReadStateSnapshot.Entry
    ) -> ClaudeCodeReadStateSnapshot.Entry {
        guard let existing else { return entry }
        let focused: Date?
        switch (existing.lastFocusedAt, entry.lastFocusedAt) {
        case let (lhs?, rhs?): focused = min(lhs, rhs)
        // One was never displayed: the reading that keeps the row.
        default: focused = nil
        }
        return ClaudeCodeReadStateSnapshot.Entry(
            lastFocusedAt: focused,
            isArchived: existing.isArchived && entry.isArchived
        )
    }

    /// `<root>/<org>/<account>`, or nil with no tree. Exactly two levels; a deeper tree answers
    /// nothing.
    private func accountDirectories() -> [URL]? {
        guard let organizations = subdirectories(of: stateDirectoryURL) else {
            return nil
        }
        return organizations.flatMap { subdirectories(of: $0) ?? [] }
    }

    private func subdirectories(of url: URL) -> [URL]? {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return contents.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    /// Every record worth opening, newest first and capped.
    ///
    /// `getattrlistbulk`: 0.06 ms a pass vs 0.44 ms for `FileManager` + `stat` (Release, 41
    /// records), run once a second. Reports the link, not its target; filters by name only.
    private func recordURLs(in accountDirectories: [URL]) -> [(URL, FileRevision)] {
        var found: [(URL, FileRevision)] = []
        for directory in accountDirectories {
            found += records(in: directory)
        }
        guard found.count > Self.maximumScannedRecords else { return found }
        return found
            .sorted {
                ($0.1.modificationDate ?? .distantPast)
                    > ($1.1.modificationDate ?? .distantPast)
            }
            .prefix(Self.maximumScannedRecords)
            .map { $0 }
    }

    /// One account folder's records, read in bulk. Entries are variable-length and packed: check
    /// `ATTR_CMN_RETURNED_ATTRS` before each field and load unaligned. A failure returns what was
    /// read.
    private func records(in directory: URL) -> [(URL, FileRevision)] {
        let descriptor = directory.withUnsafeFileSystemRepresentation {
            path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_RDONLY | O_DIRECTORY)
        }
        guard descriptor >= 0 else { return [] }
        defer { close(descriptor) }

        var attributes = attrlist()
        attributes.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
            | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_MODTIME)
            | attrgroup_t(ATTR_CMN_FILEID)
        attributes.fileattr = attrgroup_t(ATTR_FILE_DATALENGTH)

        var found: [(URL, FileRevision)] = []
        var buffer = [UInt8](repeating: 0, count: Self.attributeBufferSize)
        while true {
            let entries = buffer.withUnsafeMutableBytes { raw in
                getattrlistbulk(
                    descriptor,
                    &attributes,
                    raw.baseAddress,
                    raw.count,
                    0
                )
            }
            guard entries > 0 else { break }
            buffer.withUnsafeBytes { raw in
                guard var entry = raw.baseAddress else { return }
                for _ in 0..<entries {
                    let length = entry.loadUnaligned(as: UInt32.self)
                    if let record = Self.record(in: entry, of: directory) {
                        found.append(record)
                    }
                    entry += Int(length)
                }
            }
        }
        return found
    }

    /// One entry of the bulk buffer, or nil when it is not a session record.
    nonisolated private static func record(
        in entry: UnsafeRawPointer,
        of directory: URL
    ) -> (URL, FileRevision)? {
        var field = entry + MemoryLayout<UInt32>.size
        let returned = field.loadUnaligned(as: attribute_set_t.self)
        field += MemoryLayout<attribute_set_t>.size

        guard returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 else {
            return nil
        }
        let reference = field.loadUnaligned(as: attrreference_t.self)
        let name = String(
            cString: (field + Int(reference.attr_dataoffset))
                .assumingMemoryBound(to: CChar.self)
        )
        field += MemoryLayout<attrreference_t>.size
        guard name.hasPrefix(recordPrefix), name.hasSuffix(recordSuffix) else {
            return nil
        }

        var modificationDate: Date?
        if returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
            let modified = field.loadUnaligned(as: timespec.self)
            modificationDate = Date(
                timeIntervalSince1970: TimeInterval(modified.tv_sec)
                    + TimeInterval(modified.tv_nsec) / 1_000_000_000
            )
            field += MemoryLayout<timespec>.size
        }
        var fileNumber: UInt64?
        if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 {
            fileNumber = field.loadUnaligned(as: UInt64.self)
            field += MemoryLayout<UInt64>.size
        }
        // Absent for non-regular files: size zero is a fixed revision, and the load refuses it.
        var size: UInt64 = 0
        if returned.fileattr & attrgroup_t(ATTR_FILE_DATALENGTH) != 0 {
            size = UInt64(max(field.loadUnaligned(as: off_t.self), 0))
        }

        return (
            directory.appendingPathComponent(name, isDirectory: false),
            FileRevision(
                size: size,
                modificationDate: modificationDate,
                fileNumber: fileNumber
            )
        )
    }

    private func loadRecord(from url: URL) throws -> Record {
        let resourceValues = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ])
        guard resourceValues.isRegularFile == true,
              resourceValues.isSymbolicLink != true else {
            throw ReadStateError.unsafeFile
        }
        let fileSize = resourceValues.fileSize ?? 0
        guard fileSize <= Self.maximumRecordSize else {
            throw ReadStateError.oversizedFile(fileSize)
        }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        if let owner = attributes[.ownerAccountID] as? NSNumber,
           owner.uint32Value != getuid() {
            throw ReadStateError.unsafeFile
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Self.maximumRecordSize else {
            throw ReadStateError.oversizedFile(data.count)
        }
        return try JSONDecoder().decode(Record.self, from: data)
    }
}
