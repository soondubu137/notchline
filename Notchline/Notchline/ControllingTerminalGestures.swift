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

    nonisolated init(lastGesture: Date, hostIsInFrontOfTheUser: Bool) {
        self.lastGesture = lastGesture
        self.hostIsInFrontOfTheUser = hostIsInFrontOfTheUser
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
/// front and its row waits for the next submission instead. A session with no
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
    private let frontmostProcessIdentifier: @Sendable () -> Int32?
    private let screenIsAvailable: @Sendable () -> Bool
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    /// - Parameters:
    ///   - controllingTerminalPath: Which device a process is attached to.
    ///   - lastAccess: When that device was last read from.
    ///   - parentProcessIdentifier: Which process spawned a process.
    ///   - frontmostProcessIdentifier: Which application holds the front, or
    ///     `nil` to track it from the workspace. All four are injected so a
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
        frontmostProcessIdentifier: (@Sendable () -> Int32?)? = nil,
        screenIsAvailable: @escaping @Sendable () -> Bool =
            DesktopReadingWatcher.systemScreenIsAvailable
    ) {
        self.controllingTerminalPath = controllingTerminalPath
        self.lastAccess = lastAccess
        self.parentProcessIdentifier = parentProcessIdentifier
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
        return ControllingTerminalReading(
            lastGesture: at,
            hostIsInFrontOfTheUser: hostIsInFrontOfTheUser(ofSession: pid)
        )
    }

    /// Whether the application this session's terminal belongs to is the one in
    /// front of the user.
    ///
    /// Answered by identity rather than by name: walk the session's ancestors
    /// and see whether the frontmost application is among them. That needs no
    /// list of terminal emulators, no bundle identifier, and no judgement about
    /// which ancestor is "the application" -- a chain that reaches the frontmost
    /// process is a chain hosted by it, whatever it happens to be.
    nonisolated private func hostIsInFrontOfTheUser(ofSession pid: Int32) -> Bool {
        guard let front = frontmostProcessIdentifier(), front > 1,
              screenIsAvailable() else {
            return false
        }
        var current = pid
        for _ in 0 ..< Self.maximumAncestryDepth {
            guard let parent = parentProcessIdentifier(current), parent > 1 else {
                // `launchd` or an unreadable record. Either way nothing above
                // this is the terminal's application.
                return false
            }
            if parent == front { return true }
            current = parent
        }
        return false
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
    nonisolated static func systemControllingTerminalPath(
        forProcessIdentifier pid: Int32
    ) -> String? {
        guard let process = systemProcessRecord(forProcessIdentifier: pid) else {
            return nil
        }
        // `NODEV`, which is a cast macro and so does not reach Swift by name.
        let device = process.kp_eproc.e_tdev
        guard device != -1 else { return nil }
        var name = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard devname_r(device, S_IFCHR, &name, Int32(MAXPATHLEN)) != nil else {
            return nil
        }
        let resolved = String(cString: name)
        guard !resolved.isEmpty else { return nil }
        let path = "/dev/" + resolved
        var attributes = stat()
        guard stat(path, &attributes) == 0,
              attributes.st_mode & S_IFMT == S_IFCHR,
              attributes.st_rdev == device else {
            return nil
        }
        return path
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
