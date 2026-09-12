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
/// - **The prompt is in no payload**, so it is read out of the transcript the
///   payload names — see ``AntigravityTranscriptFile``. It was `Untitled`
///   until 2026-09-12, on the reading that a Tier 0 row is what the hooks
///   alone can say; what overturned that is that the file is *named by the
///   payload*, so reading it needs no discovery, no watcher and no guess, and
///   an `Untitled` row is the one thing that made a list of three rows
///   unusable.
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
    /// True although no payload carries a prompt: ``AntigravityPayloadTranslator``
    /// puts one on the canonical payload, and this is the reducer's switch for
    /// reading it.
    nonisolated let carriesPromptText = true
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

    /// The vocabulary with a transcript reader of the caller's choosing, for a
    /// test that writes the file the prompt is read out of.
    nonisolated init(transcripts: any AntigravityTranscriptReading) {
        payloadTranslator = AntigravityPayloadTranslator(transcripts: transcripts)
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
/// **The prompt, which is read rather than received.** No payload carries it,
/// so on the boundary above this asks ``AntigravityTranscriptReading`` for the
/// conversation's last user request and puts it on the canonical payload under
/// `prompt`, where the reducer already looks. The file is the one the payload
/// itself names, so nothing is searched for and nothing is watched.
///
/// **And read a second time if the first was too early.** The user's step is
/// appended before the first model call in every turn measured, but that is a
/// race this app does not control and could not measure through the product's
/// own hooks. So a Turn whose first read came back empty is remembered, and
/// its `Stop` — where the step is on disk beyond any doubt — reads again and
/// carries the prompt then. The reducer fills a blank title from a late
/// prompt and never overwrites one, so the second read costs nothing when the
/// first succeeded, and it is skipped entirely in that case.
///
/// **What it is not.** It is not a guess about state: it opens nothing on
/// silence and ends nothing on silence. The one file it reads is read only
/// because an event named it, never on a timer and never to decide whether
/// something is running. A launch mid-turn sees a later invocation with no
/// open Turn and starts one from that moment, which is the same late start the
/// reducer gives any product whose first event this app saw was not the first
/// it sent.
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
    /// The conversations whose open Turn was opened without a prompt, because
    /// the transcript had not been written that far yet. Their `Stop` reads
    /// again; every other conversation's does not.
    private var conversationsAwaitingAPrompt: Set<String> = []
    private let mint: @Sendable () -> String
    private let transcripts: any AntigravityTranscriptReading

    init(
        mint: @escaping @Sendable () -> String = { "local:" + UUID().uuidString.lowercased() },
        transcripts: any AntigravityTranscriptReading = AntigravityTranscriptFile()
    ) {
        self.mint = mint
        self.transcripts = transcripts
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
        if let transcript,
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
            if invocation != 0, openTurnIDs[conversation] != nil {
                // The Turn is open and this is a later model call of it.
                return nil
            }
            let turnID = mint()
            openTurnIDs[conversation] = turnID
            canonical["turn_id"] = turnID
            // Read under the lock, and only here. A turn's later model calls
            // reach the line above and stop there, so a seven-tool turn reads
            // the transcript once and not eight times -- which is the whole
            // reason this is inside the branch rather than ahead of it.
            if let prompt = transcript.flatMap(transcripts.latestUserRequest(inTranscriptAt:)) {
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
            // The second read is owed only to a Turn that opened without a
            // prompt. A `Stop` that reuses a retired id is a late duplicate of
            // a Turn already named, so it is owed nothing.
            let readsAgain = hadAnOpenTurn
                && conversationsAwaitingAPrompt.remove(conversation) != nil
            lock.unlock()
            canonical["turn_id"] = turnID
            if readsAgain,
               let prompt = transcript.flatMap(transcripts.latestUserRequest(inTranscriptAt:)) {
                canonical["prompt"] = prompt
            }
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
        if let transcript {
            canonical["transcript_path"] = transcript
        }
        return try? JSONSerialization.data(withJSONObject: canonical)
    }
}
