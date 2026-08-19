import Darwin
import Foundation

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
/// last moment the session's **controlling terminal handed it something**. That
/// is not a guess about which window is visible -- it is a record that
/// somebody's terminal delivered input to this session and to no other.
///
/// **What moves it** (measured 2026-08-19 against Ghostty and CLI `2.1.236`):
///
/// - a keystroke, including the one that starts the next Turn;
/// - that surface **gaining** the front (`ESC [ I`);
/// - that surface **losing** the front (`ESC [ O`);
/// - a terminal's reply to a query the CLI itself sent.
///
/// The two focus events are there because Claude Code turns focus reporting on
/// (`ESC [ ? 1004 h`, present in the shipped binary and written whenever it
/// leaves the alternate screen). They are what makes this cover the ordinary
/// way people use a terminal: you leave the tab while it works, and coming back
/// to it is itself the gesture.
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
///   purpose moved the access time exactly twice -- once for the terminal's
///   reply to the capability query at startup, once for the keystroke that
///   submitted the prompt -- and not once in the 67 seconds after, which
///   covered the answer landing, the Stop hook, and the `OSC 777` notification
///   the CLI sends when it starts waiting. That notification is output, and
///   terminals do not reply to it.
///
/// **It is a transition, never a state**, which is the whole safety argument --
/// the same one ``DesktopActivationReporting`` makes. A machine sitting idle
/// with a window in front of an empty chair produces none of it; the first
/// three movements above all require somebody at the keyboard.
///
/// The fourth does not, and it is the only part of this that is not a person.
/// It is bounded rather than argued away: the replies measured all arrive
/// while the CLI is starting up, which is before any Turn of that session has
/// finished, so they cannot be mistaken for reading one. A future version that
/// re-queried its terminal mid-session would move the access time without a
/// user, and the failure would look like a finished row leaving early.
nonisolated protocol ControllingTerminalGestureReporting: Sendable {
    /// The last moment this process's controlling terminal handed it anything.
    ///
    /// `nil` means the question cannot be asked at all -- the process has no
    /// controlling terminal, or the device could not be stat'ed -- and never
    /// "not recently". A session that answers `nil` keeps the behaviour a
    /// terminal session has always had: its finished row leaves on the next
    /// submission, when the session goes away, or when the user removes it.
    func lastUserGesture(forProcessIdentifier pid: Int32) async -> Date?
}

/// The controlling terminal's access time, read through two public BSD calls.
///
/// `sysctl(KERN_PROC_PID)` reports the process's controlling terminal as a
/// device number, `devname_r` turns that into `/dev/ttysNNN`, and `stat`
/// reports when it was last read from. No file contents are opened, no window
/// is inspected, no title is matched, and nothing is written.
///
/// **Where it degrades, and which way.** A terminal that does not implement
/// focus reporting -- or a multiplexer configured not to forward it -- leaves
/// only keystrokes, so a row waits for the user's next key instead of for them
/// coming back to the tab. A session with no controlling terminal at all (`-p`
/// with its output piped, or a session Claude Desktop hosts) answers `nil`.
/// Both fail towards keeping the row listed, which is the failure this product
/// prefers.
///
/// **The one way it can retire a row nobody read.** The gestures above cannot
/// tell the user leaving that surface from something else taking the front
/// while they are away: an application that activates itself sends the visible
/// surface a focus-out, and a Turn that finished just before it looks read.
/// It is narrower than the equivalent on the Desktop side --
/// ``DesktopReadingReporting`` retires a row for a user who merely walked away
/// -- and it needs the answer to have been on screen when it happened.
struct ControllingTerminalGestureReader: ControllingTerminalGestureReporting {
    private let controllingTerminalPath: @Sendable (Int32) -> String?
    private let lastAccess: @Sendable (String) -> Date?

    /// - Parameters:
    ///   - controllingTerminalPath: Which device a process is attached to.
    ///   - lastAccess: When that device was last read from. Both are injected
    ///     so a test can put a session on a terminal it controls, rather than
    ///     on whichever one the developer happens to be typing into.
    nonisolated init(
        controllingTerminalPath: @escaping @Sendable (Int32) -> String? = {
            ControllingTerminalGestureReader
                .systemControllingTerminalPath(forProcessIdentifier: $0)
        },
        lastAccess: @escaping @Sendable (String) -> Date? = {
            ControllingTerminalGestureReader.systemLastAccess(ofDevice: $0)
        }
    ) {
        self.controllingTerminalPath = controllingTerminalPath
        self.lastAccess = lastAccess
    }

    nonisolated func lastUserGesture(forProcessIdentifier pid: Int32) async -> Date? {
        guard let path = controllingTerminalPath(pid) else { return nil }
        return lastAccess(path)
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
