import Foundation

enum HookSetupStatus: Equatable, Sendable {
    case notInstalled
    case repairRequired
    case reviewRequired
    case active

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
            "尚未安装"
        case .repairRequired:
            "安装不完整；请开启总开关以修复"
        case .reviewRequired:
            "已安装；请在 Codex /hooks 中信任"
        case .active:
            "已连接"
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

struct HookIntegrationPaths: Sendable {
    let supportDirectory: URL
    let hooksConfiguration: URL

    nonisolated var script: URL {
        supportDirectory.appendingPathComponent("codex_in_notch_hook.py")
    }

    nonisolated var eventsDirectory: URL {
        supportDirectory.appendingPathComponent("events", isDirectory: true)
    }

    nonisolated var state: URL {
        supportDirectory.appendingPathComponent("monitor-state.json")
    }

    nonisolated var settings: URL {
        supportDirectory.appendingPathComponent("hook-settings.json")
    }

    nonisolated var hooksBackup: URL {
        hooksConfiguration.appendingPathExtension("codex-in-notch-backup")
    }

    nonisolated static func live(fileManager: FileManager = .default) -> HookIntegrationPaths {
        let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("CodexInNotch", isDirectory: true)
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/CodexInNotch")

        return HookIntegrationPaths(
            supportDirectory: support,
            hooksConfiguration: fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/hooks.json")
        )
    }
}

actor CodexHookInstaller {
    private enum ManagedInstallationState {
        case missing
        case repairRequired
        case current
        case upgradeable
    }

    private enum ManagedRegistrationState {
        case absent
        case partial
        case complete
    }

    private struct ManagedHookDefinition: Sendable {
        let event: String
        let matcher: String?
    }

    nonisolated private static let managedDefinitions = [
        ManagedHookDefinition(event: "UserPromptSubmit", matcher: nil),
        ManagedHookDefinition(event: "PermissionRequest", matcher: nil),
        ManagedHookDefinition(
            event: "PreToolUse",
            matcher: "^(request_user_input|request_permissions)$"
        ),
        ManagedHookDefinition(event: "PostToolUse", matcher: nil),
        ManagedHookDefinition(event: "Stop", matcher: nil),
        ManagedHookDefinition(event: "SessionEnd", matcher: nil)
    ]

    private let paths: HookIntegrationPaths
    private let fileManager: FileManager

    init(
        paths: HookIntegrationPaths = .live(),
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func status(hasObservedEvent: Bool) -> HookSetupStatus {
        switch installationState {
        case .missing:
            return .notInstalled
        case .repairRequired:
            return .repairRequired
        case .current, .upgradeable:
            return hasObservedEvent ? .active : .reviewRequired
        }
    }

    @discardableResult
    func upgradeManagedHookIfNeeded() throws -> Bool {
        guard installationState == .upgradeable else { return false }

        try writeCurrentHookScript()
        try writeSettings(showsContentPreviews: storedShowsContentPreviews)
        return true
    }

    func install(showsContentPreviews: Bool) throws {
        try fileManager.createDirectory(
            at: paths.supportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        try writeCurrentHookScript()
        try writeSettings(showsContentPreviews: showsContentPreviews)
        try mergeHooksConfiguration()
    }

    func updateSettings(showsContentPreviews: Bool) throws {
        guard fileManager.fileExists(atPath: paths.supportDirectory.path) else {
            return
        }
        try writeSettings(showsContentPreviews: showsContentPreviews)
    }

    func uninstall() throws {
        try removeManagedHooksConfiguration()

        for url in [paths.script, paths.settings, paths.state] {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        if fileManager.fileExists(atPath: paths.eventsDirectory.path) {
            try fileManager.removeItem(at: paths.eventsDirectory)
        }
        if let remaining = try? fileManager.contentsOfDirectory(
            at: paths.supportDirectory,
            includingPropertiesForKeys: nil
        ), remaining.isEmpty {
            try? fileManager.removeItem(at: paths.supportDirectory)
        }
    }

    private var command: String {
        "/usr/bin/python3 \"\(paths.script.path)\""
    }

    private var installationState: ManagedInstallationState {
        let registrationState = managedRegistrationState
        guard registrationState == .complete else {
            return registrationState == .partial || hasManagedSupportFootprint
                ? .repairRequired
                : .missing
        }

        guard fileManager.isExecutableFile(atPath: paths.script.path),
              let installedScript = try? String(
                  contentsOf: paths.script,
                  encoding: .utf8
              ) else {
            return .repairRequired
        }

        // The bundled script is available in process, so a direct comparison
        // answers "is this exactly what this build installs" without hashing.
        if installedScript == Self.hookScript {
            return .current
        }

        // A different script sits at a path this app manages exclusively. The
        // settings file is written only by install(), so its presence is what
        // distinguishes "our own older helper" from a file this app never put
        // there. Recording a content hash next to the script would not add
        // tamper resistance: both live in the same directory with the same
        // ownership, so anything that can rewrite one can rewrite the other.
        return fileManager.fileExists(atPath: paths.settings.path)
            ? .upgradeable
            : .repairRequired
    }

    private var managedRegistrationState: ManagedRegistrationState {
        guard let data = try? Data(contentsOf: paths.hooksConfiguration),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else {
            return .absent
        }

        let managedOccurrenceCount = hooks.values.reduce(into: 0) { count, value in
            guard let groups = value as? [[String: Any]] else { return }
            for group in groups {
                let handlers = group["hooks"] as? [[String: Any]] ?? []
                count += handlers.filter(isManagedHandler).count
            }
        }

        guard managedOccurrenceCount > 0 else { return .absent }
        guard managedOccurrenceCount == Self.managedDefinitions.count else {
            return .partial
        }

        let hasEveryExactDefinition = Self.managedDefinitions.allSatisfy { definition in
            guard let groups = hooks[definition.event] as? [[String: Any]] else {
                return false
            }
            let exactMatches = groups.reduce(into: 0) { count, group in
                guard matcher(in: group, matches: definition.matcher) else {
                    return
                }
                let handlers = group["hooks"] as? [[String: Any]] ?? []
                count += handlers.filter(isCurrentManagedHandler).count
            }
            return exactMatches == 1
        }

        return hasEveryExactDefinition ? .complete : .partial
    }

    private var hasManagedSupportFootprint: Bool {
        fileManager.fileExists(atPath: paths.supportDirectory.path)
            || fileManager.fileExists(atPath: paths.script.path)
            || fileManager.fileExists(atPath: paths.settings.path)
            || fileManager.fileExists(atPath: paths.state.path)
            || fileManager.fileExists(atPath: paths.eventsDirectory.path)
    }

    private func matcher(
        in group: [String: Any],
        matches expectedMatcher: String?
    ) -> Bool {
        if let expectedMatcher {
            return (group["matcher"] as? String) == expectedMatcher
        }
        return group["matcher"] == nil
    }

    private func isCurrentManagedHandler(_ handler: [String: Any]) -> Bool {
        guard isManagedHandler(handler), handler.count == 3 else { return false }
        return (handler["timeout"] as? NSNumber)?.intValue == 3
    }

    private var storedSettings: [String: Any] {
        guard let data = try? Data(contentsOf: paths.settings),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return root
    }

    private var storedShowsContentPreviews: Bool {
        storedSettings["showsContentPreviews"] as? Bool ?? true
    }

    private func writeCurrentHookScript() throws {
        try Self.hookScript.write(
            to: paths.script,
            atomically: true,
            encoding: .utf8
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: paths.script.path
        )
    }

    private func writeSettings(showsContentPreviews: Bool) throws {
        var settings = storedSettings
        settings["showsContentPreviews"] = showsContentPreviews
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: paths.settings, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: paths.settings.path
        )
    }

    private func mergeHooksConfiguration() throws {
        try fileManager.createDirectory(
            at: paths.hooksConfiguration.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var root: [String: Any] = [:]
        if fileManager.fileExists(atPath: paths.hooksConfiguration.path) {
            let data = try Data(contentsOf: paths.hooksConfiguration)
            root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for event in Array(hooks.keys) {
            guard let groups = hooks[event] as? [[String: Any]] else { continue }
            let retained = groups.compactMap(removingManagedHandlers)
            if retained.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = retained
            }
        }

        for definition in Self.managedDefinitions {
            var groups = hooks[definition.event] as? [[String: Any]] ?? []

            var group: [String: Any] = [
                "hooks": [[
                    "type": "command",
                    "command": command,
                    "timeout": 3
                ]]
            ]
            if let matcher = definition.matcher {
                group["matcher"] = matcher
            }
            groups.append(group)
            hooks[definition.event] = groups
        }

        root["hooks"] = hooks
        if root["description"] == nil {
            root["description"] = "User-level Codex lifecycle hooks."
        }

        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try preserveRecoveryCopyIfNeeded()
        try data.write(to: paths.hooksConfiguration, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: paths.hooksConfiguration.path
        )
    }

    private func removingManagedHandlers(_ group: [String: Any]) -> [String: Any]? {
        guard let handlers = group["hooks"] as? [[String: Any]] else {
            return group
        }

        let retained = handlers.filter { !isManagedHandler($0) }
        guard !retained.isEmpty else { return nil }

        var updated = group
        updated["hooks"] = retained
        return updated
    }

    private func isManagedHandler(_ handler: [String: Any]) -> Bool {
        (handler["type"] as? String) == "command"
            && (handler["command"] as? String) == command
    }

    private func preserveRecoveryCopyIfNeeded() throws {
        guard fileManager.fileExists(atPath: paths.hooksConfiguration.path) else {
            return
        }
        guard !fileManager.fileExists(atPath: paths.hooksBackup.path) else {
            return
        }
        try fileManager.copyItem(
            at: paths.hooksConfiguration,
            to: paths.hooksBackup
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: paths.hooksBackup.path
        )
    }

    private func removeManagedHooksConfiguration() throws {
        guard fileManager.fileExists(atPath: paths.hooksConfiguration.path) else {
            return
        }

        let original = try Data(contentsOf: paths.hooksConfiguration)
        guard var root = try JSONSerialization.jsonObject(with: original) as? [String: Any],
              var hooks = root["hooks"] as? [String: Any] else {
            return
        }

        for event in Array(hooks.keys) {
            guard let groups = hooks[event] as? [[String: Any]] else { continue }
            let retained = groups.compactMap(removingManagedHandlers)
            if retained.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = retained
            }
        }
        root["hooks"] = hooks

        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try preserveRecoveryCopyIfNeeded()
        try data.write(to: paths.hooksConfiguration, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: paths.hooksConfiguration.path
        )
    }

    private static let hookScript = #"""
#!/usr/bin/python3
import json
import os
import sys
import time
import uuid

SUPPORT = os.path.dirname(os.path.abspath(__file__))
EVENTS = os.path.join(SUPPORT, "events")
SETTINGS = os.path.join(SUPPORT, "hook-settings.json")

def previews_enabled():
    try:
        with open(SETTINGS, "r", encoding="utf-8") as handle:
            return bool(json.load(handle).get("showsContentPreviews", True))
    except Exception:
        return False

try:
    payload = json.load(sys.stdin)
    event = {
        "event_id": str(uuid.uuid4()),
        "received_at": time.time(),
        "hook_event_name": payload.get("hook_event_name"),
        "session_id": payload.get("session_id"),
        "turn_id": payload.get("turn_id"),
        "tool_name": payload.get("tool_name"),
        "tool_use_id": payload.get("tool_use_id"),
    }
    if previews_enabled():
        prompt = payload.get("prompt")
        assistant = payload.get("last_assistant_message")
        if isinstance(prompt, str):
            event["prompt"] = prompt[:240]
        if isinstance(assistant, str):
            event["last_assistant_message"] = assistant[:240]

    os.makedirs(EVENTS, mode=0o700, exist_ok=True)
    filename = "%020d-%s.json" % (time.time_ns(), event["event_id"])
    target = os.path.join(EVENTS, filename)
    temporary = target + ".tmp"
    with open(temporary, "x", encoding="utf-8") as handle:
        os.chmod(temporary, 0o600)
        json.dump(event, handle, separators=(",", ":"))
    os.replace(temporary, target)
except Exception:
    pass

# Stop hooks require JSON on stdout. An empty object is a no-op for every
# configured event and never changes Codex behavior.
print("{}")
"""#
}

struct HookTurnState: Sendable {
    let threadID: String
    let turnID: String
    var sessionStatus: SessionStatus
    /// `tool_use_id` of an open `request_user_input` call, if any.
    var pendingInputToolUseID: String?
    /// `tool_use_id` of an open `request_permissions` call, if any.
    ///
    /// Both waits are the same shape: Codex opens a tool call, the human acts,
    /// and the matching `PostToolUse` closes it. Pairing on the id is what
    /// keeps an auto-resolved request from sticking as a false wait.
    var pendingApprovalToolUseID: String?
    var startedAt: Date
    var lastEventAt: Date
    var retiredTurnIDs: Set<String>
    var promptPreview: String?
    var assistantPreview: String?

    nonisolated var status: SessionStatus {
        sessionStatus
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

actor HookEventRepository {
    private struct LegacyPersistedTurn: Codable {}

    private struct PersistedState: Codable {
        var hasObservedEvent: Bool?
        var turns: [LegacyPersistedTurn]?
    }

    private struct HookEvent: Decodable {
        let receivedAt: Double
        let hookEventName: String?
        let sessionID: String?
        let turnID: String?
        let toolName: String?
        let toolUseID: String?
        let prompt: String?
        let lastAssistantMessage: String?

        enum CodingKeys: String, CodingKey {
            case receivedAt = "received_at"
            case hookEventName = "hook_event_name"
            case sessionID = "session_id"
            case turnID = "turn_id"
            case toolName = "tool_name"
            case toolUseID = "tool_use_id"
            case prompt
            case lastAssistantMessage = "last_assistant_message"
        }
    }

    private let paths: HookIntegrationPaths
    private let fileManager: FileManager
    private let liveEventCutoff: Date
    private var hasObservedEvent: Bool
    private var hasObservedLiveEvent: Bool
    private var turnsByThreadID: [String: HookTurnState]

    init(
        paths: HookIntegrationPaths = .live(),
        fileManager: FileManager = .default,
        liveEventCutoff: Date = Date()
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.liveEventCutoff = liveEventCutoff

        if let data = try? Data(contentsOf: paths.state),
           let persisted = try? JSONDecoder().decode(PersistedState.self, from: data) {
            // A valid event proves only that the installed hook was trusted at
            // least once. This persisted marker is configuration health evidence;
            // it is never restored as current Desktop runtime evidence.
            self.hasObservedEvent = persisted.hasObservedEvent
                ?? !(persisted.turns ?? []).isEmpty
            self.hasObservedLiveEvent = false
            // A persisted Turn is historical by definition. Restoring it would
            // turn the last observed Running/Input/Approval into a false claim
            // about the current Desktop runtime.
            self.turnsByThreadID = [:]
            if persisted.turns != nil {
                try? Self.writeObservationMarker(
                    hasObservedEvent: self.hasObservedEvent,
                    paths: paths,
                    fileManager: fileManager
                )
            }
        } else {
            self.hasObservedEvent = false
            self.hasObservedLiveEvent = false
            self.turnsByThreadID = [:]
        }
    }

    func consumeEvents() -> HookStateSnapshot {
        let urls = (try? fileManager.contentsOfDirectory(
            at: paths.eventsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension == "json" }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        } ?? []

        guard !urls.isEmpty else {
            return snapshot()
        }

        var candidateTurns = turnsByThreadID
        var validURLs: [URL] = []
        var didConsumeLiveEvents = false
        var diagnostic: String?

        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let event = try? JSONDecoder().decode(HookEvent.self, from: data) else {
                diagnostic = "忽略了一个损坏的 Hook 事件文件。"
                quarantineInvalidEvent(at: url)
                continue
            }

            // Files left behind before this repository was created are backlog,
            // not a snapshot of the current Desktop runtime. They may prove that
            // the managed hook has executed before, but no historical event type
            // is allowed to create or mutate a current Turn.
            guard event.receivedAt.isFinite else {
                diagnostic = "忽略了一个缺少稳定身份或不受支持的 Hook 事件。"
                quarantineInvalidEvent(at: url)
                continue
            }
            guard Date(timeIntervalSince1970: event.receivedAt) >= liveEventCutoff else {
                validURLs.append(url)
                continue
            }

            if reduce(event, into: &candidateTurns) {
                validURLs.append(url)
                didConsumeLiveEvents = true
            } else {
                diagnostic = "忽略了一个缺少稳定身份或不受支持的 Hook 事件。"
                quarantineInvalidEvent(at: url)
            }
        }

        guard !validURLs.isEmpty else {
            return snapshot(diagnostic: diagnostic)
        }

        let previousTurns = turnsByThreadID
        let previouslyObservedEvent = hasObservedEvent
        let previouslyObservedLiveEvent = hasObservedLiveEvent
        turnsByThreadID = candidateTurns
        hasObservedEvent = true
        hasObservedLiveEvent = hasObservedLiveEvent || didConsumeLiveEvents
        do {
            try persist()
        } catch {
            turnsByThreadID = previousTurns
            hasObservedEvent = previouslyObservedEvent
            hasObservedLiveEvent = previouslyObservedLiveEvent
            return snapshot(
                diagnostic: "Hook 状态写入失败；事件已保留并会重试：\(error.localizedDescription)"
            )
        }

        for url in validURLs {
            try? fileManager.removeItem(at: url)
        }
        return snapshot(
            didConsumeEvents: didConsumeLiveEvents,
            diagnostic: diagnostic
        )
    }

    func removeThreads(
        notIn unarchivedThreadIDs: Set<String>,
        snapshotStartedAt: Date
    ) -> HookStateSnapshot {
        let originalCount = turnsByThreadID.count
        let now = Date()
        turnsByThreadID = turnsByThreadID.filter {
            if unarchivedThreadIDs.contains($0.key) {
                return true
            }
            // A list request that began before the latest Hook boundary cannot
            // prove that the new Turn was archived or deleted.
            if snapshotStartedAt < $0.value.lastEventAt {
                return true
            }
            // A prompt hook can arrive just before the state DB is updated.
            // Keep a short grace period so reconciliation does not erase a new turn.
            return now.timeIntervalSince($0.value.startedAt) < 10
        }
        if turnsByThreadID.count != originalCount {
            try? persist()
        }
        return snapshot()
    }

    func clearContentPreviews() {
        turnsByThreadID = turnsByThreadID.mapValues { state in
            var redacted = state
            redacted.promptPreview = nil
            redacted.assistantPreview = nil
            return redacted
        }
        try? persist()
    }

    func clearTurnsPreservingObservation() {
        turnsByThreadID.removeAll()
        try? persist()
    }

    func resetIntegrationObservation(clearTurns: Bool) {
        hasObservedEvent = false
        hasObservedLiveEvent = false
        if clearTurns {
            turnsByThreadID.removeAll()
        }
        try? persist()
    }

    private func reduce(
        _ event: HookEvent,
        into turns: inout [String: HookTurnState]
    ) -> Bool {
        guard let eventName = stableIdentifier(event.hookEventName),
              let threadID = stableIdentifier(event.sessionID),
              event.receivedAt.isFinite else {
            return false
        }

        if eventName == "SessionEnd" {
            return true
        }

        let supportedEvents = Set([
            "UserPromptSubmit",
            "PermissionRequest",
            "PreToolUse",
            "PostToolUse",
            "Stop"
        ])
        guard supportedEvents.contains(eventName),
              let turnID = stableIdentifier(event.turnID) else {
            return false
        }

        let receivedAt = Date(timeIntervalSince1970: event.receivedAt)

        switch eventName {
        case "UserPromptSubmit":
            var retiredTurnIDs = Set<String>()
            if let current = turns[threadID] {
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
            turns[threadID] = HookTurnState(
                threadID: threadID,
                turnID: turnID,
                sessionStatus: .running,
                pendingInputToolUseID: nil,
                pendingApprovalToolUseID: nil,
                startedAt: receivedAt,
                lastEventAt: receivedAt,
                retiredTurnIDs: retiredTurnIDs,
                promptPreview: event.prompt,
                assistantPreview: nil
            )
        case "PermissionRequest":
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .running,
                adoptContinuationWith: .running,
                turns: &turns
            ) { _ in
                // PermissionRequest only proves the approval pipeline ran. It is
                // neither human-wait evidence nor a Running signal, so it cannot
                // enter or leave a wait state.
            }
        case "PreToolUse" where event.toolName == "request_user_input":
            guard let toolUseID = stableIdentifier(event.toolUseID) else {
                return false
            }
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .running,
                adoptContinuationWith: .running,
                turns: &turns
            ) {
                $0.pendingInputToolUseID = toolUseID
                $0.sessionStatus = $0.sessionStatus.transitioned(on: .inputNeeded)
            }
        case "PreToolUse" where event.toolName == "request_permissions":
            // Codex surfaces a Desktop approval prompt as a `request_permissions`
            // tool call that stays open for exactly as long as the human is
            // being asked -- the same shape as `request_user_input`.
            guard let toolUseID = stableIdentifier(event.toolUseID) else {
                return false
            }
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .running,
                adoptContinuationWith: .running,
                turns: &turns
            ) {
                $0.pendingApprovalToolUseID = toolUseID
                $0.sessionStatus = $0.sessionStatus.transitioned(on: .approvalNeeded)
            }
        case "PostToolUse":
            guard let toolUseID = stableIdentifier(event.toolUseID) else {
                return true
            }
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: nil,
                adoptContinuationWith: .running,
                turns: &turns
            ) {
                if $0.pendingInputToolUseID == toolUseID {
                    $0.pendingInputToolUseID = nil
                }
                if $0.pendingApprovalToolUseID == toolUseID {
                    $0.pendingApprovalToolUseID = nil
                }
                // Only resume Running once no wait is still open: an unrelated
                // tool finishing must not clear a prompt the human has not
                // answered. The state machine only enters a wait from Running,
                // so at most one of these is ever set.
                if $0.pendingInputToolUseID != nil {
                    $0.sessionStatus = $0.sessionStatus.transitioned(on: .inputNeeded)
                } else if $0.pendingApprovalToolUseID != nil {
                    $0.sessionStatus = $0.sessionStatus.transitioned(on: .approvalNeeded)
                } else {
                    $0.sessionStatus = $0.sessionStatus.transitioned(on: .running)
                }
            }
        case "Stop":
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .completed,
                adoptContinuationWith: .completed,
                turns: &turns
            ) {
                // The product intentionally exposes one terminal state. Stop,
                // completed, failed, and interrupted all converge to Completed.
                $0.sessionStatus = $0.sessionStatus.transitioned(on: .completed)
                $0.pendingInputToolUseID = nil
                $0.pendingApprovalToolUseID = nil
                $0.assistantPreview = event.lastAssistantMessage
            }
        default:
            break
        }
        return true
    }

    private func mutateExactTurn(
        threadID: String,
        turnID: String,
        at date: Date,
        createWith sessionStatus: SessionStatus?,
        adoptContinuationWith continuationStatus: SessionStatus?,
        turns: inout [String: HookTurnState],
        mutation: (inout HookTurnState) -> Void
    ) {
        var state: HookTurnState
        if let current = turns[threadID] {
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
                    pendingApprovalToolUseID: nil,
                    startedAt: current.startedAt,
                    lastEventAt: date,
                    retiredTurnIDs: retiredTurnIDs,
                    promptPreview: current.promptPreview,
                    assistantPreview: nil
                )
            }
        } else {
            guard let sessionStatus else { return }
            state = HookTurnState(
                threadID: threadID,
                turnID: turnID,
                sessionStatus: sessionStatus,
                pendingInputToolUseID: nil,
                pendingApprovalToolUseID: nil,
                startedAt: date,
                lastEventAt: date,
                retiredTurnIDs: [],
                promptPreview: nil,
                assistantPreview: nil
            )
        }
        mutation(&state)
        state.lastEventAt = max(state.lastEventAt, date)
        turns[threadID] = state
    }

    private func stableIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func snapshot(
        didConsumeEvents: Bool = false,
        diagnostic: String? = nil
    ) -> HookStateSnapshot {
        HookStateSnapshot(
            hasObservedEvent: hasObservedEvent,
            hasObservedLiveEvent: hasObservedLiveEvent,
            turns: turnsByThreadID.values.sorted { $0.startedAt > $1.startedAt },
            didConsumeEvents: didConsumeEvents,
            diagnostic: diagnostic
        )
    }

    private func quarantineInvalidEvent(at url: URL) {
        let quarantine = url.deletingPathExtension().appendingPathExtension("invalid")
        try? fileManager.moveItem(at: url, to: quarantine)
    }

    private func persist() throws {
        try Self.writeObservationMarker(
            hasObservedEvent: hasObservedEvent,
            paths: paths,
            fileManager: fileManager
        )
    }

    private static func writeObservationMarker(
        hasObservedEvent: Bool,
        paths: HookIntegrationPaths,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: paths.supportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        // Runtime Turn identity and evidence are intentionally memory-only. A
        // successful event proves hook trust, but never proves restart liveness.
        let data = try JSONEncoder().encode(
            PersistedState(
                hasObservedEvent: hasObservedEvent,
                turns: nil
            )
        )
        try data.write(to: paths.state, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: paths.state.path
        )
    }
}
