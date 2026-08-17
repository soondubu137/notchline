import Foundation

/// Reads the title Claude Code shows for a session.
///
/// **This is a private dependency.** The transcript is written by Claude Code
/// for its own use and its record structure is not a published contract, so
/// every rule below fails closed: an unreadable, unfamiliar or retitled file
/// produces no title rather than a guess, and the row says `Untitled` — never
/// the folder name, which the data-truth contract forbids standing in for one.
///
/// Registered in `docs/non-public-codex-integration-features.md`.
actor ClaudeCodeTranscriptReader {
    /// How much of either end of a transcript is examined.
    ///
    /// Transcripts reach tens of megabytes; one on this machine is 16 MB. The
    /// most recent title is the right one, so the tail is read first. A session
    /// that was titled once early and never again is why the head is read as
    /// well, and why neither read is allowed to become "read the whole file".
    static let scannedBytes = 64 * 1024

    private struct CacheEntry {
        let size: Int
        let modifiedAt: Date
        let title: String?
    }

    private let projectsDirectory: URL
    private let fileManager: FileManager
    private var resolvedPaths: [String: URL] = [:]
    private var cache: [String: CacheEntry] = [:]

    init(
        projectsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.projectsDirectory = projectsDirectory
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true)
        self.fileManager = fileManager
    }

    /// The session's title, or nil when none can be read.
    func title(forSession sessionID: String, workingDirectory: URL) -> String? {
        guard let url = transcriptURL(
            forSession: sessionID,
            workingDirectory: workingDirectory
        ) else {
            return nil
        }

        // A transcript is appended to constantly, so re-reading one that has
        // not grown is pure waste on every refresh of every row.
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        let modifiedAt = (attributes?[.modificationDate] as? Date) ?? .distantPast
        if let cached = cache[sessionID],
           cached.size == size, cached.modifiedAt == modifiedAt {
            return cached.title
        }

        let title = readTitle(at: url, size: size)
        cache[sessionID] = CacheEntry(size: size, modifiedAt: modifiedAt, title: title)
        return title
    }

    /// The turn a session is part-way through, if it is part-way through one.
    ///
    /// This is what makes cold start possible, and it is the one capability
    /// that genuinely separates the two products. Codex has no supported way to
    /// ask what is happening right now, so the product shows nothing from
    /// before launch; Claude Code writes it down.
    ///
    /// What the transcript cannot say is *what* a turn is waiting for — nothing
    /// is written while a prompt sits in front of the user. So a reconstructed
    /// turn is only ever `Running`, and the first real event refines it.
    func currentTurn(
        forSession sessionID: String,
        workingDirectory: URL
    ) -> TranscriptTurn? {
        guard let url = transcriptURL(
            forSession: sessionID,
            workingDirectory: workingDirectory
        ) else {
            return nil
        }
        let size = (try? fileManager.attributesOfItem(atPath: url.path))
            .flatMap { ($0[.size] as? NSNumber)?.intValue } ?? 0
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return Self.turn(in: tail(of: handle, size: size))
    }

    /// Whether a session is mid-turn, and which turn it is.
    struct TranscriptTurn: Sendable, Equatable {
        let turnID: String
        let startedAt: Date
        let isUnfinished: Bool
    }

    private struct TurnRecord: Decodable {
        let type: String?
        let promptId: String?
        let timestamp: String?
        let message: Message?

        struct Message: Decodable {
            let role: String?
            let stopReason: String?

            enum CodingKeys: String, CodingKey {
                case role
                case stopReason = "stop_reason"
            }
        }
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Reads the turn state out of a run of records.
    ///
    /// Two facts do the work, both measured rather than documented: an
    /// `assistant` record carries `stop_reason` and no prompt id, and a `user`
    /// record carries the prompt id whether it is a prompt or a tool result. So
    /// the id comes from the last `user` record and the state from the last
    /// `assistant` one — unless a `user` record came after it, which means the
    /// assistant has not answered yet.
    nonisolated private static func turn(in lines: [Data]) -> TranscriptTurn? {
        var turnID: String?
        var startedAt: Date?
        var isUnfinished: Bool?

        for line in lines {
            guard let record = try? JSONDecoder().decode(TurnRecord.self, from: line) else {
                continue
            }
            switch record.type {
            case "user":
                if let promptID = record.promptId, !promptID.isEmpty {
                    if promptID != turnID {
                        turnID = promptID
                        startedAt = nil
                    }
                    // The earliest moment of this turn that this read can see.
                    // A turn whose start is older than the read window is timed
                    // from here, which under-counts rather than inventing a
                    // start -- the same rule the Codex side follows.
                    if let stamp = record.timestamp.flatMap(timestampFormatter.date(from:)),
                       startedAt == nil || stamp < startedAt! {
                        startedAt = stamp
                    }
                }
                // A user record after the assistant's last word means the
                // assistant has not had its turn yet.
                isUnfinished = true
            case "assistant":
                guard let reason = record.message?.stopReason else { continue }
                isUnfinished = reason == "tool_use"
            default:
                // Titles, modes, queue bookkeeping: not turn state.
                continue
            }
        }

        guard let turnID, let startedAt, isUnfinished == true else { return nil }
        return TranscriptTurn(turnID: turnID, startedAt: startedAt, isUnfinished: true)
    }

    /// Drops what is remembered about sessions that no longer exist.
    func retain(sessionIDs: Set<String>) {
        cache = cache.filter { sessionIDs.contains($0.key) }
        resolvedPaths = resolvedPaths.filter { sessionIDs.contains($0.key) }
    }

    // MARK: - Locating

    private func transcriptURL(forSession sessionID: String, workingDirectory: URL) -> URL? {
        if let known = resolvedPaths[sessionID],
           fileManager.fileExists(atPath: known.path) {
            return known
        }

        // Claude Code names a project directory after the working directory
        // with every separator replaced. Verified against this machine, but it
        // is an observation, so it is only ever a first guess.
        let slug = workingDirectory.standardizedFileURL.path
            .replacingOccurrences(of: "/", with: "-")
        let guess = projectsDirectory
            .appendingPathComponent(slug, isDirectory: true)
            .appendingPathComponent("\(sessionID).jsonl")
        if fileManager.fileExists(atPath: guess.path) {
            resolvedPaths[sessionID] = guess
            return guess
        }

        // The fallback needs only the weaker fact that a transcript is named
        // after its session, so a change to the directory rule alone does not
        // cost the title.
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

    private func readTitle(at url: URL, size: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        if let title = title(in: tail(of: handle, size: size)) {
            return title
        }
        // Only worth a second look when the file is bigger than one read.
        guard size > Self.scannedBytes else { return nil }
        return title(in: head(of: handle))
    }

    private func tail(of handle: FileHandle, size: Int) -> [Data] {
        let offset = max(0, size - Self.scannedBytes)
        try? handle.seek(toOffset: UInt64(offset))
        guard let data = try? handle.readToEnd() else { return [] }
        var lines = Self.jsonLines(in: data)
        // The first line of a mid-file read is a fragment of a record.
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }

    private func head(of handle: FileHandle) -> [Data] {
        try? handle.seek(toOffset: 0)
        guard let data = try? handle.read(upToCount: Self.scannedBytes) else { return [] }
        var lines = Self.jsonLines(in: data)
        // The last line of a truncated read is a fragment.
        if !lines.isEmpty { lines.removeLast() }
        return lines
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

    /// The last title in these records, preferring one the user set.
    private func title(in lines: [Data]) -> String? {
        var aiTitle: String?
        for line in lines.reversed() {
            guard let record = try? JSONDecoder().decode(TitleRecord.self, from: line) else {
                continue
            }
            // A title the user typed outranks one the product generated,
            // wherever each sits in the file.
            if record.type == "custom-title", let title = normalized(record.customTitle) {
                return title
            }
            if aiTitle == nil, record.type == "ai-title" {
                aiTitle = normalized(record.aiTitle)
            }
        }
        return aiTitle
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(240))
    }
}
