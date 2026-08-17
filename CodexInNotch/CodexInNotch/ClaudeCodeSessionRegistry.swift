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
    private var cached: [ClaudeCodeSession] = []
    private var readAt: Date?

    /// - Parameter read: Returns the raw JSON, or nil when it could not be
    ///   obtained. Injected so the parsing and staleness rules can be tested
    ///   without a real Claude Code install.
    init(
        clock: any MonitorClock = SystemMonitorClock(),
        freshness: TimeInterval = 30,
        read: (@Sendable () async -> Data?)? = nil
    ) {
        self.clock = clock
        self.freshness = freshness
        self.read = read ?? { await Self.runOfficialCommand() }
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
    private static func runOfficialCommand() async -> Data? {
        guard let executable = ClaudeExecutableLocator.locate() else { return nil }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["agents", "--json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        // Inheriting stdin would let the command wait on a terminal that is not
        // there.
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            Self.log.error("could not run the session list: \(error.localizedDescription)")
            return nil
        }

        let data = try? output.fileHandleForReading.readToEnd()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data
    }
}
