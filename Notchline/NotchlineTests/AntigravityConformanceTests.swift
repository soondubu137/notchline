import Foundation
import Testing
@testable import Notchline

/// Antigravity CLI through L1–L3 and independent-capability fixtures
/// (`docs/product-support.md` §6), with payloads measured 2026-09-11 against `agy` 1.2.2
/// (`docs/technical-explorations/multi-product-provider-architecture/antigravity-cli.md`) and a
/// fixture process table.
@Suite(.serialized)
struct AntigravityConformanceTests {
    // MARK: - Fixtures

    /// Counts reads: the file is read on the hook delivery path, only at events that can find
    /// something new.
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

    /// Counted rather than awaited once: the stream buffers, so a startup edge may already be on it.
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

    /// Counts reads: a list with no finished row must not pay for one. An unknown pid answers `nil`
    /// (no controlling terminal), which keeps a row listed.
    final class GestureStub: ControllingTerminalGestureReporting, @unchecked Sendable {
        private let lock = NSLock()
        private var readings: [Int32: ControllingTerminalReading] = [:]
        private var asks = 0

        nonisolated func set(_ pid: Int32, _ reading: ControllingTerminalReading?) {
            lock.lock()
            readings[pid] = reading
            lock.unlock()
        }

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

        /// No processes at all is the kernel declining to answer; this app is itself a process.
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

    /// Unlisted is `unavailable`.
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

    /// Records who was asked: a CLI row must never be judged by Desktop's records.
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

    private struct Product {
        let root: URL
        let paths: HookIntegrationPaths
        let table = TableStub()
        let surfaces = AntigravitySurfaceLedger()
        let desktop = DesktopStub()
        let projects = ProjectsStub()
        let records = RecordsStub()
        let sessions: AntigravitySessions
        /// The scanner's clock only: a reading must postdate the events it retires, so it starts after
        /// `t0`. The reducer keeps the real clock.
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_757_001_000))
        let scanner: AntigravityConversationScanner
        let provider: HookProductProvider
        let presenceDirectory: URL
        /// Unset by default: no controlling terminal, which keeps every finished row listed.
        let gestures = GestureStub()
        let screen = ScreenStub()
        /// The file itself is read by ``AntigravityTranscriptFile``, tested separately.
        let transcripts: TranscriptStub

        init(transcripts: TranscriptStub = TranscriptStub()) throws {
            self.transcripts = transcripts
            // A Unix socket path may not exceed 104 bytes.
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

        func run(_ conversation: String, pid: Int32 = 4242) async {
            table.set([
                (pid: pid, path: "/Users/someone/.local/bin/agy",
                 open: ["/dev/null", presenceDirectory.appendingPathComponent("\(conversation).lock").path])
            ])
            await clock.advance(by: AntigravityConversationScanner.readingLifetime + 0.01)
        }

        func stopEverything() async {
            table.set([(pid: 1, path: "/sbin/launchd", open: [])])
            await clock.advance(by: AntigravityConversationScanner.readingLifetime + 0.01)
        }

        /// The helper's framing: the event on one line, then the product's JSON.
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

    /// In the past: the reducer's new-Turn reconciliation grace uses the real clock.
    private let t0 = Date(timeIntervalSince1970: 1_757_000_000)
    private let conversation = "0f7d6a1c-4b7e-4e6b-9c2a-3d5f8e1a2b3c"
    private let workspace = "/Users/someone/Projects/demo"

    /// The common fields as the TUI sends them, or with `antigravity` as the state directory, as
    /// Desktop does (measured 2026-09-12 on 2.13.0).
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

    /// This app's definitions under its own named hook, each lifecycle handler bare and running the
    /// helper through `/bin/sh` with the event as argument; the user's named hooks untouched.
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

    /// One row, `Running` from the first event with the workspace's last component as project,
    /// `Completed` on `Stop`.
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

    /// The next turn's first invocation is held and redeemed on its own `Stop`, so the row ends up
    /// on the new turn with its start.
    @Test
    func aLostStopIsHealedByTheNextTurnsOwnStop() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
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

    /// Under `-p` the product sends no workspace.
    @Test
    func aPrintModeTurnIsAnUntitledProject() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(0, of: conversation, workspaces: []), at: t0)
        let row = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(row.projectName == RowContentFallback.projectName)
    }

    // MARK: - The prompt, read out of the transcript the payload names

    /// Read at the turn's boundary, from the file the payload names.
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

    /// A transcript read before the user's step was written is read again at the turn's end.
    @Test
    func aTranscriptReachedTooEarlyIsReadAgainAtTheTurnsEnd() async throws {
        let product = try Product(transcripts: TranscriptStub(nil))
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        let early = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(early.title == RowContentFallback.title)

        product.transcripts.holds("Fix the row that always says Untitled")
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(6))
        let named = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(named.turnID == early.turnID, "the same Turn, named late — not a second row")
        #expect(named.title == "Fix the row that always says Untitled")
        #expect(named.status == .completed)
        #expect(product.transcripts.asked.count == 2)
    }

    @Test
    func aLatePromptFillsABlankTitleAndOverwritesNothing() async throws {
        let stub = TranscriptStub("What the first turn asked")
        let product = try Product(transcripts: stub)
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        // The user types next while the turn runs, so the file's last request is not this Turn's.
        stub.holds("What the user typed next")
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(4))
        let first = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(first.title == "What the first turn asked", "a named Turn keeps its name")

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0.addingTimeInterval(10))
        let second = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(second.turnID != first.turnID)
        #expect(second.title == "What the user typed next")
    }

    @Test
    func aTranscriptThatSaysNothingLeavesTheRowUntitled() async throws {
        let product = try Product(transcripts: TranscriptStub(nil))
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        try product.deliver("PreInvocation", invocation(1, of: conversation), at: t0.addingTimeInterval(1))
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(5))
        // A repeated `Stop` is a late duplicate of a retired Turn and is owed no reading.
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(6))

        let row = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(row.title == RowContentFallback.title)
        #expect(row.preview == nil, "a transcript with no words in it leaves the model's own preview nil; the row's fallback line is drawn from that, not stored in it")
        #expect(
            product.transcripts.asked.count == 3,
            "the boundary, the one model call and the end, and nothing for the duplicate"
        )
    }

    // MARK: - The live line, read out of the same transcript

    /// No payload carries the model's words; they are in the transcript by the next
    /// `PreInvocation`, and `Stop` carries the last of them.
    ///
    /// Also pinned: a turn that said nothing draws no line (not the prompt again); a tool-only call
    /// must not hand the same message over again (the preview store joins deliveries, drawing it
    /// twice); a repeated `Stop` must not blank the closing words.
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

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0.addingTimeInterval(20))
        let next = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(next.turnID != done.turnID)
        #expect(next.preview == nil)
    }

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

        // A tool returned more than the `Stop`'s read window after the words.
        product.transcripts.saysNothing()
        try product.deliver("Stop", stop(of: conversation), at: t0.addingTimeInterval(5))
        let done = try #require(await product.provider.fetchSnapshot().sessions.first)
        #expect(done.status == .completed)
        #expect(done.preview == "Running the test suite now.")
    }

    /// An invocation between status changes changes nothing the reducer holds, so without this
    /// edge the row keeps its old line until the turn ends.
    @Test
    func wordsHandedOverForAListedRowWakeThePanel() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)
        // Listing the row arms the edge.
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

    /// A transcript under `antigravity-ide/` is nobody's row and nobody's diagnostic.
    /// (`antigravity/` is Desktop's: ``aDesktopTurnIsARowFiledUnderItsDesktopProject``.)
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

    @Test
    func theSurfaceIsTheStateDirectoryTheTranscriptNames() {
        let tail = "brain/c/.system_generated/logs/transcript_full.jsonl"
        #expect(AntigravitySurface(transcriptPath: "/Users/a/.gemini/antigravity-cli/\(tail)") == .cli)
        #expect(AntigravitySurface(transcriptPath: "/Users/a/.gemini/antigravity/\(tail)") == .desktop)
        #expect(AntigravitySurface(transcriptPath: "/Users/a/.gemini/antigravity-ide/\(tail)") == nil)
        #expect(AntigravitySurface(transcriptPath: "/Users/a/.gemini/jetski/\(tail)") == nil)
        #expect(AntigravitySurface(transcriptPath: nil) == .cli, "a payload naming no transcript was always the CLI's")
        #expect(AntigravitySurface(transcriptPath: "/Users/a/antigravity/.gemini/antigravity-cli/\(tail)") == .cli)
        #expect(AntigravitySurface(transcriptPath: "/Users/a/antigravity-cli/.gemini/antigravity/\(tail)") == .desktop)
    }

    // MARK: - Antigravity Desktop

    /// Desktop 2.13.0 loads the same `~/.gemini/config/hooks.json` and payloads. Its app being open
    /// is presence (no `agy` runs), and it files under named Projects a folder name must not stand
    /// in for (`product-support.md` §2, L2).
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

        // No Project reads ``RowContentFallback/projectName``, not Desktop's `Standalone`.
        product.projects.file(conversation, .standalone)
        #expect(try #require(await product.provider.fetchSnapshot().sessions.first).projectName == RowContentFallback.projectName)
        product.projects.file(conversation, .unavailable)
        #expect(
            try #require(await product.provider.fetchSnapshot().sessions.first).projectName
                == DesktopProjectMetadataSnapshot.unavailableProjectName
        )
    }

    /// Once Desktop quits, a Turn it was running is retired rather than left `Working...`.
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

        await product.stopEverything()
        #expect(await product.provider.fetchSnapshot().sessions.map(\.threadID) == [desktopConversation])

        product.desktop.set(running: false)
        let gone = await product.provider.fetchSnapshot()
        #expect(gone.sessions.isEmpty)
        #expect(gone.presence == .closed)
    }

    /// Desktop's unread dot compares `last_user_view_time` with the last change, and
    /// `marked_as_unread` overrides both; here the Turn's end is the change. A record written
    /// before the end (on submit) is not a reading. The terminal is never asked.
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

    /// Desktop's one deep link opens nothing else, so its row says the conversation was not reached.
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
                title: RowContentFallback.title,
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

    /// The product is open while an `agy` process holds a conversation's lock; the conversation is
    /// retired once no process holds it.
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

        product.table.set([
            (pid: 900, path: "/Users/someone/.local/bin/agy", open: ["/dev/null"]),
            (pid: 901, path: "/usr/bin/vim",
             open: [product.presenceDirectory.appendingPathComponent("\(conversation).lock").path])
        ])
        await product.clock.advance(by: 1)
        let gone = await product.provider.fetchSnapshot()
        #expect(gone.presence == .closed)
        #expect(gone.sessions.isEmpty)
        // Retired, not hidden: it stays gone when the product returns with another conversation.
        await product.run("another-conversation", pid: 778)
        let back = await product.provider.fetchSnapshot()
        #expect(back.presence == .open)
        #expect(back.sessions.isEmpty)

        product.table.set([])
        await product.clock.advance(by: 1)
        #expect(await product.scanner.presence() == .unknown)
        #expect(await product.scanner.admission() == .unknown)
    }

    // MARK: - Read state

    /// Without read evidence (`docs/product-support.md` §4) a `Completed` row stayed while the TUI
    /// session was open. Order pinned: no reading while running; a gesture before the Turn ended
    /// is not evidence; one after it retires the row.
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
        // An access time changes with nothing to watch it, so a waiting row is re-checked a second later.
        #expect(deadline <= Date().addingTimeInterval(1.5))

        product.gestures.wasAtTheTerminal(of: 4242, at: t0.addingTimeInterval(6))
        #expect(await product.provider.fetchSnapshot().sessions.isEmpty)
        #expect(
            await product.provider.nextRefreshDeadline() == nil,
            "a row that has left is waiting for nothing"
        )

        // Retiring the row is not retiring the conversation; a stale gesture cannot retire the next.
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

    /// See ``ControllingTerminalGestureReporting``. This TUI requests no focus or mouse reports
    /// (measured 2026-09-12: only `?1049h`, `?25l`, `?2004h`), so a gesture is a keystroke or paste.
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

    /// Two shapes (CR-Fable-036): `nil`, no controlling terminal (a piped `-p` run); and a host that
    /// can never hold the front (`tmux`, `screen`, `ssh`). Neither may be re-asked every second.
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

    /// Not read, since gate entries book a re-check a second (CR-Fable-003); still listed, since
    /// dropping the Turn would make the store forget the removal (CR-Fable-004).
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

    /// With a sleeping display or locked screen nothing can retire the row (CR-Fable-018); the
    /// screen-back edge is merged into this Provider's change events.
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

    /// One reading answers the refresh's two questions and a click's, until it ages.
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

    /// An outer row and no inner ones: `quota-footer-v2.md` §5's form for a product with no quota
    /// reading. ``QuotaSnapshot/unavailable`` is the single-window form and drew a false `-- left`.
    @Test @MainActor
    func theFooterNamesTheProductAndClaimsNothingAboutIt() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)
        try product.deliver("PreInvocation", invocation(0, of: conversation), at: t0)

        let store = MonitorStore(services: [])
        // A fresh store carries the preview's Codex answer; closing both leaves this product's footer.
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
        #expect(descriptor.watches == "Antigravity Desktop and Antigravity CLI.")
        #expect(descriptor.notShown?.hasPrefix("Approvals and questions.") == true)
        #expect(descriptor.notShown?.contains("stopped early may keep reading it") == true)
        #expect(descriptor.notShown?.contains("Usage quota") == true)
        for kind in [AgentKind.codex, .claudeCode] {
            #expect(ProductRegistry.descriptor(for: kind).watches == nil)
            #expect(ProductRegistry.descriptor(for: kind).notShown == nil)
        }
        #expect(ProductRegistry.spokenNames == "Codex, Claude Code, Antigravity and Trae")
        #expect(HookIntegrationPaths.live(for: .antigravity).hooksConfiguration.path.hasSuffix("/.gemini/config/hooks.json"))
        #expect(HookIntegrationPaths.live(for: .antigravity).hookSocket.path.utf8.count < 104)
    }
}

/// ``AntigravityTranscriptFile`` against transcripts as `agy` 1.2.2 writes them (measured
/// 2026-09-12).
@Suite
struct AntigravityTranscriptFileTests {
    private let reader = AntigravityTranscriptFile()

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

    @Test
    func theRequestComesOutOfItsEnvelopeWithoutTheMetadata() throws {
        let path = try write([userStep(0, request: "List the files in the current directory, then say done.")])
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(
            reader.tail(ofTranscriptAt: path).latestUserRequest
                == "List the files in the current directory, then say done."
        )
    }

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

    /// A tool-only call is passed over; tool output, the product's own message and reasoning are
    /// never taken for the words.
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

        // A step with no index cannot be told from the next, so it is not handed over.
        var unnumbered = modelStep(3, says: "two")
        unnumbered.removeValue(forKey: "step_index")
        let withoutIndex = try write([userStep(0, request: "Reply with exactly the word two."), unnumbered])
        defer { try? FileManager.default.removeItem(atPath: withoutIndex) }
        #expect(reader.tail(ofTranscriptAt: withoutIndex).latestModelText == nil)
    }

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

        // The envelope is what says which part is the user's, so an unwrapped step is skipped.
        let unwrapped = try write([
            [
                "step_index": 0, "source": "USER_EXPLICIT", "type": "USER_INPUT", "status": "DONE",
                "content": "The current local time is: 2026-09-12T00:24:42-07:00."
            ]
        ])
        defer { try? FileManager.default.removeItem(atPath: unwrapped) }
        #expect(reader.tail(ofTranscriptAt: unwrapped).latestUserRequest == nil)
    }

    /// A request past the window not being found is the bound working.
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

        steps.append(userStep(101, request: "The thing asked just now"))
        let inWindow = try write(steps)
        defer { try? FileManager.default.removeItem(atPath: inWindow) }
        #expect(reader.tail(ofTranscriptAt: inWindow).latestUserRequest == "The thing asked just now")
    }
}
