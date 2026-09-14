import Foundation

/// How complete this app's registration is, read only from the product's own hooks file.
/// Whether Codex runs the hooks is a separate fact (``IntegrationSetupStatus``).
nonisolated enum HookRegistration: Sendable, Equatable {
    case absent
    case unreadable
    /// Something of this app's is registered, but not what this build needs (partial, older, or
    /// Python-era). Repair is offered so a second registration is not added beside it.
    case mismatched
    /// Exactly one current definition per managed event, and nothing else.
    case complete
}

/// What the settings card says, projected here and nowhere else from registration (a file)
/// and delivery (arriving events).
enum IntegrationSetupStatus: Equatable, Sendable {
    case notRequired
    case unreadable
    case notInstalled
    case repairRequired
    case reviewRequired
    case active

    nonisolated static func card(
        registration: HookRegistration,
        hasObservedEvent: Bool
    ) -> IntegrationSetupStatus {
        switch registration {
        case .unreadable:
            .unreadable
        case .absent:
            .notInstalled
        case .mismatched:
            .repairRequired
        case .complete:
            hasObservedEvent ? .active : .reviewRequired
        }
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.unreadable, .unreadable),
             (.notRequired, .notRequired),
             (.notInstalled, .notInstalled),
             (.repairRequired, .repairRequired),
             (.reviewRequired, .reviewRequired),
             (.active, .active):
            true
        default:
            false
        }
    }

    var displayName: String {
        switch self {
        case .unreadable:
            "Unable to check setup"
        case .notRequired:
            "No setup required"
        case .notInstalled:
            "Not installed"
        case .repairRequired:
            "Setup needs repair"
        case .reviewRequired:
            "Set up; not yet verified"
        case .active:
            "Connected"
        }
    }

    nonisolated var isIntegrationEnabled: Bool {
        switch self {
        case .reviewRequired, .active:
            true
        case .unreadable, .notRequired, .notInstalled, .repairRequired:
            false
        }
    }
}

/// `nonisolated` as ``PendingApproval``: a `Sendable` bag of URLs read off the main actor.
nonisolated struct HookIntegrationPaths: Sendable {
    /// The app's own directory, shared by every product.
    let supportDirectory: URL
    let hooksConfiguration: URL
    let agent: AgentKind

    nonisolated init(
        supportDirectory: URL,
        hooksConfiguration: URL,
        agent: AgentKind = .codex
    ) {
        self.supportDirectory = supportDirectory
        self.hooksConfiguration = hooksConfiguration
        self.agent = agent
    }

    /// Everything belonging to one product, and nothing belonging to another. Kept short: a Unix
    /// domain socket path may not exceed 104 bytes.
    var agentDirectory: URL {
        supportDirectory
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent(agent.rawValue, isDirectory: true)
    }

    /// The folder this app's own quota reading runs in. One definition: the reading, the session
    /// registry and the hook store must agree on it exactly.
    var quotaWorkingDirectory: URL {
        agentDirectory.appendingPathComponent("usage", isDirectory: true)
    }

    /// The helper the product runs once per event.
    var hookHelper: URL {
        agentDirectory.appendingPathComponent("hook.sh")
    }

    /// Where that helper hands one payload to a running app.
    var hookSocket: URL {
        agentDirectory.appendingPathComponent("hook.sock")
    }

    /// The one file this integration keeps on disk. Only ``HookInstallRecord/lastEventAt`` is
    /// read back, so after a restart the card does not ask a user to trust the hooks again.
    var installState: URL {
        agentDirectory.appendingPathComponent("install.json")
    }

    /// Files an install made before this design left behind: a delete list for repair and
    /// uninstall, never read or branched on.
    var retiredArtifacts: [URL] {
        [
            "codex_in_notch_hook.py",
            "events",
            "monitor-state.json",
            "managed-install.json",
            "hook-settings.json",
            "preview.sock"
        ].map { agentDirectory.appendingPathComponent($0) }
            + [
                "codex_in_notch_hook.py",
                "events",
                "monitor-state.json",
                "managed-install.json",
                "hook-settings.json",
                "preview.sock"
            ].map { supportDirectory.appendingPathComponent($0) }
    }

    /// The copy of the product's configuration file kept beside it (`hooks.json.notchline-backup`,
    /// `settings.json.notchline-backup`), refreshed before every change (``ManagedHooksFileEditor``).
    var hooksBackup: URL {
        hooksConfiguration.appendingPathExtension("notchline-backup")
    }

    /// The registration file's root object, or nil (no file, empty, or not a JSON object). Nil
    /// means "nothing of ours registered", never an error.
    nonisolated func readConfigurationRoot(fileManager: FileManager) -> [String: Any]? {
        guard let data = try? Data(contentsOf: hooksConfiguration),
              !data.isEmpty,
              let decoded = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return decoded as? [String: Any]
    }

    nonisolated func readRegistration(configuration: ManagedHooksConfiguration, fileManager: FileManager) -> HookRegistration {
        do {
            let data = try Data(contentsOf: hooksConfiguration)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unreadable }
            return configuration.registration(in: root)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return .absent }
        catch { return .unreadable }
    }

    /// The Codex paths, as the no-argument spelling has always meant.
    nonisolated static func live(
        fileManager: FileManager = .default
    ) -> HookIntegrationPaths {
        live(for: .codex, fileManager: fileManager)
    }

    /// One product's paths: the shared support directory, and the file that
    /// product's ``ProductDescriptor`` says its hooks are registered in.
    nonisolated static func live(
        for agent: AgentKind,
        fileManager: FileManager = .default
    ) -> HookIntegrationPaths {
        HookIntegrationPaths(
            supportDirectory: supportDirectory(fileManager: fileManager),
            hooksConfiguration: ProductRegistry.descriptor(for: agent).setup.managedHooks!
                .configurationFile(fileManager: fileManager),
            agent: agent
        )
    }

    nonisolated static func supportDirectory(fileManager: FileManager) -> URL {
        fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("Notchline", isDirectory: true)
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Notchline")
    }
}

/// The few lines both products run once per event, and the channel one answer comes back on.
///
/// - `exec 2>/dev/null`: both products print a hook's stderr (ADR 0013). Stdout carries
///   decisions, so only non-answering events send it to `/dev/null`.
/// - Always `exit 0`: a non-zero exit shows as `<event> hook error`, and `nc` exits 1 when
///   nothing listens (measured 2026-09-05), so it cannot be `exec`ed.
/// - `-w` is an idle deadline bounding a wedged app: one literal gives lifecycle events the
///   short bound and ``answeringArgument`` a window a person can answer in. `nc -U`
///   half-closes on EOF and keeps reading for the reply (measured 2026-09-05).
/// - ``suppressionEnvironmentKey`` is read first: a nested agent raises no row.
/// - 6.3 ms per event (compiled helper 4.1 ms, old Python helper 30 ms; ADR 0013).
nonisolated enum AgentHookHelper {
    /// A word, not seconds, so changing the window changes the script and not the registered
    /// definition, which Codex hashes (ADR 0014).
    nonisolated static let answeringArgument = "wait"

    /// Wide on purpose: a hook the product kills prints an error in the user's session.
    nonisolated static let answeringSlackSeconds = 60

    /// Set on an agent's process, this keeps it out of the notch.
    nonisolated static let suppressionEnvironmentKey = "NOTCHLINE_HOOKS_OFF"

    /// - Parameter answerWindowSeconds: must sit inside the registered timeout; a helper that
    ///   gives up exits 0, one the product kills is a hook error.
    /// - Parameter announcesEvent: write `$1` as a line ahead of the payload, for payloads that
    ///   name no event (Antigravity CLI, measured 2026-09-11, 1.2.2).
    nonisolated static func script(
        socketPath: String,
        answerWindowSeconds: Int,
        announcesEvent: Bool = false
    ) -> String {
        let forward = announcesEvent
            ? """
            # This product's payload does not say which event fired; the
            # registration passed the name as $1, and it goes ahead of the
            # payload on one line.
            { printf '%s\\n' "${1:-}"; cat; } | /usr/bin/nc -U -w 1 \(singleQuoted(socketPath)) >/dev/null
            """
            : """
            /usr/bin/nc -U -w 1 \(singleQuoted(socketPath)) >/dev/null
            """
        return """
        #!/bin/sh
        # Notchline — hands one hook payload to the running app, and on the
        # events that ask a person, carries the app's answer back.
        #
        # Says nothing it was not asked to say, and always exits 0. Both are
        # required: the agent prints a line in the user's session for every hook
        # that fails or writes to stderr, and no setting suppresses it.
        if [ -n "${\(suppressionEnvironmentKey):-}" ]; then
            exit 0
        fi
        exec 2>/dev/null
        if [ "${1:-}" = \(answeringArgument) ]; then
            # Stdout is the reply channel. Whatever the app writes back is this
            # product's own hook-output JSON; when the app is closed, nc writes
            # nothing and the agent carries on unchanged.
            /usr/bin/nc -U -w \(answerWindowSeconds) \(singleQuoted(socketPath))
            exit 0
        fi
        \(forward)
        exit 0

        """
    }

    /// `/bin/sh` plus the quoted helper path, for products with no `args` key (Codex,
    /// Antigravity CLI). The quoting is part of the registration's identity.
    nonisolated static func shellCommandLine(forHelper helper: URL) -> String {
        "/bin/sh \(singleQuoted(helper.path))"
    }

    /// What ``prepare(at:answerWindowSeconds:fileManager:)`` found or did.
    nonisolated enum Preparation: Sendable, Equatable {
        case current
        case written
        case failed
    }

    /// Writes this build's helper only if it differs: a no-op write still costs a file event and
    /// rewrites a hashed Codex script. The directory is `0700`; the socket beside it is private.
    @discardableResult
    nonisolated static func prepare(
        at paths: HookIntegrationPaths,
        answerWindowSeconds: Int,
        announcesEvent: Bool = false,
        fileManager: FileManager
    ) -> Preparation {
        let desired = script(
            socketPath: paths.hookSocket.path,
            answerWindowSeconds: answerWindowSeconds,
            announcesEvent: announcesEvent
        )
        if let installed = try? String(contentsOf: paths.hookHelper, encoding: .utf8),
           installed == desired,
           fileManager.isExecutableFile(atPath: paths.hookHelper.path) {
            return .current
        }
        do {
            try fileManager.createDirectory(
                at: paths.agentDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try desired.write(to: paths.hookHelper, atomically: true, encoding: .utf8)
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: paths.hookHelper.path
            )
            return .written
        } catch {
            return .failed
        }
    }

    nonisolated static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// How one product's registration file is arranged and how its helper learns which event
/// fired. Antigravity CLI differs on all three (measured 2026-09-11, 1.2.2).
nonisolated struct HookRegistrationDialect: Sendable, Equatable {
    /// See ``ManagedHooksConfiguration/containerKey``.
    let containerKey: String
    /// A shell command line (`/bin/sh '…/hook.sh'`, Codex) rather than Claude Code's exec form
    /// with `args` (one process instead of two).
    let handlersAreShellCommandLines: Bool
    /// The event name is passed as `$1` because the payload lacks it.
    let eventNameArrivesAsArgument: Bool

    /// `hooks` at the root, the exec form, and a payload that names its event.
    nonisolated static let standard = HookRegistrationDialect(
        containerKey: "hooks",
        handlersAreShellCommandLines: false,
        eventNameArrivesAsArgument: false
    )
}

/// Turns one product's payload into ``HookPayload``. The one stateful thing allowed: proposing
/// a local Turn identity at an unambiguous submission boundary
/// (`multi-product-provider-architecture/README.md` §6.1).
nonisolated protocol HookPayloadTranslating: Sendable {
    /// nil for bytes that are not this product's, dropped silently: a product sharing its hooks
    /// file with a sibling sees the sibling's events.
    func canonicalPayload(from body: Data, receivedAt: Date) -> Data?
}

/// How one product's lifecycle events are spelled.
protocol AgentHookVocabulary: Sendable {
    nonisolated var agent: AgentKind { get }
    /// Every definition must map to a signal (tested).
    nonisolated var managedDefinitions: [ManagedHookDefinition] { get }
    /// Substrings of earlier builds' handler commands, stripped on install and proven gone on
    /// removal.
    nonisolated var legacyCommandMarkers: [String] { get }
    /// Codex sends nothing on refusal (measured 2026-08-15), so its wait ends on activity against
    /// another call. That needs ordered events: Claude Code's `Stop` arrived ahead of its
    /// subagent's `PermissionRequest` (2026-08-16).
    nonisolated var reportsApprovalDenials: Bool { get }
    /// The prompt the row falls back to before a turn has said anything (PRD §7, `Running`).
    nonisolated var carriesPromptText: Bool { get }
    /// Codex's `Stop` carries `last_assistant_message`. Claude Code's copy is not read: its text
    /// comes from `MessageDisplay` (PRD §7).
    nonisolated var carriesFinalAnswerText: Bool { get }
    /// Folded into a preview, off the change stream except on its absent-to-present edge: CLI
    /// 2.1.234 sent one 1561-character message as eleven deltas, 0.29 s apart.
    nonisolated var messageDeltaEventName: String? { get }
    /// Codex: the only local sign its App Server commentary moved
    /// (``LiveCodexMonitorService/refreshTurnProgressInBackground(requests:)``), which
    /// ``renderedProjection()`` cannot see. Claude Code's `MessageDisplay` fold wakes instead.
    nonisolated var wakesOnToolCallOpened: Bool { get }
    /// Whether a held prompt waits for the product's own record rather than an event under its
    /// turn id.
    /// - Codex: the `--approve-for-me` reviewer's hooks carry the parent's `session_id`, its own
    ///   `turn_id` and no `agent_id` (``HookEventRepository/adoptTurnsOnRecord(_:)``).
    /// - Claude Code: refusing an approval aborts the turn with no hook (measured 2026-08-23, CLI
    ///   2.1.241), so the next prompt is the held case and an event must redeem it.
    nonisolated var settlesHeldTurnsFromRecord: Bool { get }
    /// Per product: Codex re-trusts through `/hooks`, Claude Code edits its own file (CR-029).
    nonisolated var restoreDefinitionAdvice: String { get }
    /// A released notch app registers 1 hour on Codex and 24 hours on Claude Code for
    /// `PermissionRequest`. Final: changing it on Codex needs a re-trust (ADR 0014).
    nonisolated var answeringTimeoutSeconds: Int { get }
    /// nil where requests cannot be answered from here (no L6, `docs/product-support.md` §2): no
    /// connection is held and the row offers no affirmative.
    nonisolated var answering: (any RequestAnswering)? { get }
    /// Which answers the product acts on for this call, asked only of ``answeringEventName``.
    nonisolated func answerOperations(forEvent name: String, toolName: String?) -> AnswerOperations
    nonisolated var registrationDialect: HookRegistrationDialect { get }
    /// nil when the payload is already spelled as the reducer reads. Runs on the read queue.
    nonisolated var payloadTranslator: (any HookPayloadTranslating)? { get }
    /// `nil` means "not recognised": drop it and report it. `inert` means ours, without effect.
    nonisolated func signal(forEvent name: String, toolName: String?) -> HookSignal?

    /// `nil` where nothing readable arrived; the wait still opens (`AGENTS.md` §6).
    /// - Parameter permissionSuggestions: rules the product offered to persist; drawn nowhere
    ///   yet (`answer-in-notch.md` §6.5).
    nonisolated func request(
        forEvent name: String,
        toolName: String?,
        toolInput: JSONValue?,
        permissionSuggestions: JSONValue?,
        openedBy toolUseID: String
    ) -> AgentRequest?
}

extension AgentHookVocabulary {
    nonisolated var registrationDialect: HookRegistrationDialect { .standard }
    nonisolated var payloadTranslator: (any HookPayloadTranslating)? { nil }
    nonisolated func answerOperations(forEvent name: String, toolName: String?) -> AnswerOperations {
        .readingOnly
    }

    /// Read off the registration, so transport and registration cannot disagree.
    nonisolated var answeringEventName: String? {
        managedDefinitions.first { $0.argument == AgentHookHelper.answeringArgument }?.event
    }

    /// Derived so it cannot drift: the helper must give up first, or the product kills it and
    /// prints an error in the session (ADR 0013).
    nonisolated var answerWindowSeconds: Int {
        answeringTimeoutSeconds - AgentHookHelper.answeringSlackSeconds
    }

    /// Derived from the signal table, so `PostToolUse` is refused by construction (CR-030).
    /// Gating on `PreToolUse` too would decode ~28 MB on the read queue; over 30,909 tool calls
    /// (measured 2026-09-05) this admits 56.
    nonisolated func carriesRequest(forEvent name: String, toolName: String?) -> Bool {
        switch signal(forEvent: name, toolName: toolName) {
        case .inputWaitOpened, .approvalWaitOpened, .approvalWaitInferred,
             .questionAskedWithoutWaiting:
            return true
        default:
            return false
        }
    }
}

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

    /// Seven definitions; the contract §4.2 freezes. No `SessionEnd` (it reduced to nothing).
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
            ManagedHookDefinition(event: "Stop", matcher: nil)
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
        case ("SessionEnd", _):
            // Not registered; consumed so an older registration raises no diagnostic per session end.
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

/// The one file this integration keeps. No install marker (both cases rewrite the script) and
/// no `definitionsVersion`: a changed definition set already fails `isFullyInstalled`.
nonisolated struct HookInstallRecord: Codable, Sendable, Equatable {
    var installedAt: Date?
    /// Only its presence is read: it stops the card telling a user who trusted the hooks to trust
    /// them again.
    var lastEventAt: Date?
    /// Definitions this app rewrote and has not seen fire since. Codex silently stops running a
    /// changed definition until re-trusted in `/hooks` (ADR 0014), and nothing readable says
    /// whether that happened. `PermissionRequest` silence proves nothing, so it is never probed.
    /// Events are removed as they arrive.
    var eventsAwaitingTrust: [String]?
}

/// Reads and updates ``HookInstallRecord`` under one process-wide lock: the registrar and the
/// store both write it.
nonisolated enum HookInstallStateFile {
    private static let lock = NSLock()

    nonisolated static func read(at url: URL) -> HookInstallRecord {
        lock.lock()
        defer { lock.unlock() }
        return readLocked(at: url)
    }

    @discardableResult
    nonisolated static func update(
        at url: URL,
        fileManager: FileManager = .default,
        _ mutation: (inout HookInstallRecord) -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        var record = readLocked(at: url)
        mutation(&record)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(record) else { return false }
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            return true
        } catch {
            return false
        }
    }

    nonisolated private static func readLocked(at url: URL) -> HookInstallRecord {
        guard let data = try? Data(contentsOf: url) else { return HookInstallRecord() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(HookInstallRecord.self, from: data))
            ?? HookInstallRecord()
    }
}

/// Registers this app's definitions in `~/.codex/hooks.json` and installs their helper.
///
/// The definition is never rewritten after first install. Codex keys trust by content hash
/// in `config.toml`, and silently stops running a changed definition until re-trusted
/// (`PreToolUse` dead two turns, 2026-08-15). Versioning lives in the unhashed script.
/// The key is `[hooks.state."…/hooks.json:pre_tool_use:0:0"]`, group and handler by index
/// (2026-08-20), so removing a middle group drops later groups' trust
/// (``ManagedHooksConfiguration`` appends at the tail).
actor CodexHookRegistrar: HookRegistrationSetup {
    /// From the vocabulary, so the registrar never registers a hook whose events are discarded.
    nonisolated private static let managedDefinitions =
        CodexHookVocabulary().managedDefinitions

    private let paths: HookIntegrationPaths
    private let fileManager: FileManager
    nonisolated private let configurationWatcher: DirectoryChangeWatcher
    /// Kept with the change count taken at read time; apart, they race.
    private var cachedRegistration: (changeCount: UInt64, health: HookRegistration)?

    init(
        paths: HookIntegrationPaths = .live(),
        fileManager: FileManager = .default,
        timing: MonitorTiming = .standard
    ) {
        self.paths = paths
        self.fileManager = fileManager
        // Health changes only when we or the user write the file, so it is re-read on that edge.
        self.configurationWatcher = DirectoryChangeWatcher(
            directoryURL: paths.hooksConfiguration,
            debounceInterval: timing.unreadStateDebounceInterval
        )
    }

    nonisolated var socketURL: URL {
        paths.hookSocket
    }

    nonisolated func changeEvents() -> AsyncStream<Void> {
        configurationWatcher.events()
    }

    /// Read from `hooks.json` only, cached until our own writes or a file change, never a timer.
    /// The watcher's change count is compared across the read rather than subscribing to the
    /// edge, which raced a second consumer and cached a stale reading (CR-028).
    func registration() -> HookRegistration {
        // On a first run `hooks.json` did not exist at `init`, so the attach is retried per ask.
        configurationWatcher.attachIfNeeded()
        // Read after the attach: an attach counts as a change.
        let changeCount = configurationWatcher.changeCount
        if let cachedRegistration, cachedRegistration.changeCount == changeCount {
            return cachedRegistration.health
        }
        let scanned = paths.readRegistration(configuration: managedConfiguration, fileManager: fileManager)
        cachedRegistration = (changeCount, scanned)
        return scanned
    }

    func invalidateRegistration() {
        cachedRegistration = nil
    }

    /// A `stat`, the one helper question a refresh may ask: a user can empty the support folder,
    /// and `/bin/sh` on a missing path is a hook error in the session (ADR 0013).
    var isHelperInstalled: Bool {
        fileManager.isExecutableFile(atPath: paths.hookHelper.path)
    }

    /// Writes the helper if it differs from this build's. Called at launch, on install, and when
    /// ``isHelperInstalled`` says it is gone; never per refresh.
    @discardableResult
    func prepareHelper() -> Bool {
        didCompareHelperThisLaunch = true
        return AgentHookHelper.prepare(
            at: paths,
            answerWindowSeconds: CodexHookVocabulary().answerWindowSeconds,
            fileManager: fileManager
        ) != .failed
    }

    private var didCompareHelperThisLaunch = false

    /// Binds the socket on every refresh; compares the helper once per launch and again only if
    /// the `stat` fails. The socket is bound whatever the write says: a helper already on disk
    /// still delivers.
    func prepareHelperForTransport() -> Bool {
        if !didCompareHelperThisLaunch || !isHelperInstalled {
            prepareHelper()
        }
        return true
    }

    /// The settings card's status: the registration, projected against whether any definition has
    /// been seen to fire, the only evidence Codex's trust step was completed.
    func status(observedBy repository: HookEventRepository) async -> IntegrationSetupStatus {
        IntegrationSetupStatus.card(
            registration: registration(),
            hasObservedEvent: await repository.observedState().hasObservedEvent
        )
    }

    func install() throws {
        // A no-op install writes nothing: a rewrite reformats a file this app does not own, and the
        // trust key's index-based group component makes it risky for the user's definitions.
        guard registration() != .complete else { return }

        try fileManager.createDirectory(
            at: paths.agentDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard prepareHelper() else {
            throw ManagedHooksConfigurationError.verificationFailed
        }
        // Read before the write, because the question is what changed.
        let rewritten = managedConfiguration.eventsWhoseDefinitionChanges(
            comparedTo: readConfigurationRoot()
        )
        try configurationEditor.install()
        removeRetiredArtifacts()
        HookInstallStateFile.update(at: paths.installState, fileManager: fileManager) {
            $0.installedAt = Date()
            $0.eventsAwaitingTrust = rewritten.isEmpty ? nil : rewritten
        }
        cachedRegistration = nil
    }

    func uninstall() throws {
        cachedRegistration = nil
        try configurationEditor.remove()

        for url in [paths.hookHelper, paths.installState, paths.hookSocket] {
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }
        removeRetiredArtifacts()
        // Only this product's directory, then the shared ones if empty.
        removeDirectoryIfEmpty(paths.agentDirectory)
        removeDirectoryIfEmpty(paths.agentDirectory.deletingLastPathComponent())
        removeDirectoryIfEmpty(paths.supportDirectory)
    }

    // MARK: - Internals

    private func readConfigurationRoot() -> [String: Any]? {
        paths.readConfigurationRoot(fileManager: fileManager)
    }

    private func removeRetiredArtifacts() {
        for url in paths.retiredArtifacts
        where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func removeDirectoryIfEmpty(_ url: URL) {
        guard let remaining = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ), remaining.isEmpty else { return }
        try? fileManager.removeItem(at: url)
    }

    /// The one string this app registers, and never rewrites. A script file, not an inlined
    /// helper, so behaviour can change without touching the hashed definition.
    nonisolated static func command(forHelper helper: URL) -> String {
        AgentHookHelper.shellCommandLine(forHelper: helper)
    }

    private var managedConfiguration: ManagedHooksConfiguration {
        .command(
            Self.command(forHelper: paths.hookHelper),
            legacyCommands: CodexHookVocabulary().legacyCommandMarkers,
            definitions: Self.managedDefinitions,
            descriptionForNewFiles: "User-level Codex lifecycle hooks."
        )
    }

    private var configurationEditor: ManagedHooksFileEditor {
        ManagedHooksFileEditor(
            url: paths.hooksConfiguration,
            recoveryCopyURL: paths.hooksBackup,
            configuration: managedConfiguration,
            fileManager: fileManager
        )
    }
}

/// One item of in-flight background work. Decodes no fields: the reading is the count.
nonisolated struct HookBackgroundTask: Sendable, Decodable, Equatable {}

/// One hook payload, as either product sends it. The turn identity is `turn_id` on Codex and
/// `prompt_id` on Claude Code.
nonisolated struct HookPayload: Sendable, Decodable, Equatable {
    let hookEventName: String?
    let sessionID: String?
    let turnID: String?
    /// Claude Code's `prompt_id`, read directly. On `MessageDisplay`, `turn_id` and `prompt_id`
    /// differ, so ``turnID`` is a message-level id there (measured CLI 2.1.234 and 2.1.251).
    /// Nil on Codex, where the rule reading it treats nil as "whichever turn is asking".
    let promptID: String?
    /// The subagent that produced this event, when one did. Both products stamp a subagent's
    /// hooks with the parent's `session_id` (Codex measured 2026-08-22, CLI `0.149.0-alpha.4.1`;
    /// Claude Code 2026-08-23, CLI 2.1.241), so only this field says which agent is speaking.
    /// Codex: on `PreToolUse`, `PostToolUse`, `PermissionRequest`, `UserPromptSubmit` from a
    /// subagent, required on `SubagentStart`/`SubagentStop`. Claude Code: on every event.
    let agentID: String?
    let toolName: String?
    let toolUseID: String?
    let permissionMode: String?
    let workingDirectory: String?
    /// `false` when the product sent `transcript_path: null`, `true` for a path, `nil` when the
    /// key is absent. Codex allows null on all twelve events (CLI `0.153.4` schemas, 2026-09-09)
    /// for an `ephemeral` thread, one `thread/read` will not return
    /// (``HookTurnState/threadHasNoTranscript``). Claude Code always sends a path.
    let namesATranscript: Bool?
    let prompt: String?
    let lastAssistantMessage: String?
    let messageID: String?
    let delta: String?
    /// Claude Code's in-flight background work, telling "done" from "paused for background work".
    /// Nil on Codex. Read on `Stop` only: `SubagentStop`'s copy still lists the stopping agent
    /// (measured 2026-08-23, CLI 2.1.241).
    let backgroundTasks: [HookBackgroundTask]?
    /// `tool_input`, carried only where the event opens a wait
    /// (``AgentHookVocabulary/carriesRequest(forEvent:toolName:)``); nil everywhere else,
    /// including `PostToolUse`. A ``JSONValue`` so the payload stays `Sendable` and `Equatable`.
    let toolInput: JSONValue?

    /// Claude Code's `permission_suggestions: PermissionUpdate[]` (2.1.263 zod, 2026-09-06), the
    /// type `allow` accepts back as `updatedPermissions`. Absent means do not offer it; the
    /// product withholds it exactly when `suppressAlwaysAllowRule` applies. Codex never sends it.
    /// Not yet drawn or written: `answer-in-notch.md` §6.5.
    let permissionSuggestions: JSONValue?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case turnID = "turn_id"
        case promptID = "prompt_id"
        case agentID = "agent_id"
        case toolName = "tool_name"
        case toolUseID = "tool_use_id"
        case permissionMode = "permission_mode"
        case workingDirectory = "cwd"
        case transcriptPath = "transcript_path"
        case prompt
        case lastAssistantMessage = "last_assistant_message"
        case messageID = "message_id"
        case delta
        case backgroundTasks = "background_tasks"
        case toolInput = "tool_input"
        case permissionSuggestions = "permission_suggestions"

        /// Decides what happens to the field when it arrives too big (``HookPayloadDistiller``).
        nonisolated var carried: CarriedValue {
            switch self {
            case .prompt, .lastAssistantMessage, .delta: return .text
            case .backgroundTasks: return .list
            case .toolInput, .permissionSuggestions: return .request
            default: return .identity
            }
        }
    }

    nonisolated enum CarriedValue: Sendable {
        /// Cut short: a shorter answer is the same answer.
        case text
        /// Left out: half a `session_id` is a different session.
        case identity
        /// Carried whole or left out: half a list is not JSON, and the count is the reading.
        case list
        /// Carried whole or left out (half an object is not JSON; a cut request is a different
        /// command), and only on events that ask, so `PostToolUse` stays cheap (CR-030).
        /// `permission_suggestions` shares the gate; it arrives only on `PermissionRequest`.
        case request
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hookEventName = try container.decodeIfPresent(String.self, forKey: .hookEventName)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        promptID = try container.decodeIfPresent(String.self, forKey: .promptID)
        turnID = try container.decodeIfPresent(String.self, forKey: .turnID)
            ?? promptID
        agentID = try container.decodeIfPresent(String.self, forKey: .agentID)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        toolUseID = try container.decodeIfPresent(String.self, forKey: .toolUseID)
        permissionMode = try container.decodeIfPresent(String.self, forKey: .permissionMode)
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        // `decodeIfPresent` would return nil for both an absent key and an explicit null.
        if container.contains(.transcriptPath) {
            namesATranscript = try !container.decodeNil(forKey: .transcriptPath)
        } else {
            namesATranscript = nil
        }
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        lastAssistantMessage = try container.decodeIfPresent(
            String.self,
            forKey: .lastAssistantMessage
        )
        messageID = try container.decodeIfPresent(String.self, forKey: .messageID)
        delta = try container.decodeIfPresent(String.self, forKey: .delta)
        backgroundTasks = try container.decodeIfPresent(
            [HookBackgroundTask].self,
            forKey: .backgroundTasks
        )
        toolInput = try container.decodeIfPresent(JSONValue.self, forKey: .toolInput)
        permissionSuggestions = try container.decodeIfPresent(
            JSONValue.self,
            forKey: .permissionSuggestions
        )
    }

    /// False when absent: a build that stops sending it only makes `Completed` a moment early.
    nonisolated var pausesForBackgroundWork: Bool {
        backgroundTasks?.isEmpty == false
    }

    /// `admitsRequest` is required, not defaulted: "carry" would reintroduce CR-030's cost and
    /// "drop" would silently disable requests.
    nonisolated static func distilled(
        from body: Data,
        admittingRequestWhere admitsRequest: (String, String?) -> Bool
    ) -> HookPayload? {
        guard let selected = HookPayloadDistiller.distilled(
            from: body,
            admittingRequestWhere: admitsRequest
        ) else { return nil }
        return try? JSONDecoder().decode(HookPayload.self, from: selected)
    }
}

/// Reduces one arriving payload to the fields the reducer reads, before `JSONDecoder`.
///
/// Unread fields (tool results, pasted prompts) are the big ones; capping the whole payload
/// let one oversized result drop a `PostToolUse` and leave *Approval needed* up (CR-030).
/// One top-level pass keeps values under ``HookPayload/CodingKeys`` keys verbatim.
/// - Only completed values are emitted, so a short payload yields its whole fields; a
///   malformed one is refused (`AGENTS.md` §6.2).
/// - Text is shortened to ``maximumTextBytes``; an identity over ``maximumIdentityBytes`` is
///   left out, since half a `session_id` is a different session.
nonisolated enum HookPayloadDistiller {
    /// A row shows 240 characters (``HookSessionPreviewStore/maximumCharacters``); this is ample
    /// headroom yet keeps a pasted transcript out.
    nonisolated static let maximumTextBytes = 16 * 1_024

    /// Ids are UUIDs or short strings, `cwd` and `transcript_path` are paths.
    nonisolated static let maximumIdentityBytes = 1_024

    /// `background_tasks` items cap two text fields at 1,000 characters; measured items run about
    /// 145 bytes. Past this the row reaches `Completed` a moment early.
    nonisolated static let maximumListBytes = 16 * 1_024

    /// A plan is read in full (`answer-in-notch.md` §4.4). Measured 2026-09-05 over 30,909 tool
    /// calls: the `ExitPlanMode` plan was 54,411 bytes, `AskUserQuestion` 5,002; only one `Bash`
    /// heredoc (136,560) exceeds this. Affordable because it is paid on 0.18% of events.
    nonisolated static let maximumRequestBytes = 128 * 1_024

    /// `nil` if this never was a JSON object.
    nonisolated static func distilled(
        from body: Data,
        admittingRequestWhere admitsRequest: (String, String?) -> Bool
    ) -> Data? {
        body.withUnsafeBytes { raw in
            var scan = PayloadScan(bytes: raw)
            return scan.selectedFields(admittingRequestWhere: admitsRequest)
        }
    }

    /// Read off ``HookPayload/CodingKeys`` so a new field cannot be dropped.
    private static let selectedKeys: [String: HookPayload.CarriedValue] = Dictionary(
        uniqueKeysWithValues: HookPayload.CodingKeys.allCases.map {
            ($0.rawValue, $0.carried)
        }
    )

    /// The gated keys in emission order, read off ``HookPayload/CodingKeys`` for the same reason.
    fileprivate static let deferredKeyOrder: [String] = HookPayload.CodingKeys.allCases
        .filter { if case .request = $0.carried { true } else { false } }
        .map(\.rawValue)

    /// Hand-written so large values are stepped over, never materialised as
    /// `JSONSerialization` would.
    private struct PayloadScan {
        let bytes: UnsafeRawBufferPointer
        var index = 0

        static let quote: UInt8 = 0x22
        static let backslash: UInt8 = 0x5C
        static let openBrace: UInt8 = 0x7B
        static let closeBrace: UInt8 = 0x7D
        static let openBracket: UInt8 = 0x5B
        static let closeBracket: UInt8 = 0x5D
        static let colon: UInt8 = 0x3A
        static let comma: UInt8 = 0x2C
        static let lowercaseU: UInt8 = 0x75

        /// `isComplete` is false only when the bytes ran out inside the value.
        struct ScannedValue {
            let range: Range<Int>
            let isString: Bool
            let isComplete: Bool
        }

        mutating func selectedFields(
            admittingRequestWhere admitsRequest: (String, String?) -> Bool
        ) -> Data? {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == Self.openBrace else { return nil }
            index += 1

            var selected = Data([Self.openBrace])
            var isFirstCarried = true
            var isFirstMember = true
            // Request values are held as ranges until the event and tool names arrive (later, on
            // Claude Code), so a refused request costs no copy or decode (CR-030).
            var deferredRequests: [String: ScannedValue] = [:]
            var eventName: String?
            var toolName: String?
            while true {
                skipWhitespace()
                guard index < bytes.count else { break }
                if bytes[index] == Self.closeBrace { break }
                if !isFirstMember {
                    // Separators are checked, so only real JSON objects are accepted.
                    guard bytes[index] == Self.comma else { return nil }
                    index += 1
                    skipWhitespace()
                    guard index < bytes.count else { break }
                    // `JSONDecoder` accepts a trailing comma, so this does too; the decoder is the authority.
                    if bytes[index] == Self.closeBrace { break }
                }
                isFirstMember = false
                guard bytes[index] == Self.quote else { return nil }
                guard let key = scanKey() else { break }
                skipWhitespace()
                guard index < bytes.count else { break }
                guard bytes[index] == Self.colon else { return nil }
                index += 1
                skipWhitespace()
                guard index < bytes.count else { break }

                let value = scanValue()
                if let kind = HookPayloadDistiller.selectedKeys[key] {
                    if case .request = kind {
                        // The first wins, as `JSONDecoder` does with a repeated key (measured).
                        if deferredRequests[key] == nil { deferredRequests[key] = value }
                    } else if let carried = carry(value, kind: kind) {
                        if !isFirstCarried { selected.append(Self.comma) }
                        isFirstCarried = false
                        selected.append(contentsOf: Array("\"\(key)\":".utf8))
                        selected.append(carried)
                        // Read back off the bytes; needed only for the gate, and only if a request turned up.
                        switch key {
                        case HookPayload.CodingKeys.hookEventName.rawValue:
                            eventName = stringContents(of: value)
                        case HookPayload.CodingKeys.toolName.rawValue:
                            toolName = stringContents(of: value)
                        default: break
                        }
                    }
                }
                guard value.isComplete else { break }
            }

            // After the loop, so a truncated payload keeps a whole request, but only if its event name
            // arrived: an unvouched request fails closed.
            if let eventName, admitsRequest(eventName, toolName) {
                // In ``HookPayload/CodingKeys`` order, not the dictionary's, so equal payloads distil to
                // equal bytes.
                for name in HookPayloadDistiller.deferredKeyOrder {
                    guard let deferred = deferredRequests[name],
                          let carried = carry(deferred, kind: .request) else { continue }
                    if !isFirstCarried { selected.append(Self.comma) }
                    isFirstCarried = false
                    selected.append(contentsOf: Array("\"\(name)\":".utf8))
                    selected.append(carried)
                }
            }
            selected.append(Self.closeBrace)
            return selected
        }

        /// A scanned string with its quotes dropped. A name spelled with an escape fails to match;
        /// neither product spells one that way.
        private func stringContents(of value: ScannedValue) -> String? {
            guard value.isString, value.isComplete, value.range.count >= 2 else {
                return nil
            }
            let content = (value.range.lowerBound + 1) ..< (value.range.upperBound - 1)
            return String(
                decoding: UnsafeRawBufferPointer(rebasing: bytes[content]),
                as: UTF8.self
            )
        }

        /// `nil` leaves the field out entirely.
        private func carry(_ value: ScannedValue, kind: HookPayload.CarriedValue) -> Data? {
            let limit = switch kind {
            case .text: HookPayloadDistiller.maximumTextBytes
            case .identity: HookPayloadDistiller.maximumIdentityBytes
            case .list: HookPayloadDistiller.maximumListBytes
            case .request: HookPayloadDistiller.maximumRequestBytes
            }
            if value.isComplete, value.range.count <= limit {
                return Data(UnsafeRawBufferPointer(rebasing: bytes[value.range]))
            }
            // Only a string of row text can be shortened and still be itself.
            guard value.isString, case .text = kind else { return nil }
            let start = value.range.lowerBound + 1
            let end = value.isComplete ? value.range.upperBound - 1 : value.range.upperBound
            guard start <= end else { return nil }
            return Self.shortened(
                UnsafeRawBufferPointer(rebasing: bytes[start ..< end]),
                to: limit
            )
        }

        /// The key's raw bytes. An escaped key fails to match; no key this app reads contains one.
        private mutating func scanKey() -> String? {
            let start = index
            guard skipString() else { return nil }
            let content = (start + 1) ..< (index - 1)
            guard content.lowerBound <= content.upperBound else { return nil }
            return String(
                decoding: UnsafeRawBufferPointer(rebasing: bytes[content]),
                as: UTF8.self
            )
        }

        private mutating func scanValue() -> ScannedValue {
            let start = index
            let first = bytes[index]
            if first == Self.quote {
                let complete = skipString()
                return ScannedValue(range: start ..< index, isString: true, isComplete: complete)
            }
            if first == Self.openBrace || first == Self.openBracket {
                let complete = skipStructure()
                return ScannedValue(range: start ..< index, isString: false, isComplete: complete)
            }
            let complete = skipScalar()
            return ScannedValue(range: start ..< index, isString: false, isComplete: complete)
        }

        private mutating func skipString() -> Bool {
            index += 1
            while index < bytes.count {
                let byte = bytes[index]
                if byte == Self.backslash {
                    index = min(index + 2, bytes.count)
                    continue
                }
                index += 1
                if byte == Self.quote { return true }
            }
            return false
        }

        /// Steps over an object or an array, braces inside strings included.
        private mutating func skipStructure() -> Bool {
            var depth = 0
            while index < bytes.count {
                let byte = bytes[index]
                if byte == Self.quote {
                    guard skipString() else { return false }
                    continue
                }
                index += 1
                if byte == Self.openBrace || byte == Self.openBracket {
                    depth += 1
                } else if byte == Self.closeBrace || byte == Self.closeBracket {
                    depth -= 1
                    if depth == 0 { return true }
                }
            }
            return false
        }

        /// Running out of bytes is not completion: `12` and `128` differ only by the delimiter.
        private mutating func skipScalar() -> Bool {
            while index < bytes.count {
                let byte = bytes[index]
                if byte == Self.comma || byte == Self.closeBrace
                    || byte == Self.closeBracket || Self.isWhitespace(byte) {
                    return true
                }
                index += 1
            }
            return false
        }

        private mutating func skipWhitespace() {
            while index < bytes.count, Self.isWhitespace(bytes[index]) {
                index += 1
            }
        }

        private static func isWhitespace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        }

        /// The longest prefix that is still a whole string, re-quoted: cut at a character boundary,
        /// never inside an escape, multi-byte character or surrogate pair.
        static func shortened(_ content: UnsafeRawBufferPointer, to limit: Int) -> Data {
            var index = 0
            var safe = 0
            while index < content.count {
                guard let length = elementLength(in: content, at: index),
                      index + length <= limit else { break }
                index += length
                safe = index
            }
            var value = Data([quote])
            value.append(contentsOf: UnsafeRawBufferPointer(rebasing: content[0 ..< safe]))
            value.append(quote)
            return value
        }

        /// `nil` where there is no boundary after it.
        private static func elementLength(
            in content: UnsafeRawBufferPointer,
            at index: Int
        ) -> Int? {
            let byte = content[index]
            if byte == backslash {
                guard index + 1 < content.count else { return nil }
                guard content[index + 1] == lowercaseU else { return 2 }
                guard let scalar = hexEscape(in: content, at: index) else { return nil }
                if (0xDC00 ... 0xDFFF).contains(scalar) { return nil }
                guard (0xD800 ... 0xDBFF).contains(scalar) else { return 6 }
                // A lone high surrogate is not a boundary; only the pair is.
                guard let low = hexEscape(in: content, at: index + 6),
                      (0xDC00 ... 0xDFFF).contains(low) else { return nil }
                return 12
            }
            let length: Int
            switch byte {
            case 0x00 ... 0x7F: length = 1
            case 0xC2 ... 0xDF: length = 2
            case 0xE0 ... 0xEF: length = 3
            case 0xF0 ... 0xF4: length = 4
            default: return nil
            }
            guard index + length <= content.count else { return nil }
            return length
        }

        private static func hexEscape(
            in content: UnsafeRawBufferPointer,
            at index: Int
        ) -> Int? {
            guard index + 6 <= content.count,
                  content[index] == backslash,
                  content[index + 1] == lowercaseU else { return nil }
            var value = 0
            for offset in (index + 2) ..< (index + 6) {
                guard let digit = hexDigit(content[offset]) else { return nil }
                value = value << 4 | digit
            }
            return value
        }

        private static func hexDigit(_ byte: UInt8) -> Int? {
            switch byte {
            case 0x30 ... 0x39: return Int(byte - 0x30)
            case 0x41 ... 0x46: return Int(byte - 0x41) + 10
            case 0x61 ... 0x66: return Int(byte - 0x61) + 10
            default: return nil
            }
        }
    }
}

// Compatibility names for existing product adapters and fixtures; the shared types, not a
// second Hooks state machine.
typealias HookSignal = MonitoringSignal
typealias HookTurnState = MonitoredTurnState
typealias HookStateSnapshot = MonitoringStateSnapshot
typealias HookSessionPreviewStore = TurnPreviewStore
typealias HookChangeBroadcast = MonitoringChangeBroadcast
typealias HookEventRepository = MonitoringRepository
