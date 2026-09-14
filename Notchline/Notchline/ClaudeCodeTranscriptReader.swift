import Darwin
import Foundation

/// Reads what Claude Code writes about a session in its own transcript.
///
/// - The title: content, read only when the user allows content.
/// - Whether the held Turn was interrupted: state, read regardless of the preview switch and
///   without decoding message text. For a Desktop-hosted session this is the only record of an
///   interrupt (CC-022; see ``ClaudeCodeActivity``).
///
/// Private dependency, registered in `docs/non-public-codex-integration-features.md`: every rule
/// fails closed to no title, and the row says `Untitled`, never the folder name.
actor ClaudeCodeTranscriptReader {
    /// How much of a transcript's tail is examined, and the size of one read. Transcripts reach tens
    /// of megabytes (16 MB here); the tail holds the most recent title.
    static let scannedBytes = 64 * 1024

    /// How many records from the start of a transcript are examined, for a session titled only when
    /// it opened. Records, not bytes: over 480 transcripts (2026-09-11) the first title record is at
    /// most record 33, but at byte offsets up to 371 KB behind skill, plugin and MCP listings.
    static let scannedHeadRecords = 128

    /// The ceiling on the head read, since one record can be enormous; 1 MiB clears the widest
    /// opening seen here about three times over.
    static let scannedHeadBytes = 1024 * 1024

    private struct CacheEntry {
        let size: Int
        let modifiedAt: Date
        let title: String?
    }

    /// What one scan of a transcript's opening found. Apart from ``CacheEntry``: appends leave the
    /// opening unchanged, so only a shorter (replaced) file invalidates it (296 us vs 893 us a
    /// refresh, `-O`, 2026-09-11).
    private struct HeadEntry {
        let title: String?
        let scannedThrough: Int
        /// Whether the scan hit end of file rather than a budget; only a budget-stopped answer is final,
        /// since the next appended record can name the session.
        let ranOutOfFile: Bool
    }

    /// The last interruption in one transcript's tail, and the file state it was read at. Cached
    /// apart from the title, which is read only when content is allowed.
    private struct InterruptionEntry {
        let size: Int
        let modifiedAt: Date
        let interruption: Interruption?
    }

    private struct Interruption {
        /// The hook's `prompt_id`; see ``interruption(forSession:workingDirectory:turnID:after:)``.
        let turnID: String
        let at: Date
    }

    private let projectsDirectory: URL
    private let fileManager: FileManager
    private var resolvedPaths: [String: URL] = [:]
    private var cache: [String: CacheEntry] = [:]
    private var heads: [String: HeadEntry] = [:]
    private var interruptions: [String: InterruptionEntry] = [:]

    init(
        projectsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.projectsDirectory = projectsDirectory
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true)
        self.fileManager = fileManager
    }

    func title(forSession sessionID: String, workingDirectory: URL) -> String? {
        guard let url = transcriptURL(
            forSession: sessionID,
            workingDirectory: workingDirectory
        ) else {
            return nil
        }

        // Skip re-reading a transcript that has not changed; this runs every refresh for every row.
        let (size, modifiedAt) = Self.revision(of: url)
        if let cached = cache[sessionID],
           cached.size == size, cached.modifiedAt == modifiedAt {
            return cached.title
        }

        let title = readTitle(forSession: sessionID, at: url, size: size)
        cache[sessionID] = CacheEntry(size: size, modifiedAt: modifiedAt, title: title)
        return title
    }

    /// When the Turn this session is holding was interrupted, if it was.
    ///
    /// A Desktop-hosted session's only interrupt report (no hook, ADR 0011; no status, CC-022) is a
    /// `user` record with exactly one `text` block, no `promptSource`, no `isMeta`: over 7,438 `user`
    /// records (2026-08-19) it matched 15 of 15 interrupts and nothing else; the block-shape clause
    /// excludes slash-command records, some followed by more work. Its `promptId` is the hooks'
    /// `prompt_id` (2.1.237), so it ends only that Turn.
    ///
    /// - Parameter after: The Turn's last known moment; older records are earlier or applied.
    /// - Returns: When the interrupt was written, or nil. Only the newest tail record counts.
    func interruption(
        forSession sessionID: String,
        workingDirectory: URL,
        turnID: String,
        after lastEventAt: Date
    ) -> Date? {
        guard let url = transcriptURL(
            forSession: sessionID,
            workingDirectory: workingDirectory
        ) else {
            return nil
        }

        // An unchanged transcript cannot have gained a record; asked every refresh per running Turn.
        let (size, modifiedAt) = Self.revision(of: url)
        let interruption: Interruption?
        if let cached = interruptions[sessionID],
           cached.size == size, cached.modifiedAt == modifiedAt {
            interruption = cached.interruption
        } else {
            interruption = readInterruption(at: url, size: size)
            interruptions[sessionID] = InterruptionEntry(
                size: size,
                modifiedAt: modifiedAt,
                interruption: interruption
            )
        }

        guard let interruption,
              interruption.turnID == turnID,
              interruption.at > lastEventAt else {
            return nil
        }
        return interruption.at
    }

    func retain(sessionIDs: Set<String>) {
        cache = cache.filter { sessionIDs.contains($0.key) }
        heads = heads.filter { sessionIDs.contains($0.key) }
        interruptions = interruptions.filter { sessionIDs.contains($0.key) }
        resolvedPaths = resolvedPaths.filter { sessionIDs.contains($0.key) }
    }

    // MARK: - Locating

    /// The file this session's records are written to, or nil when it cannot be found.
    /// Not private: ``ClaudeCodeMonitorService`` watches it. Resolution is cached.
    func transcriptURL(forSession sessionID: String, workingDirectory: URL) -> URL? {
        if let known = resolvedPaths[sessionID],
           fileManager.fileExists(atPath: known.path) {
            return known
        }

        // Project directory = working directory with separators replaced. Observed, so only a first guess.
        let slug = workingDirectory.standardizedFileURL.path
            .replacingOccurrences(of: "/", with: "-")
        let guess = projectsDirectory
            .appendingPathComponent(slug, isDirectory: true)
            .appendingPathComponent("\(sessionID).jsonl")
        if fileManager.fileExists(atPath: guess.path) {
            resolvedPaths[sessionID] = guess
            return guess
        }

        // The fallback relies only on a transcript being named after its session.
        let directories = (try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for directory in directories {
            let candidate = directory.appendingPathComponent("\(sessionID).jsonl")
            if fileManager.fileExists(atPath: candidate.path) {
                resolvedPaths[sessionID] = candidate
                return candidate
            }
        }
        return nil
    }

    // MARK: - Reading

    /// The size and modification date the caches are keyed by, from one `stat`: roughly fifty times
    /// cheaper than `FileManager.attributesOfItem`, and asked per row per refresh. A file that cannot
    /// be stat'ed answers `(0, .distantPast)`, which matches no cache entry.
    nonisolated private static func revision(of url: URL) -> (Int, Date) {
        var status = stat()
        let read = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return lstat(path, &status)
        }
        guard read == 0 else { return (0, .distantPast) }
        let modified = status.st_mtimespec
        return (
            Int(status.st_size),
            Date(
                timeIntervalSince1970: TimeInterval(modified.tv_sec)
                    + TimeInterval(modified.tv_nsec) / 1_000_000_000
            )
        )
    }

    private func readTitle(
        forSession sessionID: String,
        at url: URL,
        size: Int
    ) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        if let title = title(in: tail(of: handle, size: size)) {
            return title
        }
        // Only worth a second look when the file is bigger than one read.
        guard size > Self.scannedBytes else { return nil }
        return headTitle(forSession: sessionID, in: handle, size: size)
    }

    /// The title in this transcript's opening, scanned at most once a session (see ``HeadEntry``).
    /// A scan that ran out of file is redone, not resumed: only 3 of 427 transcripts over 64 KiB.
    private func headTitle(
        forSession sessionID: String,
        in handle: FileHandle,
        size: Int
    ) -> String? {
        if let known = heads[sessionID],
           size >= known.scannedThrough,
           known.title != nil || !known.ranOutOfFile {
            return known.title
        }
        let scanned = head(of: handle)
        heads[sessionID] = scanned
        return scanned.title
    }

    /// - Note: Pooled: the `FileHandle` `Data` is autoreleased and would never drain on this thread
    ///   (64 KB per title, per session, per refresh).
    private func tail(of handle: FileHandle, size: Int) -> [Data] {
        let offset = max(0, size - Self.scannedBytes)
        try? handle.seek(toOffset: UInt64(offset))
        var lines = autoreleasepool { () -> [Data] in
            guard let data = try? handle.readToEnd() else { return [] }
            return Self.jsonLines(in: data)
        }
        // The first line of a mid-file read is a fragment of a record.
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }

    /// Reads forward from the start until a title turns up or a budget runs out (records; see
    /// ``scannedHeadRecords``).
    ///
    /// Taken in ``scannedBytes`` chunks, each cut at its last complete record; at least one read
    /// always happens. Only lines that could name a title are kept.
    ///
    /// - Note: Pooled, for the reason given on ``tail(of:size:)``.
    private func head(of handle: FileHandle) -> HeadEntry {
        try? handle.seek(toOffset: 0)
        var pending = Data()
        var candidates: [Data] = []
        var read = 0
        var records = 0

        while records < Self.scannedHeadRecords, read < Self.scannedHeadBytes {
            let chunk = autoreleasepool { () -> Data in
                (try? handle.read(upToCount: Self.scannedBytes)) ?? Data()
            }
            guard !chunk.isEmpty else {
                return HeadEntry(
                    title: title(in: candidates),
                    scannedThrough: read,
                    ranOutOfFile: true
                )
            }
            read += chunk.count
            pending.append(chunk)
            // No boundary in the chunk: a record longer than one read; the byte ceiling ends those.
            guard let newline = pending.lastIndex(of: UInt8(ascii: "\n")) else { continue }
            let complete = Data(pending[..<newline])
            pending = Data(pending[pending.index(after: newline)...])
            for line in Self.jsonLines(in: complete) {
                records += 1
                if Self.mayName(aTitle: line) { candidates.append(line) }
            }
            if let title = title(in: candidates) {
                return HeadEntry(title: title, scannedThrough: read, ranOutOfFile: false)
            }
        }
        return HeadEntry(
            title: title(in: candidates),
            scannedThrough: read,
            ranOutOfFile: false
        )
    }

    nonisolated private static func jsonLines(in data: Data) -> [Data] {
        data
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            .map { Data($0) }
    }

    private struct TitleRecord: Decodable {
        let type: String?
        let customTitle: String?
        let aiTitle: String?
    }

    nonisolated private static let titleMarker = Data(#"-title""#.utf8)

    /// Whether a record could be a title record: both type names contain `-title"`, which
    /// `JSON.stringify` never escapes. Tested before decoding; openings hold records of tens of KB.
    nonisolated private static func mayName(aTitle line: Data) -> Bool {
        line.range(of: titleMarker) != nil
    }

    private func title(in lines: [Data]) -> String? {
        let decoder = JSONDecoder()
        var aiTitle: String?
        for line in lines.reversed() {
            guard Self.mayName(aTitle: line),
                  let record = try? decoder.decode(TitleRecord.self, from: line) else {
                continue
            }
            // A user-typed title outranks a generated one wherever each sits.
            if record.type == "custom-title", let title = normalized(record.customTitle) {
                return title
            }
            if aiTitle == nil, record.type == "ai-title" {
                aiTitle = normalized(record.aiTitle)
            }
        }
        return aiTitle
    }

    private func readInterruption(at url: URL, size: Int) -> Interruption? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // The tail only: an interrupt is the last thing written to its file.
        return interruption(in: tail(of: handle, size: size))
    }

    /// The fields the rule asks about. No text field, as in ``AgentHookListener``: message shape is
    /// state, content is not.
    private struct InterruptionRecord: Decodable {
        let type: String?
        /// The hook's `prompt_id`.
        let promptID: String?
        /// Present on every genuine prompt, absent on an interrupt record.
        let promptSource: String?
        let isMeta: Bool?
        let timestamp: String?
        let message: Message?

        enum CodingKeys: String, CodingKey {
            case type, promptSource, isMeta, timestamp, message
            case promptID = "promptId"
        }

        struct Message: Decodable {
            /// Nil when `content` is not a block list, as in a slash-command record.
            let blockTypes: [String]?

            private struct Block: Decodable {
                let type: String?
            }

            private enum CodingKeys: String, CodingKey {
                case content
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                blockTypes = (try? container.decode([Block].self, forKey: .content))?
                    .map { $0.type ?? "" }
            }
        }
    }

    private func interruption(in lines: [Data]) -> Interruption? {
        let decoder = JSONDecoder()
        for line in lines.reversed() {
            guard let record = try? decoder.decode(InterruptionRecord.self, from: line),
                  record.type == "user",
                  record.promptSource == nil,
                  record.isMeta != true,
                  record.message?.blockTypes == ["text"],
                  let turnID = record.promptID, !turnID.isEmpty,
                  let at = instant(record.timestamp) else {
                continue
            }
            return Interruption(turnID: turnID, at: at)
        }
        return nil
    }

    /// A record's RFC 3339 UTC `timestamp`, with or without fractional seconds (a fractional
    /// formatter rejects the plain form).
    private func instant(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(240))
    }
}
