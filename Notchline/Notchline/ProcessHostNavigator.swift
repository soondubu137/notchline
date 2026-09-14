import AppKit
import Darwin
import Foundation
import os

/// Which process is running a session right now: a Claude Code session or an Antigravity CLI
/// conversation. Asked at click time as the PRD's re-confirmation: an ended session returns
/// `nil` and the click fails.
nonisolated protocol SessionProcessLocating: Sendable {
    func processIdentifier(forThreadID threadID: String) async -> Int32?
}

struct HostApplication: Sendable, Equatable {
    let bundleIdentifier: String
    /// The bundle's own name, so an unknown host is still named correctly.
    let displayName: String
    /// The ancestor found in the chain, usually the application itself. With session restoration,
    /// iTerm2 shells are children of an `iTermServer` helper the window server does not know as an
    /// application, so activation can fall back to the bundle identifier.
    let processIdentifier: Int32
}

enum ClaudeCodeHost: Sendable, Equatable {
    case desktop(HostApplication)
    case terminal(HostApplication)
}

nonisolated protocol SessionHostResolving: Sendable {
    func host(ofProcess pid: Int32) async -> ClaudeCodeHost?
}

struct ApplicationBundle: Sendable, Equatable {
    let identifier: String
    let displayName: String
}

/// Reads the host off the process tree.
///
/// - Not `~/.claude/sessions/<pid>.json`: its `entrypoint` agrees, but the schema is private.
/// - The walk starts at the parent: a desktop session's own executable is in a bundle too
///   (`~/Library/Application Support/Claude/claude-code/<version>/claude.app`,
///   `com.anthropic.claude-code`).
/// - Claude Desktop is searched for across the whole chain before the nearest application is
///   taken as a terminal: it reaches the CLI via `Claude.app/Contents/Helpers/disclaimer`
///   (measured 2026-08-19).
struct ProcessAncestryHostResolver: SessionHostResolving {
    /// Bounds the walk: a pid reused mid-walk can form a cycle. Real chains are four deep.
    static let maximumDepth = 32

    private let parent: @Sendable (Int32) -> Int32?
    private let executablePath: @Sendable (Int32) -> String?
    private let bundle: @Sendable (String) -> ApplicationBundle?

    /// All three are injected so the walk can be tested against a written-down tree.
    nonisolated init(
        parent: @escaping @Sendable (Int32) -> Int32? = {
            ProcessAncestryHostResolver.systemParent(ofProcess: $0)
        },
        executablePath: @escaping @Sendable (Int32) -> String? = {
            ProcessAncestryHostResolver.systemExecutablePath(ofProcess: $0)
        },
        bundle: @escaping @Sendable (String) -> ApplicationBundle? = {
            ProcessAncestryHostResolver.systemBundle(atPath: $0)
        }
    ) {
        self.parent = parent
        self.executablePath = executablePath
        self.bundle = bundle
    }

    nonisolated func host(ofProcess pid: Int32) async -> ClaudeCodeHost? {
        guard pid > 0 else { return nil }
        var applications: [HostApplication] = []
        var current = parent(pid)
        var depth = 0
        // `launchd` (pid 1) is nobody's host.
        while let candidate = current, candidate > 1, depth < Self.maximumDepth {
            if let path = executablePath(candidate),
               let bundlePath = Self.enclosingApplicationBundlePath(ofExecutable: path),
               let identity = bundle(bundlePath) {
                applications.append(
                    HostApplication(
                        bundleIdentifier: identity.identifier,
                        displayName: identity.displayName,
                        processIdentifier: candidate
                    )
                )
            }
            current = parent(candidate)
            depth += 1
        }

        if let desktop = applications.first(where: {
            $0.bundleIdentifier == ClaudeCodeMonitorService.desktopBundleIdentifier
        }) {
            return .desktop(Self.outermost(desktop, in: applications))
        }
        // The nearest application above the session: the terminal emulator, or the editor for its
        // built-in terminal.
        guard let nearest = applications.first else { return nil }
        return .terminal(Self.outermost(nearest, in: applications))
    }

    /// The highest ancestor belonging to the same application: the nearest may be a helper the
    /// window server cannot raise (measured 2026-08-19: `claude` -> 46867 disclaimer -> 24014
    /// Claude).
    nonisolated static func outermost(
        _ application: HostApplication,
        in applications: [HostApplication]
    ) -> HostApplication {
        applications.last { $0.bundleIdentifier == application.bundleIdentifier }
            ?? application
    }

    /// The outermost `.app` an executable sits inside, so a helper
    /// (`Claude.app/Contents/Helpers/disclaimer`) is attributed to the application that ships it.
    nonisolated static func enclosingApplicationBundlePath(
        ofExecutable path: String
    ) -> String? {
        var walked: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: false) {
            walked.append(String(component))
            if component.hasSuffix(".app") && component.count > 4 {
                return walked.joined(separator: "/")
            }
        }
        return nil
    }

    /// A process's parent; shared with ``ControllingTerminalGestureReader``.
    nonisolated static func systemParent(ofProcess pid: Int32) -> Int32? {
        ControllingTerminalGestureReader
            .systemParentProcessIdentifier(forProcessIdentifier: pid)
    }

    /// What a process is running, by absolute path. `proc_pidpath`, not `ps -o comm=`, whose name
    /// is truncated and not always a path.
    nonisolated static func systemExecutablePath(ofProcess pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    nonisolated static func systemBundle(atPath path: String) -> ApplicationBundle? {
        guard let bundle = Bundle(path: path),
              let identifier = bundle.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? (path as NSString).lastPathComponent
                .replacingOccurrences(of: ".app", with: "")
        return ApplicationBundle(identifier: identifier, displayName: name)
    }
}

/// Whether a terminal tab was actually brought to the front. Every failure (no scripting
/// dictionary, Automation refused, tab closed) degrades the same way: the host is raised.
enum TerminalTabFocus: Sendable, Equatable {
    case focused
    case unavailable
}

@MainActor
protocol TerminalTabFocusing: AnyObject {
    func focusTab(
        withTerminalDevice device: String,
        in application: HostApplication
    ) async -> TerminalTabFocus
}

/// Focuses the tab attached to a terminal device through the terminal's public scripting
/// dictionary.
///
/// - Per-host scripts live in ``TerminalHostRegistry``; a host with no entry degrades to
///   raising the application.
/// - The first click never focuses a tab: consent is requested in the background and the click
///   degrades immediately, since a TCC prompt mid-click would freeze the single in-flight
///   navigation.
/// - A refusal is final: `AEDeterminePermissionToAutomateTarget` then answers
///   `errAEEventNotPermitted` without prompting.
@MainActor
final class AppleEventsTerminalTabFocuser: TerminalTabFocusing {
    nonisolated private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "TerminalTabFocus"
    )

    /// Apple Events block on the target application, so they stay off the cooperative pool.
    nonisolated private static let queue = DispatchQueue(
        label: "com.yinfenglu.Notchline.terminal-focus",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// How long a scripted host may take before the click gives up; only a wedged terminal hits it.
    private let timeout: TimeInterval
    private let permission: @Sendable (String) -> AutomationPermission
    private let requestConsent: @Sendable (String) -> Void
    private let execute: @Sendable (String) -> Bool
    /// Schedules the deadline half of the race in ``run``. Injected so tests control the deadline:
    /// a wall-clock budget failed 2 in 10 runs under load (measured 2026-08-30).
    private let scheduleDeadline: @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void
    /// The hosts that can be asked to name a pane; tests hand in their own.
    private let adapters: [TerminalHostAdapter]
    /// Hosts with a consent request already out, so a second click does not stack another prompt.
    private var asking: Set<String> = []

    init(
        timeout: TimeInterval = 5,
        adapters: [TerminalHostAdapter] = TerminalHostRegistry.builtIn,
        permission: @escaping @Sendable (String) -> AutomationPermission = {
            AppleEventsTerminalTabFocuser.systemPermission(forHost: $0, askUserIfNeeded: false)
        },
        requestConsent: (@Sendable (String) -> Void)? = nil,
        execute: (@Sendable (String) -> Bool)? = nil,
        scheduleDeadline: (
            @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void
        )? = nil
    ) {
        self.timeout = timeout
        self.adapters = adapters
        self.permission = permission
        self.requestConsent = requestConsent ?? { bundleIdentifier in
            Self.queue.async {
                _ = Self.systemPermission(forHost: bundleIdentifier, askUserIfNeeded: true)
            }
        }
        self.execute = execute ?? { Self.runAppleScript($0) }
        self.scheduleDeadline = scheduleDeadline ?? { interval, fire in
            Self.queue.asyncAfter(deadline: .now() + interval, execute: fire)
        }
    }

    func focusTab(
        withTerminalDevice device: String,
        in application: HostApplication
    ) async -> TerminalTabFocus {
        guard let source = Self.script(
            forHost: application.bundleIdentifier,
            device: device,
            in: adapters
        ) else { return .unavailable }

        switch permission(application.bundleIdentifier) {
        case .granted:
            break
        case .refused:
            return .unavailable
        case .undecided:
            ask(application.bundleIdentifier)
            return .unavailable
        }

        return await run(source) ? .focused : .unavailable
    }

    private func ask(_ bundleIdentifier: String) {
        guard asking.insert(bundleIdentifier).inserted else { return }
        requestConsent(bundleIdentifier)
        let timeout = timeout
        Task { [weak self] in
            // Holds back a click storm only; released on a timer because TCC will not prompt twice anyway.
            try? await Task.sleep(for: .seconds(timeout))
            self?.asking.remove(bundleIdentifier)
        }
    }

    /// Races the script against the deadline so a wedged terminal cannot hold navigation open.
    private func run(_ source: String) async -> Bool {
        let execute = execute
        let scheduleDeadline = scheduleDeadline
        let timeout = timeout
        let answer = FirstAnswer()
        return await withCheckedContinuation { continuation in
            Self.queue.async {
                let focused = execute(source)
                if answer.take() { continuation.resume(returning: focused) }
            }
            scheduleDeadline(timeout) {
                if answer.take() {
                    Self.log.error("terminal tab focus outlived its deadline")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// The script that names one tab by its terminal device, or nil for an unregistered host.
    nonisolated static func script(
        forHost bundleIdentifier: String,
        device: String,
        in adapters: [TerminalHostAdapter] = TerminalHostRegistry.builtIn
    ) -> String? {
        guard let adapter = TerminalHostRegistry.adapter(for: bundleIdentifier, in: adapters) else {
            return nil
        }
        switch adapter.paneLocator {
        case let .appleScript(selecting):
            return selecting(appleScriptLiteral(device))
        }
    }

    /// A device path as an AppleScript string. `devname_r` yields only `/dev/ttysNNN`, but the value
    /// is escaped anyway because the script is assembled by concatenation.
    nonisolated static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    nonisolated static func runAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var failure: NSDictionary?
        let result = script.executeAndReturnError(&failure)
        if let failure {
            // Includes a refusal after the permission check; degrades like any failure (host raised).
            let code = failure[NSAppleScript.errorNumber] as? Int ?? 0
            log.error("terminal tab focus rejected: \(code)")
            return false
        }
        return result.booleanValue
    }

    nonisolated static func systemPermission(
        forHost bundleIdentifier: String,
        askUserIfNeeded: Bool
    ) -> AutomationPermission {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        let status = AEDeterminePermissionToAutomateTarget(
            target.aeDesc,
            typeWildCard,
            typeWildCard,
            askUserIfNeeded
        )
        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .undecided
        default:
            // `errAEEventNotPermitted` and everything else: the tab cannot be named; do not ask again.
            return .refused
        }
    }
}

enum AutomationPermission: Sendable, Equatable {
    case granted
    /// Not asked yet; asking puts the system prompt on screen.
    case undecided
    /// Refused, or unanswerable. Both mean "do not ask again".
    case refused
}

/// Lets exactly one of two racers resume a continuation.
private final class FirstAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false

    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if taken { return false }
        taken = true
        return true
    }
}

@MainActor
protocol HostApplicationActivating: AnyObject {
    /// Raises an already-running application, switching to the desktop its windows are on. `false`
    /// when there was nothing to raise.
    func activate(_ application: HostApplication) async -> Bool
}

/// Whether an application has a window on a Space the user can see right now; one that does is
/// raised by activation alone.
///
/// Placement only: it names no target, so it is outside the PRD's ban on guessing a navigation
/// target from window geometry.
nonisolated protocol ActiveSpaceOccupancyReporting: Sendable {
    func hasWindowOnActiveSpace(processIdentifier: Int32) -> Bool
}

/// Reads the window server's on-screen list (`.optionOnScreenOnly`, `.excludeDesktopElements`).
/// Only `kCGWindowOwnerPID`, `kCGWindowLayer` and `kCGWindowAlpha` are read; none is redacted
/// without Screen Recording permission.
struct WindowServerOccupancyReporter: ActiveSpaceOccupancyReporting {
    private let windows: @Sendable () -> [[String: Any]]?

    /// - Parameter windows: The on-screen list, injected so the filtering can be tested.
    nonisolated init(
        windows: @escaping @Sendable () -> [[String: Any]]? = {
            CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        }
    ) {
        self.windows = windows
    }

    nonisolated func hasWindowOnActiveSpace(processIdentifier: Int32) -> Bool {
        let listed = windows()

        // An unreadable list answers "not here": the wrong answer that way costs a visible hide.
        return (listed ?? []).contains { entry in
            guard let owner = entry[kCGWindowOwnerPID as String] as? Int32,
                  owner == processIdentifier,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  layer == 0 else {
                return false
            }
            // Layer 0 with visible alpha. Status items (Claude Desktop, Ghostty) are layer 3.
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 0
            return alpha > 0
        }
    }
}

/// The part of `NSRunningApplication` that raising a host uses; a protocol for tests.
@MainActor
protocol RaisableApplication: AnyObject {
    var processIdentifier: Int32 { get }
    /// Whether the application is hidden: set by ``hide()``, cleared by coming forward.
    var isHidden: Bool { get }
    @discardableResult func hide() -> Bool
    @discardableResult func unhide() -> Bool
    @discardableResult func activate(options: NSApplication.ActivationOptions) -> Bool
}

extension NSRunningApplication: RaisableApplication {}

/// This app's own place in the activation order.
///
/// An accessory app's `activate(options:)` for a host it just hid is declined while answering
/// `true` (measured 2026-08-30 with Ghostty on another desktop; `NSWorkspace.openApplication`
/// failed too). The same calls from a throwaway process worked: it is about who asks.
@MainActor
protocol ForegroundClaiming: AnyObject {
    /// Whether this app holds the foreground. An activation sent before it arrives is declined.
    var isClaimed: Bool { get }
    func claim()
    /// Gives the foreground back, for a raise that never arrived.
    func relinquish()
}

@MainActor
final class AppKitForeground: ForegroundClaiming {
    var isClaimed: Bool { NSRunningApplication.current.isActive }

    func claim() {
        // `ignoringOtherApps:`: the cooperative `NSApp.activate()` has been measured refused (see
        // `SettingsWindowPresenter.reveal`).
        NSApp.activate(ignoringOtherApps: true)
    }

    func relinquish() {
        // Only after a failed click: otherwise a windowless app keeps the foreground.
        NSApp.deactivate()
    }
}

/// Raises a host, and changes desktop when the host is on another one.
///
/// - Activation alone never changes Space (measured 2026-08-22): `activate()`,
///   `.activateAllWindows`, an `activate` Apple Event and `NSWorkspace.openApplication` all
///   only moved the menu bar, whatever the Mission Control setting.
/// - Accessibility cannot help: `AXWindows` omits windows on other Spaces.
/// - Hiding then activating makes the app order its own windows front, and the window server
///   follows to their Space (Xcode, Ghostty, Claude Desktop).
/// - From this accessory app the window server declines that activation while `activate`
///   answers `true`, so the raise takes the foreground first (``ForegroundClaiming``) and then
///   checks the result.
@MainActor
final class AppKitHostApplicationActivator: HostApplicationActivating {
    /// How many times each of the three steps is asked whether it took (1.5 s each at ``settle``'s
    /// 50 ms). A raise that lands answers in 300–500 ms; the ceiling bounds failures.
    static let questionsPerStep = 30

    private let occupancy: any ActiveSpaceOccupancyReporting
    private let applications: @MainActor (HostApplication) -> [any RaisableApplication]
    private let foreground: any ForegroundClaiming
    private let settle: @Sendable () async -> Void

    /// - Parameters:
    ///   - occupancy: Whether the host is already where the user is looking.
    ///   - applications: Running applications a host may be raised through, nearest first.
    ///   - foreground: This app's own place in the activation order.
    ///   - settle: One pause between two questions, injectable for tests.
    init(
        occupancy: any ActiveSpaceOccupancyReporting = WindowServerOccupancyReporter(),
        applications: (@MainActor (HostApplication) -> [any RaisableApplication])? = nil,
        foreground: (any ForegroundClaiming)? = nil,
        settle: (@Sendable () async -> Void)? = nil
    ) {
        self.occupancy = occupancy
        self.applications = applications ?? { AppKitHostApplicationActivator.systemApplications(for: $0) }
        self.foreground = foreground ?? AppKitForeground()
        self.settle = settle ?? { try? await Task.sleep(for: .milliseconds(50)) }
    }

    func activate(_ application: HostApplication) async -> Bool {
        for running in applications(application) {
            if await raise(running) { return true }
        }
        return false
    }

    /// The process the ancestry named, then anything else running the same bundle (iTerm2's shells
    /// hang off a helper process).
    nonisolated static func systemApplications(
        for application: HostApplication
    ) -> [any RaisableApplication] {
        let named = NSRunningApplication(
            processIdentifier: application.processIdentifier
        ).flatMap { $0.bundleIdentifier == application.bundleIdentifier ? $0 : nil }

        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == application.bundleIdentifier
                && $0.processIdentifier != named?.processIdentifier
        }
        return ([named].compactMap { $0 } + others)
    }

    /// Foreground, hide, activate, then ask the window server whether it worked. `activate`'s
    /// answer is never read: it reported `true` for a raise that did not happen (measured
    /// 2026-08-30).
    private func raise(_ running: any RaisableApplication) async -> Bool {
        // Already on a visible Space: activation alone works, and hiding would blink its windows.
        guard !occupancy.hasWindowOnActiveSpace(
            processIdentifier: running.processIdentifier
        ) else {
            return running.activate(options: [])
        }

        // Each step waits for its effect to be observable; a step sent early is declined, and none
        // reports its own result.
        foreground.claim()
        _ = await holds { [foreground] in foreground.isClaimed }

        // An application the user hid is left hidden; unhiding it is what carries the Space.
        let hidden = !running.isHidden
        if hidden {
            // Result ignored: `hide()` answered false on every host measured while `isHidden` went true.
            running.hide()
            _ = await holds { running.isHidden }
        }
        running.activate(options: [])

        if await holds({ [occupancy] in
            occupancy.hasWindowOnActiveSpace(processIdentifier: running.processIdentifier)
        }) { return true }

        // A failed click must not cost the user their window or leave a windowless foreground.
        if hidden { running.unhide() }
        foreground.relinquish()
        return false
    }

    /// Polls a condition none of these calls reports, stopping at the first yes.
    private func holds(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<Self.questionsPerStep {
            if condition() { return true }
            await settle()
        }
        return condition()
    }
}

enum ProcessHostNavigationError: LocalizedError, Equatable {
    case sessionGone
    case hostUnknown
    case activationFailed(String)

    var errorDescription: String? {
        switch self {
        case .sessionGone:
            "That session has ended and can no longer be opened."
        case .hostUnknown:
            "Could not tell which app that session is running in."
        case let .activationFailed(host):
            "Could not raise \(host)."
        }
    }
}

/// Takes a process-hosted row (Claude Code, Antigravity CLI) back to whatever is showing it.
///
/// Raises a host; it cannot reopen a session, since no supported interface focuses an existing
/// Claude Code session. ADR 0004's exact-navigation gate is Codex-only; ``NavigationOutcome``
/// reports the degrade. Desktop sessions raise Claude Desktop; terminal sessions select the tab
/// where the terminal allows, else raise the application.
@MainActor
final class ProcessHostNavigator: AgentNavigating {
    static let desktopDisplayName = "Claude Desktop"

    private let sessions: any SessionProcessLocating
    private let hosts: any SessionHostResolving
    private let activator: any HostApplicationActivating
    private let tabs: any TerminalTabFocusing
    private let controllingTerminalPath: @Sendable (Int32) -> String?

    init(
        sessions: any SessionProcessLocating,
        hosts: any SessionHostResolving = ProcessAncestryHostResolver(),
        activator: (any HostApplicationActivating)? = nil,
        tabs: (any TerminalTabFocusing)? = nil,
        controllingTerminalPath: @escaping @Sendable (Int32) -> String? = {
            ControllingTerminalGestureReader
                .systemControllingTerminalPath(forProcessIdentifier: $0)
        }
    ) {
        self.sessions = sessions
        self.hosts = hosts
        self.activator = activator ?? AppKitHostApplicationActivator()
        self.tabs = tabs ?? AppleEventsTerminalTabFocuser()
        self.controllingTerminalPath = controllingTerminalPath
    }

    @discardableResult
    func open(_ session: MonitoredSession) async throws -> NavigationOutcome {
        guard let pid = await sessions.processIdentifier(
            forThreadID: session.threadID
        ) else {
            throw ProcessHostNavigationError.sessionGone
        }
        guard let host = await hosts.host(ofProcess: pid) else {
            // The process went away, or nothing above it is an application (launch agent, script).
            throw ProcessHostNavigationError.hostUnknown
        }

        switch host {
        case let .desktop(application):
            guard await activator.activate(application) else {
                throw ProcessHostNavigationError.activationFailed(Self.desktopDisplayName)
            }
            return .raisedApplication(host: Self.desktopDisplayName)
        case let .terminal(application):
            if let device = controllingTerminalPath(pid),
               await tabs.focusTab(withTerminalDevice: device, in: application) == .focused {
                return .focusedTerminal(host: application.displayName)
            }
            guard await activator.activate(application) else {
                throw ProcessHostNavigationError.activationFailed(application.displayName)
            }
            return .raisedApplication(host: application.displayName)
        }
    }
}
