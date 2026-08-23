import Foundation

/// How complete this app's registration is, read from the product's own hooks
/// file and from nothing else.
///
/// One of the two facts behind the settings card. It answers "are our
/// definitions in their file, in the shape this build writes them", which is
/// the only question a file read can answer. Whether Codex actually *runs* them
/// is the other fact, and it has a different source — see ``HookSetupStatus``.
nonisolated enum HookRegistration: Sendable, Equatable {
    /// Nothing of this app's is registered.
    case absent
    /// Something of this app's is registered, but not what this build needs.
    ///
    /// A partial paste, a set from an older version, or the Python-era
    /// registration this design replaced. The user is asked to repair rather
    /// than told nothing is installed, because the latter invites a second
    /// registration beside the first.
    case mismatched
    /// Exactly one current definition per managed event, and nothing else.
    case complete
}

/// What the settings card says, projected from the two independent facts.
///
/// This is a *display* type. It used to be the model as well, which is what
/// made `status(hasObservedEvent:)` take the second fact as a parameter and
/// forced every caller to thread one fact through the other. Registration comes
/// from a file this app can read; delivery comes from events arriving. They are
/// projected here and nowhere else.
enum HookSetupStatus: Equatable, Sendable {
    case notInstalled
    case repairRequired
    case reviewRequired
    case active

    /// The four cards, from the two facts that produce them.
    nonisolated static func card(
        registration: HookRegistration,
        hasObservedEvent: Bool
    ) -> HookSetupStatus {
        switch registration {
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
        case (.notInstalled, .notInstalled),
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
        case .notInstalled:
            "Not installed"
        case .repairRequired:
            "Installation incomplete; turn the main switch on to repair it"
        case .reviewRequired:
            "Installed; trust it under /hooks in Codex"
        case .active:
            "Connected"
        }
    }

    nonisolated var isIntegrationEnabled: Bool {
        switch self {
        case .reviewRequired, .active:
            true
        case .notInstalled, .repairRequired:
            false
        }
    }
}

/// `nonisolated` for the same reason as ``PendingApproval``: a plain `Sendable`
/// bag of URLs that is read off the main actor, which the project's default
/// isolation would otherwise pin to it.
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

    /// Everything belonging to one product, and nothing belonging to another.
    ///
    /// Every file below used to sit directly in the shared directory, which is
    /// only safe while there is one product. With two, one product's uninstall
    /// deletes the other's socket, and one product's files make the other
    /// report an install footprint it does not have.
    ///
    /// Kept short deliberately: a Unix domain socket path may not exceed
    /// 104 bytes.
    var agentDirectory: URL {
        supportDirectory
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent(agent.rawValue, isDirectory: true)
    }

    /// The folder this app's own quota reading runs in.
    ///
    /// Named here rather than spelled out at each use because three
    /// collaborators have to agree on it exactly: the reading is pinned to it,
    /// the session registry excludes it, and the hook store drops payloads
    /// carrying it. Spelling it out separately is how two of those three came
    /// to have it and the third did not.
    var quotaWorkingDirectory: URL {
        agentDirectory.appendingPathComponent("usage", isDirectory: true)
    }

    /// The helper the product runs once per event.
    ///
    /// A file of this app's own, in this app's own directory. Both products run
    /// the same four lines; only the socket path differs.
    var hookHelper: URL {
        agentDirectory.appendingPathComponent("hook.sh")
    }

    /// Where that helper hands one payload to a running app.
    var hookSocket: URL {
        agentDirectory.appendingPathComponent("hook.sock")
    }

    /// The one file this integration keeps on disk.
    ///
    /// It replaces `managed-install.json`, `hook-settings.json` and
    /// `monitor-state.json`. Only ``HookInstallRecord/lastEventAt`` is ever read
    /// back, and it exists for exactly one reason: after a restart, before
    /// Codex has done anything, the card must not tell a user who trusted the
    /// hooks last week to go and trust them again.
    var installState: URL {
        agentDirectory.appendingPathComponent("install.json")
    }

    /// What an install made before this design left behind.
    ///
    /// Not legacy *handling* — nothing here is read, recognised or branched on.
    /// It is a delete list, applied by the repair that replaces the old
    /// registration and again by uninstall, so the folder does not keep a
    /// Python helper, an event queue and three state files nothing will ever
    /// open again. The flat names are from before this app's files were
    /// namespaced per product.
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

    /// The copy of the product's configuration file kept beside it.
    ///
    /// Refreshed immediately before every change this app makes to that file,
    /// so it always holds the version being replaced —
    /// `hooks.json.notchline-backup` next to `~/.codex/hooks.json`, and
    /// `settings.json.notchline-backup` next to `~/.claude/settings.json`. Both
    /// products, on the same rule: see ``ManagedHooksFileEditor`` for why it is
    /// refreshed rather than written once, and why the Codex file is the one
    /// where a stale copy does the most damage.
    var hooksBackup: URL {
        hooksConfiguration.appendingPathExtension("notchline-backup")
    }

    nonisolated static func live(
        agent: AgentKind = .codex,
        fileManager: FileManager = .default
    ) -> HookIntegrationPaths {
        HookIntegrationPaths(
            supportDirectory: supportDirectory(fileManager: fileManager),
            hooksConfiguration: fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/hooks.json"),
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

/// The four lines both products run once per event.
///
/// Deliberately the smallest thing that can carry one payload:
///
/// - **It never speaks.** `exec >/dev/null 2>&1` covers the whole script,
///   including the shell's own "not found" if `nc` is ever absent. Both
///   products parse a hook's stdout for directives and print its stderr, so
///   silence on both streams is not tidiness — a helper that reported "the app
///   is not running" would be exactly the noise this transport removes
///   (ADR 0013).
/// - **It always succeeds.** A non-zero exit is rendered as `<event> hook
///   error` in an interactive session, so the `exit 0` is load-bearing on every
///   path: no socket (the app is closed), a stale socket file, a refused
///   connection, a missing `nc`.
/// - **It cannot hang.** `-w 1` bounds the case where this app has accepted the
///   connection but wedged before reading it. Measured: 6.3 ms when the app is
///   listening, 17 ms when it is not, 1 s in the wedged case.
/// - **It forwards the payload unfiltered.** Field selection, truncation and
///   event naming are Swift, where they are testable, rather than a string
///   literal only one integration test ever executes.
///
/// `nc -U` rather than a compiled helper of our own because it is already on
/// every macOS and needs no target, no signing and no upgrade path. The cost of
/// the extra process is the difference between 6.3 ms and the 4.1 ms a compiled
/// equivalent measured — nothing, next to what it saves. Against the Python
/// helper it replaces on the Codex side it is 6.3 ms against 30 ms, which at
/// ~17 events per turn is 107 ms against 510 ms of CPU per turn (ADR 0013).
nonisolated enum AgentHookHelper {
    nonisolated static func script(socketPath: String) -> String {
        """
        #!/bin/sh
        # Notchline — hands one hook payload to the running app.
        #
        # Says nothing on any stream and always exits 0. Both are required: the
        # agent prints a line in the user's session for every hook that fails or
        # writes to stderr, and no setting suppresses it.
        exec >/dev/null 2>&1
        /usr/bin/nc -U -w 1 \(singleQuoted(socketPath))
        exit 0

        """
    }

    /// Wraps a path for `sh`, including one with a quote in it.
    ///
    /// A home directory is a user-chosen string and this one is pasted into a
    /// script, so the escape is not decoration: `O'Brien` would otherwise end
    /// the quoting and leave the rest of the path as shell words.
    nonisolated static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// What one lifecycle event means, said in words no product owns.
///
/// The Turn reducer used to switch on Codex's own event names, which made it
/// the only place that knew both *what happened* and *what Codex calls it*. A
/// second product does not rename those two facts, it renames only the second —
/// so the names move out here and the reducer keeps every rule it had.
///
/// The absence of a signal is a third answer, and a load-bearing one: a
/// vocabulary returning `nil` means "this event is not ours", which drops the
/// payload and raises a diagnostic. ``inert`` means "ours, and deliberately
/// without effect". Collapsing the two would turn every ordinary event a
/// product emits and we ignore into a corruption report.
nonisolated enum HookSignal: Sendable, Equatable {
    /// A user submission opened a new turn.
    case turnStarted
    /// A wait for the user's answer opened, carrying its own `tool_use_id`.
    case inputWaitOpened
    /// A wait for the user's approval opened, carrying its own `tool_use_id`.
    case approvalWaitOpened
    /// A wait for the user's approval opened with no id of its own, so it has
    /// to borrow the call that is still open.
    case approvalWaitInferred
    /// An ordinary tool call was announced. Not evidence a turn began.
    case toolCallOpened
    /// An announced call ended, whatever the outcome.
    case toolCallClosed
    /// The turn reached its terminal.
    case turnEnded
    /// A subagent this thread spawned began working.
    ///
    /// Not a turn boundary and deliberately not treated as one. A subagent runs
    /// in a thread of its own with a turn id of its own, and outlives the turn
    /// that spawned it -- measured 2026-08-22, the parent's `Stop` at 22:20:10
    /// and the subagent's finish at 22:21:41. It is a fact about the *thread*,
    /// so it names no turn and ends none.
    case subagentStarted
    /// A subagent this thread spawned finished.
    case subagentStopped
    /// Recognised and consumed, with nothing to say about turn state.
    case inert
}

/// How one product's lifecycle events are spelled.
///
/// Everything a product-specific integration owes the reducer: which hook
/// definitions have to be registered for the reducer to see anything, and what
/// each arriving event means.
protocol AgentHookVocabulary: Sendable {
    nonisolated var agent: AgentKind { get }
    /// The definitions this product must register. Every one of them has to map
    /// to a signal, or the integration would install a hook whose events it then
    /// discards — a test pins that.
    nonisolated var managedDefinitions: [ManagedHookDefinition] { get }
    /// Whether a refused approval is reported as an event of its own.
    ///
    /// Codex sends nothing at all when a human refuses -- measured 2026-08-15,
    /// 67 seconds of silence and then the turn's `Stop` -- so a borrowed wait
    /// there has to end on activity against any *other* call, inferring the
    /// answer from the fact that the turn carried on.
    ///
    /// That inference is only safe while events arrive in the order they were
    /// fired. A product that reports its own denials needs none of it, and must
    /// not have it: Claude Code's `Stop` was measured arriving ahead of its own
    /// subagent's `PermissionRequest` under the same `prompt_id` (2026-08-16).
    /// Unrelated activity arriving early would close a wait the human is still
    /// looking at.
    nonisolated var reportsApprovalDenials: Bool { get }
    /// Whether a lifecycle payload carries the row's text itself.
    ///
    /// Codex's `UserPromptSubmit` carries `prompt` and its `Stop` carries
    /// `last_assistant_message`, which is exactly the row's two lines and
    /// arrives with the event that changes the row anyway. Claude Code's
    /// payloads carry a prompt too, and it is deliberately not read: PRD §7
    /// gives that product one source for all four states, and it is the
    /// assistant text being printed, not the question that started the turn.
    nonisolated var carriesTurnText: Bool { get }
    /// The event that streams assistant text as it is displayed, if any.
    ///
    /// Folded into a per-session preview rather than reduced, and deliberately
    /// off the change stream except on its absent-to-present edge: measured
    /// against CLI 2.1.234, one 1561-character message arrived as eleven
    /// deltas, mean 0.29 s apart. Three a second is not a redraw rate.
    nonisolated var messageDeltaEventName: String? { get }
    /// What to tell the user when a definition this product registered has
    /// stopped running.
    ///
    /// The reducer is shared and the repair is not: Codex keys trust by content
    /// hash and takes it back through `/hooks`, while Claude Code's
    /// registration is the user's own file and is repaired by editing it. The
    /// sentence used to name Codex from inside the shared reducer, which made
    /// it wrong for half the events it described (CR-029).
    nonisolated var restoreDefinitionAdvice: String { get }
    /// `nil` means "not recognised": drop it and say so.
    nonisolated func signal(forEvent name: String, toolName: String?) -> HookSignal?
}

nonisolated struct CodexHookVocabulary: AgentHookVocabulary {
    nonisolated let agent: AgentKind = .codex
    nonisolated let restoreDefinitionAdvice =
        "Run /hooks in Codex and trust the definition again."
    /// A refusal produces no event whatsoever, so it has to be inferred.
    nonisolated let reportsApprovalDenials = false
    nonisolated let carriesTurnText = true
    nonisolated let messageDeltaEventName: String? = nil

    /// Seven definitions, and this exact set is the contract §4.2 freezes.
    ///
    /// `SessionEnd` is deliberately absent, and it was registered until this
    /// design. It cost one process launch per session end and one more
    /// definition for the user to trust, and it bought nothing: it reduced to
    /// exactly what an unrecognised-but-ours event reduces to, which is
    /// nothing. A thread whose session is gone is already retired by App Server
    /// membership reconciliation.
    ///
    /// `SubagentStart` and `SubagentStop` are the two newest, and they are the
    /// only events that can answer whether a thread still has work in flight
    /// after its own turn has ended. Nothing else can: the subagent's
    /// tool calls arrive stamped with the parent's `session_id`, so they cannot
    /// be told apart from the main agent's by identity alone, and the tool that
    /// spawns one returns immediately, so its `PostToolUse` proves only that
    /// the spawn was accepted.
    nonisolated var managedDefinitions: [ManagedHookDefinition] {
        [
            ManagedHookDefinition(event: "UserPromptSubmit", matcher: nil),
            ManagedHookDefinition(event: "PermissionRequest", matcher: nil),
            ManagedHookDefinition(event: "SubagentStart", matcher: nil),
            ManagedHookDefinition(event: "SubagentStop", matcher: nil),
            // Deliberately unmatched. Registering an exact tool-name regex here
            // means a naming detail decides whether a wait is ever observed, and
            // a miss is silent. It would cut ~90% of the event volume and it
            // still does not work: ordinary-tool approval arrives as a
            // `PermissionRequest` carrying `tool_name` and no `tool_use_id`, so
            // the wait can only be pinned to the id a catch-all `PreToolUse`
            // announced moments earlier, and the denial inference needs to see
            // activity on *other* calls. The answer to the volume is the
            // cheaper helper, not a matcher.
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
            // Codex names the tool but carries no `tool_use_id`, so the wait has
            // to borrow the call that is still open.
            .approvalWaitInferred
        case ("PreToolUse", "request_user_input"):
            .inputWaitOpened
        case ("PreToolUse", "request_permissions"):
            // A Desktop approval prompt is surfaced as a tool call that stays
            // open for exactly as long as the human is being asked.
            .approvalWaitOpened
        case ("PreToolUse", _):
            .toolCallOpened
        case ("PostToolUse", _):
            .toolCallClosed
        case ("Stop", _):
            // The main agent's terminal, and only the main agent's: the
            // official `stop.command.input` schema carries no `agent_id`, while
            // `subagent-stop.command.input` requires one.
            .turnEnded
        case ("SubagentStart", _):
            .subagentStarted
        case ("SubagentStop", _):
            .subagentStopped
        case ("SessionEnd", _):
            // Not registered by this build, and consumed rather than reported
            // so that a user who has not yet repaired an older registration
            // does not collect a diagnostic once per session end. Registering
            // it again would need a reason this case does not supply: it has
            // none of its own to give.
            .inert
        default:
            nil
        }
    }
}

/// Claude Code's spelling of the same lifecycle.
///
/// Measured against CLI 2.1.233 on 2026-08-16; every claim below is an
/// observation, not a reading of the documentation.
nonisolated struct ClaudeCodeHookVocabulary: AgentHookVocabulary {
    nonisolated let agent: AgentKind = .claudeCode
    /// ADR 0016: this app writes that file now, so the repair is a switch
    /// rather than an edit, and the sentence says which one.
    nonisolated let restoreDefinitionAdvice =
        "Switch Claude Code off and on in Notchline's settings to write the "
            + "hooks back into ~/.claude/settings.json."
    /// **`PermissionDenied` is not what its name suggests, and this used to
    /// say `true` because of that.** It carries the refused call's
    /// `tool_use_id`, so where it fires a refusal does close exactly -- but
    /// measured 2026-08-23 against CLI 2.1.241, it has exactly one emit site in
    /// the binary and that site is gated on
    /// `decisionReason.classifier == "auto-mode"`. It reports the *automatic
    /// classifier* refusing, never a human. Two interactive sittings confirmed
    /// it: selecting `No` on a dialog produced no `PermissionDenied`, no
    /// `PostToolUse`, and no `Stop` -- a human's refusal aborts the turn, and
    /// there is no hook for an abort.
    ///
    /// So this product is as silent about a real refusal as Codex is, and a
    /// borrowed wait needs the same rescue. The old value left a row saying
    /// `Approval needed` from the moment the user said no until the session
    /// status reading retired the turn (ADR 0011, up to one 30 s poll away),
    /// and left desktop-hosted sessions waiting on their transcript instead.
    ///
    /// The reason it was set that way is gone too. It was a `Stop` measured
    /// arriving ahead of its own subagent's `PermissionRequest` under the same
    /// `prompt_id`, which unordered delivery would let close a wait the human
    /// was still looking at -- but that was never disorder. It is what an
    /// asynchronous subagent looks like: the `Agent` call returns at once, the
    /// turn ends, and the subagent asks afterwards. Those two events now land
    /// in different slots (``AgentWaitSlots``), so neither can reach the
    /// other's wait.
    nonisolated let reportsApprovalDenials = false
    /// PRD §7: one source for all four states, and it is not the prompt.
    nonisolated let carriesTurnText = false
    nonisolated let messageDeltaEventName: String? = Self.messageDisplayEventName

    /// The tool Claude Code uses to put a question to the user.
    static let inputToolName = "AskUserQuestion"

    /// The event that carries assistant text, and the only one that does.
    ///
    /// Officially described as "While assistant message text is displayed".
    /// It is absent from the exploration document's table of events, which is
    /// why the first pass at this product concluded no such thing existed.
    static let messageDisplayEventName = "MessageDisplay"

    nonisolated var managedDefinitions: [ManagedHookDefinition] {
        [
            ManagedHookDefinition(event: "UserPromptSubmit", matcher: nil),
            ManagedHookDefinition(event: "PreToolUse", matcher: nil),
            ManagedHookDefinition(event: "PostToolUse", matcher: nil),
            ManagedHookDefinition(event: "PostToolUseFailure", matcher: nil),
            ManagedHookDefinition(event: "PermissionRequest", matcher: nil),
            ManagedHookDefinition(event: "PermissionDenied", matcher: nil),
            ManagedHookDefinition(event: "Elicitation", matcher: nil),
            ManagedHookDefinition(event: "ElicitationResult", matcher: nil),
            // The two subagent boundaries, and this product needs them for the
            // same reason Codex does rather than by symmetry with it. Measured
            // 2026-08-23 against CLI 2.1.241, one `-p` run whose prompt asked
            // for an `Agent` call that was not to be waited on: `PreToolUse`
            // and `PostToolUse` for `Agent` both landed immediately,
            // `SubagentStart` arrived *after* the parent's `PostToolUse`, the
            // parent's `Stop` carried
            // `background_tasks: [{type: "subagent", status: "running"}]`
            // naming that same agent, and `SubagentStop` arrived after the
            // `Stop`. So a Claude Code turn ends with its subagent still
            // working, exactly as a Codex one does, and without these two the
            // row says Completed while the thread is not.
            //
            // The matcher is deliberately absent here as everywhere else,
            // though this is the one event where a matcher would have meant
            // something: Claude Code matches these two against `agent_type`,
            // not against a tool name. Selecting types would make a naming
            // detail decide whether a subagent is counted, and a miss is
            // silent.
            ManagedHookDefinition(event: "SubagentStart", matcher: nil),
            ManagedHookDefinition(event: "SubagentStop", matcher: nil),
            // The row's third line (CC-015). Officially "While assistant
            // message text is displayed", and absent from the exploration
            // document's table of events — which is why the first pass at this
            // product concluded the text was unreachable without a new
            // transport.
            ManagedHookDefinition(event: "MessageDisplay", matcher: nil),
            ManagedHookDefinition(event: "Stop", matcher: nil),
            ManagedHookDefinition(event: "StopFailure", matcher: nil)
            // Notification is deliberately absent, and it was registered until
            // the types it carries had been measured (CC-011). Measured against
            // 2.1.238, seven interactive sessions under a pty, `--settings` and
            // `--setting-sources project` only:
            //
            // * `permission_prompt` does fire -- five dialogs, five
            //   notifications -- but on a **6 s timer** rather than on the
            //   dialog opening: 6.01s, 6.03s and 6.05s after
            //   `PermissionRequest`, and pushed out to 16.50s by a keystroke
            //   4.5s in, because the dialog notifies only once the keyboard has
            //   been idle that long. Which is why nobody had ever seen it: a
            //   human who answers in under six seconds never produces one. It
            //   carries `session_id`, `cwd`, `prompt_id` and a message, and no
            //   `tool_use_id` and no `tool_name` -- while `PermissionRequest`
            //   opened the same wait six seconds earlier *with* a call id to
            //   borrow. Nothing closes it either: approving produced
            //   `PostToolUse` and `Stop`, refusing produced nothing at all, and
            //   no notification type means "resolved".
            // * `idle_prompt` arrives 60 s after the last message (the
            //   `messageIdleNotifThresholdMs` setting), four times at
            //   60.07--60.08s after `Stop`, and only while no turn is in flight
            //   and no dialog is open -- so it cannot misreport Running as a
            //   wait, because by the time it arrives the turn has already
            //   reached Completed. It is also suppressed for that turn once the
            //   user touches the keyboard after the last message, which is what
            //   the CC-019 sitting ran into.
            // * `agent_needs_input` and `agent_completed` describe a background
            //   agent's band change rather than this turn, and the payload is
            //   stamped with the current session's id and not the agent's -- so
            //   a wait opened on one would land on the wrong row. Two probes
            //   with real background subagents produced neither.
            //
            // Every type is therefore either duplicated by an event that
            // carries an id, out of scope, or later than the state it would
            // report, and the registration only cost a process launch per
            // notification. The mapping below stays: a user who has not
            // repaired an older registration still collects no diagnostic.
            //
            // SessionEnd is deliberately absent, and for a measured reason
            // rather than the one it was first excluded on. The case for it was
            // that it would retire a dead session's row sooner than the
            // sessions-directory watcher notices. Measured against 2.1.237,
            // interactive session under a pty, sampling
            // `~/.claude/sessions/<pid>.json` at 20 ms: the file is removed at
            // +15.09s and +15.08s over two runs, and `SessionEnd` arrives at
            // +15.41s in both. **The watcher's signal lands ~330 ms first.**
            //
            // `/clear` looked like the exception and is not. It leaves the
            // process alive, so no file changes and the watcher never fires --
            // but it *changes the session id*: measured `bf10d6dc…` becoming
            // `cd9d3d18…` under the same pid, with `SessionEnd(reason: clear)`
            // carrying the old one. The old id is therefore out of
            // `claude agents --json` immediately, and row construction gates on
            // exactly that. `resume` is the same shape.
            //
            // Worth knowing if this is ever reopened: the payload carries a
            // `reason`, and the group's `matcher` is matched against it, so a
            // registration can select reasons. The vocabulary is `clear`,
            // `resume`, `logout`, `prompt_input_exit`, `other` -- and only some
            // of them mean the session went away.
        ]
    }

    nonisolated func signal(
        forEvent name: String,
        toolName: String?
    ) -> HookSignal? {
        switch (name, toolName) {
        case ("UserPromptSubmit", _):
            // `source` would separate a human's prompt from our own polling,
            // but it was measured absent from every event, including a human
            // prompt in an interactive session. The working directory is what
            // separates them instead.
            .turnStarted
        case ("PreToolUse", Self.inputToolName):
            .inputWaitOpened
        case ("PreToolUse", _):
            .toolCallOpened
        case ("PermissionRequest", _):
            // Carries `tool_name` and no `tool_use_id`, so like Codex the wait
            // borrows the call that is still open. The exploration notes
            // claimed otherwise; the payload was measured and it does not.
            .approvalWaitInferred
        case ("PostToolUse", _), ("PostToolUseFailure", _), ("PermissionDenied", _):
            // All three close the call they name. Approved and ran, failed or
            // was interrupted, or was refused -- the wait is over either way.
            .toolCallClosed
        case ("Elicitation", _):
            .inputWaitOpened
        case ("ElicitationResult", _):
            .toolCallClosed
        case ("SubagentStart", _):
            .subagentStarted
        case ("SubagentStop", _):
            // Never the turn's terminal, even though it reads like one and
            // carries the same `last_assistant_message` field `Stop` does. Its
            // text is the *subagent's* closing words, and the row reports its
            // own turn -- which `carriesTurnText` already declines to read for
            // this product, so nothing here has to say so twice.
            .subagentStopped
        case ("Notification", _):
            // No longer registered, and consumed rather than reported so that a
            // user who has not repaired an older registration does not collect
            // a diagnostic per notification. Inert by measurement now rather
            // than pending one: see `managedDefinitions` for what each type was
            // measured to mean.
            .inert
        case (Self.messageDisplayEventName, _):
            // Folded into the session preview before the reducer is reached;
            // see ``messageDeltaEventName``. The case exists because the
            // registration list and this table must agree — a registered event
            // with no signal would be reported as an unrecognised payload.
            .inert
        case ("Stop", _), ("StopFailure", _):
            // One terminal. A failure is recorded as the reason a turn ended,
            // never as a state of its own -- Codex cannot report failure at
            // all, and a state only one product can reach would make the
            // shared vocabulary lie about the other.
            .turnEnded
        default:
            nil
        }
    }
}

/// The one file this integration keeps.
///
/// There is no install marker any more. The old one only had to exist, to tell
/// "our own older helper, which should be upgraded" from "a file this app never
/// installed, which must not be silently replaced" — and that distinction is
/// not worth a file, because the response to both is the same: write the
/// current script. It never provided tamper resistance either; the code's own
/// comment conceded that anything able to rewrite the script can rewrite the
/// marker beside it.
///
/// There is no `definitionsVersion` either, and §4.2 of the design proposed
/// one. It would be a second, weaker copy of a fact `hooks.json` already
/// carries: a changed definition set makes `isFullyInstalled` fail, which is
/// `mismatched`, which is the announcement. A version field could only ever
/// agree with that or be wrong about it.
nonisolated struct HookInstallRecord: Codable, Sendable, Equatable {
    var installedAt: Date?
    /// When an event was last seen, at whatever resolution one write per launch
    /// gives. Only its presence is read: it is what stops the card telling a
    /// user who trusted the hooks last week to go and trust them again.
    var lastEventAt: Date?
}

/// Reads and updates ``HookInstallRecord`` under one process-wide lock.
///
/// Two actors write this file — the registrar stamps `installedAt`, the store
/// stamps `lastEventAt` — so the read-modify-write needs serialising. One lock
/// for every path in the process is enough and costs nothing: an install is
/// user-driven and a `lastEventAt` write happens once per launch.
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

/// Registers this app's definitions in `~/.codex/hooks.json`, and installs the
/// helper they name.
///
/// **The definition is never rewritten after it is first installed**, and that
/// is the load-bearing decision in this whole integration. Codex stores trust
/// in `config.toml` under
/// `[hooks.state."<hooks.json path>:<event>:<group>:<handler>"]`, keyed by the
/// definition's content hash. Change a definition and Codex **silently stops
/// executing that one** until the user re-trusts it in `/hooks`, while every
/// untouched definition keeps firing normally. Nothing in the app can see it:
/// the delivery evidence is satisfied by the definitions that still work, and
/// the card goes on saying Connected. On 2026-08-15 this was measured with
/// `PreToolUse` dead for two consecutive turns and no indication anywhere.
///
/// So versioning lives entirely in the *script*, which is not hashed. The
/// definition names a stable path and carries nothing else — no version, no
/// port, no token, no argument that could ever need to change.
///
/// Measured on this machine, 2026-08-20: the key's third component is a
/// **numeric index**, not a matcher or a stable identifier —
/// `[hooks.state."/Users/…/.codex/hooks.json:pre_tool_use:0:0"]`, with the
/// event spelled in snake case and a fourth component indexing the handler
/// inside the group. That is what makes the append-at-the-tail rule in
/// ``ManagedHooksConfiguration`` load-bearing for the *user's own* definitions
/// rather than merely tidy: removing a group from the middle renumbers every
/// group after it and silently drops their trust.
actor CodexHookRegistrar {
    /// Registered from the vocabulary rather than listed again here.
    ///
    /// The registrar's list and the reducer's list used to be two hand-synced
    /// literals, which is a standing invitation to register a hook whose events
    /// are then discarded — silently, since a drop looks like a corrupt payload
    /// rather than a missing case.
    nonisolated private static let managedDefinitions =
        CodexHookVocabulary().managedDefinitions

    /// The Python helper this design replaced, as a single legacy identity
    /// marker.
    ///
    /// Its only job is to make an existing install read as `mismatched` rather
    /// than `absent`, so the user is asked to repair rather than told nothing
    /// is installed — which would invite a second registration beside the
    /// first. Matched by containment, so it recognises both the namespaced path
    /// and the flat one that preceded it.
    nonisolated static let legacyHelperMarker = "codex_in_notch_hook.py"

    private let paths: HookIntegrationPaths
    private let fileManager: FileManager
    nonisolated private let configurationWatcher: DirectoryChangeWatcher
    /// The last reading, and the watcher's change count when it was taken.
    ///
    /// Kept together because separately they are a race: the count is what says
    /// whether the file has moved underneath the reading, and a reading without
    /// one is a value nobody can date.
    private var cachedRegistration: (changeCount: UInt64, health: HookRegistration)?

    init(
        paths: HookIntegrationPaths = .live(),
        fileManager: FileManager = .default,
        timing: MonitorTiming = .standard
    ) {
        self.paths = paths
        self.fileManager = fileManager
        // Registration health changes when we write this file, when the user
        // edits it, and at no other time. It used to be re-derived on a
        // 60-second cadence against three file reads; it is now read once and
        // re-read on the edge that can invalidate it.
        self.configurationWatcher = DirectoryChangeWatcher(
            directoryURL: paths.hooksConfiguration,
            debounceInterval: timing.unreadStateDebounceInterval
        )
    }

    nonisolated var socketURL: URL {
        paths.hookSocket
    }

    /// The edge that says the registration may have changed underneath us.
    nonisolated func changeEvents() -> AsyncStream<Void> {
        configurationWatcher.events()
    }

    /// How complete the registration is, read from `hooks.json` and nothing
    /// else.
    ///
    /// Cached, and the cache is dropped by our own writes and by the file
    /// changing underneath us — never by a timer. That is the whole of what
    /// replaced `installationRevalidationInterval`, the cached scan and
    /// `hasManagedSupportFootprint`.
    ///
    /// The file's edge is consulted here rather than subscribed to. Subscribing
    /// made this actor one of two consumers of the same edge, and the other one
    /// is a refresh that asks this question: whichever `Task` the scheduler
    /// resumed first decided whether the answer came from before or after the
    /// edit, and losing that race cached the stale reading with no further edge
    /// coming to correct it (CR-028). Comparing the watcher's change count
    /// across the read has no order to lose.
    func registration() -> HookRegistration {
        // On a first run `hooks.json` does not exist yet, so the attach made in
        // `init` necessarily failed and nothing else would think to ask again.
        // One failed `open` per ask is cheaper than a timer -- the same trade
        // ``DirectoryChangeWatcher/attachIfNeeded()`` exists for.
        configurationWatcher.attachIfNeeded()
        // Read after that attach, not before: an attach is counted as a change,
        // because a reading taken while nothing was watching cannot be trusted
        // to have survived.
        let changeCount = configurationWatcher.changeCount
        if let cachedRegistration, cachedRegistration.changeCount == changeCount {
            return cachedRegistration.health
        }
        let scanned = managedConfiguration.registration(
            in: readConfigurationRoot()
        )
        cachedRegistration = (changeCount, scanned)
        return scanned
    }

    func invalidateRegistration() {
        cachedRegistration = nil
    }

    /// Whether the helper the definitions name is there and runnable.
    ///
    /// A `stat`, not a read. It is the one question about the helper that a
    /// refresh may still ask, because the answer can change without this app
    /// doing anything -- a user emptying the support folder -- and getting it
    /// wrong is loud: `/bin/sh` on a missing path writes to stderr, which Codex
    /// renders as a hook error in the user's session (ADR 0013).
    var isHelperInstalled: Bool {
        fileManager.isExecutableFile(atPath: paths.hookHelper.path)
    }

    /// Writes the helper if what is on disk is not what this build ships.
    ///
    /// Called at launch, on install, and when ``isHelperInstalled`` says the
    /// file has gone — never once per refresh. The question it answers can
    /// otherwise only change when the app itself is upgraded, and asking it per
    /// refresh cost a read and a string compare on the one path where a user is
    /// watching for a row to change.
    @discardableResult
    func prepareHelper() -> Bool {
        let desired = AgentHookHelper.script(socketPath: paths.hookSocket.path)
        if let installed = try? String(contentsOf: paths.hookHelper, encoding: .utf8),
           installed == desired,
           fileManager.isExecutableFile(atPath: paths.hookHelper.path) {
            return true
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
            return true
        } catch {
            return false
        }
    }

    func install() throws {
        // A no-op install writes nothing. Turning the switch on over an already
        // correct configuration used to rewrite — and reformat — a file this
        // app does not own, and with the trust key's group component measured
        // to be an array index, a rewrite is not free of consequences for the
        // user's own definitions either.
        guard registration() != .complete else { return }

        try fileManager.createDirectory(
            at: paths.agentDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard prepareHelper() else {
            throw ManagedHooksConfigurationError.verificationFailed
        }
        try configurationEditor.install()
        removeRetiredArtifacts()
        HookInstallStateFile.update(at: paths.installState, fileManager: fileManager) {
            $0.installedAt = Date()
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
        // Only ever this product's own directory, and then the shared ones if
        // nothing else is left in them. Another product's files keep both.
        removeDirectoryIfEmpty(paths.agentDirectory)
        removeDirectoryIfEmpty(paths.agentDirectory.deletingLastPathComponent())
        removeDirectoryIfEmpty(paths.supportDirectory)
    }

    // MARK: - Internals

    private func readConfigurationRoot() -> [String: Any]? {
        guard let data = try? Data(contentsOf: paths.hooksConfiguration),
              !data.isEmpty,
              let decoded = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return decoded as? [String: Any]
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

    /// The one string this app registers, and never rewrites.
    ///
    /// Codex parses `command` with a shell and has no `args` key, so the helper
    /// is named through `/bin/sh` with its path quoted. Inlining the whole
    /// helper here instead was considered and narrowly rejected: it would
    /// remove a file to write, upgrade and verify, and show a user reviewing
    /// `/hooks` exactly what will run — but the script file is the one
    /// indirection that lets behaviour change without touching the definition,
    /// and that is the entire reason this shape exists.
    nonisolated static func command(forHelper helper: URL) -> String {
        "/bin/sh \(AgentHookHelper.singleQuoted(helper.path))"
    }

    /// The strict editor for this build's definitions.
    private var managedConfiguration: ManagedHooksConfiguration {
        .command(
            Self.command(forHelper: paths.hookHelper),
            legacyCommands: [Self.legacyHelperMarker],
            definitions: Self.managedDefinitions,
            descriptionForNewFiles: "User-level Codex lifecycle hooks."
        )
    }

    /// The strict editor for this product's configuration file.
    private var configurationEditor: ManagedHooksFileEditor {
        ManagedHooksFileEditor(
            url: paths.hooksConfiguration,
            recoveryCopyURL: paths.hooksBackup,
            configuration: managedConfiguration,
            fileManager: fileManager
        )
    }
}

/// An approval the turn is blocked on, and how it can end.
///
/// `nonisolated` because the project defaults to main-actor isolation, which
/// would isolate the synthesized `Equatable` too — and this is compared inside
/// ``HookEventRepository``, off the main actor. It is a plain `Sendable` value,
/// so there is nothing for the isolation to protect.
nonisolated struct PendingApproval: Sendable, Equatable {
    let toolUseID: String
    /// Whether the id was borrowed from the open call rather than belonging to
    /// an approval tool of its own.
    ///
    /// The two shapes end differently. A `request_permissions` call is always
    /// closed by its own `PostToolUse`, whatever the human answers. A borrowed
    /// one is only closed when the human *approves*: measured 2026-08-15, a
    /// denied Bash command produced no event at all for that call -- 67 seconds
    /// of silence and then the turn's `Stop`. So a borrowed approval also has to
    /// end on any evidence the turn resumed, since Codex sends nothing while it
    /// is genuinely blocked on the prompt.
    let isInferred: Bool
}

/// A tool call that has been announced and not yet closed.
struct OpenToolUse: Sendable, Equatable {
    let id: String
    /// `tool_name` as the product reported it, used to check that a
    /// `PermissionRequest` is asking about this call and not some other one
    /// still in flight.
    let name: String?
}

/// What one agent has open, and what it is waiting for.
///
/// **A Turn used to hold exactly one of these, inline, and that was the whole
/// reason a subagent's events had to be thrown away.** Both products announce a
/// call and then ask about it in a second event that carries no id of its own
/// (`PermissionRequest`, measured on Codex `0.149.0-alpha.4.1` and Claude Code
/// `2.1.241` on 2026-08-23), so a wait can only be pinned to the call that is
/// still open. With one slot on the turn, a subagent's calls would be a second
/// stream through it: its `PreToolUse` would displace the main agent's open
/// call, and the main agent's `PostToolUse` would close the subagent's wait.
/// One per agent is what makes both streams safe, and it is all that makes them
/// safe.
nonisolated struct AgentWaitSlots: Sendable, Equatable {
    /// `tool_use_id` of an open `request_user_input` call, if any.
    var pendingInputToolUseID: String?
    /// The call the human is being asked to approve, if any.
    var pendingApproval: PendingApproval?
    /// The most recent call this agent opened and has not yet closed.
    var openToolUse: OpenToolUse?

    /// Whether this agent has anything at all left in it.
    var isEmpty: Bool {
        pendingInputToolUseID == nil && pendingApproval == nil && openToolUse == nil
    }
}

struct HookTurnState: Sendable {
    let threadID: String
    let turnID: String
    var sessionStatus: SessionStatus
    /// `tool_use_id` of an open `request_user_input` call, if any.
    var pendingInputToolUseID: String?
    /// The call the human is being asked to approve, if any.
    var pendingApproval: PendingApproval?
    /// The most recent tool call this turn opened and has not yet closed.
    ///
    /// Codex asks about an ordinary tool with a `PermissionRequest` that names
    /// the tool but carries no `tool_use_id`. The id has to come from the
    /// `PreToolUse` that announced the same call moments earlier -- see
    /// ``HookEventRepository`` -- so the approval can close on the usual pairing
    /// instead of a timer.
    var openToolUse: OpenToolUse?
    var startedAt: Date
    var lastEventAt: Date
    /// Turns this thread has already moved past.
    ///
    /// The redesign proposed deleting this, on the argument that arrival stamps
    /// taken on one serial read queue are monotonic so a late event from a
    /// retired turn cannot exist. That holds for the transport and not for the
    /// executor: ADR 0013 records Claude Code delivering a `Stop` ahead of its
    /// own subagent's `PermissionRequest` under the same `prompt_id`, and the
    /// reducer is shared. The Codex half of the claim is also unmeasured. So it
    /// stays, and it costs one `Set` per tracked thread.
    var retiredTurnIDs: Set<String>
    var promptPreview: String?
    var assistantPreview: String?
    /// Subagents this thread has started and not yet seen stop.
    ///
    /// **A fact about the thread, carried on whichever turn it currently
    /// holds.** A subagent outlives the turn that spawned it, so it is copied
    /// across every turn boundary rather than reset by one -- a user replying
    /// while a subagent is still working must not make it disappear. Keyed by
    /// `agent_id`, which is the only identity both `SubagentStart` and
    /// `SubagentStop` carry; their `turn_id` is the subagent's own and names
    /// nothing this reducer holds.
    var runningSubagentIDs: Set<String> = []
    /// When that set last changed, and nothing else.
    ///
    /// **Read by exactly one caller**, ``TerminalUnreadMembershipGate``, and
    /// deliberately not by anything that decides turn identity. It exists
    /// because `lastEventAt` must not move for a subagent -- that stamp is the
    /// reducer's only bound against a subagent's chatter fending off membership
    /// reconciliation -- and yet a finished row whose last subagent has just
    /// stopped needs a settling window measured from *that* instant. Without
    /// one, the window is measured from a main-agent `Stop` that may be minutes
    /// old (91 seconds on the 2026-08-22 measurement) and the row vanishes the
    /// moment it stops saying anything is still working.
    ///
    /// A thread-level fact like the set it stamps, so it survives every turn
    /// boundary the set survives.
    var lastSubagentBoundaryAt: Date?
    /// What each of this thread's subagents has open, keyed by `agent_id`.
    ///
    /// A thread-level fact carried across turn boundaries, exactly like
    /// ``runningSubagentIDs`` and for the same measured reason: a subagent's
    /// permission prompt can open *after* the parent's `Stop` (Claude Code
    /// 2026-08-23, `Stop` at +4.21 s and the dialog at +4.75 s), so a slot reset
    /// by the turn boundary would forget a dialog the user is still looking at.
    ///
    /// Nothing in here decides turn identity. These events carry the
    /// subagent's own `turn_id` on Codex and the parent's `prompt_id` on Claude
    /// Code, and this table reads neither.
    var subagentSlots: [String: AgentWaitSlots] = [:]

    nonisolated var status: SessionStatus {
        sessionStatus
    }

    /// Whether a subagent of this thread is sitting on a permission prompt.
    ///
    /// **Capped by the running set on purpose.** Both products stamp `agent_id`
    /// on events from agents that never announced themselves — Claude Code's
    /// own TUI background agents, and the reviewer Codex spawns for
    /// `--approve-for-me`, which is a nested agent with no `SubagentStart` of
    /// its own (both measured 2026-08-23). A slot is therefore never evidence
    /// that this thread has a subagent; only ``runningSubagentIDs`` is. The
    /// cap also means this flag can never outlive the count that draws it: what
    /// clears one clears the other, so the stuck-state risk stays the single
    /// one already accepted in `PRD.md` §6.2.
    nonisolated var subagentsAwaitingApproval: Bool {
        subagentSlots.contains { agentID, slots in
            runningSubagentIDs.contains(agentID) && slots.pendingApproval != nil
        }
    }

    /// The instant a finished row's settling window is measured from.
    ///
    /// The later of the turn's own last event and the last subagent boundary,
    /// which for every row without a subagent is simply `lastEventAt`. The two
    /// stamps stay separate because only this one is allowed to slip forward
    /// on a subagent's account; see ``lastSubagentBoundaryAt``.
    nonisolated var terminalBoundaryAt: Date {
        max(lastEventAt, lastSubagentBoundaryAt ?? lastEventAt)
    }
}

/// One Turn the product recorded as interrupted, and when.
///
/// Produced by ``ClaudeCodeTranscriptReader`` and consumed by
/// ``HookEventRepository/endInterruptedTurns(_:)``. It carries a turn identity
/// because the evidence behind it does -- which is the whole difference between
/// this and the session reading beside it, and the reason it can be held to the
/// turn it names.
struct TurnInterruption: Sendable, Equatable {
    let threadID: String
    let turnID: String
    /// When the interrupt was written, as the product stamped it.
    let endedAt: Date
}

struct HookStateSnapshot: Sendable {
    let hasObservedEvent: Bool
    let hasObservedLiveEvent: Bool
    let turns: [HookTurnState]
    let didConsumeEvents: Bool
    let diagnostic: String?

    nonisolated init(
        hasObservedEvent: Bool,
        hasObservedLiveEvent: Bool,
        turns: [HookTurnState],
        didConsumeEvents: Bool = false,
        diagnostic: String? = nil
    ) {
        self.hasObservedEvent = hasObservedEvent
        self.hasObservedLiveEvent = hasObservedLiveEvent
        self.turns = turns
        self.didConsumeEvents = didConsumeEvents
        self.diagnostic = diagnostic
    }
}

/// One hook payload, as either product sends it.
///
/// The helper forwards stdin unchanged, so field selection happens here rather
/// than in a Python string literal inside a Swift file. Both spellings of the
/// turn identity are accepted: Codex calls it `turn_id`, Claude Code calls it
/// `prompt_id` and documents it as "a UUID correlating a user prompt with all
/// subsequent events until the next prompt".
nonisolated struct HookPayload: Sendable, Decodable, Equatable {
    let hookEventName: String?
    let sessionID: String?
    let turnID: String?
    /// The subagent that produced this event, when one did.
    ///
    /// Codex stamps a subagent's hooks with its **parent's** identity: the
    /// subagent's own rollout records `session_id` as the parent thread, and
    /// its stop hooks resolve the parent's transcript path (measured
    /// 2026-08-22, CLI `0.149.0-alpha.4.1`). So `session_id` alone cannot say
    /// which agent is speaking, and this is the field that can -- it is
    /// present on `PreToolUse`, `PostToolUse`, `PermissionRequest` and
    /// `UserPromptSubmit` only when a subagent produced them, and required on
    /// `SubagentStart` and `SubagentStop`.
    ///
    /// **Claude Code stamps the parent's `session_id` too**, and puts the field
    /// on the base schema every event extends rather than on four of them:
    /// "Subagent identifier. Present only when the hook fires from within a
    /// subagent. Absent for the main thread, even in `--agent` sessions. Use
    /// this field (not `agent_type`) to distinguish subagent calls from
    /// main-thread calls." Measured 2026-08-23 against CLI 2.1.241: a
    /// subagent's `PreToolUse` and `PostToolUse` carried the parent's
    /// `session_id`, the parent's `prompt_id`, and an `agent_id` of their own.
    /// The shared identity is what makes them land on the right row; the
    /// `agent_id` is what stops them being read as the row's own work.
    let agentID: String?
    let toolName: String?
    let toolUseID: String?
    let permissionMode: String?
    let workingDirectory: String?
    let prompt: String?
    let lastAssistantMessage: String?
    let messageID: String?
    let delta: String?

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
        case prompt
        case lastAssistantMessage = "last_assistant_message"
        case messageID = "message_id"
        case delta

        /// Whether this field is the row's text rather than an identity.
        ///
        /// Text may be cut short and still be the same answer; an identity may
        /// not, so only these three are ever shortened (see
        /// ``HookPayloadDistiller``).
        nonisolated var carriesText: Bool {
            switch self {
            case .prompt, .lastAssistantMessage, .delta: return true
            default: return false
            }
        }
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hookEventName = try container.decodeIfPresent(String.self, forKey: .hookEventName)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        turnID = try container.decodeIfPresent(String.self, forKey: .turnID)
            ?? container.decodeIfPresent(String.self, forKey: .promptID)
        agentID = try container.decodeIfPresent(String.self, forKey: .agentID)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        toolUseID = try container.decodeIfPresent(String.self, forKey: .toolUseID)
        permissionMode = try container.decodeIfPresent(String.self, forKey: .permissionMode)
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        lastAssistantMessage = try container.decodeIfPresent(
            String.self,
            forKey: .lastAssistantMessage
        )
        messageID = try container.decodeIfPresent(String.self, forKey: .messageID)
        delta = try container.decodeIfPresent(String.self, forKey: .delta)
    }

    /// The payload the reducer will see, out of the bytes that landed.
    ///
    /// Field selection happens before the decode rather than after it, because
    /// the fields nobody reads are the ones that get big — see
    /// ``HookPayloadDistiller``. `JSONDecoder` is still what reads a field; it
    /// just never sees a tool result.
    nonisolated static func distilled(from body: Data) -> HookPayload? {
        guard let selected = HookPayloadDistiller.distilled(from: body) else { return nil }
        return try? JSONDecoder().decode(HookPayload.self, from: selected)
    }
}

/// Reduces one arriving payload to the fields the reducer reads.
///
/// **Why this exists.** The helper forwards stdin unchanged, so what lands on
/// the socket is the agent's whole payload — and the fields this app never
/// reads are the ones that get big. `PostToolUse` carries the tool result: a
/// `Read` of a large file, a long `Bash` stdout, a broad `Grep`. Codex's
/// `UserPromptSubmit` carries `prompt`, which is whatever the user pasted. The
/// handful of fields the reducer wants out of either total a few hundred bytes.
///
/// Until this existed the transport's cap applied to the whole payload, so one
/// oversized tool result took the lifecycle event down with it — silently, and
/// worst where the four-state model can least absorb it: a `PostToolUse` that
/// never closes the wait its `tool_use_id` opened leaves the row on *Approval
/// needed* until the turn's `Stop` (CR-030). **Nothing about the size of a tool
/// result is evidence about the turn**, so it must not decide whether the turn
/// is heard.
///
/// **What it does.** One pass over the bytes, top level only: a value under a
/// key ``HookPayload/CodingKeys`` names is kept verbatim, everything else is
/// stepped over without being copied or decoded. What comes out is a small JSON
/// object for `JSONDecoder`, which stays the authority on what a field *means*
/// — this only decides which bytes it gets to see. Two properties are the whole
/// design:
///
/// - **A cut is never half a field.** Only completed values are emitted, so a
///   payload that ends early — the transport's ceiling, or a client that
///   stopped writing — yields the fields that arrived whole rather than
///   nothing at all. A payload that is *malformed* rather than short is still
///   refused outright: fields do not get salvaged out of bytes that were never
///   the object they claimed to be (`AGENTS.md` §6.2).
/// - **An identity is never cut.** ``maximumTextBytes`` shortens the row's
///   text, where a shorter answer is the same answer; an identity longer than
///   ``maximumIdentityBytes`` is left out instead, because half a `session_id`
///   is a different session and the reducer keys on exact identity.
nonisolated enum HookPayloadDistiller {
    /// How much of one text field is carried.
    ///
    /// A row shows the first 240 characters after normalisation
    /// (``HookSessionPreviewStore/maximumCharacters``), so this is two orders
    /// of magnitude of headroom for leading whitespace and escapes, and still
    /// small enough that a pasted transcript never reaches the reducer.
    nonisolated static let maximumTextBytes = 16 * 1_024

    /// How long a value that is an identity may be before it is refused.
    ///
    /// Session and turn ids are UUIDs, tool call ids are short strings, `cwd`
    /// is a path. Anything past this is none of those.
    nonisolated static let maximumIdentityBytes = 1_024

    /// The fields worth carrying, out of the bytes that landed, or `nil` if
    /// this never was a JSON object.
    nonisolated static func distilled(from body: Data) -> Data? {
        body.withUnsafeBytes { raw in
            var scan = PayloadScan(bytes: raw)
            return scan.selectedFields()
        }
    }

    /// The keys worth carrying, and whether a long one may be cut short.
    ///
    /// Read off ``HookPayload/CodingKeys`` rather than listed a second time, so
    /// a field added to the payload cannot become one this drops on the floor.
    private static let selectedKeys: [String: Bool] = Dictionary(
        uniqueKeysWithValues: HookPayload.CodingKeys.allCases.map {
            ($0.rawValue, $0.carriesText)
        }
    )

    /// One pass over one payload's top level.
    ///
    /// A hand-written scan rather than a JSON library because the point is to
    /// *not* decode the large values: `JSONSerialization` would materialise the
    /// tool result this exists to step over, and by the time it had, the cost
    /// this avoids has already been paid.
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

        /// What one value turned out to be, and where it sat.
        ///
        /// `isComplete` is false only when the bytes ran out inside it, which
        /// is the one failure this salvages from.
        struct ScannedValue {
            let range: Range<Int>
            let isString: Bool
            let isComplete: Bool
        }

        mutating func selectedFields() -> Data? {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == Self.openBrace else { return nil }
            index += 1

            var selected = Data([Self.openBrace])
            var isFirstCarried = true
            var isFirstMember = true
            while true {
                skipWhitespace()
                guard index < bytes.count else { break }
                if bytes[index] == Self.closeBrace { break }
                if !isFirstMember {
                    // Separators are checked rather than stepped over, so that
                    // what this accepts is JSON objects and not merely things
                    // shaped like one.
                    guard bytes[index] == Self.comma else { return nil }
                    index += 1
                    skipWhitespace()
                    guard index < bytes.count else { break }
                    // `JSONDecoder` accepts a trailing comma, so this does too.
                    // Where the two could disagree, the decoder is right by
                    // definition: this decides which bytes it sees and must
                    // never decide what they say.
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
                if let carriesText = HookPayloadDistiller.selectedKeys[key],
                   let carried = carry(value, carriesText: carriesText) {
                    if !isFirstCarried { selected.append(Self.comma) }
                    isFirstCarried = false
                    selected.append(contentsOf: Array("\"\(key)\":".utf8))
                    selected.append(carried)
                }
                guard value.isComplete else { break }
            }
            selected.append(Self.closeBrace)
            return selected
        }

        /// The bytes to emit for one selected value, or `nil` to leave the
        /// field out entirely.
        private func carry(_ value: ScannedValue, carriesText: Bool) -> Data? {
            let limit = carriesText
                ? HookPayloadDistiller.maximumTextBytes
                : HookPayloadDistiller.maximumIdentityBytes
            if value.isComplete, value.range.count <= limit {
                return Data(UnsafeRawBufferPointer(rebasing: bytes[value.range]))
            }
            // Only a string can be shortened and still be itself, and only
            // where the field is the row's text rather than an identity.
            guard value.isString, carriesText else { return nil }
            let start = value.range.lowerBound + 1
            let end = value.isComplete ? value.range.upperBound - 1 : value.range.upperBound
            guard start <= end else { return nil }
            return Self.shortened(
                UnsafeRawBufferPointer(rebasing: bytes[start ..< end]),
                to: limit
            )
        }

        /// The key's raw bytes, as written.
        ///
        /// An escape inside a key is left as it was written and simply fails to
        /// match, which is right: no key this app reads contains one, so a key
        /// that spells itself with `s` is not one of ours.
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

        /// Steps over a string, starting on its opening quote.
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

        /// Steps over a number, `true`, `false` or `null`.
        ///
        /// Running out of bytes here is not completion: `12` and `128` are
        /// different numbers, and only the delimiter says which one arrived.
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

        /// The longest prefix of a string's content that is still a whole
        /// string, quoted back up.
        ///
        /// A JSON string cannot be cut just anywhere: a cut inside `\"` leaves
        /// a dangling escape, a cut inside a multi-byte character leaves bytes
        /// no decoder accepts, and a cut between the halves of a surrogate pair
        /// leaves a code point missing its other half. Any of the three makes
        /// the *whole* payload undecodable, which is the outcome this file
        /// exists to prevent — so the content is walked one character at a time
        /// and the cut taken at the last boundary that fits.
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

        /// How many bytes the character at `index` occupies, or `nil` where
        /// there is no boundary to be had after it.
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
                // A high surrogate is not a character on its own; the pair is
                // the boundary, and a half with no other half is not one.
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

/// One payload with the moment it landed.
nonisolated struct DeliveredHookEvent: Sendable {
    let payload: HookPayload
    let receivedAt: Date
}

/// The assistant text one session is currently printing.
///
/// Lock-protected rather than actor-isolated, and deliberately: deltas are
/// folded on the listener's serial read queue at up to 3.4 a second, and an
/// actor hop there would put the reducer's mailbox on a product's critical
/// path for text that changes no state. Same shape as the transport beside it
/// (`AGENTS.md` §6.3).
nonisolated final class HookSessionPreviewStore: @unchecked Sendable {
    /// How much of one message is kept.
    ///
    /// Also the memory bound: once the head is full every further delta is
    /// dropped without being stored, so the bytes held per session are decided
    /// by a constant rather than by how much the model said.
    nonisolated static let maximumCharacters = 240

    /// How many sessions' previews are held before the oldest is dropped.
    ///
    /// Previews are pruned to the live session list on every refresh, so this
    /// is a leak stop for text belonging to a session that never appears there
    /// — not a working set.
    nonisolated static let maximumRetained = 64

    private struct SessionPreview {
        /// Whichever assistant message is currently being printed. When this
        /// changes the text starts again — the newest message is the progress,
        /// and its head is what the row reports.
        let messageID: String?
        var text: String
    }

    private let lock = NSLock()
    nonisolated(unsafe) private var previewsBySessionID: [String: SessionPreview] = [:]
    nonisolated(unsafe) private var order: [String] = []
    /// The sessions the last refresh listed.
    ///
    /// Held only to qualify the edge in ``fold(delta:messageID:sessionID:)``.
    nonisolated(unsafe) private var listedSessionIDs: Set<String> = []

    nonisolated init() {}

    /// The text this session is currently printing, if any was collected.
    ///
    /// Read, not consumed. A preview stands until the message it came from is
    /// replaced or the session leaves the live list, because a turn spends most
    /// of its life between events and a row that blanked itself after one
    /// refresh would flicker rather than report.
    nonisolated func preview(forSession sessionID: String) -> String? {
        lock.lock()
        let text = previewsBySessionID[sessionID]?.text
        lock.unlock()
        // The stored form keeps its trailing space so the next delta can join
        // onto it; a row never shows one.
        guard let trimmed = text?.trimmingCharacters(in: .whitespaces),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Drops previews for sessions that are no longer live.
    nonisolated func retain(forSessions sessionIDs: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        previewsBySessionID = previewsBySessionID.filter { sessionIDs.contains($0.key) }
        order.removeAll { !sessionIDs.contains($0) }
        listedSessionIDs = sessionIDs
    }

    nonisolated func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        previewsBySessionID.removeAll()
        order.removeAll()
        listedSessionIDs.removeAll()
    }

    /// Folds one delta into the session's preview.
    ///
    /// Returns whether this session went from having no text to having some
    /// *and* the last refresh listed it, which is the only edge the change
    /// stream carries. The deltas themselves are deliberately off it — three a
    /// second is not a redraw rate — but a row holding *no* text is a different
    /// case: nothing on screen is stale, something is missing, and a turn that
    /// talks for a minute before it touches a tool sends no lifecycle event in
    /// the meantime.
    ///
    /// Without the listed test this is a 3 Hz loop rather than one wake: text
    /// from a session the list does not carry is pruned by the very refresh it
    /// asks for, which makes the next delta an absent-to-present edge again —
    /// and the row it would draw is not on screen either way.
    @discardableResult
    nonisolated func fold(
        delta: String,
        messageID: String?,
        sessionID: String
    ) -> Bool {
        lock.lock()
        let existing = previewsBySessionID[sessionID]
        lock.unlock()

        guard !delta.isEmpty else { return false }
        // A new message replaces the old one rather than extending it: the row
        // shows the message being printed now, not the whole turn concatenated.
        let carried = existing?.messageID == messageID ? (existing?.text ?? "") : ""
        let carriedLength = carried.count
        guard carriedLength < Self.maximumCharacters else { return false }
        let text = Self.normalized(
            appending: delta,
            to: carried,
            carriedLength: carriedLength
        )
        guard !text.isEmpty else { return false }

        lock.lock()
        let isFirstSinceEmpty = previewsBySessionID[sessionID] == nil
        if isFirstSinceEmpty {
            order.append(sessionID)
        }
        previewsBySessionID[sessionID] = SessionPreview(messageID: messageID, text: text)
        while order.count > Self.maximumRetained {
            previewsBySessionID.removeValue(forKey: order.removeFirst())
        }
        let appeared = isFirstSinceEmpty && listedSessionIDs.contains(sessionID)
        lock.unlock()
        return appeared
    }

    /// One line, collapsed and cut.
    ///
    /// Control characters dropped, runs of whitespace collapsed to one space,
    /// no leading space, and never longer than ``maximumCharacters``.
    ///
    /// `carried` is seeded rather than rescanned, and the running length is
    /// carried as an `Int`. Both matter: `String.count` walks grapheme breaks,
    /// so rebuilding `carried + delta` and testing `.count` after every
    /// character would be quadratic in the cap and additionally copy the whole
    /// delta. The scan touches only the new delta and stops the moment the head
    /// is full, so a 60 KB delta costs the same as a 120-byte one — measured.
    ///
    /// A single trailing space **is** kept, and the seed relies on it: measured
    /// on CLI 2.1.234, every non-final delta ends on a line break, which
    /// collapses to that trailing space — so the next delta joins onto it and
    /// no separator is invented. Trimming the tail here instead would weld the
    /// last word of one delta onto the first word of the next; the caller trims
    /// it when the text is read.
    nonisolated static func normalized(
        appending delta: String,
        to carried: String,
        carriedLength: Int
    ) -> String {
        var normalized = carried
        normalized.reserveCapacity(maximumCharacters)
        var length = carriedLength
        var pendingSpace = !normalized.isEmpty && !normalized.hasSuffix(" ")

        for character in delta {
            if character.isWhitespace {
                // Never leading: a message that opens with a newline should not
                // spend its first character on it.
                pendingSpace = !normalized.isEmpty
                continue
            }
            guard !character.unicodeScalars.contains(
                where: CharacterSet.controlCharacters.contains
            ) else { continue }

            if pendingSpace {
                normalized.append(" ")
                pendingSpace = false
                length += 1
                if length >= maximumCharacters { return normalized }
            }
            normalized.append(character)
            length += 1
            if length >= maximumCharacters { return normalized }
        }

        if pendingSpace { normalized.append(" ") }
        return normalized
    }

    /// One string, collapsed and cut the same way, for text that arrives whole.
    nonisolated static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let folded = normalized(appending: text, to: "", carriedLength: 0)
            .trimmingCharacters(in: .whitespaces)
        return folded.isEmpty ? nil : folded
    }
}

/// Fans one change signal out to every subscriber.
///
/// Same shape as ``DirectoryChangeWatcher``'s, and for the same reason: a
/// consumer subscribes once at launch and goes on receiving edges, and more
/// than one may. A single stored `AsyncStream` would have exactly one
/// consumer -- fine for the service that merges it, and a trap for anything
/// that asks a second time.
nonisolated final class HookChangeBroadcast: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    nonisolated init() {}

    nonisolated func events() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let identifier = UUID()
            lock.lock()
            continuations[identifier] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.lock()
                continuations.removeValue(forKey: identifier)
                lock.unlock()
            }
        }
    }

    nonisolated func signal() {
        lock.lock()
        let current = Array(continuations.values)
        lock.unlock()
        for continuation in current {
            continuation.yield(())
        }
    }
}

/// Payloads waiting to be reduced, in the order they landed.
///
/// The reducer is an actor and the transport is a serial GCD queue, so the
/// hand-off cannot be an `await` without giving up the ordering the read queue
/// exists to provide: two `Task`s spawned in order are not two `Task`s that run
/// in order. Appends happen on the read queue, in order; a drain swaps the
/// whole array out at once, so whichever drain runs first sees a prefix and
/// every payload is reduced exactly once, in arrival order.
nonisolated final class HookDeliveryInbox: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var pending: [DeliveredHookEvent] = []
    /// Payloads that arrived and could not be read, waiting to be counted.
    ///
    /// It rides along with the events, under the same lock and taken in the
    /// same call, because it is the same fact from the same queue: this many
    /// arrived, that many were understood. Counted on the actor and reported
    /// there, since the transport has nowhere to report to.
    nonisolated(unsafe) private var unreadable = 0

    /// One hand-off: everything that landed, and how much of it was rubbish.
    struct Delivery: Sendable {
        let events: [DeliveredHookEvent]
        let unreadable: Int
    }

    nonisolated init() {}

    nonisolated func append(_ event: DeliveredHookEvent) {
        lock.lock()
        pending.append(event)
        lock.unlock()
    }

    nonisolated func recordUnreadablePayload() {
        lock.lock()
        unreadable += 1
        lock.unlock()
    }

    nonisolated func take() -> Delivery {
        lock.lock()
        defer { lock.unlock() }
        let taken = Delivery(events: pending, unreadable: unreadable)
        pending.removeAll(keepingCapacity: true)
        unreadable = 0
        return taken
    }

    nonisolated func removeAll() {
        lock.lock()
        pending.removeAll()
        unreadable = 0
        lock.unlock()
    }
}

/// The Turn reducer, the row's text, and the evidence that the hooks are live.
///
/// **There is no backlog and no cutoff.** An event that arrives is live by
/// construction: it came down a socket into this process, from a helper that
/// ran a moment ago. `AGENTS.md` §6.2 — "historical events carry no business
/// semantics" — stops being a check on a timestamp and becomes a property of
/// the architecture, because nothing is written down for a later launch to find.
/// The file queue that made the check necessary is gone, and with it the atomic
/// temp-and-rename writes, the `time_ns` filenames, the corrupt-file
/// quarantine, the delete-after-consume, the rollback when a marker failed to
/// persist, the directory watcher and its 100 ms debounce.
///
/// **It signals a change only when the rendered projection changes.** A
/// 17-event turn is not 17 wake-ups. `AGENTS.md` §7 asks that redraw count
/// follow what is drawn; this is that rule enforced at the source rather than
/// by a debounce downstream.
actor HookEventRepository {
    private let paths: HookIntegrationPaths
    private let fileManager: FileManager
    private let clock: any MonitorClock
    private let timing: MonitorTiming
    /// How this store's events are spelled. The rules below are the same for
    /// every product; only the names arriving on the socket differ.
    nonisolated private let vocabulary: any AgentHookVocabulary
    /// Payloads whose working directory is this one are dropped.
    ///
    /// The quota reading runs `claude -p "/usage"`, which is a real session and
    /// fires real hooks. `UserPromptSubmit` would have separated it from a
    /// human's prompt by its `source` field, except that field was measured
    /// absent from every event including a human's — so the poll is pinned to a
    /// directory of its own and recognised by that instead.
    nonisolated private let ignoredWorkingDirectory: URL?
    nonisolated private let inbox = HookDeliveryInbox()
    nonisolated private let previews = HookSessionPreviewStore()
    nonisolated private let changes = HookChangeBroadcast()

    private var hasObservedEvent: Bool
    private var hasObservedLiveEvent = false
    private var didRecordEventThisLaunch = false
    // Codex trusts each hook definition by content hash, so rewriting one stops
    // Codex executing it until the user re-trusts -- silently, while the other
    // definitions keep firing. Every PostToolUse is preceded by a PreToolUse for
    // the same call, so closes without opens are direct evidence of that state.
    private var observedPreToolUseCount = 0
    private var observedPostToolUseCount = 0
    private var turnsByThreadID: [String: HookTurnState] = [:]
    /// What the last signal described, so a payload that changes nothing
    /// rendered does not wake the panel.
    private var signalledProjection: [String] = []
    /// Whether anything has been reduced since the refresh path last looked.
    ///
    /// Sticky rather than per-call, because reduction no longer happens on the
    /// refresh: a payload lands on the transport and is reduced by whichever
    /// `Task` picks the inbox up first, which may well be before the caller
    /// asks. The caller's question is "has anything moved since I last asked",
    /// and it uses the answer to decide whether the Desktop process it can see
    /// is the one those events came from -- so an answer consumed by a
    /// background drain would silently cost a whole refresh of freshness.
    private var didReduceSinceLastReport = false
    /// Payloads that arrived and could not be read at all, since launch.
    ///
    /// **Counted for the run rather than reported once.** A diagnostic that
    /// clears itself on the next refresh is one nobody is looking at when it
    /// appears; the thing worth telling a user is that this run has been
    /// dropping payloads, which is a standing fact and not an event. The count
    /// is the difference between a one-off and a flood, which is the first
    /// thing anybody would want to know (CR-029).
    private var unreadablePayloadCount = 0
    /// Payloads that read fine and described nothing this store could place.
    private var unplaceableEventCount = 0

    init(
        paths: HookIntegrationPaths = .live(),
        fileManager: FileManager = .default,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard,
        vocabulary: any AgentHookVocabulary = CodexHookVocabulary(),
        ignoredWorkingDirectory: URL? = nil
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.clock = clock
        self.timing = timing
        self.vocabulary = vocabulary
        self.ignoredWorkingDirectory = ignoredWorkingDirectory
        // A recorded event proves only that the installed definitions were
        // trusted at least once. It is configuration health evidence and never
        // current runtime evidence, which is why the turns it once accompanied
        // are not restored and never were.
        self.hasObservedEvent = HookInstallStateFile.read(
            at: paths.installState
        ).lastEventAt != nil
    }

    nonisolated func changeEvents() -> AsyncStream<Void> {
        changes.events()
    }

    // MARK: - Delivery

    /// Takes one payload off the transport, in arrival order.
    ///
    /// Runs on the listener's serial read queue, so everything here has to be
    /// bounded: one pass to select the fields, one decode of what that leaves,
    /// and for a delta a scan that stops at the head's cap. Reduction itself
    /// happens on the actor, from a snapshot of the inbox that preserves this
    /// order.
    ///
    /// **The size of the payload decides nothing.** Selection happens before
    /// the decode, so a `PostToolUse` carrying a megabyte of tool result is the
    /// same event as one carrying none (CR-030); what the transport hands over
    /// is bounded, what the reducer is told is not the same thing at all.
    nonisolated func deliver(_ body: Data, at receivedAt: Date) {
        guard let payload = HookPayload.distilled(from: body),
              let eventName = payload.hookEventName,
              payload.sessionID != nil else {
            // Nothing here can be placed: nothing at all, or not JSON, or
            // JSON without the event name or the session this app keys
            // everything on. It is still dropped — there is nowhere to
            // quarantine it to, and the quarantine was itself unread litter —
            // but it is dropped *aloud*. This is the one report that says the
            // transport is delivering and the store is not understanding,
            // which is what every silent failure this integration is designed
            // around looks like from in here (CR-029). No drain is kicked for
            // it: nothing rendered changed, and the refresh path drains every
            // cycle anyway.
            inbox.recordUnreadablePayload()
            return
        }
        // Our own quota reading is a real session firing real hooks.
        // Compared as paths rather than URLs: a URL built from a payload string
        // is not marked as a directory, and URL equality counts that, so two
        // spellings of the same folder would not match.
        if let ignoredWorkingDirectory, let cwd = payload.workingDirectory,
           URL(fileURLWithPath: cwd).standardizedFileURL.path
            == ignoredWorkingDirectory.standardizedFileURL.path {
            return
        }

        // Assistant text stops here. Folding it costs one bounded scan and
        // reaches the reducer's mailbox not at all, which is why a talking turn
        // does not wake the panel three times a second.
        if let deltaEvent = vocabulary.messageDeltaEventName, eventName == deltaEvent {
            guard let delta = payload.delta, let sessionID = payload.sessionID else {
                return
            }
            // A subagent's words are not the row's answer, and this is the one
            // path a subagent's event could reach the user by: the fold happens
            // here, before the reducer, so the `agent_id` gate down there never
            // sees it. Written from the schema rather than from an observation:
            // `agent_id` is on the base every Claude Code hook input extends,
            // and two `-p` probes on 2026-08-23 (CLI 2.1.241) produced
            // `MessageDisplay` for the main thread only -- but `-p` displays no
            // subagent text at all, and the event's own description is "while
            // assistant message text is displayed", so a session with a screen
            // is exactly the case those probes could not reach. One comparison
            // is not a price worth paying to find that out from a user.
            if let agentID = payload.agentID,
               !agentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return
            }
            if previews.fold(
                delta: delta,
                messageID: payload.messageID,
                sessionID: sessionID
            ) {
                changes.signal()
            }
            return
        }

        inbox.append(DeliveredHookEvent(payload: payload, receivedAt: receivedAt))
        Task { await self.reduceWhatHasLanded() }
    }

    /// Reduces everything the transport has handed over, in arrival order.
    ///
    /// Called by the delivery kick and again on the refresh path, so nothing
    /// can be left waiting for a `Task` that has not run yet. Taking the inbox
    /// is atomic, so the two callers cannot reduce the same payload twice or
    /// reorder each other.
    @discardableResult
    func drainDeliveredEvents() -> HookStateSnapshot {
        drainInbox()
        let reported = snapshot(didConsumeEvents: didReduceSinceLastReport)
        didReduceSinceLastReport = false
        return reported
    }

    /// The reducer's current view, without draining and without consuming what
    /// the refresh path is entitled to be told.
    func observedState() -> HookStateSnapshot {
        snapshot()
    }

    private func drainInbox() {
        let delivered = inbox.take()
        unreadablePayloadCount += delivered.unreadable
        guard !delivered.events.isEmpty else { return }

        var didReduce = false
        for event in delivered.events {
            if reduce(event) {
                didReduce = true
            } else {
                unplaceableEventCount += 1
            }
        }

        if didReduce {
            hasObservedEvent = true
            hasObservedLiveEvent = true
            didReduceSinceLastReport = true
            recordFirstEventOfThisLaunch()
        }
        signalIfProjectionChanged()
    }

    /// Stamps `lastEventAt`, once per launch and never per event.
    ///
    /// The card only ever asks whether an event has *ever* arrived, so a write
    /// per event would be file I/O buying a resolution nothing reads. One write
    /// per run keeps the value genuinely recent and costs one write per run.
    private func recordFirstEventOfThisLaunch() {
        guard !didRecordEventThisLaunch else { return }
        didRecordEventThisLaunch = true
        HookInstallStateFile.update(at: paths.installState, fileManager: fileManager) {
            $0.lastEventAt = self.clock.now()
        }
    }

    // MARK: - Previews

    nonisolated func preview(forSession sessionID: String) -> String? {
        previews.preview(forSession: sessionID)
    }

    nonisolated func retainPreviews(forSessions sessionIDs: Set<String>) {
        previews.retain(forSessions: sessionIDs)
    }

    // MARK: - Evidence that is not a hook event

    /// Ends the turns of sessions that report they have stopped working.
    ///
    /// **The one thing that ends a turn without a hook event, and why.** A user
    /// interrupt fires nothing at all: measured against 2.1.235, the hook event
    /// registry has no cancel event of any kind, and every abort path in the
    /// CLI returns before its `Stop` hooks run -- so `Esc` leaves a row saying
    /// *Running*, or worse *Approval needed*, until the session's next prompt
    /// (CC-019, #38). A timeout is not the answer to that and never will be
    /// (`AGENTS.md` §6.2): a turn that has been quiet for a while is not a turn
    /// that has ended. What arrives instead is evidence -- the session itself
    /// stops saying it is busy, in the output of the same command that answers
    /// which sessions exist.
    ///
    /// The reducer stays the only thing that computes turn state. This does not
    /// hand the caller a turn to edit; it takes a fact about a *session* and
    /// applies the same rules any event gets, which is why it lives here and
    /// not in the service that reads the list.
    ///
    /// - Parameter observations: Session id to the moment its reading *began*.
    ///   A reading that started before the turn's last event proves nothing
    ///   about it -- the state it describes may predate that event entirely --
    ///   so it is ignored. That guard is what makes a cached list safe to act
    ///   on: an answer read half a minute ago cannot retire a turn that has
    ///   moved since.
    func endTurnsForStoppedSessions(
        _ observations: [String: Date]
    ) -> HookStateSnapshot {
        for (threadID, observedAt) in observations {
            endOpenTurn(ofThread: threadID, named: nil, at: observedAt)
        }
        signalIfProjectionChanged()
        return snapshot()
    }

    /// Ends the turns the product itself recorded as interrupted.
    ///
    /// The other half of ``endTurnsForStoppedSessions(_:)``, for the sessions
    /// that half cannot reach. A session the Claude Code desktop app hosts
    /// publishes no working status at all -- the terminal interface writes that
    /// field and the desktop app runs the CLI without one -- so "the session
    /// stopped saying it was busy" is a sentence those sessions never say, and
    /// their rows went on freezing after the CLI's had stopped (CC-022, #41).
    /// What they do leave is a record in their own transcript, written at the
    /// moment of the abort.
    ///
    /// **This one names the turn, and that changes what it is allowed to do.**
    /// The session-status reading above carries no turn identity anywhere, so it
    /// may only speak about whichever turn is open. This carries the interrupted
    /// turn's `prompt_id`, which is this reducer's own turn identity, so it is
    /// held to it: an observation naming a turn the reducer is not holding does
    /// nothing rather than ending whatever happens to be open. Neither may open,
    /// name or describe a turn; both may only end one.
    func endInterruptedTurns(_ interruptions: [TurnInterruption]) -> HookStateSnapshot {
        for interruption in interruptions {
            endOpenTurn(
                ofThread: interruption.threadID,
                named: interruption.turnID,
                at: interruption.endedAt
            )
        }
        signalIfProjectionChanged()
        return snapshot()
    }

    /// Ends one open turn on evidence that is not a hook event.
    ///
    /// - Parameter named: The turn the evidence names, when it names one. Nil is
    ///   evidence that names none -- it applies to whichever turn the thread has
    ///   open, which is all a reading of a *session* can ever justify.
    private func endOpenTurn(ofThread threadID: String, named turnID: String?, at moment: Date) {
        guard var turn = turnsByThreadID[threadID],
              turnID == nil || turn.turnID == turnID,
              turn.sessionStatus != .completed,
              moment > turn.lastEventAt else {
            return
        }
        turn.sessionStatus = turn.sessionStatus.transitioned(on: .completed)
        turn.pendingInputToolUseID = nil
        turn.pendingApproval = nil
        turn.openToolUse = nil
        // Counted as the turn's last moment, so an event that really is older
        // than this evidence cannot reopen what it ended -- the same monotonic
        // rule ``mutateExactTurn(threadID:turnID:at:createWith:adoptContinuationWith:turns:mutation:)``
        // applies to everything else.
        turn.lastEventAt = moment
        turnsByThreadID[threadID] = turn
    }

    /// Forgets the threads a listing of what exists no longer names.
    ///
    /// The reducer's own bound, and the only one it has: nothing else here ever
    /// removes a thread, so without this every thread the process has ever
    /// heard from is still being projected and sorted long after its rows
    /// stopped being drawn. Both products call it, from the same refresh that
    /// prunes their previews and caches against the same list.
    ///
    /// **A list is allowed to end a thread only where it can speak for it**,
    /// which is what the two exemptions below are. What "no longer named" means
    /// differs by product and does not have to be spelled out here: a Codex
    /// thread is archived or deleted, a Claude Code session exits or has its id
    /// rotated in place by `/clear`. Either way the caller has read which ones
    /// exist and this is held to that reading.
    ///
    /// - Parameters:
    ///   - listedThreadIDs: Every thread the reading named.
    ///   - snapshotStartedAt: When that reading *began*. A reading that started
    ///     before a Turn's last event cannot have seen what that event
    ///     reported, so it is not evidence against it.
    func removeThreads(
        notIn listedThreadIDs: Set<String>,
        snapshotStartedAt: Date
    ) -> HookStateSnapshot {
        let now = clock.now()
        turnsByThreadID = turnsByThreadID.filter {
            if listedThreadIDs.contains($0.key) {
                return true
            }
            // A list request that began before the latest Hook boundary cannot
            // prove that the new Turn is gone.
            if snapshotStartedAt < $0.value.lastEventAt {
                return true
            }
            // A prompt hook can arrive just before the record that would have
            // listed its thread is written -- Codex's state DB, or the
            // `~/.claude/sessions` entry a desktop-hosted session is born with.
            // Keep a short grace period so reconciliation does not erase a new turn.
            return now.timeIntervalSince($0.value.startedAt)
                < timing.newTurnReconciliationGrace
        }
        signalIfProjectionChanged()
        return snapshot()
    }

    /// Ends every Turn this reducer is holding, and keeps everything else.
    ///
    /// **The one way a Turn ends without its own product saying so, and why it
    /// is not a guess.** Every other route into here reads an event, a list, or
    /// a status; this one reads the *producer*. A Turn is a claim about what one
    /// process is doing, so a caller that knows that process is gone knows the
    /// claim can no longer be true — and, worse, that nothing will ever arrive
    /// to falsify it, because the events that would have ended the Turn were the
    /// dead process's to send. Held rather than retired, such a Turn is
    /// permanent: no hook will name its `turn_id` again, and membership
    /// reconciliation keeps it because its thread is still listed
    /// (CR-Fable-007). Only the caller can hold this evidence, which is why the
    /// decision is not made here.
    ///
    /// The observation flags are deliberately untouched. Those hooks did fire,
    /// and the Settings card must not fall back to "never heard from" because
    /// the user restarted the app the hooks belong to.
    ///
    /// - Parameter didConsumeEvents: carried through from the drain this call
    ///   follows, so the returned snapshot still reports what that refresh took
    ///   off the socket.
    @discardableResult
    func discardTurns(didConsumeEvents: Bool = false) -> HookStateSnapshot {
        guard !turnsByThreadID.isEmpty else {
            return snapshot(didConsumeEvents: didConsumeEvents)
        }
        turnsByThreadID.removeAll()
        signalIfProjectionChanged()
        return snapshot(didConsumeEvents: didConsumeEvents)
    }

    func resetIntegrationObservation(clearTurns: Bool) {
        hasObservedEvent = false
        hasObservedLiveEvent = false
        didRecordEventThisLaunch = false
        didReduceSinceLastReport = false
        unreadablePayloadCount = 0
        unplaceableEventCount = 0
        inbox.removeAll()
        previews.removeAll()
        if clearTurns {
            turnsByThreadID.removeAll()
        }
        signalledProjection = renderedProjection()
    }

    // MARK: - The reducer

    private func reduce(_ delivered: DeliveredHookEvent) -> Bool {
        let event = delivered.payload
        guard let eventName = stableIdentifier(event.hookEventName),
              let threadID = stableIdentifier(event.sessionID) else {
            return false
        }

        guard let signal = vocabulary.signal(
            forEvent: eventName,
            toolName: event.toolName
        ) else {
            // Not this product's event at all. Reported rather than swallowed,
            // so an unrecognised shape is visible instead of disappearing.
            return false
        }

        if signal == .inert {
            // Recognised and consumed. It needs no turn to address, so it
            // answers before the identity gate below.
            return true
        }

        // Both subagent signals are facts about the thread and name no turn
        // this reducer holds, so they answer before the turn identity gate.
        switch signal {
        case .subagentStarted, .subagentStopped:
            guard let agentID = stableIdentifier(event.agentID) else { return false }
            reduceSubagentBoundary(
                signal,
                agentID: agentID,
                threadID: threadID,
                at: delivered.receivedAt
            )
            return true
        default:
            break
        }

        // **An event a subagent produced is not evidence about the thread's
        // turn, and must never be allowed to become one** -- which is why it
        // goes to a slot of the subagent's own rather than through the turn.
        // Codex stamps a subagent's hooks with the parent's `session_id` but
        // the subagent's own `turn_id`, so before these events were separated a
        // subagent's first `PreToolUse` was adopted as a continuation of the
        // row's turn: that retired the real turn id, the parent's own `Stop`
        // was then rejected as late, and nothing could end what was left. The
        // row said *Running* until the user resumed the thread or dismissed it
        // by hand. `reduceSubagentToolEvent` never touches turn identity, so
        // that shape cannot come back.
        //
        // These events were dropped outright until 2026-08-23, and what that
        // cost was the one state this product exists to report: a subagent's
        // own `PermissionRequest` never reached the row, so the row said
        // Running -- or `N subagents` -- while the product sat on a dialog.
        // Measured on both products the same day, and the arrival pattern is
        // identical: `PreToolUse` carrying a `tool_use_id`, then
        // `PermissionRequest` 20-30 ms later carrying `tool_name` and no id at
        // all. See `docs/technical-explorations/subagent-row-consistency/`
        // §6.1 and §6.3.
        if let agentID = stableIdentifier(event.agentID) {
            reduceSubagentToolEvent(
                signal,
                agentID: agentID,
                threadID: threadID,
                event: event
            )
            return true
        }

        guard let turnID = stableIdentifier(event.turnID) else {
            return false
        }

        let receivedAt = delivered.receivedAt
        // Only products that stay silent on a refusal need a wait closed by
        // unrelated activity; see `reportsApprovalDenials`.
        let infersDenials = !vocabulary.reportsApprovalDenials
        // Text arrives in the payload that changes the row, for a product that
        // sends it at all. There is no second socket and no `event_id` to
        // correlate: one connection carried the whole thing.
        let carriesText = vocabulary.carriesTurnText

        switch signal {
        case .turnStarted:
            var retiredTurnIDs = Set<String>()
            // A subagent is not ended by the user typing again, so it survives
            // the turn boundary that its spawning turn does not.
            let runningSubagentIDs = turnsByThreadID[threadID]?.runningSubagentIDs ?? []
            let lastSubagentBoundaryAt = turnsByThreadID[threadID]?
                .lastSubagentBoundaryAt
            // And neither is the dialog one of them is sitting on: the user
            // typing again does not answer it.
            let subagentSlots = turnsByThreadID[threadID]?.subagentSlots ?? [:]
            if let current = turnsByThreadID[threadID] {
                if current.turnID == turnID {
                    guard receivedAt >= current.lastEventAt else { return true }
                    retiredTurnIDs = current.retiredTurnIDs
                } else {
                    guard receivedAt > current.lastEventAt,
                          !current.retiredTurnIDs.contains(turnID) else {
                        return true
                    }
                    retiredTurnIDs = current.retiredTurnIDs
                    retiredTurnIDs.insert(current.turnID)
                }
            }
            turnsByThreadID[threadID] = HookTurnState(
                threadID: threadID,
                turnID: turnID,
                sessionStatus: .running,
                pendingInputToolUseID: nil,
                pendingApproval: nil,
                openToolUse: nil,
                startedAt: receivedAt,
                lastEventAt: receivedAt,
                retiredTurnIDs: retiredTurnIDs,
                promptPreview: carriesText
                    ? HookSessionPreviewStore.normalized(event.prompt)
                    : nil,
                assistantPreview: nil,
                runningSubagentIDs: runningSubagentIDs,
                lastSubagentBoundaryAt: lastSubagentBoundaryAt,
                subagentSlots: subagentSlots
            )
        case .approvalWaitInferred:
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .running,
                adoptContinuationWith: .running
            ) { state in
                // Codex asks about an ordinary tool -- a shell command, say -- by
                // announcing the call in `PreToolUse` and then firing this event
                // ~30ms later. This one names the tool but carries no
                // `tool_use_id`, so the wait is pinned to the call that is still
                // open for that tool: `PostToolUse` closes it on the same id, so
                // the wait ends when the human answers and no timer is involved.
                //
                // On its own this event still proves nothing -- an approval
                // pipeline that ran with no call open is not a human waiting --
                // so with nothing to pair against it stays a no-op rather than
                // opening a wait nothing could close.
                guard let openToolUse = state.openToolUse else { return }
                guard event.toolName == nil
                    || openToolUse.name == nil
                    || event.toolName == openToolUse.name else {
                    // Asking about some other call than the one still open: the
                    // pairing would be a guess, so decline to make it.
                    return
                }
                state.pendingApproval = PendingApproval(
                    toolUseID: openToolUse.id,
                    isInferred: true
                )
                state.sessionStatus = state.sessionStatus
                    .transitioned(on: .approvalNeeded)
            }
        case .inputWaitOpened:
            observedPreToolUseCount += 1
            guard let toolUseID = stableIdentifier(event.toolUseID) else {
                return false
            }
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .running,
                adoptContinuationWith: .running
            ) {
                Self.resolveInferredApproval(
                    &$0.pendingApproval,
                    activityOn: toolUseID,
                    whenInferring: infersDenials
                )
                $0.pendingInputToolUseID = toolUseID
                $0.openToolUse = OpenToolUse(id: toolUseID, name: event.toolName)
                $0.sessionStatus = $0.sessionStatus.transitioned(on: .inputNeeded)
            }
        case .approvalWaitOpened:
            observedPreToolUseCount += 1
            guard let toolUseID = stableIdentifier(event.toolUseID) else {
                return false
            }
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .running,
                adoptContinuationWith: .running
            ) {
                Self.resolveInferredApproval(
                    &$0.pendingApproval,
                    activityOn: toolUseID,
                    whenInferring: infersDenials
                )
                $0.pendingApproval = PendingApproval(
                    toolUseID: toolUseID,
                    isInferred: false
                )
                $0.openToolUse = OpenToolUse(id: toolUseID, name: event.toolName)
                $0.sessionStatus = $0.sessionStatus.transitioned(on: .approvalNeeded)
            }
        case .toolCallOpened:
            // No state change on its own, but it records the open call so an
            // approval that carries no id of its own has something to pair
            // with. It also proves the definition runs.
            observedPreToolUseCount += 1
            guard let toolUseID = stableIdentifier(event.toolUseID) else {
                return true
            }
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                // An ordinary tool call is not evidence a turn began, so it
                // never creates one -- it only annotates a turn already known.
                createWith: nil,
                adoptContinuationWith: .running
            ) {
                Self.resolveInferredApproval(
                    &$0.pendingApproval,
                    activityOn: toolUseID,
                    whenInferring: infersDenials
                )
                $0.openToolUse = OpenToolUse(id: toolUseID, name: event.toolName)
                if $0.pendingInputToolUseID == nil, $0.pendingApproval == nil {
                    $0.sessionStatus = $0.sessionStatus.transitioned(on: .running)
                }
            }
        case .toolCallClosed:
            observedPostToolUseCount += 1
            guard let toolUseID = stableIdentifier(event.toolUseID) else {
                return true
            }
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: nil,
                adoptContinuationWith: .running
            ) {
                if $0.pendingInputToolUseID == toolUseID {
                    $0.pendingInputToolUseID = nil
                }
                if $0.pendingApproval?.toolUseID == toolUseID {
                    $0.pendingApproval = nil
                } else {
                    Self.resolveInferredApproval(
                        &$0.pendingApproval,
                        activityOn: toolUseID,
                        whenInferring: infersDenials
                    )
                }
                if $0.openToolUse?.id == toolUseID {
                    $0.openToolUse = nil
                }
                // Only resume Running once no wait is still open: an unrelated
                // tool finishing must not clear a prompt the human has not
                // answered. The state machine only enters a wait from Running,
                // so at most one of these is ever set.
                if $0.pendingInputToolUseID != nil {
                    $0.sessionStatus = $0.sessionStatus.transitioned(on: .inputNeeded)
                } else if $0.pendingApproval != nil {
                    $0.sessionStatus = $0.sessionStatus.transitioned(on: .approvalNeeded)
                } else {
                    $0.sessionStatus = $0.sessionStatus.transitioned(on: .running)
                }
            }
        case .turnEnded:
            let assistantPreview = carriesText
                ? HookSessionPreviewStore.normalized(event.lastAssistantMessage)
                : nil
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .completed,
                adoptContinuationWith: .completed
            ) {
                // The product intentionally exposes one terminal state. Stop,
                // completed, failed, and interrupted all converge to Completed.
                $0.sessionStatus = $0.sessionStatus.transitioned(on: .completed)
                $0.pendingInputToolUseID = nil
                $0.pendingApproval = nil
                $0.assistantPreview = assistantPreview
            }
        case .subagentStarted, .subagentStopped, .inert:
            // All three are answered above, before the turn identity gate.
            break
        }
        return true
    }

    /// Records a subagent starting or stopping on a thread.
    ///
    /// **Deliberately not routed through
    /// ``mutateExactTurn(threadID:turnID:at:createWith:adoptContinuationWith:mutation:)``.**
    /// That function's whole job is exact turn identity, and these two events
    /// carry the *subagent's* turn id -- a value this reducer has never held
    /// and must never adopt. What they carry that is useful is `agent_id`,
    /// which pairs a start with its stop across a parent turn boundary.
    ///
    /// It attaches to a turn the thread already has and never creates one: a
    /// subagent is something a turn spawned, so a thread with no turn open has
    /// no row for the mark to appear on. The arrival stamp is deliberately not
    /// taken as `lastEventAt` -- this is not activity by the turn, so it must
    /// not move the stamp where it would let a subagent's chatter fend off the
    /// membership reconciliation that is the reducer's only bound. It is kept
    /// separately as ``HookTurnState/lastSubagentBoundaryAt``, which one caller
    /// reads and nothing about turn identity does.
    private func reduceSubagentBoundary(
        _ signal: HookSignal,
        agentID: String,
        threadID: String,
        at receivedAt: Date
    ) {
        guard var turn = turnsByThreadID[threadID] else { return }
        switch signal {
        case .subagentStarted:
            turn.runningSubagentIDs.insert(agentID)
        case .subagentStopped:
            turn.runningSubagentIDs.remove(agentID)
            // The slot goes with it, and this is the rule that guarantees
            // nothing is ever left waiting. A *refused* call closes with no
            // event of its own on either product -- Codex measured 2026-08-15
            // (67 seconds of silence), Claude Code measured 2026-08-23, where
            // `PermissionDenied` turns out to fire only for the auto-mode
            // classifier's own refusals and never for a human's. After a
            // refusal this was the only event that arrived at all.
            turn.subagentSlots.removeValue(forKey: agentID)
        default:
            return
        }
        // Monotonic, like every other stamp here: a boundary that arrived out
        // of order must not wind a settling window backwards.
        turn.lastSubagentBoundaryAt = max(
            turn.lastSubagentBoundaryAt ?? receivedAt,
            receivedAt
        )
        turnsByThreadID[threadID] = turn
    }

    /// Records what one subagent has open, and what it is waiting for.
    ///
    /// **The same five signals the turn understands, in a slot of the
    /// subagent's own.** It exists because a subagent's approval is a fact the
    /// row has to report -- the product is sitting on a dialog -- and because
    /// routing it through the turn's single slot would let two streams close
    /// each other's waits.
    ///
    /// It borrows nothing from turn identity and gives nothing back to it. Like
    /// ``reduceSubagentBoundary(_:agentID:threadID:at:)`` it attaches to a turn
    /// the thread already has and never creates one, and it deliberately does
    /// not move `lastEventAt`: a subagent's chatter must not fend off the
    /// membership reconciliation that is this reducer's only bound. It does
    /// not move ``HookTurnState/lastSubagentBoundaryAt`` either -- that stamp
    /// belongs to the two boundaries, because what it dates is when this
    /// thread stopped working, and a call in the middle of a subagent's life
    /// says nothing about that.
    private func reduceSubagentToolEvent(
        _ signal: HookSignal,
        agentID: String,
        threadID: String,
        event: HookPayload
    ) {
        guard var turn = turnsByThreadID[threadID] else { return }
        var slots = turn.subagentSlots[agentID] ?? AgentWaitSlots()

        // **Always infer, whichever product this is.** The turn-level rule asks
        // `reportsApprovalDenials`, and for a subagent the honest answer is
        // "no" on both products: measured 2026-08-23, a human's refusal
        // produces no event whatsoever on Claude Code (its `PermissionDenied`
        // is gated on the auto-mode classifier), which is the shape Codex was
        // already known to have. The reason Claude Code switched the inference
        // off does not reach here either: that was a `Stop` arriving ahead of
        // its own subagent's `PermissionRequest`, and those two now land in
        // different slots, so one stream's activity can no longer end the
        // other's wait.
        let infersDenials = true

        switch signal {
        case .toolCallOpened, .inputWaitOpened, .approvalWaitOpened:
            observedPreToolUseCount += 1
            guard let toolUseID = stableIdentifier(event.toolUseID) else { break }
            Self.resolveInferredApproval(
                &slots.pendingApproval,
                activityOn: toolUseID,
                whenInferring: infersDenials
            )
            slots.openToolUse = OpenToolUse(id: toolUseID, name: event.toolName)
            switch signal {
            case .inputWaitOpened:
                // Tracked so the pairing is right, and deliberately not drawn:
                // whether a subagent's question reaches the user at all has not
                // been measured, and a hint this product cannot stand behind is
                // worse than no hint.
                slots.pendingInputToolUseID = toolUseID
            case .approvalWaitOpened:
                slots.pendingApproval = PendingApproval(
                    toolUseID: toolUseID,
                    isInferred: false
                )
            default:
                break
            }
        case .approvalWaitInferred:
            // The subagent's own open call, never the row's. Measured on both
            // products: `PermissionRequest` carries `tool_name` and no
            // `tool_use_id`, 20-30 ms after the `PreToolUse` that announced the
            // call it is asking about.
            guard let openToolUse = slots.openToolUse else { break }
            guard event.toolName == nil
                || openToolUse.name == nil
                || event.toolName == openToolUse.name else {
                break
            }
            slots.pendingApproval = PendingApproval(
                toolUseID: openToolUse.id,
                isInferred: true
            )
        case .toolCallClosed:
            observedPostToolUseCount += 1
            guard let toolUseID = stableIdentifier(event.toolUseID) else { break }
            if slots.pendingInputToolUseID == toolUseID {
                slots.pendingInputToolUseID = nil
            }
            if slots.pendingApproval?.toolUseID == toolUseID {
                slots.pendingApproval = nil
            } else {
                Self.resolveInferredApproval(
                    &slots.pendingApproval,
                    activityOn: toolUseID,
                    whenInferring: infersDenials
                )
            }
            if slots.openToolUse?.id == toolUseID {
                slots.openToolUse = nil
            }
        case .turnStarted, .turnEnded, .subagentStarted, .subagentStopped, .inert:
            // A subagent's own turn boundary names nothing this reducer holds,
            // and the two subagent boundaries answered before this was reached.
            return
        }

        if slots.isEmpty {
            turn.subagentSlots.removeValue(forKey: agentID)
        } else {
            turn.subagentSlots[agentID] = slots
        }
        turnsByThreadID[threadID] = turn
    }

    /// Ends an inferred approval as soon as another call shows any activity.
    ///
    /// An approved call closes with its own `PostToolUse`, but a *denied* one is
    /// never closed at all -- measured 2026-08-15: the prompt was followed by 67
    /// seconds of silence and then the turn's `Stop`, with no event whatsoever
    /// for the denied call. `Stop` alone would therefore be the only way out,
    /// which leaves the row claiming the user is still being asked for the whole
    /// rest of a turn that carried on working after the denial.
    ///
    /// Activity on a *different* call is proof the human has answered, because
    /// Codex emits nothing at all while a turn is genuinely blocked on the
    /// prompt. An approval that owns its `tool_use_id` needs none of this and is
    /// left strictly alone: it always gets its closing event.
    /// Takes the wait itself rather than the turn, because a subagent's slot
    /// needs exactly this rule and has no turn of its own to pass.
    nonisolated private static func resolveInferredApproval(
        _ pendingApproval: inout PendingApproval?,
        activityOn toolUseID: String,
        whenInferring infersDenials: Bool
    ) {
        guard infersDenials,
              let pending = pendingApproval,
              pending.isInferred,
              pending.toolUseID != toolUseID else {
            return
        }
        pendingApproval = nil
    }

    private func mutateExactTurn(
        threadID: String,
        turnID: String,
        at date: Date,
        createWith sessionStatus: SessionStatus?,
        adoptContinuationWith continuationStatus: SessionStatus?,
        mutation: (inout HookTurnState) -> Void
    ) {
        var state: HookTurnState
        if let current = turnsByThreadID[threadID] {
            if current.turnID == turnID {
                guard date >= current.lastEventAt else { return }
                state = current
            } else {
                guard let continuationStatus,
                      date > current.lastEventAt,
                      !current.retiredTurnIDs.contains(turnID) else {
                    return
                }
                var retiredTurnIDs = current.retiredTurnIDs
                retiredTurnIDs.insert(current.turnID)
                state = HookTurnState(
                    threadID: threadID,
                    turnID: turnID,
                    sessionStatus: continuationStatus,
                    pendingInputToolUseID: nil,
                    pendingApproval: nil,
                    openToolUse: nil,
                    startedAt: current.startedAt,
                    lastEventAt: date,
                    retiredTurnIDs: retiredTurnIDs,
                    promptPreview: current.promptPreview,
                    assistantPreview: nil,
                    runningSubagentIDs: current.runningSubagentIDs,
                    lastSubagentBoundaryAt: current.lastSubagentBoundaryAt,
                    subagentSlots: current.subagentSlots
                )
            }
        } else {
            guard let sessionStatus else { return }
            state = HookTurnState(
                threadID: threadID,
                turnID: turnID,
                sessionStatus: sessionStatus,
                pendingInputToolUseID: nil,
                pendingApproval: nil,
                openToolUse: nil,
                startedAt: date,
                lastEventAt: date,
                retiredTurnIDs: [],
                promptPreview: nil,
                assistantPreview: nil
            )
        }
        mutation(&state)
        state.lastEventAt = max(state.lastEventAt, date)
        turnsByThreadID[threadID] = state
    }

    private func stableIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    // MARK: - What is drawn, and when it is worth saying so

    /// Everything a row draws that this store is the source of.
    ///
    /// Turns only. A streamed delta is not here and is not meant to be: a row's
    /// text updates on whatever refresh the turn's own lifecycle events cause,
    /// and the alternative is a redraw 3.4 times a second for a line the user is
    /// already reading (`AGENTS.md` §7, and the measurement in
    /// `system-architecture.md` §6). The one case that does need an edge — a row
    /// with *nothing* to show — carries its own, qualified by whether the
    /// session is listed at all; see ``HookSessionPreviewStore/fold``.
    private func renderedProjection() -> [String] {
        turnsByThreadID.values
            .map { turn in
                [
                    turn.threadID,
                    turn.turnID,
                    String(describing: turn.sessionStatus),
                    turn.promptPreview ?? "",
                    turn.assistantPreview ?? "",
                    // The row draws how many, so a second one starting is a
                    // change the panel has to be woken for.
                    String(turn.runningSubagentIDs.count),
                    // And whether one of them is waiting on a human, which
                    // changes the collapsed summary as well as the row.
                    String(turn.subagentsAwaitingApproval)
                ].joined(separator: "\u{1}")
            }
            .sorted()
    }

    private func signalIfProjectionChanged() {
        let current = renderedProjection()
        guard current != signalledProjection else { return }
        signalledProjection = current
        changes.signal()
    }

    /// Set once enough tool calls have closed without a single one opening.
    ///
    /// Three is past coincidence and still reached within one short turn. It is
    /// the only runtime evidence that a definition has lost trust, and it is
    /// kept even though the frozen definition closes most of the hole it covers
    /// — a user editing `config.toml`, or a Codex update that rehashes, can
    /// still reach the state.
    ///
    /// Only implications where absence is genuinely evidence belong here.
    /// `PermissionRequest` fires only when a human is asked, so its silence
    /// proves nothing and it must never be probed.
    private var undeliveredPreToolUseDiagnostic: String? {
        guard observedPreToolUseCount == 0, observedPostToolUseCount >= 3 else {
            return nil
        }
        return "\(vocabulary.agent.displayName) is not running the PreToolUse hook, "
            + "so Input needed and Approval needed cannot be shown. "
            + vocabulary.restoreDefinitionAdvice
    }

    /// Everything this store currently has to say about its own health.
    ///
    /// Three independent facts, joined rather than ranked: payloads that could
    /// not be read, events that could not be placed, and a definition that has
    /// stopped firing. They have different causes and can hold at once, so
    /// picking one to report would hide the others behind it.
    private var reportedDiagnostic: String? {
        let sentences = [
            unreadablePayloadCount > 0
                ? "Ignored \(Self.payloadCount(unreadablePayloadCount)) that could not be read."
                : nil,
            unplaceableEventCount > 0
                ? "Ignored \(Self.payloadCount(unplaceableEventCount)) with no stable identity, or of an unsupported kind."
                : nil,
            undeliveredPreToolUseDiagnostic
        ].compactMap { $0 }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    private static func payloadCount(_ count: Int) -> String {
        count == 1 ? "1 hook payload" : "\(count) hook payloads"
    }

    /// The drain the transport kicks, which reports to nobody.
    private func reduceWhatHasLanded() {
        drainInbox()
    }

    private func snapshot(didConsumeEvents: Bool = false) -> HookStateSnapshot {
        HookStateSnapshot(
            hasObservedEvent: hasObservedEvent,
            hasObservedLiveEvent: hasObservedLiveEvent,
            turns: turnsByThreadID.values.sorted { $0.startedAt > $1.startedAt },
            didConsumeEvents: didConsumeEvents,
            diagnostic: reportedDiagnostic
        )
    }
}
