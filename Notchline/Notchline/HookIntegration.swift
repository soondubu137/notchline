import Foundation

/// How complete this app's registration is, read from the product's own hooks
/// file and from nothing else.
///
/// One of the two facts behind the settings card. It answers "are our
/// definitions in their file, in the shape this build writes them", which is
/// the only question a file read can answer. Whether Codex actually *runs* them
/// is the other fact, and it has a different source — see ``IntegrationSetupStatus``.
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
enum IntegrationSetupStatus: Equatable, Sendable {
    case notRequired
    case notInstalled
    case repairRequired
    case reviewRequired
    case active

    /// The four cards, from the two facts that produce them.
    nonisolated static func card(
        registration: HookRegistration,
        hasObservedEvent: Bool
    ) -> IntegrationSetupStatus {
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
        case (.notRequired, .notRequired),
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
        case .notRequired:
            "No setup required"
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
        case .notRequired, .notInstalled, .repairRequired:
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

    /// The registration file's root object, or nil when there is no file, an
    /// empty one, or one that is not JSON with an object at its root. Callers
    /// treat nil as "nothing of ours registered", never as an error.
    nonisolated func readConfigurationRoot(fileManager: FileManager) -> [String: Any]? {
        guard let data = try? Data(contentsOf: hooksConfiguration),
              !data.isEmpty,
              let decoded = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return decoded as? [String: Any]
    }

    /// The Codex paths, which is what the no-argument spelling has always
    /// meant.
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
    /// - Parameter announcesEvent: whether the registration hands the helper
    ///   the event's name as `$1`, because the product's payload does not
    ///   carry one (``HookRegistrationDialect/eventNameArrivesAsArgument``).
    ///   The name then goes ahead of the payload on a line of its own, and the
    ///   product's ``HookPayloadTranslating`` reads it back off the front.
    ///   Antigravity CLI is the product this exists for: its five hook payloads
    ///   share one set of fields and none of them is the event (measured
    ///   2026-09-11, 1.2.2). The two products whose payloads name their event
    ///   keep the script they had, byte for byte.
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

    /// The helper named through `/bin/sh` with its path quoted, for a product
    /// that parses `command` with a shell and has no `args` key.
    ///
    /// Codex has always been registered this way (``CodexHookRegistrar``);
    /// Antigravity CLI's schema is the same shape. The path is the one string
    /// such a product never sees rewritten, so the quoting here is part of the
    /// registration's identity and not a detail of it.
    nonisolated static func shellCommandLine(forHelper helper: URL) -> String {
        "/bin/sh \(singleQuoted(helper.path))"
    }

    /// Wraps a path for `sh`, including one with a quote in it.
    ///
    /// A home directory is a user-chosen string and this one is pasted into a
    /// script, so the escape is not decoration: `O'Brien` would otherwise end
    /// the quoting and leave the rest of the path as shell words.
    /// What ``prepare(at:answerWindowSeconds:fileManager:)`` found or did.
    nonisolated enum Preparation: Sendable, Equatable {
        /// The helper on disk is byte-for-byte this build's and executable.
        case current
        /// It was not, and has just been written.
        case written
        /// It could not be written.
        case failed
    }

    /// Puts this build's helper at the product's path, if it is not already
    /// there, and says which.
    ///
    /// Compared before written, because a write that changes nothing still
    /// costs a file event and, on the Codex side, would be a rewrite of a
    /// script whose definition is hashed. The directory is created `0700`
    /// alongside, since the socket that will sit beside the helper is this
    /// user's alone.
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
/// How one product's registration file is arranged, and how its helper learns
/// which event fired.
///
/// Three facts the two shipping products happened to share and a third did
/// not, so they were never written down until Antigravity CLI arrived with
/// the opposite answer to each (measured 2026-09-11, 1.2.2): its root is a set
/// of named hooks rather than one `hooks` object, its handler schema has no
/// `args` key, and its payloads carry no event name at all.
nonisolated struct HookRegistrationDialect: Sendable, Equatable {
    /// The key at the file's root the events sit under. See
    /// ``ManagedHooksConfiguration/containerKey``.
    let containerKey: String
    /// Whether a handler is one shell command line (`/bin/sh '…/hook.sh'`,
    /// as Codex has always been registered) rather than an executable with an
    /// `args` key (Claude Code's exec form, one process instead of two).
    let handlersAreShellCommandLines: Bool
    /// Whether each definition hands the helper its event's name as `$1`,
    /// because the payload does not carry one. The helper then writes the
    /// name ahead of the payload (``AgentHookHelper/script(socketPath:answerWindowSeconds:announcesEvent:)``)
    /// and the product's ``HookPayloadTranslating`` reads it back off the
    /// front.
    let eventNameArrivesAsArgument: Bool

    /// `hooks` at the root, the exec form, and a payload that names its event.
    nonisolated static let standard = HookRegistrationDialect(
        containerKey: "hooks",
        handlersAreShellCommandLines: false,
        eventNameArrivesAsArgument: false
    )
}

/// Turns one product's payload, as its helper delivered it, into the payload
/// the reducer reads (``HookPayload``).
///
/// The reducer's field names are the two shipping products' — `session_id`,
/// `turn_id`, `cwd` — and it keys everything on the first two. A product that
/// spells them otherwise, or does not send one of them, gets one of these in
/// front of the reducer rather than a second decoder inside it: the reducer
/// keeps every rule it has, and what a product means by "a Turn" stays in the
/// product's own folder. The one stateful thing a translator may do is propose
/// a **local** Turn identity at an unambiguous submission boundary, which is
/// the allowance `multi-product-provider-architecture/README.md` §6.1 makes
/// and the only one.
nonisolated protocol HookPayloadTranslating: Sendable {
    /// The canonical payload for `body`, or nil for bytes that are not this
    /// product's business — dropped without a report, because a product that
    /// shares its hooks file with a sibling product sees the sibling's events.
    func canonicalPayload(from body: Data, receivedAt: Date) -> Data?
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
    /// How this product's handlers were spelled by earlier builds of this app,
    /// so that an install can recognise and strip them and a removal can prove
    /// none survived. Substrings of the command, matched by
    /// ``ManagedHooksConfiguration``.
    nonisolated var legacyCommandMarkers: [String] { get }
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
    /// How an answer typed on the notch is encoded for this product, or nil for
    /// a product whose requests cannot be answered from here (without L6 answering coverage in
    /// `docs/product-support.md` §2): the reducer then holds no connection for its
    /// requests and the row offers no affirmative.
    nonisolated var answering: (any RequestAnswering)? { get }
    /// What an answer on the connection this event holds open may do
    /// (``AnswerOperations``), asked only of ``answeringEventName``. The
    /// capability half of ``answering``: that one spells an answer, this one
    /// says which answers the product will act on for this call, so a form
    /// the channel cannot answer is read here rather than offered and refused.
    nonisolated func answerOperations(forEvent name: String, toolName: String?) -> AnswerOperations
    /// How this product's file arranges a registration, and how its helper
    /// is told what fired. ``HookRegistrationDialect/standard`` for a product
    /// whose file is `hooks` at the root and whose payload names its event.
    nonisolated var registrationDialect: HookRegistrationDialect { get }
    /// What turns this product's payload into the one the reducer reads, for
    /// a product that spells its fields differently; nil for one that spells
    /// them as the reducer does. Runs on the transport's read queue, before
    /// anything else sees the bytes.
    nonisolated var payloadTranslator: (any HookPayloadTranslating)? { get }
    /// `nil` means "not recognised": drop it and say so.
    nonisolated func signal(forEvent name: String, toolName: String?) -> HookSignal?

    /// The request this event puts to a person, out of the arguments it carried.
    ///
    /// Read at the Hooks boundary before typed evidence is submitted: the
    /// boundary holds the event name, tool name and vocabulary together.
    /// Borrowed correlation identity is attached by the reducer afterwards. Not in the view, which stays passive; not on
    /// ``HookPayload``, which would put both products' tool names into a
    /// product-free type; and not in the two row builders, where the mapping
    /// would be written twice and could drift once.
    ///
    /// `nil` where nothing readable arrived, which is an ordinary answer and
    /// never an empty request: a wait with nothing to show still opens, and the
    /// row still says a person is wanted (`AGENTS.md` §6, failures fail closed).
    ///
    /// - Parameter permissionSuggestions: the persistent rules this product
    ///   offered to write if the request were granted, where it offers any.
    ///   Read here for the same reason the form is -- it is one product's
    ///   schema, and the surface receives a value rather than a payload -- and
    ///   drawn nowhere yet (`answer-in-notch.md` §6.5).
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
    /// A product that answers nothing declares nothing.
    nonisolated func answerOperations(forEvent name: String, toolName: String?) -> AnswerOperations {
        .readingOnly
    }

    /// The event whose connection an answer travels back on, if any.
    ///
    /// Read off the registration rather than named a second time: a definition
    /// that hands the helper ``AgentHookHelper/answeringArgument`` is exactly a
    /// definition whose connection is being held open, so the transport and the
    /// registration cannot disagree about which one that is. The argument is
    /// compared, not merely present: a product whose every definition names
    /// its event as the argument holds no connection open on any of them.
    nonisolated var answeringEventName: String? {
        managedDefinitions.first { $0.argument == AgentHookHelper.answeringArgument }?.event
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
    ///
    /// ``HookSignal/questionAskedWithoutWaiting`` is the one member that is not
    /// a wait, and it is admitted for the same reason the others are: a person
    /// has been asked something and the body is the only place it is written
    /// down. It costs nothing measurable — Codex's async question is rarer than
    /// the approvals above, and the 128 KiB bound applies to it unchanged.
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
    /// One hour, and the same hour a released notch app registers here.
    ///
    /// Declared as a `static` as well as satisfying the protocol so that
    /// ``managedDefinitions`` — which is where the number has to appear — can
    /// name it without an instance.
    nonisolated static let answeringTimeout = 60 * 60
    nonisolated let answeringTimeoutSeconds = CodexHookVocabulary.answeringTimeout
    nonisolated let answering: (any RequestAnswering)? = CodexRequestAnswering()
    /// A decision, and only a decision: `updatedInput` is reserved on this
    /// product and fails the hook closed, so a question drawn over this
    /// connection is read here and answered in Codex, whatever the form.
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
            // The blocking question, and the only one of the two that is a
            // wait. Measured 2026-09-07 against CLI `0.153.4` in Plan mode: it
            // carries its own `call_…` id and its `PostToolUse` lands when the
            // person answers, carrying their answers.
            .inputWaitOpened
        case ("PreToolUse", "request_user_input_async"):
            // **Not a wait, and not an ordinary call either.** Codex ships two
            // question handlers and which one a Turn gets is decided by the
            // model, not by a setting: measured 2026-09-07 on CLI `0.153.4`,
            // `gpt-6-astra` — this machine's default — registers only this one
            // in Default mode, and `gpt-5.6-sol` registers the blocking one.
            // So both are live for the same user on the same day.
            //
            // It asks a person and does not stop. Its `PostToolUse` arrived
            // **51 ms** after the open carrying `{"accepted":true}` whatever
            // the person does, and the Turn went on to run another tool and
            // reach its own `Stop`; any answer arrives later as a new user
            // message, which is a new Turn. So `.inputWaitOpened` is still
            // wrong: it would put *Input needed* on the row for 51 ms and take
            // it away again, and nothing on this channel could ever retire it
            // honestly — a Skip, a snooze and Desktop's own auto-resolution all
            // arrive as silence.
            //
            // **`.toolCallOpened` was wrong too, and this case used to say it
            // was right (corrected 2026-09-08).** It rested on "the person is
            // owed nothing more, because the Turn's `Stop` carries the question
            // in `last_assistant_message`" — true only when the model stops on
            // the question, and the CLI binary's own system prompt tells it to
            // "continue useful work that does not depend on the answer while
            // waiting". Reported from a user's machine that same day: the model
            // asked, went on working, and the row showed the sentence after the
            // question with the question nowhere. So the question's own words
            // are kept, and nothing else is claimed.
            //
            // A third variant would fall to the default below and land on
            // `.toolCallOpened`, which is still the safe direction: the default
            // never claims a wait, and only claiming one can misreport.
            .questionAskedWithoutWaiting
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

    /// Codex asks in two shapes, and one of them **is** a question with options.
    ///
    /// **This used to say neither of them was, and that was wrong.** Measured
    /// 2026-09-07 against CLI `0.153.4`, a real `PreToolUse(request_user_input)`
    /// carries `{"questions":[{"header","id","question","options":[{"label",
    /// "description"}]}]}` — field for field the shape
    /// ``AgentRequestReading/questions(in:)`` already reads for Claude Code's
    /// `AskUserQuestion`. The reading below looked for a **top-level**
    /// `question` or `prompt`, which that payload does not have, so every real
    /// question fell through to the arguments and was drawn as a *command* on
    /// the recessed ground: machine text, marked as a string a machine will
    /// execute, for a sentence a person was being asked. So the question set is
    /// read first now, and it is form 03 where the tool attached options and
    /// form 04 where it did not — Codex's own schema makes options optional and
    /// says the client adds the free-text answer itself.
    ///
    /// The text readings are kept **after** it rather than deleted: they cost a
    /// dictionary lookup on a payload that already failed the first reading,
    /// and they are what a question in some third shape would still land on.
    /// Everything else Codex stops on is a command to grant, and its arguments
    /// are drawn verbatim on the recessed ground.
    /// - Parameter permissionSuggestions: never anything on this product, which
    ///   documents `updatedPermissions` *reserved* and fails the hook closed on
    ///   it. There is nothing for it to suggest, so the argument is taken and
    ///   not read rather than absent from the protocol.
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
            // The question set the tool actually sends, then the prompt where
            // some other shape put one, then its whole arguments. Failing
            // closed **to the arguments** rather than to nothing: a question in
            // an unexpected shape still leaves a person with the thing they
            // were asked.
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
    nonisolated let answering: (any RequestAnswering)? = ClaudeCodeRequestAnswering()
    /// A decision on every `PermissionRequest` but the one `AskUserQuestion`
    /// raises for its own call, which takes the question's answers through
    /// `updatedInput` and nothing else: its dialogue offers no refusal, and a
    /// `deny` there would block the tool rather than answer the person.
    nonisolated func answerOperations(forEvent name: String, toolName: String?) -> AnswerOperations {
        guard name == answeringEventName else { return .readingOnly }
        return toolName == Self.inputToolName ? .questionAnswers : .decision
    }
    nonisolated let agent: AgentKind = .claudeCode
    /// The path the pre-ADR-0013 `http` handlers posted to. Still recognised so
    /// an install strips the dead handler and a removal can prove it gone.
    nonisolated static let legacyHookPath = "/codex-in-notch/hook"
    nonisolated let legacyCommandMarkers = [ClaudeCodeHookVocabulary.legacyHookPath]
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
    /// in different slots (``ProducerWaits``), so neither can reach the
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
        permissionSuggestions: JSONValue?,
        openedBy toolUseID: String
    ) -> AgentRequest? {
        // The one form that needs no arguments to be worth drawing: the row
        // reports that a person is wanted and where to answer, and it would be
        // wrong to make that depend on a payload this app declines to read.
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
actor CodexHookRegistrar: HookRegistrationSetup {
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
        didCompareHelperThisLaunch = true
        return AgentHookHelper.prepare(
            at: paths,
            answerWindowSeconds: CodexHookVocabulary().answerWindowSeconds,
            fileManager: fileManager
        ) != .failed
    }

    /// Whether this run has already compared the installed helper's bytes.
    private var didCompareHelperThisLaunch = false

    /// Binds the socket on every refresh, and writes the helper on the two
    /// occasions it can be wrong.
    ///
    /// Comparing the helper's bytes used to sit on the refresh path as
    /// `upgradeManagedHookIfNeeded()`, reading a file to answer a question
    /// that can only change when the app itself is upgraded. So the comparison
    /// happens once per launch, and again only if a `stat` says the file has
    /// gone -- which a user emptying the support folder can cause, and which is
    /// loud when it happens: `/bin/sh` on a missing path writes to stderr, and
    /// Codex renders that as a hook error in the user's session (ADR 0013).
    ///
    /// **The socket is bound whatever the write says.** A helper already on
    /// disk from an earlier launch still delivers, and a Codex that was running
    /// before this app has its trusted definitions loaded and firing; refusing
    /// to listen because a rewrite failed would drop events a working helper
    /// is sending.
    func prepareHelperForTransport() -> Bool {
        if !didCompareHelperThisLaunch || !isHelperInstalled {
            prepareHelper()
        }
        return true
    }

    /// The settings card's status: the registration, projected against whether
    /// any of its definitions has been seen to fire -- the only evidence that
    /// Codex's trust step was completed.
    func status(observedBy repository: HookEventRepository) async -> IntegrationSetupStatus {
        IntegrationSetupStatus.card(
            registration: registration(),
            hasObservedEvent: await repository.observedState().hasObservedEvent
        )
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
        AgentHookHelper.shellCommandLine(forHelper: helper)
    }

    /// The strict editor for this build's definitions.
    private var managedConfiguration: ManagedHooksConfiguration {
        .command(
            Self.command(forHelper: paths.hookHelper),
            legacyCommands: CodexHookVocabulary().legacyCommandMarkers,
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
    /// Whether the product named a file it is writing this thread down to.
    ///
    /// **Three answers arrive, and this is two of them plus a silence.** A
    /// path is the ordinary answer; an explicit `null` is the product saying
    /// there is no such file; a build that does not send the key says nothing
    /// at all. Only the middle one is worth anything here, so the path itself
    /// is dropped -- nothing in this app reads it, and the rollout a Codex
    /// thread is written to already arrives on the Thread the App Server hands
    /// over -- and `nil` is the silence.
    ///
    /// **What `null` is evidence of.** Codex requires this field on every one
    /// of its twelve hook events and allows it to be null (read out of CLI
    /// `0.153.4`'s embedded JSON schemas, 2026-09-09), and its Thread schema
    /// documents `ephemeral` as "should not be materialized on disk". A thread
    /// Codex is not writing down is one it will not hand over either, so this
    /// is the answer `thread/read` gives, arriving on the thread's first event
    /// rather than a round trip later. See
    /// ``HookTurnState/threadHasNoTranscript``.
    ///
    /// Claude Code's schema requires a path and permits no null, so this is
    /// `true` on every event of that product.
    let namesATranscript: Bool?
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

    /// The persistent rules the product offered to write alongside a grant.
    ///
    /// Claude Code's `PermissionRequest` schema names it
    /// `permission_suggestions: PermissionUpdate[]` (read from 2.1.263's own
    /// zod definitions on 2026-09-06), and it is the *same type* the product
    /// accepts back on an `allow` as `updatedPermissions` -- so what arrives
    /// here is both what its own dialogue's second answer would write and what
    /// this app would have to send to write it.
    ///
    /// **Absent means do not offer it, and no second field says so.** An ask
    /// carries either `suggestions` or `suppressAlwaysAllowRule`, never both,
    /// so the product withholds the suggestion exactly when a host must
    /// withhold the row. Nothing has to be inferred from a flag the hook
    /// payload does not carry -- and it does not: `suppress_always_allow_rule`
    /// and `default_to_no` are on the SDK's `can_use_tool` request only.
    ///
    /// Codex never sends this. Its `permission-request.command.output`
    /// documents `updatedPermissions` *reserved* and fails the hook closed on
    /// it, so there is nothing for it to suggest.
    ///
    /// Carried, and **not yet drawn or written**: `answer-in-notch.md` §6.5.
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

        /// What kind of value this field is, which is what decides what
        /// happens to it when it arrives too big (see ``HookPayloadDistiller``).
        nonisolated var carried: CarriedValue {
            switch self {
            case .prompt, .lastAssistantMessage, .delta: return .text
            case .backgroundTasks: return .list
            case .toolInput, .permissionSuggestions: return .request
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
        /// `tool_input` too, holding the arguments of a call that has already
        /// run, and carrying it there would put the highest-frequency event's
        /// variable size back on the read queue this type exists to keep cheap
        /// (CR-030). So the gate is a fact about the *event* rather than about
        /// the key, and it lives on the vocabulary:
        /// ``AgentHookVocabulary/carriesRequest(forEvent:toolName:)``.
        ///
        /// **Two keys share it**, and `permission_suggestions` is inside the
        /// gate rather than beside it: it arrives only on a `PermissionRequest`,
        /// which the gate already admits, so admitting it under the same rule
        /// costs a subset of what is already paid and cannot widen what any
        /// other event carries.
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
        // Asked in two questions because `decodeIfPresent` answers both with
        // nil, and the whole of this field is telling them apart: a key that
        // never arrived is a build that does not send it, and a key that
        // arrived null is the product saying there is no such file.
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
    /// and `transcript_path` are paths. Anything past this is none of those.
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

    /// The gated keys, in the one order they are ever emitted in.
    ///
    /// Read off ``HookPayload/CodingKeys`` for the same reason
    /// ``selectedKeys`` is: a `.request` field added to the payload cannot
    /// become one this silently stops carrying.
    fileprivate static let deferredKeyOrder: [String] = HookPayload.CodingKeys.allCases
        .filter { if case .request = $0.carried { true } else { false } }
        .map(\.rawValue)

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
            // The request's keys seen so far, held rather than emitted.
            //
            // **Held because the two names that decide them may arrive after
            // them**, and on Claude Code they always do -- its keys arrive
            // alphabetically, so `tool_name` is later than both `tool_input`
            // and `permission_suggestions` every time. Held as ranges into
            // bytes this scan is already holding, so a `PostToolUse` whose
            // request is refused pays *nothing* for the refusal: no copy, no
            // decode, and no second pass over a payload whose tail may be
            // 16 MiB of tool result (CR-030).
            //
            // **Keyed, because there is more than one of them.** Held in a
            // single slot and re-emitted under a hard-coded name -- which is
            // what this was while `tool_input` was the only `.request` key --
            // `permission_suggestions` would either be dropped by the
            // first-wins rule below or emitted under `tool_input`'s name, and
            // the second is a request drawn out of a rule list.
            var deferredRequests: [String: ScannedValue] = [:]
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
                        // choose; these are emitted once, so the choice is
                        // made here and it has to be the same choice. The
                        // distiller decides which bytes the decoder sees and
                        // must never decide what they say.
                        if deferredRequests[key] == nil { deferredRequests[key] = value }
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
            if let eventName, admitsRequest(eventName, toolName) {
                // Emitted in ``HookPayload/CodingKeys`` order rather than the
                // dictionary's, for the same reason
                // ``AgentRequestReading/arguments(of:)`` sorts: a `Dictionary`
                // iterates differently between instances holding equal values,
                // so an order taken from one would make the same payload
                // distil to different bytes on a later read.
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

// Compatibility names for the existing product adapters and regression fixtures.
// These are the shared types, not a second Hooks state machine.
typealias HookSignal = MonitoringSignal
typealias HookTurnState = MonitoredTurnState
typealias HookStateSnapshot = MonitoringStateSnapshot
typealias HookSessionPreviewStore = TurnPreviewStore
typealias HookChangeBroadcast = MonitoringChangeBroadcast
typealias HookEventRepository = MonitoringRepository
