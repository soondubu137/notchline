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

/// Whether a session is working, and the moment that was true.
///
/// Claude Code derives this in its own terminal UI from whether a turn is in
/// flight and whether a dialog is open, and publishes it with each session --
/// `busy`, `waiting` while a prompt sits in front of the user, `idle`, and
/// `shell` for an idle session that still has a shell running. Measured
/// against 2.1.235 on 2026-08-18: a submitted prompt reached `busy` within
/// 150 ms, an approval dialog reached `waiting` (`waitingFor: "permission
/// prompt"`) within 150 ms, and `Esc` reached `idle` within 160 ms -- with the
/// dialog still open, which is the case no hook reports at all (CC-019).
///
/// **This says nothing about which turn.** It cannot: there is no turn id
/// anywhere in the command's output. So it is never allowed to open, name or
/// describe a turn -- only to say that whatever turn the reducer is holding is
/// no longer being worked on. Everything else about a turn still comes from the
/// hooks and from nowhere else.
nonisolated struct ClaudeCodeActivity: Sendable, Equatable {
    /// The four words Claude Code uses. Anything else is not understood, and
    /// an activity that is not understood is not reported at all.
    enum State: String, Sendable, Equatable {
        case busy
        case waiting
        case idle
        case shell
    }

    let state: State
    /// When the command that read this **started running**, not when it
    /// answered.
    ///
    /// The stricter of the two, and deliberately: it is what lets a reader say
    /// "this reading is entirely newer than that event". Stamping the answer
    /// would let a command that started before a turn did, and returned after,
    /// report that turn's session as idle.
    let observedAt: Date

    /// Whether a turn could still be running behind this.
    ///
    /// `waiting` counts as working: the turn is alive and parked on the user,
    /// which is a state the reducer already owns and must not be overruled.
    var isWorking: Bool {
        state == .busy || state == .waiting
    }
}

/// Which Claude Code sessions exist right now.
///
/// **Identity first, and one bounded fact about state.** This answers "which
/// sessions are there"; turn state comes from the Turn reducer and only from
/// there. The one exception is ``ClaudeCodeActivity``, which the command does
/// report and which this used to drop on the floor -- the comment here claimed
/// for a while that the output was "byte-identical whether the session is
/// mid-turn or sitting idle", and that was measured false on 2026-08-18: it
/// carries `status` and `waitingFor`. It is carried because it is the only
/// signal a *user interrupt* produces anywhere (CC-019, #38): no hook fires,
/// and the session simply stops saying it is busy.
///
/// Even so it is not turn state. It names no turn, so it can only ever end the
/// one the reducer is already holding -- see ``ClaudeCodeActivity``.
///
/// It matters more here than the equivalent would on the Codex side: it is the
/// only way a row whose session died can be retired, because `SessionEnd` is
/// deliberately not registered — see ``ClaudeCodeHookVocabulary``.
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
    /// When the reading behind the held list *began*, or `.distantFuture` for
    /// a source that cannot be out of date.
    ///
    /// The left-hand side of "this event proves the list is wrong". A reading
    /// that started before a session existed cannot be evidence that it does
    /// not, so a caller holding a Turn the list does not name can ask whether
    /// its evidence is newer than the reading and, if it is, say so —
    /// ``invalidate()`` above.
    ///
    /// `.distantFuture` rather than `nil` for a source that reads live state:
    /// nothing a caller can hear is newer than an answer taken on the spot, so
    /// the comparison is simply never true. The registry answers the same way
    /// before its first successful read, which is the fail-closed direction —
    /// a `claude` that never answers must not be asked again on every event.
    ///
    /// **Without a default implementation**, for the reason ``invalidate()``
    /// above has none: an actor satisfies an `async` requirement with a
    /// synchronous member, and a default would then be what the caller gets.
    func listReadStartedAt() async -> Date
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

/// Finds the `claude` executable the same way a user's shell would, and then
/// in the one place a shell would never look.
///
/// **A machine can be running Claude Code and have no `claude` on `PATH`.**
/// Claude Desktop ships its own copy of the CLI and runs desktop-hosted
/// sessions with it; installing the terminal command is a separate step in its
/// install hub, and plenty of people never take it. Every candidate below the
/// override used to assume they had — so on a Desktop-only machine this
/// returned `nil`, `claude agents --json` never ran, presence never left
/// `unknown`, and Claude Code drew no mark and no row while its hooks were
/// registered and firing perfectly. The settings card said `Connected` the
/// whole time, because it was reporting the registration and nothing else.
///
/// Desktop's copy answers the same command against the same
/// `~/.claude/sessions`, verified against `2.1.258` on 2026-09-02, so nothing
/// downstream has to know which one replied. It is tried **last**: a user who
/// installed the CLI themselves is the one who updates it, and that is the one
/// they drive.
enum ClaudeExecutableLocator {
    /// An override for tests and for a user whose install is somewhere unusual.
    static let overrideEnvironmentKey = "NOTCHLINE_CLAUDE_PATH"

    /// Where Claude Desktop keeps the CLI versions it has downloaded.
    ///
    /// One directory per version, and **more than one at a time**: measured
    /// here on 2026-09-02, `2.1.255` and `2.1.258` sat side by side the day
    /// after an update, with `2.1.247` already collected. So this is a choice
    /// rather than a lookup, and it is made on the version in the name.
    nonisolated private static let desktopVersionsDirectoryName = "claude-code"

    /// The path inside one of those version directories.
    ///
    /// The bundle is `com.anthropic.claude-code`, which is the same fact
    /// ``ClaudeCodeNavigator`` already depends on from the other end -- it
    /// walks a session's ancestors and has to start at the *parent*, because a
    /// desktop-hosted `claude` is itself inside this bundle and would otherwise
    /// be found hosting itself.
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
        // A login shell's PATH is not this process's PATH, so this is a
        // fallback rather than the primary route.
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            candidates.append(
                URL(fileURLWithPath: String(directory))
                    .appendingPathComponent("claude")
            )
        }
        // And the copy that is there whether or not the user ever installed
        // the command themselves.
        candidates.append(
            contentsOf: desktopBundledExecutables(
                environment: environment,
                fileManager: fileManager
            )
        )
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    /// Claude Desktop's own CLI copies, newest version first.
    ///
    /// Nothing here is filtered on the name looking like a version: an entry
    /// whose name this cannot parse is still offered, last, because a naming
    /// scheme this app failed to anticipate is a reason to rank a directory
    /// low and never a reason to refuse a working executable. `.verified` --
    /// the sha256 Desktop drops beside a version it has checked -- is
    /// deliberately not read: what this needs to know is whether a file will
    /// run, and `isExecutableFile` answers that without borrowing a meaning
    /// from a marker nothing documents.
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

    /// Version-directory order, on the numbers rather than on the string.
    ///
    /// `2.1.9` sorts above `2.1.10` on any string comparison, which is the one
    /// mistake this ordering exists to avoid. A name that is not all-numeric
    /// dotted components compares as older than every one that is, and two of
    /// those fall back to the string so the order is total and stable.
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
///
/// **The deadline is therefore on the read, not on the child** (CR-Fable-038).
/// Killing the child does not end `readToEnd`, because EOF is not the child's
/// to give: it arrives when the *last* copy of the write end closes, and
/// anything the child started that inherited its stdout holds one. A deadline
/// that stops at the child left the original symptom exactly where it was for
/// that case, and left it worse -- the session list single-flights its read,
/// so one orphan wedged every later caller in *both* products behind a read
/// that was never going to finish. Reading now stops at EOF, or a
/// ``drainGrace`` after the child is gone, or at a ``readGrace`` past the
/// child's own deadline, whichever comes first.
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

    /// How long stdout is still read after the child itself has gone.
    ///
    /// Everything the child wrote is already in the pipe by the time it exits,
    /// so this is a margin for reading that out rather than a wait for more.
    /// Whoever is still holding the write end afterwards is not the process
    /// this app asked a question of, and waiting for them to close it is
    /// waiting for nothing -- for ever, in the case this exists for, and for
    /// the whole of `timeout` even once ``readGrace`` bounds it, which at ten
    /// and thirty seconds is long enough on its own to make the product look
    /// frozen.
    private static let drainGrace: TimeInterval = 0.25

    /// How long past the child's own deadline stdout is still read.
    ///
    /// Only ever reached when the two rules above have both failed to end the
    /// read: the child is signalled at its deadline and killed a ``killGrace``
    /// later, and a dead child closes the window above. What is left is a
    /// child that outlives `SIGKILL` or a death this process is never told
    /// about -- neither of which is a thing to have no bound for, since the
    /// bound is the whole point of the exercise.
    private static let readGrace: TimeInterval = killGrace + 1

    /// The longest `poll` may sleep while the child is still running.
    ///
    /// Purely so that the child going away is noticed promptly. The pipe
    /// closing wakes `poll` on its own and needs no slicing.
    private static let pollSlice: Int32 = 250

    /// How long a finished child's pid is still remembered as this app's own.
    ///
    /// The record is removed just *before* the child exits, and the edge that
    /// reports the removal is debounced behind it, so forgetting the pid the
    /// instant `waitUntilExit` returns would race the edge it exists to
    /// explain. Seconds rather than minutes because the guarantee wanted is
    /// the narrow one: a pid cannot be reused while its process is alive, so
    /// the only window where this could mistake somebody else's session for
    /// this app's is the grace itself.
    private static let ownPIDGrace: TimeInterval = 5

    /// The `claude` processes this app is running, and the ones it has just
    /// finished running.
    ///
    /// Claude Code files every session as `~/.claude/sessions/<pid>.json`, and
    /// this app's own quota reading is a session like any other. So the record
    /// that reading leaves, and its removal a few seconds later, look to the
    /// sessions watcher exactly like a user's session appearing and going
    /// away -- and each of those edges told the registry its list was wrong,
    /// which is a `claude` launch: a Node process and about 0.4 s of a core, to
    /// re-read a list whose only change was a session this app started and
    /// already filters out. Measured on a Release launch: one extra launch
    /// 3.5 s in, and one per quota reading for as long as the app runs.
    ///
    /// The pid is what tells them apart and it costs nothing to know, because
    /// it is the pid of a process this app launched itself. Nothing here reads
    /// a session file; the only thing borrowed from Claude Code is that a
    /// record is *named* after its pid, which this app already depends on to
    /// watch those records at all.
    nonisolated(unsafe) private static var ownPIDs: Set<Int32> = []
    private static let ownPIDsLock = NSLock()

    /// Whether an entry of the sessions directory belongs to a `claude` this
    /// app launched.
    ///
    /// Takes the file name rather than a pid because both of the entries a
    /// session leaves -- `<pid>.json` and `<pid>.<hash>.key` -- lead with it,
    /// and a name that does not lead with a pid at all is somebody else's by
    /// construction.
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
    ///   - timeout: How long the child may take before it is killed. A killed
    ///     child reports failure, which is a thing every caller here already
    ///     knows how to degrade to. Reading its stdout is bounded separately
    ///     and can end sooner -- see ``drain(_:of:until:)``.
    ///   - executable: Overridden only by the tests that have to watch a
    ///     command outstay a deadline or leave its stdout open behind it,
    ///     which need ones that reliably do.
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

        // Noted for every command rather than only the one that leaves a
        // session record, because which commands leave one is Claude Code's
        // business and not something to encode here. A pid that never appears
        // in the sessions directory is simply never asked about, and is
        // forgotten a few seconds after the child exits either way.
        let launched = process.processIdentifier
        noteOwn(pid: launched)
        defer {
            queue.asyncAfter(deadline: .now() + ownPIDGrace) {
                forgetOwn(pid: launched)
            }
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

        let (data, outcome) = drain(
            output.fileHandleForReading,
            of: process,
            until: .now() + timeout + readGrace
        )
        switch outcome {
        case .endOfFile:
            break
        case .outlivedByPipe:
            // Not a failure. The child answered and exited; something it
            // started is holding the pipe it no longer needs. Whether the
            // answer is usable is the parser's question, exactly as it is
            // when the pipe closes tidily.
            log.error("claude \(arguments.first ?? "") left its stdout open behind it")
        case .deadline:
            log.error("claude \(arguments.first ?? "") outlived its read deadline; abandoning it")
            // `expire` runs on this same queue and may not have got there.
            // Nothing below this line is bounded while the child is alive.
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
        /// The child is gone and the pipe is not: something it started
        /// inherited stdout and is still holding it. What the child wrote is
        /// already here.
        case outlivedByPipe
        /// Neither the child nor the pipe finished in time.
        case deadline
    }

    /// Reads the child's stdout, under a deadline of its own.
    ///
    /// `FileHandle.readToEnd()` cannot be given one, and the thing it waits
    /// for is not the child -- see this type's own documentation, and
    /// ``drainGrace`` and ``readGrace`` for the two ways out of here that are
    /// not EOF.
    ///
    /// Read straight off the descriptor into one reused buffer, which is also
    /// why the `autoreleasepool` this used to need has gone: nothing on this
    /// path hands back an autoreleased `Data` any more, for the same reason
    /// ``ClaudeCodeTokenCounter`` reads its chunks this way.
    private static func drain(
        _ handle: FileHandle,
        of process: Process,
        until deadline: DispatchTime
    ) -> (data: Data, outcome: ReadOutcome) {
        let descriptor = handle.fileDescriptor
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        // Armed the first time the child is seen to have gone, and pushed back
        // by anything that arrives after that.
        var quiet: DispatchTime?

        while true {
            if quiet == nil, !process.isRunning { quiet = .now() + drainGrace }
            let now = DispatchTime.now()
            if now >= deadline { return (data, .deadline) }
            if let quiet, now >= quiet { return (data, .outlivedByPipe) }

            // Sliced while the child is alive so its exit is noticed; once it
            // is gone there is nothing left to notice but bytes, and `poll`
            // reports those itself.
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
                // A descriptor this app opened itself does not fail `poll` for
                // anything a retry would mend, so what is in hand is the
                // answer -- and the child's exit status still has to agree
                // before any caller is given it.
                return (data, .endOfFile)
            }

            let count = buffer.withUnsafeMutableBytes {
                read(descriptor, $0.baseAddress, $0.count)
            }
            if count > 0 {
                data.append(contentsOf: buffer[..<count])
                // A child that filled the pipe before exiting is read out
                // however many passes that takes; ``readGrace`` is what bounds
                // a holder that goes on writing.
                if quiet != nil { quiet = .now() + drainGrace }
            } else if count == 0 {
                return (data, .endOfFile)
            } else if errno != EINTR, errno != EAGAIN {
                return (data, .endOfFile)
            }
        }
    }
}

actor ClaudeCodeSessionRegistry: ClaudeCodeSessionListing {
    private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "ClaudeCodeSessionRegistry"
    )

    /// The shape `claude agents --json` prints.
    ///
    /// Every field is optional because the schema is Claude Code's to change
    /// and a field this app has never seen must not cost it the whole list.
    /// That tolerance is exactly why ``identity`` has to exist: a type this
    /// permissive decodes *any* JSON object, so a successful decode says
    /// nothing about what was decoded -- see ``reportedEntries(in:)``.
    private struct Reported: Decodable {
        let pid: Int32?
        let cwd: String?
        let kind: String?
        let startedAt: Double?
        let sessionId: String?
        let name: String?
        /// Absent for a session the Claude Code desktop app hosts, always: it
        /// drives the CLI over `stream-json` with no terminal UI, and the
        /// terminal UI is what publishes this (#41). Absent is not `idle`.
        let status: String?

        /// The four fields without which an entry cannot be a session at all.
        ///
        /// Asked in one place because two callers ask it for opposite reasons:
        /// ``reportedEntries(in:)`` to decide whether a decoded array *is* a
        /// session list, ``sessions(in:)`` to build the rows from one that is.
        /// Two spellings of the same question could drift, and the shape that
        /// drift takes is an entry that passes the gate and then quietly
        /// vanishes from the answer -- which is the bug the gate is for.
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
    /// When a process started, or nil when there is no such process.
    ///
    /// The whole of the ghost check — see ``everyListedSessionIsStillAlive()``.
    /// Injected so a test can kill a session without killing a process.
    private let processStartedAt: @Sendable (Int32) -> Date?
    /// Whether there is a screen the user could read the notch on.
    ///
    /// Gates the *clock-driven* re-read and nothing else. See
    /// ``isDueForReading``.
    private let screenIsAvailable: @Sendable () -> Bool
    private let clock: any MonitorClock
    private let freshness: TimeInterval
    private let edgeFloor: TimeInterval
    private let trustCeiling: TimeInterval
    /// The start instant of each listed session's process, read once when the
    /// list was read.
    ///
    /// Empty for any pid the kernel would not answer for at anchoring time,
    /// which is what makes ``everyListedSessionIsStillAlive()`` refuse rather
    /// than guess. Rebuilt with every answered read, so a pid that leaves the
    /// list leaves this too.
    private var livenessAnchors: [Int32: Date] = [:]
    /// Resolved once, because it is compared against every entry of every read.
    private let ignoredWorkingDirectoryPath: String?
    private var cached: [ClaudeCodeSession] = []
    /// When the command last *answered*. Decides how long the answer is
    /// believed.
    private var readAt: Date?
    /// When the command behind the held list *started*. Decides what that list
    /// can be held to have known -- see ``listReadStartedAt()``.
    private var readStartedAt: Date?
    /// When the command was last *run*, answer or none. Decides when it is run
    /// again, which is a different question -- see ``liveSessions()``.
    private var attemptedAt: Date?
    /// Whether the last attempt came back with a list this registry could read.
    ///
    /// Separates the two ways of holding an empty list, which look identical in
    /// ``cached`` and mean opposite things: one is `claude` having answered
    /// "nothing is running", the other is nobody having answered at all. The
    /// first is knowledge and is held until something contradicts it; the
    /// second is ignorance and has to keep asking. See ``liveSessions()`` and
    /// ``presence()``.
    private var lastAttemptAnswered = false
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
    ///     desktop session plus two idle ones (measured 2026-08-18). The reason
    ///     given here used to be that those files are written only when a
    ///     session starts or stops; that is half right. A CLI session rewrites
    ///     its own record on every `busy`/`waiting`/`idle` flip, several times
    ///     a turn -- but in place, with no rename, and a directory vnode source
    ///     does not fire for a write *inside* the directory. Measured
    ///     2026-08-18 with this app's own event mask: an in-place rewrite
    ///     produced no directory event and a create, a delete or an atomic
    ///     replace produced one each. So the edges stay as rare as the number
    ///     above says, and the flips reach this app only when something reads
    ///     the list again.
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
    ///   exactly as it reports a human's (measured on 2.1.234, 2026-08-18). It
    ///   therefore **answers presence** — a user with no Claude Code open at all
    ///   had the product light up in the notch every five minutes because this
    ///   app had just run `claude` itself.
    ///
    ///   It used to cost a row as well. Its transcript carries two `user`
    ///   records and **no `assistant` record at all** — a slash command never
    ///   reaches the model, `num_turns: 0` — so nothing ever supplied the
    ///   `stop_reason` that ends a turn, and the cold-start reconstruction read
    ///   that as a *Running* turn named after this app's own folder, held for a
    ///   whole freshness window against a subprocess that lived a second or
    ///   two. That reconstruction has been removed, so this filter now answers
    ///   presence alone.
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
    ///
    /// **The ceiling bounds failing reads, not elapsed time**, and it is
    /// spelled that way here because those stopped being the same thing. An
    /// answer this registry has deliberately not re-asked for -- see
    /// ``liveSessions()`` -- is not stale evidence, it is uncontradicted
    /// evidence: nothing has failed, and every route by which it could have
    /// become wrong reports an edge. Ageing it out would be reporting that we
    /// do not know something we do know and simply chose not to buy again. Once
    /// an attempt does fail the ceiling applies exactly as it always did, and
    /// with the same arithmetic behind it: three consecutive failures a
    /// ``freshness`` apart.
    func presence() async -> AgentPresence {
        let sessions = await liveSessions()
        guard lastAttemptAnswered || isWithinTrustCeiling else { return .unknown }
        return sessions.isEmpty ? .closed : .open
    }

    /// Whether the last answer is still recent enough to decide presence.
    ///
    /// False when there has never been one, which is the fail-closed end of the
    /// same rule: a registry that has never been answered knows nothing.
    private var isWithinTrustCeiling: Bool {
        guard let readAt else { return false }
        return clock.now().timeIntervalSince(readAt) <= trustCeiling
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
    ///
    /// **And a known-empty list is not re-read at all.** ``freshness`` is a
    /// ceiling on how stale an answer may get, never a reason to buy one
    /// nobody asked for: the store wakes at least every
    /// ``MonitorTiming/heartbeatInterval``, that window has always lapsed by
    /// the time it does, and so this command ran every 30-60 seconds for the
    /// life of the process -- on an idle machine, with no session open and the
    /// screen locked (CR-Fable-002). It is not a cheap command: 0.26-0.33s of
    /// CPU measured here (`/usr/bin/time -p`, user + sys, reaped children
    /// included), and it **starts the user's MCP servers** on the way -- which
    /// is why ``arraySpans(in:)`` exists -- so each spawn is a process tree,
    /// not a process. At one every 30-60 seconds that is 0.4%-1.1% of a core
    /// forever, the single largest steady-state cost in a product whose bar is
    /// "barely noticeable".
    ///
    /// What it bought was a re-confirmation of an empty list, and every route
    /// out of empty already reports itself: a session's record appears in
    /// `~/.claude/sessions` when it starts (a create fires a directory event --
    /// measured, unlike the in-place rewrites that do not), and a hook event
    /// naming a session the list does not have is itself proof that session
    /// exists. So an answered-empty list is held until something says
    /// otherwise, and the clock keeps pacing every other case:
    ///
    /// - **listed sessions** are re-read on ``freshness``, and then only when
    ///   the cheap version of the question says the answer could have changed.
    ///   The one route to retiring a row that raises no edge is a `SIGKILL`ed
    ///   session, which leaves its record behind; the command sees that through
    ///   its own `pid` + `procStart` check, and so can this app, for one
    ///   `sysctl` a session instead of a process tree -- see
    ///   ``everyListedSessionIsStillAlive()``. So the clock still says *when*
    ///   the question may be asked and the kernel says whether it is worth
    ///   paying `claude` to answer it;
    /// - **a failed or unreadable attempt** is retried on ``freshness``, which
    ///   is the cadence ``trustCeiling`` counts its three failures in. The
    ///   liveness check does not gate this one: there is no list to check, and
    ///   the point of the retry is the failure rather than the contents;
    /// - **an edge** is answered no sooner than ``edgeFloor``, empty or not.
    ///
    /// **Only the clock's branch is gated on there being a screen.** An edge is
    /// a report that the list is wrong and is answered whether or not anybody
    /// is looking; the cadence is a guess about staleness, and a guess bought
    /// while the display is asleep is bought for nobody. The display waking is
    /// itself one of the edges the service merges, so the reading arrives with
    /// the user rather than after them.
    func liveSessions() async -> [ClaudeCodeSession] {
        guard isDueForReading else { return cached }
        return await refresh()
    }

    /// Whether the command is run for the caller now standing at the door.
    private var isDueForReading: Bool {
        guard let attemptedAt else { return true }
        let waited = clock.now().timeIntervalSince(attemptedAt)
        if isKnownStale { return waited >= edgeFloor }
        // Nothing has reported this wrong, and there is nothing in it that
        // could go wrong quietly. Holding it is the whole of the fix.
        if lastAttemptAnswered, cached.isEmpty { return false }
        guard waited >= freshness else { return false }
        // Both of the remaining gates are on the *clock-driven* re-read alone,
        // which is the branch this line ends. An edge left above them
        // deliberately: an edge is somebody reporting that the list has stopped
        // being true, and neither a dark screen nor a live pid is an argument
        // against a report.
        //
        // Nobody can read the notch, so nothing on it has to be right yet. The
        // list is held instead, exactly as a known-empty one is, and the
        // display waking is one of the edges
        // ``ClaudeCodeMonitorService/stateChangeEvents`` already carries -- so
        // the reading a locked night would have bought thirty seconds at a time
        // is bought once, when somebody is there to see it.
        guard screenIsAvailable() else { return false }
        // An attempt that did not answer is retried on the failure, not on the
        // contents: there is no list the check below could speak for, and the
        // cadence this restores is the one ``trustCeiling`` counts its three
        // consecutive failures in.
        guard lastAttemptAnswered else { return true }
        return !everyListedSessionIsStillAlive()
    }

    /// Whether every session in the held list is still the process it was.
    ///
    /// **This is the whole reason listed sessions were re-read on a clock.**
    /// Every other way the list can go wrong reports an edge: a session
    /// starting or ending writes `~/.claude/sessions/<pid>.json`, and a hook
    /// event naming a session the list does not have is proof in itself. The
    /// exception is a session that was `SIGKILL`ed, which leaves its record
    /// behind and raises nothing at all -- so the list goes on naming a ghost,
    /// and only a `pid` + start-time check can tell.
    ///
    /// The command does that check too, and that is what the cadence was
    /// buying: one `claude agents --json` every ``freshness`` for the life of
    /// every listed session. Measured in Release on 2026-08-25 that is 0.29 s
    /// of CPU and 187 MB of peak resident memory per run, and it starts the
    /// user's MCP servers on the way, so it is a process tree rather than a
    /// process. This asks the same question of the kernel directly: one
    /// `sysctl` per listed session, microseconds, no subprocess and nothing
    /// started on anybody's behalf.
    ///
    /// **It is a trigger, not an answer.** A false here does not retire
    /// anything -- it only lets the command run, which is what decides. So the
    /// worst a wrong reading can do is buy a reading, and the direction is
    /// chosen accordingly: a pid this could not anchor when the list arrived,
    /// or cannot read now, counts as *not* still alive and falls straight
    /// through to the command, which is the behaviour that was there before.
    ///
    /// It also makes a ghost show up *sooner* rather than later. The check runs
    /// on whatever refresh comes next instead of on the next freshness
    /// boundary, and refreshes are driven by hook events -- so the kill of a
    /// busy session is now noticed in the same second, where before it waited
    /// out up to a full ``freshness``.
    private func everyListedSessionIsStillAlive() -> Bool {
        cached.allSatisfy { session in
            guard let anchored = livenessAnchors[session.processIdentifier],
                  let started = processStartedAt(session.processIdentifier) else {
                return false
            }
            // Compared against an earlier reading of the same value, never
            // against the session's own reported start -- see
            // ``ControllingTerminalGestureReader/systemProcessStartedAt(forProcessIdentifier:)``.
            return started == anchored
        }
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

    /// When the command behind the held list started running.
    ///
    /// The *start*, not the answer, because that is the instant the list stops
    /// being able to speak for: `claude agents --json` takes a quarter of a
    /// second alone and seconds under load, and a session born inside that
    /// window is one this reading never saw. Reported so a caller holding
    /// evidence of its own -- a hook event names a session, and a session that
    /// sends events exists -- can tell "the list has not caught up" from "the
    /// list is right and the Turn is stale".
    ///
    /// `.distantFuture` until a read has succeeded, so a caller compares
    /// against an answer that cannot be beaten rather than against no answer
    /// at all. That is deliberate in the fail-closed direction: while `claude`
    /// is not answering, an edge would buy a launch every ``edgeFloor`` for a
    /// list that is not going to change.
    func listReadStartedAt() -> Date {
        readStartedAt ?? .distantFuture
    }

    /// Reads again regardless of freshness, for when something said to.
    ///
    /// Single-flighted: an actor suspends at every `await`, so without this two
    /// callers that arrive while the command is out would each start one of
    /// their own. One refresh asks twice by design -- once for the rows and
    /// once for the mark -- so that was not a rare interleaving but the
    /// ordinary path.
    ///
    /// **The read clears the claim itself**, rather than leaving it to
    /// whoever is waiting on it. The claim outliving its read is the worst
    /// failure this file has: every later caller is sent to `await` a task
    /// that has already stopped being able to answer, and `fetchSnapshot`
    /// waits on this and on ``presence()`` together, so the refresh loop
    /// stops -- for Codex as well (CR-Fable-038). ``ClaudeCommand`` is what
    /// makes that unreachable now, by bounding the read; this is here so that
    /// the invariant is held where it can be read, and not by an argument
    /// about a caller two types away.
    @discardableResult
    func refresh() async -> [ClaudeCodeSession] {
        if let inFlight { return await inFlight.value }
        readGeneration += 1
        let generation = readGeneration
        let task = Task { await self.readClearingClaim(generation: generation) }
        inFlight = task
        return await task.value
    }

    private func readClearingClaim(generation: Int) async -> [ClaudeCodeSession] {
        let sessions = await performRead()
        if readGeneration == generation { inFlight = nil }
        return sessions
    }

    private func performRead() async -> [ClaudeCodeSession] {
        // Taken immediately before the command goes out, so an edge that lands
        // while it is running survives it: that read cannot have seen what the
        // edge is reporting -- see ``invalidations``.
        let answering = invalidations
        // The same instant, and the same reasoning, for what the answer is
        // allowed to prove: a reading that *began* before an event cannot
        // report on the state that event describes. See ``ClaudeCodeActivity``.
        let observedAt = clock.now()
        let data = await read()
        // Stamped whether or not there was an answer: this is what paces the
        // next attempt, and a failure that booked no time at all is what let
        // one failed read become a run of them.
        attemptedAt = clock.now()
        answeredInvalidation = max(answeredInvalidation, answering)
        // Cleared before either failure below can return, so an attempt that
        // did not answer puts this registry back on the retry cadence however
        // long it had been holding a quiet answer.
        lastAttemptAnswered = false
        guard let data else {
            // Keep the last good answer rather than reporting that every
            // session vanished: a failed read is not evidence of absence, and
            // treating it as such would retire every row at once.
            return cached
        }
        guard let sessions = Self.sessions(in: data, observedAt: observedAt) else {
            Self.log.error("could not decode the session list; keeping the last one")
            return cached
        }
        lastAttemptAnswered = true

        cached = sessions.filter { !isOwnReading($0) }
        // Anchored from the answer that produced the list, so the two can never
        // describe different sets: a pid that has just left the list leaves
        // this with it, and one that has just joined is anchored before
        // anything can ask about it. Read here rather than lazily because the
        // kernel's answer is only an identity while the process it names is the
        // one the command reported -- a moment later the pid could be somebody
        // else's, and an anchor taken then would certify the wrong process for
        // as long as it lived.
        livenessAnchors = Dictionary(
            cached.compactMap { session in
                processStartedAt(session.processIdentifier)
                    .map { (session.processIdentifier, $0) }
            },
            // Two sessions in one process is not a shape this app has seen, and
            // if it ever appears the two agree by construction -- the value is
            // a property of the pid, not of the session.
            uniquingKeysWith: { first, _ in first }
        )
        readAt = clock.now()
        readStartedAt = observedAt
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
    /// this array is pretty-printed across many lines; ``arraySpans(in:)`` does.
    ///
    /// Made `static` and non-private so the rule can be tested against captured
    /// bytes rather than by running anything, exactly as the quota's parser is.
    /// - Parameter observedAt: When the command that produced these bytes
    ///   started. Defaults to the distant past, which is the fail-closed
    ///   answer: a list parsed without a reading behind it reports an activity
    ///   old enough to prove nothing, so it can never end a turn.
    nonisolated static func sessions(
        in data: Data,
        observedAt: Date = .distantPast
    ) -> [ClaudeCodeSession]? {
        guard let reported = reportedEntries(in: data) else { return nil }
        // Total, not selective: ``reportedEntries(in:)`` has already refused
        // any array holding an entry without an identity, so nothing is
        // dropped here. It is written as a `compactMap` only because the
        // compiler cannot know that.
        return reported.compactMap { entry in
            guard let identity = entry.identity else { return nil }
            return ClaudeCodeSession(
                sessionID: identity.sessionID,
                processIdentifier: identity.pid,
                workingDirectory: URL(fileURLWithPath: identity.cwd),
                // Reported in milliseconds.
                startedAt: Date(timeIntervalSince1970: identity.startedAt / 1000),
                name: entry.name,
                // A word this app does not know is no activity at all. The
                // vocabulary is Claude Code's and it can grow; guessing which
                // side of "working" a new word falls on is how a live turn
                // gets retired.
                activity: entry.status
                    .flatMap(ClaudeCodeActivity.State.init(rawValue:))
                    .map { ClaudeCodeActivity(state: $0, observedAt: observedAt) }
            )
        }
    }

    /// The entries the command reported, taken from wherever in the stream its
    /// array happens to be.
    ///
    /// **The decoder decides where the array starts, because nothing else can.**
    /// This used to take one span, from the first `[` to the last `]`, on the
    /// argument that a span taken that way is never a line printed before or
    /// after the array. That only holds while no surrounding line contains a
    /// bracket -- true of the single pollutant that was measured, and false of
    /// the shape log lines usually have: `[INFO] ...`, `[2026-08-21T...] ...`,
    /// `[server] ...`. One of those above the array starts the span inside log
    /// text, one below it ends the span past the array, and either way the
    /// decode fails -- which at this boundary is not one lost reading but the
    /// product ageing into `Disconnected` with its sessions still running
    /// (CR-Fable-039). The defence held against the pollutant it was written
    /// from and gave way to the commonest form of the same thing.
    ///
    /// So every balanced `[ ... ]` is offered to the decoder in the order they
    /// open, and the first one that is a session list is the answer.
    ///
    /// **An empty decode is the last answer taken, never the first.** `[]` is a
    /// plausible thing for a log line to carry, and it is the one answer that
    /// costs everything: an empty list is a *known*-empty list here, so it
    /// reports the product closed and takes every row with it. A non-empty span
    /// lower down therefore wins over an empty one above it, and an empty
    /// answer is returned only when the stream offered nothing else.
    ///
    /// **Decoding is not evidence; identity is.** ``Reported`` makes every
    /// field optional, so it decodes any JSON object whatsoever -- and the
    /// preference above then hands the answer to the *first* non-empty array
    /// in the stream, session list or not. An MCP server logging
    /// `tools: [{"name": "read_file"}]`, or any object array printed above the
    /// real one, was therefore accepted as the reading: every entry fell out
    /// of ``sessions(in:)`` for want of a `sessionId`, and the empty list left
    /// behind is a *known*-empty one, so the product was reported closed with
    /// its sessions still running and that answer held until an edge arrived
    /// (CR-Codex-001). CR-Fable-039 taught this rule where an array begins; it
    /// did not make a candidate prove it is the array we came for.
    ///
    /// So a candidate is taken only when every entry in it carries a
    /// ``Reported/identity``. All of them, not most: an array that is part
    /// session and part something else is not a session list that lost a few
    /// rows, it is a span this code has misread, and dropping the entries it
    /// cannot explain would omit live sessions from an answer still marked
    /// trusted. Refusing costs one reading -- ``performRead()`` keeps the last
    /// list and retries on the cadence -- and that is the affordable half of
    /// the trade in a way that reporting the product closed is not.
    ///
    /// **And an empty answer must be a document, not a fragment.** The rule
    /// above sends every unproven candidate down to the last-resort empty span,
    /// which is the answer that costs everything -- so `tools: []` inside a log
    /// line, or the `[]` nested in a lone `[{"tools": []}]`, would report the
    /// product closed by the back door the identity gate just shut. An empty
    /// span is therefore taken only where it stands by itself: the whole stream
    /// is `[]`, or `[]` is alone on its line, which is how a command printing
    /// JSON writes it and is not how a value appears inside a sentence.
    ///
    /// The price is that an entry kind Claude Code invents without a `pid`,
    /// `cwd`, `sessionId` or `startedAt` would take the whole list down with
    /// it, where today it would be skipped. That direction is survivable:
    /// refusal ages into `unknown`, which says we do not know, rather than
    /// into `closed`, which says we do.
    nonisolated private static func reportedEntries(in data: Data) -> [Reported]? {
        let decoder = JSONDecoder()
        // The ordinary case: nothing else wrote to this stdout. Still gated --
        // a lone `[{"tools": []}]` from a server that outlived a `claude` which
        // printed nothing at all reaches this line as the whole stream.
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

    /// Whether a span has nothing but blank space around it on its own line.
    ///
    /// Only asked of an empty span, and only because that is the one answer
    /// taken on no evidence but its own shape -- see ``reportedEntries(in:)``.
    /// A `[]` written as somebody's value has a key or a sentence beside it; a
    /// `[]` that is the command's whole answer has nothing.
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

    /// Whether a decoded array can be the list `claude agents --json` prints.
    ///
    /// An empty array passes, and has to: `[]` is the one answer that says the
    /// product is closed, and there is nothing in it left to check. Which span
    /// an empty answer may be taken from is a separate question, and
    /// ``reportedEntries(in:)`` answers it.
    nonisolated private static func isSessionList(_ entries: [Reported]) -> Bool {
        entries.allSatisfy { $0.identity != nil }
    }

    /// Every balanced `[ ... ]` in the stream, in the order they open.
    ///
    /// Brackets inside a JSON string do not count -- a working directory may be
    /// named `~/Projects/[wip]`, and counting the one in it would close the
    /// array early. The in-string state is dropped at every newline, because a
    /// JSON string can never contain a raw one: an odd quote in somebody's log
    /// line therefore cannot swallow the array printed below it.
    ///
    /// An opening bracket nothing ever closes is simply never offered, rather
    /// than taking the rest of the stream with it.
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
        // Recorded as they close, which puts an inner array ahead of the one
        // holding it; the outermost is the one worth offering first.
        return spans.sorted { $0.lowerBound < $1.lowerBound }
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
