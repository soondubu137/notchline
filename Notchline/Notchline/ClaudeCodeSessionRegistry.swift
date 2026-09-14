import Foundation
import os

/// One live Claude Code session, as the official command reports it.
nonisolated struct ClaudeCodeSession: Sendable, Equatable {
    let sessionID: String
    let processIdentifier: Int32
    let workingDirectory: URL
    let startedAt: Date
    /// Derived by Claude Code from the directory; not shown.
    let name: String?
    /// What the session says it is doing, when it says anything at all.
    let activity: ClaudeCodeActivity?

    nonisolated init(
        sessionID: String,
        processIdentifier: Int32,
        workingDirectory: URL,
        startedAt: Date,
        name: String?,
        activity: ClaudeCodeActivity? = nil
    ) {
        self.sessionID = sessionID
        self.processIdentifier = processIdentifier
        self.workingDirectory = workingDirectory
        self.startedAt = startedAt
        self.name = name
        self.activity = activity
    }
}

/// Whether a session is working, and when that was true.
///
/// Claude Code publishes `busy`, `waiting` (a prompt in front of the user), `idle` and `shell`;
/// on 2.1.235 (2026-08-18) each landed within 160 ms, including `Esc` reaching `idle` with the
/// dialog still open, which no hook reports (CC-019). It names no Turn, so it may only say the
/// held Turn is no longer being worked on.
nonisolated struct ClaudeCodeActivity: Sendable, Equatable {
    /// Claude Code's four words; an unrecognised one reports no activity.
    enum State: String, Sendable, Equatable {
        case busy
        case waiting
        case idle
        case shell
    }

    let state: State
    /// When the reading command started, not when it answered, so the reading is entirely newer
    /// than any earlier event.
    let observedAt: Date

    /// Whether a Turn could still be running; `waiting` counts, since the reducer owns that state.
    var isWorking: Bool {
        state == .busy || state == .waiting
    }
}

/// Which Claude Code sessions the user has; also this product's presence source
/// (``ProductPresenceReporting``).
///
/// Turn state comes from the reducer, except ``ClaudeCodeActivity``: the only signal a user
/// interrupt produces (CC-019, #38), and what retires a row whose session died, since
/// `SessionEnd` is not registered (``ClaudeCodeHookVocabulary``). This app's quota reading
/// also reports `kind: "interactive"`; only its directory tells it apart.
protocol ClaudeCodeSessionListing: ProductPresenceReporting {
    func liveSessions() async -> [ClaudeCodeSession]
    /// Whether Claude Code is open at all; for a CLI the session list is the presence signal.
    func presence() async -> AgentPresence
    /// Marks the held answer out of date (a `~/.claude/sessions` file appeared or went away); the
    /// source decides whether that costs a read.
    ///
    /// No default implementation: on the concrete type an actor's synchronous method would lose
    /// to the extension's empty body, silently.
    func invalidate() async
    /// When the reading behind the held list began, or `.distantFuture` for a source that cannot
    /// be out of date (and the registry before its first successful read, failing closed).
    /// No default implementation, for ``invalidate()``'s reason.
    func listReadStartedAt() async -> Date
}

extension ClaudeCodeSessionListing {
    /// Correct only for sources that cannot go stale; a caching source must override it.
    func presence() async -> AgentPresence {
        await liveSessions().isEmpty ? .closed : .open
    }
}

/// Finds `claude` as a user's shell would, then in Claude Desktop's bundled copy.
///
/// Desktop-only machines have no `claude` on `PATH`; Desktop's copy answers the same command
/// against `~/.claude/sessions` (`2.1.258`, 2026-09-02). Tried last: a CLI the user installed
/// is the one they drive.
enum ClaudeExecutableLocator {
    /// An override for tests and for a user whose install is somewhere unusual.
    static let overrideEnvironmentKey = "NOTCHLINE_CLAUDE_PATH"

    /// Where Claude Desktop keeps downloaded CLI versions, several at once (`2.1.255` and
    /// `2.1.258` side by side, 2026-09-02), so one is chosen by the version in the name.
    nonisolated private static let desktopVersionsDirectoryName = "claude-code"

    /// The executable inside a version directory; its bundle `com.anthropic.claude-code` is
    /// also what ``ProcessHostNavigator`` depends on.
    nonisolated private static let desktopRelativeExecutablePath =
        "claude.app/Contents/MacOS/claude"

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
        // A login shell's PATH is not this process's PATH, so this is only a fallback.
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            candidates.append(
                URL(fileURLWithPath: String(directory))
                    .appendingPathComponent("claude")
            )
        }
        // Claude Desktop's copy, present even if the user never installed the command.
        candidates.append(
            contentsOf: desktopBundledExecutables(
                environment: environment,
                fileManager: fileManager
            )
        )
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    /// Claude Desktop's own CLI copies, newest first. Unparseable names are still offered, last;
    /// `.verified` is not read, only `isExecutableFile`.
    nonisolated static func desktopBundledExecutables(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [URL] {
        let versions = ClaudeCodeDesktopReadStateRepository
            .liveHomeURL(environment: environment, fileManager: fileManager)
            .appendingPathComponent(desktopVersionsDirectoryName, isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: versions,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries
            .sorted { isNewer($0.lastPathComponent, than: $1.lastPathComponent) }
            .map { $0.appendingPathComponent(desktopRelativeExecutablePath) }
    }

    /// Numeric version order (`2.1.10` above `2.1.9`); non-numeric names sort older, by string.
    nonisolated private static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        if left == nil, right == nil { return lhs > rhs }
        guard let left else { return false }
        guard let right else { return true }
        for (a, b) in zip(left, right) where a != b { return a > b }
        if left.count != right.count { return left.count > right.count }
        return lhs > rhs
    }

    nonisolated private static func versionComponents(_ name: String) -> [Int]? {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        return numbers
    }
}

/// Runs a `claude` subcommand off the cooperative pool and under a deadline.
///
/// `readToEnd` and `waitUntilExit` block a cooperative thread while the child runs, and the
/// user's MCP servers can keep it running forever. The deadline is on the read, not the child
/// (CR-Fable-038): EOF needs every inherited write end closed, and one orphan wedged every
/// caller in both products. Reading stops at EOF, a ``drainGrace`` after the child exits, or a
/// ``readGrace`` past its deadline.
enum ClaudeCommand {
    private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "ClaudeCommand"
    )

    /// Blocking work belongs on a queue that is allowed to grow threads.
    private static let queue = DispatchQueue(
        label: "com.yinfenglu.Notchline.claude-command",
        qos: .utility,
        attributes: .concurrent
    )

    /// How long after `SIGTERM` to stop being polite.
    private static let killGrace: TimeInterval = 2

    /// How long stdout is still read after the child exits. Its output is already in the pipe, so
    /// this drains it rather than waiting on whoever else holds the write end.
    private static let drainGrace: TimeInterval = 0.25

    /// How long past the child's deadline stdout is still read: the last bound, for a child that
    /// outlives `SIGKILL` or whose death is never reported.
    private static let readGrace: TimeInterval = killGrace + 1

    /// The longest `poll` sleeps while the child runs, so its exit is noticed promptly.
    private static let pollSlice: Int32 = 250

    /// How long a finished child's pid is still remembered as this app's own: the record's
    /// removal edge is debounced behind the exit. Short, since a live pid cannot be reused.
    private static let ownPIDGrace: TimeInterval = 5

    /// The `claude` processes this app is running or has just finished running.
    ///
    /// The quota reading's `~/.claude/sessions/<pid>.json` record looks like a user session to the
    /// watcher, and each edge cost a `claude` launch (~0.4 s of a core, one per quota reading,
    /// measured in Release). The pid tells them apart; no session file is read.
    nonisolated(unsafe) private static var ownPIDs: Set<Int32> = []
    private static let ownPIDsLock = NSLock()

    /// Whether a sessions-directory entry belongs to a `claude` this app launched. Takes the name:
    /// `<pid>.json` and `<pid>.<hash>.key` both lead with the pid.
    nonisolated static func ownsSessionRecord(named name: String) -> Bool {
        guard let pid = Int32(name.prefix { $0 != "." }) else { return false }
        ownPIDsLock.lock()
        defer { ownPIDsLock.unlock() }
        return ownPIDs.contains(pid)
    }

    nonisolated private static func noteOwn(pid: Int32) {
        guard pid > 0 else { return }
        ownPIDsLock.lock()
        ownPIDs.insert(pid)
        ownPIDsLock.unlock()
    }

    nonisolated private static func forgetOwn(pid: Int32) {
        ownPIDsLock.lock()
        ownPIDs.remove(pid)
        ownPIDsLock.unlock()
    }

    /// - Parameters:
    ///   - timeout: How long the child may take before it is killed and reports failure. Reading
    ///     stdout is bounded separately; see ``drain(_:of:until:)``.
    ///   - executable: Overridden only by tests.
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
        // Discarded, not piped: an unread pipe fills at 64 KB and blocks the writer for good.
        process.standardError = FileHandle.nullDevice
        // Inheriting stdin could leave the command waiting on a terminal that is not there.
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            log.error("could not run claude \(arguments.first ?? ""): \(error.localizedDescription)")
            return nil
        }

        // Noted for every command; which ones leave a session record is Claude Code's business.
        let launched = process.processIdentifier
        noteOwn(pid: launched)
        defer {
            queue.asyncAfter(deadline: .now() + ownPIDGrace) {
                forgetOwn(pid: launched)
            }
        }

        // SIGTERM at the deadline, SIGKILL shortly after: a child ignoring SIGTERM holds the pipe.
        let expire = DispatchWorkItem {
            // By pid, not `terminate()` (raises on an unlaunched process). `processIdentifier` is 0
            // before launch, and `kill(0, ...)` signals this app's whole process group.
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

        let (data, outcome) = drain(
            output.fileHandleForReading,
            of: process,
            until: .now() + timeout + readGrace
        )
        switch outcome {
        case .endOfFile:
            break
        case .outlivedByPipe:
            // Not a failure: the child answered and exited; something it started holds the pipe.
            log.error("claude \(arguments.first ?? "") left its stdout open behind it")
        case .deadline:
            log.error("claude \(arguments.first ?? "") outlived its read deadline; abandoning it")
            // `expire` runs on this same queue and may not have run yet.
            let pid = process.processIdentifier
            if process.isRunning, pid > 0 { kill(pid, SIGKILL) }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data
    }

    /// Why a read of the child's stdout stopped.
    private enum ReadOutcome {
        /// Every copy of the write end is closed, so the answer is complete.
        case endOfFile
        /// The child is gone but something it started still holds stdout; its output is already here.
        case outlivedByPipe
        /// Neither the child nor the pipe finished in time.
        case deadline
    }

    /// Reads the child's stdout under a deadline of its own, which `readToEnd()` cannot take.
    /// Straight off the descriptor into one reused buffer, so no autoreleased `Data`.
    private static func drain(
        _ handle: FileHandle,
        of process: Process,
        until deadline: DispatchTime
    ) -> (data: Data, outcome: ReadOutcome) {
        let descriptor = handle.fileDescriptor
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        // Armed when the child is first seen gone; pushed back by any later bytes.
        var quiet: DispatchTime?

        while true {
            if quiet == nil, !process.isRunning { quiet = .now() + drainGrace }
            let now = DispatchTime.now()
            if now >= deadline { return (data, .deadline) }
            if let quiet, now >= quiet { return (data, .outlivedByPipe) }

            // Sliced only while the child is alive, so its exit is noticed; `poll` reports bytes itself.
            let stop = min(quiet ?? deadline, deadline)
            var waiting = Int32(
                clamping: (stop.uptimeNanoseconds - now.uptimeNanoseconds) / 1_000_000 + 1
            )
            if quiet == nil { waiting = min(waiting, pollSlice) }

            var watched = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&watched, 1, waiting)
            if ready == 0 { continue }
            if ready < 0 {
                if errno == EINTR { continue }
                // Retrying `poll` on our own descriptor mends nothing; the exit status still has to agree.
                return (data, .endOfFile)
            }

            let count = buffer.withUnsafeMutableBytes {
                read(descriptor, $0.baseAddress, $0.count)
            }
            if count > 0 {
                data.append(contentsOf: buffer[..<count])
                // A pipe filled before exit is read out fully; ``readGrace`` bounds a holder still writing.
                if quiet != nil { quiet = .now() + drainGrace }
            } else if count == 0 {
                return (data, .endOfFile)
            } else if errno != EINTR, errno != EAGAIN {
                return (data, .endOfFile)
            }
        }
    }
}

actor ClaudeCodeSessionRegistry: ClaudeCodeSessionListing, ManagedMonitoringSource {
    private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "ClaudeCodeSessionRegistry"
    )

    /// The shape `claude agents --json` prints. Every field is optional so an unknown schema costs
    /// no list, which is why ``identity`` must gate what decoded (``reportedEntries(in:)``).
    private struct Reported: Decodable {
        let pid: Int32?
        let cwd: String?
        let kind: String?
        let startedAt: Double?
        let sessionId: String?
        let name: String?
        /// Always absent for Desktop-hosted sessions (`stream-json`, no terminal UI, #41). Absent is
        /// not `idle`.
        let status: String?

        /// The four fields without which an entry is not a session; shared by ``reportedEntries(in:)``
        /// and ``sessions(in:)`` so the gate and the rows cannot drift.
        var identity: (sessionID: String, pid: Int32, cwd: String, startedAt: Double)? {
            guard let sessionId, !sessionId.isEmpty,
                  let pid,
                  let cwd, !cwd.isEmpty,
                  let startedAt else {
                return nil
            }
            return (sessionId, pid, cwd, startedAt)
        }
    }

    private let read: @Sendable () async -> Data?
    /// When a process started, or nil if there is none: the ghost check
    /// (``everyListedSessionIsStillAlive()``). Injected for tests.
    private let processStartedAt: @Sendable (Int32) -> Date?
    /// Whether there is a screen to read the notch on; gates only the clock-driven re-read
    /// (``isDueForReading``).
    private let screenIsAvailable: @Sendable () -> Bool
    private let clock: any MonitorClock
    private let freshness: TimeInterval
    private let edgeFloor: TimeInterval
    private let trustCeiling: TimeInterval
    /// Each listed session's process start instant, read with the list. A pid the kernel would not
    /// answer for is absent, so ``everyListedSessionIsStillAlive()`` refuses rather than guesses.
    private var livenessAnchors: [Int32: Date] = [:]
    /// Resolved once, because it is compared against every entry of every read.
    private let ignoredWorkingDirectoryPath: String?
    private var cached: [ClaudeCodeSession] = []
    /// When the command last answered; decides how long the answer is believed.
    private var readAt: Date?
    /// When the command behind the held list started; see ``listReadStartedAt()``.
    private var readStartedAt: Date?
    /// When the command was last run, answered or not; decides when it runs again.
    private var attemptedAt: Date?
    /// Whether the last attempt returned a readable list: separates `claude` answering "nothing is
    /// running" (held) from no answer at all (keeps asking).
    private var lastAttemptAnswered = false
    /// How many times the held answer was reported wrong. A count, not a flag, so an edge landing
    /// while a read is out is not cleared by that read.
    private var invalidations = 0
    /// The invalidation count the last completed read answered.
    private var answeredInvalidation = 0
    /// The read that is out, so callers arriving mid-read wait for it.
    private var inFlight: Task<[ClaudeCodeSession], Never>?
    /// Lets a caller clear only the read it started.
    private var readGeneration = 0
    private var monitoringPaused = false

    /// - Parameters:
    ///   - freshness: How long before the command runs again, from the last attempt.
    ///   - edgeFloor: The shortest gap an ``invalidate()`` may force between attempts: at most 30
    ///     launches a minute. `~/.claude/sessions` changed 0 times in 45 seconds of use
    ///     (2026-08-18); in-place record rewrites fire no directory event.
    ///   - trustCeiling: How long a stale answer may still be believed: three consecutive
    ///     failures, so a missing `claude` cannot keep presence alive forever.
    ///   - read: Returns the raw JSON, or nil; injected for tests.
    ///   - ignoringWorkingDirectory: The quota reading's folder. `claude -p "/usage"` is reported
    ///     as `kind: "interactive"` (2.1.234, 2026-08-18) and would otherwise answer presence;
    ///     filtered here because presence is decided here.
    init(
        clock: any MonitorClock = SystemMonitorClock(),
        freshness: TimeInterval = 30,
        edgeFloor: TimeInterval = 2,
        trustCeiling: TimeInterval = 90,
        ignoringWorkingDirectory: URL? = nil,
        screenIsAvailable: @escaping @Sendable () -> Bool = { true },
        processStartedAt: (@Sendable (Int32) -> Date?)? = nil,
        read: (@Sendable () async -> Data?)? = nil
    ) {
        self.clock = clock
        self.freshness = freshness
        self.edgeFloor = edgeFloor
        self.trustCeiling = trustCeiling
        self.screenIsAvailable = screenIsAvailable
        self.processStartedAt = processStartedAt
            ?? ControllingTerminalGestureReader.systemProcessStartedAt(
                forProcessIdentifier:
            )
        // Symlinks resolved on both sides: the command reports kernel-resolved directories.
        self.ignoredWorkingDirectoryPath = ignoringWorkingDirectory
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        self.read = read ?? { await Self.runOfficialCommand() }
    }

    /// Presence, with the cache's age taken into account. Empty means closed only when known empty;
    /// past the ceiling it is unknown, so `Disconnected` (§6.7). The ceiling counts failed reads
    /// (three, a ``freshness`` apart), not elapsed time: an uncontradicted answer does not age.
    func presence() async -> AgentPresence {
        let sessions = await liveSessions()
        guard lastAttemptAnswered || isWithinTrustCeiling else { return .unknown }
        return sessions.isEmpty ? .closed : .open
    }

    /// Whether the last answer is recent enough to decide presence; false if there never was one.
    private var isWithinTrustCeiling: Bool {
        guard let readAt else { return false }
        return clock.now().timeIntervalSince(readAt) <= trustCeiling
    }

    /// The list, re-read when the last attempt has gone stale.
    ///
    /// - Paced on the attempt, not the answer: a failed read otherwise relaunched `claude` 71 times
    ///   in 110 seconds during a busy Turn, and ``trustCeiling``'s failures must be ``freshness``
    ///   apart.
    /// - An edge (``invalidate()``) cuts the wait to ``edgeFloor``; otherwise a session born with
    ///   its first prompt is invisible for its whole first Turn.
    /// - A known-empty list is not re-read (CR-Fable-002): each run costs 0.26-0.33s of CPU and
    ///   starts the user's MCP servers, and every route out of empty raises an edge.
    /// - Listed sessions are re-read on ``freshness`` only when
    ///   ``everyListedSessionIsStillAlive()`` fails, since a `SIGKILL`ed session raises no edge.
    /// - Only the clock-driven branch waits for a screen; edges are answered regardless.
    func liveSessions() async -> [ClaudeCodeSession] {
        guard isDueForReading else { return cached }
        return await refresh()
    }

    /// Whether the command is run for the caller now standing at the door.
    private var isDueForReading: Bool {
        guard let attemptedAt else { return true }
        let waited = clock.now().timeIntervalSince(attemptedAt)
        if isKnownStale { return waited >= edgeFloor }
        // Answered empty and nothing reported it wrong: hold it.
        if lastAttemptAnswered, cached.isEmpty { return false }
        guard waited >= freshness else { return false }
        // The remaining gates apply only to the clock-driven re-read. With no screen the list is held;
        // the display waking is an edge ``ClaudeCodeMonitorService/stateChangeEvents`` carries.
        guard screenIsAvailable() else { return false }
        // A failed attempt is retried on the failure; there is no list to check.
        guard lastAttemptAnswered else { return true }
        return !everyListedSessionIsStillAlive()
    }

    /// Whether every session in the held list is still the process it was (pid + start time).
    ///
    /// A `SIGKILL`ed session leaves its record and raises no edge; only this finds it. One `sysctl`
    /// per session replaces a `claude agents --json` per ``freshness`` (0.29 s CPU, 187 MB peak,
    /// starts MCP servers; Release, 2026-08-25). A trigger, not an answer: false only lets the
    /// command run, so a pid unanchored or unreadable counts as not alive.
    private func everyListedSessionIsStillAlive() -> Bool {
        cached.allSatisfy { session in
            guard let anchored = livenessAnchors[session.processIdentifier],
                  let started = processStartedAt(session.processIdentifier) else {
                return false
            }
            // Compared against an earlier reading, never the session's reported start; see
            // ``ControllingTerminalGestureReader/systemProcessStartedAt(forProcessIdentifier:)``.
            return started == anchored
        }
    }

    private var isKnownStale: Bool {
        invalidations > answeredInvalidation
    }

    /// Marks the held list wrong so the next reader re-reads it; driven by `~/.claude/sessions`
    /// changing.
    ///
    /// A Desktop session is created by its first prompt, so its whole turn ran before the list named
    /// it and ``ClaudeCodeMonitorService`` dropped it (row 20–23 s after `Stop`; 2026-08-18, 2.1.234).
    /// Not a read itself: it only moves the next reader's deadline, no closer than ``edgeFloor``.
    func invalidate() {
        invalidations += 1
    }

    /// When the command behind the held list started: a session born during the read (a quarter
    /// second, seconds under load) is not in it, so a caller with hook evidence can tell "not caught
    /// up" from "Turn is stale". `.distantFuture` until a read succeeds, so an edge buys no launch
    /// every ``edgeFloor`` while `claude` is not answering.
    func listReadStartedAt() -> Date {
        readStartedAt ?? .distantFuture
    }

    /// Reads again regardless of freshness.
    ///
    /// Single-flighted: one refresh asks twice (rows and mark). The read clears its own claim: a claim
    /// outliving its read stalls `fetchSnapshot`, which also awaits ``presence()``, and stops the
    /// refresh loop for Codex too (CR-Fable-038).
    @discardableResult
    func refresh() async -> [ClaudeCodeSession] {
        guard !monitoringPaused else { return cached }
        if let inFlight { return await inFlight.value }
        readGeneration += 1
        let generation = readGeneration
        let task = Task { await self.readClearingClaim(generation: generation) }
        inFlight = task
        return await task.value
    }

    func startMonitoring() { monitoringPaused = false }
    func stopMonitoring() {
        monitoringPaused = true
        readGeneration += 1
        inFlight?.cancel()
        inFlight = nil
    }

    private func readClearingClaim(generation: Int) async -> [ClaudeCodeSession] {
        let sessions = await performRead(generation: generation)
        if readGeneration == generation { inFlight = nil }
        return sessions
    }

    private func performRead(generation: Int) async -> [ClaudeCodeSession] {
        // Taken before the command goes out, so an edge landing during the read survives it.
        let answering = invalidations
        // Same instant: a reading that began before an event cannot report on it (``ClaudeCodeActivity``).
        let observedAt = clock.now()
        let data = await read()
        guard readGeneration == generation, !Task.isCancelled else { return cached }
        // Stamped even on failure: it paces the next attempt, and an unbooked failure became a run of them.
        attemptedAt = clock.now()
        answeredInvalidation = max(answeredInvalidation, answering)
        // Cleared before either failure returns, so a failed attempt restores the retry cadence.
        lastAttemptAnswered = false
        guard let data else {
            // Keep the last good answer: a failed read is not evidence of absence.
            return cached
        }
        guard let sessions = Self.sessions(in: data, observedAt: observedAt) else {
            Self.log.error("could not decode the session list; keeping the last one")
            return cached
        }
        lastAttemptAnswered = true

        cached = sessions.filter { !isOwnReading($0) }
        // Anchored from the same answer as the list, so both describe one set; a moment later the pid
        // could belong to another process.
        livenessAnchors = Dictionary(
            cached.compactMap { session in
                processStartedAt(session.processIdentifier)
                    .map { (session.processIdentifier, $0) }
            },
            // Two sessions in one pid agree by construction: the value is a property of the pid.
            uniquingKeysWith: { first, _ in first }
        )
        readAt = clock.now()
        readStartedAt = observedAt
        return cached
    }

    /// Whether an entry is this app's own quota reading, not a user session.
    private func isOwnReading(_ session: ClaudeCodeSession) -> Bool {
        guard let ignoredWorkingDirectoryPath else { return false }
        return session.workingDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path == ignoredWorkingDirectoryPath
    }

    /// The sessions in one run of stdout, or nil when there are none.
    ///
    /// The array is found, not assumed to be the whole stream: a user's MCP server wrote a log line
    /// to this stdout (2 runs in 5), and an undecodable list ages the product towards `Disconnected`.
    /// - Parameter observedAt: When the producing command started. Defaults to the distant past
    ///   (fail-closed), so such a list can never end a turn.
    nonisolated static func sessions(
        in data: Data,
        observedAt: Date = .distantPast
    ) -> [ClaudeCodeSession]? {
        guard let reported = reportedEntries(in: data) else { return nil }
        // Total: ``reportedEntries(in:)`` already refused arrays with an identity-less entry.
        return reported.compactMap { entry in
            guard let identity = entry.identity else { return nil }
            return ClaudeCodeSession(
                sessionID: identity.sessionID,
                processIdentifier: identity.pid,
                workingDirectory: URL(fileURLWithPath: identity.cwd),
                // Reported in milliseconds.
                startedAt: Date(timeIntervalSince1970: identity.startedAt / 1000),
                name: entry.name,
                // An unknown word is no activity: guessing its side of "working" can retire a live turn.
                activity: entry.status
                    .flatMap(ClaudeCodeActivity.State.init(rawValue:))
                    .map { ClaudeCodeActivity(state: $0, observedAt: observedAt) }
            )
        }
    }

    /// The entries the command reported, from wherever in the stream its array is.
    ///
    /// - Every balanced `[ ... ]` is offered to the decoder in opening order; log lines like
    ///   `[INFO] ...` broke a first-`[`-to-last-`]` span (CR-Fable-039).
    /// - A candidate is taken only if every entry has a ``Reported/identity``; otherwise any object
    ///   array (`tools: [{"name": "read_file"}]`) read as a known-empty list (CR-Codex-001).
    ///   Refusing costs one reading and ages to `unknown`, not `closed`.
    /// - An empty decode is the last resort, and only from a span that stands alone (whole stream,
    ///   or alone on its line): `[]` reports the product closed.
    nonisolated private static func reportedEntries(in data: Data) -> [Reported]? {
        let decoder = JSONDecoder()
        // The ordinary case. Still gated: a lone `[{"tools": []}]` can be the whole stream.
        if let whole = try? decoder.decode([Reported].self, from: data),
           isSessionList(whole) {
            return whole
        }
        var empty: [Reported]?
        for span in arraySpans(in: data) {
            guard let entries = try? decoder.decode([Reported].self, from: Data(data[span])),
                  isSessionList(entries)
            else { continue }
            if !entries.isEmpty { return entries }
            if empty == nil, standsAlone(span, in: data) { empty = entries }
        }
        return empty
    }

    /// Whether a span is alone on its line apart from blank space; asked only of an empty span.
    nonisolated private static func standsAlone(
        _ span: ClosedRange<Data.Index>,
        in data: Data
    ) -> Bool {
        func isBlank(_ range: Range<Data.Index>) -> Bool {
            data[range].allSatisfy {
                $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t")
                    || $0 == UInt8(ascii: "\r") || $0 == UInt8(ascii: "\n")
            }
        }
        let lineStart = data[..<span.lowerBound]
            .lastIndex(of: UInt8(ascii: "\n"))
            .map(data.index(after:)) ?? data.startIndex
        let afterSpan = data.index(after: span.upperBound)
        let lineEnd = data[afterSpan...]
            .firstIndex(of: UInt8(ascii: "\n")) ?? data.endIndex
        return isBlank(lineStart ..< span.lowerBound) && isBlank(afterSpan ..< lineEnd)
    }

    /// Whether a decoded array can be the list `claude agents --json` prints; `[]` passes.
    nonisolated private static func isSessionList(_ entries: [Reported]) -> Bool {
        entries.allSatisfy { $0.identity != nil }
    }

    /// Every balanced `[ ... ]` in the stream, in opening order. Brackets inside JSON strings do not
    /// count (`~/Projects/[wip]`); string state resets at each newline so a stray quote in a log line
    /// cannot swallow the array. An unclosed bracket is never offered.
    nonisolated private static func arraySpans(in data: Data) -> [ClosedRange<Data.Index>] {
        var open: [Data.Index] = []
        var spans: [ClosedRange<Data.Index>] = []
        var inString = false
        var escaped = false
        for index in data.indices {
            if escaped {
                escaped = false
                continue
            }
            switch data[index] {
            case UInt8(ascii: "\n"):
                inString = false
            case UInt8(ascii: "\\") where inString:
                escaped = true
            case UInt8(ascii: "\""):
                inString.toggle()
            case UInt8(ascii: "[") where !inString:
                open.append(index)
            case UInt8(ascii: "]") where !inString:
                if let start = open.popLast() { spans.append(start ... index) }
            default:
                break
            }
        }
        // Recorded as they close (inner first); sorted so the outermost is offered first.
        return spans.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// Runs `claude agents --json`, documented to list active sessions without a TTY.
    ///
    /// It already drops dead sessions by checking `pid` + `procStart` as a pair (measured, 2.1.229).
    /// Do not redo it: `--json` omits `procStart`, so that would need the private session-file
    /// schema (`AGENTS.md` §8).
    private static func runOfficialCommand() async -> Data? {
        // 10 s against a 30 s re-read: slower is stale on arrival, and a failed read keeps the last list.
        await ClaudeCommand.run(["agents", "--json"], timeout: 10)
    }
}
