import Foundation
import Testing
@testable import Notchline

/// The helper announces the event on its first line when the registration names it, and the
/// vocabulary's translator produces the reducer's payload. Shipping products are unchanged.
@Suite(.serialized)
struct HookTransportDialectTests {
    /// The payload names no event, so the name must come from the registration.
    private struct AnnouncingVocabulary: AgentHookVocabulary {
        let agent: AgentKind = .claudeCode
        let managedDefinitions = [
            ManagedHookDefinition(event: "Begin", matcher: nil, shape: .handlerList, argument: "Begin"),
            ManagedHookDefinition(event: "Stop", matcher: nil, shape: .handlerList, argument: "Stop")
        ]
        let legacyCommandMarkers: [String] = []
        let reportsApprovalDenials = false
        let carriesPromptText = false
        let carriesFinalAnswerText = false
        let messageDeltaEventName: String? = nil
        let wakesOnToolCallOpened = false
        let settlesHeldTurnsFromRecord = false
        let restoreDefinitionAdvice = "Turn the switch off and on."
        let answeringTimeoutSeconds = 60
        let answering: (any RequestAnswering)? = nil
        let registrationDialect = HookRegistrationDialect(
            containerKey: "fixture",
            handlersAreShellCommandLines: true,
            eventNameArrivesAsArgument: true
        )
        let payloadTranslator: (any HookPayloadTranslating)? = FirstLineTranslator()

        func signal(forEvent name: String, toolName: String?) -> HookSignal? {
            switch name {
            case "Begin": .turnStarted
            case "Stop": .turnEnded
            default: nil
            }
        }

        func request(
            forEvent name: String, toolName: String?, toolInput: JSONValue?,
            permissionSuggestions: JSONValue?, openedBy toolUseID: String
        ) -> AgentRequest? { nil }
    }

    private struct FirstLineTranslator: HookPayloadTranslating {
        func canonicalPayload(from body: Data, receivedAt: Date) -> Data? {
            guard let newline = body.firstIndex(of: UInt8(ascii: "\n")) else { return nil }
            let event = String(decoding: body[..<newline], as: UTF8.self)
            guard let object = try? JSONSerialization.jsonObject(with: body[body.index(after: newline)...]) as? [String: Any],
                  let conversation = object["conversationId"] as? String else { return nil }
            return try? JSONSerialization.data(withJSONObject: [
                "hook_event_name": event,
                "session_id": conversation,
                "turn_id": "\(conversation)-turn"
            ])
        }
    }

    private func root() throws -> URL {
        // A Unix socket path may not exceed 104 bytes.
        let root = URL(fileURLWithPath: "/tmp").appendingPathComponent("htd-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: - The script

    @Test
    func theHelperAnnouncesTheEventOnlyWhenTold() {
        let bare = AgentHookHelper.script(socketPath: "/tmp/x/hook.sock", answerWindowSeconds: 60)
        let announcing = AgentHookHelper.script(
            socketPath: "/tmp/x/hook.sock", answerWindowSeconds: 60, announcesEvent: true
        )
        #expect(bare == AgentHookHelper.script(socketPath: "/tmp/x/hook.sock", answerWindowSeconds: 60, announcesEvent: false))
        #expect(!bare.contains("printf"))
        #expect(announcing.contains("{ printf '%s\\n' \"${1:-}\"; cat; } | /usr/bin/nc -U -w 1 '/tmp/x/hook.sock' >/dev/null"))
        // The reply channel is untouched: the long wait still comes first.
        #expect(announcing.contains("if [ \"${1:-}\" = \(AgentHookHelper.answeringArgument) ]; then"))
        #expect(announcing.hasSuffix("exit 0\n"))
        #expect(!announcing.contains("exec /usr/bin/nc"))
    }

    /// Only `wait` opens the reply channel, so a product naming its event in every argument holds
    /// no connection.
    @Test
    func onlyTheWaitArgumentNamesTheAnsweringEvent() {
        #expect(AnnouncingVocabulary().answeringEventName == nil)
        #expect(ClaudeCodeHookVocabulary().answeringEventName == "PermissionRequest")
        #expect(CodexHookVocabulary().answeringEventName != nil)
    }

    // MARK: - The registration

    @Test
    func theSetupWritesTheDialectTheVocabularyDeclares() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HookIntegrationPaths(
            supportDirectory: root.appendingPathComponent("AS"),
            hooksConfiguration: root.appendingPathComponent("hooks.json"),
            agent: .claudeCode
        )
        let setup = ManagedHooksSetup(paths: paths, vocabulary: AnnouncingVocabulary())
        let configuration = setup.configuration
        #expect(configuration.containerKey == "fixture")
        #expect(configuration.command == "/bin/sh '\(paths.hookHelper.path)'")
        let stop = configuration.handler(for: AnnouncingVocabulary().managedDefinitions[1])
        #expect(stop["command"] as? String == "/bin/sh '\(paths.hookHelper.path)' Stop")
        #expect(stop["args"] == nil)

        try await setup.install()
        let written = try #require(paths.readConfigurationRoot(fileManager: .default))
        #expect(written.keys.sorted() == ["fixture"])
        let helper = try String(contentsOf: paths.hookHelper, encoding: .utf8)
        #expect(helper.contains("printf '%s\\n' \"${1:-}\""))
        #expect(await setup.status() == .active)

        let classic = ManagedHooksSetup(paths: paths, vocabulary: ClaudeCodeHookVocabulary()).configuration
        #expect(classic.containerKey == "hooks")
        #expect(classic.command == paths.hookHelper.path)
        #expect(classic.handler(for: ClaudeCodeHookVocabulary().managedDefinitions[0])["args"] as? [String] == [])
    }

    // MARK: - End to end

    @Test
    func theAnnouncedPayloadReachesTheReducerThroughTheTranslator() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HookIntegrationPaths(
            supportDirectory: root.appendingPathComponent("AS"),
            hooksConfiguration: root.appendingPathComponent("hooks.json"),
            agent: .claudeCode
        )
        let source = HookLifecycleSource(paths: paths, vocabulary: AnnouncingVocabulary())
        defer { source.disconnect() }
        #expect(await source.prepareTransport())

        for event in ["Begin", "Stop"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [paths.hookHelper.path, event]
            process.environment = ProcessInfo.processInfo.environment
                .filter { $0.key != AgentHookHelper.suppressionEnvironmentKey }
            let input = Pipe()
            let errors = Pipe()
            process.standardInput = input
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errors
            try process.run()
            input.fileHandleForWriting.write(#"{"conversationId":"conv-1","modelName":"auto"}"#.data(using: .utf8)!)
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            let stderr = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            #expect(
                process.terminationStatus == 0,
                Comment(rawValue: "reason \(process.terminationReason.rawValue), stderr: \(stderr), helper: \((try? String(contentsOf: paths.hookHelper, encoding: .utf8)) ?? "<missing>")")
            )
        }

        var turns: [HookTurnState] = []
        for _ in 0..<40 where turns.first?.sessionStatus != .completed {
            turns = await source.repository.drainDeliveredEvents().turns
            try await Task.sleep(for: .milliseconds(50))
        }
        let turn = try #require(turns.first)
        #expect(turns.count == 1)
        #expect(turn.threadID == "conv-1")
        #expect(turn.turnID == "conv-1-turn")
        #expect(turn.sessionStatus == .completed)
    }

    /// Not counted as unreadable: a sibling product's event is nobody's fault.
    @Test
    func aPayloadTheTranslatorDeclinesIsDroppedQuietly() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HookIntegrationPaths(
            supportDirectory: root.appendingPathComponent("AS"),
            hooksConfiguration: root.appendingPathComponent("hooks.json"),
            agent: .claudeCode
        )
        let source = HookLifecycleSource(paths: paths, vocabulary: AnnouncingVocabulary())
        _ = source.deliver(Data(#"{"conversationId":"conv-2"}"#.utf8), at: Date())
        let state = await source.repository.drainDeliveredEvents()
        #expect(state.turns.isEmpty)
        #expect(state.diagnostic == nil)
    }
}
