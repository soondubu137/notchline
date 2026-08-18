import Foundation
import os

/// One live Claude Code session, as the official command reports it.
nonisolated struct ClaudeCodeSession: Sendable, Equatable {
    let sessionID: String
    let processIdentifier: Int32
    let workingDirectory: URL
    let startedAt: Date
    /// A name Claude Code derives from the directory. Not shown; it is here
    /// because the command reports it and dropping it would make a future
    /// question ("was this session named by the user?") unanswerable.
    let name: String?
}

/// Which Claude Code sessions exist right now.
///
/// **Identity, not state.** The command this reads reports nothing about what a
/// session is doing — its output is byte-identical whether the session is
/// mid-turn or sitting idle. State comes from the Turn reducer and only from
/// there; this answers "which sessions are there", and the two must not be
/// confused.
///
/// It matters more here than the equivalent would on the Codex side, for two
/// reasons. It is the only way a row whose session died can be retired, because
/// `SessionEnd` is deliberately not registered — see
/// ``ClaudeCodeHookVocabulary``. And it is what makes cold start possible at
/// all: Codex has no supported way to ask what is happening right now, so the
/// product shows nothing from before launch; Claude Code does.
protocol ClaudeCodeSessionListing: Sendable {
    func liveSessions() async -> [ClaudeCodeSession]
    /// Whether Claude Code is open at all.
    ///
    /// There is no application to ask -- Claude Code is a CLI the user starts
    /// per directory -- so the session list is the presence signal. That is the
    /// only thing it is used for here: this reports *whether* sessions exist,
    /// never what they are doing.
    func presence() async -> AgentPresence
}

extension ClaudeCodeSessionListing {
    /// Presence read straight off the session list.
    ///
    /// Correct for any source that cannot go stale, which is every test double
    /// and would be any future source that reads live state directly. A source
    /// that caches has to override this, because a cache that never expires
    /// answers `open` forever.
    func presence() async -> AgentPresence {
        await liveSessions().isEmpty ? .closed : .open
    }
}

/// Finds the `claude` executable the same way a user's shell would.
enum ClaudeExecutableLocator {
    /// An override for tests and for a user whose install is somewhere unusual.
    static let overrideEnvironmentKey = "CODEX_IN_NOTCH_CLAUDE_PATH"

    nonisolated static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if let override = environment[overrideEnvironmentKey], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            return fileManager.isExecutableFile(atPath: url.path) ? url : nil
        }

        var candidates = [
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude")
        ]
        // A login shell's PATH is not this process's PATH, so this is a
        // fallback rather than the primary route.
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            candidates.append(
                URL(fileURLWithPath: String(directory))
                    .appendingPathComponent("claude")
            )
        }
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

/// Runs a `claude` subcommand, off the cooperative pool and under a deadline.
///
/// Both of the things this fixes are properties of `Process`, not of Claude
/// Code. `readToEnd` waits for the pipe to close and `waitUntilExit` waits for
/// the child, and doing either inside an `async` function blocks a cooperative
/// thread -- there is roughly one per core -- for as long as the child runs.
/// Four to seven seconds of that once a minute is a real share of a small pool,
/// and if the child never exits the thread is gone for good.
///
/// "Never exits" is not hypothetical here: `claude` starts the user's MCP
/// servers, one of which was already caught writing to this command's stdout.
/// Before the deadline, one wedged child meant the reading that owned it never
/// returned -- the quota froze at its last value, the staleness ceiling never
/// got to fire because nothing ever completed, and only relaunching the app
/// recovered it.
enum ClaudeCommand {
    private static let log = Logger(
        subsystem: "com.yinfenglu.CodexInNotch",
        category: "ClaudeCommand"
    )

    /// Blocking work belongs on a queue that is allowed to grow threads.
    private static let queue = DispatchQueue(
        label: "com.yinfenglu.CodexInNotch.claude-command",
        qos: .utility,
        attributes: .concurrent
    )

    /// How long after `SIGTERM` to stop being polite.
    private static let killGrace: TimeInterval = 2

    /// - Parameters:
    ///   - timeout: How long the child may take before it is killed. A killed
    ///     child reports failure, which is a thing every caller here already
    ///     knows how to degrade to.
    ///   - executable: Overridden only by the test that has to watch a command
    ///     outstay its deadline, which needs one that reliably does.
    static func run(
        _ arguments: [String],
        in directory: URL? = nil,
        timeout: TimeInterval = 20,
        executable: URL? = nil
    ) async -> Data? {
        guard let executable = executable ?? ClaudeExecutableLocator.locate() else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(
                    returning: execute(
                        executable,
                        arguments: arguments,
                        in: directory,
                        timeout: timeout
                    )
                )
            }
        }
    }

    private static func execute(
        _ executable: URL,
        arguments: [String],
        in directory: URL?,
        timeout: TimeInterval
    ) -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        // Discarded rather than piped: a pipe nobody reads fills at 64 KB and
        // then blocks the writer for good, which would hang the read rather
        // than fail it.
        process.standardError = FileHandle.nullDevice
        // Inheriting stdin would let the command wait on a terminal that is not
        // there.
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            log.error("could not run claude \(arguments.first ?? ""): \(error.localizedDescription)")
            return nil
        }

        // SIGTERM at the deadline, SIGKILL shortly after. Politeness alone is
        // not a deadline: a child that ignores SIGTERM would hold the pipe open
        // and `readToEnd` would go on waiting for it.
        let expire = DispatchWorkItem {
            // Signalled by pid rather than through `terminate()`, which is
            // documented to raise on a process that was never launched. The
            // pid guard is not ceremony either: `processIdentifier` is 0 before
            // launch, and `kill(0, ...)` signals this app's whole process
            // group -- this app included.
            let pid = process.processIdentifier
            guard process.isRunning, pid > 0 else { return }
            log.error("claude \(arguments.first ?? "") outlived its deadline; terminating")
            kill(pid, SIGTERM)
            queue.asyncAfter(deadline: .now() + killGrace) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
        queue.asyncAfter(deadline: .now() + timeout, execute: expire)
        defer { expire.cancel() }

        // Pooled: the `Data` off the pipe is autoreleased, and on this queue
        // nothing would ever drain it.
        let data = autoreleasepool {
            try? output.fileHandleForReading.readToEnd()
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data
    }
}

actor ClaudeCodeSessionRegistry: ClaudeCodeSessionListing {
    private static let log = Logger(
        subsystem: "com.yinfenglu.CodexInNotch",
        category: "ClaudeCodeSessionRegistry"
    )

    /// The shape `claude agents --json` prints.
    private struct Reported: Decodable {
        let pid: Int32?
        let cwd: String?
        let kind: String?
        let startedAt: Double?
        let sessionId: String?
        let name: String?
    }

    private let read: @Sendable () async -> Data?
    private let clock: any MonitorClock
    private let freshness: TimeInterval
    private let trustCeiling: TimeInterval
    private var cached: [ClaudeCodeSession] = []
    private var readAt: Date?

    /// - Parameters:
    ///   - freshness: How long before the answer is re-read.
    ///   - trustCeiling: How long a *stale* answer may still be believed.
    ///   - read: Returns the raw JSON, or nil when it could not be obtained.
    ///     Injected so the parsing and staleness rules can be tested without a
    ///     real Claude Code install.
    ///
    /// The two intervals are deliberately separate. They were effectively one
    /// number before, and that made a permanently failing read -- a `claude`
    /// that was uninstalled, renamed or moved off `PATH` -- keep the last good
    /// answer alive for the life of the process. Rows can survive a single
    /// failed read and should; presence cannot survive an unbounded run of
    /// them, because presence is now the difference between `Connected` and
    /// `Disconnected`. Three consecutive failures is the ceiling.
    init(
        clock: any MonitorClock = SystemMonitorClock(),
        freshness: TimeInterval = 30,
        trustCeiling: TimeInterval = 90,
        read: (@Sendable () async -> Data?)? = nil
    ) {
        self.clock = clock
        self.freshness = freshness
        self.trustCeiling = trustCeiling
        self.read = read ?? { await Self.runOfficialCommand() }
    }

    /// Presence, with the cache's own age taken into account.
    ///
    /// An empty list means closed only when the list is *known* to be empty. A
    /// cache past its ceiling knows nothing, and unknown is not a weak "closed"
    /// -- it lands on `Disconnected` by the plain meaning of the word (§6.7):
    /// we have no working connection to report on.
    func presence() async -> AgentPresence {
        let sessions = await liveSessions()
        guard let readAt,
              clock.now().timeIntervalSince(readAt) <= trustCeiling else {
            return .unknown
        }
        return sessions.isEmpty ? .closed : .open
    }

    func liveSessions() async -> [ClaudeCodeSession] {
        if let readAt, clock.now().timeIntervalSince(readAt) < freshness {
            return cached
        }
        return await refresh()
    }

    /// Reads again regardless of freshness, for when something said to.
    @discardableResult
    func refresh() async -> [ClaudeCodeSession] {
        guard let data = await read() else {
            // Keep the last good answer rather than reporting that every
            // session vanished: a failed read is not evidence of absence, and
            // treating it as such would retire every row at once.
            return cached
        }
        guard let reported = try? JSONDecoder().decode([Reported].self, from: data) else {
            Self.log.error("could not decode the session list; keeping the last one")
            return cached
        }

        cached = reported.compactMap { entry in
            guard let sessionID = entry.sessionId, !sessionID.isEmpty,
                  let pid = entry.pid,
                  let cwd = entry.cwd, !cwd.isEmpty,
                  let startedAt = entry.startedAt else {
                return nil
            }
            return ClaudeCodeSession(
                sessionID: sessionID,
                processIdentifier: pid,
                workingDirectory: URL(fileURLWithPath: cwd),
                // Reported in milliseconds.
                startedAt: Date(timeIntervalSince1970: startedAt / 1000),
                name: entry.name
            )
        }
        readAt = clock.now()
        return cached
    }

    /// Runs the documented command and returns its stdout.
    ///
    /// `--json` is documented as printing active sessions, interactive ones
    /// included, and as not requiring a TTY. That is a promise in the CLI's own
    /// help rather than an observed coincidence, which is what makes this a
    /// supported interface instead of a private one.
    ///
    /// **Dead sessions are already filtered, and by the right test.** A session
    /// that was `SIGKILL`ed cannot delete its own `~/.claude/sessions/<pid>.json`,
    /// and those files carry no heartbeat, so the obvious worry is that this
    /// command lists ghosts. Measured against 2.1.229, it does not: a session
    /// file copied verbatim from a live session, with *only* `procStart`
    /// altered, is dropped from the output, and so is one naming a live pid
    /// that belongs to some other process. The command validates `pid` and
    /// `procStart` as a pair -- which is exactly the check that would be needed
    /// here, and is the one thing PID recycling defeats if you only ask whether
    /// the pid is alive.
    ///
    /// So this app does not redo it, and must not: `--json` does not even emit
    /// `procStart`, so re-implementing the check would mean reading the private
    /// session-file schema directly and registering a non-public dependency
    /// (`AGENTS.md` §8) to duplicate a correct public one.
    private static func runOfficialCommand() async -> Data? {
        // Ten seconds, against a list that is re-read every thirty: a slower
        // answer than that would be stale before it arrived, and the registry
        // already keeps its last one when a read fails.
        await ClaudeCommand.run(["agents", "--json"], timeout: 10)
    }
}
