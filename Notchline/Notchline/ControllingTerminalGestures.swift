import AppKit
import Darwin
import Foundation

/// What a session's controlling terminal can say about the user being at it; neither reading
/// is usable alone (``ControllingTerminalGestureReporting``).
nonisolated struct ControllingTerminalReading: Sendable, Equatable {
    /// The last moment the session read anything from its controlling terminal.
    let lastGesture: Date
    /// Whether the application hosting that terminal held the front, on a
    /// screen somebody could be looking at, when `lastGesture` was read.
    let hostIsInFrontOfTheUser: Bool
    /// Whether this session's host could hold the front at all. A session under `tmux`, `screen`
    /// or `ssh` has a controlling terminal but no application ancestor, so it never can; treated
    /// as "not right now", its row booked a full refresh every second (CR-Fable-036). Fixed by
    /// the ancestry for the session's life.
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

/// When the user was last at a process's terminal: the terminal half of "has this been read",
/// without inspecting windows (`AGENTS.md` §6.2).
///
/// Reports the controlling terminal's access time, which moves on any attempted `read` (even
/// `EAGAIN`) and nothing else: `write`, `open`, `close`, `tcgetattr`, `ioctl`, `select` leave
/// it (measured 2026-08-20). The terminal hands the CLI input on (Ghostty, CLI `2.1.238`):
/// - a keystroke, focus gained (`ESC [ I`) or lost (`ESC [ O`), or a reply to a CLI query;
/// - any pointer motion over the surface: Claude Code enables `ESC [ ? 1003 h`.
///
/// It does not move for another tab, window or app (0 stamps over two focus cycles), for the
/// CLI's output (that is the modification time), or for a Turn ending (one move at submit,
/// none in the 110 s after).
///
/// Pointer motion reaches unfocused windows (ADR 0012), so the gesture is ANDed with whether
/// the hosting application holds the front: a crossing pointer, or `ESC [ O` from an app
/// stealing the front, says nothing. An idle terminal makes no gesture; the state alone
/// never counts.
nonisolated protocol ControllingTerminalGestureReporting: Sendable {
    /// What this session's terminal says, or `nil` when it cannot be asked (no controlling
    /// terminal, or `stat` failed); never "not recently". A `nil` row leaves on the next
    /// submission, when the session goes away, or when the user removes it.
    func reading(forProcessIdentifier pid: Int32) async -> ControllingTerminalReading?
}

/// The controlling terminal's access time and its host, via public BSD calls and one public
/// workspace notification: `sysctl(KERN_PROC_PID)` gives the tty device and parent,
/// `devname_r` the path, `stat` the access time; walking parents finds the emulator
/// (`claude` → `-/bin/zsh` → `/usr/bin/login` → `Ghostty`). Nothing is opened or written.
///
/// All degradations keep the row:
/// - No focus reporting: only keystrokes count.
/// - `tmux`, `screen`, `ssh`: never frontmost, reported via
///   ``ControllingTerminalReading/hostCanEverBeInFrontOfTheUser`` to keep them out of the gate.
/// - No controlling terminal (`-p` piped, Claude Desktop): `nil`.
///
/// It can still retire an unread row: pointer motion over a frontmost terminal counts, and
/// the front is sampled ~1 s after the gesture, missing a fast `ESC [ O` exit.
final class ControllingTerminalGestureReader:
    ControllingTerminalGestureReporting, @unchecked Sendable {
    /// Bound on the process-tree walk (three hops on plain Ghostty); deeper answers "not in
    /// front", which keeps the row.
    nonisolated private static let maximumAncestryDepth = 16

    private let controllingTerminalPath: @Sendable (Int32) -> String?
    private let lastAccess: @Sendable (String) -> Date?
    private let parentProcessIdentifier: @Sendable (Int32) -> Int32?
    private let executablePath: @Sendable (Int32) -> String?
    private let frontmostProcessIdentifier: @Sendable () -> Int32?
    private let screenIsAvailable: @Sendable () -> Bool
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    /// - Parameters:
    ///   - executablePath: Read only to ask whether an ancestor sits inside an application bundle.
    ///   - frontmostProcessIdentifier: `nil` tracks it from the workspace.
    ///   - screenIsAvailable: Shared with ``DesktopReadingWatcher``; locking also sends `ESC [ O`.
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
        // Tracked from the notification, as in ``DesktopReadingWatcher``: AppKit is not promised to
        // answer on the refresh's executor. Seeded once: a user already in the terminal fires no
        // activation.
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

    /// Holds the frontmost pid so the closure does not capture `self` from inside its own observer.
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

    nonisolated private struct Host {
        /// The frontmost process is an ancestor, on a screen somebody could be looking at.
        let isInFront: Bool
        /// Some ancestor is an application, so this host could hold the front on a later look.
        let canEverBeInFront: Bool
    }

    /// Whether this session's terminal application is in front (the frontmost process is an
    /// ancestor), and whether it has one (an ancestor sits in an `.app` bundle, by path as in
    /// ``ProcessAncestryHostResolver``). A `tmux` server is daemonised onto `launchd`; `ssh` goes
    /// through `sshd`. An unreadable ancestor answers "cannot be in front", keeping the row.
    nonisolated private func host(ofSession pid: Int32) -> Host {
        let front = frontmostProcessIdentifier()
        // A front held through a sleeping display or a locked screen does not count.
        let frontCounts = (front ?? 0) > 1 && screenIsAvailable()
        var isInFront = false
        var canEverBeInFront = false
        var current = pid
        for _ in 0 ..< Self.maximumAncestryDepth {
            guard let parent = parentProcessIdentifier(current), parent > 1 else {
                // `launchd` or an unreadable record: nothing above can be the terminal's application.
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
            // An unbundled app can still become frontmost via `TransformProcessType`.
            canEverBeInFront: canEverBeInFront || isInFront
        )
    }

    /// The device a process is attached to (`kp_eproc.e_tdev`), or nil. The name is checked back
    /// against the device number, as `devname_r`'s cache may hold a reused name; that check also
    /// makes caching names safe, which saves a `/dev` walk measured at a fifth of steady-state cost.
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

    nonisolated private static func isCharacterDevice(
        _ path: String,
        numbered device: dev_t
    ) -> Bool {
        var attributes = stat()
        return stat(path, &attributes) == 0
            && attributes.st_mode & S_IFMT == S_IFCHR
            && attributes.st_rdev == device
    }

    /// Verified device names by device number, process-wide. Emptied rather than aged past a
    /// bound, so names for gone ttys do not accumulate.
    nonisolated private static let deviceNames = DeviceNames()

    nonisolated private final class DeviceNames: @unchecked Sendable {
        /// Far above a user's open terminals; a reset costs one `/dev` walk per live session.
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

    /// The process that spawned this one, or nil when unreadable; the app's one implementation
    /// (``ProcessAncestryHostResolver`` uses it too). A process reparented onto `launchd` answers 1.
    nonisolated static func systemParentProcessIdentifier(
        forProcessIdentifier pid: Int32
    ) -> Int32? {
        guard let process = systemProcessRecord(forProcessIdentifier: pid) else {
            return nil
        }
        let parent = process.kp_eproc.e_ppid
        return parent > 0 ? parent : nil
    }

    /// When a process started, or nil when there is no such process. An identity, not a clock:
    /// ``ClaudeCodeSessionRegistry`` pairs it with the reusable pid and compares it only with
    /// earlier readings of itself.
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
        // A gone process answers a zero-length record rather than an error.
        guard read == 0, size >= MemoryLayout<kinfo_proc>.stride else { return nil }
        return process
    }

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
