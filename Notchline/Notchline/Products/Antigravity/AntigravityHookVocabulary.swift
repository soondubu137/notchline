import Foundation

/// How Antigravity CLI spells its lifecycle events, and what it does not spell.
///
/// Measured 2026-09-11 against `agy` 1.2.2, in print mode and in the
/// interactive TUI, through a hooks file of this app's own
/// (`docs/technical-explorations/multi-product-provider-architecture/antigravity-cli.md`):
///
/// - Five events exist — `PreToolUse`, `PostToolUse`, `PreInvocation`,
///   `PostInvocation`, `Stop` — and every payload carries the same fields:
///   `conversationId`, `workspacePaths`, `transcriptPath`,
///   `artifactDirectoryPath`, `modelName`. **None carries the event's name**,
///   so the registration hands the helper the name as its argument and the
///   helper writes it ahead of the payload (``HookRegistrationDialect``).
/// - **There is no Turn id.** `PreInvocation` fires once per model call with
///   `invocationNum` counting from 0 inside a turn, and `Stop` fires once at
///   the turn's end with `executionNum` — which read 0 on every turn measured,
///   so it does not count turns. The first invocation of a turn is the one
///   unambiguous submission boundary, and ``AntigravityPayloadTranslator``
///   proposes a local Turn identity there and retires it on `Stop`.
/// - The prompt is not in any payload, so a row is `Untitled` at this tier.
/// - `workspacePaths` names the workspace in the TUI and is empty under `-p`,
///   so a print-mode row is an `Untitled folder`.
/// - Nothing observes a wait. `PreToolUse` fires before a tool runs whether
///   or not a person is then asked, and a headless auto-denial fires nothing
///   at all; the product's permission decisions are the hook's *output*, a
///   write path this app does not take. So the product is **Tier 0**, and
///   Settings says so (`tiered-support.md` §2).
///
/// Two of the five are registered. `PostInvocation` and the tool events would
/// cost a process each with nothing a Tier 0 row could draw from them.
nonisolated struct AntigravityHookVocabulary: AgentHookVocabulary {
    static let invocationEvent = "PreInvocation"
    static let stopEvent = "Stop"
    /// The name this app's definitions sit under at the root of the shared
    /// hooks file, beside whatever named hooks the user keeps there.
    static let containerName = "notchline"
    /// The directory the CLI's own files live in, under the user's home.
    static let stateDirectoryRelativeToHome = ".gemini/antigravity-cli"
    /// The hooks file the CLI reads at launch, shared with its TUI's `/hooks`
    /// command (its 1.2.x changelog names it as the one file both read).
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
    nonisolated let carriesPromptText = false
    nonisolated let carriesFinalAnswerText = false
    nonisolated let messageDeltaEventName: String? = nil
    nonisolated let wakesOnToolCallOpened = false
    nonisolated let settlesHeldTurnsFromRecord = false
    nonisolated let restoreDefinitionAdvice =
        "Switch Antigravity CLI off and on in Notchline's settings to write the "
            + "hooks back into ~/\(AntigravityHookVocabulary.hooksFileRelativeToHome)."
    /// No definition selects the helper's long wait — `answering` is nil and
    /// no argument is the word `wait` — so this only keeps that unreachable
    /// branch of the helper well-formed. Codex's hour, for no better reason.
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

/// Turns what Antigravity CLI's helper delivers into the payload the reducer
/// reads, and proposes the Turn identity the product does not send.
///
/// **What arrives.** One line naming the event, then the product's JSON as it
/// was written to the helper's stdin. Keys are camelCase; the conversation is
/// `conversationId`; the workspace, where there is one, is `workspacePaths[0]`.
///
/// **The local Turn identity, and why it is allowed.** The rule
/// (`multi-product-provider-architecture/README.md` §6.1) is that a Provider
/// may propose a local id only at an unambiguous submission boundary, with a
/// demonstrated way to associate later events and to reject duplicates. The
/// boundary is `PreInvocation` with `invocationNum` 0 — measured to open
/// every turn, in both modes, and to read 0 again on the next turn of the same
/// conversation. Association is the conversation's one open Turn: a
/// conversation runs one execution at a time, and every later event of it
/// belongs to that Turn until its `Stop`. A later invocation of an open Turn
/// is not a boundary and is dropped here rather than reduced; a `Stop` for a
/// conversation with no open Turn reuses the id it last retired, so a repeated
/// `Stop` is the late duplicate the reducer already ignores; and a first
/// invocation while a Turn is still open — a `Stop` this app never received —
/// mints anew, which the reducer holds and then redeems on the new Turn's own
/// `Stop`, exactly as it does for the product whose refusals abort a turn
/// without a hook.
///
/// **What it is not.** It is not a guess about state: it opens nothing on
/// silence, ends nothing on silence, and reads no file. A launch mid-turn
/// sees a later invocation with no open Turn and starts one from that moment,
/// which is the same late start the reducer gives any product whose first
/// event this app saw was not the first it sent.
///
/// **Whose events.** The hooks file is shared with the product's other
/// surfaces, which the documentation says write their transcripts under
/// `antigravity/` and `antigravity-ide/` where the CLI writes under
/// `antigravity-cli/`; a payload naming one of those is a sibling product's
/// and is declined, so it is neither drawn nor counted as unreadable.
final class AntigravityPayloadTranslator: HookPayloadTranslating, @unchecked Sendable {
    private let lock = NSLock()
    /// The local Turn id open on each conversation this process has seen.
    private var openTurnIDs: [String: String] = [:]
    /// The id each conversation's last `Stop` retired, for the duplicate that
    /// arrives after it.
    private var lastRetiredTurnIDs: [String: String] = [:]
    private let mint: @Sendable () -> String

    init(mint: @escaping @Sendable () -> String = { "local:" + UUID().uuidString.lowercased() }) {
        self.mint = mint
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
        let transcript = object["transcriptPath"] as? String
        if let transcript, !transcript.isEmpty,
           !transcript.contains("/\(AntigravityHookVocabulary.stateDirectoryRelativeToHome.split(separator: "/").last!)/") {
            return nil
        }

        var canonical: [String: Any] = [
            "hook_event_name": event,
            "session_id": conversation
        ]
        switch event {
        case AntigravityHookVocabulary.invocationEvent:
            let invocation = (object["invocationNum"] as? NSNumber)?.intValue ?? 0
            lock.lock()
            defer { lock.unlock() }
            if invocation != 0, let open = openTurnIDs[conversation] {
                // The Turn is open and this is a later model call of it.
                _ = open
                return nil
            }
            let turnID = mint()
            openTurnIDs[conversation] = turnID
            canonical["turn_id"] = turnID
        case AntigravityHookVocabulary.stopEvent:
            lock.lock()
            defer { lock.unlock() }
            let turnID = openTurnIDs.removeValue(forKey: conversation)
                ?? lastRetiredTurnIDs[conversation]
                ?? mint()
            lastRetiredTurnIDs[conversation] = turnID
            canonical["turn_id"] = turnID
        default:
            // Not registered by this app; handed on under the open Turn, if
            // any, so the reducer reports it as unrecognised rather than
            // this type hiding it.
            lock.lock()
            canonical["turn_id"] = openTurnIDs[conversation]
            lock.unlock()
        }
        if let paths = object["workspacePaths"] as? [String],
           let first = paths.first, !first.isEmpty {
            canonical["cwd"] = first
        }
        if let transcript, !transcript.isEmpty {
            canonical["transcript_path"] = transcript
        }
        return try? JSONSerialization.data(withJSONObject: canonical)
    }
}
