import Foundation

nonisolated struct CodexHookVocabulary: AgentHookVocabulary {
    /// One hour, as a released notch app registers here.
    nonisolated static let answeringTimeout = 60 * 60
    nonisolated let answeringTimeoutSeconds = CodexHookVocabulary.answeringTimeout
    nonisolated let answering: (any RequestAnswering)? = CodexRequestAnswering()
    /// `updatedInput` is reserved on Codex and fails the hook closed, so questions are answered in
    /// Codex.
    nonisolated func answerOperations(forEvent name: String, toolName: String?) -> AnswerOperations {
        name == answeringEventName ? .decision : .readingOnly
    }
    nonisolated let agent: AgentKind = .codex
    /// The Python helper the first builds registered.
    nonisolated static let legacyHelperMarker = "codex_in_notch_hook.py"
    nonisolated let legacyCommandMarkers = [CodexHookVocabulary.legacyHelperMarker]
    nonisolated let restoreDefinitionAdvice =
        "Run /hooks in Codex and trust the definition again."
    /// A refusal produces no event whatsoever, so it has to be inferred.
    nonisolated let reportsApprovalDenials = false
    nonisolated let carriesPromptText = true
    nonisolated let carriesFinalAnswerText = true
    nonisolated let messageDeltaEventName: String? = nil
    nonisolated let wakesOnToolCallOpened = true
    nonisolated let settlesHeldTurnsFromRecord = true

    /// Append lifecycle definitions to preserve the existing seven trust identities.
    /// `SubagentStart`/`SubagentStop` are the only signal of work in flight after a turn ends.
    nonisolated var managedDefinitions: [ManagedHookDefinition] {
        [
            ManagedHookDefinition(event: "UserPromptSubmit", matcher: nil),
            // Not `PreToolUse`: it fires for every tool call, so every call would wait in the window.
            ManagedHookDefinition(
                event: "PermissionRequest",
                matcher: nil,
                timeoutSeconds: Self.answeringTimeout,
                argument: AgentHookHelper.answeringArgument
            ),
            ManagedHookDefinition(event: "SubagentStart", matcher: nil),
            ManagedHookDefinition(event: "SubagentStop", matcher: nil),
            // Unmatched on purpose: a tool-name matcher makes a naming detail decide whether a wait is
            // seen, silently. `PermissionRequest` has no `tool_use_id`, so the wait borrows the id this
            // catch-all announced, and denial inference needs activity on other calls.
            ManagedHookDefinition(event: "PreToolUse", matcher: nil),
            ManagedHookDefinition(event: "PostToolUse", matcher: nil),
            ManagedHookDefinition(event: "Stop", matcher: nil),
            ManagedHookDefinition(event: "SessionStart", matcher: nil),
            ManagedHookDefinition(event: "SessionEnd", matcher: nil, timeoutSeconds: 3),
            ManagedHookDefinition(event: "Interrupt", matcher: nil, timeoutSeconds: 3)
        ]
    }

    nonisolated func signal(
        forEvent name: String,
        toolName: String?
    ) -> HookSignal? {
        switch (name, toolName) {
        case ("UserPromptSubmit", _):
            .turnStarted
        case ("PermissionRequest", _):
            // No `tool_use_id`, so the wait borrows the call still open.
            .approvalWaitInferred
        case ("PreToolUse", "request_user_input"):
            // The blocking question (measured 2026-09-07, CLI `0.153.4`, Plan mode): its own `call_…` id,
            // and `PostToolUse` lands with the answers.
            .inputWaitOpened
        case ("PreToolUse", "request_user_input_async"):
            // Not a wait. The model picks the handler (2026-09-07, CLI `0.153.4`: `gpt-6-astra` gets
            // this one, `gpt-5.6-sol` the blocking one). `PostToolUse` arrives 51 ms later with
            // `{"accepted":true}` and the Turn keeps working; any answer is a new Turn. The question's
            // words are kept because the model may continue past it (corrected 2026-09-08). An unknown
            // variant falls to the default, which never claims a wait.
            .questionAskedWithoutWaiting
        case ("PreToolUse", "request_permissions"):
            // A Desktop approval prompt: a tool call open exactly as long as the human is asked.
            .approvalWaitOpened
        case ("PreToolUse", _):
            .toolCallOpened
        case ("PostToolUse", _):
            .toolCallClosed
        case ("Stop", _):
            // The main agent's only: `stop.command.input` has no `agent_id`;
            // `subagent-stop.command.input` requires one.
            .turnEnded
        case ("SubagentStart", _):
            .subagentStarted
        case ("SubagentStop", _):
            .subagentStopped
        case ("Interrupt", _):
            .turnInterrupted
        case ("SessionStart", _), ("SessionEnd", _):
            // Ownership is recorded at the boundary; these events cannot create a Turn.
            .inert
        default:
            nil
        }
    }

    /// Codex asks in two shapes. `request_user_input` carries `{"questions":[…]}`, the shape
    /// ``AgentRequestReading/questions(in:)`` reads for `AskUserQuestion` (measured 2026-09-07,
    /// CLI `0.153.4`): form 03 with options, 04 without. Top-level text readings stay as a
    /// fallback. Everything else is a command to grant, drawn verbatim.
    /// - Parameter permissionSuggestions: unread; `updatedPermissions` is reserved here and fails
    ///   the hook closed.
    nonisolated func request(
        forEvent name: String,
        toolName: String?,
        toolInput: JSONValue?,
        permissionSuggestions _: JSONValue?,
        openedBy toolUseID: String
    ) -> AgentRequest? {
        guard let toolInput else { return nil }
        let form: AgentRequest.Form? = switch (name, toolName) {
        case ("PreToolUse", "request_user_input"), ("PreToolUse", "request_user_input_async"):
            // Question set, then prompt text, then the whole arguments: fail closed to the arguments.
            AgentRequestReading.questions(in: toolInput).map { .questions($0) }
                ?? (AgentRequestReading.text("question", in: toolInput)
                    ?? AgentRequestReading.text("prompt", in: toolInput))
                .map { .question($0) }
                ?? AgentRequestReading.arguments(of: toolInput).map { .command($0) }
        default:
            AgentRequestReading.arguments(of: toolInput).map { .command($0) }
        }
        return form.map {
            AgentRequest(
                id: toolUseID, toolName: toolName, form: $0,
                argumentFields: $0.name == "command" ? AgentRequestReading.approvalFields(in: toolInput) : []
            )
        }
    }
}

/// Codex's `permission-request.command.output`: approval only. `0.151.x` reserves `interrupt`,
/// `updatedInput` and `updatedPermissions`, failing the hook closed (§11 rule 06).
nonisolated struct CodexRequestAnswering: RequestAnswering {
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
        case .answers:
            // `updatedInput` fails the hook closed, worse than saying nothing.
            return nil
        }
    }

    private static func encode(_ decision: [String: JSONValue]) -> Data? {
        AgentHookOutput.encode(
            eventName: "PermissionRequest",
            fields: ["decision": .object(decision)]
        )
    }
}
