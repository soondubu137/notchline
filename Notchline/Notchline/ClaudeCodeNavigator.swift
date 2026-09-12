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
/// **Which hosts can be asked, and how, lives in ``TerminalHostRegistry``**,
/// not here: this type owns the consent choreography, the deadline and the
/// AppleScript execution, and looks the script up by the host's bundle
/// identifier. A host with no entry takes the documented degrade — the
/// application is raised and the row says so — and adding one is an entry in
/// the registry, not a branch in this file.
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
    /// Schedules the deadline half of the race in ``run``.
    ///
    /// Injected only so a test can decide when the deadline falls. Asserting
    /// that the click comes back early by timing it needs a wall-clock budget,
    /// and a budget wide enough for a loaded machine is no longer evidence of
    /// anything -- measured failing twice in ten suite runs on 2026-08-30
    /// while builds ran alongside, at 2.7 s and 2.9 s against a 2 s budget,
    /// with the deadline itself working correctly every time.
    private let scheduleDeadline: @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void
    /// The hosts that can be asked to name a pane, and how. The built-in list
    /// in production; a test hands in its own to prove that a host is an entry
    /// and nothing else.
    private let adapters: [TerminalHostAdapter]
    /// Hosts with a consent request already out, so a second click while the
    /// prompt is on screen does not stack another one behind it.
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

    /// The script that names one tab by its terminal device, or nil for a host
    /// that is not registered and so cannot be asked.
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
    /// Raises an application that is already running, taking the user to the
    /// desktop its windows are on. `false` when there was nothing to raise.
    func activate(_ application: HostApplication) async -> Bool
}

/// Whether an application has a window on a Space the user can see right now.
///
/// Raising a host asks this first, and asks the window server nothing else: an
/// application that already has a window in front of the user is brought
/// forward by activation alone, and one that does not needs the extra step in
/// ``AppKitHostApplicationActivator``.
///
/// **This is a question about placement, not about identity.** It does not
/// decide which window the click was about, does not read a window title and
/// does not match a session to a window; the pid is one the process tree
/// already answered, and so is the yes or no. The PRD's ban on guessing a
/// navigation target from window geometry is about naming a target, and this
/// names nothing.
nonisolated protocol ActiveSpaceOccupancyReporting: Sendable {
    func hasWindowOnActiveSpace(processIdentifier: Int32) -> Bool
}

/// Reads the answer out of the window server's on-screen window list.
///
/// `.optionOnScreenOnly` *is* the question: that list holds the windows on the
/// Spaces showing right now, so an application whose windows all sit on the
/// desktop the user left is simply absent from it. `.excludeDesktopElements`
/// drops the wallpaper, as it does in ``OverlayConcealment``.
///
/// Only `kCGWindowOwnerPID`, `kCGWindowLayer` and `kCGWindowAlpha` are read.
/// None of the three is redacted without Screen Recording permission —
/// `kCGWindowName` is, and nothing here reads it.
struct WindowServerOccupancyReporter: ActiveSpaceOccupancyReporting {
    private let windows: @Sendable () -> [[String: Any]]?

    /// - Parameter windows: The on-screen list. Injected for the same reason
    ///   ``ProcessAncestryHostResolver`` injects its readers: the filtering
    ///   below is the part with rules in it, and it should be tested against a
    ///   list that is written down rather than against whatever is on screen
    ///   while the tests run.
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

        // A list that cannot be read answers "not here", which sends the click
        // down the route that works either way: being wrong in that direction
        // costs one hide the user may see, and being wrong in the other
        // direction is exactly the defect this exists to fix.
        return (listed ?? []).contains { entry in
            guard let owner = entry[kCGWindowOwnerPID as String] as? Int32,
                  owner == processIdentifier,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  layer == 0 else {
                return false
            }
            // Layer 0 and a visible alpha are what "the user can see it" means
            // here. A status item is layer 3 — Claude Desktop and Ghostty each
            // keep one — and a fully transparent window is not something
            // anybody is looking at. Windows that are closed, minimised or
            // never ordered in are already absent from an on-screen list.
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 0
            return alpha > 0
        }
    }
}

/// The part of `NSRunningApplication` that raising a host uses.
///
/// It is a protocol so that the sequence below can be tested against an
/// application that is written down, rather than against whichever applications
/// this machine happens to be running. `NSRunningApplication` satisfies it as
/// it stands.
@MainActor
protocol RaisableApplication: AnyObject {
    var processIdentifier: Int32 { get }
    /// Whether the application is hidden — the state ``hide()`` produces and
    /// coming forward clears.
    var isHidden: Bool { get }
    @discardableResult func hide() -> Bool
    @discardableResult func unhide() -> Bool
    @discardableResult func activate(options: NSApplication.ActivationOptions) -> Bool
}

extension NSRunningApplication: RaisableApplication {}

/// This app's own place in the activation order.
///
/// A raise needs it. `NSRunningApplication.activate(options:)` is a *request*,
/// and the window server declines the one an accessory application makes for a
/// host it has just hidden — while answering `true` either way. Measured
/// 2026-08-30 inside the running app, host Ghostty windowed on a desktop that
/// was not showing: `activate` answered `true`, the host came back from
/// hidden, and 400 ms later it still had no window on any desktop in view.
/// `NSWorkspace.openApplication` with `activates = true`, tried straight
/// afterwards, left it there too. The identical two calls made by a throwaway
/// process — from a shell and from `launchctl` alike — were honoured every
/// time, which is what makes this about *who is asking* rather than about the
/// calls.
///
/// It is a protocol so the sequence can be tested without a foreground to take.
@MainActor
protocol ForegroundClaiming: AnyObject {
    /// Whether this app holds the foreground right now.
    ///
    /// Taking it is not instant, and the raise has to wait for it: an
    /// activation sent while this app is still on its way to the foreground is
    /// declined exactly like one sent from the background.
    var isClaimed: Bool { get }
    /// Takes the foreground, so the raise that follows is honoured.
    func claim()
    /// Gives it back up, for a raise that never arrived.
    func relinquish()
}

@MainActor
final class AppKitForeground: ForegroundClaiming {
    var isClaimed: Bool { NSRunningApplication.current.isActive }

    func claim() {
        // `ignoringOtherApps:` rather than the cooperative `NSApp.activate()`,
        // for the reason `SettingsWindowPresenter.reveal` gives: the
        // cooperative call is itself a request this app has measured being
        // refused. Taking the foreground is what an accessory application is
        // entitled to do here — it answers a click the user has just made on
        // this app's own surface, and it holds it only for as long as it takes
        // the host to take it away.
        NSApp.activate(ignoringOtherApps: true)
    }

    func relinquish() {
        // Only reached by a click that failed. Without it the user is left
        // looking at their own desktop with an application in the foreground
        // that has no window to show them.
        NSApp.deactivate()
    }
}

/// Raises a host, and changes desktop when the host is on another one.
///
/// **Activation on its own never changes desktop, and that is why this is more
/// than one line.** Measured 2026-08-22 against an application whose windows
/// were all on another Space: `NSRunningApplication.activate()`,
/// `activate(options: .activateAllWindows)`, an `activate` Apple Event and
/// `NSWorkspace.openApplication` each handed the application the menu bar and
/// left every window exactly where it was — with the Mission Control preference
/// "When switching to an application, switch to a Space with open windows for
/// the application" both unset and on. The user was left looking at their own
/// desktop with somebody else's menu bar, which is the defect this fixes.
///
/// **Accessibility could not stand in for them, so the choice never arose.** An
/// application's `AXWindows` does not list windows on other Spaces at all
/// (measured: zero windows for Xcode with three open, and `AXMainWindow`
/// answering `kAXErrorNoValue`), so there is nothing there to raise. The PRD's
/// exclusion of Accessibility and GUI automation therefore costs this nothing.
///
/// **What does move the user is the application raising its own window**, and
/// hiding it first is the public way to ask for that: coming back, it orders
/// its own windows front and the window server follows the front window to its
/// Space. Measured the same day across three hosts built on very different
/// stacks — Xcode (AppKit), Ghostty (its own AppKit layer) and Claude Desktop
/// (Electron) — all three landed the user on the window's desktop.
///
/// **What that measurement missed is who was asking.** It was taken from a
/// throwaway process, and this app is not one: it is an accessory application
/// whose panel is a `nonactivatingPanel`, so it is never in the foreground, and
/// the window server declines the activation it sends for a host it has just
/// hidden. The decline is invisible — `activate` answers `true` regardless, the
/// host merely comes back from hidden, and the desktop stays where it was. That
/// is why the raise now takes the foreground first (``ForegroundClaiming``) and
/// then **checks**, rather than believing the answer it is given.
@MainActor
final class AppKitHostApplicationActivator: HostApplicationActivating {
    /// How many times each of the three steps is asked whether it took.
    ///
    /// At ``settle``'s default 50 ms that is a second and a half apiece. The
    /// foreground and the hide answer in a few tens of milliseconds and a raise
    /// that lands is measured answering inside 300–500 ms, all of them
    /// returning on the first yes; the ceiling is only there to bound the ones
    /// that never will.
    static let questionsPerStep = 30

    private let occupancy: any ActiveSpaceOccupancyReporting
    private let applications: @MainActor (HostApplication) -> [any RaisableApplication]
    private let foreground: any ForegroundClaiming
    private let settle: @Sendable () async -> Void

    /// - Parameters:
    ///   - occupancy: Whether the host is already where the user is looking.
    ///   - applications: The running applications a host may be raised through,
    ///     nearest answer first.
    ///   - foreground: This app's own place in the activation order.
    ///   - settle: One pause between two questions, so a test can ask them
    ///     without a clock.
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

    /// The process the ancestry named, then anything else running the same
    /// bundle.
    ///
    /// The ancestor is not always the application: iTerm2's shells hang off a
    /// helper process, and the identifier is the only way back to the window
    /// that can actually be raised.
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

    /// The foreground, then hide, then activate — and then the window server is
    /// asked whether any of it worked.
    ///
    /// **Nothing here reads `activate`'s answer.** It reports that the request
    /// went out, never that it was honoured, and this app's requests are
    /// routinely not: measured 2026-08-30 inside the running app, a host
    /// windowed on a desktop that was not showing answered `true` and stayed
    /// exactly where it was. Taking that word for it is what made a click that
    /// did nothing report itself as a raise.
    ///
    /// **The one question the window server does answer honestly** is the same
    /// one that decided whether to hide: does this pid have a visible window on
    /// a desktop showing right now. Asking it again afterwards is what
    /// separates a click that moved the user from one that only moved the menu
    /// bar.
    private func raise(_ running: any RaisableApplication) async -> Bool {
        // A host with a window in front of the user has no desktop to change:
        // activation alone brings it forward, and hiding it first would make
        // its windows blink for no reason at all. That path is measured
        // working from this app as it stands, and is left exactly as it was.
        guard !occupancy.hasWindowOnActiveSpace(
            processIdentifier: running.processIdentifier
        ) else {
            return running.activate(options: [])
        }

        // Everything below is declined without this, and declined just the
        // same if it is sent before the foreground has actually arrived — so
        // each step here waits for its own effect to be observable before the
        // next one is asked for. None of the three reports its own result.
        foreground.claim()
        _ = await holds { [foreground] in foreground.isClaimed }

        // An application the user hid themselves is left hidden: activation
        // unhides it, and unhiding it is the same thing that carries the Space.
        let hidden = !running.isHidden
        if hidden {
            // The result is deliberately ignored. `hide()` reports whether the
            // request was sent, and it answered false on every host measured
            // while `isHidden` went true immediately afterwards.
            running.hide()
            _ = await holds { running.isHidden }
        }
        running.activate(options: [])

        if await holds({ [occupancy] in
            occupancy.hasWindowOnActiveSpace(processIdentifier: running.processIdentifier)
        }) { return true }

        // A click that did not land must not also cost the user their window,
        // or leave an application with nothing to show holding the foreground.
        if hidden { running.unhide() }
        foreground.relinquish()
        return false
    }

    /// Waits for something none of these calls reports: the foreground
    /// arriving, the host going hidden, the desktop changing.
    ///
    /// Stops at the first yes, so a step that lands is not held up by the
    /// ceiling; only a click that had already failed pays it in full.
    private func holds(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<Self.questionsPerStep {
            if condition() { return true }
            await settle()
        }
        return condition()
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
