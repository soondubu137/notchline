import Foundation

/// One hook definition this app manages.
///
/// **The timeout and the argument are per definition, not per configuration**,
/// and that is the whole shape of the write path in the registration. One event
/// on each product opens a wait for a person and carries their answer back, so
/// that one definition registers a window a person can answer inside and passes
/// the helper the literal that selects the long wait. Every other definition
/// keeps the bytes it has always had — which on Codex is not tidiness but the
/// difference between one re-trust and seven (ADR 0014).
nonisolated struct ManagedHookDefinition: Sendable, Equatable {
    /// The default a lifecycle definition registers, in seconds.
    ///
    /// Three, and the helper's own `-w 1` is inside it: three bounds, innermost
    /// first, so the one that fires is always the one closest to the problem.
    static let lifecycleTimeoutSeconds = 3

    /// How a product's file arranges the handlers registered for one event.
    ///
    /// Both shipping products use one arrangement for every event. Antigravity
    /// CLI uses two, and gets the difference wrong loudly: measured 2026-09-11
    /// on 1.2.2, a *group* written under one of its list-shaped events fails
    /// the parse of the whole named hook (`command hook must specify
    /// 'command'`) and none of that hook's handlers run for any event. So the
    /// shape is a fact about the definition, declared beside its event name,
    /// never inferred from what is already in the file.
    nonisolated enum Shape: Sendable, Equatable {
        /// `[{"matcher": …, "hooks": [handler, …]}, …]` — Codex and Claude
        /// Code for every event, and Antigravity CLI for its tool events.
        case groupedByMatcher
        /// `[handler, …]`, the handlers themselves with nothing around them —
        /// Antigravity CLI's `PreInvocation`, `PostInvocation` and `Stop`.
        /// There is no group to carry a matcher, so `matcher` is nil here.
        case handlerList
    }

    let event: String
    let matcher: String?
    let shape: Shape
    /// How long this product may wait for the hook before killing it.
    ///
    /// The helper's own window has to be *inside* this: a helper that gives up
    /// on its own exits 0 and says nothing, and one the product kills is a hook
    /// error printed in the user's session — the noise this transport exists to
    /// remove (ADR 0013).
    let timeoutSeconds: Int
    /// The literal `$1` handed to the helper, where this definition wants one.
    ///
    /// ``AgentHookHelper/answeringArgument`` on the event that opens a wait,
    /// and `nil` everywhere else. Selecting the wait from the registration
    /// rather than from the payload is what keeps the shell from having to
    /// parse anything.
    let argument: String?

    nonisolated init(
        event: String,
        matcher: String?,
        shape: Shape = .groupedByMatcher,
        timeoutSeconds: Int = ManagedHookDefinition.lifecycleTimeoutSeconds,
        argument: String? = nil
    ) {
        self.event = event
        self.matcher = matcher
        self.shape = shape
        self.timeoutSeconds = timeoutSeconds
        self.argument = argument
    }
}

/// Why an edit to a user's hooks configuration was refused.
///
/// Every case here means "we stopped before writing". The previous
/// implementation had no such vocabulary: it coerced whatever it did not
/// understand into an empty dictionary and carried on, which is how a valid
/// JSON file whose root was an array got replaced wholesale.
nonisolated enum ManagedHooksConfigurationError: LocalizedError, Equatable {
    case rootIsNotObject
    case hooksIsNotObject
    case eventIsNotGroupArray(event: String)
    case groupHooksAreNotHandlerArray(event: String)
    case unremovableManagedCommand
    case changedWhileEditing
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .rootIsNotObject:
            "The root of the hook configuration file is not a JSON object; the write was stopped rather than overwrite what is there."
        case .hooksIsNotObject:
            "`hooks` in the hook configuration file is not a JSON object; the write was stopped rather than overwrite what is there."
        case let .eventIsNotGroupArray(event):
            "The shape of `\(event)` in the hook configuration is unrecognised; the write was stopped rather than overwrite what is there."
        case let .groupHooksAreNotHandlerArray(event):
            "One of the groups under `\(event)` in the hook configuration has an unrecognised shape; the write was stopped rather than overwrite what is there."
        case .unremovableManagedCommand:
            "The hook configuration holds a command of this app that cannot be removed safely; the helper was kept rather than leave a dangling reference."
        case .changedWhileEditing:
            "Another program changed the hook configuration during this write; the write was abandoned rather than overwrite their edit. Please try again."
        case .verificationFailed:
            "The hook configuration failed verification after being written; please check the settings file for that product."
        }
    }
}

/// Adds and removes exactly this app's hook definitions inside a configuration
/// file that belongs to the user.
///
/// The contract is narrow on purpose: **only the managed definitions may be
/// touched, and anything this type cannot positively identify is left byte for
/// byte alone.** Where it cannot honour that -- because a key it must write
/// already holds a shape it does not understand -- it refuses the whole edit
/// rather than guessing.
///
/// That strictness is not theoretical tidiness. This same shape of merge is
/// what a second agent's configuration would need, and such a file typically
/// carries far more than hooks, so "coerce anything unexpected to empty" is a
/// data-loss bug waiting for a bigger file to happen to.
nonisolated struct ManagedHooksConfiguration: Sendable {
    /// The key at the file's root under which the events sit.
    ///
    /// `hooks` for Codex and Claude Code, whose files hold one such object that
    /// the user's own handlers share with this app's — which is why every edit
    /// below identifies handlers one by one rather than replacing the object.
    /// Antigravity CLI's root is a set of *named* hooks, each an object of
    /// events, so this app's container there is a name of its own and holds
    /// nothing but this app's definitions.
    let containerKey: String
    /// What every handler this build installs runs.
    let command: String
    /// The arguments the helper is launched with, before this definition's own.
    ///
    /// Present selects Claude Code's exec form — with an `args` key the CLI
    /// resolves `command` as an executable and spawns it directly rather than
    /// through a shell. `nil` is Codex, whose schema has no such key and which
    /// parses `command` with a shell, so an argument there goes on the command
    /// line instead.
    let baseArguments: [String]?
    /// The string that identifies this app's handler anywhere in the document.
    ///
    /// Codex's handler is a shell command, so the command line itself is the
    /// identity. An HTTP handler cannot use its URL that way -- the URL carries
    /// a port, and a port that was taken at launch has to be rebound, which
    /// would make every previously installed handler unrecognisable exactly
    /// when it most needs repairing. So the marker is a fixed path inside the
    /// URL, and identity survives the part of it that moves.
    let identityMarker: String
    /// Markers earlier versions of this app installed under.
    ///
    /// A handler is found by a string, so moving where this app keeps its
    /// helper changes what that string is -- and an upgrade would then neither
    /// recognise nor remove what the previous version registered. The old
    /// handler would survive a reinstall, sitting beside the new one and
    /// pointing at a script the upgrade had just deleted: a dangling reference,
    /// firing on every event, which is precisely what this type exists to
    /// prevent.
    let legacyIdentityMarkers: [String]
    let definitions: [ManagedHookDefinition]
    /// Written into a file this app creates, and never into one it did not.
    ///
    /// `nil` for a product whose settings file has a schema of its own.
    /// `~/.codex/hooks.json` holds hooks and nothing else, so a `description`
    /// at its root is a courtesy to whoever opens it; `~/.claude/settings.json`
    /// is validated by Claude Code against a known set of keys, and stamping an
    /// invented one into a file this app just created for the user would be
    /// this app's first act being to put something unrecognised in it.
    let descriptionForNewFiles: String?

    nonisolated init(
        containerKey: String = "hooks",
        command: String,
        baseArguments: [String]? = nil,
        identityMarker: String,
        legacyIdentityMarkers: [String] = [],
        definitions: [ManagedHookDefinition],
        descriptionForNewFiles: String? = "User-level agent lifecycle hooks."
    ) {
        self.containerKey = containerKey
        self.command = command
        self.baseArguments = baseArguments
        self.identityMarker = identityMarker
        self.legacyIdentityMarkers = legacyIdentityMarkers
        self.definitions = definitions
        self.descriptionForNewFiles = descriptionForNewFiles
    }

    /// A configuration that runs a helper script.
    ///
    /// Both products use this now. Codex always did -- it has no other hook
    /// type -- and Claude Code moved here from `http` when the port turned out
    /// to be the whole of CC-021 and CC-014: an unowned port prints a line in
    /// the user's session for every event and can be taken by anything, and no
    /// registration this app can write changes either. A helper that exits 0
    /// says nothing, and a socket in this app's own directory cannot be taken.
    ///
    /// `arguments` selects Claude Code's exec form. With the key present the
    /// CLI resolves `command` as an executable and spawns it directly rather
    /// than through a shell, which is one process instead of two: measured
    /// 6.3 ms against 10.9 ms per event on 2.1.237. Codex passes `nil` because
    /// its schema has no such key.
    nonisolated static func command(
        _ command: String,
        arguments: [String]? = nil,
        containerKey: String = "hooks",
        legacyCommands: [String] = [],
        definitions: [ManagedHookDefinition],
        descriptionForNewFiles: String? = "User-level Codex lifecycle hooks."
    ) -> ManagedHooksConfiguration {
        ManagedHooksConfiguration(
            containerKey: containerKey,
            command: command,
            baseArguments: arguments,
            identityMarker: command,
            legacyIdentityMarkers: legacyCommands,
            definitions: definitions,
            descriptionForNewFiles: descriptionForNewFiles
        )
    }

    /// The handler entry this build installs for one definition.
    ///
    /// Everything a definition can vary is here and nowhere else, so a
    /// definition that varies nothing produces the bytes it always produced —
    /// which is what keeps the other six or eleven definitions' Codex trust
    /// hashes untouched when the answering one changes (ADR 0014).
    nonisolated func handler(for definition: ManagedHookDefinition) -> [String: Any] {
        var handler: [String: Any] = [
            "type": "command",
            "timeout": definition.timeoutSeconds
        ]
        if let baseArguments {
            handler["command"] = command
            handler["args"] = baseArguments + (definition.argument.map { [$0] } ?? [])
        } else {
            // Codex has no `args` key and parses `command` with a shell, so the
            // literal goes on the command line — where it is also the thing a
            // person reviewing `/hooks` reads.
            handler["command"] = definition.argument.map { "\(command) \($0)" }
                ?? command
        }
        return handler
    }

    // MARK: - Install

    /// Returns `root` with exactly one current definition per managed event.
    ///
    /// Any earlier copy of this app's handler is removed first, so installing
    /// twice cannot accumulate duplicates.
    nonisolated func installing(
        into root: [String: Any],
        isNewFile: Bool
    ) throws -> [String: Any] {
        var root = root
        var hooks = try validatedHooks(in: root)

        hooks = try strippingManagedHandlers(from: hooks, strictEvents: managedEventNames)

        // Nothing this app wrote may survive the strip. If a copy of the
        // command is still reachable, it sits in a structure this type cannot
        // edit, and installing on top of it would register the hook twice.
        if Self.containsAnyMarker(of: self, in: hooks) {
            throw ManagedHooksConfigurationError.unremovableManagedCommand
        }

        for definition in definitions {
            switch definition.shape {
            case .groupedByMatcher:
                var groups = try validatedGroups(for: definition.event, in: hooks)
                var group: [String: Any] = ["hooks": [handler(for: definition)]]
                if let matcher = definition.matcher {
                    group["matcher"] = matcher
                }
                groups.append(group)
                hooks[definition.event] = groups
            case .handlerList:
                var handlers = try validatedHandlerList(for: definition.event, in: hooks)
                handlers.append(handler(for: definition))
                hooks[definition.event] = handlers
            }
        }

        root[containerKey] = hooks
        // Only ever stamped on a file this app just created, and only for a
        // product that wants one. Adding a description to a file somebody else
        // owns is outside the boundary, however harmless it looks.
        if isNewFile, let descriptionForNewFiles, root["description"] == nil {
            root["description"] = descriptionForNewFiles
        }
        return root
    }

    // MARK: - Remove

    /// Returns `root` with every copy of this app's handler removed.
    ///
    /// Throws rather than returning a partial result, because the caller
    /// deletes the helper script afterwards: a silent partial removal is how
    /// `hooks.json` ends up pointing at a script that no longer exists.
    nonisolated func removing(from root: [String: Any]) throws -> [String: Any] {
        var root = root
        guard root[containerKey] != nil else {
            // No hooks at all is a clean state, but only if the command is not
            // hiding somewhere else in the document.
            if Self.containsAnyMarker(of: self, in: root) {
                throw ManagedHooksConfigurationError.unremovableManagedCommand
            }
            return root
        }

        var hooks = try validatedHooks(in: root)
        // No event is strict here, deliberately. Removal writes no key of its
        // own, so an event whose shape this type cannot read is one it can
        // simply leave alone -- and refusing on account of it would mean a user
        // with any unusual event could never cleanly uninstall. The deep scan
        // below is what makes that safe: it finds anything of ours that
        // survived, in any shape, and turns it into a refusal.
        hooks = try strippingManagedHandlers(from: hooks, strictEvents: [])

        if Self.containsAnyMarker(of: self, in: hooks) {
            throw ManagedHooksConfigurationError.unremovableManagedCommand
        }

        if hooks.isEmpty {
            root.removeValue(forKey: containerKey)
        } else {
            root[containerKey] = hooks
        }

        if Self.containsAnyMarker(of: self, in: root) {
            throw ManagedHooksConfigurationError.unremovableManagedCommand
        }
        return root
    }

    // MARK: - Verification

    /// Whether `root` holds exactly one current definition per managed event.
    ///
    /// Two conditions, because they catch different failures. **Exactly one of
    /// ours** rules out a second copy, which would fire alongside the first.
    /// **And it is the current one** rules out a handler this app would no
    /// longer install — an older shape still fires, and fires wrongly.
    ///
    /// The second condition used to be missing here, and the gap had teeth on
    /// the Claude Code side, where a registration was whatever the user had
    /// once pasted and the app could not repair it (ADR 0010, since reversed by
    /// ADR 0016). A paste whose `timeout` had since changed was reported
    /// `active`, and the events then waited longer than they should while the
    /// notch simply stayed empty. Being able to rewrite the file does not make
    /// this condition redundant — it is what turns a stale registration into a
    /// row that asks to be switched off and on. The app had no way to say so,
    /// because identity here is
    /// deliberately just a marker — it has to stay loose enough to recognise
    /// shapes this app no longer writes — and a marker cannot tell a current
    /// handler from a stale one.
    ///
    /// The stale shape that matters now is the whole of the previous
    /// transport: an `http` handler naming `127.0.0.1:51741`, which everyone
    /// who installed before ADR 0013 still has. It is recognised through the
    /// legacy marker and reported as needing repair, which is the only thing
    /// this app can do about it — it may not take the handler out of their
    /// file.
    nonisolated func isFullyInstalled(in root: [String: Any]) -> Bool {
        guard let hooks = root[containerKey] as? [String: Any] else { return false }
        return definitions.allSatisfy { definition in
            let managed = managedHandlers(for: definition, in: hooks)
            guard managed.count == 1 else { return false }
            return isCurrentManagedHandler(managed[0], for: definition)
        }
    }

    /// This app's handlers registered where `definition` would be written —
    /// in the group carrying its matcher, or in the list, as its shape says.
    nonisolated private func managedHandlers(
        for definition: ManagedHookDefinition,
        in hooks: [String: Any]
    ) -> [[String: Any]] {
        guard let registered = hooks[definition.event] as? [[String: Any]] else {
            return []
        }
        switch definition.shape {
        case .groupedByMatcher:
            return registered
                .filter { matcher(in: $0, matches: definition.matcher) }
                .flatMap { ($0["hooks"] as? [[String: Any]] ?? []).filter(isManagedHandler) }
        case .handlerList:
            return registered.filter(isManagedHandler)
        }
    }

    /// The managed events whose registered handler this build would **change**.
    ///
    /// Asked *before* an install writes, and the answer is what a Codex user
    /// then has to trust a second time: that product hashes a definition's
    /// content under a key that names the event, so a definition whose bytes
    /// did not move keeps its hash and keeps firing while a changed one
    /// silently stops (ADR 0014).
    ///
    /// **A definition that was not there does not count**, and the distinction
    /// is the whole usefulness of this. A first install needs trusting too, and
    /// says so twice already — the settings card reads `reviewRequired` until
    /// an event arrives, and the install message names `/hooks`. The state
    /// nothing announces is the other one: an upgrade rewrites a definition on
    /// a machine that has been delivering events for weeks, so the card reads
    /// `Connected` off a `lastEventAt` from before the rewrite and one
    /// definition is quietly dead behind it.
    ///
    /// This is the app's own knowledge of a state it **cannot verify**: whether
    /// the user then went to `/hooks` is not readable from here, and the
    /// alternative that would make it readable — parsing `[hooks.state]` out of
    /// `config.toml` — is a private-schema dependency ADR 0014 weighed and
    /// declined.
    nonisolated func eventsWhoseDefinitionChanges(
        comparedTo root: [String: Any]?
    ) -> [String] {
        guard let hooks = root?[containerKey] as? [String: Any] else { return [] }
        return definitions.filter { definition in
            let registered = managedHandlers(for: definition, in: hooks)
            // Nothing of ours registered for this event is a first install of
            // it, not a change to it.
            guard let existing = registered.first, registered.count == 1 else {
                return false
            }
            return !isCurrentManagedHandler(existing, for: definition)
        }.map(\.event)
    }

    /// Whether any trace of this app's command remains anywhere in `root`.
    nonisolated func isFullyRemoved(from root: [String: Any]) -> Bool {
        !Self.containsAnyMarker(of: self, in: root)
    }

    /// How complete this app's registration is in a configuration document.
    ///
    /// The single reading behind both products' settings cards. It answers only
    /// what a file read can answer — Codex's own per-definition trust lives in
    /// `config.toml` and is not consulted here (see ``CodexHookRegistrar``).
    ///
    /// The middle case is the one that earns its keep. Some of ours is there
    /// and some is not: a partial paste, a set from a version of this app that
    /// registered different events, or a handler whose shape this build no
    /// longer writes. The user has to be told, because the missing events fail
    /// silently — no error, just a state the notch never learns about — and
    /// reporting `absent` instead would invite a second registration beside the
    /// first.
    nonisolated func registration(in root: [String: Any]?) -> HookRegistration {
        guard let root else { return .absent }
        if isFullyInstalled(in: root) { return .complete }
        if Self.containsAnyMarker(of: self, in: root) { return .mismatched }
        return .absent
    }

    /// Whether this handler is one of ours, including one an earlier version
    /// of this app installed.
    ///
    /// Deliberately loose, and it must stay that way: removal and reinstall
    /// both depend on recognising a handler this app no longer writes. Use
    /// ``isCurrentManagedHandler(_:)`` to ask the narrower question.
    nonisolated func isManagedHandler(_ handler: [String: Any]) -> Bool {
        allIdentityMarkers.contains { Self.contains(marker: $0, in: handler) }
    }

    /// Whether this handler is ours *and* the one this build installs.
    ///
    /// Whole-value equality against ``handler(for:)`` rather than a list of
    /// fields to check, so a field added to the handler later is covered the
    /// day it is added instead of the day somebody remembers this method. It
    /// subsumes what the Codex installer used to spell out by hand — a key
    /// count and one `timeout` — and it is what makes a paste that carries the
    /// wrong `timeout`, or names another port than the one it was read from, or
    /// still carries a key this app has stopped writing, report as needing
    /// repair rather than as active.
    ///
    /// **Asked per definition**, because the answer differs per definition now:
    /// the one event that carries an answer back registers a window and an
    /// argument the other definitions do not have. Asking it against a single
    /// handler would report every install as needing repair the moment one
    /// definition stopped matching the rest.
    ///
    /// Equality is `NSDictionary`'s, which is what both sides already are once
    /// `JSONSerialization` has been through them: nested objects compare by
    /// value, and `true` compares equal to `1` the way JSON means it.
    nonisolated func isCurrentManagedHandler(
        _ candidate: [String: Any],
        for definition: ManagedHookDefinition
    ) -> Bool {
        (candidate as NSDictionary) == (handler(for: definition) as NSDictionary)
    }

    nonisolated var allIdentityMarkers: [String] {
        [identityMarker] + legacyIdentityMarkers
    }

    // MARK: - Validation

    nonisolated private var managedEventNames: Set<String> {
        Set(definitions.map(\.event))
    }

    nonisolated private func validatedHooks(
        in root: [String: Any]
    ) throws -> [String: Any] {
        guard let existing = root[containerKey] else { return [:] }
        guard let hooks = existing as? [String: Any] else {
            throw ManagedHooksConfigurationError.hooksIsNotObject
        }
        return hooks
    }

    /// The handlers already registered for one list-shaped managed event.
    ///
    /// The same rule as ``validatedGroups(for:in:)``: absent is fine, and
    /// present in a shape this type cannot read is a refusal, because writing
    /// our handler would mean replacing what is there.
    nonisolated private func validatedHandlerList(
        for event: String,
        in hooks: [String: Any]
    ) throws -> [[String: Any]] {
        guard let existing = hooks[event] else { return [] }
        guard let handlers = existing as? [[String: Any]] else {
            throw ManagedHooksConfigurationError.eventIsNotGroupArray(event: event)
        }
        return handlers
    }

    /// How this app arranges `event`, where it registers one; a group array
    /// where it does not, which is the only shape a stripped event can have
    /// anything of ours inside.
    nonisolated private func shape(ofEvent event: String) -> ManagedHookDefinition.Shape {
        definitions.first { $0.event == event }?.shape ?? .groupedByMatcher
    }

    /// The groups already registered for one managed event.
    ///
    /// Absent is fine. Present but not an array of objects is not: writing our
    /// group would mean replacing whatever is there, which is exactly the
    /// data loss this type exists to prevent.
    nonisolated private func validatedGroups(
        for event: String,
        in hooks: [String: Any]
    ) throws -> [[String: Any]] {
        guard let existing = hooks[event] else { return [] }
        guard let groups = existing as? [[String: Any]] else {
            throw ManagedHooksConfigurationError.eventIsNotGroupArray(event: event)
        }
        for group in groups where group["hooks"] != nil {
            guard group["hooks"] is [[String: Any]] else {
                throw ManagedHooksConfigurationError.groupHooksAreNotHandlerArray(
                    event: event
                )
            }
        }
        return groups
    }

    /// Removes this app's handlers from every event it can parse.
    ///
    /// `strictEvents` are the events where an unparseable shape is an error
    /// instead of something to leave alone -- the ones this call is going to
    /// write to, or, on removal, all of them.
    nonisolated private func strippingManagedHandlers(
        from hooks: [String: Any],
        strictEvents: Set<String>
    ) throws -> [String: Any] {
        var hooks = hooks

        for event in hooks.keys.sorted() {
            guard let value = hooks[event] else { continue }
            guard let groups = value as? [[String: Any]] else {
                if strictEvents.contains(event) {
                    throw ManagedHooksConfigurationError.eventIsNotGroupArray(
                        event: event
                    )
                }
                // Not a shape this app could have written, so there is nothing
                // of ours to take out and nothing we are entitled to change.
                continue
            }

            if shape(ofEvent: event) == .handlerList {
                // The elements are the handlers. Ours go; anything else
                // stays, and an event left with nothing goes with them.
                let survivors = groups.filter { !isManagedHandler($0) }
                if survivors.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = survivors
                }
                continue
            }

            var retained: [[String: Any]] = []
            for group in groups {
                guard let handlers = group["hooks"] else {
                    retained.append(group)
                    continue
                }
                guard let handlerObjects = handlers as? [[String: Any]] else {
                    if strictEvents.contains(event) {
                        throw ManagedHooksConfigurationError
                            .groupHooksAreNotHandlerArray(event: event)
                    }
                    retained.append(group)
                    continue
                }

                let survivors = handlerObjects.filter { !isManagedHandler($0) }
                if survivors.isEmpty {
                    // The group existed only to carry our handler, so it goes
                    // with it. A group that had other handlers keeps them.
                    if handlerObjects.isEmpty {
                        retained.append(group)
                    }
                    continue
                }
                var updated = group
                updated["hooks"] = survivors
                retained.append(updated)
            }

            if retained.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = retained
            }
        }
        return hooks
    }

    nonisolated private func matcher(
        in group: [String: Any],
        matches expectedMatcher: String?
    ) -> Bool {
        if let expectedMatcher {
            return (group["matcher"] as? String) == expectedMatcher
        }
        return group["matcher"] == nil
    }

    /// Finds this app's marker anywhere in an arbitrary JSON value.
    ///
    /// This is the safety net that makes the whole type trustworthy: the
    /// structured editing above only reaches shapes it understands, so this
    /// answers "did anything of ours survive in a shape we could not touch"
    /// without needing to understand that shape at all.
    ///
    /// A command matches exactly; a URL matches on containment, because the
    /// port in it is allowed to move and the path is not.
    nonisolated static func containsAnyMarker(
        of configuration: ManagedHooksConfiguration,
        in value: Any
    ) -> Bool {
        configuration.allIdentityMarkers.contains { contains(marker: $0, in: value) }
    }

    nonisolated static func contains(marker: String, in value: Any) -> Bool {
        switch value {
        case let string as String:
            return string == marker || string.contains(marker)
        case let array as [Any]:
            return array.contains { contains(marker: marker, in: $0) }
        case let object as [String: Any]:
            return object.values.contains { contains(marker: marker, in: $0) }
        default:
            return false
        }
    }
}
