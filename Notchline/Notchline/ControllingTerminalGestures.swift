import AppKit
import Darwin
import Foundation

/// What a session's controlling terminal can say about the user being at it.
///
/// Two readings taken together rather than one, because neither is usable
/// alone -- see ``ControllingTerminalGestureReporting``.
nonisolated struct ControllingTerminalReading: Sendable, Equatable {
    /// The last moment the session read anything from its controlling terminal.
    let lastGesture: Date
    /// Whether the application hosting that terminal held the front, on a
    /// screen somebody could be looking at, when `lastGesture` was read.
    let hostIsInFrontOfTheUser: Bool
    /// Whether this session is hosted by something that could hold the front
    /// **at all**, on any future look.
    ///
    /// The distinction the reading above cannot make. "Not in front right now"
    /// is a question worth asking again in a second, and a terminal on another
    /// display answers it differently the moment the user clicks into it.
    /// "Never in front" is not a question at all: a session under `tmux`,
    /// `screen` or `ssh` has a controlling terminal, so it answers everything
    /// else here, but its ancestry runs to `launchd` without passing through an
    /// application, and no gesture at it can ever coincide with that host
    /// holding the front.
    ///
    /// Reported so a caller can tell the two apart. Treating them alike put a
    /// `tmux` session's finished row into the unread gate with a permanently
    /// false verdict, which booked a full two-product refresh once a second for
    /// the life of the session (CR-Fable-036). `ssh` and `tmux` are first-class
    /// ways to run this tool, so that was an ordinary workflow, not an edge.
    ///
    /// Answered by the ancestry alone, and so unaffected by what is in front or
    /// whether the screen is on: this is a property of how the session was
    /// started, and it does not change while it runs.
    let hostCanEverBeInFrontOfTheUser: Bool

    nonisolated init(
        lastGesture: Date,
        hostIsInFrontOfTheUser: Bool,
        hostCanEverBeInFrontOfTheUser: Bool
    ) {
        self.lastGesture = lastGesture
        self.hostIsInFrontOfTheUser = hostIsInFrontOfTheUser
        self.hostCanEverBeInFrontOfTheUser = hostCanEverBeInFrontOfTheUser
    }
}

/// When the user was last at a process's terminal.
///
/// **The terminal half of "has this been read".** Codex answers it with
/// Desktop's blue dot, and a Claude Code session hosted by Claude Desktop
/// answers it with the instant Desktop put that session on screen. A session
/// started from a terminal had no answer at all: nothing in Claude Code records
/// focus, being read, or being seen, and asking which tab of a terminal
/// emulator is on screen is exactly the guessing `AGENTS.md` §6.2 forbids.
///
/// What this reports is a narrower fact, and one the kernel already keeps: the
/// **access time of the session's controlling terminal**. No window is
/// inspected, no title is matched, and nothing is written.
///
/// **What that access time actually records, measured 2026-08-20 on a pty
/// against this kernel.** Not "the terminal handed the session something",
/// which is what this route was built believing. It records that the session
/// *attempted a read* on the device -- a `read` returning `EAGAIN` with no
/// bytes at all moves it just as far as one that returns a keystroke. Nothing
/// else does: `write`, `open`, `close`, `tcgetattr`, `ioctl` and `select` on
/// the same device all leave it alone. The distinction was invisible while the
/// only thing making the CLI read was the terminal handing it something, and
/// it stopped being invisible for the reason below.
///
/// **What makes the terminal hand it something** (measured 2026-08-19 and
/// re-measured 2026-08-20 against Ghostty and CLI `2.1.238`):
///
/// - a keystroke, including the one that starts the next Turn;
/// - that surface **gaining** the front (`ESC [ I`);
/// - that surface **losing** the front (`ESC [ O`);
/// - a terminal's reply to a query the CLI itself sent;
/// - **any movement of the pointer across that surface.** Claude Code turns on
///   any-event mouse tracking -- `ESC [ ? 1000 h`, `1002 h`, **`1003 h`**,
///   `1006 h`, written at startup and again during the session -- so the
///   terminal reports every pointer motion over the window, with no button
///   held, no keystroke, and **no focus**.
///
/// **What does not move it**, which is the half that makes it usable at all:
///
/// - anything happening in another tab, another window, or another application
///   -- a surface that is not on screen is handed nothing, measured across two
///   full focus cycles with a hidden surface stamped 0 times;
/// - the CLI writing its answer out. That is the device's *modification* time,
///   and it ticks about twice a second for as long as a Turn runs, which is why
///   the reading here is the access time and never that one;
/// - **a Turn ending.** Measured separately, because the whole route is
///   worthless if it is not true: a full Turn driven on a pty opened for the
///   purpose -- submit, answer, `Stop` hook, the `OSC 777` notification and the
///   bell the CLI sends when it starts waiting -- moved the access time exactly
///   once, at the submitting keystroke, and not once in the 110 seconds after.
///   Re-measured against `2.1.238`: still true, and the CLI sends no terminal
///   query after its first few hundred milliseconds.
///
/// **Why the gesture alone is not the answer.** Mouse reporting broke the
/// safety argument this route was built on. macOS delivers pointer motion to
/// whatever is under the pointer regardless of which application is active --
/// [ADR 0012](../../docs/adr/0012-read-state-is-answered-per-product-or-not-at-all.md)
/// says exactly that where it rejects `CGEventSource` mouse movement as
/// evidence -- so on a second display a pointer merely crossing an unfocused
/// terminal window stamped the access time and retired a finished row nobody
/// had looked at. Nothing recoverable distinguishes those bytes from a
/// keystroke afterwards: the access time is one scalar, and by the time it is
/// read the reason it moved is gone.
///
/// So the gesture is paired with a second reading taken in the same instant:
/// **is the application hosting that terminal the one in front of the user**.
/// That is a state rather than a transition, and the reversal is the same one
/// ``DesktopReadingReporting`` documents -- but here it is only ever an `AND`
/// over the transition, so it can only ever make this route *narrower* than it
/// was. A pointer crossing an unfocused window now says nothing; `ESC [ O`
/// from an application stealing the front says nothing, because by the time it
/// is sampled that application is the one holding the front; a keystroke and
/// `ESC [ I` both still count, because both require that terminal to be in
/// front at the moment they happen.
///
/// **It is still a transition first**, which is the rest of the safety
/// argument. A machine sitting idle with a terminal in front of an empty chair
/// produces no gesture at all, so it retires nothing -- the state alone is
/// never enough.
nonisolated protocol ControllingTerminalGestureReporting: Sendable {
    /// What this session's terminal says, or `nil` when it cannot be asked at
    /// all -- the process has no controlling terminal, or the device could not
    /// be stat'ed. Never "not recently". A session that answers `nil` keeps the
    /// behaviour a terminal session has always had: its finished row leaves on
    /// the next submission, when the session goes away, or when the user
    /// removes it.
    func reading(forProcessIdentifier pid: Int32) async -> ControllingTerminalReading?
}

/// The controlling terminal's access time, and who is hosting it, through
/// public BSD calls and one public workspace notification.
///
/// `sysctl(KERN_PROC_PID)` reports the process's controlling terminal as a
/// device number, `devname_r` turns that into `/dev/ttysNNN`, and `stat`
/// reports when it was last read from. The same `sysctl` reports the parent of
/// a process, which is how the terminal's application is found: walking up from
/// the session lands on the emulator that spawned the shell (measured on this
/// machine: `claude` → `-/bin/zsh` → `/usr/bin/login` → `Ghostty`). No file
/// contents are opened, no window is inspected, no title is matched, and
/// nothing is written.
///
/// **Where it degrades, and which way.** A terminal that does not implement
/// focus reporting -- or a multiplexer configured not to forward it -- leaves
/// only keystrokes, so a row waits for the user's next key instead of for them
/// coming back to the tab. A session under `tmux`, `screen` or `ssh` has no
/// ancestor that is ever the frontmost application, so its host never holds the
/// front and its row waits for the next submission instead; that case is
/// reported as ``ControllingTerminalReading/hostCanEverBeInFrontOfTheUser``
/// rather than left to look like an ordinary "not right now", because the
/// caller has to keep such a row out of the unread gate. A session with no
/// controlling terminal at all (`-p` with its output piped, or a session Claude
/// Desktop hosts) answers `nil`. All three fail towards keeping the row, which
/// is the failure this product prefers.
///
/// **The ways it can still retire a row nobody read.** The pointer moving
/// across the terminal window while that terminal *does* hold the front counts
/// as reading; that is the same bargain ``DesktopReadingReporting`` already
/// makes for a window in front of an empty chair, and it is narrower, because
/// it also needs somebody to have moved the pointer. And the front is sampled
/// about a second after the gesture, so a user who leaves a terminal in the
/// few milliseconds between `ESC [ O` and the workspace notification is read as
/// having stayed.
final class ControllingTerminalGestureReader:
    ControllingTerminalGestureReporting, @unchecked Sendable {
    /// How far up the process tree the terminal's application is looked for.
    ///
    /// Three hops on a plain Ghostty session, a few more inside an editor that
    /// hosts its own terminal. The cap is a bound on a loop that cannot cycle,
    /// not a judgement about where the application is: anything deeper answers
    /// "not in front", which keeps the row.
    nonisolated private static let maximumAncestryDepth = 16

    private let controllingTerminalPath: @Sendable (Int32) -> String?
    private let lastAccess: @Sendable (String) -> Date?
    private let parentProcessIdentifier: @Sendable (Int32) -> Int32?
    private let executablePath: @Sendable (Int32) -> String?
    private let frontmostProcessIdentifier: @Sendable () -> Int32?
    private let screenIsAvailable: @Sendable () -> Bool
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    /// - Parameters:
    ///   - controllingTerminalPath: Which device a process is attached to.
    ///   - lastAccess: When that device was last read from.
    ///   - parentProcessIdentifier: Which process spawned a process.
    ///   - executablePath: What a process is running, by absolute path. Read
    ///     only to ask whether an ancestor sits inside an application bundle,
    ///     which is what separates a host that is not in front from one that
    ///     never can be.
    ///   - frontmostProcessIdentifier: Which application holds the front, or
    ///     `nil` to track it from the workspace. All five are injected so a
    ///     test can put a session on a terminal it controls under an
    ///     application it names, rather than on whichever one the developer
    ///     happens to be typing into.
    ///   - screenIsAvailable: Whether the display is awake and the login
    ///     session unlocked and on the console. Shared with
    ///     ``DesktopReadingWatcher`` rather than restated: holding the front
    ///     through a locked screen means nothing here either, and locking is
    ///     itself a way for a surface to be sent `ESC [ O`.
    nonisolated init(
        controllingTerminalPath: @escaping @Sendable (Int32) -> String? = {
            ControllingTerminalGestureReader
                .systemControllingTerminalPath(forProcessIdentifier: $0)
        },
        lastAccess: @escaping @Sendable (String) -> Date? = {
            ControllingTerminalGestureReader.systemLastAccess(ofDevice: $0)
        },
        parentProcessIdentifier: @escaping @Sendable (Int32) -> Int32? = {
            ControllingTerminalGestureReader
                .systemParentProcessIdentifier(forProcessIdentifier: $0)
        },
        executablePath: @escaping @Sendable (Int32) -> String? = {
            ProcessAncestryHostResolver.systemExecutablePath(ofProcess: $0)
        },
        frontmostProcessIdentifier: (@Sendable () -> Int32?)? = nil,
        screenIsAvailable: @escaping @Sendable () -> Bool =
            DesktopReadingWatcher.systemScreenIsAvailable
    ) {
        self.controllingTerminalPath = controllingTerminalPath
        self.lastAccess = lastAccess
        self.parentProcessIdentifier = parentProcessIdentifier
        self.executablePath = executablePath
        self.screenIsAvailable = screenIsAvailable
        if let frontmostProcessIdentifier {
            self.frontmostProcessIdentifier = frontmostProcessIdentifier
            return
        }
        // Tracked from the notification rather than read on demand, for the
        // same reason ``DesktopReadingWatcher`` tracks it: this is asked from
        // whatever executor the refresh is on, and AppKit is not promised to
        // answer there. Read once first, because the front is a state -- a user
        // already in their terminal when this app starts never generates an
        // activation for it.
        let box = Box()
        self.frontmostProcessIdentifier = { box.value }
        box.value = NSWorkspace.shared.frontmostApplication?.processIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            box.value = (
                notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            )?.processIdentifier
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Holds the frontmost process identifier for the closure above, so the
    /// closure does not capture `self` and keep this reader alive from inside
    /// its own notification observer.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        nonisolated(unsafe) private var stored: Int32?
        var value: Int32? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }
    }

    nonisolated func reading(
        forProcessIdentifier pid: Int32
    ) async -> ControllingTerminalReading? {
        guard let path = controllingTerminalPath(pid),
              let at = lastAccess(path) else {
            return nil
        }
        let host = host(ofSession: pid)
        return ControllingTerminalReading(
            lastGesture: at,
            hostIsInFrontOfTheUser: host.isInFront,
            hostCanEverBeInFrontOfTheUser: host.canEverBeInFront
        )
    }

    /// What the session's ancestry says about the application hosting its
    /// terminal.
    nonisolated private struct Host {
        /// The frontmost process is one of this session's ancestors, on a
        /// screen somebody could be looking at.
        let isInFront: Bool
        /// Some ancestor is an application at all, so holding the front is a
        /// thing this host could do on some later look.
        let canEverBeInFront: Bool
    }

    /// Whether the application this session's terminal belongs to is the one in
    /// front of the user -- and, separately, whether it has one.
    ///
    /// **Being in front is answered by identity rather than by name:** walk the
    /// session's ancestors and see whether the frontmost application is among
    /// them. That needs no list of terminal emulators, no bundle identifier,
    /// and no judgement about which ancestor is "the application" -- a chain
    /// that reaches the frontmost process is a chain hosted by it, whatever it
    /// happens to be.
    ///
    /// **Having one is answered by the same walk**, asking whether any ancestor
    /// sits inside an `.app` bundle. Every chain ends at `launchd`, so where it
    /// ends says nothing; what separates a Ghostty session from a `tmux` one is
    /// what it passes through on the way. Measured on this machine: `claude` ->
    /// `-/bin/zsh` -> `/usr/bin/login` -> `/Applications/Ghostty.app/...`,
    /// against `claude` -> `-/bin/zsh` -> `/opt/homebrew/bin/tmux` -> `launchd`
    /// for a session under a multiplexer, whose server is daemonised and so is
    /// reparented away from whatever terminal started it. `ssh` has the same
    /// shape through `sshd`.
    ///
    /// The bundle is recognised by path alone -- ``ProcessAncestryHostResolver``
    /// already spells out that rule, and this borrows it rather than restating
    /// it. Nothing is opened and no `Info.plist` is read: the question here is
    /// only whether something in the chain *is* an application, not which.
    ///
    /// **An unreadable ancestor answers "cannot be in front"**, which keeps the
    /// row and books nothing -- the same direction every other failure in this
    /// file takes.
    nonisolated private func host(ofSession pid: Int32) -> Host {
        let front = frontmostProcessIdentifier()
        // Read once, before the walk: a front held through a sleeping display
        // or a locked screen is not a front anybody is looking at.
        let frontCounts = (front ?? 0) > 1 && screenIsAvailable()
        var isInFront = false
        var canEverBeInFront = false
        var current = pid
        for _ in 0 ..< Self.maximumAncestryDepth {
            guard let parent = parentProcessIdentifier(current), parent > 1 else {
                // `launchd` or an unreadable record. Either way there is
                // nothing above this to be the terminal's application.
                break
            }
            if frontCounts, parent == front { isInFront = true }
            if !canEverBeInFront,
               let path = executablePath(parent),
               ProcessAncestryHostResolver
                   .enclosingApplicationBundlePath(ofExecutable: path) != nil {
                canEverBeInFront = true
            }
            if isInFront, canEverBeInFront { break }
            current = parent
        }
        return Host(
            isInFront: isInFront,
            // An application unbundled enough to escape the check above can
            // still be made frontmost through `TransformProcessType`, and one
            // that *is* in front has answered the question by being there.
            canEverBeInFront: canEverBeInFront || isInFront
        )
    }

    /// The device a process is attached to, or nil when it is attached to none.
    ///
    /// `kp_eproc.e_tdev` is the controlling terminal a process inherited from
    /// its shell, so it names the *session's* terminal rather than whatever
    /// this app happens to be running under.
    ///
    /// The name is checked back against the device number it came from.
    /// `devname_r` answers out of a cache keyed by device number, so a name
    /// that has since been reused would otherwise report some other terminal's
    /// gestures as this session's. A mismatch answers nil, which keeps the row.
    ///
    /// **That check is also what makes remembering the answer safe**, and
    /// remembering it is what this asks for. `devname_r`'s own cache is built
    /// by walking `/dev` -- a `readdir` over every entry and an `lstat` on each
    /// until the device number matches -- and it is rebuilt whenever the name
    /// it is asked for is not the one it happens to be holding. Measured in
    /// Release with a listed finished row: that walk was a fifth of the app's
    /// whole steady-state cost, bought once per listed row per second. A name
    /// this app has already verified is re-verified by the same `stat` it would
    /// do anyway, so a device number reused for another terminal is caught
    /// exactly as before -- by the name no longer naming it -- and the walk is
    /// bought once per device rather than once per look.
    nonisolated static func systemControllingTerminalPath(
        forProcessIdentifier pid: Int32
    ) -> String? {
        guard let process = systemProcessRecord(forProcessIdentifier: pid) else {
            return nil
        }
        // `NODEV`, which is a cast macro and so does not reach Swift by name.
        let device = process.kp_eproc.e_tdev
        guard device != -1 else { return nil }
        if let remembered = deviceNames.path(forDevice: device),
           isCharacterDevice(remembered, numbered: device) {
            return remembered
        }
        var name = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard devname_r(device, S_IFCHR, &name, Int32(MAXPATHLEN)) != nil else {
            return nil
        }
        let resolved = String(cString: name)
        guard !resolved.isEmpty else { return nil }
        let path = "/dev/" + resolved
        guard isCharacterDevice(path, numbered: device) else { return nil }
        deviceNames.remember(path, forDevice: device)
        return path
    }

    /// Whether this path is still the character device with that number.
    nonisolated private static func isCharacterDevice(
        _ path: String,
        numbered device: dev_t
    ) -> Bool {
        var attributes = stat()
        return stat(path, &attributes) == 0
            && attributes.st_mode & S_IFMT == S_IFCHR
            && attributes.st_rdev == device
    }

    /// The device names this app has verified, keyed by device number.
    ///
    /// Process-wide because the mapping is the system's rather than any one
    /// reader's, and tiny: one entry per terminal a monitored session has ever
    /// been attached to. It is emptied rather than aged when it grows past a
    /// bound no real machine reaches, so a long-running app cannot accumulate
    /// names for ttys that are gone.
    nonisolated private static let deviceNames = DeviceNames()

    nonisolated private final class DeviceNames: @unchecked Sendable {
        /// Far more terminals than a user has open, and small enough that
        /// starting over costs one `/dev` walk per live session.
        private static let capacity = 64

        private let lock = NSLock()
        nonisolated(unsafe) private var paths: [dev_t: String] = [:]

        func path(forDevice device: dev_t) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return paths[device]
        }

        func remember(_ path: String, forDevice device: dev_t) {
            lock.lock()
            defer { lock.unlock() }
            if paths.count >= Self.capacity { paths.removeAll() }
            paths[device] = path
        }
    }

    /// The process that spawned this one, or nil when it cannot be read.
    ///
    /// The one implementation of this in the app: ``ProcessAncestryHostResolver``
    /// walks the same chain to find the terminal to raise, and used to read it
    /// with its own copy of the `sysctl` below.
    ///
    /// A process that has been reparented onto `launchd` answers 1, which the
    /// walk above treats as the end of the chain rather than as an application.
    nonisolated static func systemParentProcessIdentifier(
        forProcessIdentifier pid: Int32
    ) -> Int32? {
        guard let process = systemProcessRecord(forProcessIdentifier: pid) else {
            return nil
        }
        let parent = process.kp_eproc.e_ppid
        return parent > 0 ? parent : nil
    }

    /// When a process started, or nil when there is no such process.
    ///
    /// The second reader on this record, and here rather than beside its
    /// caller for the reason the parent walk above gives: one `sysctl` wrapper
    /// in the app, not one per question asked of it.
    ///
    /// **This is an identity, not a clock reading.** A pid on its own does not
    /// name a process for longer than that process lives — the number is
    /// reused — so ``ClaudeCodeSessionRegistry`` pairs it with this instant and
    /// treats a changed start time exactly as it treats a missing one. The
    /// value is never compared against a time the app got from anywhere else,
    /// only against an earlier reading of itself, so its epoch and its
    /// resolution do not have to agree with anything.
    nonisolated static func systemProcessStartedAt(
        forProcessIdentifier pid: Int32
    ) -> Date? {
        guard let process = systemProcessRecord(forProcessIdentifier: pid) else {
            return nil
        }
        let started = process.kp_proc.p_un.__p_starttime
        return Date(
            timeIntervalSince1970: TimeInterval(started.tv_sec)
                + TimeInterval(started.tv_usec) / 1_000_000
        )
    }

    /// One process's kernel record, or nil when it has gone.
    nonisolated private static func systemProcessRecord(
        forProcessIdentifier pid: Int32
    ) -> kinfo_proc? {
        guard pid > 0 else { return nil }
        var process = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let read = mib.withUnsafeMutableBufferPointer { buffer in
            sysctl(buffer.baseAddress, UInt32(buffer.count), &process, &size, nil, 0)
        }
        // A process that has gone answers a zero-length record rather than an
        // error, so the size is checked as well as the return value.
        guard read == 0, size >= MemoryLayout<kinfo_proc>.stride else { return nil }
        return process
    }

    /// When that device was last read from.
    nonisolated static func systemLastAccess(ofDevice path: String) -> Date? {
        var attributes = stat()
        guard stat(path, &attributes) == 0 else { return nil }
        let access = attributes.st_atimespec
        return Date(
            timeIntervalSince1970: TimeInterval(access.tv_sec)
                + TimeInterval(access.tv_nsec) / 1_000_000_000
        )
    }
}
