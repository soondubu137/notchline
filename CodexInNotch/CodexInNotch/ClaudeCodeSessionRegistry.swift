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
///
/// **The question is which sessions the *user* has, not which exist.** This
/// app's own quota reading is a Claude Code session too, and the command
/// reports it as `kind: "interactive"` — indistinguishable from a human's by
/// anything except the directory it runs in.
protocol ClaudeCodeSessionListing: Sendable {
    func liveSessions() async -> [ClaudeCodeSession]
    /// Whether Claude Code is open at all.
    ///
    /// There is no application to ask -- Claude Code is a CLI the user starts
    /// per directory -- so the session list is the presence signal. That is the
    /// only thing it is used for here: this reports *whether* sessions exist,
    /// never what they are doing.
    func presence() async -> AgentPresence
    /// Says the answer being held is known to be out of date.
    ///
    /// The caller is `~/.claude/sessions` changing: a session file appeared or
    /// went away, which is the one event that makes a cached list wrong rather
    /// than merely old. Whether that costs a read is the source's decision, not
    /// the caller's -- see ``ClaudeCodeSessionRegistry/invalidate()``.
    ///
    /// **Deliberately without a default implementation**, unlike ``presence()``
    /// above, even though every source that cannot go stale would want the
    /// empty one. A default here is a trap: an actor satisfies this `async`
    /// requirement with a synchronous method, and `await source.invalidate()`
    /// on the concrete type then resolves to the *extension's* empty body
    /// rather than the actor's -- silently, since both compile and only one
    /// does anything. A source that has nothing to do writes the empty body
    /// itself; a source that forgets gets a compile error rather than a
    /// no-op.
    func invalidate() async
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
    private let edgeFloor: TimeInterval
    private let trustCeiling: TimeInterval
    /// Resolved once, because it is compared against every entry of every read.
    private let ignoredWorkingDirectoryPath: String?
    private var cached: [ClaudeCodeSession] = []
    /// When the command last *answered*. Decides how long the answer is
    /// believed.
    private var readAt: Date?
    /// When the command was last *run*, answer or none. Decides when it is run
    /// again, which is a different question -- see ``liveSessions()``.
    private var attemptedAt: Date?
    /// How many times something has said the held answer is wrong.
    ///
    /// Counted rather than flagged, and answered against ``answeredInvalidation``
    /// below, so an edge that lands *while a read is out* is not cleared by
    /// that read: the command was already on its way and cannot have seen what
    /// the edge was reporting. A single flag loses exactly that case, and a
    /// timestamp cannot tell it from "the edge landed a moment before the read
    /// started" without a clock finer than the events being compared.
    private var invalidations = 0
    /// The invalidation count the last completed read answered.
    private var answeredInvalidation = 0
    /// The read that is out, so callers arriving mid-read wait for it instead
    /// of starting one of their own.
    private var inFlight: Task<[ClaudeCodeSession], Never>?
    /// Distinguishes the read this call started from a later one, so an
    /// earlier caller cannot clear somebody else's.
    private var readGeneration = 0

    /// - Parameters:
    ///   - freshness: How long before the command is run again, counted from
    ///     the last *attempt* rather than the last answer -- see
    ///     ``liveSessions()``.
    ///   - edgeFloor: The shortest gap between two attempts that an
    ///     ``invalidate()`` may ask for. It is not a second freshness: an edge
    ///     already means the answer is wrong, so the only thing left to decide
    ///     is how fast a *stream* of edges may make this app launch `claude`.
    ///     Two seconds caps that at 30 launches a minute against the four the
    ///     cadence allows, and the measured rate is far below either --
    ///     `~/.claude/sessions` changed **0 times in 45 seconds** of an active
    ///     desktop session plus two idle ones (measured 2026-08-18), because
    ///     those files are written when a session starts or stops and when a
    ///     CLI session flips busy/idle, not while a turn runs.
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
    ///
    /// - Parameter ignoringWorkingDirectory: A directory whose sessions are not
    ///   the user's. There is exactly one — the folder the quota reading is
    ///   pinned to — and leaving it unset is what made this app monitor itself.
    ///
    ///   `claude -p "/usage"` is a real Claude Code session for the second or so
    ///   it runs, and `claude agents --json` reports it as `kind: "interactive"`,
    ///   exactly as it reports a human's (measured on 2.1.234, 2026-08-18).
    ///   Two things followed. Its transcript carries two `user` records and
    ///   **no `assistant` record at all** — a slash command never reaches the
    ///   model, `num_turns: 0` — so nothing ever supplies the `stop_reason`
    ///   that ends a turn, and
    ///   ``ClaudeCodeTranscriptReader/currentTurn(forSession:workingDirectory:)``
    ///   reconstructs it as *Running*: a row named after this app's own folder,
    ///   held for as long as the list is cached rather than for as long as the
    ///   subprocess lives. And it answers presence, so a user with no Claude
    ///   Code open at all had the product light up in the notch every five
    ///   minutes because this app had just run `claude` itself.
    ///
    ///   Filtered here rather than at the surface because presence is decided
    ///   here: a consumer that dropped the row afterwards would still have been
    ///   told the product was open.
    init(
        clock: any MonitorClock = SystemMonitorClock(),
        freshness: TimeInterval = 30,
        edgeFloor: TimeInterval = 2,
        trustCeiling: TimeInterval = 90,
        ignoringWorkingDirectory: URL? = nil,
        read: (@Sendable () async -> Data?)? = nil
    ) {
        self.clock = clock
        self.freshness = freshness
        self.edgeFloor = edgeFloor
        self.trustCeiling = trustCeiling
        // Symlinks resolved on both sides: the command reports a working
        // directory the kernel already resolved, and a home reached through a
        // link would otherwise never compare equal to the one this app built
        // out of `FileManager`.
        self.ignoredWorkingDirectoryPath = ignoringWorkingDirectory
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
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

    /// The list, re-read when the last *attempt* has gone stale.
    ///
    /// Paced on the attempt and not on the answer, which is the whole of the
    /// difference. Pacing on the answer meant a read that failed left nothing
    /// to wait behind: the next caller found the answer still stale and ran the
    /// command again immediately, and so did the one after that. On the Claude
    /// Code side a refresh is driven by hook events, so a busy turn asks
    /// several times a second -- and a single failed read therefore became a
    /// run of `claude` launches at that rate, measured here at 71 of them
    /// inside 110 seconds against the four the cadence allows for. Each is a
    /// Node process; 24 of them at once take 1.6s apiece against 0.25s alone,
    /// so the storm makes the next read slower, which is the wrong direction.
    ///
    /// It also restores what the ceiling above is written against. "Three
    /// consecutive failures" is only three if failures are spaced a
    /// ``freshness`` apart; unpaced, the ceiling was reached by wall-clock
    /// after dozens of them, and reached it while a busy session was at its
    /// busiest.
    ///
    /// **An edge cuts the wait short, because it is evidence and the clock is
    /// not.** ``freshness`` is a guess about how long a list stays true;
    /// ``invalidate()`` is somebody reporting that it has stopped being true.
    /// Waiting out a guess after receiving the report is what made a session
    /// that is *born with its first prompt* invisible for its whole first turn
    /// -- see ``invalidate()``.
    func liveSessions() async -> [ClaudeCodeSession] {
        if let attemptedAt,
           clock.now().timeIntervalSince(attemptedAt)
            < (isKnownStale ? edgeFloor : freshness) {
            return cached
        }
        return await refresh()
    }

    /// Whether something has reported this list wrong since it was last read.
    private var isKnownStale: Bool {
        invalidations > answeredInvalidation
    }

    /// Says the held list is wrong, so the next reader re-reads it.
    ///
    /// The signal is `~/.claude/sessions` changing, and it is the only thing
    /// that separates "old" from "wrong": a session file appears when a session
    /// starts and goes away when it ends, so an edge means the list this
    /// registry is holding is missing a session or holding a dead one.
    ///
    /// Nothing was listening to that before, and the cost fell entirely on one
    /// product. A CLI session is started by hand and then sits at its prompt,
    /// so by the time the user types anything the list has long since caught
    /// up. A session in the Claude Code desktop app is created *by* the first
    /// prompt -- the process, its `~/.claude/sessions/<pid>.json`, and
    /// `UserPromptSubmit` all arrive inside a second -- so the whole turn ran
    /// inside the window where the list still said that session did not exist.
    /// ``ClaudeCodeMonitorService`` drops any turn whose session is not listed,
    /// which is deliberate and right; the list simply has to be told. Measured
    /// 2026-08-18 against 2.1.234: a desktop-shaped session's row appeared 20
    /// and 23 seconds after its `Stop`, so *Running* was never drawn at all and
    /// *Completed* arrived long after the turn it described.
    ///
    /// Deliberately not a read of its own. Reading here would put a `claude`
    /// launch on the watcher's thread, which is exactly the storm the pacing
    /// above exists to prevent; this only moves the *next* reader's deadline
    /// forward, and no closer than ``edgeFloor``.
    func invalidate() {
        invalidations += 1
    }

    /// Reads again regardless of freshness, for when something said to.
    ///
    /// Single-flighted: an actor suspends at every `await`, so without this two
    /// callers that arrive while the command is out would each start one of
    /// their own. One refresh asks twice by design -- once for the rows and
    /// once for the mark -- so that was not a rare interleaving but the
    /// ordinary path.
    @discardableResult
    func refresh() async -> [ClaudeCodeSession] {
        if let inFlight { return await inFlight.value }
        readGeneration += 1
        let generation = readGeneration
        let task = Task { await self.performRead() }
        inFlight = task
        let sessions = await task.value
        if readGeneration == generation { inFlight = nil }
        return sessions
    }

    private func performRead() async -> [ClaudeCodeSession] {
        // Taken immediately before the command goes out, so an edge that lands
        // while it is running survives it: that read cannot have seen what the
        // edge is reporting -- see ``invalidations``.
        let answering = invalidations
        let data = await read()
        // Stamped whether or not there was an answer: this is what paces the
        // next attempt, and a failure that booked no time at all is what let
        // one failed read become a run of them.
        attemptedAt = clock.now()
        answeredInvalidation = max(answeredInvalidation, answering)
        guard let data else {
            // Keep the last good answer rather than reporting that every
            // session vanished: a failed read is not evidence of absence, and
            // treating it as such would retire every row at once.
            return cached
        }
        guard let sessions = Self.sessions(in: data) else {
            Self.log.error("could not decode the session list; keeping the last one")
            return cached
        }

        cached = sessions.filter { !isOwnReading($0) }
        readAt = clock.now()
        return cached
    }

    /// Whether an entry is this app's own quota reading rather than a session
    /// the user started.
    private func isOwnReading(_ session: ClaudeCodeSession) -> Bool {
        guard let ignoredWorkingDirectoryPath else { return false }
        return session.workingDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path == ignoredWorkingDirectoryPath
    }

    /// The sessions in one run of stdout, or nil when there are none to be had.
    ///
    /// **The array is found rather than assumed to be the whole stream.** This
    /// is the same problem ``ClaudeCodeUsageReader`` already answers and it is
    /// answered here for the same measured reason: `claude` starts the user's
    /// MCP servers, and one of them was caught writing a line of its own --
    /// `Client.listTools() called but server does not advertise tools
    /// capability - returning empty list` -- to this command's stdout, on two
    /// runs in five. `JSONDecoder` rejects the whole stream over text the
    /// object did not ask for.
    ///
    /// That mattered more here than it looks. A list that cannot be decoded is
    /// indistinguishable at this boundary from a command that never answered,
    /// so somebody else's log line does not merely cost one reading — it ages
    /// this product towards `Disconnected` and takes its mark off the notch.
    /// The line-by-line trick used for the quota does not transfer, because
    /// this array is pretty-printed across many lines; the bracketed span does.
    ///
    /// Made `static` and non-private so the rule can be tested against captured
    /// bytes rather than by running anything, exactly as the quota's parser is.
    nonisolated static func sessions(in data: Data) -> [ClaudeCodeSession]? {
        let decoder = JSONDecoder()
        let reported = (try? decoder.decode([Reported].self, from: data))
            ?? bracketedSpan(in: data).flatMap { try? decoder.decode([Reported].self, from: $0) }
        guard let reported else { return nil }
        return reported.compactMap { entry in
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
    }

    /// From the first `[` to the last `]`, which is the array and whatever the
    /// array itself contains -- never a line printed before or after it.
    nonisolated private static func bracketedSpan(in data: Data) -> Data? {
        guard let start = data.firstIndex(of: UInt8(ascii: "[")),
              let end = data.lastIndex(of: UInt8(ascii: "]")),
              start < end else {
            return nil
        }
        return Data(data[start ... end])
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
