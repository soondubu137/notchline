import Darwin
import Foundation

/// Reads what Claude Code writes about a session in its own transcript.
///
/// Two questions, and they are not the same kind of question. One is the title
/// the product shows for the session, which is content and is read only when
/// the user allows content. The other is whether the Turn a session is holding
/// was **interrupted** -- the only place a user interrupt is recorded at all
/// for a session the Claude Code desktop app hosts (CC-022), which reports no
/// working status for the session-list route to read (see
/// ``ClaudeCodeActivity``). That one is state, not content: it is read whatever
/// the preview switch says, and no message text is decoded to answer it.
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

    /// The last interruption in one transcript's tail, and the state the file
    /// was in when it was read.
    ///
    /// Cached separately from the title rather than beside it, because the two
    /// reads are asked for under different conditions: a title only when the
    /// user allows content, an interruption on every refresh that has a Turn to
    /// end. One entry holding both would make the cheaper question wait on the
    /// switch that governs the other.
    private struct InterruptionEntry {
        let size: Int
        let modifiedAt: Date
        let interruption: Interruption?
    }

    /// A Turn the transcript records as having been interrupted.
    private struct Interruption {
        /// The Turn it names, which is the hook's `prompt_id` -- see
        /// ``interruption(forSession:workingDirectory:turnID:after:)``.
        let turnID: String
        let at: Date
    }

    private let projectsDirectory: URL
    private let fileManager: FileManager
    private var resolvedPaths: [String: URL] = [:]
    private var cache: [String: CacheEntry] = [:]
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
        let (size, modifiedAt) = Self.revision(of: url)
        if let cached = cache[sessionID],
           cached.size == size, cached.modifiedAt == modifiedAt {
            return cached.title
        }

        let title = readTitle(at: url, size: size)
        cache[sessionID] = CacheEntry(size: size, modifiedAt: modifiedAt, title: title)
        return title
    }

    /// When the Turn this session is holding was interrupted, if it was.
    ///
    /// **This is the only report an interrupt makes for a desktop-hosted
    /// session.** No hook fires for one (ADR 0011), and the working status the
    /// CLI publishes -- which is what ends an interrupted Turn everywhere else
    /// -- is written by the terminal interface the desktop app does not run, so
    /// those sessions never carry it (CC-022). What is left is that Claude Code
    /// writes a `user` record at the moment it aborts, and that record names the
    /// Turn it aborted.
    ///
    /// **It reads no message text, and does not need to.** The rule is
    /// structural: a `user` record whose message carries exactly one `text`
    /// block, with no `promptSource` and no `isMeta`. Surveyed over every
    /// transcript on this machine on 2026-08-19 -- 205 files, 7,438 `user`
    /// records -- it matched 15 of 15 interrupt records and **nothing else at
    /// all**. The rule the issue proposed was one clause weaker (it did not ask
    /// about the shape of `content`) and that clause is the whole of it: the 202
    /// records that separate the two are slash-command and
    /// `<local-command-stdout>` records, which carry their content as a plain
    /// string rather than as blocks. They are not harmless, either, which is why
    /// this was measured rather than reasoned about: 23 of them are followed by
    /// the model working on the same `promptId`, so a rule that matched them
    /// would retire Turns that were still running -- the one direction this app
    /// is not allowed to be wrong in.
    ///
    /// **It names the Turn, so it may only end that one.** The record's
    /// `promptId` is the same value the hooks call `prompt_id`, which is the
    /// reducer's Turn identity: measured on 2.1.237 with a hook listener of its
    /// own, `UserPromptSubmit` and the interrupt record carried the same id.
    /// That is a stronger footing than the session-status route has -- that one
    /// names no Turn and can only speak about whichever one the reducer holds --
    /// and it is what makes the remaining difference between an interrupt record
    /// and a genuine prompt (`promptSource`) safe to lean on: a prompt opens a
    /// Turn under a *new* id, so even a version that stopped writing
    /// `promptSource` could not make one end the Turn it starts.
    ///
    /// - Parameter after: The Turn's last known moment. A record older than
    ///   that describes an earlier Turn of the same session, or the same
    ///   interrupt already applied.
    /// - Returns: When the interrupt was written, or nil when there is none to
    ///   report. Only the newest record in the tail is considered, which is the
    ///   one an interrupt would be.
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

        // A transcript that has not changed cannot have gained a record, and
        // this is asked once per refresh for every Turn still going.
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

    /// Drops what is remembered about sessions that no longer exist.
    func retain(sessionIDs: Set<String>) {
        cache = cache.filter { sessionIDs.contains($0.key) }
        interruptions = interruptions.filter { sessionIDs.contains($0.key) }
        resolvedPaths = resolvedPaths.filter { sessionIDs.contains($0.key) }
    }

    // MARK: - Locating

    /// The file this session's records are written to, or nil when it cannot be
    /// found.
    ///
    /// Not private, because the low-latency half of ending an interrupted Turn
    /// is a watch on that file and the path rule lives here -- see
    /// ``ClaudeCodeMonitorService``. Resolving is cached, so asking every
    /// refresh costs a `fileExists` and no directory scan.
    func transcriptURL(forSession sessionID: String, workingDirectory: URL) -> URL? {
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

    /// The size and modification date the caches above are keyed by, from one
    /// `stat`.
    ///
    /// `FileManager.attributesOfItem` answers the same two, and gets there by
    /// listing the file's extended attributes and reading each one back,
    /// resolving the owner and group through Directory Services, and bridging
    /// a dictionary of around twenty values. That is roughly fifty times the
    /// work of the call below, and it is bought once per listed row per
    /// refresh -- once a second while a finished row waits to be read.
    ///
    /// A file that cannot be stat'ed answers `(0, .distantPast)`, which is what
    /// the unreadable case answered before: no cache entry matches it, so the
    /// reading below is attempted and fails on its own terms.
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

    /// - Note: Pooled, like every `FileHandle` read in this app. The `Data` it
    ///   hands back is autoreleased, and on a thread with no pool of its own
    ///   nothing ever drains it -- 64 KB per title, per session, on every
    ///   refresh, kept for the life of the process. `jsonLines` copies the part
    ///   worth keeping, so draining the rest costs nothing.
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

    /// - Note: Pooled, for the reason given on ``tail(of:size:)``.
    private func head(of handle: FileHandle) -> [Data] {
        try? handle.seek(toOffset: 0)
        var lines = autoreleasepool { () -> [Data] in
            guard let data = try? handle.read(upToCount: Self.scannedBytes) else {
                return []
            }
            return Self.jsonLines(in: data)
        }
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

    private func readInterruption(at url: URL, size: Int) -> Interruption? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // The tail only, and no second look at the head: an interrupt is the
        // last thing written to the file it happened in. The title read looks
        // at both ends because a title can be old; this cannot.
        return interruption(in: tail(of: handle, size: size))
    }

    /// The fields the rule asks about. **There is no text field**, exactly as
    /// ``AgentHookListener``'s decoder has none: the shape of the message is
    /// state, its content is not, and nothing here should be able to hold the
    /// latter by accident.
    private struct InterruptionRecord: Decodable {
        let type: String?
        /// The Turn, spelled as the transcript spells it. It is the hook's
        /// `prompt_id`.
        let promptID: String?
        /// Present on every genuine prompt, absent on the record an interrupt
        /// writes.
        let promptSource: String?
        let isMeta: Bool?
        let timestamp: String?
        let message: Message?

        enum CodingKeys: String, CodingKey {
            case type, promptSource, isMeta, timestamp, message
            case promptID = "promptId"
        }

        /// A message reduced to the *types* of its blocks.
        struct Message: Decodable {
            /// Nil when `content` is not a list of blocks at all -- which is how
            /// a slash-command record is written, and the clause that keeps this
            /// rule off it.
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

    /// The newest interrupt record in these lines, if one of them is.
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

    /// A record's `timestamp`, which is RFC 3339 in UTC.
    ///
    /// Both forms are accepted. Every interrupt record seen carries fractional
    /// seconds, and a formatter configured for them rejects a timestamp without
    /// them outright -- so the plain form is tried as well rather than letting a
    /// record that is otherwise an interrupt fall silently out of the scan.
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
