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
    /// deletes the other's event queue and preview socket, and one product's
    /// files make the other report an install footprint it does not have —
    /// which turns its integration switch off by itself.
    ///
    /// Kept short deliberately: the preview socket lives in here and a Unix
    /// domain socket path may not exceed 104 bytes.
    var agentDirectory: URL {
        supportDirectory
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent(agent.rawValue, isDirectory: true)
    }

    var script: URL {
        agentDirectory.appendingPathComponent("codex_in_notch_hook.py")
    }

    var eventsDirectory: URL {
        agentDirectory.appendingPathComponent("events", isDirectory: true)
    }

    var state: URL {
        agentDirectory.appendingPathComponent("monitor-state.json")
    }

    /// Where the helper hands preview text to a running app.
    ///
    /// See ``HookPreviewChannel``: the text goes over this socket instead of
    /// into an event file, so nothing the product promises not to persist is
    /// ever written.
    var previewSocket: URL {
        agentDirectory.appendingPathComponent("preview.sock")
    }

    /// Proof that this app, rather than something else, put a helper here.
    ///
    /// It only has to exist. ``CodexHookInstaller`` uses it to tell "our own
    /// older helper, which should be upgraded" from "a file this app never
    /// installed, which must not be silently replaced".
    var installMarker: URL {
        agentDirectory.appendingPathComponent("managed-install.json")
    }

    /// The file the marker replaced.
    ///
    /// It used to carry `showsContentPreviews` down to the helper. The helper
    /// no longer handles text at all, so there is no setting left to send; the
    /// path survives only so an existing install is still recognised as ours
    /// and the stale file gets cleaned up.
    var legacySettings: URL {
        agentDirectory.appendingPathComponent("hook-settings.json")
    }

    /// The flat layout every file used before products were namespaced.
    ///
    /// Installing rewrites the hooks configuration with the new script path, so
    /// the old registration stops matching and the old helper stops being
    /// referenced. These are the files it would otherwise leave behind — all of
    /// them paths this app has always owned exclusively.
    /// Where the helper lived before this app's files were namespaced.
    var legacyScript: URL {
        supportDirectory.appendingPathComponent("codex_in_notch_hook.py")
    }

    var legacyFlatLayout: [URL] {
        [
            "codex_in_notch_hook.py",
            "monitor-state.json",
            "preview.sock",
            "managed-install.json",
            "hook-settings.json",
            "events"
        ].map { supportDirectory.appendingPathComponent($0) }
    }

    var hooksBackup: URL {
        hooksConfiguration.appendingPathExtension("codex-in-notch-backup")
    }

    nonisolated static func live(
        agent: AgentKind = .codex,
        fileManager: FileManager = .default
    ) -> HookIntegrationPaths {
        let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("CodexInNotch", isDirectory: true)
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/CodexInNotch")

        return HookIntegrationPaths(
            supportDirectory: support,
            hooksConfiguration: fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/hooks.json"),
            agent: agent
        )
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
/// vocabulary returning `nil` means "this event is not ours", which quarantines
/// the file and raises a diagnostic. ``inert`` means "ours, and deliberately
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
    /// The session itself went away.
    case sessionEnded
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
    /// quarantines — a test pins that.
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
    /// not have it: Claude Code's hooks are delivered fire-and-forget over
    /// loopback, and a `Stop` was measured arriving ahead of its own subagent's
    /// `PermissionRequest` under the same `prompt_id` (2026-08-16). Unrelated
    /// activity arriving early would close a wait the human is still looking at.
    nonisolated var reportsApprovalDenials: Bool { get }
    /// Whether this product hands preview text over a side channel.
    ///
    /// Codex's helper does, because a hook there is a shell command and text
    /// must not go through a file. Claude Code posts its whole payload to this
    /// app, whose decoder simply has no field for the text -- so there is
    /// nothing for a channel to carry, and binding a socket to receive text
    /// this product never collects would contradict the claim.
    nonisolated var usesPreviewChannel: Bool { get }
    /// `nil` means "not recognised": quarantine rather than consume.
    nonisolated func signal(forEvent name: String, toolName: String?) -> HookSignal?
}

nonisolated struct CodexHookVocabulary: AgentHookVocabulary {
    nonisolated let agent: AgentKind = .codex
    /// A refusal produces no event whatsoever, so it has to be inferred.
    nonisolated let reportsApprovalDenials = false
    nonisolated let usesPreviewChannel = true

    nonisolated var managedDefinitions: [ManagedHookDefinition] {
        [
            ManagedHookDefinition(event: "UserPromptSubmit", matcher: nil),
            ManagedHookDefinition(event: "PermissionRequest", matcher: nil),
            // Deliberately unmatched. Registering an exact tool-name regex here
            // means a naming detail decides whether a wait is ever observed, and
            // a miss is silent. PostToolUse is already catch-all, so the
            // dispatch cost is the same order; the reducer does the filtering.
            ManagedHookDefinition(event: "PreToolUse", matcher: nil),
            ManagedHookDefinition(event: "PostToolUse", matcher: nil),
            ManagedHookDefinition(event: "Stop", matcher: nil),
            ManagedHookDefinition(event: "SessionEnd", matcher: nil)
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
            .turnEnded
        case ("SessionEnd", _):
            .sessionEnded
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
    /// `PermissionDenied` carries the refused call's `tool_use_id`, so a
    /// refusal closes exactly. This is the one place Claude Code is plainly
    /// better than Codex, and it is what lets the reducer drop an inference
    /// that unordered delivery would otherwise be able to fool.
    nonisolated let reportsApprovalDenials = true
    /// Nothing to carry: the listener's decoder has no field for prompt or
    /// answer text, so none is ever received.
    nonisolated let usesPreviewChannel = false

    /// The tool Claude Code uses to put a question to the user.
    static let inputToolName = "AskUserQuestion"

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
            ManagedHookDefinition(event: "Notification", matcher: nil),
            ManagedHookDefinition(event: "Stop", matcher: nil),
            ManagedHookDefinition(event: "StopFailure", matcher: nil)
            // SessionEnd is deliberately absent. It is the one event that is
            // not delivered in the background, so with nothing listening it
            // prints a connection-refused warning to the user's own stderr,
            // once per session (measured 2026-08-16). Nothing here needs it: a
            // session going away is equally visible through the official
            // session list and the sessions directory watcher.
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
        case ("Notification", _):
            // Registered so its types can be measured, and inert until they
            // are. Every wait this product can open is already covered by an
            // event that carries an id, and a notification carries none --
            // opening a wait nothing can close would be worse than ignoring it.
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

    /// Registered from the vocabulary rather than listed again here.
    ///
    /// The installer's list and the reducer's list used to be two hand-synced
    /// literals, which is a standing invitation to register a hook whose events
    /// are then quarantined as unrecognised — silently, since a quarantine looks
    /// like a corrupt file rather than a missing case.
    nonisolated private static let managedDefinitions =
        CodexHookVocabulary().managedDefinitions

    private let paths: HookIntegrationPaths
    private let fileManager: FileManager
    private let clock: any MonitorClock
    private let timing: MonitorTiming
    private var cachedInstallationState: (state: ManagedInstallationState, readAt: Date)?

    init(
        paths: HookIntegrationPaths = .live(),
        fileManager: FileManager = .default,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.clock = clock
        self.timing = timing
    }

    /// Drops the cached scan so the next read hits disk.
    ///
    /// Called after this app writes the configuration and whenever the user
    /// asks for a recheck -- the moments installation health can actually
    /// change by our own doing.
    func invalidateInstallationCache() {
        cachedInstallationState = nil
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
        try writeInstallMarker()
        invalidateInstallationCache()
        return true
    }

    func install() throws {
        try fileManager.createDirectory(
            at: paths.agentDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        removeLegacyFlatLayout()

        try writeCurrentHookScript()
        try writeInstallMarker()
        try mergeHooksConfiguration()
        invalidateInstallationCache()
    }

    func uninstall() throws {
        invalidateInstallationCache()
        try removeManagedHooksConfiguration()

        for url in [
            paths.script,
            paths.installMarker,
            paths.legacySettings,
            paths.state,
            paths.previewSocket
        ] {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        if fileManager.fileExists(atPath: paths.eventsDirectory.path) {
            try fileManager.removeItem(at: paths.eventsDirectory)
        }
        removeLegacyFlatLayout()
        // Only ever this product's own directory, and then the shared ones if
        // nothing else is left in them. Another product's files keep both.
        removeDirectoryIfEmpty(paths.agentDirectory)
        removeDirectoryIfEmpty(paths.agentDirectory.deletingLastPathComponent())
        removeDirectoryIfEmpty(paths.supportDirectory)
    }

    private func removeDirectoryIfEmpty(_ url: URL) {
        guard let remaining = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ), remaining.isEmpty else { return }
        try? fileManager.removeItem(at: url)
    }

    private func removeLegacyFlatLayout() {
        for url in paths.legacyFlatLayout
        where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private var command: String {
        Self.command(forScript: paths.script)
    }

    nonisolated static func command(forScript script: URL) -> String {
        "/usr/bin/python3 \"\(script.path)\""
    }

    /// Cached because it is three file reads answering a question that changes
    /// only when someone rewrites the configuration. Re-deriving it on every
    /// refresh was both wasteful and misleading: it cannot observe Codex's own
    /// per-definition trust, so a passing scan never meant the hooks would run.
    private var installationState: ManagedInstallationState {
        if let cached = cachedInstallationState,
           clock.now().timeIntervalSince(cached.readAt)
               < timing.installationRevalidationInterval {
            return cached.state
        }
        let scanned = scanInstallationState()
        cachedInstallationState = (scanned, clock.now())
        return scanned
    }

    private func scanInstallationState() -> ManagedInstallationState {
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
        // marker is written only by install(), so its presence is what
        // distinguishes "our own older helper" from a file this app never put
        // there. Recording a content hash next to the script would not add
        // tamper resistance: both live in the same directory with the same
        // ownership, so anything that can rewrite one can rewrite the other.
        //
        // The legacy settings file counts as a marker too, so an install made
        // before the marker existed upgrades instead of demanding a repair.
        return hasManagedInstallMarker ? .upgradeable : .repairRequired
    }

    private var hasManagedInstallMarker: Bool {
        fileManager.fileExists(atPath: paths.installMarker.path)
            || fileManager.fileExists(atPath: paths.legacySettings.path)
    }

    private var managedRegistrationState: ManagedRegistrationState {
        guard let data = try? Data(contentsOf: paths.hooksConfiguration),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else {
            return .absent
        }

        let configuration = managedConfiguration
        let managedOccurrenceCount = hooks.values.reduce(into: 0) { count, value in
            guard let groups = value as? [[String: Any]] else { return }
            for group in groups {
                let handlers = group["hooks"] as? [[String: Any]] ?? []
                count += handlers.filter(configuration.isManagedHandler).count
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
        fileManager.fileExists(atPath: paths.agentDirectory.path)
            || fileManager.fileExists(atPath: paths.script.path)
            || hasManagedInstallMarker
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
        guard managedConfiguration.isManagedHandler(handler),
              handler.count == 3 else {
            return false
        }
        return (handler["timeout"] as? NSNumber)?.intValue == 3
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

    /// Writes the marker, and retires the settings file it replaced.
    ///
    /// Nothing in the marker is read back -- only its presence matters -- so it
    /// carries just enough to identify itself to a human looking at the folder.
    /// It deliberately holds no privacy state: the preview switch is now an
    /// in-memory flag on ``HookPreviewChannel``, because a switch that has to
    /// be written to disk to take effect can fail open, and did.
    private func writeInstallMarker() throws {
        let data = try JSONSerialization.data(
            withJSONObject: ["managedBy": "codex-in-notch"],
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: paths.installMarker, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: paths.installMarker.path
        )

        if fileManager.fileExists(atPath: paths.legacySettings.path) {
            try? fileManager.removeItem(at: paths.legacySettings)
        }
    }

    /// The strict editor for this build's definitions.
    private var managedConfiguration: ManagedHooksConfiguration {
        .command(
            command,
            // What this app registered before its files were namespaced per
            // product. Without it an upgrade would leave that handler in place,
            // pointing at a helper the upgrade itself deleted.
            legacyCommands: [Self.command(forScript: paths.legacyScript)],
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

    private func mergeHooksConfiguration() throws {
        try configurationEditor.install()
    }

    private func removeManagedHooksConfiguration() throws {
        try configurationEditor.remove()
    }

    private static let hookScript = #"""
#!/usr/bin/python3
import json
import os
import socket
import sys
import time
import uuid

SUPPORT = os.path.dirname(os.path.abspath(__file__))
EVENTS = os.path.join(SUPPORT, "events")
PREVIEW_SOCKET = os.path.join(SUPPORT, "preview.sock")

# Codex gives this hook 3 seconds. Handing the preview over must cost a small
# fraction of that even when nothing is listening, so the whole exchange is
# bounded well below the budget and every failure is silent: a missing preview
# is a cosmetic loss, a late hook is not.
PREVIEW_TIMEOUT_SECONDS = 0.25

def send_preview(event_id, payload):
    """Hand prompt/answer text to a running app over a local socket.

    This text is deliberately never written to disk. If the app is not running
    there is nothing to hand it to and the text is dropped -- which is correct,
    because an event written while the app is down is discarded on its next
    launch anyway.
    """
    prompt = payload.get("prompt")
    assistant = payload.get("last_assistant_message")
    preview = {"event_id": event_id}
    if isinstance(prompt, str):
        preview["prompt"] = prompt[:240]
    if isinstance(assistant, str):
        preview["last_assistant_message"] = assistant[:240]
    if len(preview) == 1:
        return

    connection = None
    try:
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        connection.settimeout(PREVIEW_TIMEOUT_SECONDS)
        connection.connect(PREVIEW_SOCKET)
        connection.sendall(
            json.dumps(preview, separators=(",", ":")).encode("utf-8") + b"\n"
        )
    except Exception:
        pass
    finally:
        if connection is not None:
            try:
                connection.close()
            except Exception:
                pass

try:
    payload = json.load(sys.stdin)
    event_id = str(uuid.uuid4())
    event = {
        "event_id": event_id,
        "received_at": time.time(),
        "hook_event_name": payload.get("hook_event_name"),
        "session_id": payload.get("session_id"),
        "turn_id": payload.get("turn_id"),
        "tool_name": payload.get("tool_name"),
        "tool_use_id": payload.get("tool_use_id"),
        "permission_mode": payload.get("permission_mode"),
    }

    # Send before writing the file, never after. The file appearing is what
    # wakes the app, so the text has to already be in its hands by then or the
    # reducer would claim an id whose preview is still in flight.
    send_preview(event_id, payload)

    os.makedirs(EVENTS, mode=0o700, exist_ok=True)
    filename = "%020d-%s.json" % (time.time_ns(), event_id)
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
    /// `tool_name` as Codex reported it, used to check that a `PermissionRequest`
    /// is asking about this call and not some other one still in flight.
    let name: String?
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

    /// One lifecycle event as the helper wrote it.
    ///
    /// It deliberately carries no prompt or answer text: those arrive over
    /// ``HookPreviewChannel`` and are matched back to this by `eventID`.
    private struct HookEvent: Decodable {
        let eventID: String?
        let receivedAt: Double
        let hookEventName: String?
        let sessionID: String?
        let turnID: String?
        let toolName: String?
        let toolUseID: String?
        let permissionMode: String?

        enum CodingKeys: String, CodingKey {
            case eventID = "event_id"
            case receivedAt = "received_at"
            case hookEventName = "hook_event_name"
            case sessionID = "session_id"
            case turnID = "turn_id"
            case toolName = "tool_name"
            case toolUseID = "tool_use_id"
            case permissionMode = "permission_mode"
        }
    }

    private let paths: HookIntegrationPaths
    private let fileManager: FileManager
    private let clock: any MonitorClock
    private let timing: MonitorTiming
    /// How this repository's events are spelled. The rules below are the same
    /// for every product; only the names arriving on disk differ.
    private let vocabulary: any AgentHookVocabulary
    nonisolated private let eventsWatcher: DirectoryChangeWatcher
    nonisolated private let previewChannel: HookPreviewChannel
    private let liveEventCutoff: Date
    private var hasObservedEvent: Bool
    private var hasObservedLiveEvent: Bool
    // Codex trusts each hook definition by content hash, so rewriting one stops
    // Codex executing it until the user re-trusts -- silently, while the other
    // definitions keep firing. Every PostToolUse is preceded by a PreToolUse for
    // the same call, so closes without opens are direct evidence of that state.
    private var observedPreToolUseCount = 0
    private var observedPostToolUseCount = 0
    private var turnsByThreadID: [String: HookTurnState]

    init(
        paths: HookIntegrationPaths = .live(),
        fileManager: FileManager = .default,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard,
        liveEventCutoff: Date? = nil,
        previewChannel: HookPreviewChannel? = nil,
        vocabulary: any AgentHookVocabulary = CodexHookVocabulary()
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.clock = clock
        self.timing = timing
        self.vocabulary = vocabulary
        // The helper writes one file per lifecycle event, so watching the queue
        // directory turns a Hook into an immediate refresh instead of one that
        // waits out the poll interval.
        self.eventsWatcher = DirectoryChangeWatcher(
            directoryURL: paths.eventsDirectory,
            debounceInterval: timing.hookEventDebounceInterval
        )
        self.previewChannel = previewChannel
            ?? HookPreviewChannel(socketURL: paths.previewSocket)
        // Binding fails harmlessly before the support directory exists; the
        // installer asks again once it has created it. A product that hands
        // over no text is never bound at all.
        if vocabulary.usesPreviewChannel {
            self.previewChannel.start()
        }
        self.liveEventCutoff = liveEventCutoff ?? clock.now()

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

    nonisolated func changeEvents() -> AsyncStream<Void> {
        eventsWatcher.events()
    }

    /// Turns preview collection on or off.
    ///
    /// Deliberately `nonisolated` and synchronous. The previous design wrote
    /// the switch to a settings file the helper read, through an unheld `Task`
    /// whose write failure was swallowed -- so two quick toggles could land out
    /// of order, and one failed write left the UI showing "off" while text kept
    /// being collected. There is no write to lose any more: the caller's last
    /// call is the state, and it takes effect before that call returns.
    nonisolated func setContentPreviewsEnabled(_ isEnabled: Bool) {
        previewChannel.setAcceptsText(isEnabled)
    }

    /// Rebinds the preview socket, for use once the support directory exists.
    ///
    /// The channel is constructed at launch, which on a first run is before
    /// anything has created the directory it binds in.
    @discardableResult
    nonisolated func startPreviewChannel() -> Bool {
        // A product that hands over no text has no channel to bind.
        guard vocabulary.usesPreviewChannel else { return false }
        return previewChannel.start()
    }

    /// Attaches the event-queue watcher, for the same reason.
    ///
    /// Called the moment the installer creates the directory, so the first turn
    /// after setup is delivered immediately rather than waiting out a refresh
    /// deadline. ``consumeEvents`` also retries, as a backstop.
    @discardableResult
    nonisolated func attachEventWatcher() -> Bool {
        eventsWatcher.attachIfNeeded()
    }

    nonisolated var isEventWatcherAttached: Bool {
        eventsWatcher.isAttached
    }

    nonisolated func stopPreviewChannel() {
        previewChannel.stop()
    }

    nonisolated var previewChannelDiagnostic: String? {
        previewChannel.diagnostic
    }

    private func claimedPreview(for event: HookEvent) -> HookPreviewChannel.Preview? {
        guard let eventID = stableIdentifier(event.eventID) else { return nil }
        return previewChannel.claimPreview(forEventID: eventID)
    }

    /// The reducer's current view, without touching the event queue.
    ///
    /// `consumeEvents` deletes files and advances Turn state, so it must happen
    /// exactly once per refresh. Callers that only need the trust marker or the
    /// current Turns use this instead.
    func observedState() -> HookStateSnapshot {
        snapshot()
    }

    func consumeEvents() -> HookStateSnapshot {
        // Every refresh is a chance to pick the low-latency path back up. On a
        // first run the directory does not exist until the installer creates
        // it, so the attach attempted at launch necessarily failed; piggybacking
        // on the refresh that was happening anyway costs one `open` and needs no
        // timer of its own.
        eventsWatcher.attachIfNeeded()

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
        let now = clock.now()
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
            return now.timeIntervalSince($0.value.startedAt)
                < timing.newTurnReconciliationGrace
        }
        if turnsByThreadID.count != originalCount {
            try? persist()
        }
        return snapshot()
    }

    /// Redacts text already reduced into Turn state.
    ///
    /// The switch itself is ``setContentPreviewsEnabled``, which must have run
    /// first: this only cleans up what was collected while it was on.
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

        guard let signal = vocabulary.signal(
            forEvent: eventName,
            toolName: event.toolName
        ) else {
            // Not this product's event at all. Quarantine rather than consume,
            // so an unrecognised shape is reported instead of disappearing.
            return false
        }

        switch signal {
        case .sessionEnded, .inert:
            // Recognised and consumed. Neither needs a turn to address, so both
            // answer before the identity gate below.
            return true
        default:
            break
        }

        guard let turnID = stableIdentifier(event.turnID) else {
            return false
        }

        let receivedAt = Date(timeIntervalSince1970: event.receivedAt)
        // Only products that stay silent on a refusal need a wait closed by
        // unrelated activity; see `reportsApprovalDenials`.
        let infersDenials = !vocabulary.reportsApprovalDenials

        switch signal {
        case .turnStarted:
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
                pendingApproval: nil,
                openToolUse: nil,
                startedAt: receivedAt,
                lastEventAt: receivedAt,
                retiredTurnIDs: retiredTurnIDs,
                promptPreview: claimedPreview(for: event)?.prompt,
                assistantPreview: nil
            )
        case .approvalWaitInferred:
            mutateExactTurn(
                threadID: threadID,
                turnID: turnID,
                at: receivedAt,
                createWith: .running,
                adoptContinuationWith: .running,
                turns: &turns
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
                adoptContinuationWith: .running,
                turns: &turns
            ) {
                Self.resolveInferredApproval(
                    &$0, activityOn: toolUseID, whenInferring: infersDenials
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
                adoptContinuationWith: .running,
                turns: &turns
            ) {
                Self.resolveInferredApproval(
                    &$0, activityOn: toolUseID, whenInferring: infersDenials
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
                adoptContinuationWith: .running,
                turns: &turns
            ) {
                Self.resolveInferredApproval(
                    &$0, activityOn: toolUseID, whenInferring: infersDenials
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
                adoptContinuationWith: .running,
                turns: &turns
            ) {
                if $0.pendingInputToolUseID == toolUseID {
                    $0.pendingInputToolUseID = nil
                }
                if $0.pendingApproval?.toolUseID == toolUseID {
                    $0.pendingApproval = nil
                } else {
                    Self.resolveInferredApproval(
                        &$0, activityOn: toolUseID, whenInferring: infersDenials
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
            // Claimed before the mutation so the text is taken exactly once,
            // whether or not this event turns out to address a live turn.
            let assistantPreview = claimedPreview(for: event)?.assistantMessage
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
                $0.pendingApproval = nil
                $0.assistantPreview = assistantPreview
            }
        case .sessionEnded, .inert:
            // Both answered above, before the turn identity gate.
            break
        }
        return true
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
    nonisolated private static func resolveInferredApproval(
        _ state: inout HookTurnState,
        activityOn toolUseID: String,
        whenInferring infersDenials: Bool
    ) {
        guard infersDenials,
              let pending = state.pendingApproval,
              pending.isInferred,
              pending.toolUseID != toolUseID else {
            return
        }
        state.pendingApproval = nil
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
                    pendingApproval: nil,
                    openToolUse: nil,
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
        turns[threadID] = state
    }

    private func stableIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    /// Set once enough tool calls have closed without a single one opening.
    ///
    /// Three is past coincidence and still reached within one short turn.
    private var undeliveredPreToolUseDiagnostic: String? {
        guard observedPreToolUseCount == 0, observedPostToolUseCount >= 3 else {
            return nil
        }
        return "Codex 未执行 PreToolUse hook，等待输入与等待审批无法显示；请在 Codex 中运行 /hooks 重新信任该定义。"
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
            diagnostic: diagnostic ?? undeliveredPreToolUseDiagnostic
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
            at: paths.agentDirectory,
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
