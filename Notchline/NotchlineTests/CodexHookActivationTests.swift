import Foundation
import Testing
@testable import Notchline

@MainActor
struct CodexHookActivationTests {
    private func paths() -> HookIntegrationPaths {
        let root = URL(fileURLWithPath: "/tmp/nha-\(UUID().uuidString.prefix(8))")
        return HookIntegrationPaths(supportDirectory: root.appendingPathComponent("AS"),
                                    hooksConfiguration: root.appendingPathComponent(".codex/hooks.json"))
    }

    private func response(_ paths: HookIntegrationPaths, change: (inout [JSONValue]) -> Void = { _ in }) -> JSONValue {
        let command = CodexHookRegistrar.command(forHelper: paths.hookHelper)
        var hooks = CodexHookVocabulary().managedDefinitions.map { definition in
            JSONValue.object([
                "sourcePath": .string(paths.hooksConfiguration.path),
                "eventName": .string(definition.event.prefix(1).lowercased() + definition.event.dropFirst()),
                "command": .string(definition.argument.map { "\(command) \($0)" } ?? command),
                "source": .string("user"), "handlerType": .string("command"),
                "enabled": .bool(true), "trustStatus": .string("trusted"),
                "matcher": definition.matcher.map(JSONValue.string) ?? .null,
                "timeoutSec": .number(Double(definition.timeoutSeconds)), "async": .bool(false)
            ])
        }
        change(&hooks)
        return .object(["data": .array([.object([
            "cwd": .string(paths.hooksConfiguration.deletingLastPathComponent().path),
            "errors": .array([]), "warnings": .array([]), "hooks": .array(hooks)
        ])])])
    }

    @Test func requiresEveryCurrentDefinitionEnabledAndTrusted() {
        let paths = paths()
        #expect(CodexHookActivation.allManagedHooksAreTrusted(in: response(paths), paths: paths))
        let invalid: [(String, JSONValue)] = [
            ("trustStatus", .string("untrusted")), ("trustStatus", .string("modified")),
            ("trustStatus", .string("future-status")), ("enabled", .bool(false)),
            ("sourcePath", .string("/other/hooks.json")), ("source", .string("project")),
            ("matcher", .string("Bash")), ("command", .string("another-helper")),
            ("timeoutSec", .number(1)), ("timeoutSec", .number(3.5)), ("async", .bool(true)), ("handlerType", .string("prompt"))
        ]
        for (field, value) in invalid {
            let reading = response(paths) { hooks in
                var first = hooks[0].objectValue!
                first[field] = value
                hooks[0] = .object(first)
            }
            #expect(!CodexHookActivation.allManagedHooksAreTrusted(in: reading, paths: paths))
        }
        for reading in [JSONValue.null, .object([:]), .object(["data": .array([])]),
                        response(paths, change: { $0.removeLast() }),
                        response(paths, change: { $0.append($0[0]) })] {
            #expect(!CodexHookActivation.allManagedHooksAreTrusted(in: reading, paths: paths))
        }
    }

    @Test func trustingHooksConnectsWithoutATurnAndReenablingRechecks() async throws {
        let paths = paths()
        defer { try? FileManager.default.removeItem(at: paths.supportDirectory.deletingLastPathComponent()) }
        let registrar = CodexHookRegistrar(paths: paths)
        try await registrar.install()
        let config = paths.hooksConfiguration.deletingLastPathComponent().appendingPathComponent("config.toml")
        try Data("# before trust\n".utf8).write(to: config)
        let client = ActivationClient(response: response(paths) { hooks in
            var first = hooks[0].objectValue!; first["trustStatus"] = .string("untrusted"); hooks[0] = .object(first)
        })
        let repository = HookEventRepository(paths: paths)
        let service = LiveCodexMonitorService(client: client, hookEvents: repository,
            hookRegistrar: registrar, desktopProcessIdentifierProvider: { 42 })
        let before = await service.fetchSnapshot()
        #expect(before.setupStatus == .reviewRequired)
        #expect(!before.isConnected)
        #expect(await service.nextRefreshDeadline() != nil)
        var automaticallyConnected = false
        let changes = service.stateChangeEvents
        let observer = Task { @MainActor in
            for await _ in changes {
                guard !Task.isCancelled else { return }
                if await service.fetchSnapshot().isConnected { automaticallyConnected = true; return }
            }
        }
        defer { observer.cancel() }
        await client.setResponse(response(paths))
        // Atomic replacement mirrors Codex saving trust; no Hook event and no manual Recheck.
        try Data("# after trust\n".utf8).write(to: config, options: .atomic)
        for _ in 0..<250 {
            if automaticallyConnected { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(automaticallyConnected)
        // Connected is read from the Provider snapshot, as Settings reads it.
        // The configuration-only setupStatus() intentionally remains a registration check.
        #expect(await repository.observedState().hasObservedEvent == false)
        #expect(await service.fetchSnapshot().sessions.isEmpty)
        await service.disconnect()
        #expect(await service.nextRefreshDeadline() == nil)
        try await service.removeIntegration()
        try await service.installIntegration()
        #expect(await service.fetchSnapshot().isConnected)
        await service.disconnect()
    }

    @Test func aFailedConnectionDoesNotKeepTheActivationRetryAwake() async throws {
        let paths = paths()
        defer { try? FileManager.default.removeItem(at: paths.supportDirectory.deletingLastPathComponent()) }
        let registrar = CodexHookRegistrar(paths: paths)
        try await registrar.install()
        let client = ActivationClient(response: .null)
        let service = LiveCodexMonitorService(client: client, hookEvents: HookEventRepository(paths: paths),
            hookRegistrar: registrar, desktopProcessIdentifierProvider: { 42 })
        #expect(await service.fetchSnapshot().setupStatus == .reviewRequired)
        let activationDeadline = try #require(await service.nextRefreshDeadline())
        await client.failConnection()
        #expect(await service.fetchSnapshot().availability == .disconnected)
        let remaining = await service.nextRefreshDeadline()
        #expect(remaining == nil || remaining! > activationDeadline)
        await service.disconnect()
    }

    @Test func cachesVerifiedReadsAndRejectsLateReadsAfterReset() async throws {
        let paths = paths()
        defer { try? FileManager.default.removeItem(at: paths.supportDirectory.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: paths.hooksConfiguration.deletingLastPathComponent(), withIntermediateDirectories: true)
        let reader = CodexHookActivation(paths: paths, clock: SystemMonitorClock())
        let client = ActivationClient(response: response(paths))
        #expect(await reader.verified(using: client) == true)
        for _ in 0..<10 { #expect(await reader.verified(using: client) == true) }
        #expect(await client.hookReads == 1)
        #expect(await reader.nextDeadline() == nil)
        await reader.invalidate()
        await client.setDelay(true)
        let late = Task { await reader.verified(using: client) }
        while await client.hookReads < 2 { await Task.yield() }
        await reader.invalidate()
        await client.release()
        #expect(await late.value == false)
        #expect(await reader.nextDeadline() == nil)
    }

    @Test func unsupportedIsDistinctFromBrokenOrUnreadable() async {
        let paths = paths()
        let reader = CodexHookActivation(paths: paths, clock: SystemMonitorClock())
        let client = ActivationClient(response: .null)
        #expect(await reader.verified(using: client) == false)
        #expect(await reader.nextDeadline() != nil)
        await reader.invalidate()
        await client.setUnsupported()
        #expect(await reader.verified(using: client) == nil)
        #expect(await reader.nextDeadline() == nil)
    }
}

private actor ActivationClient: CodexAppServerCommunicating {
    var hookReads = 0
    private var response: JSONValue
    private var unsupported = false
    private var connectionFailed = false
    private var delayed = false
    private var held: CheckedContinuation<Void, Never>?
    init(response: JSONValue) { self.response = response }
    func setResponse(_ value: JSONValue) { response = value }
    func setUnsupported() { unsupported = true }
    func setDelay(_ value: Bool) { delayed = value }
    func release() { held?.resume(); held = nil }
    func failConnection() { connectionFailed = true }
    func connect() throws {
        if connectionFailed { throw CodexAppServerError.disconnected }
    }
    func disconnect() {}
    func request(method: String, params: JSONValue?, timeoutNanoseconds: UInt64?) async throws -> JSONValue {
        if method == "hooks/list" {
            hookReads += 1
            if delayed { await withCheckedContinuation { held = $0 } }
            if unsupported { throw CodexAppServerError.remote(code: -32601, message: "Method not found") }
            return response
        }
        if method == "thread/list" { return .object(["data": .array([]), "nextCursor": .null]) }
        return .object([:])
    }
}
