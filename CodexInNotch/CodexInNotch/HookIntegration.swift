import CryptoKit
import Foundation

enum HookSetupStatus: Equatable, Sendable {
    case notInstalled
    case reviewRequired
    case active

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.notInstalled, .notInstalled),
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
        case .reviewRequired:
            "已安装；请在 Codex /hooks 中信任"
        case .active:
            "已连接"
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
        case current
        case upgradeable
    }

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
        guard installationState != .missing else { return .notInstalled }
        return hasObservedEvent ? .active : .reviewRequired
    }

    @discardableResult
    func upgradeManagedHookIfNeeded() throws -> Bool {
        guard installationState == .upgradeable else { return false }

        try writeCurrentHookScript()
        try writeSettings(
            showsContentPreviews: storedShowsContentPreviews,
            managedScript: Self.hookScript
        )
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
        try writeSettings(
            showsContentPreviews: showsContentPreviews,
            managedScript: Self.hookScript
        )
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
        guard fileManager.isExecutableFile(atPath: paths.script.path),
              let installedScript = try? String(
                  contentsOf: paths.script,
                  encoding: .utf8
              ),
              hasManagedHookRegistration else {
            return .missing
        }

        let installedDigest = Self.digest(of: installedScript)
        if installedScript == Self.hookScript {
            return storedManagedHookDigest == installedDigest
                ? .current
                : .upgradeable
        }
        if storedManagedHookDigest == installedDigest
            || Self.legacyManagedHookDigests.contains(installedDigest) {
            return .upgradeable
        }
        return .missing
    }

    private var hasManagedHookRegistration: Bool {
        guard let data = try? Data(contentsOf: paths.hooksConfiguration),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else {
            return false
        }

        return hooks.values.contains { value in
            guard let groups = value as? [[String: Any]] else { return false }
            return groups.contains { group in
                guard let handlers = group["hooks"] as? [[String: Any]] else {
                    return false
                }
                return handlers.contains {
                    ($0["command"] as? String) == command
                }
            }
        }
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

    private var storedManagedHookDigest: String? {
        storedSettings[Self.managedHookDigestKey] as? String
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

    private func writeSettings(
        showsContentPreviews: Bool,
        managedScript: String? = nil
    ) throws {
        var settings = storedSettings
        settings["showsContentPreviews"] = showsContentPreviews
        if let managedScript {
            settings[Self.managedHookDigestKey] = Self.digest(of: managedScript)
            settings[Self.managedHookVersionKey] = Self.currentManagedHookVersion
        }
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

    nonisolated private static func digest(of script: String) -> String {
        SHA256.hash(data: Data(script.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
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
        let definitions: [(event: String, matcher: String?)] = [
            ("UserPromptSubmit", nil),
            ("PermissionRequest", nil),
            ("PreToolUse", "^request_user_input$"),
            ("PostToolUse", nil),
            ("Stop", nil),
            ("SessionEnd", nil)
        ]

        for definition in definitions {
            var groups = hooks[definition.event] as? [[String: Any]] ?? []
            groups = groups.compactMap(removingManagedHandlers)

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

    private static let managedHookDigestKey = "managedHookSHA256"
    private static let managedHookVersionKey = "managedHookVersion"
    private static let currentManagedHookVersion = 1

    // Releases before managed-hook metadata used this exact helper. Recognizing
    // its digest provides a one-time safe migration without accepting arbitrary
    // executable files at the managed path.
    private static let legacyManagedHookDigests: Set<String> = [
        "064bacb3aa56c5fb7399c192fe51fa8e1d8dfda24f6c61b72869448cbced839b"
    ]

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

enum HookPendingInputEvidence: Sendable {
    case hook(toolUseID: String)
    case appServerSnapshot
}

struct HookTurnState: Sendable {
    let threadID: String
    let turnID: String
    var lifecycleStatus: MonitorStatus
    var pendingInput: HookPendingInputEvidence?
    var isApprovalPending: Bool
    var isTerminalStatusPending: Bool = false
    var startedAt: Date
    var lastEventAt: Date
    var hasLiveBoundary: Bool
    var retiredTurnIDs: Set<String>
    var promptPreview: String?
    var assistantPreview: String?

    nonisolated var status: MonitorStatus {
        switch lifecycleStatus {
        case .unknown:
            // A live Stop establishes a terminal boundary but not its outcome.
            // Keep the last user-visible active state while App Server resolves
            // completed/failed/interrupted instead of flashing Unknown.
            return isTerminalStatusPending && hasLiveBoundary ? .running : .unknown
        case .completed, .error, .cancelled:
            return lifecycleStatus
        default:
            if pendingInput != nil {
                return .inputNeeded
            }
            if isApprovalPending {
                return .approvalNeeded
            }
            return .running
        }
    }
}

struct HookStateSnapshot: Sendable {
    let hasObservedEvent: Bool
    let turns: [HookTurnState]
    let didConsumeEvents: Bool
    let diagnostic: String?

    nonisolated init(
        hasObservedEvent: Bool,
        turns: [HookTurnState],
        didConsumeEvents: Bool = false,
        diagnostic: String? = nil
    ) {
        self.hasObservedEvent = hasObservedEvent
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
            // A valid event proves the installed hook was trusted at least once.
            // Runtime liveness is still checked independently against the current
            // Codex Desktop process before this marker is used.
            self.hasObservedEvent = persisted.hasObservedEvent
                ?? !(persisted.turns ?? []).isEmpty
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
        var diagnostic: String?

        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let event = try? JSONDecoder().decode(HookEvent.self, from: data) else {
                diagnostic = "忽略了一个损坏的 Hook 事件文件。"
                quarantineInvalidEvent(at: url)
                continue
            }
            if reduce(event, into: &candidateTurns) {
                validURLs.append(url)
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
        turnsByThreadID = candidateTurns
        hasObservedEvent = true
        do {
            try persist()
        } catch {
            turnsByThreadID = previousTurns
            hasObservedEvent = previouslyObservedEvent
            return snapshot(
                diagnostic: "Hook 状态写入失败；事件已保留并会重试：\(error.localizedDescription)"
            )
        }

        for url in validURLs {
            try? fileManager.removeItem(at: url)
        }
        return snapshot(didConsumeEvents: true, diagnostic: diagnostic)
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
        if clearTurns {
            turnsByThreadID.removeAll()
        }
        try? persist()
    }

    func reconcileActiveStatus(
        threadID: String,
        turnID: String,
        isInputPending: Bool,
        isApprovalPending: Bool,
        snapshotStartedAt: Date
    ) -> Bool {
        guard var state = turnsByThreadID[threadID],
              state.turnID == turnID,
              snapshotStartedAt >= state.lastEventAt,
              ![.completed, .error, .cancelled].contains(
                  state.lifecycleStatus
              ) else {
            return false
        }

        state.lifecycleStatus = .running
        state.pendingInput = isInputPending ? .appServerSnapshot : nil
        state.isApprovalPending = isApprovalPending
        state.isTerminalStatusPending = false
        state.hasLiveBoundary = true
        turnsByThreadID[threadID] = state
        return true
    }

    func resolveTerminalStatus(
        threadID: String,
        turnID: String,
        status: MonitorStatus,
        snapshotStartedAt: Date
    ) -> Bool {
        guard [.completed, .error, .cancelled].contains(status),
              var state = turnsByThreadID[threadID],
              state.turnID == turnID,
              snapshotStartedAt >= state.lastEventAt else {
            return false
        }
        guard state.status != status
                || state.pendingInput != nil
                || state.isApprovalPending else {
            return false
        }
        state.lifecycleStatus = status
        state.pendingInput = nil
        state.isApprovalPending = false
        state.isTerminalStatusPending = false
        turnsByThreadID[threadID] = state
        return true
    }

    func markTerminalStatusUnresolved(
        threadID: String,
        turnID: String,
        snapshotStartedAt: Date
    ) -> Bool {
        guard var state = turnsByThreadID[threadID],
              state.turnID == turnID,
              snapshotStartedAt >= state.lastEventAt,
              state.lifecycleStatus == .unknown,
              state.isTerminalStatusPending else {
            return false
        }

        // Unknown is appropriate only after an authoritative resolution attempt
        // failed or returned no status, not as the routine Stop intermediate state.
        state.isTerminalStatusPending = false
        turnsByThreadID[threadID] = state
        return true
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
        let isLiveEvent = receivedAt >= liveEventCutoff

        switch eventName {
        case "UserPromptSubmit":
            guard isLiveEvent else { return true }
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
                lifecycleStatus: .running,
                pendingInput: nil,
                isApprovalPending: false,
                startedAt: receivedAt,
                lastEventAt: receivedAt,
                hasLiveBoundary: true,
                retiredTurnIDs: retiredTurnIDs,
                promptPreview: event.prompt,
                assistantPreview: nil
            )
        case "PermissionRequest":
            guard isLiveEvent else { return true }
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .running,
                observedLiveEvent: true,
                turns: &turns
            ) {
                // PermissionRequest says that the approval pipeline ran. It does
                // not prove a human is still needed: automatic review can resolve
                // the request without surfacing an approval UI. The fresh App
                // Server waitingOnApproval flag is the authoritative evidence.
                $0.isApprovalPending = false
            }
        case "PreToolUse" where event.toolName == "request_user_input":
            guard let toolUseID = stableIdentifier(event.toolUseID) else {
                return false
            }
            guard isLiveEvent else { return true }
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .running,
                observedLiveEvent: true,
                turns: &turns
            ) {
                $0.pendingInput = .hook(toolUseID: toolUseID)
            }
        case "PostToolUse":
            guard isLiveEvent,
                  let toolUseID = stableIdentifier(event.toolUseID) else {
                return true
            }
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: nil,
                observedLiveEvent: true,
                turns: &turns
            ) {
                if case .hook(let pendingToolUseID)? = $0.pendingInput,
                   pendingToolUseID == toolUseID {
                    $0.pendingInput = nil
                }
            }
        case "Stop":
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .unknown,
                observedLiveEvent: isLiveEvent,
                turns: &turns
            ) {
                // Stop means the turn reached a terminal boundary, not that it
                // succeeded. App Server turn status resolves completed/failed/
                // interrupted on the next reconciliation.
                $0.lifecycleStatus = .unknown
                $0.pendingInput = nil
                $0.isApprovalPending = false
                $0.isTerminalStatusPending = isLiveEvent
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
        createWith lifecycleStatus: MonitorStatus?,
        observedLiveEvent: Bool,
        turns: inout [String: HookTurnState],
        mutation: (inout HookTurnState) -> Void
    ) {
        var state: HookTurnState
        if let current = turns[threadID] {
            guard current.turnID == turnID,
                  date >= current.lastEventAt else {
                return
            }
            state = current
        } else {
            guard let lifecycleStatus else { return }
            state = HookTurnState(
                threadID: threadID,
                turnID: turnID,
                lifecycleStatus: lifecycleStatus,
                pendingInput: nil,
                isApprovalPending: false,
                startedAt: date,
                lastEventAt: date,
                hasLiveBoundary: observedLiveEvent,
                retiredTurnIDs: [],
                promptPreview: nil,
                assistantPreview: nil
            )
        }
        mutation(&state)
        state.lastEventAt = max(state.lastEventAt, date)
        state.hasLiveBoundary = state.hasLiveBoundary || observedLiveEvent
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
