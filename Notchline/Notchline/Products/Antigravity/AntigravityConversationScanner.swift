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
    func processes() -> [ProcessEntry]
    /// The paths of the files `processIdentifier` holds open, for a process
    /// this user may inspect; empty otherwise.
    func openFilePaths(ofProcess processIdentifier: Int32) -> [String]
}

/// The live table, read through `libproc` — the same calls the terminal
/// route already makes for a process's executable and parent.
struct LibprocProcessTable: ProcessTableReading {
    nonisolated func processes() -> [ProcessEntry] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }
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
        guard filled > 0 else { return [] }
        return identifiers
            .prefix(Int(filled) / MemoryLayout<pid_t>.stride)
            .filter { $0 > 0 }
            .map {
                ProcessEntry(
                    processIdentifier: $0,
                    executablePath: ProcessAncestryHostResolver.systemExecutablePath(ofProcess: $0)
                )
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
final class AntigravityConversationScanner: ProductPresenceReporting, ThreadAdmitting,
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
        let processes = table.processes()
        let directory = presenceDirectory.standardizedFileURL.path
        var conversations: [AntigravityLiveConversation] = []
        for process in processes
        where process.executablePath.map({ URL(fileURLWithPath: $0).lastPathComponent }) == Self.executableName {
            for path in table.openFilePaths(ofProcess: process.processIdentifier) {
                let url = URL(fileURLWithPath: path)
                guard url.pathExtension == "lock",
                      url.deletingLastPathComponent().standardizedFileURL.path == directory else {
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
        let reading = (conversations: conversations, readAt: now, listedAnything: !processes.isEmpty)
        cached = reading
        return reading
    }

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
