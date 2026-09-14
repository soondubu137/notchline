import AppKit
import Foundation
import SQLite3

// What Antigravity Desktop writes down that its hooks do not say: whether it is
// running, which Project a conversation is filed under, and when the user last
// looked at one. Every reading here is read-only, on files the application
// owns, and fails towards the answer that claims least.
// `docs/technical-explorations/multi-product-provider-architecture/antigravity-desktop.md`
// is the measurement.

/// Whether Antigravity Desktop is running, and the application to raise.
nonisolated protocol AntigravityDesktopLocating: Sendable {
    func runningApplication() async -> HostApplication?
}

/// The running-application list, by bundle identifier.
///
/// `com.google.antigravity` is Desktop 2.x's identifier, and its data directory
/// is `~/.gemini/antigravity`. The pre-2.0 IDE used the same directory — the
/// Desktop's first-run wizard migrates an IDE found there to
/// `~/.gemini/antigravity-ide` — so an unmigrated IDE of that vintage would be
/// taken for Desktop. It cannot be installed beside Desktop at the same path,
/// and nothing about it has been measured.
nonisolated struct AntigravityDesktopApplication: AntigravityDesktopLocating {
    static let bundleIdentifier = "com.google.antigravity"

    func runningApplication() async -> HostApplication? {
        await Self.running()
    }

    @MainActor
    static func running() -> HostApplication? {
        guard let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated }) else {
            return nil
        }
        return HostApplication(
            bundleIdentifier: bundleIdentifier,
            displayName: application.localizedName ?? "Antigravity",
            processIdentifier: application.processIdentifier
        )
    }
}

// MARK: - Projects

/// Which Desktop Project a conversation is filed under.
nonisolated enum AntigravityDesktopProjectResolution: Equatable, Sendable {
    case project(String)
    /// Filed under no Project. `Standalone` is Desktop's own heading for these.
    case standalone
    /// The assignment could not be read, and no earlier reading of it exists.
    /// Never shown as `Standalone`: a failure to read is not an answer.
    case unavailable

    var displayName: String {
        switch self {
        case let .project(name):
            name
        // Was `Standalone`, Desktop's own heading for these -- replaced so a
        // row with no Project reads the same regardless of which product
        // left it that way (``RowContentFallback``).
        case .standalone:
            RowContentFallback.projectName
        case .unavailable:
            DesktopProjectMetadataSnapshot.unavailableProjectName
        }
    }
}

nonisolated protocol AntigravityDesktopProjectResolving: Sendable {
    func resolution(forConversation conversationID: String) -> AntigravityDesktopProjectResolution
}

/// Reads a conversation's Project out of Desktop's conversation summaries and
/// its name out of the Project's own file.
///
/// **Two files, both Desktop's.** `~/.gemini/antigravity/conversation_summaries.db`
/// is the SQLite store its sidebar is built from; its `conversation_summaries`
/// table carries `project_id` per `conversation_id`. The Project itself is
/// `~/.gemini/config/projects/<id>.json`, whose `name` is what the sidebar
/// draws. Measured 2026-09-12 on 2.13.0: a conversation started in a Project
/// has its row, `project_id` included, by the time its first `PreInvocation`
/// reaches this app (queried 34 ms after it); a conversation filed under no
/// Project has an empty id or `outside-of-project`, the renderer's own two
/// spellings of it.
///
/// **What is not used, and why.** The summaries table also has a `status`
/// column that flips between `RUNNING` and `IDLE`, and it lags the hooks by up
/// to a second in both directions — `IDLE` at a Turn's first invocation,
/// `RUNNING` at its `Stop` — so nothing here reads it. A Project is matched by
/// the assignment, never by the folder: two Projects may share one, and a
/// conversation in that folder may belong to neither.
///
/// **The database is in WAL mode**, measured on the live file: its header says
/// so, and while Desktop's server has written recently the newest rows — a new
/// conversation's among them — are in `conversation_summaries.db-wal` and not
/// in the main file, whose modification time does not move. So a change is
/// the main file *or* its WAL changing. And between Desktop's checkpoints
/// neither `-wal` nor `-shm` exists, which a read-only connection cannot open
/// against (SQLite needs to create them and a read-only connection may not —
/// measured failing this way on the first live run, 2026-09-12). With no WAL
/// on disk every committed row is in the main file, so that case is read with
/// `immutable=1`, which asks for neither file and writes nothing beside the
/// database; a checkpoint racing that read can only fail it, which keeps the
/// name the row already had.
///
/// **Cost.** A `stat` of the database, its WAL and the Project file per row per
/// refresh; the database is opened only when it has changed since the
/// conversation's assignment was last read, and the Project file is parsed only
/// when it has changed.
nonisolated final class AntigravityDesktopProjects: AntigravityDesktopProjectResolving, @unchecked Sendable {
    /// Desktop's own key for "no Project".
    static let outsideOfProject = "outside-of-project"

    let summariesDatabase: URL
    let projectsDirectory: URL

    private nonisolated struct Stamp: Equatable {
        let modified: timespec
        let size: off_t

        static func == (lhs: Stamp, rhs: Stamp) -> Bool {
            lhs.modified.tv_sec == rhs.modified.tv_sec
                && lhs.modified.tv_nsec == rhs.modified.tv_nsec
                && lhs.size == rhs.size
        }
    }

    /// The database as it stood: its main file, and its WAL where there is one.
    private nonisolated struct DatabaseStamp: Equatable {
        let main: Stamp
        let writeAheadLog: Stamp?
    }

    private let lock = NSLock()
    /// Each conversation's Project id, and the database it was read from.
    private var assignments: [String: (projectID: String, database: DatabaseStamp)] = [:]
    /// Each Project's name, and the file it was read from.
    private var names: [String: (name: String, file: Stamp)] = [:]
    /// The last answer that was not `unavailable`, per conversation, for a
    /// reading that fails after one succeeded.
    private var lastKnownGood: [String: AntigravityDesktopProjectResolution] = [:]

    init(
        summariesDatabase: URL? = nil,
        projectsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let home = fileManager.homeDirectoryForCurrentUser
        self.summariesDatabase = summariesDatabase
            ?? home.appendingPathComponent(AntigravityHookVocabulary.desktopStateDirectoryRelativeToHome, isDirectory: true)
                .appendingPathComponent("conversation_summaries.db")
        self.projectsDirectory = projectsDirectory
            ?? home.appendingPathComponent(".gemini/config/projects", isDirectory: true)
    }

    func resolution(forConversation conversationID: String) -> AntigravityDesktopProjectResolution {
        lock.lock()
        defer { lock.unlock() }
        let answer = freshResolution(forConversation: conversationID)
        if answer == .unavailable {
            return lastKnownGood[conversationID] ?? .unavailable
        }
        lastKnownGood[conversationID] = answer
        return answer
    }

    private func freshResolution(forConversation conversationID: String) -> AntigravityDesktopProjectResolution {
        guard let main = Self.stamp(summariesDatabase.path) else { return .unavailable }
        let database = DatabaseStamp(main: main, writeAheadLog: Self.stamp(summariesDatabase.path + "-wal"))
        let projectID: String
        if let cached = assignments[conversationID], cached.database == database {
            projectID = cached.projectID
        } else {
            guard let read = Self.projectID(forConversation: conversationID, inDatabaseAt: summariesDatabase.path) else {
                return .unavailable
            }
            assignments[conversationID] = (read, database)
            projectID = read
        }
        if projectID.isEmpty || projectID == Self.outsideOfProject {
            return .standalone
        }
        // An id is a file name here, so it may not name anything else.
        guard !projectID.contains("/"), projectID != ".", projectID != ".." else { return .unavailable }
        let file = projectsDirectory.appendingPathComponent(projectID + ".json").path
        guard let stamp = Self.stamp(file) else { return .unavailable }
        if let cached = names[projectID], cached.file == stamp {
            return .project(cached.name)
        }
        guard let data = FileManager.default.contents(atPath: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return .unavailable
        }
        names[projectID] = (name, stamp)
        return .project(name)
    }

    private static func stamp(_ path: String) -> Stamp? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return Stamp(modified: info.st_mtimespec, size: info.st_size)
    }

    /// The conversation's `project_id`, or nil when the database cannot be
    /// read or holds no row for it. An empty string is an answer: no Project.
    static func projectID(forConversation conversationID: String, inDatabaseAt path: String) -> String? {
        if let answer = projectID(forConversation: conversationID, opening: path, flags: SQLITE_OPEN_READONLY) {
            return answer
        }
        // A WAL database between checkpoints, with no `-wal` to read beside it:
        // everything committed is in the main file.
        guard !FileManager.default.fileExists(atPath: path + "-wal"),
              var components = URLComponents(string: "file:") else {
            return nil
        }
        components.path = path
        components.queryItems = [URLQueryItem(name: "immutable", value: "1")]
        guard let uri = components.string else { return nil }
        return projectID(
            forConversation: conversationID,
            opening: uri,
            flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        )
    }

    private static func projectID(forConversation conversationID: String, opening name: String, flags: Int32) -> String? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(name, &database, flags, nil) == SQLITE_OK else {
            sqlite3_close_v2(database)
            return nil
        }
        defer { sqlite3_close_v2(database) }
        // Desktop writes this file while it runs, and row content is built on
        // the main actor. A reader that cannot get its lock at once waits no
        // longer than a frame and then answers nothing, which keeps the last
        // name the row had.
        sqlite3_busy_timeout(database, 10)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT project_id FROM conversation_summaries WHERE conversation_id = ?1",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, conversationID, -1, transient) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        guard let text = sqlite3_column_text(statement, 0) else { return "" }
        return String(cString: text)
    }
}

// MARK: - Read records

/// What Desktop has recorded about the user looking at one conversation.
nonisolated struct AntigravityDesktopReadRecord: Sendable, Equatable {
    /// `last_user_view_time`, or nil where Desktop has recorded no view.
    let lastViewedAt: Date?
    /// `marked_as_unread`: the user asked for the conversation to stay unread.
    let markedAsUnread: Bool
}

nonisolated protocol AntigravityDesktopReadRecordReading: Sendable {
    /// The record, or nil where there is none or it cannot be parsed.
    func record(forConversation conversationID: String) -> AntigravityDesktopReadRecord?
}

/// Reads `~/.gemini/antigravity/annotations/<conversationId>.pbtxt`.
///
/// **When Desktop writes the view time**, read out of 2.13.0's renderer and
/// then measured on the file: when the user moves from one conversation to
/// another, the one left and — if the window has focus — the one entered;
/// when the window regains focus, the conversation on screen; and when a new
/// conversation is started. It is **not** written while the user sits on a
/// conversation whose Turn finishes: the renderer keeps that view in memory
/// only, to draw its own sidebar. So a row watched to its end in Desktop stays
/// until the user leaves that conversation, switches back to Desktop's window,
/// or submits again — the side of the line that keeps a row.
///
/// The file is text-format protobuf, a handful of fields on one line:
///
/// ```text
/// title:"Request To Say Hi" last_user_view_time:{seconds:1789252368 nanos:120000000}
/// ```
nonisolated struct AntigravityDesktopReadRecords: AntigravityDesktopReadRecordReading {
    /// A record is a title and two timestamps; anything much larger is not one.
    static let maximumSize = 64 * 1024

    let annotationsDirectory: URL

    init(annotationsDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.annotationsDirectory = annotationsDirectory
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(AntigravityHookVocabulary.desktopStateDirectoryRelativeToHome, isDirectory: true)
                .appendingPathComponent("annotations", isDirectory: true)
    }

    func record(forConversation conversationID: String) -> AntigravityDesktopReadRecord? {
        guard !conversationID.isEmpty, !conversationID.contains("/"),
              conversationID != ".", conversationID != ".." else {
            return nil
        }
        let url = annotationsDirectory.appendingPathComponent(conversationID + ".pbtxt")
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maximumSize + 1),
              data.count <= Self.maximumSize,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return Self.parse(text)
    }

    /// The two fields this reads, out of a text-format message; nil for text
    /// that is not one.
    ///
    /// Strings are blanked before anything is matched, so a title cannot carry
    /// a field of its own, and an unterminated string or an unbalanced brace
    /// is no record at all rather than part of one.
    static func parse(_ text: String) -> AntigravityDesktopReadRecord? {
        guard let bare = withoutStrings(text),
              bare.filter({ $0 == "{" }).count == bare.filter({ $0 == "}" }).count else {
            return nil
        }
        var lastViewedAt: Date?
        if let view = bare.firstMatch(of: #/(?:^|[\s,;])last_user_view_time\s*:?\s*\{([^{}]*)\}/#) {
            guard let seconds = view.1.firstMatch(of: #/(?:^|[\s,;])seconds\s*:\s*(\d+)/#).flatMap({ Int64($0.1) }) else {
                return nil
            }
            let nanos = view.1.firstMatch(of: #/(?:^|[\s,;])nanos\s*:\s*(\d+)/#).flatMap { Int64($0.1) } ?? 0
            lastViewedAt = Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanos) / 1_000_000_000)
        }
        return AntigravityDesktopReadRecord(
            lastViewedAt: lastViewedAt,
            markedAsUnread: bare.contains(#/(?:^|[\s,;])marked_as_unread\s*:\s*true(?:$|[\s,;])/#)
        )
    }

    /// The text with every quoted string removed, or nil when one never ends.
    private static func withoutStrings(_ text: String) -> String? {
        var bare = ""
        var quote: Character?
        var escaped = false
        for character in text {
            if let open = quote {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == open {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else {
                bare.append(character)
            }
        }
        return quote == nil ? bare : nil
    }
}
