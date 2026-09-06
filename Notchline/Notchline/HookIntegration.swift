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

    /// The paths one product's live monitoring is actually built over, chosen
    /// by kind.
    ///
    /// The two spellings that already exist answer for one product each —
    /// ``live(agent:fileManager:)`` for Codex and
    /// ``liveClaudeCode(fileManager:)`` for Claude Code — so a caller holding
    /// an ``AgentKind`` and nothing else has no way through them. Settings is
    /// that caller: its Products card offers to open the folder each product's
    /// hooks are registered in, for a product it knows only by kind. Routed to
    /// those two rather than spelling either path a second time, so a file that
    /// moves moves for the button as well as for the writer.
    nonisolated static func live(
        for agent: AgentKind,
        fileManager: FileManager = .default
    ) -> HookIntegrationPaths {
        switch agent {
        case .codex:
            HookIntegrationPaths.live(fileManager: fileManager)
        case .claudeCode:
            HookIntegrationPaths.liveClaudeCode(fileManager: fileManager)
        }
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

/// The few lines both products run once per event, and the channel one
/// answer comes back on.
///
/// Deliberately the smallest thing that can carry one payload:
///
/// - **It speaks on one stream, and only when it was asked to.** `exec
///   2>/dev/null` covers the whole script, including the shell's own "not
///   found" if `nc` is ever absent, because both products *print* a hook's
///   stderr — a helper that reported "the app is not running" would be exactly
///   the noise this transport removes (ADR 0013). Stdout is the other half of
///   that rule and is no longer silenced unconditionally: both products *parse*
///   it for a decision, and on the events that ask a person that is precisely
///   what this app now has to say. On every other event stdout is still sent to
///   `/dev/null` at the call, so the 99.8% of events nobody is being asked
///   about keep the older, stricter silence by construction rather than by the
///   app remembering not to write.
/// - **It always succeeds.** A non-zero exit is rendered as `<event> hook
///   error` in an interactive session, so the `exit 0` is load-bearing on every
///   path: no socket (the app is closed), a stale socket file, a refused
///   connection, a missing `nc`. `nc` itself is measured to exit **1** on both
///   shapes of "nothing is listening" (2026-09-05, no socket file and a socket
///   file whose owner has gone), which is why this cannot be an `exec` — that
///   would hand the product `nc`'s status instead of ours.
/// - **It cannot hang.** `-w` bounds the case where this app has accepted the
///   connection but wedged before reading it. Measured: 6.3 ms when the app is
///   listening, 17 ms when it is not, and the window in the wedged case.
/// - **It forwards the payload unfiltered.** Field selection, truncation and
///   event naming are Swift, where they are testable, rather than a string
///   literal only one integration test ever executes.
///
/// **One literal argument selects the wait**, and the registration is what
/// passes it: bare on a lifecycle event, ``answeringArgument`` on the events
/// that open a wait for a person. That keeps the tight bound where it belongs —
/// a wedged app still costs one second on every event nobody is being asked
/// about — while the answering event gets a window a person can actually answer
/// inside. Reading the payload to decide, which is what a compiled helper would
/// do, was rejected: the registration already knows which event it is
/// registering, so the shell never has to parse anything.
///
/// **`nc -U` holds the connection open after its stdin reaches EOF**, which is
/// the whole of why decision 4 stands and no compiled helper is needed
/// (measured 2026-09-05 against a Unix-domain server on this machine): Apple's
/// `nc` shuts down only its *write* half on EOF — the server sees end-of-payload
/// immediately — and goes on reading until the peer closes or `-w` expires.
/// `-w` is an idle deadline rather than a total one, so a long window costs
/// nothing when the answer comes early: `-w 3600` against a server that replied
/// after 3 s returned in 3.04 s. A 128 KiB payload made the round trip in 60 ms,
/// and the app closing the connection — or dying — released the client at once.
///
/// **One variable keeps an agent out of the notch entirely.**
/// ``suppressionEnvironmentKey`` is read before anything else, so a wrapper can
/// set it on a nested agent's child process and that agent raises no row, no
/// request and no held connection. It is cheap here and awkward to retrofit
/// once people rely on the rows.
///
/// `nc -U` rather than a compiled helper of our own because it is already on
/// every macOS and needs no target, no signing and no upgrade path. The cost of
/// the extra process is the difference between 6.3 ms and the 4.1 ms a compiled
/// equivalent measured — nothing, next to what it saves. Against the Python
/// helper it replaces on the Codex side it is 6.3 ms against 30 ms, which at
/// ~17 events per turn is 107 ms against 510 ms of CPU per turn (ADR 0013).
nonisolated enum AgentHookHelper {
    /// The literal `$1` that selects the long wait.
    ///
    /// A word rather than the number of seconds, so that changing the window
    /// changes the *script* and not the registered definition — which on Codex
    /// is a hash the user has trusted (ADR 0014).
    nonisolated static let answeringArgument = "wait"

    /// How far inside the registered timeout the helper's own window sits.
    ///
    /// A minute, and the gap only has to cover the microseconds between `nc`
    /// giving up and the shell exiting — it is this wide because the cost of
    /// widening it is a person who waited 59 minutes getting nothing either
    /// way, and the cost of narrowing it is the product killing a hook and
    /// printing that in the user's session.
    nonisolated static let answeringSlackSeconds = 60

    /// Set on an agent's process, this keeps it out of the notch.
    ///
    /// Checked before the payload is even read, so the cost of opting out is
    /// one `sh` and no connection.
    nonisolated static let suppressionEnvironmentKey = "NOTCHLINE_HOOKS_OFF"

    /// - Parameter answerWindowSeconds: how long `nc` waits for this app's
    ///   answer on the events that ask. It has to be *inside* the timeout the
    ///   definition registers: a helper that gives up on its own exits 0, and
    ///   one the product kills is a hook error in the user's session.
    nonisolated static func script(
        socketPath: String,
        answerWindowSeconds: Int
    ) -> String {
        """
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
        /usr/bin/nc -U -w 1 \(singleQuoted(socketPath)) >/dev/null
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
    /// Whether `UserPromptSubmit` carries the prompt the row falls back to.
    ///
    /// **Both products, and Claude Code only since this line existed.** A turn
    /// that has not said anything yet has nothing else to show, and what the
    /// row showed instead was whatever the *previous* turn finished saying --
    /// or, on a session's first turn, nothing at all. Codex answers that with
    /// the prompt (PRD §7, `Running`), and there is no reason for the other
    /// product to answer it differently: the field is in the payload that
    /// starts the turn, and reading it costs one normalisation per turn.
    nonisolated var carriesPromptText: Bool { get }
    /// Whether the terminal event carries the turn's closing words.
    ///
    /// Codex's `Stop` carries `last_assistant_message`, which is exactly what
    /// its finished row draws and arrives with the event that finishes it.
    /// Claude Code's carries one too and it is deliberately not read: that
    /// product's assistant text all comes from `MessageDisplay` (PRD §7), and
    /// the final message is the last thing that event delivered -- so reading
    /// the terminal's copy as well would be a second source for one line,
    /// differing from the first only in where it was cut.
    nonisolated var carriesFinalAnswerText: Bool { get }
    /// The event that streams assistant text as it is displayed, if any.
    ///
    /// Folded into a per-session preview rather than reduced, and deliberately
    /// off the change stream except on its absent-to-present edge: measured
    /// against CLI 2.1.234, one 1561-character message arrived as eleven
    /// deltas, mean 0.29 s apart. Three a second is not a redraw rate.
    nonisolated var messageDeltaEventName: String? { get }
    /// Whether a tool call opening is worth waking the panel for.
    ///
    /// It changes nothing this reducer holds — the row draws no tool name and
    /// the status stays Running — so ``renderedProjection()`` cannot see it,
    /// and by that projection alone a turn that talks for five minutes between
    /// two status changes never redraws once.
    ///
    /// It is still the moment the row's live text moves, for the product whose
    /// text is not in here. Codex prints its commentary and *then* calls the
    /// tool, and that commentary is read from the App Server against the turn
    /// this reducer owns (``LiveCodexMonitorService/refreshTurnProgressInBackground(requests:)``), so this
    /// is the only local evidence that there is something new to ask for. One
    /// wake per call, not per event: the paired close is deliberately not
    /// counted, because nothing is printed by a tool finishing.
    ///
    /// Claude Code answers `false` and needs to: its text arrives here as
    /// `MessageDisplay` deltas, so the fold itself knows when the row's line
    /// changed and says so directly (``HookSessionPreviewStore/fold``). Waking
    /// on its tool calls as well would be a second wake for the same edge.
    nonisolated var wakesOnToolCallOpened: Bool { get }
    /// Whether a prompt this thread held back waits for the product's own
    /// record to name it, rather than for an event under its turn id.
    ///
    /// **The two products need opposite answers, and the difference is whether
    /// anything can run under a thread's identity without saying so.** Codex
    /// has one that can: the `--approve-for-me` reviewer is a session of its
    /// own whose hooks carry the parent thread's `session_id`, its own
    /// `turn_id`, and **no `agent_id`** -- so an event under a held turn id
    /// proves nothing there, and the only thing that can settle it is the
    /// thread's own rollout (``HookEventRepository/adoptTurnsOnRecord(_:)``).
    ///
    /// Claude Code has no such caller and no such record. Its subagents stamp
    /// `agent_id`, so they never reach turn identity at all, and its one
    /// nested agent -- the read-only fork Claude Desktop opens -- runs with
    /// `settingSources: []` and fires no hook of any kind (`CONTEXT.md`, *Side
    /// chat*). So a held prompt there is the user's own next turn, and taking
    /// it away from an event would cost the one case it exists for: **a human
    /// refusing an approval aborts that turn with no hook at all** (measured
    /// 2026-08-23, CLI 2.1.241, twice), so the turn stays open and the user's
    /// next prompt is exactly the held case -- with nothing else to redeem it,
    /// the row would sit on the abandoned turn until the prompt after that.
    nonisolated var settlesHeldTurnsFromRecord: Bool { get }
    /// What to tell the user when a definition this product registered has
    /// stopped running.
    ///
    /// The reducer is shared and the repair is not: Codex keys trust by content
    /// hash and takes it back through `/hooks`, while Claude Code's
    /// registration is the user's own file and is repaired by editing it. The
    /// sentence used to name Codex from inside the shared reducer, which made
    /// it wrong for half the events it described (CR-029).
    nonisolated var restoreDefinitionAdvice: String { get }
    /// How long this product may be kept waiting on the one definition that
    /// carries an answer back.
    ///
    /// The value is per product because the products' own numbers are: a
    /// released notch app registers **1 hour** on Codex and **24 hours** on
    /// Claude Code for `PermissionRequest`, and that its users answer from its
    /// UI is the evidence that both products honour a window this long. Every
    /// other definition keeps ``ManagedHookDefinition/lifecycleTimeoutSeconds``.
    ///
    /// Chosen to be **final**. On Codex the registered definition is a hash the
    /// user has trusted, and changing it silently stops that definition firing
    /// until they trust it again (ADR 0014) — so this is the second and last
    /// re-trust that definition is worth.
    nonisolated var answeringTimeoutSeconds: Int { get }
    /// How this product spells an answer on the connection it is waiting on.
    ///
    /// Named from here so the reducer needs one injection point rather than
    /// two, and a type of its own so that reading an event and answering it stay
    /// separate kinds of knowledge. See ``RequestAnswering``.
    nonisolated var answering: any RequestAnswering { get }
    /// `nil` means "not recognised": drop it and say so.
    nonisolated func signal(forEvent name: String, toolName: String?) -> HookSignal?

    /// The request this event puts to a person, out of the arguments it carried.
    ///
    /// Read **here**, in the actor, at the moment the wait opens -- the one
    /// place holding the signal, the event name, the tool name and this
    /// vocabulary at once. Not in the view, which stays passive; not on
    /// ``HookPayload``, which would put both products' tool names into a
    /// product-free type; and not in the two row builders, where the mapping
    /// would be written twice and could drift once.
    ///
    /// `nil` where nothing readable arrived, which is an ordinary answer and
    /// never an empty request: a wait with nothing to show still opens, and the
    /// row still says a person is wanted (`AGENTS.md` §6, failures fail closed).
    nonisolated func request(
        forEvent name: String,
        toolName: String?,
        toolInput: JSONValue?,
        openedBy toolUseID: String
    ) -> AgentRequest?
}

extension AgentHookVocabulary {
    /// The event whose connection an answer travels back on, if any.
    ///
    /// Read off the registration rather than named a second time: a definition
    /// that hands the helper ``AgentHookHelper/answeringArgument`` is exactly a
    /// definition whose connection is being held open, so the transport and the
    /// registration cannot disagree about which one that is.
    nonisolated var answeringEventName: String? {
        managedDefinitions.first { $0.argument != nil }?.event
    }

    /// How long the helper waits for an answer, which is inside
    /// ``answeringTimeoutSeconds`` by construction.
    ///
    /// Derived rather than declared beside it, because the ordering between the
    /// two is the load-bearing part and a pair of literals is a pair that can
    /// drift. The helper has to give up **first**: one that does exits 0 and
    /// says nothing, and one the product kills is a hook error printed in the
    /// user's session, which is the noise this transport exists to remove
    /// (ADR 0013).
    nonisolated var answerWindowSeconds: Int {
        answeringTimeoutSeconds - AgentHookHelper.answeringSlackSeconds
    }

    /// Whether this event's `tool_input` is a request a person is being asked
    /// about, rather than a call's arguments nobody reads.
    ///
    /// **Derived from the signal table rather than listed a second time**, the
    /// same discipline ``HookPayloadDistiller`` applies to the key list: an
    /// event that opens a wait carries its request, and no other event does.
    /// `PostToolUse` is ``HookSignal/toolCallClosed`` and is therefore refused
    /// *by construction* rather than by a rule somebody has to remember, which
    /// is exactly the shape CR-030 turned out to be.
    ///
    /// The tempting gate is the one `answer-in-notch.md` §14.1 wrote --
    /// "`PermissionRequest` and `PreToolUse`" -- and it is far wider than it
    /// sounds: `PreToolUse` fires for *every* tool call and is one-to-one with
    /// `PostToolUse`, so it halves the volume rather than removing it. Measured
    /// 2026-09-05 over 30,909 tool calls in this machine's `~/.claude/projects`
    /// (p50 263 B, p99 8,951 B, max 136,560 B), that gate would copy and decode
    /// about 28 MB of arguments nobody reads, on the serial read queue. This one
    /// admits 56 of those 30,909 calls: **0.18%**.
    nonisolated func carriesRequest(forEvent name: String, toolName: String?) -> Bool {
        switch signal(forEvent: name, toolName: toolName) {
        case .inputWaitOpened, .approvalWaitOpened, .approvalWaitInferred:
            return true
        default:
            return false
        }
    }
}

nonisolated struct CodexHookVocabulary: AgentHookVocabulary {
    /// One hour, and the same hour a released notch app registers here.
    ///
    /// Declared as a `static` as well as satisfying the protocol so that
    /// ``managedDefinitions`` — which is where the number has to appear — can
    /// name it without an instance.
    nonisolated static let answeringTimeout = 60 * 60
    nonisolated let answeringTimeoutSeconds = CodexHookVocabulary.answeringTimeout
    nonisolated let answering: any RequestAnswering = CodexRequestAnswering()
    nonisolated let agent: AgentKind = .codex
    nonisolated let restoreDefinitionAdvice =
        "Run /hooks in Codex and trust the definition again."
    /// A refusal produces no event whatsoever, so it has to be inferred.
    nonisolated let reportsApprovalDenials = false
    nonisolated let carriesPromptText = true
    nonisolated let carriesFinalAnswerText = true
    nonisolated let messageDeltaEventName: String? = nil
    /// No delta event, so the row's live text is read from the App Server and a
    /// tool call opening is the only sign it has moved. See
    /// ``AgentHookVocabulary/wakesOnToolCallOpened``.
    nonisolated let wakesOnToolCallOpened = true
    /// The product with a nested agent that carries no `agent_id`, so the only
    /// thing that can say whose turn a held prompt is, is this thread's own
    /// rollout.
    nonisolated let settlesHeldTurnsFromRecord = true

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
            // The one definition that changes, and the one a person answers on.
            // `PreToolUse` is deliberately *not* the second: it fires for every
            // tool call, so a window a person can answer inside would be a
            // window every tool call waits in.
            ManagedHookDefinition(
                event: "PermissionRequest",
                matcher: nil,
                timeoutSeconds: Self.answeringTimeout,
                argument: AgentHookHelper.answeringArgument
            ),
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

    /// Codex asks in two shapes, and neither of them is a question with options.
    ///
    /// `request_user_input` is a question and nothing more — no labels, no
    /// `multiSelect` — so it is form 04, answered in a person's own words.
    /// Everything else Codex stops on is a command to grant, and its arguments
    /// are drawn verbatim on the recessed ground.
    nonisolated func request(
        forEvent name: String,
        toolName: String?,
        toolInput: JSONValue?,
        openedBy toolUseID: String
    ) -> AgentRequest? {
        guard let toolInput else { return nil }
        let form: AgentRequest.Form? = switch (name, toolName) {
        case ("PreToolUse", "request_user_input"):
            // The prompt where the tool put one, and its whole arguments where
            // it did not. Failing closed **to the arguments** rather than to
            // nothing: a question in an unexpected shape still leaves a person
            // with the thing they were asked.
            (AgentRequestReading.text("question", in: toolInput)
                ?? AgentRequestReading.text("prompt", in: toolInput))
                .map { .question($0) }
                ?? AgentRequestReading.arguments(of: toolInput).map { .command($0) }
        default:
            AgentRequestReading.arguments(of: toolInput).map { .command($0) }
        }
        return form.map {
            AgentRequest(id: toolUseID, toolName: toolName, form: $0)
        }
    }
}

/// Claude Code's spelling of the same lifecycle.
///
/// Measured against CLI 2.1.233 on 2026-08-16; every claim below is an
/// observation, not a reading of the documentation.
nonisolated struct ClaudeCodeHookVocabulary: AgentHookVocabulary {
    /// Twenty-four hours, and the same day a released notch app registers here.
    ///
    /// Longer than Codex's hour because this product's own number is longer,
    /// and because there is no trust hash on this side: a value that turns out
    /// to be wrong is one settings write away from being right (ADR 0016).
    nonisolated static let answeringTimeout = 24 * 60 * 60
    nonisolated let answeringTimeoutSeconds = ClaudeCodeHookVocabulary.answeringTimeout
    nonisolated let answering: any RequestAnswering = ClaudeCodeRequestAnswering()
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
    /// The prompt is read here as it is on Codex: it is what a turn that has
    /// not printed anything yet has to show.
    nonisolated let carriesPromptText = true
    /// PRD §7: every word of assistant text this product draws comes from
    /// `MessageDisplay`, so its `Stop`'s copy of the last message is not read.
    nonisolated let carriesFinalAnswerText = false
    nonisolated let messageDeltaEventName: String? = Self.messageDisplayEventName
    /// The fold carries its own edge, so a tool call would only wake the panel
    /// a second time for text it has already reported.
    nonisolated let wakesOnToolCallOpened = false
    /// Nothing runs under this product's thread identity without saying so, and
    /// there is no rollout to ask -- so a held prompt is redeemed here by the
    /// first event under its id, as it was on both products before Codex's
    /// reviewer proved that test worthless on that one. See
    /// ``AgentHookVocabulary/settlesHeldTurnsFromRecord``.
    nonisolated let settlesHeldTurnsFromRecord = false

    /// The tool Claude Code uses to put a question to the user.
    static let inputToolName = "AskUserQuestion"
    /// The tool that hands over a document rather than a command.
    ///
    /// Named here rather than matched inline because it is the one tool whose
    /// request is set as prose: `answer-in-notch.md` §4.2 decides the setting by
    /// which payload a request came from and never by how long it is, so the
    /// decision has to be a name and not a length.
    static let planToolName = "ExitPlanMode"

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
            // The one definition that carries an answer back, on this product
            // as on the other — and here it carries a question's answers as
            // well as an approval, because this is the product whose `allow`
            // accepts `updatedInput`.
            ManagedHookDefinition(
                event: "PermissionRequest",
                matcher: nil,
                timeoutSeconds: Self.answeringTimeout,
                argument: AgentHookHelper.answeringArgument
            ),
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
            // own turn -- which `carriesFinalAnswerText` already declines to
            // read for this product, so nothing here has to say so twice.
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

    /// Claude Code asks in three shapes, and one of them it asks twice.
    ///
    /// - `AskUserQuestion` is a **set** of questions, one to four of them, each
    ///   with a header, two to four labelled options and a `multiSelect` flag.
    ///   It reaches this app on `PreToolUse` *and* again on the
    ///   `PermissionRequest` the product raises for it; both are admitted by the
    ///   gate and both read to the same form, so whichever lands second simply
    ///   replaces an equal value.
    /// - `ExitPlanMode` hands over a document — routinely longer than the whole
    ///   panel — and it is read as prose rather than as machine text, because a
    ///   plan is read and not scanned.
    /// - Everything else it stops on is a command to grant.
    ///
    /// An `Elicitation` is named and not drawn (§2.2): its fields are an MCP
    /// server's own, chosen at run time, and a half-rendered form is a wrong
    /// answer submitted confidently.
    nonisolated func request(
        forEvent name: String,
        toolName: String?,
        toolInput: JSONValue?,
        openedBy toolUseID: String
    ) -> AgentRequest? {
        // The one form that needs no arguments to be worth drawing: the row
        // reports that a person is wanted and where to answer, and it would be
        // wrong to make that depend on a payload this app declines to read.
        if name == "Elicitation" {
            return AgentRequest(id: toolUseID, toolName: toolName, form: .unsupported)
        }
        guard let toolInput else { return nil }
        let form: AgentRequest.Form? = switch toolName {
        case Self.inputToolName:
            AgentRequestReading.questions(in: toolInput).map { .questions($0) }
                ?? AgentRequestReading.arguments(of: toolInput).map { .command($0) }
        case Self.planToolName:
            // Fails closed **to the arguments, never to nothing**: a plan that
            // is not where its schema says still leaves a person something to
            // read, where an empty prose body is a request the row cannot
            // honour.
            AgentRequestReading.text("plan", in: toolInput).map { .document($0) }
                ?? AgentRequestReading.arguments(of: toolInput).map { .command($0) }
        default:
            AgentRequestReading.arguments(of: toolInput).map { .command($0) }
        }
        return form.map {
            AgentRequest(id: toolUseID, toolName: toolName, form: $0)
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
    /// Definitions this app rewrote and has not seen fire since.
    ///
    /// **The one thing this app knows about a state it cannot verify.** Codex
    /// hashes a definition's content and silently stops executing a changed one
    /// until the user trusts it again in `/hooks` (ADR 0014); nothing readable
    /// from here says whether they did. The silence probe cannot cover it —
    /// `PermissionRequest` fires only when a person is asked, so its silence
    /// proves nothing and must never be probed — so the evidence that is left
    /// is the app's own memory of having written it.
    ///
    /// Recorded at the install that changed the bytes and removed one event at
    /// a time as those events arrive, which is the only proof of trust that
    /// exists without reading Codex's own private state. This is not a second
    /// copy of anything `hooks.json` carries: that file says what is
    /// *registered*, and this says what has not been seen *running* since it
    /// was registered.
    var eventsAwaitingTrust: [String]?
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
        let desired = AgentHookHelper.script(
            socketPath: paths.hookSocket.path,
            answerWindowSeconds: CodexHookVocabulary().answerWindowSeconds
        )
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
        // Read before the write, because the question is what *changed*.
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
    /// When the event that opened this wait arrived.
    ///
    /// Carried so that evidence which is not a hook event can be held to the
    /// same monotonic rule every hook event is held to. A reading of the
    /// session that *started* before this instant cannot have seen the dialog
    /// this wait is about, so it is not allowed to close it -- see
    /// ``HookEventRepository/endAnsweredApprovalWaits(_:)``. Getting
    /// that backwards would close a dialog the user is still looking at, which
    /// is worse than the delay it exists to fix.
    let openedAt: Date
    /// What the person is being asked to grant, where the event that opened
    /// this wait carried it.
    ///
    /// **A field of the wait rather than a slot beside it**, and that is the
    /// whole of its lifecycle: every `pendingApproval = nil` this reducer
    /// already performs -- the paired close, the inferred resolution, the turn
    /// ending, a session going away, a reading that says the dialog was
    /// answered elsewhere, a subagent stopping, a turn boundary -- clears this
    /// with it, and there is no eighth site to forget. `answer-in-notch.md` §17
    /// proposed a table keyed by `(agent_id, tool_use_id)`, which would need all
    /// seven repeated; a rule that held until one site forgot it is exactly the
    /// shape CR-030 turned out to be.
    ///
    /// `nil` is an ordinary answer: a wait whose payload carried nothing
    /// readable is still a wait, and the row still says a person is wanted.
    let request: AgentRequest?

    /// The same wait, with its request no longer answerable.
    ///
    /// The wait itself stands: §8.1 is that answering does not retire a row.
    nonisolated func withdrawingReplyTicket() -> PendingApproval {
        PendingApproval(
            toolUseID: toolUseID,
            isInferred: isInferred,
            openedAt: openedAt,
            request: request?.answerable(on: nil)
        )
    }
}

/// A question the turn is blocked on, and what it is asking.
///
/// Replaces the bare `tool_use_id` this used to be, so that a question travels
/// with the wait it belongs to exactly as an approval's request does. Every
/// rule that only ever wanted the id still gets one, from the computed
/// `pendingInputToolUseID` beside each slot.
nonisolated struct PendingInput: Sendable, Equatable {
    /// This event's own `tool_use_id` -- unlike an approval's, never borrowed:
    /// both `AskUserQuestion` and `request_user_input` are ordinary tool calls
    /// and carry one.
    let toolUseID: String
    let openedAt: Date
    /// What is being asked, where the event carried it. See
    /// ``PendingApproval/request`` for why it lives here rather than beside.
    let request: AgentRequest?

    /// The same wait, with its request no longer answerable.
    nonisolated func withdrawingReplyTicket() -> PendingInput {
        PendingInput(
            toolUseID: toolUseID,
            openedAt: openedAt,
            request: request?.answerable(on: nil)
        )
    }
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
    /// The open question, if any.
    var pendingInput: PendingInput?
    /// The call the human is being asked to approve, if any.
    var pendingApproval: PendingApproval?
    /// The most recent call this agent opened and has not yet closed.
    var openToolUse: OpenToolUse?

    /// Whether this agent has anything at all left in it.
    var isEmpty: Bool {
        pendingInput == nil && pendingApproval == nil && openToolUse == nil
    }

    /// The open question's id, for the rules that only ever wanted that.
    var pendingInputToolUseID: String? { pendingInput?.toolUseID }
}

struct HookTurnState: Sendable {
    let threadID: String
    let turnID: String
    var sessionStatus: SessionStatus
    /// The open question, if any.
    var pendingInput: PendingInput?
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
    /// The open question's id, for the rules that only ever wanted that.
    var pendingInputToolUseID: String? { pendingInput?.toolUseID }
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
    /// **"When the set changed" is literal, and it used not to be.** A
    /// `SubagentStop` naming an agent this thread never counted leaves the set
    /// alone and must leave this alone with it -- both products stamp
    /// `agent_id` on agents that never announced themselves, and Claude Code's
    /// arrive *minutes after* the turn they name has finished. See
    /// ``HookEventRepository/reduceSubagentBoundary(_:agentID:threadID:at:)``.
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
    /// Whether this turn's own terminal event said the session was pausing
    /// rather than finishing.
    ///
    /// **The gap this closes is between two facts that are both true.** An
    /// asynchronous subagent's `SubagentStop` empties
    /// ``runningSubagentIDs``, and Claude Code re-enters the parent with a new
    /// prompt of its own -- measured 2026-08-23 against CLI 2.1.241 at 130 ms
    /// under `-p` and 50 ms in a pty. In between, a row whose only evidence was
    /// the count said `Completed`, and then said `Running` again, for a state
    /// the thread was never in. Claude Code's `Stop` had already said which of
    /// the two it was: `background_tasks` is documented as the field that
    /// "lets hooks distinguish 'session is done' from 'session is paused
    /// waiting for background work to wake it'".
    ///
    /// A fact about **this turn**, unlike the two above it, so it is not copied
    /// across a turn boundary: it is written by the turn's own `Stop` and it
    /// cannot outlive the turn that wrote it. The next turn's `Stop` answers
    /// for the next turn, with an empty list when the work is finally done.
    ///
    /// Nothing infers it from elapsed time (`AGENTS.md` §6.2). It is set by one
    /// event and cleared by another, and its failure direction is the old
    /// behaviour: a build that stops sending the field puts the flicker back
    /// and invents nothing.
    var pausedForBackgroundWork: Bool = false
    /// A prompt this thread was told about while its own turn was still open.
    ///
    /// **The one thing a nested agent can do that `agent_id` does not label.**
    /// Codex's `--approve-for-me` reviewer is a thread of its own whose rollout
    /// records the *parent* as its `session_id` and its own turn as `turn_id`,
    /// and its `UserPromptSubmit` carries no `agent_id` at all -- so it arrives
    /// looking exactly like the user starting a second turn on this thread.
    /// Adopted as one, it retired the real turn id, and the turn's own `Stop`
    /// was then refused as late: the row said `Running` for ever, its timer
    /// counted from the reviewer's prompt, and the reviewer's instructions
    /// became the row's preview. Reproduced end to end on a Release build,
    /// 2026-08-24 (`docs/tech-design.md` §9.2).
    ///
    /// So a prompt whose turn is not this thread's open one is **held** rather
    /// than adopted, and held is recoverable where retiring is not.
    ///
    /// **What redeems it used to be "any event arrives under that id", and
    /// that was not evidence.** The sentence it was standing in for is *this
    /// turn was this thread's after all*, and a nested agent's own events
    /// arrive under its own turn id exactly as a resumed turn's do -- so the
    /// test was satisfied word for word by the one caller it was written to
    /// exclude. It held only while the reviewer emitted nothing but its prompt
    /// (measured on CLI `0.149.0-alpha.4.3`, which emitted no hook at all).
    /// A reviewer that runs one read-only check, as its own instructions
    /// permit, walked straight back into the defect above and landed on
    /// whichever assessment was held at the time: a row saying `Working...`
    /// for ever whose preview read *"The following is the Codex agent history
    /// added since your last approval assessment"* -- the reviewer's **second
    /// and later** prompts, one guardian thread running a fresh turn per
    /// assessment (up to 8 per parent turn, measured over 1 970 of them).
    ///
    /// Redemption is now the thread's **own record**: a `turn_context` in this
    /// thread's rollout naming that turn ([ADR 0011](../../docs/adr/0011-a-turn-may-end-on-evidence-that-is-not-a-hook-event.md)'s
    /// evidence, asked about a turn's identity rather than its end), applied by
    /// ``HookEventRepository/adoptTurnsOnRecord(_:)``. A nested agent's turn is
    /// written to a rollout of its **own**, so this thread's record never names
    /// it, and no reading is needed to exclude it -- silence does.
    var heldTurnStart: HeldTurnStart?

    /// Every turn id this thread has ever held back.
    ///
    /// **The refusal has to outlive the candidate above.** That slot holds one
    /// turn start, the newest, because that is the only one a redemption could
    /// ever want -- but a reviewer opens a turn per assessment, so by the time
    /// its third prompt is the candidate its first two are no longer named
    /// anywhere, and an event under either of those would have found the thread
    /// with nothing to refuse it. This set is what refuses them, and it holds
    /// ids rather than starts so that remembering one costs a string.
    ///
    /// Carried across every turn boundary, exactly like ``retiredTurnIDs`` and
    /// bounded by the same thing: the thread leaving ``HookEventRepository``.
    /// A turn proven to be another agent's does not become this thread's
    /// because this thread started a new one.
    var heldTurnIDs: Set<String> = []

    /// A turn start waiting for this thread's own record to name it.
    nonisolated struct HeldTurnStart: Sendable, Equatable {
        let turnID: String
        let startedAt: Date
        let promptPreview: String?

        nonisolated init(turnID: String, startedAt: Date, promptPreview: String?) {
            self.turnID = turnID
            self.startedAt = startedAt
            self.promptPreview = promptPreview
        }
    }

    nonisolated var status: SessionStatus {
        sessionStatus
    }

    /// How many of this thread's subagents are sitting on a permission prompt.
    ///
    /// **Capped by the running set on purpose.** Both products stamp `agent_id`
    /// on events from agents that never announced themselves — Claude Code's
    /// own TUI background agents, and the reviewer Codex spawns for
    /// `--approve-for-me`, which is a nested agent with no `SubagentStart` of
    /// its own (both measured 2026-08-23). A slot is therefore never evidence
    /// that this thread has a subagent; only ``runningSubagentIDs`` is. The
    /// cap also means this count can never outlive the count that draws it:
    /// what clears one clears the other, so the stuck-state risk stays the
    /// single one already accepted in `PRD.md` §6.2.
    ///
    /// A count in the reducer, a flag on the surface, since
    /// `dual-agent-design.md` §10. The badge that draws this thread's trailing
    /// mark carries ``runningSubagentIDs``'s count — waiting subagents
    /// included — and says *whether* any of them is stopped by flipping its
    /// ground rather than by drawing a second figure. The reducer has a real
    /// count here and keeps one; only `> 0` is ever drawn from it.
    nonisolated var subagentsAwaitingApprovalCount: Int {
        subagentSlots.filter { agentID, slots in
            runningSubagentIDs.contains(agentID) && slots.pendingApproval != nil
        }.count
    }

    /// Whether a subagent of this thread is sitting on a permission prompt.
    nonisolated var subagentsAwaitingApproval: Bool {
        subagentsAwaitingApprovalCount > 0
    }

    /// The one request this thread's row can open, out of everything it is
    /// waiting on.
    ///
    /// **One row holds one request**, because a row is
    /// `agent:threadID:turnID` and a subagent has no row of its own. So this
    /// picks, and the order it picks in is the order the surface already reads:
    /// the turn's own question first, then the turn's own approval, then a
    /// subagent's -- which is `PRD.md` §6.2's priority with its stated
    /// exception, *input outranks approval where both are this turn's*, and it
    /// has to agree or a row would say `Approval needed` and open to nothing.
    ///
    /// Among several waiting subagents the **oldest** wins. It has been
    /// blocking longest, and it is the only stable choice: newest-first would
    /// swap an open row's contents under a reader's eye, which is exactly what
    /// `answer-in-notch.md` §6.3 exists to prevent. `runningSubagentIDs` gates
    /// it for the same reason ``subagentsAwaitingApprovalCount`` is gated --
    /// an agent that never announced itself is not this thread's.
    ///
    /// A subagent's *question* is deliberately not offered, exactly as its
    /// count is not drawn: whether one reaches a person at all is unmeasured,
    /// and a request this app cannot vouch for is worse than none.
    /// Every connection this turn is holding open, its subagents' included.
    ///
    /// Deliberately *every* one and not only the request a row can open: a
    /// subagent's approval that is not the one the row is drawing is still a
    /// hook process this app is keeping waiting, and closing it because the
    /// surface has nothing to say about it would answer that subagent's
    /// question by silence.
    nonisolated var heldReplyTickets: [HookReplyRegistry.Ticket] {
        var tickets: [HookReplyRegistry.Ticket] = []
        if let ticket = pendingInput?.request?.replyTicket { tickets.append(ticket) }
        if let ticket = pendingApproval?.request?.replyTicket { tickets.append(ticket) }
        for slots in subagentSlots.values {
            if let ticket = slots.pendingInput?.request?.replyTicket {
                tickets.append(ticket)
            }
            if let ticket = slots.pendingApproval?.request?.replyTicket {
                tickets.append(ticket)
            }
        }
        return tickets
    }

    nonisolated var requestAwaitingAnAnswer: AgentRequest? {
        if let request = pendingInput?.request { return request }
        if let request = pendingApproval?.request { return request }
        return subagentSlots
            .filter { agentID, _ in runningSubagentIDs.contains(agentID) }
            .compactMap { _, slots in slots.pendingApproval }
            .min { $0.openedAt < $1.openedAt }?
            .request
    }

    /// The instant this turn's own terminal arrived.
    ///
    /// **What every piece of read evidence is dated against**, on both
    /// products, and the reason it is published under a name of its own rather
    /// than read off `lastEventAt` at four call sites. Reading is something a
    /// person does to a turn's *answer*, and the answer landed here: Claude
    /// Desktop's `lastFocusedAt`, its return to the foreground, a controlling
    /// terminal's access time and Codex Desktop's blue dot are all evidence
    /// only if they came after this.
    ///
    /// Deliberately not ``terminalBoundaryAt``, which a subagent pushes past
    /// the answer nobody has read yet -- see there for what that cost.
    ///
    /// Meaningful only once the turn is terminal, exactly like the stamp below
    /// it; on a running turn it is simply the last thing that happened.
    nonisolated var turnEndedAt: Date { lastEventAt }

    /// The instant a finished row's settling window is measured from.
    ///
    /// The later of the turn's own last event and the last subagent boundary,
    /// which for every row without a subagent is simply `lastEventAt`. The two
    /// stamps stay separate because only this one is allowed to slip forward
    /// on a subagent's account; see ``lastSubagentBoundaryAt``.
    ///
    /// **It says when this *thread* stopped working and nothing else, and it
    /// may not be used to date read evidence.** A subagent's `SubagentStop`
    /// was measured 91 seconds after its parent's `Stop` (2026-08-22), and
    /// from `dff7d66` until this was split out both products compared the
    /// user's read against this instant: Codex against the unread file's
    /// `modificationDate`, Claude Code against `lastFocusedAt`, the return to
    /// the foreground and the terminal's access time. A user who read the
    /// answer while the subagent was still working -- which is the ordinary
    /// case, since that is when the row is on the notch -- had their read
    /// dated before the bar and thrown away, and the row then waited on
    /// evidence from a moment nobody was going to act at. See
    /// ``turnEndedAt``.
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
    /// Whether the stop also cut this Turn's subagents off from it.
    ///
    /// **A Turn's subagent set normally outlives the Turn, and that is the
    /// point of it**: a subagent finishes after its parent's `Stop`, the parent
    /// collects the result, and a row reading the count alone is what stops
    /// `Completed` meaning "nothing is happening here" while it does. A stop is
    /// where that stops being true.
    ///
    /// Measured 2026-08-29, CLI `0.151.0-alpha.7.1`, a Codex turn told to spawn
    /// one subagent and wait for it, interrupted 5 s in:
    ///
    /// ```text
    /// PreToolUse   collaborationspawn_agent          -- closes
    /// PostToolUse  collaborationspawn_agent
    /// PreToolUse   collaborationwait_agent           -- never closes
    /// SubagentStart  agent=01a04f6f-8570
    /// ...  turn/interrupt, turn_aborted
    /// PreToolUse   Bash  agent=01a04f6f-8570         -- the subagent works on
    /// PostToolUse  Bash  agent=01a04f6f-8570
    /// SubagentStop       agent=01a04f6f-8570         -- 27 s after the abort
    /// ```
    ///
    /// The subagent is not killed and does eventually report. What the stop
    /// killed is the `wait_agent` the Turn was going to collect it with, so
    /// whatever that subagent produces can never reach this Turn -- it is
    /// written into the rollout as `SubAgentActivity` against a Turn that is
    /// over, and nothing re-enters. Counting it goes on saying *the thread is
    /// working* for as long as the orphan runs, on a Turn the user ended by
    /// hand, and with no bound on how long that is.
    ///
    /// So this is not "guessing the subagent stopped": it is declining to
    /// report work the stopped Turn can no longer receive as that Turn's. A
    /// `SubagentStop` that does arrive afterwards names an agent the thread no
    /// longer counts, which the reducer already treats as changing nothing.
    ///
    /// **Codex only, and only because only Codex was measured this way.**
    /// Claude Code runs a subagent's own `SubagentStop` on an interrupt (its
    /// query loop logs `SubagentStop on interrupted query failed`), so the
    /// count clears itself there and the evidence says nothing more. It
    /// defaults to the answer that changes nothing.
    let orphansSubagents: Bool

    nonisolated init(
        threadID: String,
        turnID: String,
        endedAt: Date,
        orphansSubagents: Bool = false
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.endedAt = endedAt
        self.orphansSubagents = orphansSubagents
    }
}

/// One Turn a thread's own record says is that thread's.
///
/// The mirror of ``TurnInterruption``, and produced from the same file by the
/// same sweep: that one carries what the product wrote down about a Turn
/// **ending**, this one what it wrote down about a Turn **beginning**. Codex
/// writes a `turn_context` at the head of every Turn naming the Turn it opens,
/// in the rollout of the thread that Turn belongs to — so a Turn running under
/// a thread's identity that this thread's rollout does not name belongs to
/// something else running under that identity, which is the whole question
/// ``HookTurnState/heldTurnStart`` exists to ask.
///
/// It is consumed by ``HookEventRepository/adoptTurnsOnRecord(_:)`` and, like
/// the interruption beside it, it may only speak about the Turn it names.
struct TurnOnRecord: Sendable, Equatable {
    let threadID: String
    let turnID: String

    nonisolated init(threadID: String, turnID: String) {
        self.threadID = threadID
        self.turnID = turnID
    }
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

/// One item of in-flight background work, read for the fact that it is there.
///
/// **It decodes no fields, and that is the whole design.** The schema gives
/// each item an id, a type, a status and a description, and none of them
/// changes the one question this app asks of the list -- the question the
/// field's own documentation is written to answer: is the session done, or
/// paused waiting for background work to wake it. A list of these is a count,
/// and the count is the entire reading. Anything more would be a private
/// schema this app does not need and would then have to keep up with.
nonisolated struct HookBackgroundTask: Sendable, Decodable, Equatable {}

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
    /// Claude Code's turn identity, read from the key it actually spells it
    /// with rather than through ``turnID``'s two-spelling fallback.
    ///
    /// **`MessageDisplay` is why this is a field of its own.** It is the one
    /// event that carries `turn_id` *and* `prompt_id`, and the two hold
    /// **different values** -- so on that event ``turnID`` answers with a
    /// message-level id the reducer has never held, and text keyed by it would
    /// belong to no turn at all. Measured on CLI 2.1.234 and again on 2.1.251
    /// (a `-p` run against a throwaway `--settings` listener): the turn's
    /// `UserPromptSubmit`, its `MessageDisplay` and its `Stop` all carried the
    /// same `prompt_id`, and only the middle one carried a `turn_id` as well.
    /// Every other event of this product carries `prompt_id` only, which is
    /// where ``turnID`` already takes it from; Codex sends none, so this is nil
    /// there and the one rule that reads it treats nil as "belongs to whichever
    /// turn is asking".
    let promptID: String?
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
    /// The session's in-flight background work, as its own terminal event
    /// reports it.
    ///
    /// **Claude Code's answer to the one question a `Stop` cannot otherwise
    /// settle**, and its own schema says so: "In-flight background work
    /// (running/pending + backgrounded) registered in this session. Lets hooks
    /// distinguish 'session is done' from 'session is paused waiting for
    /// background work to wake it'. Empty array when nothing is in flight."
    /// It rides on `Stop` and `SubagentStop`; Codex sends nothing of the kind,
    /// so it is nil there and every rule that reads it is an identity
    /// transform on that product.
    ///
    /// Read on `Stop` and nowhere else. `SubagentStop` carries one too, but it
    /// still lists the agent that is stopping (measured 2026-08-23 against CLI
    /// 2.1.241, twice), so it is not an absolute reading of what is left.
    let backgroundTasks: [HookBackgroundTask]?
    /// What a person is being asked, on the events that ask them.
    ///
    /// **Present only where the event opens a wait**, which is 0.18% of the
    /// tool calls this app sees -- see
    /// ``AgentHookVocabulary/carriesRequest(forEvent:toolName:)`` for the gate
    /// and why it is that one rather than "`PermissionRequest` and
    /// `PreToolUse`". On every other event the key is stepped over unread, so
    /// this is nil there whether or not the product sent it, and in particular
    /// it is nil on `PostToolUse`, whose copy describes a call nobody is being
    /// stopped by.
    ///
    /// Both products spell it `tool_input`, and both put the whole of a tool's
    /// arguments in it: a command, a path, a patch, a plan, or a question's
    /// options. Kept as ``JSONValue`` rather than as bytes because the reducer
    /// has to read named fields out of it -- a plan's `plan`, a question's
    /// `questions` -- and as a value type rather than `[String: Any]` so this
    /// payload stays `Sendable` and `Equatable`.
    let toolInput: JSONValue?

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
        case backgroundTasks = "background_tasks"
        case toolInput = "tool_input"

        /// What kind of value this field is, which is what decides what
        /// happens to it when it arrives too big (see ``HookPayloadDistiller``).
        nonisolated var carried: CarriedValue {
            switch self {
            case .prompt, .lastAssistantMessage, .delta: return .text
            case .backgroundTasks: return .list
            case .toolInput: return .request
            default: return .identity
            }
        }
    }

    /// The four kinds of value this payload carries, and the answers to "it is
    /// too big".
    nonisolated enum CarriedValue: Sendable {
        /// Cut short: a shorter answer is the same answer.
        case text
        /// Left out: half a `session_id` is a different session.
        case identity
        /// Carried whole or left out. A list cannot be cut -- half of one is
        /// not JSON -- and it must not be, because "how many are left" is the
        /// entire reading.
        case list
        /// Carried whole or left out, and **only on the events that ask**.
        ///
        /// Whole or nothing for the same reason ``list`` is: half an object is
        /// not JSON. Stated rather than inherited -- ``text`` happens to behave
        /// this way on a non-string only because ``HookPayloadDistiller`` guards
        /// its shortening on `isString`, which is a fact about the neighbouring
        /// rule and not about this field. And a request cut short is a
        /// different command, which is a worse failure than none.
        ///
        /// The second half is the one no other case has. `PostToolUse` carries
        /// this key too, holding the arguments of a call that has already run,
        /// and carrying it there would put the highest-frequency event's
        /// variable size back on the read queue this type exists to keep cheap
        /// (CR-030). So the gate is a fact about the *event* rather than about
        /// the key, and it lives on the vocabulary:
        /// ``AgentHookVocabulary/carriesRequest(forEvent:toolName:)``.
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
    }

    /// Whether this terminal event says the session is pausing rather than
    /// finishing.
    ///
    /// False when the field is absent, which is both products' honest answer:
    /// Codex never sends it, and a Claude Code build that stopped sending it
    /// would leave the row saying `Completed` a moment early -- the behaviour
    /// this reading improves on, never a state it invents.
    nonisolated var pausesForBackgroundWork: Bool {
        backgroundTasks?.isEmpty == false
    }

    /// The payload the reducer will see, out of the bytes that landed.
    ///
    /// Field selection happens before the decode rather than after it, because
    /// the fields nobody reads are the ones that get big — see
    /// ``HookPayloadDistiller``. `JSONDecoder` is still what reads a field; it
    /// just never sees a tool result.
    ///
    /// `admitsRequest` decides whether this event's ``toolInput`` is a request
    /// a person is being asked about or a call's arguments nobody reads, and it
    /// is **required rather than defaulted**. A default of "carry it" would put
    /// the highest-frequency event's variable size back on the read queue,
    /// which is the whole of CR-030; a default of "drop it" would silently
    /// disable this feature for any caller that forgot. Both are mistakes a
    /// missing argument should not be able to make, so the caller states it.
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

    /// How long a list may be before it is refused whole.
    ///
    /// The one list carried is `background_tasks`, whose items cap their two
    /// free-text fields at 1,000 characters each -- so this is room for several
    /// worst-case items and hundreds of the ones measured, which run about 145
    /// bytes. Past it the field is left out, and the row reaches `Completed` a
    /// moment early rather than the payload being lost.
    nonisolated static let maximumListBytes = 16 * 1_024

    /// How much of one request is carried.
    ///
    /// **A plan is the largest thing either product sends this way**, and it is
    /// read in full rather than previewed: `answer-in-notch.md` §4.4 scrolls the
    /// body and counts what is under the fold, so unlike ``maximumTextBytes`` --
    /// which bounds a line the row cuts to 240 characters anyway -- this bounds
    /// a document nobody wants cut.
    ///
    /// Measured 2026-09-05 over the 30,909 tool calls in this machine's
    /// `~/.claude/projects`: the one `ExitPlanMode` plan weighs 54,411 bytes and
    /// `AskUserQuestion` tops out at 5,002. This is 2.4x that plan and above
    /// 99.997% of every tool input in the corpus -- one `Bash` heredoc at
    /// 136,560 is the sole exception -- so a request this refuses is one no
    /// 240-point viewport was going to draw.
    ///
    /// It is eight times ``maximumTextBytes``, and affordable only because of
    /// the gate: it is paid on the 0.18% of events that open a wait, at the one
    /// moment in this system with no latency to protect, because a person is
    /// about to be asked something.
    nonisolated static let maximumRequestBytes = 128 * 1_024

    /// The fields worth carrying, out of the bytes that landed, or `nil` if
    /// this never was a JSON object.
    nonisolated static func distilled(
        from body: Data,
        admittingRequestWhere admitsRequest: (String, String?) -> Bool
    ) -> Data? {
        body.withUnsafeBytes { raw in
            var scan = PayloadScan(bytes: raw)
            return scan.selectedFields(admittingRequestWhere: admitsRequest)
        }
    }

    /// The keys worth carrying, and what kind of value each one is.
    ///
    /// Read off ``HookPayload/CodingKeys`` rather than listed a second time, so
    /// a field added to the payload cannot become one this drops on the floor.
    private static let selectedKeys: [String: HookPayload.CarriedValue] = Dictionary(
        uniqueKeysWithValues: HookPayload.CodingKeys.allCases.map {
            ($0.rawValue, $0.carried)
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

        mutating func selectedFields(
            admittingRequestWhere admitsRequest: (String, String?) -> Bool
        ) -> Data? {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == Self.openBrace else { return nil }
            index += 1

            var selected = Data([Self.openBrace])
            var isFirstCarried = true
            var isFirstMember = true
            // The request seen so far, held rather than emitted.
            //
            // **Held because the two names that decide it may arrive after it**,
            // and on Claude Code they always do -- its keys arrive
            // alphabetically, so `tool_name` is later than `tool_input` every
            // time. Held as a range into bytes this scan is already holding, so
            // a `PostToolUse` whose request is refused pays *nothing* for the
            // refusal: no copy, no decode, and no second pass over a payload
            // whose tail may be 16 MiB of tool result (CR-030).
            var deferredRequest: ScannedValue?
            var eventName: String?
            var toolName: String?
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
                if let kind = HookPayloadDistiller.selectedKeys[key] {
                    if case .request = kind {
                        // **The first one wins**, because that is what
                        // `JSONDecoder` does with a repeated key -- measured,
                        // not assumed. The streamed keys below get this for
                        // free by emitting every copy and letting the decoder
                        // choose; this one is emitted once, so the choice is
                        // made here and it has to be the same choice. The
                        // distiller decides which bytes the decoder sees and
                        // must never decide what they say.
                        if deferredRequest == nil { deferredRequest = value }
                    } else if let carried = carry(value, kind: kind) {
                        if !isFirstCarried { selected.append(Self.comma) }
                        isFirstCarried = false
                        selected.append(contentsOf: Array("\"\(key)\":".utf8))
                        selected.append(carried)
                        // Read back off the bytes rather than kept in a second
                        // variable up the stack: these two are needed only to
                        // answer the gate, and only if a request turned up.
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

            // After the loop, so a payload that stopped part way through still
            // carries a request that arrived whole -- and a payload that
            // stopped *before* its event name carries none, because nothing is
            // left to vouch for it. That is the fail-closed direction: an
            // unvouched request would be one drawn for an event this app never
            // established was asking anybody anything.
            if let deferredRequest,
               let eventName,
               admitsRequest(eventName, toolName),
               let carried = carry(deferredRequest, kind: .request) {
                if !isFirstCarried { selected.append(Self.comma) }
                selected.append(
                    contentsOf: Array(
                        "\"\(HookPayload.CodingKeys.toolInput.rawValue)\":".utf8
                    )
                )
                selected.append(carried)
            }
            selected.append(Self.closeBrace)
            return selected
        }

        /// A scanned string's contents, unescaped only in the sense that the
        /// quotes are dropped.
        ///
        /// Read the way ``scanKey`` reads a key, and with the same consequence:
        /// a name spelled with an escape simply fails to match, which leaves the
        /// request out. Neither product spells an event or tool name that way.
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

        /// The bytes to emit for one selected value, or `nil` to leave the
        /// field out entirely.
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
            // Only a string can be shortened and still be itself, and only
            // where the field is the row's text rather than an identity or a
            // list.
            guard value.isString, case .text = kind else { return nil }
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
    /// The connection this event arrived on, where it is still open.
    ///
    /// Set only on the one event per product that asks a person something. It
    /// travels with the event rather than being looked up later because the
    /// thing it names is a *descriptor*, and the only moment at which this
    /// payload and that descriptor are both in hand is the read queue.
    var replyTicket: HookReplyRegistry.Ticket?

    nonisolated init(
        payload: HookPayload,
        receivedAt: Date,
        replyTicket: HookReplyRegistry.Ticket? = nil
    ) {
        self.payload = payload
        self.receivedAt = receivedAt
        self.replyTicket = replyTicket
    }
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
        /// The turn this message belongs to, as the payload spelled it.
        ///
        /// Nil where the product does not say, and read as "whichever turn is
        /// asking" — the reading that keeps the row's text on a build that
        /// stopped sending the field, rather than blanking it.
        let turnID: String?
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
    /// Held only to qualify the edge in ``fold(delta:messageID:turnID:sessionID:)``.
    nonisolated(unsafe) private var listedSessionIDs: Set<String> = []

    nonisolated init() {}

    /// The text this turn is currently printing, if any was collected.
    ///
    /// Read, not consumed. A preview stands until the message it came from is
    /// replaced or the session leaves the live list, because a turn spends most
    /// of its life between events and a row that blanked itself after one
    /// refresh would flicker rather than report.
    ///
    /// **Scoped to the turn asking, which is what makes the row's fallback to
    /// the prompt work at all.** The store is keyed by session and a session
    /// outlives its turns, so the text sitting in it when a turn opens is the
    /// *previous* turn's closing words. Answering with those would describe
    /// work that has finished as the work being done -- the same failure the
    /// Codex side's `turnId` argument names (`tech-design.md` §11) -- and would
    /// leave the prompt fallback reachable only on a session's first turn.
    ///
    /// - Parameter turnID: The turn the row is drawing. Text stamped with a
    ///   different one is not this turn's and is not answered with.
    nonisolated func preview(
        forSession sessionID: String,
        inTurn turnID: String
    ) -> String? {
        lock.lock()
        let stored = previewsBySessionID[sessionID]
        lock.unlock()
        guard let stored, stored.turnID == nil || stored.turnID == turnID else {
            return nil
        }
        // The stored form keeps its trailing space so the next delta can join
        // onto it; a row never shows one.
        let trimmed = stored.text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
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
    /// Returns whether the line this session would *draw* moved, and the last
    /// refresh listed it. That is the edge the change stream carries.
    ///
    /// **This used to be the absent-to-present edge only, and a row that is
    /// never blank is exactly the case that got wrong.** Nothing else wakes for
    /// text: ``HookEventRepository/renderedProjection()`` holds no delta, and a
    /// tool call opening and closing leaves every field in it unchanged — so
    /// between two status changes the row kept whichever message happened to be
    /// half-printed at the last refresh, while the session went on to say three
    /// more things. What a user reads as "live progress" was then the step
    /// before the one being worked on, or older.
    ///
    /// **It is still not a 3.4 Hz redraw**, because the head is capped
    /// (``maximumCharacters``): once a message has filled it, every further
    /// delta of that message returns early and wakes nothing at all. Measured
    /// against CLI 2.1.234 — 1561 characters in eleven deltas, mean 142 each —
    /// a message costs two wakes and then goes quiet, however long it runs on.
    /// A short message costs one. The rate is therefore set by how often the
    /// agent starts a new message, which is the rate the row is meant to
    /// follow.
    ///
    /// Whitespace-only growth is not a change: the stored form keeps a trailing
    /// space so the next delta can join onto it (see ``normalized``), and the
    /// row never draws one.
    ///
    /// Without the listed test this is a loop rather than a wake: text from a
    /// session the list does not carry is pruned by the very refresh it asks
    /// for, which makes the next delta a change again — and the row it would
    /// draw is not on screen either way.
    ///
    /// - Parameter turnID: The turn that is speaking, so that
    ///   ``preview(forSession:inTurn:)`` can tell this turn's words from the
    ///   previous one's. A turn change is a change in its own right: the row
    ///   was drawing the prompt and is now drawing text, which is a different
    ///   line even in the one case where the two turns' text matches.
    @discardableResult
    nonisolated func fold(
        delta: String,
        messageID: String?,
        turnID: String?,
        sessionID: String
    ) -> Bool {
        lock.lock()
        let existing = previewsBySessionID[sessionID]
        lock.unlock()

        guard !delta.isEmpty else { return false }
        // A new message replaces the old one rather than extending it: the row
        // shows the message being printed now, not the whole turn concatenated.
        // A new turn replaces it for the same reason and more strongly: its
        // words are not a continuation of anything the last turn said.
        let continuesMessage = existing?.messageID == messageID
            && existing?.turnID == turnID
        let carried = continuesMessage ? (existing?.text ?? "") : ""
        let carriedLength = carried.count
        guard carriedLength < Self.maximumCharacters else { return false }
        let text = Self.normalized(
            appending: delta,
            to: carried,
            carriedLength: carriedLength
        )
        guard !text.isEmpty else { return false }
        // Compared as the row reads them, not as they are stored.
        let drawn = text.trimmingCharacters(in: .whitespaces)
        let wasDrawn = existing?.text.trimmingCharacters(in: .whitespaces)

        lock.lock()
        let isFirstSinceEmpty = previewsBySessionID[sessionID] == nil
        if isFirstSinceEmpty {
            order.append(sessionID)
        }
        previewsBySessionID[sessionID] = SessionPreview(
            turnID: turnID,
            messageID: messageID,
            text: text
        )
        while order.count > Self.maximumRetained {
            previewsBySessionID.removeValue(forKey: order.removeFirst())
        }
        // `isFirstSinceEmpty` is checked as well as the comparison, because a
        // prune between the two locks leaves `existing` describing text this
        // store no longer holds: the row is blank again, and putting text back
        // on it is a change whatever that text says. The turn is checked for a
        // narrower reason: the row draws the prompt until its turn has said
        // something, so the first delta of a turn moves the line it draws even
        // when the characters happen to match what the last turn left here.
        let didChange = isFirstSinceEmpty
            || drawn != wasDrawn
            || existing?.turnID != turnID
        let moved = didChange && listedSessionIDs.contains(sessionID)
        lock.unlock()
        return moved
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
    /// The connections this product's hooks are being kept waiting on.
    ///
    /// Lock-protected rather than actor-isolated, and for the same reason as
    /// the preview store beside it (`AGENTS.md` §6.3): a descriptor is handed
    /// over on the listener's serial read queue, and an actor hop there would
    /// put the reducer's mailbox between a product and its own transport.
    nonisolated private let replies = HookReplyRegistry()

    private var hasObservedEvent: Bool
    private var hasObservedLiveEvent = false
    /// Definitions this app rewrote and has not seen fire since; see
    /// ``HookInstallRecord/eventsAwaitingTrust``.
    private var eventsAwaitingTrust: Set<String>
    private var didRecordEventThisLaunch = false
    // Codex trusts each hook definition by content hash, so rewriting one stops
    // Codex executing it until the user re-trusts -- silently, while the other
    // definitions keep firing. Every PostToolUse is preceded by a PreToolUse for
    // the same call, so closes without opens are direct evidence of that state.
    private var observedPreToolUseCount = 0
    private var observedPostToolUseCount = 0
    /// Whether the batch being reduced opened a tool call on a turn this store
    /// still holds.
    ///
    /// Consumed by ``drainInbox()``; see
    /// ``AgentHookVocabulary/wakesOnToolCallOpened`` for why one product needs
    /// the wake and the other must not have it.
    private var didOpenToolCallInThisBatch = false
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
        let record = HookInstallStateFile.read(at: paths.installState)
        self.hasObservedEvent = record.lastEventAt != nil
        // Seeded here rather than watched, because the state it describes is
        // written by an install and read on the launches after it: an install
        // in this session says so through `lastIntegrationMessage`, and what
        // this covers is the launch a week later where the card reads
        // `Connected` off a `lastEventAt` from before the rewrite.
        self.eventsAwaitingTrust = Set(record.eventsAwaitingTrust ?? [])
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
    @discardableResult
    nonisolated func deliver(
        _ body: Data,
        at receivedAt: Date,
        on descriptor: Int32? = nil
    ) -> AgentHookListener.Disposition {
        guard let payload = HookPayload.distilled(
            from: body,
            admittingRequestWhere: vocabulary.carriesRequest(forEvent:toolName:)
        ),
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
            return .close
        }
        // Our own quota reading is a real session firing real hooks.
        // Compared as paths rather than URLs: a URL built from a payload string
        // is not marked as a directory, and URL equality counts that, so two
        // spellings of the same folder would not match.
        if let ignoredWorkingDirectory, let cwd = payload.workingDirectory,
           URL(fileURLWithPath: cwd).standardizedFileURL.path
            == ignoredWorkingDirectory.standardizedFileURL.path {
            return .close
        }

        // Assistant text stops here. Folding it costs one bounded scan and
        // reaches the reducer's mailbox not at all, which is why a talking turn
        // never reduces anything. It does wake the panel when the line the row
        // draws moves -- that is the whole point of the line -- and the head's
        // cap is what keeps that to about one wake per message rather than one
        // per delta. See ``HookSessionPreviewStore/fold``.
        if let deltaEvent = vocabulary.messageDeltaEventName, eventName == deltaEvent {
            guard let delta = payload.delta, let sessionID = payload.sessionID else {
                return .close
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
                return .close
            }
            if previews.fold(
                delta: delta,
                messageID: payload.messageID,
                // `prompt_id`, never `turn_id`: this is the one event that
                // carries both, and on it they are different values -- see
                // ``HookPayload/promptID``.
                turnID: payload.promptID,
                sessionID: sessionID
            ) {
                changes.signal()
            }
            return .close
        }

        // The one event per product whose connection an answer travels back on.
        // Held here rather than after the reduce, because this is the only
        // moment at which the payload and its descriptor are both in hand — and
        // held *by handing it away*, so this queue, whose serialness is what
        // preserves arrival order, never waits on anybody.
        //
        // A ticket that the reducer then does not attach to a wait is closed by
        // the reconciliation after the drain, so this cannot leak by admitting
        // too much.
        var ticket: HookReplyRegistry.Ticket?
        if let descriptor, eventName == vocabulary.answeringEventName {
            ticket = replies.hold(descriptor, answering: payload.toolInput)
        }
        inbox.append(
            DeliveredHookEvent(
                payload: payload,
                receivedAt: receivedAt,
                replyTicket: ticket
            )
        )
        Task { await self.reduceWhatHasLanded() }
        return ticket == nil ? .close : .held
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
            noteDefinitionFired(event.payload.hookEventName)
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
        releaseConnectionsNoWaitStillNames()
        let didOpenToolCall = didOpenToolCallInThisBatch
        didOpenToolCallInThisBatch = false
        // The projection first, so a batch that both opened a call and changed
        // a status is still one wake rather than two.
        guard !signalIfProjectionChanged() else { return }
        if didOpenToolCall, vocabulary.wakesOnToolCallOpened {
            changes.signal()
        }
    }

    /// Answers one request on the connection it arrived on.
    ///
    /// Returns whether the answer reached the product. `false` is an ordinary
    /// outcome with two ordinary causes, and the row says which is which by
    /// saying neither: the connection is gone — settled in the product, or the
    /// hook process killed with it — or this product will not accept an answer
    /// of this shape at all, which today is a question on Codex
    /// (``RequestAnswering``).
    ///
    /// **Answering does not retire the row** (`answer-in-notch.md` §8.1): a
    /// granted command is a Turn that is now running, and the product's own
    /// next event is what closes the wait. What does change is that the request
    /// stops being answerable — the connection it would have travelled on is
    /// closed either way, so leaving `canBeAnswered` true would offer a second
    /// affirmative the app could not deliver.
    func answer(_ answer: AgentAnswer, on ticket: HookReplyRegistry.Ticket) -> Bool {
        guard let body = vocabulary.answering.hookOutput(
            for: answer,
            updating: replies.input(for: ticket)
        ) else {
            return false
        }
        let delivered = replies.answer(ticket, with: body)
        withdrawTicket(ticket)
        return delivered
    }

    /// Takes one connection's name off whatever wait is still holding it.
    ///
    /// The mirror of the reconciliation below: that one closes a connection no
    /// wait names, and this forgets a connection that is no longer open. Both
    /// exist so that "is this answerable" has exactly one answer — is there a
    /// connection — rather than two that can disagree.
    private func withdrawTicket(_ ticket: HookReplyRegistry.Ticket) {
        for (threadID, var turn) in turnsByThreadID {
            var changed = false
            if turn.pendingApproval?.request?.replyTicket == ticket {
                turn.pendingApproval = turn.pendingApproval?.withdrawingReplyTicket()
                changed = true
            }
            if turn.pendingInput?.request?.replyTicket == ticket {
                turn.pendingInput = turn.pendingInput?.withdrawingReplyTicket()
                changed = true
            }
            for (agentID, var slots) in turn.subagentSlots {
                if slots.pendingApproval?.request?.replyTicket == ticket {
                    slots.pendingApproval = slots.pendingApproval?.withdrawingReplyTicket()
                    turn.subagentSlots[agentID] = slots
                    changed = true
                }
                if slots.pendingInput?.request?.replyTicket == ticket {
                    slots.pendingInput = slots.pendingInput?.withdrawingReplyTicket()
                    turn.subagentSlots[agentID] = slots
                    changed = true
                }
            }
            if changed { turnsByThreadID[threadID] = turn }
        }
    }

    /// Closes every held connection the reducer is no longer holding a wait for.
    ///
    /// **The whole lifecycle of a held descriptor, in one place.** Seven sites
    /// already clear a wait — the paired close, the inferred resolution, the
    /// turn ending, a session going away, a reading that says the dialog was
    /// answered elsewhere, a subagent stopping, a turn boundary — and none of
    /// them knows a connection exists. Reconciling after the drain means none of
    /// them has to: a rule that holds until one site forgets it is exactly the
    /// shape CR-030 turned out to be, and this is the same argument that put the
    /// request inside the wait rather than in a table beside it.
    ///
    /// It also covers the case admitting the connection could not: a payload
    /// held on the read queue and then dropped by the reducer as unplaceable
    /// names no wait at the next drain, so its connection closes and its
    /// product carries on unchanged.
    ///
    /// Cheap by construction, and it has to be, running once per drain: the set
    /// is empty for everyone with nothing waiting, and `retain(only:)` walks
    /// only what is actually held.
    private func releaseConnectionsNoWaitStillNames() {
        var live: Set<HookReplyRegistry.Ticket> = []
        for turn in turnsByThreadID.values {
            for ticket in turn.heldReplyTickets { live.insert(ticket) }
        }
        replies.retain(only: live)
    }

    /// One event is the only proof of trust this app can obtain.
    ///
    /// Noted before the reduce rather than after it, because the question is
    /// whether the *definition* executed and not whether its payload could be
    /// placed: an event this vocabulary drops still proves Codex ran the hook.
    ///
    /// At most one write per definition ever, and none at all on the ordinary
    /// path — the set is empty for everyone whose definitions this app has not
    /// rewritten, so the cost per event is a `Set.isEmpty`.
    private func noteDefinitionFired(_ eventName: String?) {
        guard !eventsAwaitingTrust.isEmpty,
              let eventName = stableIdentifier(eventName),
              eventsAwaitingTrust.remove(eventName) != nil else { return }
        let remaining = eventsAwaitingTrust.sorted()
        HookInstallStateFile.update(at: paths.installState, fileManager: fileManager) {
            $0.eventsAwaitingTrust = remaining.isEmpty ? nil : remaining
        }
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

    nonisolated func preview(
        forSession sessionID: String,
        inTurn turnID: String
    ) -> String? {
        previews.preview(forSession: sessionID, inTurn: turnID)
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
                at: interruption.endedAt,
                orphansSubagents: interruption.orphansSubagents
            )
        }
        signalIfProjectionChanged()
        return snapshot()
    }

    /// Gives a thread the Turn its own record says it is on.
    ///
    /// **The only thing that redeems a held prompt, and the reason it is not an
    /// event.** A prompt naming a Turn this thread was not holding is held back
    /// (``HookTurnState/heldTurnStart``) because it may have come from a nested
    /// agent running under this thread's identity. What settles it has to be
    /// something a nested agent cannot produce, and its own events are not that:
    /// they arrive under its own turn id exactly as a resumed Turn's do. Its
    /// **rollout** is: Codex writes each Turn's `turn_context` into the rollout
    /// of the thread that Turn belongs to, and a reviewer's turns are written
    /// to a rollout of its own. So this thread's record naming the held Turn is
    /// the proof, and this thread's record staying silent is the refusal — no
    /// reading has to say "no", and none can.
    ///
    /// **It may only redeem what is already held.** Like
    /// ``endInterruptedTurns(_:)`` it carries a turn identity and is held to it,
    /// and unlike that one it may put a thread onto a Turn rather than take it
    /// off one — so it is deliberately the narrower of the two: it can promote
    /// the one start this thread already took in and set aside, and it cannot
    /// invent a Turn from a record alone.
    ///
    /// The promoted Turn is `Running` because that is what it is: a prompt
    /// opened it and no terminal has arrived for it. It keeps its own start and
    /// its own text, which is the point — the alternative on the resumed-Turn
    /// path is a row timing the Turn the user interrupted.
    func adoptTurnsOnRecord(_ records: [TurnOnRecord]) -> HookStateSnapshot {
        for record in records {
            guard let current = turnsByThreadID[record.threadID],
                  current.turnID != record.turnID,
                  let held = current.heldTurnStart,
                  held.turnID == record.turnID,
                  !current.retiredTurnIDs.contains(record.turnID),
                  // The same monotonic rule every other route obeys: a start
                  // older than the Turn this thread is holding describes a
                  // moment that Turn has already been seen past.
                  held.startedAt > current.lastEventAt else {
                continue
            }
            var retiredTurnIDs = current.retiredTurnIDs
            retiredTurnIDs.insert(current.turnID)
            var heldTurnIDs = current.heldTurnIDs
            heldTurnIDs.remove(record.turnID)
            turnsByThreadID[record.threadID] = HookTurnState(
                threadID: record.threadID,
                turnID: record.turnID,
                sessionStatus: .running,
                pendingInput: nil,
                pendingApproval: nil,
                openToolUse: nil,
                startedAt: held.startedAt,
                lastEventAt: held.startedAt,
                retiredTurnIDs: retiredTurnIDs,
                promptPreview: held.promptPreview,
                assistantPreview: nil,
                // A subagent outlives the Turn that spawned it, so it survives
                // this boundary as it survives every other one.
                runningSubagentIDs: current.runningSubagentIDs,
                lastSubagentBoundaryAt: current.lastSubagentBoundaryAt,
                subagentSlots: current.subagentSlots,
                heldTurnIDs: heldTurnIDs
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
    /// - Parameter orphansSubagents: Whether the same evidence says this turn's
    ///   subagents were cut off from it. See ``TurnInterruption/orphansSubagents``
    ///   for the measurement; the default is the answer that changes nothing.
    private func endOpenTurn(
        ofThread threadID: String,
        named turnID: String?,
        at moment: Date,
        orphansSubagents: Bool = false
    ) {
        guard var turn = turnsByThreadID[threadID],
              turnID == nil || turn.turnID == turnID,
              turn.sessionStatus != .completed,
              moment > turn.lastEventAt else {
            return
        }
        turn.sessionStatus = turn.sessionStatus.transitioned(on: .completed)
        turn.pendingInput = nil
        turn.pendingApproval = nil
        turn.openToolUse = nil
        if orphansSubagents, !turn.runningSubagentIDs.isEmpty {
            turn.runningSubagentIDs.removeAll()
            // The waits go with them. A dialogue raised by a subagent of a turn
            // the user stopped is not a question anyone is going to answer on
            // this row, and it is the same rule as the turn's own
            // `pendingApproval` two lines up.
            turn.subagentSlots.removeAll()
            // The set moved, so the stamp that dates the set moves with it --
            // the invariant on ``HookTurnState/lastSubagentBoundaryAt``. It
            // lands on the same instant `lastEventAt` is about to, which is
            // what the settling window should measure from: this is the moment
            // the row stopped saying anything was in flight.
            turn.lastSubagentBoundaryAt = moment
        }
        // Counted as the turn's last moment, so an event that really is older
        // than this evidence cannot reopen what it ended -- the same monotonic
        // rule ``mutateExactTurn(threadID:turnID:at:createWith:adoptContinuationWith:turns:mutation:)``
        // applies to everything else.
        turn.lastEventAt = moment
        turnsByThreadID[threadID] = turn
    }

    /// Ends the approval waits a human has been shown to have answered.
    ///
    /// **No hook fires when a person approves, on either host.** Measured
    /// 2026-08-23 against CLI 2.1.241 with *all thirty-one* hook events
    /// registered: between the `PermissionRequest` that opened the dialog and
    /// the call's own `PostToolUse` twenty-six seconds later, the only event of
    /// any kind was an unrelated agent's `SubagentStop`. `PostToolUse` lands
    /// when the *tool finishes* rather than when the dialog closes, so a row is
    /// right for a command that takes 200 ms and wrong for every second of one
    /// that takes longer -- thirteen seconds of `Approval needed` after the
    /// answer, on the first measurement of this.
    ///
    /// So the wait can only be ended by evidence that is not a hook event, and
    /// the two hosts keep that evidence in different places. **This method is
    /// the one rule both of them feed**, because what they produce is the same
    /// sentence -- *no dialog of this thread was in front of the user at this
    /// instant* -- and only the way they prove it differs:
    ///
    /// * A terminal-hosted session says so itself. `claude agents --json`
    ///   reads `waiting` (`waitingFor: "permission prompt"`) for exactly as
    ///   long as a dialog is up -- including one a *subagent* raised after the
    ///   parent turn's `Stop` -- and `busy` otherwise. `busy` **only**, never
    ///   "not `waiting`": `idle` does not prove the absence of a dialog, since
    ///   `Esc` reaches `idle` with one still drawn (CC-019), and reading a
    ///   wait's end out of an absence would close one the user is still looking
    ///   at.
    /// * A desktop-hosted session publishes no status at all -- the terminal
    ///   interface writes that field and Claude Desktop has no terminal
    ///   interface (CC-022, #41) -- but Claude Desktop logs both ends of every
    ///   dialog it raises. See ``ClaudeDesktopPermissionLogReader``.
    ///
    /// **It may only end a wait, exactly like the two methods above it.**
    /// Neither piece of evidence carries a turn id or an `agent_id`, so neither
    /// can open an approval any more than a session status can open a turn. It
    /// applies to whichever waits the thread is holding -- the turn's own and
    /// every subagent's -- because a session with no dialog open has none of
    /// them in front of the user.
    ///
    /// Each wait is held to its own stamp, so evidence older than a dialog can
    /// never close it. The cost of that strictness is one refresh, and both
    /// hosts have an edge that brings it: the session record is rewritten on
    /// the `waiting` to `busy` flip, and the desktop log is watched for as long
    /// as an answer is what the app is waiting for.
    ///
    /// - Parameter observations: Thread id to the instant no dialog was open.
    ///   For the session reading that is when the command **started running**,
    ///   which is the strictest thing it can be held to; for the desktop log it
    ///   is the instant Desktop stamped on the line saying the human answered.
    func endAnsweredApprovalWaits(
        _ observations: [String: Date]
    ) -> HookStateSnapshot {
        for (threadID, observedAt) in observations {
            endApprovalWaits(ofThread: threadID, at: observedAt)
        }
        signalIfProjectionChanged()
        return snapshot()
    }

    /// Clears every approval wait one thread holds that the evidence outdates.
    ///
    /// Deliberately does not move `lastEventAt`. This is not the turn doing
    /// anything -- it is a reading of the session that happens to prove a
    /// dialog is gone -- and that stamp is the reducer's only bound against a
    /// row fending off membership reconciliation. ``endOpenTurn(ofThread:named:at:)``
    /// moves it because it *ends* the turn and a later event must not reopen
    /// what it closed; there is nothing here for a later event to undo, because
    /// a later `PermissionRequest` is a new dialog and should reopen the wait.
    private func endApprovalWaits(ofThread threadID: String, at moment: Date) {
        guard var turn = turnsByThreadID[threadID] else { return }
        var changed = false

        if let pending = turn.pendingApproval, moment > pending.openedAt {
            turn.pendingApproval = nil
            changed = true
            // The same re-derivation `toolCallClosed` performs, and for the
            // same reason: an input wait outranks the approval that was
            // cleared, and a turn already at `completed` absorbs both.
            turn.sessionStatus = turn.sessionStatus.transitioned(
                on: turn.pendingInputToolUseID != nil ? .inputNeeded : .running
            )
        }

        for (agentID, slots) in turn.subagentSlots {
            guard let pending = slots.pendingApproval, moment > pending.openedAt else {
                continue
            }
            var cleared = slots
            cleared.pendingApproval = nil
            changed = true
            if cleared.isEmpty {
                turn.subagentSlots.removeValue(forKey: agentID)
            } else {
                turn.subagentSlots[agentID] = cleared
            }
        }

        guard changed else { return }
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
                event: event,
                at: delivered.receivedAt,
                replyTicket: delivered.replyTicket
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
        let carriesPrompt = vocabulary.carriesPromptText
        let carriesFinalAnswer = vocabulary.carriesFinalAnswerText
        // What this event is asking, once the arm that opens the wait has said
        // which id that wait will carry.
        //
        // Taken as a function of the id rather than as a value, because a
        // borrowed approval's wait is keyed on the **open call's** id and not on
        // this event's -- a `PermissionRequest` carries none of its own on
        // either product. Lazy is the point twice over: the ten signals that
        // ask nobody anything never touch `tool_input` at all.
        //
        // Filed on this event's connection as it is read, so answerability is
        // decided by the one fact that decides it -- whether the descriptor
        // that carried this request is still open.
        let replyTicket = delivered.replyTicket
        let requestAsked: (String) -> AgentRequest? = { [vocabulary] toolUseID in
            vocabulary.request(
                forEvent: eventName,
                toolName: event.toolName,
                toolInput: event.toolInput,
                openedBy: toolUseID
            )?.answerable(on: replyTicket)
        }

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
            // A turn this thread once held back stays held back, whatever this
            // thread has done since -- so the set crosses this boundary the way
            // the subagent facts above it do.
            let heldTurnIDs = turnsByThreadID[threadID]?.heldTurnIDs ?? []
            if let current = turnsByThreadID[threadID] {
                if current.turnID == turnID {
                    guard receivedAt >= current.lastEventAt else { return true }
                    retiredTurnIDs = current.retiredTurnIDs
                } else {
                    guard receivedAt > current.lastEventAt,
                          !current.retiredTurnIDs.contains(turnID),
                          // **And a held turn may not start one either.** A
                          // reviewer's next assessment arriving after this
                          // thread's own turn had finished would otherwise be
                          // adopted outright rather than held, which is the
                          // same takeover reached through the one branch the
                          // hold does not cover.
                          !(vocabulary.settlesHeldTurnsFromRecord
                            && current.heldTurnIDs.contains(turnID)) else {
                        return true
                    }
                    // **A thread has one agent and one open turn.** A second
                    // turn cannot start on it while the first is still working:
                    // Codex Desktop queues a follow-up until the running turn's
                    // terminal, so a prompt that really is this thread's next
                    // turn always lands after `Stop`. One that lands *during* a
                    // turn came from something else running under this thread's
                    // identity -- see ``HookTurnState/heldTurnStart``, which is
                    // where it goes instead of over the turn.
                    //
                    // Deliberately not conditioned on the turn sitting on an
                    // approval, which is the only window today's reviewer can
                    // appear in. What is being defended is the identity rule,
                    // not the one caller known to break it, and a narrower test
                    // would have to be widened again by the next nested agent
                    // Codex adds. The stamp is left alone for the same reason
                    // `reduceSubagentToolEvent` leaves it alone: this is not
                    // this turn's activity, so it must not fend off membership
                    // reconciliation.
                    guard current.sessionStatus == .completed else {
                        var holder = current
                        holder.heldTurnStart = HookTurnState.HeldTurnStart(
                            turnID: turnID,
                            startedAt: receivedAt,
                            promptPreview: carriesPrompt
                                ? HookSessionPreviewStore.normalized(event.prompt)
                                : nil
                        )
                        // The candidate is the newest; the refusal is every one
                        // of them. See ``HookTurnState/heldTurnIDs``.
                        holder.heldTurnIDs.insert(turnID)
                        turnsByThreadID[threadID] = holder
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
                pendingInput: nil,
                pendingApproval: nil,
                openToolUse: nil,
                startedAt: receivedAt,
                lastEventAt: receivedAt,
                retiredTurnIDs: retiredTurnIDs,
                promptPreview: carriesPrompt
                    ? HookSessionPreviewStore.normalized(event.prompt)
                    : nil,
                assistantPreview: nil,
                runningSubagentIDs: runningSubagentIDs,
                lastSubagentBoundaryAt: lastSubagentBoundaryAt,
                subagentSlots: subagentSlots,
                heldTurnIDs: heldTurnIDs
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
                    isInferred: true,
                    openedAt: receivedAt,
                    // A `PermissionRequest` that carried nothing readable must
                    // not blank a request the call that opened this wait
                    // already supplied -- and must not carry one across to a
                    // *different* call, which is why this is keyed on the id.
                    //
                    // Re-filed on *this* event's connection: the request may be
                    // the one the opening call supplied, but the connection an
                    // answer travels back on is the one that just arrived.
                    request: requestAsked(openToolUse.id) ?? (
                        state.pendingApproval?.toolUseID == openToolUse.id
                            ? state.pendingApproval?.request?
                                .answerable(on: replyTicket)
                            : nil
                    )
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
                $0.pendingInput = PendingInput(
                    toolUseID: toolUseID,
                    openedAt: receivedAt,
                    request: requestAsked(toolUseID)
                )
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
                    isInferred: false,
                    openedAt: receivedAt,
                    request: requestAsked(toolUseID)
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
                // Recorded inside the mutation rather than beside it, so it is
                // set only where a turn this store holds was actually
                // annotated: a call announced against a retired turn, or one
                // arriving out of order, changes nothing and is worth no wake.
                didOpenToolCallInThisBatch = true
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
                    $0.pendingInput = nil
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
            let assistantPreview = carriesFinalAnswer
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
                $0.pendingInput = nil
                $0.pendingApproval = nil
                $0.assistantPreview = assistantPreview
                // And whether that terminal was the session finishing or the
                // session pausing, which only its own payload can say. Assigned
                // rather than or-ed: a turn that stops twice is answered by its
                // latest stop, and an empty list is that answer.
                $0.pausedForBackgroundWork = event.pausesForBackgroundWork
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
    ///
    /// **And that stamp moves only when the running set moves.** Both products
    /// send these events for agents this thread never had; see below for what
    /// stamping one of those cost.
    private func reduceSubagentBoundary(
        _ signal: HookSignal,
        agentID: String,
        threadID: String,
        at receivedAt: Date
    ) {
        guard var turn = turnsByThreadID[threadID] else { return }
        // Whether the set the stamp below dates actually moved. **An agent that
        // never announced itself is not a subagent of this thread**, which is
        // the same rule ``HookTurnState/subagentsAwaitingApprovalCount`` is
        // capped by -- and it has to hold for the stamp too, or a thread that
        // never had a subagent gets told when its last one stopped.
        let didChangeTheRunningSet: Bool
        switch signal {
        case .subagentStarted:
            didChangeTheRunningSet = turn.runningSubagentIDs.insert(agentID).inserted
        case .subagentStopped:
            didChangeTheRunningSet = turn.runningSubagentIDs.remove(agentID) != nil
            // The slot goes with it whether or not this thread ever counted the
            // agent, and this is the rule that guarantees nothing is ever left
            // waiting. A *refused* call closes with no event of its own on
            // either product -- Codex measured 2026-08-15 (67 seconds of
            // silence), Claude Code measured 2026-08-23, where
            // `PermissionDenied` turns out to fire only for the auto-mode
            // classifier's own refusals and never for a human's. After a
            // refusal this was the only event that arrived at all.
            turn.subagentSlots.removeValue(forKey: agentID)
        default:
            return
        }
        // **A stop that changed nothing dates nothing, and that is the whole
        // fix.** Claude Code runs internal forks *on a turn that has already
        // ended* -- the prompt suggestion, and the session recap (`/config` ->
        // `Session recap`). Each announces itself with no `SubagentStart` at
        // all and finishes with a `SubagentStop` carrying `agent_type: ""`, an
        // `agent_id` nothing ever named, and the **finished** turn's
        // `prompt_id`. Measured 2026-08-26 against CLI `2.1.246` in a pty with
        // every event registered: the suggestion at `Stop` + 3.79 s carrying
        // the suggested next prompt, and the recap at `Stop` + 183.74 s
        // carrying the summary -- the latter with no user input of any kind,
        // because it fires `min(180 s, 0.8 x prompt-cache TTL)` after the turn
        // ends while the terminal is blurred.
        //
        // Stamped unconditionally, each of those moved `terminalBoundaryAt`
        // minutes past the `Stop`, and that instant is exactly what
        // ``TerminalUnreadMembershipGate`` compares for `endedAgain`. So a
        // Completed row the user had read, and which the gate had hidden for
        // good, was un-hidden and re-judged against a boundary later than the
        // gesture that read it -- it came back unread and stayed until the user
        // went back to that terminal. Hiding is final for the Turn it was
        // decided for (CC-024); an agent this thread never had must not be able
        // to present the same Turn as a new one.
        //
        // Monotonic when it does move, like every other stamp here: a boundary
        // that arrived out of order must not wind a settling window backwards.
        if didChangeTheRunningSet {
            turn.lastSubagentBoundaryAt = max(
                turn.lastSubagentBoundaryAt ?? receivedAt,
                receivedAt
            )
        }
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
    ///
    /// - Parameter at: The arrival stamp, kept on the approval it opens and
    ///   nowhere else. It is what lets
    ///   ``endAnsweredApprovalWaits(_:)`` refuse a session reading
    ///   older than the dialog it would be closing; it moves neither of the
    ///   two stamps above.
    private func reduceSubagentToolEvent(
        _ signal: HookSignal,
        agentID: String,
        threadID: String,
        event: HookPayload,
        at receivedAt: Date,
        replyTicket: HookReplyRegistry.Ticket?
    ) {
        guard var turn = turnsByThreadID[threadID] else { return }
        var slots = turn.subagentSlots[agentID] ?? AgentWaitSlots()
        // The event name this signal was read from, for the request reading
        // below. Present by construction -- `reduce` could not have named a
        // signal without it -- and the fallback is the fail-closed one: no name
        // means no request, and the wait still opens.
        let eventName = event.hookEventName ?? ""

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
                slots.pendingInput = PendingInput(
                    toolUseID: toolUseID,
                    openedAt: receivedAt,
                    request: vocabulary.request(
                        forEvent: eventName,
                        toolName: event.toolName,
                        toolInput: event.toolInput,
                        openedBy: toolUseID
                    )?.answerable(on: replyTicket)
                )
            case .approvalWaitOpened:
                slots.pendingApproval = PendingApproval(
                    toolUseID: toolUseID,
                    isInferred: false,
                    openedAt: receivedAt,
                    request: vocabulary.request(
                        forEvent: eventName,
                        toolName: event.toolName,
                        toolInput: event.toolInput,
                        openedBy: toolUseID
                    )?.answerable(on: replyTicket)
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
                isInferred: true,
                openedAt: receivedAt,
                // Same rule as the turn's own borrowed approval: a request that
                // did not arrive must not blank one the call that opened this
                // wait already supplied, and must not travel to another call.
                request: vocabulary.request(
                    forEvent: eventName,
                    toolName: event.toolName,
                    toolInput: event.toolInput,
                    openedBy: openToolUse.id
                )?.answerable(on: replyTicket) ?? (
                    slots.pendingApproval?.toolUseID == openToolUse.id
                        ? slots.pendingApproval?.request?.answerable(on: replyTicket)
                        : nil
                )
            )
        case .toolCallClosed:
            observedPostToolUseCount += 1
            guard let toolUseID = stableIdentifier(event.toolUseID) else { break }
            if slots.pendingInputToolUseID == toolUseID {
                slots.pendingInput = nil
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
                // **A turn this thread held back may never be continued into.**
                // Everything else about an unknown turn id stays as it was: an
                // event naming one is still taken for this thread's own turn,
                // which is what recovers a thread whose `UserPromptSubmit` this
                // app never saw -- it launched mid-turn, or the reducer was
                // emptied under it. What that recovery cannot be allowed to do
                // is finish the job a held prompt started: the prompt is
                // refused at the door and then the same turn's next event walks
                // in through the window. See ``HookTurnState/heldTurnStart``
                // for the reviewer that did exactly this.
                guard let continuationStatus,
                      date > current.lastEventAt,
                      !current.retiredTurnIDs.contains(turnID),
                      !(vocabulary.settlesHeldTurnsFromRecord
                        && current.heldTurnIDs.contains(turnID)) else {
                    return
                }
                var retiredTurnIDs = current.retiredTurnIDs
                retiredTurnIDs.insert(current.turnID)
                // On the product whose held prompts are settled by an event
                // rather than by a record, this is that event, so the start and
                // text it was holding come with it. On the other, a held id
                // never reaches this line at all and this is always nil.
                let redeemed = current.heldTurnStart?.turnID == turnID
                    ? current.heldTurnStart
                    : nil
                var heldTurnIDs = current.heldTurnIDs
                heldTurnIDs.remove(turnID)
                state = HookTurnState(
                    threadID: threadID,
                    turnID: turnID,
                    sessionStatus: continuationStatus,
                    pendingInput: nil,
                    pendingApproval: nil,
                    openToolUse: nil,
                    startedAt: redeemed?.startedAt ?? current.startedAt,
                    lastEventAt: date,
                    retiredTurnIDs: retiredTurnIDs,
                    promptPreview: redeemed?.promptPreview ?? current.promptPreview,
                    assistantPreview: nil,
                    runningSubagentIDs: current.runningSubagentIDs,
                    lastSubagentBoundaryAt: current.lastSubagentBoundaryAt,
                    subagentSlots: current.subagentSlots,
                    heldTurnIDs: heldTurnIDs
                )
            }
        } else {
            guard let sessionStatus else { return }
            state = HookTurnState(
                threadID: threadID,
                turnID: turnID,
                sessionStatus: sessionStatus,
                pendingInput: nil,
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
    /// Turns only. A streamed delta is not here and is not meant to be: it does
    /// not reach this actor at all, and putting it on the reducer's mailbox at
    /// 3.4 events a second would be the expensive half of the old design
    /// (`AGENTS.md` §7, and the measurement in `system-architecture.md` §6).
    /// The text still has to reach the panel, so it carries an edge of its own,
    /// raised where it is folded and bounded by the head's cap; see
    /// ``HookSessionPreviewStore/fold``.
    ///
    /// A tool call opening is likewise absent and likewise woken for, on the
    /// one product whose row text is read from somewhere else entirely; see
    /// ``AgentHookVocabulary/wakesOnToolCallOpened``.
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
                    String(turn.subagentsAwaitingApproval),
                    // A finished turn that is only paused reads as Running in
                    // the collapsed summary, so the surface has to be woken
                    // when the last subagent stops and this is what is left
                    // holding it there.
                    String(turn.pausedForBackgroundWork),
                    // The request the row can open, **identified rather than
                    // spelled out**. A request is fixed by the wait it belongs
                    // to -- one `tool_use_id` never carries two -- so its id and
                    // its form say everything a redraw needs, and a 54 KiB plan
                    // is not string-compared once per arriving event to discover
                    // that it has not changed.
                    //
                    // It is also the only term that catches one case: with two
                    // subagents waiting, answering the first moves the request
                    // the row draws while `subagentsAwaitingApproval` -- a Bool
                    // -- stands still.
                    turn.requestAwaitingAnAnswer
                        .map { "\($0.id)\u{2}\($0.form.name)" } ?? ""
                ].joined(separator: "\u{1}")
            }
            .sorted()
    }

    /// Returns whether it signalled.
    @discardableResult
    private func signalIfProjectionChanged() -> Bool {
        let current = renderedProjection()
        guard current != signalledProjection else { return false }
        signalledProjection = current
        changes.signal()
        return true
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

    /// Set when this app rewrote a definition and has no evidence it runs.
    ///
    /// The second trigger for a sentence that already existed, and the second
    /// is needed because the first cannot reach the definition this design
    /// changes: the silence probe above may never watch `PermissionRequest`,
    /// whose silence means only that nobody has been asked anything.
    ///
    /// **Gated on a live event**, so it says the thing that is actually wrong —
    /// this product's hooks are firing and *this* definition is not. Without
    /// that gate it would nag a user whose Codex simply has not run since the
    /// upgrade, which is not a fault and not something `/hooks` fixes.
    ///
    /// It says *may*, and that is not hedging: the app rewrote the definition
    /// and cannot see whether the user then trusted it. If they have, the
    /// sentence clears at their next approval — the first event that definition
    /// produces — and there is no sooner honest moment, because that event is
    /// the only proof of trust obtainable without reading Codex's private
    /// state.
    private var untrustedDefinitionDiagnostic: String? {
        guard hasObservedLiveEvent, !eventsAwaitingTrust.isEmpty else { return nil }
        let events = eventsAwaitingTrust.sorted().joined(separator: ", ")
        return "\(vocabulary.agent.displayName) may not be running the "
            + "\(events) hook: Notchline changed that definition and cannot "
            + "confirm it was trusted again. "
            + vocabulary.restoreDefinitionAdvice
    }

    /// Everything this store currently has to say about its own health.
    ///
    /// Four independent facts, joined rather than ranked: payloads that could
    /// not be read, events that could not be placed, a definition that has
    /// stopped firing, and a definition this app changed and has not seen fire.
    /// They have different causes and can hold at once, so picking one to
    /// report would hide the others behind it.
    private var reportedDiagnostic: String? {
        let sentences = [
            unreadablePayloadCount > 0
                ? "Ignored \(Self.payloadCount(unreadablePayloadCount)) that could not be read."
                : nil,
            unplaceableEventCount > 0
                ? "Ignored \(Self.payloadCount(unplaceableEventCount)) with no stable identity, or of an unsupported kind."
                : nil,
            undeliveredPreToolUseDiagnostic,
            untrustedDefinitionDiagnostic
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
