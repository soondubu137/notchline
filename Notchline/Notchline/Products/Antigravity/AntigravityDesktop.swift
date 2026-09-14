import AppKit
import Foundation
import SQLite3

// What Antigravity Desktop writes that its hooks do not say: running state, a conversation's
// Project, when the user last looked. Read-only, failing towards the answer that claims least.
// Measurements: `docs/technical-explorations/multi-product-provider-architecture/antigravity-desktop.md`.

/// Whether Antigravity Desktop is running, and the application to raise.
nonisolated protocol AntigravityDesktopLocating: Sendable {
    func runningApplication() async -> HostApplication?
}

/// The running-application list, by bundle identifier. `com.google.antigravity` is Desktop 2.x;
/// an unmigrated pre-2.0 IDE shared the id's data directory and would be taken for Desktop
/// (unmeasured).
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

nonisolated enum AntigravityDesktopProjectResolution: Equatable, Sendable {
    case project(String)
    /// Filed under no Project. `Standalone` is Desktop's own heading for these.
    case standalone
    /// The assignment could not be read and no earlier reading exists. Never shown as `Standalone`.
    case unavailable

    var displayName: String {
        switch self {
        case let .project(name):
            name
        // Shown as ``RowContentFallback`` so a row with no Project reads the same for every product.
        case .standalone:
            RowContentFallback.projectName
        case .unavailable:
            RowContentFallback.unavailableProjectName
        }
    }
}

nonisolated protocol AntigravityDesktopProjectResolving: Sendable {
    func resolution(forConversation conversationID: String) -> AntigravityDesktopProjectResolution
}

/// Reads a conversation's Project from Desktop's conversation summaries and its name from the
/// Project's own file.
///
/// - `~/.gemini/antigravity/conversation_summaries.db`, table `conversation_summaries`, maps
///   `conversation_id` to `project_id`; the name is `name` in
///   `~/.gemini/config/projects/<id>.json`. Measured 2026-09-12 on 2.13.0: the row exists by the
///   first `PreInvocation` (34 ms after); no Project is an empty id or `outside-of-project`.
/// - The `status` column lags the hooks by up to a second both ways; not read. Projects are
///   matched by assignment, never by folder.
/// - WAL mode: new rows may be only in `-wal`, so a change is the main file or WAL changing.
///   With no `-wal`/`-shm` on disk a read-only open fails (measured 2026-09-12), so that case
///   uses `immutable=1`; a racing checkpoint only fails the read, keeping the previous name.
/// - Cost: a `stat` of database, WAL and Project file per row per refresh; each is re-read only
///   when changed.
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
    private var assignments: [String: (projectID: String, database: DatabaseStamp)] = [:]
    private var names: [String: (name: String, file: Stamp)] = [:]
    /// The last answer that was not `unavailable`, per conversation, for a later failed read.
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
        // The id is a file name, so it may not name anything else.
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

    /// Nil when unreadable or absent; "" means no Project.
    static func projectID(forConversation conversationID: String, inDatabaseAt path: String) -> String? {
        if let answer = projectID(forConversation: conversationID, opening: path, flags: SQLITE_OPEN_READONLY) {
            return answer
        }
        // A WAL database with no `-wal` beside it: everything committed is in the main file.
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
        // Desktop writes this file live and rows build on the main actor: wait at most a frame for the
        // lock, then answer nothing so the row keeps its last name.
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

nonisolated struct AntigravityDesktopReadRecord: Sendable, Equatable {
    /// `last_user_view_time`; nil where no view is recorded.
    let lastViewedAt: Date?
    /// `marked_as_unread`.
    let markedAsUnread: Bool
}

nonisolated protocol AntigravityDesktopReadRecordReading: Sendable {
    func record(forConversation conversationID: String) -> AntigravityDesktopReadRecord?
}

/// Reads `~/.gemini/antigravity/annotations/<conversationId>.pbtxt` (text-format protobuf):
/// `title:"…" last_user_view_time:{seconds:1789252368 nanos:120000000}`.
///
/// Desktop 2.13.0 writes the view time on leaving or entering a conversation, on window focus,
/// and on a new conversation, but not while the user watches a Turn finish; that row stays
/// until the user leaves, refocuses or submits.
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

    /// Strings are blanked before matching, so a title cannot carry a field; an unterminated string
    /// or unbalanced brace is no record.
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

    /// Nil when a string never ends.
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
