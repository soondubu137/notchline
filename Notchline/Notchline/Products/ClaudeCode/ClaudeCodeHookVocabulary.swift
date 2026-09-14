import Foundation

/// Claude Code's spelling of the same lifecycle. Measured against CLI 2.1.233 on 2026-08-16.
nonisolated struct ClaudeCodeHookVocabulary: AgentHookVocabulary {
    /// Twenty-four hours, as a released notch app registers here. No trust hash on this side, so
    /// a wrong value is one settings write from right (ADR 0016).
    nonisolated static let answeringTimeout = 24 * 60 * 60
    nonisolated let answeringTimeoutSeconds = ClaudeCodeHookVocabulary.answeringTimeout
    nonisolated let answering: (any RequestAnswering)? = ClaudeCodeRequestAnswering()
    /// A decision on every `PermissionRequest` except `AskUserQuestion`'s, which takes answers via
    /// `updatedInput` only: a `deny` there would block the tool rather than answer the person.
    nonisolated func answerOperations(forEvent name: String, toolName: String?) -> AnswerOperations {
        guard name == answeringEventName else { return .readingOnly }
        return toolName == Self.inputToolName ? .questionAnswers : .decision
    }
    nonisolated let agent: AgentKind = .claudeCode
    /// The pre-ADR-0013 `http` handler path, still recognised so it is stripped and proven gone.
    nonisolated static let legacyHookPath = "/codex-in-notch/hook"
    nonisolated let legacyCommandMarkers = [ClaudeCodeHookVocabulary.legacyHookPath]
    /// ADR 0016: this app writes that file, so the repair is a switch.
    nonisolated let restoreDefinitionAdvice =
        "Switch Claude Code off and on in Notchline's settings to write the "
            + "hooks back into ~/.claude/settings.json."
    /// `PermissionDenied` fires only for the auto-mode classifier (one emit site, gated on
    /// `decisionReason.classifier == "auto-mode"`; measured 2026-08-23, CLI 2.1.241). A human's
    /// refusal aborts the turn with no hook, so a borrowed wait needs the same rescue as Codex.
    /// A `Stop` before its subagent's `PermissionRequest` is an async subagent, not disorder;
    /// the two land in different slots (``ProducerWaits``).
    nonisolated let reportsApprovalDenials = false
    nonisolated let carriesPromptText = true
    /// PRD §7: assistant text comes from `MessageDisplay`, so `Stop`'s copy is not read.
    nonisolated let carriesFinalAnswerText = false
    nonisolated let messageDeltaEventName: String? = Self.messageDisplayEventName
    /// The fold carries its own edge; a tool call would wake the panel twice.
    nonisolated let wakesOnToolCallOpened = false
    /// No rollout and no unmarked nested agent, so the first event under a held prompt's id
    /// redeems it. See ``AgentHookVocabulary/settlesHeldTurnsFromRecord``.
    nonisolated let settlesHeldTurnsFromRecord = false

    static let inputToolName = "AskUserQuestion"
    /// Set as prose: `answer-in-notch.md` §4.2 decides by payload source, never length, so this
    /// has to be a name.
    static let planToolName = "ExitPlanMode"

    /// The only event that carries assistant text ("While assistant message text is displayed").
    static let messageDisplayEventName = "MessageDisplay"

    nonisolated var managedDefinitions: [ManagedHookDefinition] {
        [
            ManagedHookDefinition(event: "UserPromptSubmit", matcher: nil),
            ManagedHookDefinition(event: "PreToolUse", matcher: nil),
            ManagedHookDefinition(event: "PostToolUse", matcher: nil),
            ManagedHookDefinition(event: "PostToolUseFailure", matcher: nil),
            // The answer-carrying definition; here `allow` accepts `updatedInput`, so it also carries a
            // question's answers.
            ManagedHookDefinition(
                event: "PermissionRequest",
                matcher: nil,
                timeoutSeconds: Self.answeringTimeout,
                argument: AgentHookHelper.answeringArgument
            ),
            ManagedHookDefinition(event: "PermissionDenied", matcher: nil),
            ManagedHookDefinition(event: "Elicitation", matcher: nil),
            ManagedHookDefinition(event: "ElicitationResult", matcher: nil),
            // A turn can end with its subagent still working (measured 2026-08-23, CLI 2.1.241:
            // `SubagentStart` after the parent's `PostToolUse`, `Stop` with `background_tasks` running,
            // `SubagentStop` after `Stop`); without these the row says Completed early. No `agent_type`
            // matcher: a miss would be silent.
            ManagedHookDefinition(event: "SubagentStart", matcher: nil),
            ManagedHookDefinition(event: "SubagentStop", matcher: nil),
            // The row's third line (CC-015).
            ManagedHookDefinition(event: "MessageDisplay", matcher: nil),
            ManagedHookDefinition(event: "Stop", matcher: nil),
            ManagedHookDefinition(event: "StopFailure", matcher: nil)
            // Not registered (CC-011, measured 2.1.238):
            // - `Notification`: `permission_prompt` fires on a 6 s idle timer after `PermissionRequest`,
            //   with no `tool_use_id`, and nothing closes it. `idle_prompt` arrives 60 s after `Stop`,
            //   when the turn is already Completed. `agent_needs_input`/`agent_completed` carry the
            //   current session's id, not the agent's. The mapping stays for older registrations.
            // - `SessionEnd`: the `~/.claude/sessions/<pid>.json` removal lands ~330 ms first (2.1.237).
            //   `/clear` and `resume` change the session id, so `claude agents --json` drops it at once.
            //   Its `matcher` selects on `reason` (`clear`, `resume`, `logout`, `prompt_input_exit`,
            //   `other`).
        ]
    }

    nonisolated func signal(
        forEvent name: String,
        toolName: String?
    ) -> HookSignal? {
        switch (name, toolName) {
        case ("UserPromptSubmit", _):
            // `source` was measured absent from every event; the working directory separates a human's
            // prompt from our own polling.
            .turnStarted
        case ("PreToolUse", Self.inputToolName):
            .inputWaitOpened
        case ("PreToolUse", _):
            .toolCallOpened
        case ("PermissionRequest", _):
            // No `tool_use_id` (measured), so the wait borrows the call still open.
            .approvalWaitInferred
        case ("PostToolUse", _), ("PostToolUseFailure", _), ("PermissionDenied", _):
            .toolCallClosed
        case ("Elicitation", _):
            .inputWaitOpened
        case ("ElicitationResult", _):
            .toolCallClosed
        case ("SubagentStart", _):
            .subagentStarted
        case ("SubagentStop", _):
            // Never the terminal: its `last_assistant_message` is the subagent's.
            .subagentStopped
        case ("Notification", _):
            // Not registered; consumed so an older registration raises no diagnostic per notification.
            .inert
        case (Self.messageDisplayEventName, _):
            // Folded into the preview before the reducer (``messageDeltaEventName``); the case exists
            // so a registered event is not reported as unrecognised.
            .inert
        case ("Stop", _), ("StopFailure", _):
            // One terminal. Failure is a reason, never a state: Codex cannot report failure at all.
            .turnEnded
        default:
            nil
        }
    }

    /// Claude Code asks in three shapes:
    /// - `AskUserQuestion`: a set of one to four questions, arriving on `PreToolUse` and again on
    ///   its `PermissionRequest`; both read to the same form.
    /// - `ExitPlanMode`: a document, read as prose.
    /// - Everything else: a command to grant.
    ///
    /// An `Elicitation` is named and not drawn (§2.2): its fields are the MCP server's own.
    nonisolated func request(
        forEvent name: String,
        toolName: String?,
        toolInput: JSONValue?,
        permissionSuggestions: JSONValue?,
        openedBy toolUseID: String
    ) -> AgentRequest? {
        // Needs no arguments: the row still says a person is wanted and where to answer.
        if name == "Elicitation" {
            return AgentRequest(id: toolUseID, toolName: toolName, form: .unsupported)
        }
        let offeredRules = AgentRequestReading.offeredRules(in: permissionSuggestions)
        guard let toolInput else { return nil }
        let form: AgentRequest.Form? = switch toolName {
        case Self.inputToolName:
            // Notes are this product's `annotations`, keyed like its answers.
            AgentRequestReading.questions(in: toolInput, acceptingNotes: true).map { .questions($0) }
                ?? AgentRequestReading.arguments(of: toolInput).map { .command($0) }
        case Self.planToolName:
            // Fails closed to the arguments, never to an empty body.
            AgentRequestReading.text("plan", in: toolInput).map { .document($0) }
                ?? AgentRequestReading.arguments(of: toolInput).map { .command($0) }
        default:
            AgentRequestReading.arguments(of: toolInput).map { .command($0) }
        }
        return form.map {
            AgentRequest(
                id: toolUseID,
                toolName: toolName,
                form: $0,
                argumentFields: $0.name == "command" ? AgentRequestReading.approvalFields(in: toolInput) : [],
                offeredRules: offeredRules
            )
        }
    }
}

/// Claude Code's `PermissionRequest` output, measured on 2.1.261 (2026-09-05): a late `allow`
/// dismisses the product's dialogue; a `deny` `message` reaches the model as the tool's error.
nonisolated struct ClaudeCodeRequestAnswering: RequestAnswering {
    /// `AskUserQuestion`'s answers field, keyed by question text; `updatedInput` is its designed path.
    static let answersKey = "answers"
    static let annotationsKey = "annotations"

    nonisolated func hookOutput(
        for answer: AgentAnswer,
        updating input: JSONValue?
    ) -> Data? {
        switch answer {
        case .grant:
            return Self.encode(["behavior": .string("allow")])
        case let .refuse(message):
            return Self.encode(
                message.map { ["behavior": .string("deny"), "message": .string($0)] }
                    ?? ["behavior": .string("deny")]
            )
        case let .answers(answers):
            // `updatedInput` replaces the tool's input, so never answer into an input this app did not see.
            guard case let .object(fields)? = input else { return nil }
            // Refuse rather than send the part that fits: half an answer is a different answer.
            var spelled: [(String, String)] = []
            for answered in answers {
                guard answered.fitsItsQuestion, let text = Self.spelling(of: answered) else {
                    return nil
                }
                spelled.append((answered.question.text, text))
            }
            var updated = fields
            // Keyed by question text per the product's schema; identical questions collapse, later wins.
            updated[Self.answersKey] = .object(
                Dictionary(
                    spelled.map { ($0.0, JSONValue.string($0.1)) },
                    uniquingKeysWith: { _, last in last }
                )
            )
            let notes = answers.compactMap { answered -> (String, JSONValue)? in
                guard let note = answered.note, !note.isEmpty else { return nil }
                return (answered.question.text, .object(["notes": .string(note)]))
            }
            if !notes.isEmpty {
                updated[Self.annotationsKey] = .object(
                    Dictionary(notes, uniquingKeysWith: { _, last in last })
                )
            }
            return Self.encode([
                "behavior": .string("allow"),
                "updatedInput": .object(updated)
            ])
        }
    }

    /// Chosen labels joined with `", "` in the product's order (§5.5), or the typed words (§5.4).
    nonisolated static func spelling(of answered: AgentQuestionAnswer) -> String? {
        guard let chosen = answered.selectedOptions else { return nil }
        if !chosen.isEmpty {
            return chosen.map(\.label).joined(separator: ", ")
        }
        let typed = answered.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return typed.isEmpty ? nil : typed
    }

    private static func encode(_ decision: [String: JSONValue]) -> Data? {
        AgentHookOutput.encode(
            eventName: "PermissionRequest",
            fields: ["decision": .object(decision)]
        )
    }
}
