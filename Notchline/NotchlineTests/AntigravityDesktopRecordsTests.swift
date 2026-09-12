import Foundation
import SQLite3
import Testing
@testable import Notchline

/// ``AntigravityDesktopProjects`` against a summaries database and Project
/// files written the way Antigravity Desktop 2.13.0 writes them.
///
/// The table is the measured schema's two columns this reads; Desktop's other
/// columns are irrelevant to the query and are left out so that a change to
/// them cannot be mistaken for a change to what is read.
@Suite
struct AntigravityDesktopProjectsTests {
    private struct Fixture {
        let root: URL
        let database: URL
        let projects: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("agy-desktop-\(UUID().uuidString.prefix(8))", isDirectory: true)
            projects = root.appendingPathComponent("config/projects", isDirectory: true)
            try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
            database = root.appendingPathComponent("conversation_summaries.db")
            try execute("""
                CREATE TABLE `conversation_summaries` (`conversation_id` text, `title` text NOT NULL DEFAULT "",
                `project_id` text NOT NULL DEFAULT "", PRIMARY KEY (`conversation_id`));
                """)
        }

        func execute(_ sql: String) throws {
            var handle: OpaquePointer?
            guard sqlite3_open(database.path, &handle) == SQLITE_OK else {
                sqlite3_close(handle)
                throw CocoaError(.fileWriteUnknown)
            }
            defer { sqlite3_close(handle) }
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
                throw CocoaError(.fileWriteUnknown)
            }
        }

        func file(_ conversation: String, under projectID: String) throws {
            try execute("INSERT OR REPLACE INTO conversation_summaries (conversation_id, project_id) VALUES ('\(conversation)', '\(projectID)');")
        }

        func project(_ id: String, named name: String) throws {
            let data = try JSONSerialization.data(withJSONObject: ["id": id, "name": name, "settings": [:]])
            try data.write(to: projects.appendingPathComponent("\(id).json"))
        }

        func reader() -> AntigravityDesktopProjects {
            AntigravityDesktopProjects(summariesDatabase: database, projectsDirectory: projects)
        }

        func tearDown() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// The conversation's own assignment names its Project, as the sidebar
    /// draws it, and follows a rename.
    @Test
    func aConversationIsNamedByTheProjectItIsFiledUnder() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        try fixture.project("69295c15", named: "notchline")
        try fixture.file("c1", under: "69295c15")
        let reader = fixture.reader()
        #expect(reader.resolution(forConversation: "c1") == .project("notchline"))

        try fixture.project("69295c15", named: "Notchline, renamed")
        #expect(reader.resolution(forConversation: "c1") == .project("Notchline, renamed"))
    }

    /// Desktop's two spellings of "no Project" are both `Standalone`.
    @Test
    func noProjectIsStandaloneInEitherSpelling() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        try fixture.file("empty", under: "")
        try fixture.file("outside", under: "outside-of-project")
        let reader = fixture.reader()
        #expect(reader.resolution(forConversation: "empty") == .standalone)
        #expect(reader.resolution(forConversation: "outside") == .standalone)
    }

    /// Nothing that cannot be read becomes `Standalone`: a missing row, a
    /// missing database, a Project file that is gone or not JSON, and an id
    /// that would name a file somewhere else are all `unavailable`.
    @Test
    func whatCannotBeReadIsUnavailableAndNeverStandalone() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let reader = fixture.reader()
        #expect(reader.resolution(forConversation: "unlisted") == .unavailable)

        try fixture.file("orphan", under: "deleted-project")
        #expect(reader.resolution(forConversation: "orphan") == .unavailable)

        try fixture.file("corrupt", under: "broken")
        try Data("not json".utf8).write(to: fixture.projects.appendingPathComponent("broken.json"))
        #expect(reader.resolution(forConversation: "corrupt") == .unavailable)

        try fixture.file("escape", under: "../escape")
        #expect(reader.resolution(forConversation: "escape") == .unavailable)

        let missing = AntigravityDesktopProjects(
            summariesDatabase: fixture.root.appendingPathComponent("absent.db"),
            projectsDirectory: fixture.projects
        )
        #expect(missing.resolution(forConversation: "c1") == .unavailable)
    }

    /// A reading that fails after one succeeded keeps the name the row had,
    /// rather than flickering to `Project unavailable`.
    @Test
    func aFailedReadingKeepsTheLastGoodName() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        try fixture.project("p1", named: "Demo")
        try fixture.file("c1", under: "p1")
        let reader = fixture.reader()
        #expect(reader.resolution(forConversation: "c1") == .project("Demo"))

        try FileManager.default.removeItem(at: fixture.database)
        #expect(reader.resolution(forConversation: "c1") == .project("Demo"))
    }

    /// **Desktop's database is in WAL mode, and both of its states are read.**
    ///
    /// Between checkpoints there is no `-wal` beside it, and a read-only
    /// connection cannot open a WAL database it would have to create one for —
    /// the first live run failed exactly so, and every Desktop row read
    /// `Project unavailable`. While Desktop is writing, the newest rows are in
    /// the WAL alone and the main file's modification time stands still, so a
    /// cache keyed on the main file would never see a conversation filed after
    /// the first reading.
    @Test
    func aWALDatabaseIsReadBetweenCheckpointsAndWhileItIsBeingWritten() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        try fixture.execute("PRAGMA journal_mode=WAL;")
        try fixture.project("p1", named: "Demo")
        try fixture.file("c1", under: "p1")
        // Every connection has closed, so the checkpoint has emptied the WAL
        // into the main file. Desktop's engine then removes the WAL and its
        // index; the system SQLite this test writes with keeps them, empty, by
        // default, so the test removes them as Desktop would.
        try fixture.execute("PRAGMA wal_checkpoint(TRUNCATE);")
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: fixture.database.path + suffix)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.database.path + "-wal"))
        // The premise: a plain read-only connection cannot read this state.
        var plain: OpaquePointer?
        let opened = sqlite3_open_v2(fixture.database.path, &plain, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
            && sqlite3_exec(plain, "SELECT count(*) FROM conversation_summaries;", nil, nil, nil) == SQLITE_OK
        sqlite3_close_v2(plain)
        #expect(!opened, "if this reads, the state below is not the one the live run failed on")
        #expect(AntigravityDesktopProjects.projectID(forConversation: "c1", inDatabaseAt: fixture.database.path) == "p1")
        let reader = fixture.reader()
        #expect(reader.resolution(forConversation: "c1") == .project("Demo"))

        // Desktop's server holding the database open, with rows in the WAL
        // that no checkpoint has moved yet.
        var writer: OpaquePointer?
        #expect(sqlite3_open(fixture.database.path, &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        #expect(sqlite3_exec(writer, "PRAGMA wal_autocheckpoint=0;", nil, nil, nil) == SQLITE_OK)
        let mainFileBefore = try FileManager.default.attributesOfItem(atPath: fixture.database.path)[.modificationDate] as? Date
        try fixture.project("p2", named: "Second")
        #expect(sqlite3_exec(writer, "INSERT INTO conversation_summaries (conversation_id, project_id) VALUES ('c2', 'p2');", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(writer, "UPDATE conversation_summaries SET project_id = 'p2' WHERE conversation_id = 'c1';", nil, nil, nil) == SQLITE_OK)
        #expect(FileManager.default.fileExists(atPath: fixture.database.path + "-wal"))
        let mainFileAfter = try FileManager.default.attributesOfItem(atPath: fixture.database.path)[.modificationDate] as? Date
        #expect(mainFileBefore == mainFileAfter, "the rows are in the WAL alone")

        #expect(reader.resolution(forConversation: "c2") == .project("Second"))
        #expect(reader.resolution(forConversation: "c1") == .project("Second"), "a move that is only in the WAL is still a change")
    }

    /// Moving a conversation to another Project is read, because the database
    /// changed under it.
    @Test
    func aConversationMovedToAnotherProjectIsReadAgain() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        try fixture.project("p1", named: "First")
        try fixture.project("p2", named: "Second, with a longer name")
        try fixture.file("c1", under: "p1")
        let reader = fixture.reader()
        #expect(reader.resolution(forConversation: "c1") == .project("First"))

        try fixture.file("c1", under: "p2")
        #expect(reader.resolution(forConversation: "c1") == .project("Second, with a longer name"))
    }
}

/// ``AntigravityDesktopReadRecords`` against records written the way Desktop
/// 2.13.0 writes `annotations/<conversationId>.pbtxt`.
@Suite
struct AntigravityDesktopReadRecordsTests {
    /// The line Desktop wrote, measured 2026-09-12.
    @Test
    func theMeasuredRecordReadsItsViewTime() throws {
        let record = try #require(AntigravityDesktopReadRecords.parse(
            #"title:"Request To Say Hi" last_user_view_time:{seconds:1789252368 nanos:120000000}"#
        ))
        #expect(record.lastViewedAt == Date(timeIntervalSince1970: 1_789_252_368.12))
        #expect(record.markedAsUnread == false)
    }

    /// Before its title is generated a record is the view time alone, and a
    /// record Desktop has written no view into has none.
    @Test
    func aRecordWithoutATitleOrAViewIsStillARecord() throws {
        let untitled = try #require(AntigravityDesktopReadRecords.parse(
            "last_user_view_time:{seconds:1789253028 nanos:832000000}"
        ))
        #expect(untitled.lastViewedAt == Date(timeIntervalSince1970: 1_789_253_028.832))

        let unviewed = try #require(AntigravityDesktopReadRecords.parse(#"title:"Pinned" pinned:true"#))
        #expect(unviewed.lastViewedAt == nil)
    }

    /// `marked_as_unread` is read, in the text format's other spellings too.
    @Test
    func markedAsUnreadIsRead() throws {
        let record = try #require(AntigravityDesktopReadRecords.parse(
            "marked_as_unread: true\nlast_user_view_time {\n  seconds: 20\n}\n"
        ))
        #expect(record.markedAsUnread)
        #expect(record.lastViewedAt == Date(timeIntervalSince1970: 20))
    }

    /// A title is the user's words, and may say anything — including the
    /// fields this reads.
    @Test
    func aTitleCannotCarryAFieldOfItsOwn() throws {
        let record = try #require(AntigravityDesktopReadRecords.parse(
            #"title:"why does last_user_view_time:{seconds:99} marked_as_unread:true \" break" last_user_view_time:{seconds:5}"#
        ))
        #expect(record.lastViewedAt == Date(timeIntervalSince1970: 5))
        #expect(record.markedAsUnread == false)
    }

    /// Text that is not a record is no record, rather than part of one.
    @Test
    func textThatIsNotARecordIsNil() {
        #expect(AntigravityDesktopReadRecords.parse(#"title:"never closed"#) == nil)
        #expect(AntigravityDesktopReadRecords.parse("last_user_view_time:{seconds:1") == nil)
        #expect(AntigravityDesktopReadRecords.parse("last_user_view_time:{nanos:5}") == nil)
    }

    /// The file is read by the conversation's id and nothing else.
    @Test
    func theFileIsReadByConversationIDOnly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agy-annotations-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("last_user_view_time:{seconds:7}".utf8)
            .write(to: directory.appendingPathComponent("c1.pbtxt"))
        let records = AntigravityDesktopReadRecords(annotationsDirectory: directory)

        #expect(records.record(forConversation: "c1")?.lastViewedAt == Date(timeIntervalSince1970: 7))
        #expect(records.record(forConversation: "absent") == nil)
        #expect(records.record(forConversation: "../c1") == nil)
        #expect(records.record(forConversation: "") == nil)
    }
}
