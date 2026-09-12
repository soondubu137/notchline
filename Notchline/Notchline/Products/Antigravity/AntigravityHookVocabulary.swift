import Foundation

/// How Antigravity spells its lifecycle events, and what it does not spell.
///
/// One vocabulary for both of the product's surfaces, the CLI and Desktop,
/// because they are one engine reading one hooks file and sending one payload
/// shape (``AntigravityPayloadTranslator``, `antigravity-desktop.md`).
/// Measured 2026-09-11 against `agy` 1.2.2, in print mode and in the
/// interactive TUI, through a hooks file of this app's own
/// (`docs/technical-explorations/multi-product-provider-architecture/antigravity-cli.md`),
/// and re-measured for Desktop 2.13.0 on 2026-09-12:
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
///   until 2026-09-12, on the reading that a lifecycle-only row is what the hooks
///   alone can say; what overturned that is that the file is *named by the
///   payload*, so reading it needs no discovery, no watcher and no guess, and
///   an `Untitled` row is the one thing that made a list of three rows
///   unusable.
/// - **Nor is anything the model says**, so a row's live line is read out of
///   the same file, at the two events that already arrive once a model call's
///   words are on disk: the turn's next `PreInvocation` and its `Stop`. See
///   ``AntigravityPayloadTranslator``.
/// - `workspacePaths` names the workspace in the TUI and in Desktop and is
///   empty under `-p`, so a print-mode row is an `Untitled folder`.
/// - Nothing observes a wait. `PreToolUse` fires before a tool runs whether
///   or not a person is then asked, and a headless auto-denial fires nothing
///   at all; the product's permission decisions are the hook's *output*, a
///   write path this app does not take. So waits and requests are unsupported; the context and progress
///   sources give **L3** (`docs/product-support.md` §5). Settings declares
///   the missing wait detection rather than claiming work is confirmed.
///
/// Two of the five are registered, and the other three would buy nothing.
/// `PostInvocation` fires only once the call's tools have returned — measured
/// 2026-09-12, 10.3 s after the words it follows reached the transcript, around
/// a `sleep` awaiting approval — and the next `PreInvocation` fires 30 ms after
/// it, so it is no earlier an edge than one already registered. `PreToolUse`
/// would be earlier, and it is a write path: a handler answering `{}` had every
/// tool call of the turn refused (`antigravity-cli.md` §2.2). `PostToolUse`
/// never fired.
nonisolated struct AntigravityHookVocabulary: AgentHookVocabulary {
    static let invocationEvent = "PreInvocation"
    static let stopEvent = "Stop"
    /// The name the translator gives a model response it read, which the
    /// product never sends and nothing registers: it exists so the words reach
    /// the reducer's preview store the way a streamed message does, and never
    /// the reducer itself. Named for the transcript step it is read from.
    static let modelResponseEvent = "PlannerResponse"
    /// The name this app's definitions sit under at the root of the shared
    /// hooks file, beside whatever named hooks the user keeps there.
    static let containerName = "notchline"
    /// The directory the CLI's own files live in, under the user's home.
    static let stateDirectoryRelativeToHome = ".gemini/antigravity-cli"
    /// The directory Antigravity Desktop's own files live in, under the user's
    /// home: its transcripts, its read records and its conversation summaries.
    static let desktopStateDirectoryRelativeToHome = ".gemini/antigravity"
    /// The hooks file the CLI reads at launch, shared with its TUI's `/hooks`
    /// command (its 1.2.x changelog names it as the one file both read), and
    /// the global customization root's hooks file Desktop loads too (measured
    /// 2026-09-12 on 2.13.0; its embedded guide names `~/.gemini/config/` as
    /// that root). One registration therefore observes both surfaces.
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
    /// True for the same reason: the translator reads the turn's closing words
    /// at its `Stop` and puts them where Codex's `Stop` carries its own.
    nonisolated let carriesFinalAnswerText = true
    /// Every model response the translator read mid-turn arrives as one whole
    /// message under this name, which the reducer folds into the row's live
    /// line without reducing anything.
    nonisolated let messageDeltaEventName: String? = AntigravityHookVocabulary.modelResponseEvent
    nonisolated let wakesOnToolCallOpened = false
    nonisolated let settlesHeldTurnsFromRecord = false
    nonisolated let restoreDefinitionAdvice =
        "Switch Antigravity off and on in Notchline's settings to write the "
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
    /// test that writes the file the prompt is read out of, recording surfaces
    /// in the ledger the test's other sources read.
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
/// is not a boundary and never reaches the reducer; a `Stop` for a
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
/// its `Stop` — where the step is on disk beyond any doubt — carries the
/// prompt its own read finds. The reducer fills a blank title from a late
/// prompt and never overwrites one, and a Turn that was named at its boundary
/// is handed no prompt at its end at all.
///
/// **The row's live line, read at the same two edges.** A later invocation of
/// an open Turn is not a boundary, and it is the first moment the previous
/// model call's words are certainly on disk: measured 2026-09-12 against 1.2.2,
/// the step is written whole when the call finishes, the call's tools run, and
/// only then does `PostInvocation` fire, with the next `PreInvocation` 30 ms
/// behind it — the transcript held the step at all seven later invocations and
/// both `Stop`s of the two turns measured.
/// So that invocation reads the file and, when the newest words are a step it
/// has not handed over yet, hands them over as one whole message under
/// ``AntigravityHookVocabulary/modelResponseEvent``, scoped to the open Turn;
/// otherwise it is dropped exactly as before. `Stop` puts the turn's closing
/// words under `last_assistant_message` in the same single read that settles a
/// late prompt, and a repeated `Stop` carries the words its original carried
/// rather than reading again, so it cannot blank a finished row.
///
/// The ceiling is the product's: words written before a tool call reach the row
/// once that tool has returned, which is late for a long command and, above
/// all, for one waiting on the user's approval.
///
/// **What it is not.** It is not a guess about state: it opens nothing on
/// silence and ends nothing on silence. The one file it reads is read only
/// because an event named it, never on a timer and never to decide whether
/// something is running. A launch mid-turn sees a later invocation with no
/// open Turn and starts one from that moment, which is the same late start the
/// reducer gives any product whose first event this app saw was not the first
/// it sent.
///
/// **Whose events.** The hooks file is shared by every surface of the
/// product's engine, which the documentation says write their transcripts
/// under `antigravity-cli/` (the CLI), `antigravity/` (Antigravity Desktop,
/// which the guide calls 2.0) and `antigravity-ide/`. The first two are this
/// product's and are told apart by that directory alone
/// (``AntigravitySurface``), which is recorded in the ledger every source that
/// has to treat the two differently reads; the IDE's is a sibling product's
/// and is declined, so it is neither drawn nor counted as unreadable.
///
/// **Desktop's events are the CLI's, measured.** Antigravity Desktop 2.13.0
/// runs the same engine in one long-lived `language_server` and loads the
/// same `~/.gemini/config/hooks.json` — measured 2026-09-12 by the
/// registration this app had already written for the CLI firing, unchanged,
/// for Desktop turns: the same five common fields with `workspacePaths`
/// filled, `invocationNum` 0 opening every turn, `Stop` closing it, and the
/// user's step and the model's words in a transcript of the same shape. So
/// nothing above branches on the surface.
final class AntigravityPayloadTranslator: HookPayloadTranslating, @unchecked Sendable {
    private let lock = NSLock()
    /// The local Turn id open on each conversation this process has seen.
    private var openTurnIDs: [String: String] = [:]
    /// The id each conversation's last `Stop` retired, for the duplicate that
    /// arrives after it.
    private var lastRetiredTurnIDs: [String: String] = [:]
    /// The conversations whose open Turn was opened without a prompt, because
    /// the transcript had not been written that far yet. Their `Stop` takes
    /// the prompt from its read; every other conversation's leaves it.
    private var conversationsAwaitingAPrompt: Set<String> = []
    /// The step whose words were last handed over for each conversation's open
    /// Turn, so a later invocation that finds no newer words hands over none.
    /// The preview store joins two deliveries of one message onto each other,
    /// so this is correctness and not only thrift.
    private var lastHandedOverSteps: [String: Int] = [:]
    /// The closing words each conversation's last `Stop` carried, for the
    /// duplicate that arrives after it.
    private var lastRetiredAnswers: [String: String] = [:]
    private let mint: @Sendable () -> String
    private let transcripts: any AntigravityTranscriptReading
    /// Which surface each accepted conversation's events came from.
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
                // The Turn is open and this is a later model call of it: no
                // boundary, and the previous call's words are on disk.
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
            // Read under the lock, and only for the prompt here: the words
            // after it belong to a model call that has not happened yet.
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
            // The second read for a prompt is owed only to a Turn that opened
            // without one.
            let wantsThePrompt = hadAnOpenTurn
                && conversationsAwaitingAPrompt.remove(conversation) != nil
            // A `Stop` that reuses a retired id is a late duplicate of a Turn
            // already named and already answered, so it reads nothing and
            // repeats what the original carried.
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
