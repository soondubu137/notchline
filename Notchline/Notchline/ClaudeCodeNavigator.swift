import AppKit
import Darwin
import Foundation
import os

/// Which process is running a Claude Code session right now.
///
/// Navigation needs this and the row cannot carry it: ``MonitoredSession``
/// names a thread and a turn, and a Claude Code session's host is a *process*.
/// It is asked at click time rather than stored on the row, which is also the
/// re-confirmation the PRD requires before a click: a session that has ended is
/// no longer listed, so the answer is `nil` and the click fails rather than
/// raising a window that has nothing to do with the row.
nonisolated protocol ClaudeCodeSessionLocating: Sendable {
    func processIdentifier(forThreadID threadID: String) async -> Int32?
}

/// An application that is already running, and that this app may raise.
struct HostApplication: Sendable, Equatable {
    let bundleIdentifier: String
    /// What the sentence after the click calls it — the bundle's own name, so
    /// a host this app has never heard of still gets named correctly.
    let displayName: String
    /// The ancestor that was found in the chain.
    ///
    /// Usually the application process itself. iTerm2 is the exception worth
    /// naming: with session restoration on, shells are children of an
    /// `iTermServer` helper that the window server does not know as an
    /// application at all. The bundle identifier is carried alongside so the
    /// activation can fall back to it.
    let processIdentifier: Int32
}

/// What is showing a Claude Code session.
enum ClaudeCodeHost: Sendable, Equatable {
    /// The session belongs to the Claude Code desktop app.
    case desktop(HostApplication)
    /// The session was started in a terminal, and this is that terminal.
    case terminal(HostApplication)
}

nonisolated protocol ClaudeCodeHostResolving: Sendable {
    func host(ofProcess pid: Int32) async -> ClaudeCodeHost?
}

/// One application bundle, as far as anything here cares about it.
struct ApplicationBundle: Sendable, Equatable {
    let identifier: String
    let displayName: String
}

/// Reads the host off the process tree, which is the only place it is written.
///
/// **Why the tree and not `~/.claude/sessions/<pid>.json`.** That file does
/// carry `entrypoint`, and it says `claude-desktop` or `cli` exactly as this
/// walk concludes. It is also a private file with an unpublished schema, and
/// nothing here needs it: the ancestry is a public kernel fact, reported by
/// calls this app already uses for the terminal read route. The file stays
/// useful as corroboration when this ever disagrees, and as nothing else.
///
/// **The walk starts at the parent, deliberately.** A desktop-hosted session's
/// own executable lives inside an application bundle too — measured at
/// `~/Library/Application Support/Claude/claude-code/<version>/claude.app`,
/// bundle identifier `com.anthropic.claude-code` — so a scan that included the
/// session process would find an "application" for every desktop session and
/// mistake it for the host.
///
/// **Claude Desktop wins over position.** The whole chain is searched for it
/// before the nearest application is taken as a terminal, because the desktop
/// app reaches the CLI through a helper of its own
/// (`Claude.app/Contents/Helpers/disclaimer`, measured 2026-08-19) and a future
/// version could put something else in between.
struct ProcessAncestryHostResolver: ClaudeCodeHostResolving {
    /// How far up to walk before giving up.
    ///
    /// A cycle cannot happen in a process tree, but a pid that is reused
    /// mid-walk can produce one, and a walk with no bound would then never
    /// return. Real chains measured here are four deep.
    static let maximumDepth = 32

    private let parent: @Sendable (Int32) -> Int32?
    private let executablePath: @Sendable (Int32) -> String?
    private let bundle: @Sendable (String) -> ApplicationBundle?

    /// - Parameters:
    ///   - parent: A process's parent, or nil when it has gone.
    ///   - executablePath: What a process is running.
    ///   - bundle: The identity of an application bundle at a path. All three
    ///     are injected so the walk can be tested against a tree that is
    ///     written down rather than against whatever this machine happens to be
    ///     running.
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
        // `launchd` is nobody's host, so pid 1 ends the walk rather than
        // entering it.
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
        // The nearest application above the session. For a terminal session
        // that is the emulator; for a session started from an editor's built-in
        // terminal it is the editor, which is the right thing to raise.
        guard let nearest = applications.first else { return nil }
        return .terminal(Self.outermost(nearest, in: applications))
    }

    /// The highest ancestor belonging to the same application.
    ///
    /// An application can appear in the chain more than once, and the copy
    /// nearest the session is the wrong one to name: a desktop-hosted session's
    /// closest ancestor is `Claude.app/Contents/Helpers/disclaimer` (measured
    /// 2026-08-19: `claude` -> 46867 disclaimer -> 24014 Claude), and a helper
    /// is not a process the window server knows as an application. Walking to
    /// the top of the run finds the application process itself, which is the
    /// one that can be raised without going through Launch Services.
    nonisolated static func outermost(
        _ application: HostApplication,
        in applications: [HostApplication]
    ) -> HostApplication {
        applications.last { $0.bundleIdentifier == application.bundleIdentifier }
            ?? application
    }

    /// The outermost `.app` an executable sits inside.
    ///
    /// Outermost rather than innermost so a helper is attributed to the
    /// application that ships it: `Claude.app/Contents/Frameworks/Claude
    /// Helper.app/...` is Claude Desktop, not a separate application, and
    /// `Claude.app/Contents/Helpers/disclaimer` is the one that actually
    /// appears in a desktop-hosted session's ancestry.
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

    /// A process's parent.
    ///
    /// Read by ``ControllingTerminalGestureReader``, which needs the same walk
    /// to answer whether a session's terminal is the application in front of
    /// the user. It used to be a second copy of that `sysctl` here.
    nonisolated static func systemParent(ofProcess pid: Int32) -> Int32? {
        ControllingTerminalGestureReader
            .systemParentProcessIdentifier(forProcessIdentifier: pid)
    }

    /// What a process is running, by absolute path.
    ///
    /// `proc_pidpath` rather than `ps -o comm=`: the accounting name `ps`
    /// prints is truncated and is not always a path, and this walk has to
    /// recognise an application by the bundle it sits in.
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

/// Whether a terminal tab was actually brought to the front.
///
/// Two values and not three, because every way of failing leads to the same
/// place: the host gets raised instead, and the sentence the user reads says
/// so. A host with no scripting dictionary, a user who refused Automation and
/// a terminal that has already closed the tab are not distinguished here.
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

/// Focuses the tab attached to a terminal device, through the terminal's own
/// public scripting dictionary.
///
/// **Only two hosts are scripted, and by measurement rather than by choice.**
/// A tab can only be named if the terminal publishes the tty its shell is
/// attached to. Terminal.app does (`tty` on `tab`) and iTerm2 does (`tty` on
/// `session`). Ghostty publishes a full dictionary — windows, tabs, terminal
/// surfaces, `select tab`, `activate window` — and **no tty anywhere in it**
/// (`Ghostty.sdef`, 1.3.1, checked 2026-08-19); the only identifiers it exposes
/// are the title and the working directory, and matching on either is the
/// guessing the PRD forbids. kitty, WezTerm and Alacritty ship no scripting
/// dictionary at all. All of them therefore take the documented degrade: the
/// application is raised and the row says so.
///
/// **The first click on a terminal row never focuses a tab, on purpose.**
/// Automation consent is asked for in the background and the click degrades
/// immediately, rather than the click blocking on a human. The alternative —
/// running the script and letting TCC put its prompt up mid-click — freezes
/// navigation for as long as the prompt sits unanswered, and the overlay has a
/// single navigation in flight at a time. The cost is one imprecise click, and
/// the sentence it produces is true.
///
/// **A refusal is final and silent.** Once TCC holds a denial,
/// `AEDeterminePermissionToAutomateTarget` answers `errAEEventNotPermitted`
/// without prompting, so nothing is ever asked again and nothing is ever shown
/// to the user except the ordinary "raised the application" sentence.
@MainActor
final class AppleEventsTerminalTabFocuser: TerminalTabFocusing {
    nonisolated private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "TerminalTabFocus"
    )

    /// Apple Events block on the application being talked to, so they do not
    /// belong on a cooperative thread.
    nonisolated private static let queue = DispatchQueue(
        label: "com.yinfenglu.Notchline.terminal-focus",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// How long a scripted host may take before the click gives up on it.
    ///
    /// Only reached by a wedged terminal: consent is already granted by the
    /// time a script runs, so there is no human in this wait.
    private let timeout: TimeInterval
    private let permission: @Sendable (String) -> AutomationPermission
    private let requestConsent: @Sendable (String) -> Void
    private let execute: @Sendable (String) -> Bool
    /// Hosts with a consent request already out, so a second click while the
    /// prompt is on screen does not stack another one behind it.
    private var asking: Set<String> = []

    init(
        timeout: TimeInterval = 5,
        permission: @escaping @Sendable (String) -> AutomationPermission = {
            AppleEventsTerminalTabFocuser.systemPermission(forHost: $0, askUserIfNeeded: false)
        },
        requestConsent: (@Sendable (String) -> Void)? = nil,
        execute: (@Sendable (String) -> Bool)? = nil
    ) {
        self.timeout = timeout
        self.permission = permission
        self.requestConsent = requestConsent ?? { bundleIdentifier in
            Self.queue.async {
                _ = Self.systemPermission(forHost: bundleIdentifier, askUserIfNeeded: true)
            }
        }
        self.execute = execute ?? { Self.runAppleScript($0) }
    }

    func focusTab(
        withTerminalDevice device: String,
        in application: HostApplication
    ) async -> TerminalTabFocus {
        guard let source = Self.script(
            forHost: application.bundleIdentifier,
            device: device
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
        // Sent here rather than from inside the task below: the request is
        // already fire-and-forget -- it goes out on a queue and blocks on the
        // user there -- and deferring it to whenever a task happens to be
        // scheduled only makes the moment it leaves unobservable.
        requestConsent(bundleIdentifier)
        let timeout = timeout
        Task { [weak self] in
            // The hold exists to stop a click storm stacking a second prompt
            // behind the first, and nothing else. Released on a timer rather
            // than on the answer, because the answer arrives on the queue the
            // request went out on and TCC will not prompt twice anyway.
            try? await Task.sleep(for: .seconds(timeout))
            self?.asking.remove(bundleIdentifier)
        }
    }

    /// Races the script against the deadline, so a wedged terminal cannot hold
    /// the one in-flight navigation open for good.
    private func run(_ source: String) async -> Bool {
        let execute = execute
        let timeout = timeout
        let answer = FirstAnswer()
        return await withCheckedContinuation { continuation in
            Self.queue.async {
                let focused = execute(source)
                if answer.take() { continuation.resume(returning: focused) }
            }
            Self.queue.asyncAfter(deadline: .now() + timeout) {
                if answer.take() {
                    Self.log.error("terminal tab focus outlived its deadline")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// The script that names one tab by its terminal device, or nil for a host
    /// that cannot be asked.
    nonisolated static func script(forHost bundleIdentifier: String, device: String) -> String? {
        let literal = appleScriptLiteral(device)
        switch bundleIdentifier {
        case "com.apple.Terminal":
            return """
            tell application id "com.apple.Terminal"
                repeat with theWindow in windows
                    repeat with theTab in tabs of theWindow
                        if tty of theTab is \(literal) then
                            set selected of theTab to true
                            set frontmost of theWindow to true
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """
        case "com.googlecode.iterm2":
            return """
            tell application id "com.googlecode.iterm2"
                repeat with theWindow in windows
                    repeat with theTab in tabs of theWindow
                        repeat with theSession in sessions of theTab
                            if tty of theSession is \(literal) then
                                select theWindow
                                select theTab
                                select theSession
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
            """
        default:
            return nil
        }
    }

    /// A device path as an AppleScript string.
    ///
    /// `devname_r` only ever produces `/dev/ttysNNN`, so nothing here needs
    /// escaping today. It is escaped anyway: the value reaches this from the
    /// kernel through two layers, and a script assembled by concatenation is
    /// the wrong place to rely on a shape holding.
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
            // Includes a refusal that landed between the permission check and
            // this call. It degrades like every other failure here: the caller
            // raises the application instead, and the user is told that is what
            // happened rather than being shown an error.
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
            // `errAEEventNotPermitted` and everything else — a host that is not
            // running, a target that cannot be addressed. All of them mean the
            // tab cannot be named, and none of them are worth asking again.
            return .refused
        }
    }
}

/// Whether this app may drive another application through Apple Events.
enum AutomationPermission: Sendable, Equatable {
    case granted
    /// The user has not been asked yet. Asking is what puts the system prompt
    /// on screen.
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
    /// Raises an application that is already running. `false` when there was
    /// nothing to raise.
    func activate(_ application: HostApplication) async -> Bool
}

@MainActor
final class AppKitHostApplicationActivator: HostApplicationActivating {
    func activate(_ application: HostApplication) async -> Bool {
        if let running = NSRunningApplication(
            processIdentifier: application.processIdentifier
        ), running.bundleIdentifier == application.bundleIdentifier,
           await raise(running) {
            return true
        }
        // The ancestor is not always the application: iTerm2's shells hang off
        // a helper process, and the identifier is the only way back to the
        // window that can actually be raised.
        for running in NSWorkspace.shared.runningApplications
        where running.bundleIdentifier == application.bundleIdentifier {
            if await raise(running) { return true }
        }
        return false
    }

    /// Cooperative activation first, Launch Services second.
    ///
    /// `activate()` is the cheap one and it can be declined — an app that is
    /// not the current front app has a say in whether it yields. Opening the
    /// bundle is the same route ``AppKitCodexWorkspace`` uses and does not
    /// launch a second copy of an application that is already running.
    private func raise(_ running: NSRunningApplication) async -> Bool {
        if running.activate() { return true }
        guard let bundleURL = running.bundleURL else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(
                at: bundleURL,
                configuration: configuration
            )
            return true
        } catch {
            return false
        }
    }
}

enum ClaudeCodeNavigationError: LocalizedError, Equatable {
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

/// Takes a Claude Code row back to whatever is showing it.
///
/// **It raises a host; it does not reopen a session.** No supported interface
/// focuses a Claude Code session that already exists — the official deep links
/// only ever create a new one — so ADR 0004's exact-navigation gate is a Codex
/// requirement and this is the declared degrade, not a fallback dressed up as
/// success. The row draws no mark for the difference; ``NavigationOutcome`` is
/// where it gets said.
///
/// Two hosts, and the process tree is what tells them apart. A desktop-hosted
/// session gets Claude Desktop raised. A terminal session gets its tab
/// selected where the terminal publishes enough to name it, and its application
/// raised where it does not.
@MainActor
final class ClaudeCodeNavigator: AgentNavigating {
    static let desktopDisplayName = "Claude Desktop"

    private let sessions: any ClaudeCodeSessionLocating
    private let hosts: any ClaudeCodeHostResolving
    private let activator: any HostApplicationActivating
    private let tabs: any TerminalTabFocusing
    private let controllingTerminalPath: @Sendable (Int32) -> String?

    init(
        sessions: any ClaudeCodeSessionLocating,
        hosts: any ClaudeCodeHostResolving = ProcessAncestryHostResolver(),
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
            throw ClaudeCodeNavigationError.sessionGone
        }
        guard let host = await hosts.host(ofProcess: pid) else {
            // Either the process went away between the two questions, or it has
            // no application above it at all — a session started by a launch
            // agent or a script has nothing to raise. Neither is worth
            // guessing about.
            throw ClaudeCodeNavigationError.hostUnknown
        }

        switch host {
        case let .desktop(application):
            guard await activator.activate(application) else {
                throw ClaudeCodeNavigationError.activationFailed(Self.desktopDisplayName)
            }
            return .raisedApplication(host: Self.desktopDisplayName)
        case let .terminal(application):
            if let device = controllingTerminalPath(pid),
               await tabs.focusTab(withTerminalDevice: device, in: application) == .focused {
                return .focusedTerminal(host: application.displayName)
            }
            guard await activator.activate(application) else {
                throw ClaudeCodeNavigationError.activationFailed(application.displayName)
            }
            return .raisedApplication(host: application.displayName)
        }
    }
}
