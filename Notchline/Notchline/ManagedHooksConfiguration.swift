import Foundation

/// One hook definition this app manages. Timeout and argument are per definition: only the
/// answering event gets the long wait, and every other definition keeps its bytes so Codex
/// needs one re-trust, not seven (ADR 0014).
nonisolated struct ManagedHookDefinition: Sendable, Equatable {
    /// Seconds; the helper's own `-w 1` sits inside it, so the innermost bound fires first.
    static let lifecycleTimeoutSeconds = 3

    /// How a product's file arranges one event's handlers. Declared per definition, never inferred
    /// from the file: Antigravity CLI 1.2.2 (measured 2026-09-11) rejects a group under a
    /// list-shaped event and disables the whole named hook.
    nonisolated enum Shape: Sendable, Equatable {
        /// `[{"matcher": …, "hooks": [handler, …]}, …]`: Codex and Claude Code for every event,
        /// Antigravity CLI for its tool events.
        case groupedByMatcher
        /// `[handler, …]`: Antigravity CLI's `PreInvocation`, `PostInvocation` and `Stop`; `matcher` is nil.
        case handlerList
    }

    let event: String
    let matcher: String?
    let shape: Shape
    /// Must exceed the helper's own window: a helper that gives up exits 0 silently, a killed one
    /// prints a hook error in the user's session (ADR 0013).
    let timeoutSeconds: Int
    /// The literal `$1` for the helper: ``AgentHookHelper/answeringArgument`` on the event that opens
    /// a wait, else `nil`, so the shell parses nothing.
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

/// Why an edit to a user's hooks configuration was refused; every case stops before writing.
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

/// Adds and removes exactly this app's hook definitions inside a user-owned configuration file.
/// Anything not positively identified is left byte for byte; a key holding an unknown shape
/// refuses the whole edit rather than coercing it to empty.
nonisolated struct ManagedHooksConfiguration: Sendable {
    /// `hooks` for Codex and Claude Code, shared with the user's own handlers, so edits go handler
    /// by handler. Antigravity CLI's root holds named hooks; this app's name holds only its own.
    let containerKey: String
    let command: String
    /// Present selects Claude Code's exec form (`command` spawned directly); `nil` is Codex, whose
    /// shell-parsed `command` takes arguments on the command line.
    let baseArguments: [String]?
    /// The command line for a shell handler; a fixed URL path for an HTTP one, whose port moves.
    let identityMarker: String
    /// Markers earlier versions installed under, so an upgrade still removes the old handler
    /// instead of leaving it pointing at a deleted script.
    let legacyIdentityMarkers: [String]
    let definitions: [ManagedHookDefinition]
    /// Written only into a file this app creates. `nil` for Claude Code, whose `settings.json` is
    /// validated against known keys.
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

    /// A configuration that runs a helper script, not an `http` port (CC-021, CC-014).
    /// `arguments` selects Claude Code's exec form: 6.3 ms against 10.9 ms per event on 2.1.237.
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

    /// Everything a definition varies is here, so an unchanged definition keeps its bytes and its
    /// Codex trust hash (ADR 0014).
    nonisolated func handler(for definition: ManagedHookDefinition) -> [String: Any] {
        var handler: [String: Any] = [
            "type": "command",
            "timeout": definition.timeoutSeconds
        ]
        if let baseArguments {
            handler["command"] = command
            handler["args"] = baseArguments + (definition.argument.map { [$0] } ?? [])
        } else {
            // Codex parses `command` with a shell; the literal is also what `/hooks` shows.
            handler["command"] = definition.argument.map { "\(command) \($0)" }
                ?? command
        }
        return handler
    }

    // MARK: - Install

    /// Returns `root` with exactly one current definition per managed event; earlier copies are
    /// removed first.
    nonisolated func installing(
        into root: [String: Any],
        isNewFile: Bool
    ) throws -> [String: Any] {
        var root = root
        var hooks = try validatedHooks(in: root)

        hooks = try strippingManagedHandlers(from: hooks, strictEvents: managedEventNames)

        // A copy still reachable sits in a structure this type cannot edit; installing would
        // register the hook twice.
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
        // Only on a file this app just created.
        if isNewFile, let descriptionForNewFiles, root["description"] == nil {
            root["description"] = descriptionForNewFiles
        }
        return root
    }

    // MARK: - Remove

    /// Returns `root` with every copy of this app's handler removed. Throws rather than returning
    /// a partial result: the caller then deletes the helper script.
    nonisolated func removing(from root: [String: Any]) throws -> [String: Any] {
        var root = root
        guard root[containerKey] != nil else {
            // No hooks at all is clean only if the command is not hiding elsewhere in the document.
            if Self.containsAnyMarker(of: self, in: root) {
                throw ManagedHooksConfigurationError.unremovableManagedCommand
            }
            return root
        }

        var hooks = try validatedHooks(in: root)
        // No event is strict: removal writes no key, so an unreadable event is left alone (or unusual
        // events would block uninstall). The deep scan below refuses anything of ours that survived.
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

    /// Whether `root` holds exactly one current definition per managed event. A second copy fires
    /// alongside; a stale shape (e.g. the pre-ADR 0013 `http` handler on `127.0.0.1:51741`) fires
    /// wrongly and reads as needing repair.
    nonisolated func isFullyInstalled(in root: [String: Any]) -> Bool {
        guard let hooks = root[containerKey] as? [String: Any] else { return false }
        return definitions.allSatisfy { definition in
            let managed = managedHandlers(for: definition, in: hooks)
            guard managed.count == 1 else { return false }
            return isCurrentManagedHandler(managed[0], for: definition)
        }
    }

    /// This app's handlers where `definition` would be written: its matcher's group, or the list.
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

    /// The managed events whose registered handler this build would change, asked before an
    /// install writes: Codex silently stops a changed definition until re-trusted (ADR 0014), while
    /// the card still reads `Connected`. A first install does not count; `reviewRequired` covers it.
    nonisolated func eventsWhoseDefinitionChanges(
        comparedTo root: [String: Any]?
    ) -> [String] {
        guard let hooks = root?[containerKey] as? [String: Any] else { return [] }
        return definitions.filter { definition in
            let registered = managedHandlers(for: definition, in: hooks)
            // Nothing of ours registered is a first install, not a change.
            guard let existing = registered.first, registered.count == 1 else {
                return false
            }
            return !isCurrentManagedHandler(existing, for: definition)
        }.map(\.event)
    }

    nonisolated func isFullyRemoved(from root: [String: Any]) -> Bool {
        !Self.containsAnyMarker(of: self, in: root)
    }

    /// How complete this app's registration is in a configuration document; the reading behind both
    /// products' settings cards. Codex trust in `config.toml` is not consulted
    /// (``CodexHookRegistrar``). A partial registration must not read `absent`: missing events fail
    /// silently, and `absent` invites a second registration.
    nonisolated func registration(in root: [String: Any]?) -> HookRegistration {
        guard let root else { return .absent }
        guard (try? validatedHooks(in: root)) != nil else { return .unreadable }
        if isFullyInstalled(in: root) { return .complete }
        if Self.containsAnyMarker(of: self, in: root) { return .mismatched }
        return .absent
    }

    /// Whether this handler is one of ours, including an earlier version's. Must stay loose: removal
    /// and reinstall recognise handlers this app no longer writes (see ``isCurrentManagedHandler(_:)``).
    nonisolated func isManagedHandler(_ handler: [String: Any]) -> Bool {
        allIdentityMarkers.contains { Self.contains(marker: $0, in: handler) }
    }

    /// Whether this handler is ours and current: whole-value `NSDictionary` equality against
    /// ``handler(for:)``, so new fields are covered. Asked per definition.
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

    /// Same rule as ``validatedGroups(for:in:)``: absent is fine, an unreadable shape refuses.
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

    /// How this app arranges `event`; a group array where it registers none, the only shape a
    /// stripped event can hold ours in.
    nonisolated private func shape(ofEvent event: String) -> ManagedHookDefinition.Shape {
        definitions.first { $0.event == event }?.shape ?? .groupedByMatcher
    }

    /// The groups already registered for one managed event. Absent is fine; anything but an array of
    /// objects refuses, since writing would replace it.
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

    /// Removes this app's handlers from every event it can parse. In `strictEvents` (those about to
    /// be written, or all on removal) an unparseable shape throws instead of being left alone.
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
                // Not a shape this app writes: nothing of ours, nothing to change.
                continue
            }

            if shape(ofEvent: event) == .handlerList {
                // The elements are the handlers; an event left empty is removed.
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
                    // A group that only carried our handler goes; others keep their handlers.
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

    /// Finds this app's marker anywhere in an arbitrary JSON value: the safety net for shapes the
    /// structured editing cannot reach. A command matches exactly; a URL on containment, since its
    /// port may move.
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
