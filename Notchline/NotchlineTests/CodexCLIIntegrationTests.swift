import Darwin
import Foundation
import Testing
@testable import Notchline

@MainActor
struct CodexCLIIntegrationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func cli(_ pid: Int32 = 100, start: Date? = nil) -> CodexExecution {
        CodexExecution(pid: pid, startedAt: start ?? now, surface: .cli, terminal: "/dev/ttys\(pid)")
    }
    private func ledger(_ executions: [CodexExecution]) -> CodexSurfaceLedger {
        CodexSurfaceLedger(source: CodexProcessSource(resolvePeer: { _ in executions.first },
            isAlive: { executions.contains($0) }, localProcesses: { executions.filter { $0.surface == .cli } }))
    }

    @Test func aNewThreadDoesNotRetireItsPreviousExecution() async {
        let process = cli()
        let source = ledger([process])
        source.record(owner: process, thread: "old", event: "SessionStart")
        source.record(owner: process, thread: "new", event: "SessionStart")
        source.record(owner: process, thread: "old", event: "PreToolUse", isSubagent: true)
        #expect(source.refresh(at: now).threadIDs == ["old", "new"])
        #expect(await source.processIdentifier(forThreadID: "old") == process.pid)
        #expect(source.navigationProcess("old") == process.pid)
        #expect(await source.processIdentifier(forThreadID: "new") == process.pid)
        source.record(owner: process, thread: "old", event: "SessionEnd")
        #expect(!source.record(owner: process, thread: "old", event: "PostToolUse"))
        #expect(source.refresh(at: now).threadIDs == ["new"])
        #expect(await source.processIdentifier(forThreadID: "new") == process.pid)
    }

    @Test func sameDirectoryDoesNotJoinTerminalsAndAReusedPIDCannotRead() async {
        let first = cli(), second = cli(101)
        let alive = CLIProcessFixture([first, second])
        let source = CodexSurfaceLedger(source: alive.source)
        source.record(owner: first, thread: "one", event: "UserPromptSubmit")
        source.record(owner: second, thread: "two", event: "UserPromptSubmit")
        #expect(await source.processIdentifier(forThreadID: "one") == first.pid)
        #expect(await source.processIdentifier(forThreadID: "two") == second.pid)
        alive.replace([cli(start: now.addingTimeInterval(1)), second])
        #expect(await source.processIdentifier(forThreadID: "one") == nil)
        #expect(source.navigationProcess("one") == nil)
        #expect(source.refresh(at: now).threadIDs == ["two"])
    }

    @Test func sharedThreadKeepsOtherOwnerAndHasNoAmbiguousTerminalAuthority() async {
        let local = cli()
        let desktop = CodexExecution(pid: 200, startedAt: now, surface: .desktop, terminal: nil)
        let source = ledger([local, desktop])
        source.record(owner: local, thread: "shared", event: "SessionStart")
        source.record(owner: desktop, thread: "shared", event: "SessionStart")
        #expect(source.hasCLI("shared"))
        #expect(!source.isCLI("shared"))
        #expect(await source.processIdentifier(forThreadID: "shared") == nil)
        #expect(source.admit(owner: local, thread: "shared", turn: "t", event: "UserPromptSubmit"))
        #expect(!source.admit(owner: desktop, thread: "shared", turn: "t", event: "PermissionRequest"))
        source.record(owner: desktop, thread: "shared", event: "SessionEnd")
        #expect(source.refresh(at: now).threadIDs == ["shared"])
        #expect(await source.processIdentifier(forThreadID: "shared") == local.pid)
    }

    @Test func nativeArgumentReadingIsBoundedAndDiscardsTheEnvironment() throws {
        var count: Int32 = 3
        var bytes = withUnsafeBytes(of: &count) { Array($0) }
        bytes += Array("/bin/codex\0\0codex\0-m\0model\0\0\0HOME=/Users/a\0SECRET=not-retained\0CODEX_HOME=/Users/a/.codex\0\0".utf8)
        let reading = try #require(CodexNativeProcesses.decodeArguments(bytes))
        #expect(reading == ["codex", "-m", "model"])
        #expect(CodexNativeProcesses.decodeArguments([0, 0, 0, 0]) == nil)
        #expect(CodexNativeProcesses.decodeArguments(Array(bytes.prefix(14))) == nil)
        bytes[4] = 0xff
        #expect(CodexNativeProcesses.decodeArguments(bytes) == nil)
    }

    @Test func nativeKernelArgumentsCanBeReadWithoutAProcessListing() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["10"]
        process.environment = ["HOME": "/tmp/notchline-cli-test", "SECRET": "not-retained"]
        try process.run()
        defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        let reading = try #require(CodexNativeProcesses.arguments(process.processIdentifier))
        #expect(reading.last == "10")
    }

    @Test func unknownModesOptionsAndHomesAreRejected() {
        #expect(CodexNativeProcesses.isAppServer(["codex", "-c", "key=value", "app-server", "--analytics-default-enabled"]))
        #expect(CodexNativeProcesses.isAppServer(["codex", "app-server", "--listen", "stdio://"]))
        #expect(!CodexNativeProcesses.isAppServer(["codex", "-c", "key=value", "exec"]))
        #expect(!CodexNativeProcesses.isAppServer(["codex", "--remote", "app-server"]))
        for args in [["codex"], ["codex", "--no-alt-screen"], ["codex", "resume", "--last"],
                     ["codex", "-m", "model", "a prompt"], ["codex", "-c", "model=\"model\""]] {
            #expect(CodexNativeProcesses.isLocalTUI(args))
        }
        for args in [["codex", "exec", "hello"], ["codex", "app-server"], ["codex", "--remote", "unix://x"],
                     ["codex", "--future-mode"], ["codex", "-m"], ["codex", "mcp-server"], []] {
            #expect(!CodexNativeProcesses.isLocalTUI(args))
        }
        let home = URL(fileURLWithPath: "/Users/a")
        #expect(CodexNativeProcesses.hasHomeDatabase(in: ["/Users/a/.codex/state_5.sqlite"], home: home))
        for paths in [[], ["/tmp/other/state_5.sqlite"], ["/Users/a/.codex/state_6.sqlite"],
                      ["/Users/a/.codex/state_5.sqlite", "/tmp/other/state_5.sqlite"]] {
            #expect(!CodexNativeProcesses.hasHomeDatabase(in: paths, home: home))
        }
    }

    @Test func interruptionEndsOnlyItsObservedTurnAndClearsItsWait() async throws {
        let repository = HookEventRepository()
        func send(_ name: String, turn: String = "t", extra: [String: String] = [:], offset: TimeInterval) throws {
            var value = extra
            value["hook_event_name"] = name; value["session_id"] = "thread"; value["turn_id"] = turn
            _ = repository.deliver(try JSONSerialization.data(withJSONObject: value), at: now.addingTimeInterval(offset))
        }
        try send("Interrupt", offset: 0)
        #expect(await repository.drainDeliveredEvents().turns.isEmpty)
        try send("UserPromptSubmit", offset: 1)
        try send("PreToolUse", extra: ["tool_name": "request_user_input", "tool_use_id": "question"], offset: 2)
        try send("Interrupt", turn: "wrong", offset: 3)
        #expect(await repository.drainDeliveredEvents().turns.first?.status == .inputNeeded)
        try send("Interrupt", offset: 4)
        let stopped = await repository.drainDeliveredEvents()
        #expect(stopped.turns.first?.status == .completed)
        #expect(stopped.turns.first?.requestsAwaitingAnAnswer.isEmpty == true)
        try send("PreToolUse", extra: ["tool_name": "Bash", "tool_use_id": "late"], offset: 2)
        #expect(await repository.drainDeliveredEvents().turns.first?.status == .completed)
    }

    @Test func appendedHooksPreserveExistingTrustInputs() {
        let definitions = CodexHookVocabulary().managedDefinitions
        #expect(definitions.prefix(7).map(\.event) == ["UserPromptSubmit", "PermissionRequest", "SubagentStart",
            "SubagentStop", "PreToolUse", "PostToolUse", "Stop"])
        #expect(definitions.suffix(3).map(\.event) == ["SessionStart", "SessionEnd", "Interrupt"])
        #expect(definitions[1].argument == AgentHookHelper.answeringArgument)
        #expect(definitions[1].timeoutSeconds == 3600)
        #expect(definitions.allSatisfy { $0.matcher == nil })
    }

    @Test func navigationRaisesOnlyTheHostBecauseTheDisplayedThreadCannotBeVerified() async throws {
        let process = cli(), alive = CLIProcessFixture([cli()])
        let source = CodexSurfaceLedger(source: alive.source)
        source.record(owner: process, thread: "old", event: "SessionStart")
        source.record(owner: process, thread: "new", event: "SessionStart")
        let tabs = CLITabFixture(), activator = CLIActivationFixture()
        let navigator = ProcessHostNavigator(sessions: source,
            hosts: CLIHostFixture(), activator: activator, tabs: tabs,
            allowsTerminalFocus: { _, _ in false },
            controllingTerminalPath: { _ in "/dev/ttys100" })
        func row(_ thread: String) -> MonitoredSession {
            MonitoredSession(threadID: thread, turnID: "t", projectName: "work", title: "title",
                preview: nil, status: .completed, startedAt: now)
        }
        #expect(try await navigator.open(row("old")) == .raisedApplication(host: "Terminal"))
        #expect(tabs.calls == 0 && activator.calls == 1)
        #expect(try await navigator.open(row("new")) == .raisedApplication(host: "Terminal"))
        #expect(tabs.calls == 0 && activator.calls == 2)
        alive.replace([])
        await #expect(throws: ProcessHostNavigationError.self) { try await navigator.open(row("new")) }
        #expect(tabs.calls == 0 && activator.calls == 2)
    }

    @Test func providerKeepsCLIWithoutDesktopAndRetiresOnlyExitedOwner() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nc-cli-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HookIntegrationPaths(supportDirectory: root.appendingPathComponent("support"),
            hooksConfiguration: root.appendingPathComponent(".codex/hooks.json"))
        let registrar = CodexHookRegistrar(paths: paths)
        try await registrar.install()
        let repository = HookEventRepository(paths: paths)
        let first = cli(), second = cli(101)
        let processes = CLIProcessFixture([first, second])
        let surfaces = CodexSurfaceLedger(source: processes.source)
        var timing = MonitorTiming.standard
        timing.terminalReadSettlingInterval = 0
        let service = LiveCodexMonitorService(client: CLIMetadataClient(), hookEvents: repository,
            hookRegistrar: registrar, surfaces: surfaces, unreadState: CLIEmptyDesktopReading(),
            timing: timing, desktopProcessIdentifierProvider: { nil })
        for (thread, owner) in [("one", first), ("two", second)] {
            surfaces.record(owner: owner, thread: thread, event: "UserPromptSubmit")
            _ = repository.deliver(try JSONSerialization.data(withJSONObject: ["hook_event_name": "UserPromptSubmit",
                "session_id": thread, "turn_id": "t-\(thread)", "cwd": "/work/shared", "prompt": "Live prompt"]), at: Date())
        }
        var reading = await service.fetchSnapshot()
        for _ in 0..<100 where reading.sessions.count != 2 {
            try await Task.sleep(for: .milliseconds(10))
            reading = await service.fetchSnapshot()
        }
        #expect(reading.presence == .open)
        #expect(Set(reading.sessions.map(\.threadID)) == ["one", "two"])
        #expect(reading.sessions.allSatisfy { $0.status == .running && $0.projectName == "shared" })
        _ = repository.deliver(try JSONSerialization.data(withJSONObject: ["hook_event_name": "Stop",
            "session_id": "one", "turn_id": "t-one", "last_assistant_message": "Finished"]), at: Date())
        let completed = await service.fetchSnapshot()
        #expect(completed.sessions.first(where: { $0.threadID == "one" })?.status == .completed,
            "Desktop's current empty unread set must not retire a CLI row, even after settling")
        processes.replace([second])
        let afterExit = await service.fetchSnapshot()
        #expect(afterExit.sessions.map(\.threadID) == ["two"])
        #expect(afterExit.sessions.first?.status == .running)
        await service.disconnect()
        #expect(await service.nextRefreshDeadline() == nil)
        #expect(surfaces.refresh(at: Date()).threadIDs.isEmpty)
    }
}

private nonisolated struct CLIEmptyDesktopReading: DesktopUnreadStateProviding {
    func snapshot() async -> DesktopUnreadStateSnapshot {
        .init(unreadThreadIDs: [], source: .current, currentAsOf: .distantFuture)
    }
    func changeEvents() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

private nonisolated final class CLIProcessFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var executions: [CodexExecution]
    init(_ executions: [CodexExecution]) { self.executions = executions }
    func replace(_ executions: [CodexExecution]) { lock.lock(); defer { lock.unlock() }; self.executions = executions }
    func reading() -> [CodexExecution] { lock.lock(); defer { lock.unlock() }; return executions }
    var source: CodexProcessSource {
        CodexProcessSource(resolvePeer: { _ in self.reading().first },
            isAlive: { self.reading().contains($0) }, localProcesses: { self.reading().filter { $0.surface == .cli } })
    }
}

private actor CLIMetadataClient: CodexAppServerCommunicating {
    func connect() async throws {}
    func disconnect() async {}
    func request(method: String, params: JSONValue?, timeoutNanoseconds: UInt64?) async throws -> JSONValue {
        func thread(_ id: String) -> JSONValue {
            .object(["id": .string(id), "threadSource": .string("user"), "source": .string("cli"),
                "name": .string(id), "status": .object(["type": .string("notLoaded")])])
        }
        switch method {
        case "thread/read": return .object(["thread": thread(params?["threadId"]?.stringValue ?? "")])
        case "thread/list": return .object(["data": .array([thread("one"), thread("two")]), "nextCursor": .null])
        default: return .object([:])
        }
    }
}

private struct CLIHostFixture: SessionHostResolving {
    func host(ofProcess pid: Int32) async -> ClaudeCodeHost? {
        .terminal(HostApplication(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal", processIdentifier: 300))
    }
}

@MainActor private final class CLITabFixture: TerminalTabFocusing {
    var calls = 0
    func focusTab(withTerminalDevice device: String, in application: HostApplication) async -> TerminalTabFocus {
        calls += 1; return .focused
    }
}

@MainActor private final class CLIActivationFixture: HostApplicationActivating {
    var calls = 0
    func activate(_ application: HostApplication) async -> Bool { calls += 1; return true }
}
