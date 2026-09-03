import Darwin
import Foundation
import os

/// Whether the user has looked at a Claude Code session, and when.
///
/// The question this answers is the one the notch needs to retire a finished
/// row: a Turn that has ended stays listed until the user has actually read it
/// (`未读终态`). Codex answers it with Desktop's blue dot; Claude Code has no
/// equivalent public signal at all -- see
/// ``ClaudeCodeDesktopReadStateRepository`` for what is read instead, and for
/// the half of the product this cannot cover.
nonisolated protocol ClaudeCodeReadStateProviding: Sendable {
    func snapshot() async -> ClaudeCodeReadStateSnapshot
    nonisolated func changeEvents() -> AsyncStream<Void>
}

/// What is known right now about which sessions have been read.
///
/// **Keyed by the id the hooks use.** Claude Desktop files its own session
/// state under an id of its own (`local_<uuid>`) and records the CLI's id
/// alongside it, so the two can be joined without guessing.
struct ClaudeCodeReadStateSnapshot: Equatable, Sendable {
    /// What Claude Desktop last recorded about one session.
    struct Entry: Equatable, Sendable {
        /// When Claude Desktop last put this session on screen.
        ///
        /// Absent for a session it has recorded but never displayed, which is
        /// not the same as "never read": absent can only ever mean *unread*
        /// here, never read.
        let lastFocusedAt: Date?
        /// Whether the user has archived the session in Claude Desktop.
        let isArchived: Bool

        nonisolated init(lastFocusedAt: Date?, isArchived: Bool) {
            self.lastFocusedAt = lastFocusedAt
            self.isArchived = isArchived
        }
    }

    /// How much this snapshot may be trusted to *hide* a row.
    ///
    /// It never decides whether a row may be *shown*: the timestamps do that on
    /// their own, and they are self-limiting in a way an unread set is not. A
    /// stale reading carries old focus instants, and an old instant can only
    /// fail to clear a newer Turn -- so the worst a stale reading does is keep
    /// a row the user has already read, which is the failure this product
    /// prefers.
    enum Source: Equatable, Sendable {
        case current
        case lastKnownGood
        case unavailable

        nonisolated var isAuthoritative: Bool {
            if case .current = self { return true }
            return false
        }
    }

    /// Whether one session has been read, when that is knowable at all.
    enum SessionReadState: Equatable, Sendable {
        case read
        case unread
        /// Claude Desktop has no record of this session, so nothing here can
        /// speak for it. Every session started from a terminal is in this
        /// state, permanently -- see ``ClaudeCodeDesktopReadStateRepository``.
        case unknown
    }

    private let entries: [String: Entry]
    /// The CLI session id filed under each of Claude Desktop's own ids.
    ///
    /// The records are keyed by `cliSessionId` because that is the id the hooks
    /// carry, and this is the same join pointed the other way -- for the one
    /// caller that starts from Desktop's id instead: Desktop's log, which names
    /// what it has on screen as `local_<uuid>` (see
    /// ``DesktopDisplayedSessionReporting``). An id that is missing here joins
    /// to nothing, and a session that joins to nothing is not one of these
    /// rows.
    private let cliSessionIDsByDesktopID: [String: String]
    /// The same join pointed back again: Claude Desktop's own id for a session
    /// the hooks name. Derived rather than stored separately, so the two can
    /// never disagree.
    ///
    /// It answers the one question the forward join cannot, and only that one:
    /// *is the name on screen a different session's name?* A record Claude
    /// Desktop has not written yet joins to nothing forwards -- which is the
    /// ordinary state for a second or so after the user navigates -- and a
    /// session whose own record names a different id is plainly not the one on
    /// screen, whatever that pending record turns out to say.
    private let desktopIDsByCLISessionID: [String: String]
    let source: Source
    let diagnostic: String?
    /// The session Claude Desktop most recently put on screen, if it has
    /// recorded putting any there.
    ///
    /// **This is not "which session is on screen right now", and the gap is
    /// load-bearing.** Desktop stamps the instant a session is *shown* and
    /// never records it being hidden, so the newest stamp is the last thing it
    /// displayed — which the user may since have left for something that is not
    /// a session at all, most often the composer for a new one. Nothing in
    /// these records can see that happen; ``DesktopDisplayedSessionReporting``
    /// is where Desktop says it, and ``ClaudeCodeMonitorService`` requires the
    /// two to agree before it treats a session as being on screen.
    let mostRecentlyDisplayedSessionID: String?

    nonisolated init(
        entries: [String: Entry],
        source: Source,
        diagnostic: String? = nil,
        cliSessionIDsByDesktopID: [String: String] = [:]
    ) {
        self.entries = entries
        self.cliSessionIDsByDesktopID = cliSessionIDsByDesktopID
        // A session two Desktop ids claim cannot say which one is its own, so
        // it answers nothing rather than picking -- the same rule the forward
        // join applies to an ambiguous Desktop id, pointed the other way.
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
        // Ties broken by id so the answer cannot flap between two records that
        // were stamped in the same millisecond.
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

    /// Which session the hooks would call the one Claude Desktop files under
    /// `desktopSessionID`, when the records can say.
    nonisolated func cliSessionID(forDesktopSessionID desktopSessionID: String) -> String? {
        cliSessionIDsByDesktopID[desktopSessionID]
    }

    /// What Claude Desktop calls the session the hooks call `sessionID`, when
    /// the records say. `nil` for a session Desktop has no record of, and for
    /// one whose record has stopped carrying its own id.
    nonisolated func desktopSessionID(forSession sessionID: String) -> String? {
        desktopIDsByCLISessionID[sessionID]
    }

    /// Whether the user has read what ended at `terminalBoundaryAt`.
    ///
    /// **Compared against the Turn's own last moment, not against Desktop's
    /// idea of when the session was last active.** Claude Desktop records both
    /// halves -- `lastFocusedAt` and `lastActivityAt` -- and their difference is
    /// the natural unread equivalent, but this app already holds a better left
    /// half than the file does: the instant the Turn actually ended, from the
    /// event that ended it. Using it means a Desktop that lags, throttles or
    /// stops writing activity cannot make a Turn look read; only a focus
    /// recorded *after* the Turn finished can.
    ///
    /// Archiving counts as reading. It is a deliberate act on that session and
    /// it is what Codex's rule already says (`已读、归档、删除后移除`).
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

/// Claude Desktop's own record of which sessions it has shown the user.
///
/// **Why this exists at all.** A finished Claude Code row used to disappear in
/// exactly three cases: that session's next `UserPromptSubmit`, the session
/// leaving the official session list, or the user clearing it by hand (CC-013).
/// Reading the answer in Claude Desktop was not one of them, so a user who read
/// a turn and moved on kept the row forever.
///
/// **What is read.** `~/Library/Application Support/Claude/claude-code-sessions/
/// <org>/<account>/local_<uuid>.json`, and out of it four fields:
/// `cliSessionId` (the id the hooks carry, so no id has to be guessed),
/// `sessionId` (Desktop's own id for the same session, which is what its log
/// names on screen), `lastFocusedAt`, and `isArchived`. Nothing else in those
/// files is decoded -- they also hold the session's title, its working
/// directory and its MCP configuration, none of which this app takes from here.
///
/// `lastFocusedAt` is stamped by Claude Desktop when it puts a session on
/// screen, and the record is written immediately afterwards, by atomic replace
/// -- so a directory watcher reports it, and the row leaves the notch on the
/// same gesture that reads it.
///
/// **What it cannot cover, by construction.** A session started from a terminal
/// has no file here and no concept of "read" anywhere else: Claude Code's own
/// session record carries `status`, `waitingFor` and `updatedAt` and nothing
/// about focus (checked against 2.1.235). Such a session is reported
/// ``ClaudeCodeReadStateSnapshot/SessionReadState/unknown`` and its finished row
/// keeps the behaviour it has always had. Guessing from window focus or a timer
/// is banned outright (`AGENTS.md` §6.2), and this adapter does not do it.
///
/// **Fail closed.** Every failure -- a missing tree, an unreadable file, a
/// schema that no longer carries `cliSessionId` -- reports `unknown` for the
/// sessions it could not speak for, which keeps their rows listed.
actor ClaudeCodeDesktopReadStateRepository: ClaudeCodeReadStateProviding {
    private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "ClaudeCodeDesktopReadState"
    )

    /// An override for tests and for an install somewhere unusual. Points at
    /// Claude Desktop's application-support directory, the way
    /// `NOTCHLINE_CODEX_HOME` points at `$CODEX_HOME`.
    nonisolated static let homeOverrideKey = "NOTCHLINE_CLAUDE_DESKTOP_HOME"

    nonisolated private static let sessionsDirectoryName = "claude-code-sessions"
    nonisolated private static let recordPrefix = "local_"
    nonisolated private static let recordSuffix = ".json"
    nonisolated private static let maximumRecordSize = 4 * 1_024 * 1_024
    /// A ceiling on how many records one reading opens.
    ///
    /// Records accumulate for as long as the user keeps sessions, and this app
    /// only ever asks about sessions that are running right now. A running
    /// session's record was necessarily written when Claude Desktop last
    /// displayed or resumed it, so the ones that can matter are the most
    /// recently written ones; the tail beyond this cap answers `unknown` and
    /// keeps its row, which is the same conservative outcome as any other gap.
    nonisolated private static let maximumScannedRecords = 512
    /// One bulk read of a folder's attributes. Sized so an ordinary tree comes
    /// back in a single call; a larger one simply loops.
    nonisolated private static let attributeBufferSize = 64 * 1_024

    private struct FileRevision: Equatable {
        let size: UInt64
        let modificationDate: Date?
        let fileNumber: UInt64?
    }

    private struct Record: Decodable {
        let cliSessionID: String
        /// Claude Desktop's own id for this session, `local_<uuid>`, which is
        /// also this file's name and the id its log names on screen. Optional
        /// because a record that has stopped carrying it can still answer
        /// everything else; what it loses is the join in
        /// ``ClaudeCodeReadStateSnapshot/cliSessionID(forDesktopSessionID:)``,
        /// and a session that cannot be joined keeps its row.
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
            // Milliseconds since the epoch, the way every timestamp in these
            // files is written.
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
    /// Parsed records, keyed by file and answered against the file's revision.
    ///
    /// The whole tree is stat'ed on every reading and only the records that
    /// changed since the last one are opened. Claude Desktop rewrites a record
    /// for reasons of its own as well as for focus, so this is what keeps a
    /// reading proportional to what actually moved rather than to how many
    /// sessions the user has ever had.
    private var cachedRecords: [URL: (revision: FileRevision, record: Record?)] = [:]
    private var lastKnownGood: ClaudeCodeReadStateSnapshot?

    /// Claude Desktop's application-support root.
    ///
    /// Named here rather than spelled at each use because two unrelated things
    /// now read this tree: the session records below, and the CLI copy Desktop
    /// keeps under `claude-code/<version>` that ``ClaudeExecutableLocator``
    /// falls back to on a machine where nobody installed the terminal command.
    /// One override has to move both, or a test pointing this at its own tree
    /// silently leaves the other reading the developer's real Claude Desktop.
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
        // The root on its own until the first reading discovers the account
        // folders under it. It is also the edge that reports a *new* account
        // folder, which is the one thing the reconcile below cannot find on its
        // own.
        watcher.watch(paths: [stateDirectoryURL])
    }

    nonisolated func changeEvents() -> AsyncStream<Void> {
        watcher.events()
    }

    func snapshot() async -> ClaudeCodeReadStateSnapshot {
        // The whole pass is pooled, exactly as the token counter's is and for
        // the same reason. Listing the account folders bridges an `NSURL` per
        // entry, `resourceValues` and `attributesOfItem` bridge a dictionary
        // apiece for every record that has changed since the last reading, and
        // `JSONDecoder` builds one more; all of it is autoreleased, and none of
        // it is drained inside a synchronous actor method.
        //
        // The exposure is what makes it worth doing here. The token counter
        // runs once a minute; this runs once per refresh, which is once a
        // second for as long as any finished row is listed (CR-Fable-041).
        autoreleasepool { currentSnapshot() }
    }

    private func currentSnapshot() -> ClaudeCodeReadStateSnapshot {
        guard let accountDirectories = accountDirectories() else {
            // No tree at all. That is the ordinary state for a user who runs
            // Claude Code only from a terminal, so it carries no diagnostic:
            // there is nothing wrong and nothing for them to fix.
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
            // Two accounts holding one Desktop id would make the join a guess,
            // and a guess here would let Desktop's log name the wrong session
            // on screen. Neither answer is taken: the id joins to nothing, and
            // both rows stay listed.
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

        // Everything unreadable, with something there to read, is the shape a
        // schema change takes. One unreadable record among many is not: a
        // record being written right now looks exactly like that, and the
        // session it belongs to answers `unknown` and keeps its row anyway.
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

    /// The conservative half of two records naming one session.
    ///
    /// Two files should never carry the same `cliSessionId`, and if they ever
    /// do, the one that hides a row is the wrong one to believe. The earlier
    /// focus wins and archiving has to be unanimous, so a duplicate can only
    /// ever keep a row listed for longer.
    nonisolated private static func merging(
        _ existing: ClaudeCodeReadStateSnapshot.Entry?,
        with entry: ClaudeCodeReadStateSnapshot.Entry
    ) -> ClaudeCodeReadStateSnapshot.Entry {
        guard let existing else { return entry }
        let focused: Date?
        switch (existing.lastFocusedAt, entry.lastFocusedAt) {
        case let (lhs?, rhs?): focused = min(lhs, rhs)
        // One of them says the session was never displayed, which is the
        // reading that keeps the row.
        default: focused = nil
        }
        return ClaudeCodeReadStateSnapshot.Entry(
            lastFocusedAt: focused,
            isArchived: existing.isArchived && entry.isArchived
        )
    }

    /// `<root>/<org>/<account>`, or nil when there is no tree to read.
    ///
    /// Exactly two levels: this is a location, not a search. A tree that has
    /// grown a level answers nothing rather than guessing where the records
    /// moved to.
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
    /// **The names and the three numbers come out of the directory together**,
    /// which is what makes this affordable to repeat. A listed finished row
    /// asks for a refresh once a second, and every refresh asks this for every
    /// record in the tree -- the whole point of the revisions is to decide
    /// which records are worth opening, so they are read before any cache can
    /// save anything.
    ///
    /// Listing through `FileManager` and then `stat`ing each entry costs a
    /// system call per record and builds a `URL` object for every name in the
    /// folder; `getattrlistbulk` answers the same directory in one call per
    /// bufferful and hands back the name beside the attributes. Measured in
    /// Release over this machine's 41 records: **0.06ms a pass against
    /// 0.44ms**, and the gap widens with the record count -- a tree at
    /// ``maximumScannedRecords`` would have been paying it 512 times a second.
    ///
    /// It reports the link rather than its target, exactly as the `stat` it
    /// replaced did, and it filters on the name alone: a record that is not a
    /// regular file is refused by ``loadRecord(from:)`` on its own terms, and
    /// is meant to be counted as a failure there rather than quietly skipped
    /// here.
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

    /// One account folder's records, read in bulk.
    ///
    /// The buffer holds a run of variable-length entries, each one a length
    /// followed by the attributes that were actually returned -- which is why
    /// `ATTR_CMN_RETURNED_ATTRS` is asked for first and every field below is
    /// read only when the kernel says it is there. Fields are packed rather
    /// than aligned, so each is loaded unaligned.
    ///
    /// A directory this cannot open, or a call that fails part way, answers
    /// with what it has. That is the same shape the enumerator had: a folder
    /// that cannot be listed contributes nothing and the others still do.
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
        // Absent for anything that is not a regular file, which reads as zero
        // and is exactly what the record of such an entry is worth: it names a
        // revision that does not move, and the load that follows refuses it.
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
