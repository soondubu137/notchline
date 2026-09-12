import Darwin
import Foundation

/// One process in the kernel's table, and what it is running.
struct ProcessEntry: Sendable, Equatable {
    let processIdentifier: Int32
    /// Absolute, or nil where the kernel would not say (another user's
    /// process, or one that has already exited).
    let executablePath: String?
}

/// The kernel's process table and the files a process holds open, as two
/// questions — so the reading that depends on them can be tested against a
/// table of the test's own.
nonisolated protocol ProcessTableReading: Sendable {
    /// Every process running an executable with this last path component.
    ///
    /// **The name is the table's business rather than the caller's**, because
    /// the kernel answers it far more cheaply than it answers a path:
    /// `proc_pidpath` reconstructs a path from a vnode for every process on the
    /// machine (2.3 ms for 713 of them, measured in Release on this machine),
    /// while the short name in `PROC_PIDTBSDINFO` is 0.5 ms for the same walk.
    /// Filtering here rather than after the fact is what makes the reading
    /// cheap enough to take once a second while a finished row waits to be
    /// read. The entries that come back still carry the full path, and the
    /// caller still checks it.
    ///
    /// **Nil is the kernel declining to answer**, which is the one reading that
    /// is not evidence: an empty list says no such process is running, and no
    /// list at all says nothing at all. The live table cannot answer nil while
    /// this app runs — it is at least one of the processes counted.
    func processes(named name: String) -> [ProcessEntry]?
    /// The paths of the files `processIdentifier` holds open, for a process
    /// this user may inspect; empty otherwise.
    func openFilePaths(ofProcess processIdentifier: Int32) -> [String]
}

/// The live table, read through `libproc` — the same calls the terminal
/// route already makes for a process's executable and parent.
struct LibprocProcessTable: ProcessTableReading {
    nonisolated func processes(named name: String) -> [ProcessEntry]? {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return nil }
        // Room for the processes that start between the two calls.
        var identifiers = [pid_t](
            repeating: 0,
            count: Int(needed) / MemoryLayout<pid_t>.stride + 64
        )
        let filled = identifiers.withUnsafeMutableBufferPointer { buffer in
            proc_listpids(
                UInt32(PROC_ALL_PIDS),
                0,
                buffer.baseAddress,
                Int32(buffer.count * MemoryLayout<pid_t>.stride)
            )
        }
        guard filled > 0 else { return nil }
        return identifiers
            .prefix(Int(filled) / MemoryLayout<pid_t>.stride)
            .filter { $0 > 0 && Self.shortName(ofProcess: $0) == name }
            .map {
                ProcessEntry(
                    processIdentifier: $0,
                    executablePath: ProcessAncestryHostResolver.systemExecutablePath(ofProcess: $0)
                )
            }
    }

    /// The name the kernel keeps beside a process, or nil for one this user may
    /// not inspect.
    ///
    /// A copy of the executable's last path component, made when the process
    /// was executed and truncated at 31 characters. It is a pre-filter and
    /// never the verdict: the caller still reads the path the entry carries,
    /// so a name that is a truncation of a longer one, or a binary since
    /// renamed, cannot make a process pass for another.
    nonisolated private static func shortName(ofProcess pid: pid_t) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            return nil
        }
        return withUnsafePointer(to: &info.pbi_name) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(2 * MAXCOMLEN)) {
                String(cString: $0)
            }
        }
    }

    nonisolated func openFilePaths(ofProcess processIdentifier: Int32) -> [String] {
        let needed = proc_pidinfo(processIdentifier, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0 else { return [] }
        var descriptors = [proc_fdinfo](
            repeating: proc_fdinfo(),
            count: Int(needed) / MemoryLayout<proc_fdinfo>.stride + 16
        )
        let filled = descriptors.withUnsafeMutableBufferPointer { buffer in
            proc_pidinfo(
                processIdentifier,
                PROC_PIDLISTFDS,
                0,
                buffer.baseAddress,
                Int32(buffer.count * MemoryLayout<proc_fdinfo>.stride)
            )
        }
        guard filled > 0 else { return [] }
        var paths: [String] = []
        for descriptor in descriptors.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.stride)
        where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            var info = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout<vnode_fdinfowithpath>.stride)
            let got = proc_pidfdinfo(
                processIdentifier,
                descriptor.proc_fd,
                PROC_PIDFDVNODEPATHINFO,
                &info,
                size
            )
            guard got == size else { continue }
            let path = withUnsafePointer(to: &info.pvip.vip_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                    String(cString: $0)
                }
            }
            if !path.isEmpty {
                paths.append(path)
            }
        }
        return paths
    }
}

/// A conversation Antigravity CLI is running right now, and the process
/// running it.
struct AntigravityLiveConversation: Sendable, Equatable {
    let conversationID: String
    let processIdentifier: Int32
}

/// Which conversations Antigravity CLI is running, read off the kernel.
///
/// **The product's own live list, without asking the product.** The CLI keeps
/// `~/.gemini/antigravity-cli/presence/<conversationId>.lock`, one per
/// conversation, and holds the file open under an exclusive `flock` for
/// exactly as long as the process running that conversation lives — measured
/// 2026-09-11 on 1.2.2: locked from the turn's first event to the process's
/// exit, free the instant it exits, and the file left behind unlocked. Which
/// files an `agy` process holds open is a kernel fact (`proc_pidfdinfo`), so
/// the live set is read without touching the locks — taking even a shared
/// lock to probe one would race the product's own acquisition.
///
/// This one reading answers three questions the Provider and the navigator
/// ask separately: whether the product is open (``ProductPresenceReporting``),
/// which Threads it vouches for (``ThreadAdmitting``, ADR 0017), and which
/// process is showing a row (``SessionProcessLocating``), from which the
/// terminal route reads the host to raise.
///
/// **Ceiling, stated.** *Open* means an executable named `agy` holding a
/// presence lock open; the CLI's `remote-control` daemon and `mic-serve` are
/// `agy` too and hold none, so they are not open, and a copy installed under
/// another name is invisible. A conversation's process is found by the lock
/// it holds, never by title, cwd or age. `unknown` is answered only when the
/// kernel lists no process at all, which it cannot while this one runs.
final class AntigravityConversationScanner: ProductPresenceReporting, ThreadAdmitting, ProductSessionReading,
    SessionProcessLocating, @unchecked Sendable {
    static let executableName = "agy"

    /// How long one reading answers for, so the refresh's two questions and a
    /// click's third do not each walk the table.
    static let readingLifetime: TimeInterval = 0.5

    let presenceDirectory: URL
    private let table: any ProcessTableReading
    private let clock: any MonitorClock
    private let lock = NSLock()
    private var cached: (conversations: [AntigravityLiveConversation], readAt: Date, listedAnything: Bool)?

    init(
        presenceDirectory: URL? = nil,
        table: any ProcessTableReading = LibprocProcessTable(),
        clock: any MonitorClock = SystemMonitorClock(),
        fileManager: FileManager = .default
    ) {
        self.presenceDirectory = presenceDirectory
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(AntigravityHookVocabulary.stateDirectoryRelativeToHome, isDirectory: true)
                .appendingPathComponent("presence", isDirectory: true)
        self.table = table
        self.clock = clock
    }

    /// The conversations live at `readAt`, and whether the kernel listed any
    /// process at all — the one case that is not evidence.
    func read() -> (conversations: [AntigravityLiveConversation], readAt: Date, listedAnything: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let now = clock.now()
        if let cached, now.timeIntervalSince(cached.readAt) < Self.readingLifetime, now >= cached.readAt {
            return cached
        }
        guard let processes = table.processes(named: Self.executableName) else {
            // The kernel would not say, so this reading retires nothing and
            // claims nothing — it is not an empty machine.
            let reading = (conversations: [AntigravityLiveConversation](), readAt: now, listedAnything: false)
            cached = reading
            return reading
        }
        let directory = presenceDirectory.standardizedFileURL.path
        var conversations: [AntigravityLiveConversation] = []
        // Every path here is compared as a *string* until one is a candidate.
        // `URL(fileURLWithPath:)` stats the path it is given — it has to, to
        // decide whether the last component is a directory — so the obvious
        // spelling of this loop cost one `lstat` per process on the machine
        // plus one per open file of every `agy` process. That was invisible
        // while the reading happened on an edge; a finished row waiting to be
        // read asks for it once a second, and it was then 293 of the app's 342
        // active samples in a 20-second Release profile. `NSString`'s path
        // arithmetic touches nothing (`AGENTS.md` §7's "measure, do not
        // assume"), and the one comparison that must survive a `/private`
        // prefix is made on the handful of candidates that reach it.
        for process in processes
        where process.executablePath.map({ ($0 as NSString).lastPathComponent })
            == Self.executableName {
            for path in table.openFilePaths(ofProcess: process.processIdentifier)
            where path.hasSuffix(".lock") {
                let url = URL(fileURLWithPath: path)
                guard url.deletingLastPathComponent().standardizedFileURL.path == directory else {
                    continue
                }
                let conversationID = url.deletingPathExtension().lastPathComponent
                guard !conversationID.isEmpty,
                      !conversations.contains(where: { $0.conversationID == conversationID }) else {
                    continue
                }
                conversations.append(
                    AntigravityLiveConversation(
                        conversationID: conversationID,
                        processIdentifier: process.processIdentifier
                    )
                )
            }
        }
        let reading = (conversations: conversations, readAt: now, listedAnything: true)
        cached = reading
        return reading
    }

    /// Presence and admission from one kernel reading, which is what they are.
    func read(observing state: HookStateSnapshot) async -> SessionReading {
        let reading = read()
        guard reading.listedAnything else {
            return SessionReading(presence: .unknown, admission: .unknown)
        }
        return SessionReading(
            presence: reading.conversations.isEmpty ? .closed : .open,
            admission: .exactly(Set(reading.conversations.map(\.conversationID)), readAt: reading.readAt)
        )
    }

    /// Nothing is watched: the locks are read from the kernel when asked.
    func stopWatching() async {}

    func presence() async -> AgentPresence {
        let reading = read()
        guard reading.listedAnything else { return .unknown }
        return reading.conversations.isEmpty ? .closed : .open
    }

    func admission() async -> ThreadAdmission {
        let reading = read()
        guard reading.listedAnything else { return .unknown }
        return .exactly(Set(reading.conversations.map(\.conversationID)), readAt: reading.readAt)
    }

    func processIdentifier(forThreadID threadID: String) async -> Int32? {
        read().conversations.first { $0.conversationID == threadID }?.processIdentifier
    }
}
