import Foundation

/// Antigravity's lifecycle events, one vocabulary for CLI and Desktop (one engine, hooks file
/// and payload). Measured on `agy` 1.2.2 (2026-09-11) and Desktop 2.13.0 (2026-09-12);
/// see `antigravity-cli.md`.
///
/// - Payloads never name their event, so the registration passes it to the helper
///   (``HookRegistrationDialect``).
/// - No Turn id: `invocationNum` counts model calls from 0 per turn; `Stop`'s `executionNum`
///   always read 0.
/// - No payload carries the prompt or model text; both come from the transcript
///   (``AntigravityTranscriptFile``). `workspacePaths` is empty under `-p`.
/// - Nothing observes a wait, so waits and requests are unsupported (L3,
///   `docs/product-support.md` §5).
///
/// Only two events are registered: `PostInvocation` fires after tools return (10.3 s late
/// around an approval), 30 ms before the next `PreInvocation`; a `{}` `PreToolUse` handler
/// refused every tool call (§2.2); `PostToolUse` never fired.
nonisolated struct AntigravityHookVocabulary: AgentHookVocabulary {
    static let invocationEvent = "PreInvocation"
    static let stopEvent = "Stop"
    /// Never sent or registered: routes transcript model text to the preview store like a streamed
    /// message, never to the reducer.
    static let modelResponseEvent = "PlannerResponse"
    /// The key this app's definitions sit under in the shared hooks file.
    static let containerName = "notchline"
    static let stateDirectoryRelativeToHome = ".gemini/antigravity-cli"
    static let desktopStateDirectoryRelativeToHome = ".gemini/antigravity"
    /// Read by the CLI and its TUI, and loaded by Desktop 2.13.0 (measured 2026-09-12), so one
    /// registration observes both surfaces.
    static let hooksFileRelativeToHome = ".gemini/config/hooks.json"

    nonisolated let agent: AgentKind = .antigravity
    nonisolated let managedDefinitions = [
        ManagedHookDefinition(
            event: AntigravityHookVocabulary.invocationEvent,
            matcher: nil,
            shape: .handlerList,
            argument: AntigravityHookVocabulary.invocationEvent
        ),
        ManagedHookDefinition(
            event: AntigravityHookVocabulary.stopEvent,
            matcher: nil,
            shape: .handlerList,
            argument: AntigravityHookVocabulary.stopEvent
        )
    ]
    nonisolated let legacyCommandMarkers: [String] = []
    /// No wait is ever opened here, so nothing is ever inferred closed.
    nonisolated let reportsApprovalDenials = false
    /// True: ``AntigravityPayloadTranslator`` adds the prompt.
    nonisolated let carriesPromptText = true
    nonisolated let carriesFinalAnswerText = true
    nonisolated let messageDeltaEventName: String? = AntigravityHookVocabulary.modelResponseEvent
    nonisolated let wakesOnToolCallOpened = false
    nonisolated let settlesHeldTurnsFromRecord = false
    nonisolated let restoreDefinitionAdvice =
        "Switch Antigravity off and on in Notchline's settings to write the "
            + "hooks back into ~/\(AntigravityHookVocabulary.hooksFileRelativeToHome)."
    /// Unreachable: no definition selects the helper's long wait.
    nonisolated let answeringTimeoutSeconds = 60 * 60
    nonisolated let answering: (any RequestAnswering)? = nil
    nonisolated let registrationDialect = HookRegistrationDialect(
        containerKey: AntigravityHookVocabulary.containerName,
        handlersAreShellCommandLines: true,
        eventNameArrivesAsArgument: true
    )
    nonisolated let payloadTranslator: (any HookPayloadTranslating)?

    nonisolated init(translator: AntigravityPayloadTranslator = AntigravityPayloadTranslator()) {
        payloadTranslator = translator
    }

    nonisolated init(
        transcripts: any AntigravityTranscriptReading,
        surfaces: AntigravitySurfaceLedger = AntigravitySurfaceLedger()
    ) {
        payloadTranslator = AntigravityPayloadTranslator(transcripts: transcripts, surfaces: surfaces)
    }

    nonisolated func signal(forEvent name: String, toolName: String?) -> HookSignal? {
        switch name {
        case Self.invocationEvent: .turnStarted
        case Self.stopEvent: .turnEnded
        default: nil
        }
    }

    nonisolated func request(
        forEvent name: String,
        toolName: String?,
        toolInput: JSONValue?,
        permissionSuggestions: JSONValue?,
        openedBy toolUseID: String
    ) -> AgentRequest? {
        nil
    }
}

/// Turns the helper's delivery (event-name line, then JSON) into the reducer's payload, and
/// proposes the Turn identity the product does not send
/// (`multi-product-provider-architecture/README.md` §6.1).
///
/// - `PreInvocation` with `invocationNum` 0 opens a Turn, measured on every turn. Later events
///   belong to the open Turn until `Stop`; later invocations never reach the reducer. A `Stop`
///   with no open Turn reuses the last retired id; invocation 0 on an open Turn mints anew.
/// - The prompt is read from the transcript at the boundary; if empty (a race), `Stop` carries it.
/// - A later invocation is the first moment the previous call's words are on disk (1.2.2), so
///   a new step goes out under ``AntigravityHookVocabulary/modelResponseEvent``. `Stop` carries
///   the closing words; a repeated `Stop` repeats them without reading.
/// - Nothing opens or ends on silence, and the file is read only when an event names it.
/// - `antigravity-ide/` transcripts are a sibling product's and declined (``AntigravitySurface``).
///   Desktop 2.13.0 behaves identically, so nothing here branches on surface.
final class AntigravityPayloadTranslator: HookPayloadTranslating, @unchecked Sendable {
    private let lock = NSLock()
    private var openTurnIDs: [String: String] = [:]
    private var lastRetiredTurnIDs: [String: String] = [:]
    /// Turns opened before the prompt was on disk; their `Stop` supplies it.
    private var conversationsAwaitingAPrompt: Set<String> = []
    /// Correctness, not thrift: the preview store joins two deliveries of one message.
    private var lastHandedOverSteps: [String: Int] = [:]
    private var lastRetiredAnswers: [String: String] = [:]
    private let mint: @Sendable () -> String
    private let transcripts: any AntigravityTranscriptReading
    let surfaces: AntigravitySurfaceLedger

    init(
        mint: @escaping @Sendable () -> String = { "local:" + UUID().uuidString.lowercased() },
        transcripts: any AntigravityTranscriptReading = AntigravityTranscriptFile(),
        surfaces: AntigravitySurfaceLedger = AntigravitySurfaceLedger()
    ) {
        self.mint = mint
        self.transcripts = transcripts
        self.surfaces = surfaces
    }

    func canonicalPayload(from body: Data, receivedAt: Date) -> Data? {
        guard let newline = body.firstIndex(of: UInt8(ascii: "\n")) else { return nil }
        let event = String(decoding: body[..<newline], as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        guard !event.isEmpty,
              let object = try? JSONSerialization.jsonObject(
                with: body[body.index(after: newline)...]
              ) as? [String: Any],
              let conversation = object["conversationId"] as? String,
              !conversation.isEmpty else {
            return nil
        }
        let transcript = (object["transcriptPath"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard let surface = AntigravitySurface(transcriptPath: transcript) else {
            return nil
        }
        surfaces.record(surface, forConversation: conversation)

        var canonical: [String: Any] = [
            "hook_event_name": event,
            "session_id": conversation
        ]
        switch event {
        case AntigravityHookVocabulary.invocationEvent:
            let invocation = (object["invocationNum"] as? NSNumber)?.intValue ?? 0
            lock.lock()
            defer { lock.unlock() }
            if invocation != 0, let openTurnID = openTurnIDs[conversation] {
                // A later call of an open Turn: no boundary, and the previous call's words are on disk.
                guard let said = transcript.flatMap({ transcripts.tail(ofTranscriptAt: $0).latestModelText }),
                      lastHandedOverSteps[conversation] != said.step else {
                    return nil
                }
                lastHandedOverSteps[conversation] = said.step
                return try? JSONSerialization.data(withJSONObject: [
                    "hook_event_name": AntigravityHookVocabulary.modelResponseEvent,
                    "session_id": conversation,
                    // The preview store's name for the Turn that is speaking.
                    "prompt_id": openTurnID,
                    "message_id": String(said.step),
                    "delta": said.text
                ])
            }
            let turnID = mint()
            openTurnIDs[conversation] = turnID
            lastHandedOverSteps.removeValue(forKey: conversation)
            canonical["turn_id"] = turnID
            // Prompt only: later words belong to a model call not yet made.
            if let prompt = transcript.flatMap({ transcripts.tail(ofTranscriptAt: $0).latestUserRequest }) {
                canonical["prompt"] = prompt
                conversationsAwaitingAPrompt.remove(conversation)
            } else {
                conversationsAwaitingAPrompt.insert(conversation)
            }
        case AntigravityHookVocabulary.stopEvent:
            lock.lock()
            let hadAnOpenTurn = openTurnIDs[conversation] != nil
            let turnID = openTurnIDs.removeValue(forKey: conversation)
                ?? lastRetiredTurnIDs[conversation]
                ?? mint()
            lastRetiredTurnIDs[conversation] = turnID
            lastHandedOverSteps.removeValue(forKey: conversation)
            let wantsThePrompt = hadAnOpenTurn
                && conversationsAwaitingAPrompt.remove(conversation) != nil
            // A late duplicate `Stop`: read nothing, repeat the original.
            let repeatedAnswer = hadAnOpenTurn ? nil : lastRetiredAnswers[conversation]
            lock.unlock()
            canonical["turn_id"] = turnID
            if hadAnOpenTurn {
                let tail = transcript.map(transcripts.tail(ofTranscriptAt:)) ?? AntigravityTranscriptTail()
                if wantsThePrompt, let prompt = tail.latestUserRequest {
                    canonical["prompt"] = prompt
                }
                let answer = tail.latestModelText?.text
                if let answer {
                    canonical["last_assistant_message"] = answer
                }
                lock.lock()
                lastRetiredAnswers[conversation] = answer
                lock.unlock()
            } else if let repeatedAnswer {
                canonical["last_assistant_message"] = repeatedAnswer
            }
        default:
            // Unregistered: pass on so the reducer reports it as unrecognised.
            lock.lock()
            canonical["turn_id"] = openTurnIDs[conversation]
            lock.unlock()
        }
        if let paths = object["workspacePaths"] as? [String],
           let first = paths.first, !first.isEmpty {
            canonical["cwd"] = first
        }
        if let transcript {
            canonical["transcript_path"] = transcript
        }
        return try? JSONSerialization.data(withJSONObject: canonical)
    }
}
