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

    /// A drop nobody counts is indistinguishable from "the hooks never fired", which is the one
    /// reading a user cannot act on. Provenance failure is the shape an unsupported home or mode
    /// arrives in, so it is the drop that has to be said out loud.
    @Test func anUnattributableEventIsDroppedOutLoudAndAContractRefusalStaysSilent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nc-drop-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let repository = HookEventRepository(paths: HookIntegrationPaths(supportDirectory: support,
            hooksConfiguration: root.appendingPathComponent(".codex/hooks.json")))
        let process = cli()
        let owned = CodexSurfaceLedger(source: CodexProcessSource(resolvePeer: { _ in process },
            isAlive: { _ in true }, localProcesses: { [process] }))
        let unnameable = CodexSurfaceLedger(source: CodexProcessSource(resolvePeer: { _ in nil },
            isAlive: { _ in false }, localProcesses: { [] }))
        func body(_ value: [String: String]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
        let submit = try body(["hook_event_name": "UserPromptSubmit", "session_id": "thread",
            "turn_id": "t", "prompt": "Live prompt"])

        #expect(unnameable.receive(submit, at: now, descriptor: -1, repository: repository) == .close)
        var reading = await repository.drainDeliveredEvents()
        #expect(reading.turns.isEmpty)
        #expect(reading.diagnostic?.contains("Ignored 1 hook payload Notchline could not attribute to a "
            + "supported Codex process") == true)

        // Neither of these can book ownership, and both belong to counts the boundary already keeps.
        #expect(owned.receive(Data("{".utf8), at: now, descriptor: -1, repository: repository) == .close)
        #expect(owned.receive(try body(["hook_event_name": "Invented", "session_id": "thread"]),
            at: now, descriptor: -1, repository: repository) == .close)
        reading = await repository.drainDeliveredEvents()
        #expect(reading.turns.isEmpty)
        #expect(reading.diagnostic?.contains("Ignored 1 hook payload that could not be read.") == true)
        #expect(reading.diagnostic?.contains("of an unsupported kind") == true)

        // The ownership contract's own refusals are expected traffic: no sentence, and no count.
        owned.record(owner: process, thread: "thread", event: "SessionEnd")
        #expect(owned.receive(submit, at: now, descriptor: -1, repository: repository) == .close)
        let settled = await repository.drainDeliveredEvents()
        #expect(settled.turns.isEmpty)
        #expect(settled.diagnostic == reading.diagnostic)
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

    /// A scan nothing can schedule. The process inventory answers the presence dot and nothing else,
    /// and "a TUI that has never sent a Hook may have started" is not a condition any refresh
    /// clears: published as a deadline it woke every product every five seconds for the life of the
    /// app, an asleep screen included, because the refresh it woke only booked the next one. So it
    /// is read inside a refresh that is already happening, exactly as `AntigravityConversationScanner`
    /// reads its presence locks, and costs nothing while nothing else wakes the provider. The
    /// accepted degradation: a TUI started before this app, or with Hooks untrusted, moves the dot
    /// at the next refresh from any cause instead of within five seconds. One started normally sends
    /// `SessionStart`, which books an owner and wakes the store itself.
    @Test func theCLIInventoryIsScannedOpportunisticallyAndAsksForNoWakeUp() async throws {
        let process = cli()
        let scans = ScanCounter()
        let ledger = CodexSurfaceLedger(source: CodexProcessSource(resolvePeer: { _ in process },
            isAlive: { _ in true }, localProcesses: { scans.record(); return [process] }))

        // Presence with no Hook at all, and one reading answers the burst of refreshes around it.
        #expect(ledger.refresh(at: now).cliIsOpen == true)
        #expect(ledger.refresh(at: now.addingTimeInterval(CodexSurfaceLedger.scanLifetime - 0.5))
            .cliIsOpen == true)
        #expect(scans.count == 1)
        #expect(ledger.refresh(at: now.addingTimeInterval(CodexSurfaceLedger.scanLifetime)).cliIsOpen == true)
        #expect(scans.count == 2, "the lifetime caps repeat cost within a burst; it never asks to be woken")

        // The idle provider: no Desktop, no TUI, no Hook and no screen leaves nothing to wake for.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nc-idle-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HookIntegrationPaths(supportDirectory: root.appendingPathComponent("support"),
            hooksConfiguration: root.appendingPathComponent(".codex/hooks.json"))
        let registrar = CodexHookRegistrar(paths: paths)
        try await registrar.install()
        let empty = CodexSurfaceLedger(source: CodexProcessSource(resolvePeer: { _ in nil },
            isAlive: { _ in false }, localProcesses: { [] }))
        let service = LiveCodexMonitorService(client: CLIMetadataClient(),
            hookEvents: HookEventRepository(paths: paths), hookRegistrar: registrar, surfaces: empty,
            unreadState: CLIEmptyDesktopReading(), screenAvailability: CLINoScreen(),
            desktopProcessIdentifierProvider: { nil })
        #expect(await service.fetchSnapshot().presence == .closed)
        #expect(await service.nextRefreshDeadline() == nil,
            "an inventory that found nothing must not book the store's next wake")
        await service.disconnect()
    }

    /// One list, so the two readings cannot answer different questions about the same machine.
    /// `CodexExecutableLocator` picks the binary that runs `app-server`; `command(named:)` names
    /// the CLI install Settings shows. They are allowed to name different binaries — Desktop ships
    /// its own `codex` and it is preferred for the App Server — but they must not search different
    /// *places*, or a CLI in a directory only one of them knows is half-seen: present in Settings
    /// and unusable for metadata, or the reverse.
    @Test func theAppServerAndTheCLIReadingSearchTheSameInstallDirectories() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let environment = ["PATH": "/usr/bin:/opt/custom/bin"]
        let directories = ProductInstallationDiscovery.commandDirectories(home: home, environment: environment)
        let candidates = CodexExecutableLocator.candidates(home: home, environment: environment)

        let desktop = candidates.prefix(2).map(\.path)
        #expect(desktop == ["/Applications/ChatGPT.app/Contents/Resources/codex",
                            "/Applications/Codex.app/Contents/Resources/codex"],
            "Desktop's own build answers for Desktop's App Server, and stays first")
        #expect(Array(candidates.dropFirst(2)) == directories.map { $0.appendingPathComponent("codex") },
            "everything after it is the shared list, in the shared order")
        #expect(!directories.contains { $0.path.hasPrefix("/Applications/") },
            "a Desktop bundle is not a CLI install and is never offered as one")
    }

    /// A CLI shipped on npm lands wherever the user's package or version manager keeps binaries,
    /// and `PATH` cannot be relied on to find it: the window server launches this app, so its
    /// `PATH` is the system default. The directories are therefore named outright, and `PATH` is
    /// appended after them without repeating one.
    @Test func macPortsAndVersionManagerShimsAreSearchedWithoutTrustingPATH() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let directories = ProductInstallationDiscovery.commandDirectories(
            home: home, environment: ["PATH": "/opt/homebrew/bin:/opt/custom/bin"]
        ).map(\.path)

        for expected in ["/Users/someone/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
                         "/opt/local/bin", "/Users/someone/.local/share/mise/shims",
                         "/Users/someone/.asdf/shims", "/Users/someone/.volta/bin",
                         "/Users/someone/.bun/bin"] {
            #expect(directories.contains(expected), "\(expected) is searched without help from PATH")
        }
        #expect(directories.firstIndex(of: "/Users/someone/.local/bin") == 0,
            "the products' own installer location still breaks a tie first")
        #expect(directories.filter { $0 == "/opt/homebrew/bin" }.count == 1,
            "a PATH that repeats a named directory does not search it twice")
        #expect(directories.last == "/opt/custom/bin", "PATH is the fallback, after every named directory")
    }

    /// Identity is not an install location. Everything `localTUI` still reads describes the running
    /// process — its name, its argv, its terminal, its open home database — so a TUI started from a
    /// shim, a second Homebrew prefix or a version directory is the same evidence as one started
    /// from the path a search happens to find first. Nothing here consults a list of paths.
    @Test func aTUIIsIdentifiedByTheProcessAndNotByWhereItWasInstalled() {
        #expect(CodexNativeProcesses.isLocalTUI(["/opt/local/bin/codex"]))
        #expect(CodexNativeProcesses.isLocalTUI(["/Users/someone/.local/share/mise/installs/npm-openai-codex/0.154.0/bin/codex", "--search"]))
        #expect(!CodexNativeProcesses.isLocalTUI(["/opt/local/bin/codex", "app-server"]),
            "a subcommand is still what separates the surfaces, wherever the binary lives")
        #expect(!CodexNativeProcesses.isLocalTUI(["/opt/local/bin/codex", "exec", "do the thing"]))

        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(CodexNativeProcesses.hasHomeDatabase(
            in: ["/Users/someone/.codex/state_5.sqlite"], home: home
        ), "the home database is read from the process, not from where the binary sits")
        #expect(!CodexNativeProcesses.hasHomeDatabase(
            in: ["/Users/elsewhere/.codex/state_5.sqlite"], home: home
        ))
    }

    /// The same claim against the kernel rather than against pure functions, because this is the
    /// defect's actual shape: a real process, running a binary in a directory **no list contains**,
    /// holding this home's database open on a real terminal. Matching the running executable
    /// against the one discovered install path failed exactly here, and the Turn got no row.
    ///
    /// The pty is allocated here and the staged process makes it its own controlling terminal —
    /// `script(1)` cannot do it, since it needs a terminal on its own stdin and a window server
    /// launch has none. The staged binary is a copy of `perl` named `codex`: it takes a script as
    /// its one positional argument, which is the argv shape of a TUI started with a prompt.
    @Test func aTUIInstalledWhereNoListLooksIsStillIdentifiedFromTheKernel() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nc-tui-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let database = home.appendingPathComponent(".codex/state_5.sqlite")
        let installed = root.appendingPathComponent("no/list/knows/this/bin")
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        try Data().write(to: database)
        let executable = installed.appendingPathComponent(CodexNativeProcesses.executableName)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/perl"), to: executable)

        let master = posix_openpt(O_RDWR | O_NOCTTY)
        try #require(master >= 0, "no pty available")
        defer { close(master) }
        try #require(grantpt(master) == 0 && unlockpt(master) == 0)
        let terminal = String(cString: ptsname(master))

        // A session leader with no controlling terminal takes the first one it opens, which is how
        // a TUI in Terminal.app gets its own. The session has to come from the spawn:
        // `Foundation.Process` makes the child a process-group leader, and a group leader's
        // `setsid()` fails, so the staged process would never acquire the terminal.
        let script = root.appendingPathComponent("hold.pl")
        try """
            open(TTY, "+<", "\(terminal)") or exit 3;
            open(DB, "<", "\(database.path)") or exit 4;
            sleep 120;
            """.write(to: script, atomically: true, encoding: .utf8)

        let pid = try #require(Self.spawnInItsOwnSession(executable.path, script.path))
        defer { kill(pid, SIGKILL) }

        let reader = CodexNativeProcesses(home: home)
        var execution: CodexExecution?
        // The terminal and the database are opened a moment after exec, so the poll races the
        // staging rather than the code under test.
        for _ in 0 ..< 200 where execution == nil {
            execution = reader.localTUI(pid)
            if execution == nil { try await Task.sleep(for: .milliseconds(25)) }
        }
        let tui = try #require(execution, """
            a process named codex, with TUI-shaped argv, a controlling terminal and this home's \
            database open is a local TUI wherever it was installed from
            """)
        #expect(tui.surface == .cli)
        #expect(tui.pid == pid)
        #expect(tui.terminal == terminal, "the controlling terminal is the row's read authority")
        #expect(reader.usesDefaultHome(pid), "and it is this home, not another")
        #expect(
            LibprocProcessTable().processes(named: CodexNativeProcesses.executableName)?
                .contains { $0.processIdentifier == pid } == true,
            "and the inventory that answers the presence dot lists it too"
        )

        // The same process read against another home is not this user's TUI: still fails closed.
        let elsewhere = CodexNativeProcesses(home: root.appendingPathComponent("someone-else"))
        #expect(elsewhere.localTUI(pid) == nil)
    }

    private static func spawnInItsOwnSession(_ executable: String, _ argument: String) -> pid_t? {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for descriptor in Int32(0) ... 2 {
            posix_spawn_file_actions_addopen(&actions, descriptor, "/dev/null", O_RDWR, 0)
        }
        let argv = [strdup(executable), strdup(argument), nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        guard posix_spawn(&pid, executable, &actions, &attributes, argv, environ) == 0 else { return nil }
        return pid
    }
}

private nonisolated final class ScanCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var scans = 0
    func record() { lock.lock(); scans += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return scans }
}

/// No screen, so the quota and terminal-recheck deadlines park and the inventory is the only
/// candidate left for `nextRefreshDeadline()` to report.
private nonisolated struct CLINoScreen: ScreenAvailabilityReporting {
    func isAvailable() -> Bool { false }
    func changeEvents() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
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
