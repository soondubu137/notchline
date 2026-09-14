import Foundation
import os

/// Reads Claude Code's rate-limit windows.
///
/// Runs `claude -p "/usage" --output-format json` (no model request: `total_cost_usd: 0`,
/// `num_turns: 0`, ~2 s) for its side effect: the fetch leaves `cachedUsageUtilization` in
/// `~/.claude.json`, parsed by ``ClaudeCodeUsageUtilization``. The printed text is only checked
/// for the session-cost summary a signed-out CLI prints instead of windows (common on
/// Desktop-only machines, measured 2026-09-09); see ``quotaDiagnostic()``.
actor ClaudeCodeUsageReader: UsageReading, ManagedMonitoringSource {
    private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "ClaudeCodeUsageReader"
    )

    /// What the answer begins with when there are no subscription windows. The only prose this file
    /// knows; a wording change costs the explanation, not the figures.
    private static let costSummaryPrefix = "Total cost:"

    private let read: @Sendable () async -> String?
    /// Claude Code's own configuration, where the fetch leaves its answer.
    private let readConfiguration: @Sendable () -> Data?
    /// Announces that a reading landed; nothing waits for one.
    private let onUpdate: (@Sendable () -> Void)?
    private let tokens: ClaudeCodeTokenCounter?
    private let clock: any MonitorClock
    private let freshness: TimeInterval
    private let tokensFreshness: TimeInterval
    private let retryInterval: TimeInterval
    private let trustCeiling: TimeInterval
    /// Whether there is a screen the figures could be read on; gates the reading itself (see
    /// ``startReadIfStale()``).
    private let screenIsAvailable: @Sendable () -> Bool
    private let transcripts: ClaudeCodeUsageTranscripts?
    // Start as this product's two fixed windows, unknown; `QuotaSnapshot.unavailable` would draw one
    // unlabelled rule. The per-model window is discovered in a reading, not declared.
    private var cachedWindows = ClaudeCodeUsageReader.unavailableWindows
    private var cached = QuotaSnapshot(
        windows: ClaudeCodeUsageReader.unavailableWindows
    )
    /// When the last attempt finished, successful or not; paces the next one.
    private var attemptedAt: Date?
    /// Whether the last answer was the session-cost summary (no subscription). Replaced by each
    /// answer, since signing in happens between readings.
    private var lastAnswerHadNoSubscription = false
    private var consecutiveFailures = 0
    private var tokensReadAt: Date?
    private var inFlight: Task<QuotaSnapshot, Never>?
    nonisolated private let updates = MonitoringChangeBroadcast()
    nonisolated var sourceChanges: [AsyncStream<Void>] { [updates.events()] }
    private var readGeneration = 0
    private var monitoringPaused = false

    /// - Parameters:
    ///   - freshness: How long an answer stands. 30 minutes, set by cost: one run is 2.53 s CPU,
    ///     375 MB peak, 31.5 K page faults, 35.5 K context switches (Release, 2026-08-25), charged to
    ///     this app's coalition, and leaves a transcript. A ceiling, not a cadence: a screen wake
    ///     also triggers a reading.
    ///   - tokensFreshness: How long today's token figure stands; shorter, since it comes off the
    ///     transcripts (~30 ms, no subprocess) and moves visibly.
    ///   - retryInterval: How soon to retry after an attempt that produced nothing; shared stdout
    ///     makes some failures transient.
    ///   - trustCeiling: How old the product's own fetch may be and still be drawn, counted from
    ///     `cachedUsageUtilization.fetchedAtMs`. `3600` matches Claude Code's own reader, and a
    ///     command answering from a stale cache no longer reads as new.
    ///   - configurationFile: Where the product keeps that object; overridden only by tests.
    init(
        clock: any MonitorClock = SystemMonitorClock(),
        freshness: TimeInterval = 1800,
        tokensFreshness: TimeInterval = 60,
        retryInterval: TimeInterval = 5,
        trustCeiling: TimeInterval = 3600,
        workingDirectory: URL? = nil,
        configurationFile: URL? = nil,
        screenIsAvailable: @escaping @Sendable () -> Bool = { true },
        tokens: ClaudeCodeTokenCounter? = nil,
        transcripts: ClaudeCodeUsageTranscripts? = nil,
        onUpdate: (@Sendable () -> Void)? = nil,
        read: (@Sendable () async -> String?)? = nil,
        readConfiguration: (@Sendable () -> Data?)? = nil
    ) {
        self.onUpdate = onUpdate
        self.tokens = tokens
        self.transcripts = transcripts
        self.clock = clock
        self.freshness = freshness
        self.tokensFreshness = tokensFreshness
        self.retryInterval = retryInterval
        self.trustCeiling = trustCeiling
        self.screenIsAvailable = screenIsAvailable
        let directory = workingDirectory
        let cleaner = transcripts
        self.read = read ?? {
            await Self.runUsageCommand(in: directory, clearing: cleaner)
        }
        let configuration = configurationFile ?? Self.defaultConfigurationFile
        self.readConfiguration = readConfiguration ?? {
            try? Data(contentsOf: configuration)
        }
    }

    /// `~/.claude.json`, the product's file. Read only.
    nonisolated static var defaultConfigurationFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json", isDirectory: false)
    }

    /// A reader that answers nothing and runs no command, for tests: each real reading leaves a
    /// transcript folder in the user's `~/.claude/projects` (380 in two days from the suite).
    static func silent(
        clock: any MonitorClock = SystemMonitorClock()
    ) -> ClaudeCodeUsageReader {
        ClaudeCodeUsageReader(
            clock: clock,
            read: { nil },
            // Nor the user's `~/.claude.json`: it would assert against the machine's account.
            readConfiguration: { nil }
        )
    }

    /// What is known now, starting a reading behind it if stale. Never waits for the subprocess
    /// (4–7 s); the reading announces itself through ``onUpdate``.
    func currentQuota() -> QuotaSnapshot {
        if inFlight == nil { _ = startReadIfStale() }
        return cached
    }

    /// Starts a reading if stale without waiting. ``currentQuota()`` does the same, so asking both
    /// starts one reading.
    func readIfStale() {
        if inFlight == nil { _ = startReadIfStale() }
    }

    /// The same reading, waited on; used by tests.
    func quota() async -> QuotaSnapshot {
        // A running reading is the answer: the reading is itself a Claude Code session whose hooks
        // trigger refreshes, so a caller always arrives mid-read.
        if let task = inFlight ?? startReadIfStale() {
            return await task.value
        }
        return cached
    }

    /// When this wants to be read again, so the refresh loop can sleep on it (otherwise a failure
    /// waited on the 60-second heartbeat). Nil while a reading is out or there is no screen: the
    /// refresh could not advance such a deadline, making it a busy-wait.
    func nextReadDeadline() -> Date? {
        guard !monitoringPaused, inFlight == nil, screenIsAvailable() else { return nil }
        let deadlines = [
            attemptedAt?.addingTimeInterval(currentInterval),
            tokensReadAt?.addingTimeInterval(tokensFreshness)
        ]
        return deadlines.compactMap { $0 }.min()
    }

    /// Starts a reading unless one is running or nothing is stale. Tokens are due every minute,
    /// windows every half hour; a tokens-only pass skips the subprocess.
    ///
    /// Nothing is read without a screen (asleep or locked): an idle machine otherwise launched Node
    /// every half hour all night. The wake arrives via ``ClaudeCodeMonitorService/stateChangeEvents``.
    private func startReadIfStale() -> Task<QuotaSnapshot, Never>? {
        guard !monitoringPaused, inFlight == nil, screenIsAvailable() else { return nil }
        let now = clock.now()
        let windowsAreStale = attemptedAt
            .map { now.timeIntervalSince($0) >= currentInterval } ?? true
        let tokensAreStale = tokensReadAt
            .map { now.timeIntervalSince($0) >= tokensFreshness } ?? true
        guard windowsAreStale || tokensAreStale else { return nil }
        let generation = readGeneration
        let task = Task { await self.performRead(readingWindows: windowsAreStale, generation: generation) }
        inFlight = task
        Task { [onUpdate] in
            _ = await task.value
            if await self.readFinished(generation: generation) { self.updates.signal(); onUpdate?() }
        }
        return task
    }

    private func readFinished(generation: Int) -> Bool {
        guard generation == readGeneration else { return false }
        inFlight = nil
        return true
    }

    func startMonitoring() { monitoringPaused = false }
    func stopMonitoring() {
        monitoringPaused = true
        readGeneration += 1
        inFlight?.cancel()
        inFlight = nil
    }

    /// What the readings have left on disk, reported to Settings only; this app does not clear them
    /// (see ``ClaudeCodeUsageTranscripts``).
    ///
    /// *Still looking* is read off `inFlight`, and only until `attemptedAt` is set, so retries do not
    /// flick back to `Calculating…`. Both nil means no quota was ever asked (integration not
    /// registered), which must not read as `Calculating…` forever.
    func transcriptFootprint() async -> AgentDiskFootprintReport {
        guard let transcripts else { return .leavesNothing }
        if let measured = await transcripts.footprint() { return .measured(measured) }
        return attemptedAt == nil && inFlight != nil ? .measuring : .unavailable
    }

    /// Retry interval: doubles with each consecutive failure, capped at `freshness`.
    private var currentInterval: TimeInterval {
        guard consecutiveFailures > 0 else { return freshness }
        let escalated = retryInterval * pow(2, Double(consecutiveFailures - 1))
        return min(escalated, freshness)
    }

    private func performRead(readingWindows: Bool, generation: Int) async -> QuotaSnapshot {
        // Counted separately so one failing does not blank the other.
        let todayTokens = await tokens?.todayTokens()
        guard generation == readGeneration, !Task.isCancelled else { return cached }
        tokensReadAt = clock.now()

        guard readingWindows else {
            cached = QuotaSnapshot(windows: cachedWindows, todayTokens: todayTokens)
            return cached
        }

        // Run for its side effect: the fetch writes the object read below.
        let output = await read()
        guard generation == readGeneration, !Task.isCancelled else { return cached }
        let now = clock.now()
        attemptedAt = now
        consecutiveFailures = output == nil ? consecutiveFailures + 1 : 0
        if let output {
            lastAnswerHadNoSubscription = Self.isCostSummary(output)
        }

        // Read whether or not the command answered, dated by the product's stamp: a failed launch does
        // not mean the figures went away, and an answered one does not mean they are new.
        cachedWindows = readConfiguration()
            .flatMap {
                ClaudeCodeUsageUtilization.windows(
                    in: $0,
                    now: now,
                    ceiling: trustCeiling
                )
            }
            ?? Self.unavailableWindows

        cached = QuotaSnapshot(windows: cachedWindows, todayTokens: todayTokens)
        return cached
    }

    /// Why the windows are unavailable, when this app can say; nil otherwise. The one case is a
    /// signed-out CLI (Desktop injects auth per session, so `claude` may have no credential and
    /// `/usage` prints its session cost). Said only while nothing is drawn.
    func quotaDiagnostic() -> String? {
        guard lastAnswerHadNoSubscription,
              cachedWindows.allSatisfy({ $0.remainingPercent == nil }) else {
            return nil
        }
        return "Claude Code reported no usage limits: its CLI is not signed in. "
            + "Run `claude auth login` in a terminal — signing in to Claude "
            + "Desktop does not sign in the CLI."
    }

    /// Whether an answer is the session-cost summary printed without a subscription. Anchored to the
    /// first line: a later `Total cost:` is another writer's.
    nonisolated static func isCostSummary(_ output: String) -> Bool {
        output
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces).hasPrefix(costSummaryPrefix) }
            ?? false
    }

    nonisolated static var unavailableWindows: [QuotaWindow] {
        [
            QuotaWindow(
                label: ClaudeCodeUsageUtilization.sessionLabel,
                remainingPercent: nil,
                resetsAt: nil
            ),
            QuotaWindow(
                label: ClaudeCodeUsageUtilization.allModelsLabel,
                remainingPercent: nil,
                resetsAt: nil
            )
        ]
    }

    /// What `--output-format json` prints around the answer; internal so it is tested against
    /// captured bytes.
    struct Envelope: Decodable {
        let result: String?
        let isError: Bool?
        /// Names the transcript this reading wrote, so the folder can be found.
        let sessionID: String?

        enum CodingKeys: String, CodingKey {
            case result
            case isError = "is_error"
            case sessionID = "session_id"
        }

        /// Whether this object is the answer. All-optional fields decode any JSON object, so an object
        /// with none of these fields is another writer's line.
        var isAnswer: Bool { result != nil || sessionID != nil }
    }

    /// Runs the reading in its own directory. Its hooks carry no `source` (measured absent on every
    /// event), so the working directory is what separates it from a human's prompt; it also
    /// collects the transcripts in one place.
    private static func runUsageCommand(
        in directory: URL?,
        clearing transcripts: ClaudeCodeUsageTranscripts?
    ) async -> String? {
        if let directory {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        // 30 s against a 4–7 s reading: a slow machine is not a failure, a wedged one recovers within a
        // freshness window.
        guard let data = await ClaudeCommand.run(
            ["-p", "/usage", "--output-format", "json"],
            in: directory,
            timeout: 30
        ) else {
            return nil
        }
        guard let envelope = envelope(in: data) else { return nil }
        // The reading's session id locates the folder its transcripts go to.
        if let sessionID = envelope.sessionID {
            await transcripts?.noteReading(sessionID)
        }
        guard envelope.isError != true else { return nil }
        return envelope.result
    }

    /// Finds the answer in stdout, which may hold other writers' lines: on 2.1.234 an MCP line
    /// (`Client.listTools() called but server does not advertise tools capability - returning
    /// empty list`) followed the object in 2 runs of 5. Decoded line by line; static and internal so
    /// it is tested against captured bytes.
    nonisolated static func usageText(in data: Data) -> String? {
        guard let envelope = envelope(in: data), envelope.isError != true else {
            return nil
        }
        return envelope.result
    }

    /// The answer object in a stream that may hold more than it.
    ///
    /// A line decoding is not enough (``Envelope/isAnswer``, CR-Fable-040): an earlier JSON line won,
    /// counting a good reading as failed and leaving its transcript unnamed. A line with `result`
    /// outranks one that only names a session (`stream-json` stamps `session_id` on every line).
    nonisolated static func envelope(in data: Data) -> Envelope? {
        let decoder = JSONDecoder()
        if let whole = try? decoder.decode(Envelope.self, from: data),
           whole.isAnswer {
            return whole
        }
        var named: Envelope?
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let decoded = try? decoder.decode(Envelope.self, from: Data(line)),
                  decoded.isAnswer else {
                continue
            }
            if decoded.result != nil { return decoded }
            if named == nil { named = decoded }
        }
        return named
    }
}
