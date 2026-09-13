import Foundation
import Testing
@testable import Notchline

/// Antigravity CLI through L1–L3 and independent-capability fixtures
/// (`docs/product-support.md` §6),
/// with the product's own payloads as its helper delivers them.
///
/// The payloads are the shapes measured on 2026-09-11 against `agy` 1.2.2
/// (`docs/technical-explorations/multi-product-provider-architecture/antigravity-cli.md`),
/// with the ids and paths of the fixture rather than of any conversation. The
/// process table is the fixture's too, so presence, admission and the click's
/// process come from the same reading the live scanner would make, without
/// the kernel.
@Suite(.serialized)
struct AntigravityConformanceTests {
    // MARK: - Fixtures

    /// The transcript the payload names, as the test says it reads — and a
    /// count of how many times it was asked, because the file is read on the
    /// hook delivery path and only at the events that can find something new.
    final class TranscriptStub: AntigravityTranscriptReading, @unchecked Sendable {
        private let lock = NSLock()
        private var answer: String?
        private var modelText: AntigravityModelText?
        private var paths: [String] = []

        nonisolated init(_ answer: String? = "Rename the third product's row") {
            self.answer = answer
        }

        nonisolated func holds(_ request: String?) {
            lock.lock()
            answer = request
            lock.unlock()
        }

        /// The model's newest words since the request, written in `step`.
        nonisolated func says(_ text: String, step: Int) {
            lock.lock()
            modelText = AntigravityModelText(step: step, text: text)
            lock.unlock()
        }

        nonisolated func saysNothing() {
            lock.lock()
            modelText = nil
            lock.unlock()
        }

        /// Every path asked about, in order.
        nonisolated var asked: [String] {
            lock.lock()
            defer { lock.unlock() }
            return paths
        }

        nonisolated func tail(ofTranscriptAt path: String) -> AntigravityTranscriptTail {
            lock.lock()
            defer { lock.unlock() }
            paths.append(path)
            return AntigravityTranscriptTail(latestUserRequest: answer, latestModelText: modelText)
        }
    }

    /// Edges seen on a change stream, counted rather than awaited once: the
    /// stream buffers, so an edge from starting up can already be on it.
    final class EdgeCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = 0

        nonisolated func record() {
            lock.lock()
            stored += 1
            lock.unlock()
        }

        nonisolated var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
    }

    /// What the terminal a conversation's process is attached to says, as the
    /// test says it — and how many times it was asked, because a list with no
    /// finished row in it must not pay for a reading at all.
    ///
    /// A pid it has never heard of answers `nil`, which is a conversation with
    /// no controlling terminal: the reading that keeps a row listed.
    final class GestureStub: ControllingTerminalGestureReporting, @unchecked Sendable {
        private let lock = NSLock()
        private var readings: [Int32: ControllingTerminalReading] = [:]
        private var asks = 0

        nonisolated func set(_ pid: Int32, _ reading: ControllingTerminalReading?) {
            lock.lock()
            readings[pid] = reading
            lock.unlock()
        }

        /// The user was at that terminal at `at`, with its application in
        /// front of them.
        nonisolated func wasAtTheTerminal(of pid: Int32, at date: Date) {
            set(pid, ControllingTerminalReading(
                lastGesture: date,
                hostIsInFrontOfTheUser: true,
                hostCanEverBeInFrontOfTheUser: true
            ))
        }

        nonisolated var timesAsked: Int {
            lock.lock()
            defer { lock.unlock() }
            return asks
        }

        nonisolated func reading(
            forProcessIdentifier pid: Int32
        ) async -> ControllingTerminalReading? {
            lock.lock()
            asks += 1
            let answer = readings[pid]
            lock.unlock()
            return answer
        }
    }

    /// Stands in for the machine's display and lock state.
    final class ScreenStub: ScreenAvailabilityReporting, @unchecked Sendable {
        private let lock = NSLock()
        private var stored = true

        var available: Bool {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }

        nonisolated func isAvailable() -> Bool { available }
        nonisolated func changeEvents() -> AsyncStream<Void> {
            AsyncStream { $0.finish() }
        }
    }

    /// A process table the test writes.
    private final class TableStub: ProcessTableReading, @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [ProcessEntry] = []
        private var openFiles: [Int32: [String]] = [:]

        nonisolated func set(_ processes: [(pid: Int32, path: String?, open: [String])]) {
            lock.lock()
            entries = processes.map { ProcessEntry(processIdentifier: $0.pid, executablePath: $0.path) }
            openFiles = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0.open) })
            lock.unlock()
        }

        /// The kernel's own shape: a machine with no processes on it at all is
        /// the kernel declining to answer, never an empty machine — this app is
        /// itself one of the processes it would have listed.
        nonisolated func processes(named name: String) -> [ProcessEntry]? {
            lock.lock()
            defer { lock.unlock() }
            guard !entries.isEmpty else { return nil }
            return entries.filter {
                ($0.executablePath as NSString?)?.lastPathComponent == name
            }
        }

        nonisolated func openFilePaths(ofProcess processIdentifier: Int32) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return openFiles[processIdentifier] ?? []
        }
    }

    /// Whether Antigravity Desktop is running, as the test says.
    final class DesktopStub: AntigravityDesktopLocating, @unchecked Sendable {
        private let lock = NSLock()
        private var running: HostApplication?

        nonisolated init(running: Bool = false) {
            if running { self.running = Self.application }
        }

        nonisolated static let application = HostApplication(
            bundleIdentifier: AntigravityDesktopApplication.bundleIdentifier,
            displayName: "Antigravity",
            processIdentifier: 5150
        )

        nonisolated func set(running isRunning: Bool) {
            lock.lock()
            running = isRunning ? Self.application : nil
            lock.unlock()
        }

        nonisolated func runningApplication() async -> HostApplication? {
            lock.lock()
            defer { lock.unlock() }
            return running
        }
    }

    /// Desktop's Project assignments, as the test says. Unlisted is
    /// `unavailable`.
    final class ProjectsStub: AntigravityDesktopProjectResolving, @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [String: AntigravityDesktopProjectResolution] = [:]

        nonisolated func file(_ conversation: String, _ resolution: AntigravityDesktopProjectResolution) {
            lock.lock()
            answers[conversation] = resolution
            lock.unlock()
        }

        nonisolated func resolution(forConversation conversationID: String) -> AntigravityDesktopProjectResolution {
            lock.lock()
            defer { lock.unlock() }
            return answers[conversationID] ?? .unavailable
        }
    }

    /// Desktop's read records, as the test says — and who was asked, because
    /// a CLI row must never be judged by one.
    final class RecordsStub: AntigravityDesktopReadRecordReading, @unchecked Sendable {
        private let lock = NSLock()
        private var records: [String: AntigravityDesktopReadRecord] = [:]
        private var askedAbout: [String] = []

        nonisolated func set(_ conversation: String, _ record: AntigravityDesktopReadRecord?) {
            lock.lock()
            records[conversation] = record
            lock.unlock()
        }

        nonisolated var asked: [String] {
            lock.lock()
            defer { lock.unlock() }
            return askedAbout
        }

        nonisolated func record(forConversation conversationID: String) -> AntigravityDesktopReadRecord? {
            lock.lock()
            defer { lock.unlock() }
            askedAbout.append(conversationID)
            return records[conversationID]
        }
    }

    /// The product over a root of its own, torn down with it.
    private struct Product {
        let root: URL
        let paths: HookIntegrationPaths
        let table = TableStub()
        /// The one ledger the translator writes and every source reads, as the
        /// registry composes it.
        let surfaces = AntigravitySurfaceLedger()
        let desktop = DesktopStub()
        let projects = ProjectsStub()
        let records = RecordsStub()
        let sessions: AntigravitySessions
        /// The scanner's clock, and only the scanner's: a reading has to
        /// postdate the events it retires, so it starts after `t0`. The
        /// reducer keeps the real clock, against which `t0` is long past
        /// its new-Turn reconciliation grace.
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_757_001_000))
        let scanner: AntigravityConversationScanner
        let provider: HookProductProvider
        let presenceDirectory: URL
        /// What the conversation's terminal says about the user being at it,
        /// and whether there is a screen to read it on. Nothing is set by
        /// default, which is a conversation with no controlling terminal — the
        /// reading that keeps every finished row listed.
        let gestures = GestureStub()
        let screen = ScreenStub()
        /// What the transcript the payload names is holding, as the test says
        /// it is. The file itself is read by ``AntigravityTranscriptFile``,
        /// which has a suite of its own below.
        let transcripts: TranscriptStub

        init(transcripts: TranscriptStub = TranscriptStub()) throws {
            self.transcripts = transcripts
            // Short on purpose: a Unix socket path may not exceed 104 bytes.
            root = URL(fileURLWithPath: "/tmp")
                .appendingPathComponent("agy-\(UUID().uuidString.prefix(8))")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            paths = HookIntegrationPaths(
                supportDirectory: root.appendingPathComponent("AS"),
                hooksConfiguration: root.appendingPathComponent("config/hooks.json"),
                agent: .antigravity
            )
            presenceDirectory = root.appendingPathComponent("antigravity-cli/presence", isDirectory: true)
            scanner = AntigravityConversationScanner(
                presenceDirectory: presenceDirectory,
                table: table,
                clock: clock
            )
            sessions = AntigravitySessions(cli: scanner, desktop: desktop, surfaces: surfaces)
            provider = HookProductProvider(
                agent: .antigravity,
                hooks: HookLifecycleSource(
                    paths: paths,
                    vocabulary: AntigravityHookVocabulary(transcripts: transcripts, surfaces: surfaces)
                ),
                sessions: sessions,
                rowContent: AntigravityRowContent(surfaces: surfaces, projects: projects),
                readEvidence: AntigravityReadEvidence(
                    surfaces: surfaces,
                    terminal: TerminalReadEvidence(
                        sessions: sessions,
                        gestures: gestures,
                        screen: screen
                    ),
                    desktopRecords: records
                )
            )
        }

        /// One process running `conversation`, holding its lock.
        func run(_ conversation: String, pid: Int32 = 4242) async {
            table.set([
                (pid: pid, path: "/Users/someone/.local/bin/agy",
                 open: ["/dev/null", presenceDirectory.appendingPathComponent("\(conversation).lock").path])
            ])
            // A fresh reading, not the cached one.
            await clock.advance(by: AntigravityConversationScanner.readingLifetime + 0.01)
        }

        func stopEverything() async {
            table.set([(pid: 1, path: "/sbin/launchd", open: [])])
            await clock.advance(by: AntigravityConversationScanner.readingLifetime + 0.01)
        }

        /// What the helper hands the socket: the event on one line, then the
        /// product's JSON.
        func deliver(_ event: String, _ fields: [String: Any], at date: Date) throws {
            var body = Data("\(event)\n".utf8)
            body.append(try JSONSerialization.data(withJSONObject: fields))
            provider.deliver(body, at: date)
        }

        func tearDown() async {
            await provider.disconnect()
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// Well in the past, because the reducer's new-Turn reconciliation grace
    /// is measured against the real clock.
    private let t0 = Date(timeIntervalSince1970: 1_757_000_000)
    private let conversation = "0f7d6a1c-4b7e-4e6b-9c2a-3d5f8e1a2b3c"
    private let workspace = "/Users/someone/Projects/demo"

    /// The common fields every payload carries, as the TUI sends them — or, with
    /// `antigravity` for the state directory, as Desktop does: the same fields,
    /// measured 2026-09-12 on 2.13.0, with only the directory different.
    private func common(
        _ conversation: String,
        workspaces: [String],
        stateDirectory: String = "antigravity-cli"
    ) -> [String: Any] {
        [
            "conversationId": conversation,
            "workspacePaths": workspaces,
            "transcriptPath": "/Users/someone/.gemini/\(stateDirectory)/brain/\(conversation)/.system_generated/logs/transcript_full.jsonl",
            "artifactDirectoryPath": "/Users/someone/.gemini/\(stateDirectory)/brain/\(conversation)",
            "modelName": "gemini-3.8-flash-high"
        ]
    }

    private func desktopInvocation(_ number: Int, of conversation: String) -> [String: Any] {
        common(conversation, workspaces: [workspace], stateDirectory: "antigravity")
            .merging(["invocationNum": number, "initialNumSteps": 1 + 2 * number]) { $1 }
    }

    private func desktopStop(of conversation: String) -> [String: Any] {
        common(conversation, workspaces: [workspace], stateDirectory: "antigravity")
            .merging(["executionNum": 0, "fullyIdle": true, "terminationReason": "NO_TOOL_CALL", "error": ""]) { $1 }
    }

    private func invocation(_ number: Int, of conversation: String, workspaces: [String]? = nil) -> [String: Any] {
        common(conversation, workspaces: workspaces ?? [workspace])
            .merging(["invocationNum": number, "initialNumSteps": 1 + 2 * number]) { $1 }
    }

    private func stop(of conversation: String, workspaces: [String]? = nil) -> [String: Any] {
        common(conversation, workspaces: workspaces ?? [workspace])
            .merging(["executionNum": 0, "fullyIdle": true, "terminationReason": "NO_TOOL_CALL", "error": ""]) { $1 }
    }

    // MARK: - Setup

    /// The registration is the product's own shape: this app's definitions
    /// under a named hook of its own, each lifecycle handler bare, naming the
    /// helper through `/bin/sh` with the event as its argument; the user's
    /// named hooks beside it untouched; and the helper announces the event.
    @Test
    func theRegistrationIsWrittenInTheProductsShapeBesideTheUsersOwn() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try FileManager.default.createDirectory(
            at: product.paths.hooksConfiguration.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let theirs = #"{"lint-checker":{"PostToolUse":[{"matcher":"run_command","hooks":[{"command":"./lint.sh"}]}]}}"#
        try theirs.write(to: product.paths.hooksConfiguration, atomically: true, encoding: .utf8)

        #expect(await product.provider.setupStatus() == .notInstalled)
        try await product.provider.installIntegration()
        #expect(await product.provider.setupStatus() == .active)

        let root = try #require(product.paths.readConfigurationRoot(fileManager: .default))
        #expect(root.keys.sorted() == ["lint-checker", "notchline"])
        let ours = try #require(root["notchline"] as? [String: Any])
        #expect(ours.keys.sorted() == ["PreInvocation", "Stop"])
        for event in ["PreInvocation", "Stop"] {
            let handlers = try #require(ours[event] as? [[String: Any]])
            #expect(handlers.count == 1)
            #expect(handlers[0]["command"] as? String == "/bin/sh '\(product.paths.hookHelper.path)' \(event)")
            #expect(handlers[0]["type"] as? String == "command")
            #expect(handlers[0]["hooks"] == nil, "a group under a lifecycle event disables the whole named hook")
            #expect(handlers[0]["matcher"] == nil)
        }
        #expect(root["description"] == nil, "a root key is a hook's name here")
        let helper = try String(contentsOf: product.paths.hookHelper, encoding: .utf8)
        #expect(helper.contains("{ printf '%s\\n' \"${1:-}\"; cat; } | /usr/bin/nc"))

        try await product.provider.removeIntegration()
        #expect(await product.provider.setupStatus() == .notInstalled)
        let after = try #require(product.paths.readConfigurationRoot(fileManager: .default))
        #expect(after.keys.sorted() == ["lint-checker"])
        #expect(FileManager.default.fileExists(atPath: product.paths.hooksBackup.path))
    }

    // MARK: - L1 lifecycle and L2 context

    /// A turn is its first invocation to its `Stop`: one row, `Running` from
    /// the first event with the workspace's last component for a project,
    /// unchanged by the invocations between, `Completed` on the end.
    @Test
    func aTurnIsItsFirstInvocationToItsStop() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        let started = await product.provider.fetchSnapshot()
        #expect(started.availability == .ready)
        #expect(started.presence == .open)
        let row = try #require(started.sessions.first)
        #expect(started.sessions.count == 1)
        #expect(row.agent == .antigravity)
        #expect(row.threadID == conversation)
        #expect(row.turnID.hasPrefix("local:"))
        #expect(row.status == .running)
        #expect(row.projectName == "demo")
        #expect(
            row.title == "Rename the third product's row",
            "no payload carries the prompt, so the transcript the payload names is read for it"
        )
        #expect(row.startedAt == t0)
        #expect(row.request == nil)
        #expect(started.quota == .noneReported)
        #expect(started.quota.windows.isEmpty, "no quota is read for this product")

        for number in 1...4 {
            try product.deliver("PreInvocation", invocation(number, of: conversation), at: t0.addingTimeInterval(Double(number)))
        }
        let working = await product.provider.fetchSnapshot()
        #expect(working.sessions.count == 1)
        #expect(working.sessions.first?.turnID == row.turnID)
        #expect(working.sessions.first?.startedAt == t0)
        #expect(working.sessions.first?.status == .running)

        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(9))
        let finished = await product.provider.fetchSnapshot()
        let done = try #require(finished.sessions.first)
        #expect(finished.sessions.count == 1)
        #expect(done.turnID == row.turnID)
        #expect(done.status == .completed)
        #expect(done.startedAt == t0)
        #expect(done.finishedAt == t0.addingTimeInterval(9))
    }

    /// The next turn of the same conversation starts at its own first
    /// invocation and replaces the finished row; a `Stop` that repeats
    /// changes nothing.
    @Test
    func theNextTurnReplacesTheFinishedRowAndARepeatedStopChangesNothing() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(5))
        let first = try #require(await product.provider.fetchSnapshot().sessions.first)

        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(6))
        let repeated = await product.provider.fetchSnapshot()
        #expect(repeated.sessions.count == 1)
        #expect(repeated.sessions.first?.turnID == first.turnID)
        #expect(repeated.sessions.first?.startedAt == t0)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0.addingTimeInterval(20))
        let second = await product.provider.fetchSnapshot()
        #expect(second.sessions.count == 1)
        let next = try #require(second.sessions.first)
        #expect(next.turnID != first.turnID)
        #expect(next.status == .running)
        #expect(next.startedAt == t0.addingTimeInterval(20))
        #expect(next.finishedAt == nil)
    }

    /// Launched mid-turn, the first thing seen is a later invocation: the
    /// row runs from that moment and ends on the turn's own `Stop`.
    @Test
    func aTurnSeenFromItsMiddleRunsFromThenAndEndsOnItsStop() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(3, of: conversation), at: t0)
        let seen = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(seen.status == .running)
        #expect(seen.startedAt == t0)

        try product.deliver("PreInvocation", invocation(4, of: conversation), at: t0.addingTimeInterval(1))
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(2))
        let ended = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(ended.turnID == seen.turnID)
        #expect(ended.status == .completed)
        #expect(ended.startedAt == t0)
    }

    /// A `Stop` this app never saw the start of: the next turn's first
    /// invocation is held and then redeemed on that turn's own `Stop`, so the
    /// row ends up on the new turn with the new turn's start.
    @Test
    func aLostStopIsHealedByTheNextTurnsOwnStop() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        // No Stop arrives. The next turn begins.
        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0.addingTimeInterval(30))
        let held = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(held.status == .running)
        #expect(held.startedAt == t0, "nothing said the first turn ended")

        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(40))
        let healed = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(healed.status == .completed)
        #expect(healed.startedAt == t0.addingTimeInterval(30))
        #expect(healed.turnID != held.turnID)
    }

    /// Under `-p` the product sends no workspace, and the row says so rather
    /// than guessing one.
    @Test
    func aPrintModeTurnIsAnUntitledFolder() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(0, of: conversation, workspaces: []), at: t0)
        let row = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(row.projectName == "Untitled folder")
    }

    // MARK: - The prompt, read out of the transcript the payload names

    /// The prompt is read at the turn's boundary, from the file the payload
    /// itself names, and the row is titled with it.
    @Test
    func theTitleIsTheRequestReadOutOfTheTranscriptThePayloadNames() async throws {
        let product = try Product(transcripts: TranscriptStub("Take the third product end to end"))
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        let row = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(row.title == "Take the third product end to end")
        #expect(
            product.transcripts.asked == [
                "/Users/someone/.gemini/antigravity-cli/brain/\(conversation)/.system_generated/logs/transcript_full.jsonl"
            ],
            "the file the payload named, once, and nothing searched for"
        )

        // The invocations between and the end are read for the model's words,
        // and a Turn already named keeps its name through all of them.
        product.transcripts.holds("Something the user typed later")
        for number in 1...3 {
            try product.deliver(
                "PreInvocation",
                invocation(number, of: conversation),
                at: t0.addingTimeInterval(Double(number))
            )
        }
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(8))
        let done = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(done.title == "Take the third product end to end")
        #expect(
            product.transcripts.asked.count == 5,
            "one read per event that can find something new: the boundary, three model calls, the end"
        )
    }

    /// A transcript this app reached before the product had written the user's
    /// step is read again at the turn's end, and the row is named then rather
    /// than staying `Untitled` for the life of the Turn.
    @Test
    func aTranscriptReachedTooEarlyIsReadAgainAtTheTurnsEnd() async throws {
        let product = try Product(transcripts: TranscriptStub(nil))
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        let early = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(early.title == "Untitled")

        product.transcripts.holds("Fix the row that always says Untitled")
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(6))
        let named = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(named.turnID == early.turnID, "the same Turn, named late — not a second row")
        #expect(named.title == "Fix the row that always says Untitled")
        #expect(named.status == .completed)
        #expect(product.transcripts.asked.count == 2)
    }

    /// A prompt read late may fill a blank title and may never rewrite one the
    /// Turn already carries, nor reach the Turn after it.
    @Test
    func aLatePromptFillsABlankTitleAndOverwritesNothing() async throws {
        let stub = TranscriptStub("What the first turn asked")
        let product = try Product(transcripts: stub)
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        // The user types the next thing while the first turn is still running,
        // so the file's last request is no longer this Turn's.
        stub.holds("What the user typed next")
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(4))
        let first = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(first.title == "What the first turn asked", "a named Turn keeps its name")

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0.addingTimeInterval(10))
        let second = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(second.turnID != first.turnID)
        #expect(second.title == "What the user typed next")
    }

    /// A transcript that never says what was asked leaves the row `Untitled`,
    /// which is the honest answer, and a repeated `Stop` reads nothing.
    @Test
    func aTranscriptThatSaysNothingLeavesTheRowUntitled() async throws {
        let product = try Product(transcripts: TranscriptStub(nil))
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        try product.deliver("PreInvocation", invocation(1, of: conversation), at: t0.addingTimeInterval(1))
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(5))
        // A repeated `Stop` is a late duplicate of a Turn already retired and
        // is owed no reading at all.
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(6))

        let row = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(row.title == "Untitled")
        #expect(row.preview == nil, "and a transcript with no words in it draws no line")
        #expect(
            product.transcripts.asked.count == 3,
            "the boundary, the one model call and the end, and nothing for the duplicate"
        )
    }

    // MARK: - The live line, read out of the same transcript

    /// **A running row says what the model last said**, and a finished one its
    /// closing words.
    ///
    /// No payload carries anything the model says, so until 2026-09-12 an
    /// Antigravity row had a title and a clock and no line under them for the
    /// whole of its Turn. The words are in the transcript, written whole when a
    /// model call finishes and on disk by the next `PreInvocation`; that
    /// invocation hands them over, and `Stop` carries the last of them.
    ///
    /// Three things are pinned beside the happy path. A turn that has said
    /// nothing draws no line rather than the prompt a second time. A model call
    /// that only called a tool leaves the transcript's newest words where they
    /// were, and the invocation after it must not hand the same message over
    /// again — the preview store joins two deliveries of one message into one
    /// line, which drew the sentence twice. And a repeated `Stop`, which reads
    /// nothing, must not blank the closing words the first one carried.
    @Test
    func aRunningRowSaysWhatTheModelLastSaidAndAFinishedOneItsClosingWords() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        let started = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(started.preview == nil, "nothing said yet, and the prompt is already the title")

        product.transcripts.says("I will list the files in this directory first.", step: 1)
        try product.deliver("PreInvocation", invocation(1, of: conversation), at: t0.addingTimeInterval(2))
        let first = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(first.turnID == started.turnID)
        #expect(first.status == .running)
        #expect(first.preview == "I will list the files in this directory first.")

        // The next call only called a tool, so the newest words are still step 1's.
        try product.deliver("PreInvocation", invocation(2, of: conversation), at: t0.addingTimeInterval(4))
        let quiet = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(quiet.preview == "I will list the files in this directory first.", "one message, not the same one twice")

        product.transcripts.says("Now reading notes.txt.\n\nIt is short.", step: 5)
        try product.deliver("PreInvocation", invocation(3, of: conversation), at: t0.addingTimeInterval(6))
        let second = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(second.preview == "Now reading notes.txt. It is short.", "a newer message replaces the last, on one line")

        product.transcripts.says("notes.txt holds three Greek letters, one per line.", step: 7)
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(9))
        let done = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(done.status == .completed)
        #expect(done.preview == "notes.txt holds three Greek letters, one per line.")

        let asked = product.transcripts.asked.count
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(10))
        let repeated = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(repeated.preview == "notes.txt holds three Greek letters, one per line.")
        #expect(product.transcripts.asked.count == asked)

        // The next Turn does not open on the last one's words.
        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0.addingTimeInterval(20))
        let next = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(next.turnID != done.turnID)
        #expect(next.preview == nil)
    }

    /// A Turn that ends without closing words of its own keeps the last thing
    /// it said, rather than going blank at the moment it finishes.
    @Test
    func aTurnThatEndsWithoutClosingWordsKeepsItsLastLine() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        product.transcripts.says("Running the test suite now.", step: 1)
        try product.deliver("PreInvocation", invocation(1, of: conversation), at: t0.addingTimeInterval(2))
        _ = await product.provider.fetchSnapshot()

        // The window the `Stop` reads no longer reaches the words: a tool
        // returned more than the window after them.
        product.transcripts.saysNothing()
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(5))
        let done = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(done.status == .completed)
        #expect(done.preview == "Running the test suite now.")
    }

    /// Words handed over for a listed row wake the panel, because nothing else
    /// would: an invocation between two status changes changes nothing the
    /// reducer holds, so without the edge the row keeps its old line until the
    /// turn ends.
    @Test
    func wordsHandedOverForAListedRowWakeThePanel() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        // Lists the row, which is what arms the edge.
        #expect(await product.provider.fetchSnapshot().sessions.count == 1)

        let edges = EdgeCounter()
        let observer = Task {
            for await _ in product.provider.stateChangeEvents {
                edges.record()
            }
        }
        defer { observer.cancel() }
        try await Task.sleep(nanoseconds: 300_000_000)
        let before = edges.count

        product.transcripts.says("Reading the settings window.", step: 1)
        try product.deliver("PreInvocation", invocation(1, of: conversation), at: t0.addingTimeInterval(2))
        for _ in 0 ..< 150 where edges.count == before {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(edges.count > before, "the words were collected and nothing asked for them to be drawn")
    }

    /// The IDE's event through the shared file — a transcript under
    /// `antigravity-ide/` — is nobody's row and nobody's diagnostic.
    ///
    /// Until 2026-09-12 this was pinned with a transcript under `antigravity/`,
    /// which is now Antigravity Desktop's and this product's own
    /// (``aDesktopTurnIsARowFiledUnderItsDesktopProject``).
    @Test
    func theIDEsEventIsDeclinedQuietly() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)
        product.desktop.set(running: true)

        var ide = invocation(0, of: "ide-conversation")
        ide["transcriptPath"] = "/Users/someone/.gemini/antigravity-ide/brain/ide-conversation/.system_generated/logs/transcript_full.jsonl"
        try product.deliver("PreInvocation", ide, at: t0)
        let snapshot = await product.provider.fetchSnapshot()
        #expect(snapshot.sessions.isEmpty)
        #expect(snapshot.diagnostic == nil)
    }

    /// The surface is the directory under `.gemini` the transcript names, and
    /// nothing else in the path.
    @Test
    func theSurfaceIsTheStateDirectoryTheTranscriptNames() {
        let tail = "brain/c/.system_generated/logs/transcript_full.jsonl"
        #expect(AntigravitySurface(transcriptPath: "/Users/a/.gemini/antigravity-cli/\(tail)") == .cli)
        #expect(AntigravitySurface(transcriptPath: "/Users/a/.gemini/antigravity/\(tail)") == .desktop)
        #expect(AntigravitySurface(transcriptPath: "/Users/a/.gemini/antigravity-ide/\(tail)") == nil)
        #expect(AntigravitySurface(transcriptPath: "/Users/a/.gemini/jetski/\(tail)") == nil)
        #expect(AntigravitySurface(transcriptPath: nil) == .cli, "a payload naming no transcript was always the CLI's")
        // A workspace folder of the same name decides nothing.
        #expect(AntigravitySurface(transcriptPath: "/Users/a/antigravity/.gemini/antigravity-cli/\(tail)") == .cli)
        #expect(AntigravitySurface(transcriptPath: "/Users/a/antigravity-cli/.gemini/antigravity/\(tail)") == .desktop)
    }

    // MARK: - Antigravity Desktop

    /// **A Desktop Turn is a row, through the registration the CLI already
    /// has**, filed under Desktop's own Project rather than its folder.
    ///
    /// Desktop 2.13.0 loads the same `~/.gemini/config/hooks.json` and sends
    /// the same payloads, so nothing is registered for it; what is its own is
    /// that its application being open is the product being open — no `agy`
    /// runs here at all — and that it files conversations under named Projects,
    /// one of which a folder name must not stand in for (`product-support.md`
    /// §2, L2). The title and line come from its transcript exactly as the
    /// CLI's do.
    @Test
    func aDesktopTurnIsARowFiledUnderItsDesktopProject() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.stopEverything()
        product.desktop.set(running: true)
        product.projects.file(conversation, .project("Notchline app"))

        try product.deliver("PreInvocation", desktopInvocation(0, of: conversation), at: t0)
        let running = await product.provider.fetchSnapshot()
        #expect(running.presence == .open, "Desktop running is the product open, with no agy anywhere")
        let row = try #require(running.sessions.first)
        #expect(row.status == .running)
        #expect(row.projectName == "Notchline app", "Desktop's Project, not the folder `demo`")
        #expect(row.title == "Rename the third product's row")
        #expect(product.surfaces.surface(ofConversation: conversation) == .desktop)

        product.transcripts.says("Done.", step: 1)
        try product.deliver("Stop", desktopStop(of: conversation), at: t0.addingTimeInterval(4))
        let done = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(done.status == .completed)
        #expect(done.preview == "Done.")

        // A conversation in no Project says so in Desktop's own word, and one
        // whose assignment cannot be read says that instead.
        product.projects.file(conversation, .standalone)
        #expect(try #require(await product.provider.fetchSnapshot().sessions.first).projectName == "Standalone")
        product.projects.file(conversation, .unavailable)
        #expect(
            try #require(await product.provider.fetchSnapshot().sessions.first).projectName
                == DesktopProjectMetadataSnapshot.unavailableProjectName
        )
    }

    /// Desktop vouches for its conversations while it runs, and for none once
    /// it has quit — a Turn it was running is retired rather than left saying
    /// `Working...` for an application that is gone.
    @Test
    func desktopVouchesForItsConversationsOnlyWhileItRuns() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.stopEverything()

        let closed = await product.provider.fetchSnapshot()
        #expect(closed.presence == .closed)

        product.desktop.set(running: true)
        await product.clock.advance(by: 1)
        try product.deliver("PreInvocation", desktopInvocation(0, of: conversation), at: t0)
        #expect(await product.provider.fetchSnapshot().sessions.count == 1)

        product.desktop.set(running: false)
        await product.clock.advance(by: AntigravityConversationScanner.readingLifetime + 0.01)
        let quit = await product.provider.fetchSnapshot()
        #expect(quit.presence == .closed)
        #expect(quit.sessions.isEmpty)

        product.desktop.set(running: true)
        await product.clock.advance(by: AntigravityConversationScanner.readingLifetime + 0.01)
        let back = await product.provider.fetchSnapshot()
        #expect(back.presence == .open)
        #expect(back.sessions.isEmpty, "retired, not merely hidden while the application was away")
    }

    /// A CLI conversation and a Desktop one side by side: each is open on its
    /// own surface's evidence, and neither surface's quitting takes the other's
    /// row with it.
    @Test
    func eachSurfaceVouchesOnlyForItsOwnConversations() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        let desktopConversation = "5b1e0c7a-2f44-4d8e-9a31-7c6d2e9f0a14"
        product.desktop.set(running: true)
        product.projects.file(desktopConversation, .project("Demo"))
        await product.run(conversation, pid: 4242)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        try product.deliver("PreInvocation", desktopInvocation(0, of: desktopConversation), at: t0)
        #expect(Set(await product.provider.fetchSnapshot().sessions.map(\.threadID)) == [conversation, desktopConversation])
        #expect(await product.sessions.processIdentifier(forThreadID: conversation) == 4242)
        #expect(await product.sessions.processIdentifier(forThreadID: desktopConversation) == nil)

        // The CLI exits; Desktop's row stays.
        await product.stopEverything()
        #expect(await product.provider.fetchSnapshot().sessions.map(\.threadID) == [desktopConversation])

        // Desktop quits; nothing is left, and the product is closed.
        product.desktop.set(running: false)
        let gone = await product.provider.fetchSnapshot()
        #expect(gone.sessions.isEmpty)
        #expect(gone.presence == .closed)
    }

    /// **A finished Desktop row is retired by Desktop's own record of the
    /// conversation being viewed**, and its terminal is never asked.
    ///
    /// Desktop draws its own unread dot from `last_user_view_time` against
    /// when the conversation last changed, and `marked_as_unread` overrides
    /// both; this row follows the same rule with the Turn's end as the change.
    /// A record written before the end — the one Desktop writes when the user
    /// submits — is not a reading of the answer.
    @Test
    func aFinishedDesktopRowIsRetiredByDesktopsOwnViewRecord() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.stopEverything()
        product.desktop.set(running: true)
        product.projects.file(conversation, .project("Demo"))

        try product.deliver("PreInvocation", desktopInvocation(0, of: conversation), at: t0)
        #expect(await product.provider.fetchSnapshot().sessions.count == 1)
        #expect(product.records.asked.isEmpty, "a running row pays for no reading")

        try product.deliver("Stop", desktopStop(of: conversation), at: t0.addingTimeInterval(5))
        product.records.set(conversation, AntigravityDesktopReadRecord(lastViewedAt: t0, markedAsUnread: false))
        #expect(await product.provider.fetchSnapshot().sessions.count == 1)
        #expect(await product.provider.nextRefreshDeadline() != nil, "a record can move, so it is asked again")

        product.records.set(
            conversation,
            AntigravityDesktopReadRecord(lastViewedAt: t0.addingTimeInterval(9), markedAsUnread: true)
        )
        #expect(await product.provider.fetchSnapshot().sessions.count == 1, "marked unread in Desktop stays unread")

        product.records.set(
            conversation,
            AntigravityDesktopReadRecord(lastViewedAt: t0.addingTimeInterval(9), markedAsUnread: false)
        )
        #expect(await product.provider.fetchSnapshot().sessions.isEmpty)
        #expect(product.gestures.timesAsked == 0, "no terminal is asked about a Desktop row")
    }

    /// A Desktop conversation with no record to read keeps its row and books
    /// nothing, and a CLI row beside it is judged by its terminal alone.
    @Test
    func aDesktopRowWithNoRecordKeepsItsRowAndBooksNothing() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        product.desktop.set(running: true)
        await product.stopEverything()

        try product.deliver("PreInvocation", desktopInvocation(0, of: conversation), at: t0)
        try product.deliver("Stop", desktopStop(of: conversation), at: t0.addingTimeInterval(5))
        #expect(await product.provider.fetchSnapshot().sessions.count == 1)
        #expect(await product.provider.nextRefreshDeadline() == nil)
        #expect(product.records.asked == [conversation])
    }

    // MARK: - Antigravity Desktop's navigation

    @MainActor
    private final class ActivatorSpy: HostApplicationActivating {
        private(set) var raised: [HostApplication] = []
        func activate(_ application: HostApplication) async -> Bool {
            raised.append(application)
            return true
        }
    }

    @MainActor
    private final class TerminalNavigatorSpy: AgentNavigating {
        private(set) var opened: [String] = []
        func open(_ session: MonitoredSession) async throws -> NavigationOutcome {
            opened.append(session.threadID)
            return .focusedTerminal(host: "Terminal")
        }
    }

    /// A Desktop row raises Desktop and says the conversation itself was not
    /// reached — its one deep link opens nothing else — and a CLI row goes to
    /// its terminal as before.
    @Test @MainActor
    func aDesktopRowRaisesDesktopAndACLIRowGoesToItsTerminal() async throws {
        let surfaces = AntigravitySurfaceLedger()
        surfaces.record(.desktop, forConversation: "desktop-conversation")
        let desktop = DesktopStub(running: true)
        let activator = ActivatorSpy()
        let terminal = TerminalNavigatorSpy()
        let navigator = AntigravityNavigator(
            surfaces: surfaces,
            desktop: desktop,
            terminal: terminal,
            activator: activator
        )

        func row(_ threadID: String) -> MonitoredSession {
            MonitoredSession(
                agent: .antigravity,
                threadID: threadID,
                turnID: "local:1",
                projectName: "Demo",
                title: "Untitled",
                preview: nil,
                status: .completed,
                startedAt: t0
            )
        }

        #expect(try await navigator.open(row("desktop-conversation")) == .raisedApplication(host: "Antigravity"))
        #expect(activator.raised == [DesktopStub.application])
        #expect(terminal.opened.isEmpty)

        #expect(try await navigator.open(row("cli-conversation")) == .focusedTerminal(host: "Terminal"))
        #expect(terminal.opened == ["cli-conversation"])

        desktop.set(running: false)
        await #expect(throws: ProcessHostNavigationError.sessionGone) {
            try await navigator.open(row("desktop-conversation"))
        }
    }

    /// Presence and admission are one kernel reading: the product is open
    /// while an `agy` process holds a conversation's lock, its rows are listed
    /// while it does, and the conversation is retired once no process holds
    /// the lock — a list read after the Turn last spoke.
    @Test
    func theProcessHoldingTheLockIsPresenceAdmissionAndTheClicksTarget() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()

        await product.stopEverything()
        let closed = await product.provider.fetchSnapshot()
        #expect(closed.presence == .closed)
        #expect(closed.availability == .ready)
        #expect(closed.sessions.isEmpty)

        await product.run(conversation, pid: 777)
        await product.clock.advance(by: 1)
        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        let open = await product.provider.fetchSnapshot()
        #expect(open.presence == .open)
        #expect(open.sessions.count == 1)
        #expect(await product.scanner.processIdentifier(forThreadID: conversation) == 777)
        #expect(await product.scanner.processIdentifier(forThreadID: "other") == nil)

        // The daemon and a stranger holding a lock are not the product open.
        product.table.set([
            (pid: 900, path: "/Users/someone/.local/bin/agy", open: ["/dev/null"]),
            (pid: 901, path: "/usr/bin/vim",
             open: [product.presenceDirectory.appendingPathComponent("\(conversation).lock").path])
        ])
        await product.clock.advance(by: 1)
        let gone = await product.provider.fetchSnapshot()
        #expect(gone.presence == .closed)
        #expect(gone.sessions.isEmpty)
        // And the Thread is retired, not merely hidden: the product came back
        // with a different conversation and this one stayed gone.
        await product.run("another-conversation", pid: 778)
        let back = await product.provider.fetchSnapshot()
        #expect(back.presence == .open)
        #expect(back.sessions.isEmpty)

        // A kernel that lists nothing is not evidence.
        product.table.set([])
        await product.clock.advance(by: 1)
        #expect(await product.scanner.presence() == .unknown)
        #expect(await product.scanner.admission() == .unknown)
    }

    // MARK: - Read state

    /// **A finished row is retired once the user has been at its terminal**,
    /// and not before.
    ///
    /// The default without read evidence (`docs/product-support.md` §4) leaves on the
    /// next submission, when the Thread goes away, or on a right-click — is
    /// what a product with no read evidence gets, and it left a `Completed`
    /// row standing on the notch for as long as the TUI session it belonged to
    /// stayed open, however thoroughly its answer had been read. Antigravity
    /// supplies the evidence by naming the process its conversation runs in,
    /// which it already does for presence, admission and the click.
    ///
    /// Three instants, in order: the reading is not taken at all while the row
    /// is running; a gesture from *before* the Turn ended is not evidence it
    /// was read; one after it is, and the row goes.
    @Test
    func aFinishedRowIsRetiredOnceTheUserHasBeenAtItsTerminal() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation, pid: 4242)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        let running = await product.provider.fetchSnapshot()
        #expect(running.sessions.count == 1)
        #expect(
            product.gestures.timesAsked == 0,
            "a list with no finished row in it pays for no reading"
        )
        #expect(
            await product.provider.nextRefreshDeadline() == nil,
            "and books no re-check"
        )

        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(5))
        product.gestures.wasAtTheTerminal(of: 4242, at: t0.addingTimeInterval(1))
        let unread = await product.provider.fetchSnapshot()
        #expect(unread.sessions.count == 1)
        #expect(unread.sessions.first?.status == .completed)
        #expect(product.gestures.timesAsked == 1, "one reading per finished row per refresh")
        let deadline = try #require(await product.provider.nextRefreshDeadline())
        // An access time moves in the kernel with nothing to watch it, so a row
        // waiting on one is looked at again a second later.
        #expect(deadline <= Date().addingTimeInterval(1.5))

        product.gestures.wasAtTheTerminal(of: 4242, at: t0.addingTimeInterval(6))
        #expect(await product.provider.fetchSnapshot().sessions.isEmpty)
        #expect(
            await product.provider.nextRefreshDeadline() == nil,
            "a row that has left is waiting for nothing"
        )

        // Retiring the row is not retiring the conversation: the next turn
        // draws its own, and a stale gesture cannot retire that one.
        try product.deliver(
            "PreInvocation",
            invocation(0, of: conversation),
            at: t0.addingTimeInterval(30)
        )
        let next = await product.provider.fetchSnapshot()
        #expect(next.sessions.count == 1)
        #expect(next.sessions.first?.status == .running)
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(40))
        #expect(await product.provider.fetchSnapshot().sessions.count == 1)
    }

    /// A gesture at a terminal nobody was in front of is not a reading.
    ///
    /// The pairing ``ControllingTerminalGestureReporting`` documents, kept here
    /// rather than assumed: the access time is one scalar, and this product
    /// asks its terminal for neither focus reports nor mouse reports (measured
    /// 2026-09-12: the TUI writes `?1049h`, `?25l` and `?2004h` and nothing
    /// else), so the bytes behind a gesture are a keystroke or a paste. That
    /// makes the front narrower than it is for Claude Code and no less
    /// required — a row is retired on somebody being *there*.
    @Test
    func aGestureAtATerminalNobodyWasInFrontOfIsNotAReading() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation, pid: 4242)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(5))
        product.gestures.set(4242, ControllingTerminalReading(
            lastGesture: t0.addingTimeInterval(9),
            hostIsInFrontOfTheUser: false,
            hostCanEverBeInFrontOfTheUser: true
        ))
        #expect(await product.provider.fetchSnapshot().sessions.count == 1)
        #expect(
            await product.provider.nextRefreshDeadline() != nil,
            "a terminal nobody is in front of is a question worth asking again"
        )
    }

    /// A conversation nothing can ever speak for keeps its row and books
    /// nothing.
    ///
    /// Two shapes of it, and the distinction is the one CR-Fable-036 was:
    /// `nil` is a conversation with no controlling terminal at all — a `-p` run
    /// with its output piped — and a reading whose host can never hold the
    /// front is one under `tmux`, `screen` or `ssh`, whose ancestry reaches
    /// `launchd` without passing an application. Both are questions with no
    /// possible answer, so neither may be re-asked once a second for the life
    /// of the session.
    @Test
    func aConversationNothingCanSpeakForKeepsItsRowAndBooksNothing() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation, pid: 4242)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(5))
        #expect(await product.provider.fetchSnapshot().sessions.count == 1)
        #expect(await product.provider.nextRefreshDeadline() == nil)

        product.gestures.set(4242, ControllingTerminalReading(
            lastGesture: t0.addingTimeInterval(9),
            hostIsInFrontOfTheUser: false,
            hostCanEverBeInFrontOfTheUser: false
        ))
        #expect(await product.provider.fetchSnapshot().sessions.count == 1)
        #expect(await product.provider.nextRefreshDeadline() == nil)
    }

    /// A row the user has waved away is judged by nobody, and still reported.
    ///
    /// Both halves matter. The reading is not taken, because a row that has
    /// already left the list at the user's asking cannot be improved on by one
    /// and an entry in the gate books a re-check a second either way
    /// (CR-Fable-003). And the row is still listed, because what this product
    /// reports is what it knows about: a Provider that stopped listing the Turn
    /// would be telling the store the Turn had ended, which is the one thing
    /// that makes it forget the removal (CR-Fable-004).
    @Test
    func aRowTheUserHasWavedAwayIsJudgedByNobody() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation, pid: 4242)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(5))
        product.gestures.wasAtTheTerminal(of: 4242, at: t0.addingTimeInterval(1))
        let row = try #require(await product.provider.fetchSnapshot().sessions.first)
        let asked = product.gestures.timesAsked

        let dismissed = await product.provider.fetchSnapshot(dismissedRowIDs: [row.id])
        #expect(dismissed.sessions.count == 1)
        #expect(dismissed.sessions.first?.id == row.id)
        #expect(product.gestures.timesAsked == asked)
        #expect(await product.provider.nextRefreshDeadline() == nil)
    }

    /// A row waiting to be read waits on the screen coming back, not on a
    /// re-check nobody could act on.
    ///
    /// Every route that could retire this row needs a screen somebody can see,
    /// so through a sleeping display or a locked screen the answer is knowably
    /// "no" before the work is done and the sample is not a sample of anything
    /// (CR-Fable-018). The row is not abandoned: the same evidence carries the
    /// edge for the screen coming back, and it is merged into this Provider's
    /// change events.
    @Test
    func anUnreadRowWaitsOnTheScreenComingBackRatherThanOnAReCheck() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation, pid: 4242)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(5))
        product.gestures.wasAtTheTerminal(of: 4242, at: t0.addingTimeInterval(1))
        #expect(await product.provider.fetchSnapshot().sessions.count == 1)
        #expect(await product.provider.nextRefreshDeadline() != nil)

        product.screen.available = false
        #expect(await product.provider.nextRefreshDeadline() == nil)
        product.screen.available = true
        #expect(await product.provider.nextRefreshDeadline() != nil)
    }

    /// The scanner answers from one reading for the two questions the refresh
    /// asks and the third a click asks, and reads again once it has aged.
    @Test
    func oneReadingAnswersUntilItAges() async throws {
        let table = TableStub()
        let clock = TestClock()
        let directory = URL(fileURLWithPath: "/tmp/agy-scan-\(UUID().uuidString.prefix(8))/presence")
        let scanner = AntigravityConversationScanner(presenceDirectory: directory, table: table, clock: clock)
        table.set([(pid: 5, path: "/opt/agy", open: [directory.appendingPathComponent("c1.lock").path])])
        #expect(await scanner.presence() == .open)
        table.set([(pid: 1, path: "/sbin/launchd", open: [])])
        #expect(await scanner.presence() == .open, "the reading is younger than its lifetime")
        await clock.advance(by: AntigravityConversationScanner.readingLifetime)
        #expect(await scanner.presence() == .closed)
    }

    // MARK: - Registry and Settings

    /// **The footer names the product and claims nothing about it.**
    ///
    /// An outer row and no inner ones, which is `quota-footer-v2.md` §5's form
    /// for a connected product this app reads no quota for. The store's side
    /// of that rule was written and tested with a hand-built snapshot; this
    /// product is the first to produce one, and until 2026-09-11 it produced
    /// ``QuotaSnapshot/unavailable`` instead — the *single-window* form — so a
    /// live Antigravity drew one `-- left` line under its name on every
    /// render, for ever, saying a reading had not come back for a window that
    /// does not exist. Found by running a turn through the built app.
    @Test @MainActor
    func theFooterNamesTheProductAndClaimsNothingAboutIt() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)
        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)

        let store = MonitorStore(services: [])
        // A fresh store carries the preview's own Codex answer; a closed one
        // takes it back out, so the footer below is this product's alone.
        for agent in [AgentKind.codex, .claudeCode] {
            store.applyForTesting(
                AgentSnapshot(
                    agent: agent,
                    availability: .ready,
                    sessions: [],
                    quota: .unavailable,
                    diagnostic: nil,
                    presence: .closed
                )
            )
        }
        store.applyForTesting(await product.provider.fetchSnapshot())

        #expect(store.footerRules.map(\.agent) == [.antigravity])
        let rule = try #require(store.footerRules.first)
        #expect(rule.windows.isEmpty, "no line of dashes under a product with no windows")
        #expect(rule.today.text == "-- today")
    }

    /// The product is one descriptor: its file, its two definitions, no trust
    /// step, and the unsupported capabilities Settings declares for this L3 product.
    @Test
    func theDescriptorSaysWhatTheProductIsAndIsNot() {
        let descriptor = ProductRegistry.descriptor(for: .antigravity)
        #expect(descriptor.settingsTitle == "Antigravity", "one switch, because Desktop and the CLI read one file")
        #expect(descriptor.displayName == "Antigravity")
        #expect(descriptor.setup.managedHooks!.displayPath == "~/.gemini/config/hooks.json")
        #expect(descriptor.setup.managedHooks!.definitionCount == 2)
        #expect(descriptor.setup.managedHooks!.trustStep == nil)
        #expect(descriptor.setup.managedHooks!.backupName == "hooks.json.notchline-backup")
        #expect(descriptor.setup.managedHooks!.switchHelp.contains("2 lifecycle definitions in ~/.gemini/config/hooks.json"))
        #expect(descriptor.declaredBoundary?.contains("Antigravity Desktop and Antigravity CLI") == true)
        #expect(descriptor.declaredBoundary?.contains("Approvals and questions are not detected") == true)
        #expect(descriptor.declaredBoundary?.contains("stopped before it finished") == true)
        #expect(descriptor.declaredBoundary?.contains("Usage quota is not supported") == true)
        #expect(ProductRegistry.descriptor(for: .codex).declaredBoundary == nil)
        #expect(ProductRegistry.descriptor(for: .claudeCode).declaredBoundary == nil)
        #expect(ProductRegistry.spokenNames == "Codex, Claude Code and Antigravity")
        #expect(HookIntegrationPaths.live(for: .antigravity).hooksConfiguration.path.hasSuffix("/.gemini/config/hooks.json"))
        #expect(HookIntegrationPaths.live(for: .antigravity).hookSocket.path.utf8.count < 104)
    }
}

/// ``AntigravityTranscriptFile`` against transcripts written the way `agy`
/// 1.2.2 writes them — the shapes measured 2026-09-12 on this machine, with
/// the requests of the fixture rather than of any conversation.
@Suite
struct AntigravityTranscriptFileTests {
    private let reader = AntigravityTranscriptFile()

    /// One step as the product appends it, with the envelope it wraps a
    /// request in and the metadata it appends after it.
    private func userStep(_ index: Int, request: String) -> [String: Any] {
        [
            "step_index": index,
            "source": "USER_EXPLICIT",
            "type": "USER_INPUT",
            "status": "DONE",
            "created_at": "2026-09-12T07:24:42Z",
            "content": "<USER_REQUEST>\n\(request)\n</USER_REQUEST>\n"
                + "<ADDITIONAL_METADATA>\nThe current local time is: 2026-09-12T00:24:42-07:00.\n"
                + "</ADDITIONAL_METADATA>"
        ]
    }

    private func write(_ steps: [[String: Any]]) throws -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agy-transcript-\(UUID().uuidString.prefix(8)).jsonl")
        var body = Data()
        for step in steps {
            body.append(try JSONSerialization.data(withJSONObject: step))
            body.append(0x0A)
        }
        try body.write(to: url)
        return url.path
    }

    /// The request comes out of its envelope, without the metadata the product
    /// appends for its own model.
    @Test
    func theRequestComesOutOfItsEnvelopeWithoutTheMetadata() throws {
        let path = try write([userStep(0, request: "List the files in the current directory, then say done.")])
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(
            reader.tail(ofTranscriptAt: path).latestUserRequest
                == "List the files in the current directory, then say done."
        )
    }

    /// A conversation's later turns append their own steps, and the last
    /// request is the one a row is named for.
    @Test
    func theLastRequestInTheFileIsTheOneRead() throws {
        let path = try write([
            userStep(0, request: "Read README.txt, then reply with exactly the word done."),
            [
                "step_index": 1, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
                "created_at": "2026-09-12T07:24:45Z",
                "tool_calls": [["name": "view_file", "args": ["toolAction": "Reading README.txt"]]]
            ],
            userStep(2, request: "Reply with exactly the word two.")
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(reader.tail(ofTranscriptAt: path).latestUserRequest == "Reply with exactly the word two.")
    }

    /// One model response as the product appends it: the words the user sees
    /// in `content`, reasoning beside them, and the tool it went on to call.
    private func modelStep(_ index: Int, says content: String, calls tool: String? = nil) -> [String: Any] {
        var step: [String: Any] = [
            "step_index": index,
            "source": "MODEL",
            "type": "PLANNER_RESPONSE",
            "status": "DONE",
            "created_at": "2026-09-12T19:48:52Z",
            "content": content,
            "thinking": "**Planning the listing**\n\nThe reasoning, which a row never shows."
        ]
        if let tool {
            step["tool_calls"] = [["name": tool, "args": ["toolAction": "Running \(tool)"]]]
        }
        return step
    }

    /// The newest words since the request are read, a call that only called a
    /// tool is passed over, and neither the tool's output, the product's own
    /// message nor the model's reasoning is taken for them.
    @Test
    func theModelsNewestWordsAreItsLastResponseThatSaidAnything() throws {
        let path = try write([
            userStep(0, request: "Run sleep 12, then tell me it finished."),
            modelStep(1, says: "I will execute the command for you right away.", calls: "run_command"),
            [
                "step_index": 2, "source": "MODEL", "type": "GENERIC", "status": "DONE",
                "content": "Created At: 2026-09-12T12:48:55-07:00\nfinished"
            ],
            modelStep(3, says: "", calls: "command_status"),
            [
                "step_index": 4, "source": "SYSTEM", "type": "SYSTEM_MESSAGE", "status": "DONE",
                "content": "The following is a <SYSTEM_MESSAGE> not actually sent by the user."
            ]
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let tail = reader.tail(ofTranscriptAt: path)
        #expect(tail.latestModelText == AntigravityModelText(step: 1, text: "I will execute the command for you right away."))
        #expect(tail.latestUserRequest == "Run sleep 12, then tell me it finished.", "and one read answers both")
    }

    /// The walk back stops at the user's step: what the model said before it
    /// was said to an earlier turn, and a turn that has just been asked has
    /// said nothing yet.
    @Test
    func wordsFromBeforeTheLatestRequestAreNotThisTurns() throws {
        let path = try write([
            userStep(0, request: "Reply with exactly the word one."),
            modelStep(1, says: "one"),
            userStep(2, request: "Reply with exactly the word two.")
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let tail = reader.tail(ofTranscriptAt: path)
        #expect(tail.latestModelText == nil)
        #expect(tail.latestUserRequest == "Reply with exactly the word two.")

        // And a step with no index cannot be told from the next one, so it is
        // not handed over as a message at all.
        var unnumbered = modelStep(3, says: "two")
        unnumbered.removeValue(forKey: "step_index")
        let withoutIndex = try write([userStep(0, request: "Reply with exactly the word two."), unnumbered])
        defer { try? FileManager.default.removeItem(atPath: withoutIndex) }
        #expect(reader.tail(ofTranscriptAt: withoutIndex).latestModelText == nil)
    }

    /// The product's own message to its model is not a request, however much
    /// its first sentence reads like one.
    @Test
    func aSystemMessageIsNotAUserRequest() throws {
        let path = try write([
            userStep(0, request: "Wait ten seconds, then fetch a page."),
            [
                "step_index": 1, "source": "SYSTEM", "type": "SYSTEM_MESSAGE", "status": "DONE",
                "created_at": "2026-09-12T07:24:59Z",
                "content": "The following is a <SYSTEM_MESSAGE> not actually sent by the user. "
                    + "<SYSTEM_MESSAGE>\n<USER_REQUEST>\nten seconds elapsed\n</USER_REQUEST>\n</SYSTEM_MESSAGE>"
            ]
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(reader.tail(ofTranscriptAt: path).latestUserRequest == "Wait ten seconds, then fetch a page.")
    }

    /// A file that is not there, is empty, or holds no request at all is
    /// nothing to draw — never an empty title and never a crash.
    @Test
    func nothingReadableIsNoRequest() throws {
        #expect(reader.tail(ofTranscriptAt: "/nonexistent/transcript_full.jsonl").latestUserRequest == nil)

        let empty = try write([])
        defer { try? FileManager.default.removeItem(atPath: empty) }
        #expect(reader.tail(ofTranscriptAt: empty).latestUserRequest == nil)

        let modelOnly = try write([
            ["step_index": 0, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE", "content": "hello"]
        ])
        defer { try? FileManager.default.removeItem(atPath: modelOnly) }
        #expect(reader.tail(ofTranscriptAt: modelOnly).latestUserRequest == nil)

        // A step whose content carries no envelope is skipped rather than
        // drawn whole: the envelope is what says which part is the user's.
        let unwrapped = try write([
            [
                "step_index": 0, "source": "USER_EXPLICIT", "type": "USER_INPUT", "status": "DONE",
                "content": "The current local time is: 2026-09-12T00:24:42-07:00."
            ]
        ])
        defer { try? FileManager.default.removeItem(atPath: unwrapped) }
        #expect(reader.tail(ofTranscriptAt: unwrapped).latestUserRequest == nil)
    }

    /// Only the tail is read, and the half-line the window opens on is not
    /// mistaken for a step. A request past the window is not found, which is
    /// the bound working rather than failing.
    @Test
    func onlyTheTailIsRead() throws {
        let filler = String(repeating: "x", count: 4_000)
        var steps: [[String: Any]] = [userStep(0, request: "The first thing asked, long ago")]
        for index in 1...100 {
            steps.append([
                "step_index": index, "source": "MODEL", "type": "GENERIC", "status": "DONE",
                "content": filler
            ])
        }
        let farBack = try write(steps)
        defer { try? FileManager.default.removeItem(atPath: farBack) }
        let size = try FileManager.default.attributesOfItem(atPath: farBack)[.size] as? Int
        #expect((size ?? 0) > AntigravityTranscriptFile.tailBytes, "the fixture has to exceed the window")
        #expect(reader.tail(ofTranscriptAt: farBack).latestUserRequest == nil)

        // The same file with a request inside the window is found, so the nil
        // above is the bound and not a parse failure.
        steps.append(userStep(101, request: "The thing asked just now"))
        let inWindow = try write(steps)
        defer { try? FileManager.default.removeItem(atPath: inWindow) }
        #expect(reader.tail(ofTranscriptAt: inWindow).latestUserRequest == "The thing asked just now")
    }
}
