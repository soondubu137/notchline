import Foundation
import Testing
@testable import Notchline

/// Antigravity CLI through the Tier 0 fixtures of `tiered-support.md` §7,
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

        nonisolated func processes() -> [ProcessEntry] {
            lock.lock()
            defer { lock.unlock() }
            return entries
        }

        nonisolated func openFilePaths(ofProcess processIdentifier: Int32) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return openFiles[processIdentifier] ?? []
        }
    }

    /// The product over a root of its own, torn down with it.
    private struct Product {
        let root: URL
        let paths: HookIntegrationPaths
        let table = TableStub()
        /// The scanner's clock, and only the scanner's: a reading has to
        /// postdate the events it retires, so it starts after `t0`. The
        /// reducer keeps the real clock, against which `t0` is long past
        /// its new-Turn reconciliation grace.
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_757_001_000))
        let scanner: AntigravityConversationScanner
        let provider: HookProductProvider
        let presenceDirectory: URL

        init() throws {
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
            provider = HookProductProvider(
                agent: .antigravity,
                paths: paths,
                vocabulary: AntigravityHookVocabulary(),
                presence: scanner,
                admission: scanner
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

    /// The common fields every payload carries, as the TUI sends them.
    private func common(_ conversation: String, workspaces: [String]) -> [String: Any] {
        [
            "conversationId": conversation,
            "workspacePaths": workspaces,
            "transcriptPath": "/Users/someone/.gemini/antigravity-cli/brain/\(conversation)/.system_generated/logs/transcript_full.jsonl",
            "artifactDirectoryPath": "/Users/someone/.gemini/antigravity-cli/brain/\(conversation)",
            "modelName": "gemini-3.8-flash-high"
        ]
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

    // MARK: - Tier 0: Listed

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
        #expect(row.title == "Untitled", "the prompt is in no payload")
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

    /// A sibling surface's event through the shared file — a transcript under
    /// `antigravity/` rather than `antigravity-cli/` — is nobody's row and
    /// nobody's diagnostic.
    @Test
    func aSiblingProductsEventIsDeclinedQuietly() async throws {
        let product = try Product()
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        await product.run(conversation)

        var ide = invocation(0, of: "ide-conversation")
        ide["transcriptPath"] = "/Users/someone/.gemini/antigravity/brain/ide-conversation/.system_generated/logs/transcript_full.jsonl"
        try product.deliver("PreInvocation", ide, at: t0)
        let snapshot = await product.provider.fetchSnapshot()
        #expect(snapshot.sessions.isEmpty)
        #expect(snapshot.diagnostic == nil)
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
    /// step, and the boundary Settings states for a Tier 0 product.
    @Test
    func theDescriptorSaysWhatTheProductIsAndIsNot() {
        let descriptor = ProductRegistry.descriptor(for: .antigravity)
        #expect(descriptor.settingsTitle == "Antigravity CLI")
        #expect(descriptor.displayName == "Antigravity")
        #expect(descriptor.setup.displayPath == "~/.gemini/config/hooks.json")
        #expect(descriptor.setup.definitionCount == 2)
        #expect(descriptor.setup.trustStep == nil)
        #expect(descriptor.setup.backupName == "hooks.json.notchline-backup")
        #expect(descriptor.setup.switchHelp.contains("2 lifecycle definitions in ~/.gemini/config/hooks.json"))
        #expect(descriptor.declaredBoundary?.contains("Approvals and questions are not detected") == true)
        #expect(ProductRegistry.descriptor(for: .codex).declaredBoundary == nil)
        #expect(ProductRegistry.descriptor(for: .claudeCode).declaredBoundary == nil)
        #expect(ProductRegistry.spokenNames == "Codex, Claude Code and Antigravity")
        #expect(HookIntegrationPaths.live(for: .antigravity).hooksConfiguration.path.hasSuffix("/.gemini/config/hooks.json"))
        #expect(HookIntegrationPaths.live(for: .antigravity).hookSocket.path.utf8.count < 104)
    }
}
