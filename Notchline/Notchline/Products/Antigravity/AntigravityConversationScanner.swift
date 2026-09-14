import Darwin
import Foundation

struct ProcessEntry: Sendable, Equatable {
    let processIdentifier: Int32
    /// Absolute, or nil where the kernel would not say (another user's process, or one exited).
    let executablePath: String?
}

/// The kernel's process table and a process's open files, as a protocol so readings can be
/// tested against a fake table.
nonisolated protocol ProcessTableReading: Sendable {
    /// Every process running an executable with this last path component.
    ///
    /// - Filtered by the kernel's short name: `PROC_PIDTBSDINFO` takes 0.5 ms vs `proc_pidpath`'s
    ///   2.3 ms for 713 processes (Release), cheap enough for once a second. Callers still check the
    ///   full path.
    /// - Nil is the kernel declining to answer, which is not evidence; empty means none running.
    func processes(named name: String) -> [ProcessEntry]?
    /// The paths of files `processIdentifier` holds open, for a process this user may inspect;
    /// empty otherwise.
    func openFilePaths(ofProcess processIdentifier: Int32) -> [String]
}

/// The live table, read through `libproc`.
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

    /// The kernel's short name for a process (truncated at 31 characters), or nil if not
    /// inspectable. A pre-filter only: the caller still checks the path.
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

struct AntigravityLiveConversation: Sendable, Equatable {
    let conversationID: String
    let processIdentifier: Int32
}

/// Which conversations Antigravity CLI is running, read off the kernel.
///
/// - The CLI holds `~/.gemini/antigravity-cli/presence/<conversationId>.lock` under an exclusive
///   `flock` for exactly the life of the conversation's process (measured 2026-09-11 on 1.2.2;
///   the file stays behind unlocked). Open files are read via `proc_pidfdinfo`, never by taking
///   a lock, which would race the product's own acquisition.
/// - One reading answers presence, admission (ADR 0017) and ``SessionProcessLocating``.
/// - Ceiling: open means an `agy` executable holding a presence lock (`remote-control` and
///   `mic-serve` hold none; a renamed copy is invisible). Matched by lock, never title, cwd or
///   age. `unknown` only when the kernel lists no process at all.
final class AntigravityConversationScanner: ProductPresenceReporting, ThreadAdmitting, ProductSessionReading,
    SessionProcessLocating, @unchecked Sendable {
    static let executableName = "agy"

    /// How long one reading answers for, so the refresh's two questions and a click's third share it.
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

    /// The conversations live at `readAt`, and whether the kernel listed any process at all.
    func read() -> (conversations: [AntigravityLiveConversation], readAt: Date, listedAnything: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let now = clock.now()
        if let cached, now.timeIntervalSince(cached.readAt) < Self.readingLifetime, now >= cached.readAt {
            return cached
        }
        guard let processes = table.processes(named: Self.executableName) else {
            // The kernel would not say: this reading retires and claims nothing.
            let reading = (conversations: [AntigravityLiveConversation](), readAt: now, listedAnything: false)
            cached = reading
            return reading
        }
        let directory = presenceDirectory.standardizedFileURL.path
        var conversations: [AntigravityLiveConversation] = []
        // Paths stay strings until one is a candidate: `URL(fileURLWithPath:)` stats each one, which
        // was 293 of 342 active samples in a 20 s Release profile. Only candidates get the `/private`
        // comparison.
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
