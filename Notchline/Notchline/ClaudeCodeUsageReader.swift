import Foundation
import os

/// Reads Claude Code's rate-limit windows.
///
/// The command is public and free — `claude -p "/usage" --output-format json`
/// makes no model request at all (measured `total_cost_usd: 0`, `num_turns: 0`,
/// `duration_api_ms: 0`, about two seconds). It is still run, and it is still
/// the reason this app has anything to draw — but **not for what it prints**.
/// Running it makes the product fetch its usage, and the fetch leaves the
/// answer in `~/.claude.json` as `cachedUsageUtilization`. The figures are read
/// from there, as JSON, by ``ClaudeCodeUsageUtilization``.
///
/// **The paragraph is no longer parsed for numbers, and that was a real
/// failure, not a tidy-up.** The command only prints the windows when the CLI
/// itself is signed in to a Claude subscription; otherwise the same run answers
/// with its session-cost summary — `Total cost: $0.0000 …`, no windows in it
/// anywhere — and every regular expression came back empty. Measured on this
/// machine on 2026-09-09, where `claude auth status` reports
/// `{"loggedIn": false, "authMethod": "none"}` for the `PATH` binary *and* for
/// both of Claude Desktop's bundled copies: Desktop hosts its own sessions with
/// auth injected per session, so a Desktop-only machine can use Claude Code all
/// day with a CLI that has no credential at all. What the footer showed for it
/// was two `--` rules and no reason anywhere. The reason is now said out loud —
/// see ``quotaDiagnostic()``.
///
/// The one thing still read out of the answer is that shape, and only to say
/// so. No figure comes off prose any more.
actor ClaudeCodeUsageReader {
    private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "ClaudeCodeUsageReader"
    )

    /// What the answer begins with when the product has no subscription
    /// windows to report, and therefore prints its session cost instead.
    ///
    /// The **only** prose this file still knows, and it produces a sentence
    /// rather than a number. A wording change here costs the explanation and
    /// nothing else: the windows come from JSON either way.
    private static let costSummaryPrefix = "Total cost:"

    private let read: @Sendable () async -> String?
    /// Claude Code's own configuration, where the fetch this run performs
    /// leaves its answer. Injected so the shape can be tested against captured
    /// bytes without a home directory.
    private let readConfiguration: @Sendable () -> Data?
    /// Announces that a reading landed, because nothing waits for one any more.
    private let onUpdate: (@Sendable () -> Void)?
    private let tokens: ClaudeCodeTokenCounter?
    private let clock: any MonitorClock
    private let freshness: TimeInterval
    private let tokensFreshness: TimeInterval
    private let retryInterval: TimeInterval
    private let trustCeiling: TimeInterval
    /// Whether there is a screen the figures could be read on.
    ///
    /// See ``startReadIfStale()`` -- this gates the reading itself, not
    /// what is drawn from what has already been read.
    private let screenIsAvailable: @Sendable () -> Bool
    private let transcripts: ClaudeCodeUsageTranscripts?
    // Both start as this product's two fixed windows with nothing known about
    // either. `QuotaSnapshot.unavailable` is the single-window form and would
    // draw one unlabelled rule where the footer expects two labelled ones --
    // which nothing could see while every answer came from a completed
    // reading, and everything can now that answers come before one. The
    // per-model window is not among them: it is discovered in the reading
    // rather than declared here, so a machine that has not been read yet
    // claims nothing about whether the account has one.
    private var cachedWindows = ClaudeCodeUsageReader.unavailableWindows
    private var cached = QuotaSnapshot(
        windows: ClaudeCodeUsageReader.unavailableWindows
    )
    /// When the last attempt finished, successful or not. Paces the next one.
    private var attemptedAt: Date?
    /// Whether the last answer was the product's session-cost summary — the
    /// shape it takes when the CLI has no subscription to report windows for.
    ///
    /// Kept as a fact about the last answer rather than as a running count:
    /// signing in is a thing a person does between two readings, so the next
    /// answer replaces this outright.
    private var lastAnswerHadNoSubscription = false
    private var consecutiveFailures = 0
    private var tokensReadAt: Date?
    private var inFlight: Task<QuotaSnapshot, Never>?

    /// - Parameters:
    ///   - freshness: How long an answer stands before the command is run
    ///     again. Thirty minutes, and the number is set by what the reading
    ///     costs rather than by what it is worth: measured in Release on
    ///     2026-08-25, one `claude -p "/usage" --output-format json` is
    ///     **2.53 s of CPU, 375 MB of peak resident memory, 31.5 K page
    ///     faults and 35.5 K context switches**, and it leaves a transcript on
    ///     disk that nothing removes. At the five minutes this used to run at,
    ///     that is 142 launches and about 360 s of CPU per twelve hours —
    ///     more than the whole rest of the app spends in the same period, and
    ///     charged to this app's coalition rather than to `claude`, which is
    ///     why it never showed up in the process's own numbers.
    ///
    ///     What it buys is a 5-hour window and a 7-day one, drawn to the
    ///     percent. A 5-hour rule moves about 0.3% a minute at the fastest a
    ///     person can spend it, so half an hour of staleness is at worst a few
    ///     points on the rule furthest from its reset — against a reading that
    ///     was never a live figure to begin with. The footer already draws a
    ///     quota up to a whole freshness window old and says nothing about its
    ///     age.
    ///
    ///     This is a ceiling, not a cadence, in the same sense as everything
    ///     else here: the reading also runs when the screen comes back after
    ///     being away, so the figure a user actually looks at is at most one
    ///     wake old rather than half an hour.
    ///   - tokensFreshness: How long today's token figure stands. Deliberately
    ///     the shorter of the two. It shares a reading with the windows for no
    ///     better reason than that they are drawn together; it comes off the
    ///     transcripts rather than the command, costs about 30 ms and no
    ///     subprocess at all, and unlike a quota window it moves visibly while
    ///     you work. Slowing it to match would have been a regression bought
    ///     with nothing.
    ///   - retryInterval: How soon to try again after an attempt that produced
    ///     nothing. A failure must not book the full freshness window: the
    ///     reading is a subprocess whose stdout is shared with whatever else
    ///     decides to log there, so some attempts fail for reasons that are
    ///     gone by the next one, and sitting out a whole freshness window to
    ///     discover that is what the user saw as the figures coming and going.
    ///     That mattered more once the window became five minutes, and more
    ///     again at thirty.
    ///   - trustCeiling: How old the product's own fetch may be and still be
    ///     drawn. The same split the session registry makes, for the same
    ///     reason: `freshness` says when to read again, the ceiling says how
    ///     long the last answer is still evidence. A quota is drawn to the
    ///     percent and moves over hours, so one unlucky attempt is no reason to
    ///     blank it -- but a `claude` that has been uninstalled, or signed out,
    ///     is every reason, and only a ceiling tells those two apart.
    ///
    ///     **It is now counted from the product's stamp rather than from this
    ///     app's last answer, and the hour is theirs.** `cachedUsageUtilization`
    ///     carries `fetchedAtMs`, and Claude Code's own reader of that object
    ///     stops trusting it at exactly one hour. Matching that is the whole
    ///     argument: a figure the product has expired is not one this app
    ///     should be drawing beside it. It also closes a hole the old rule had
    ///     — a command that answered out of a cache it had failed to refresh
    ///     used to be dated by the run, so a stale figure could be redrawn as
    ///     new indefinitely. The number is unchanged at `3600`; what it is
    ///     measured from is not.
    ///   - configurationFile: Where the product keeps that object. Overridden
    ///     only by tests.
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

    /// `~/.claude.json`, which is the product's, not this app's. Read only;
    /// nothing here ever writes it.
    nonisolated static var defaultConfigurationFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json", isDirectory: false)
    }

    /// A reader that answers nothing and runs no command, for tests.
    ///
    /// Every reading is a real Claude Code session, and Claude Code files a
    /// session under a directory named after its working directory. A suite
    /// that builds a fresh temporary root per case therefore left one folder
    /// per case, per run, in the user's `~/.claude/projects` -- 380 of them
    /// inside two days, each holding one 3.4 KB transcript of a `/usage` the
    /// suite never looked at. `tearDown` removed the temporary root and could
    /// not remove that, because it is somewhere else and belongs to somebody
    /// else's application.
    ///
    /// Nothing under test asserts on a live quota -- a figure that comes from
    /// the machine's own account could not be asserted on anyway -- so the
    /// subprocess bought nothing and the residue was its whole effect. Tests
    /// of the reading itself inject ``read`` with captured output instead.
    static func silent(
        clock: any MonitorClock = SystemMonitorClock()
    ) -> ClaudeCodeUsageReader {
        ClaudeCodeUsageReader(
            clock: clock,
            read: { nil },
            // The user's own `~/.claude.json` is not this suite's business
            // either: a case that read it would assert against whatever the
            // machine's account happens to say today.
            readConfiguration: { nil }
        )
    }

    /// What is known now, with a reading started behind it if that has gone
    /// stale. Never waits for the subprocess.
    ///
    /// The snapshot used to await the reading, which put a `claude` launch --
    /// four to seven seconds of it -- in front of every row in the panel,
    /// including rows a hook event had just changed. The two do not come from
    /// the same place and have no business arriving on the same schedule. So
    /// this hands back what is known, and the reading announces itself through
    /// ``onUpdate`` when it lands, which is one more edge on a surface that is
    /// already driven by edges.
    func currentQuota() -> QuotaSnapshot {
        if inFlight == nil { _ = startReadIfStale() }
        return cached
    }

    /// The same reading, waited on. Kept for callers that want the answer
    /// rather than the latest one, which is every test of this file.
    func quota() async -> QuotaSnapshot {
        // A reading already running is the answer. Without this, a caller that
        // arrives while the subprocess is out -- and one always does, because
        // the reading is itself a Claude Code session and fires the hooks that
        // trigger refreshes -- would read a cache from before the attempt and
        // treat it as the result.
        if let task = inFlight ?? startReadIfStale() {
            return await task.value
        }
        return cached
    }

    /// When this wants to be read again, so the refresh loop can sleep on it.
    ///
    /// Without a deadline the reading was paced by whatever else happened to
    /// ask -- a hook event, or the 60-second heartbeat -- and a failed attempt
    /// therefore stood for up to two minutes rather than the seconds it is
    /// actually worth waiting.
    ///
    /// Nil while a reading is out: that one will announce itself, and a
    /// deadline the refresh could not advance is a busy-wait in a deadline's
    /// clothes.
    ///
    /// Nil too while there is no screen, for the same reason and a stronger
    /// one: the deadline would be a wake-up booked to buy a figure nobody can
    /// look at. ``startReadIfStale()`` would refuse the reading anyway, so a
    /// deadline left standing here is one the refresh *cannot* advance -- the
    /// exact shape of busy-wait the paragraph above is about.
    func nextReadDeadline() -> Date? {
        guard inFlight == nil, screenIsAvailable() else { return nil }
        let deadlines = [
            attemptedAt?.addingTimeInterval(currentInterval),
            tokensReadAt?.addingTimeInterval(tokensFreshness)
        ]
        return deadlines.compactMap { $0 }.min()
    }

    /// Starts a reading unless one is running or nothing has gone stale.
    ///
    /// Two clocks, one reading. Today's tokens come off the transcripts every
    /// minute; the windows come off the command every half hour. A pass that
    /// only the tokens are due for skips the subprocess entirely.
    ///
    /// **And nothing is read at all while there is no screen.** Both halves of
    /// this reading exist to be drawn in the panel's footer, which a user
    /// reaches by hovering the notch -- so a display that is asleep or a screen
    /// that is locked means the figures cannot be looked at, not merely that
    /// they are unlikely to be. Left ungated, an idle machine spent the night
    /// launching a Node process every half hour and stat-ing every transcript
    /// on disk every minute, for a footer nobody could open. The wake is an
    /// edge ``ClaudeCodeMonitorService/stateChangeEvents`` already carries, so
    /// the first thing that happens when the screen comes back is this reading.
    private func startReadIfStale() -> Task<QuotaSnapshot, Never>? {
        guard inFlight == nil, screenIsAvailable() else { return nil }
        let now = clock.now()
        let windowsAreStale = attemptedAt
            .map { now.timeIntervalSince($0) >= currentInterval } ?? true
        let tokensAreStale = tokensReadAt
            .map { now.timeIntervalSince($0) >= tokensFreshness } ?? true
        guard windowsAreStale || tokensAreStale else { return nil }
        let task = Task { await self.performRead(readingWindows: windowsAreStale) }
        inFlight = task
        Task { [onUpdate] in
            _ = await task.value
            await self.readFinished()
            onUpdate?()
        }
        return task
    }

    private func readFinished() {
        inFlight = nil
    }

    /// What the readings have left on disk, and what to say before one has
    /// told this where that is.
    ///
    /// Reported to Settings and nothing else. This app does not clear them: see
    /// ``ClaudeCodeUsageTranscripts`` for why that is a decision and not an
    /// omission.
    ///
    /// *Still looking* is a claim about a reading, so it is read off one that
    /// is actually out rather than off the absence of a finished one.
    ///
    /// `inFlight` is that reading. `attemptedAt` then keeps the word to the
    /// first of them: once an attempt has come back with nothing the answer
    /// stays `unavailable` through every retry, instead of flicking back to
    /// `Calculating…` each time the escalating retry fires. The reading notes
    /// its own session id from inside ``read``, before either is set, so a
    /// folder a finished reading located is never still reported as on its way.
    ///
    /// **Both nil is neither of those states**: nothing has ever asked this for
    /// a quota. On a machine with no Claude Code on it nothing ever will --
    /// `ClaudeCodeMonitorService.fetchSnapshot` returns before the reading
    /// whenever the integration is not registered, so no attempt is made, none
    /// comes back, and `attemptedAt` stays nil for the life of the process.
    /// Keyed on that alone the state was indistinguishable from a first reading
    /// still out, and Settings read `Calculating…` forever -- a progress claim
    /// about work that was never going to start.
    func transcriptFootprint() async -> AgentDiskFootprintReport {
        guard let transcripts else { return .leavesNothing }
        if let measured = await transcripts.footprint() { return .measured(measured) }
        return attemptedAt == nil && inFlight != nil ? .measuring : .unavailable
    }

    /// A failure is worth retrying sooner than a success is worth re-reading --
    /// but only the first few.
    ///
    /// The interval doubles with each consecutive failure and stops at
    /// `freshness`. One unlucky attempt costs seconds, and a `claude` that has
    /// been uninstalled does not buy a full refresh every five of them for the
    /// life of the process.
    private var currentInterval: TimeInterval {
        guard consecutiveFailures > 0 else { return freshness }
        let escalated = retryInterval * pow(2, Double(consecutiveFailures - 1))
        return min(escalated, freshness)
    }

    private func performRead(readingWindows: Bool) async -> QuotaSnapshot {
        // Counted separately from the windows: the two come from different
        // places, on different clocks, and one failing must not blank the
        // other.
        let todayTokens = await tokens?.todayTokens()
        tokensReadAt = clock.now()

        guard readingWindows else {
            cached = QuotaSnapshot(windows: cachedWindows, todayTokens: todayTokens)
            return cached
        }

        // The command is run for what it *does*, not for what it says: it makes
        // the product fetch its usage, and the fetch writes the object read
        // below. Its text is only asked one question, and the answer to that
        // one is a sentence for the user rather than a figure.
        let output = await read()
        let now = clock.now()
        attemptedAt = now
        consecutiveFailures = output == nil ? consecutiveFailures + 1 : 0
        if let output {
            lastAnswerHadNoSubscription = Self.isCostSummary(output)
        }

        // Read whether or not the command answered, and dated by the product's
        // own stamp rather than by this run. A failed launch is not evidence
        // the figures went away -- another Claude Code on this machine may have
        // refreshed them a minute ago -- and a launch that answered is not
        // evidence they are new.
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

    /// Why the windows are unavailable, when this app can say — and nil
    /// whenever it cannot, which includes every case where they are fine.
    ///
    /// **The one state worth a sentence is a signed-out CLI**, because it is
    /// the one the user can fix and the one nothing else reports. Claude
    /// Desktop hosts its own sessions with auth injected per session, so a
    /// machine can run Claude Code all day while `claude` itself has no
    /// credential; the product then answers `/usage` with its session cost and
    /// this app has nothing to draw. Silent `--` was the old behaviour and it
    /// left the user with a blank and no next step.
    ///
    /// Said only while there is in fact nothing to draw: an account whose
    /// figures are on screen has no problem to report, whatever shape the last
    /// answer took.
    func quotaDiagnostic() -> String? {
        guard lastAnswerHadNoSubscription,
              cachedWindows.allSatisfy({ $0.remainingPercent == nil }) else {
            return nil
        }
        return "Claude Code reported no usage limits: its CLI is not signed in. "
            + "Run `claude auth login` in a terminal — signing in to Claude "
            + "Desktop does not sign in the CLI."
    }

    /// Whether an answer is the product's session-cost summary, which is what
    /// it prints in place of the windows when there is no subscription behind
    /// the CLI.
    ///
    /// Anchored to the first line it has, because the summary *is* the whole
    /// answer in that state; a `Total cost:` further down belongs to something
    /// else that decided to write to the same stream.
    nonisolated static func isCostSummary(_ output: String) -> Bool {
        output
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces).hasPrefix(costSummaryPrefix) }
            ?? false
    }

    /// The windows this draws, with nothing known about any of them.
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

    /// What `--output-format json` prints around the answer.
    ///
    /// Internal for the same reason ``usageText(in:)`` is: it is a rule about
    /// someone else's output, so it is tested against captured bytes.
    struct Envelope: Decodable {
        let result: String?
        let isError: Bool?
        /// Names the transcript this reading wrote, which is how the pile of
        /// them gets found and cleared.
        let sessionID: String?

        enum CodingKeys: String, CodingKey {
            case result
            case isError = "is_error"
            case sessionID = "session_id"
        }

        /// Whether this object is the answer rather than something that merely
        /// parsed.
        ///
        /// Every field here is optional, because the object drops fields
        /// depending on how the command ended -- and a synthesized `Decodable`
        /// whose fields are all optional decodes `{}`, and therefore decodes
        /// **any** JSON object at all. So "it decoded" is not a test of
        /// anything, and the line-by-line read below needs one: an object that
        /// carries none of these fields is somebody else's line.
        var isAnswer: Bool { result != nil || sessionID != nil }
    }

    /// Runs the reading, pinned to a directory of its own.
    ///
    /// It is a real session and fires real hooks. `UserPromptSubmit` would have
    /// separated it from a human's prompt by its `source` field, except that
    /// field was measured absent from every event including a human's — so the
    /// working directory is what tells them apart, and this is the other half
    /// of that arrangement. Each call also leaves a few kilobytes of transcript
    /// behind, and pinning collects them all in one directory that can be
    /// cleaned.
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
        // Thirty seconds against a reading measured at four to seven: long
        // enough that a slow machine is not called a failure, short enough that
        // a wedged one is corrected inside a freshness window rather than
        // freezing the figure until the app is relaunched.
        guard let data = await ClaudeCommand.run(
            ["-p", "/usage", "--output-format", "json"],
            in: directory,
            timeout: 30
        ) else {
            return nil
        }
        guard let envelope = envelope(in: data) else { return nil }
        // The reading names its own session, so the transcript it just left
        // behind is the one landmark that finds the folder they all go to.
        if let sessionID = envelope.sessionID {
            await transcripts?.noteReading(sessionID)
        }
        guard envelope.isError != true else { return nil }
        return envelope.result
    }

    /// Finds the answer in stdout, which is not guaranteed to hold only it.
    ///
    /// `--output-format json` documents the object; it does not promise to be
    /// the only writer to that stream. Measured on 2.1.234, two runs in five
    /// append a line of their own --
    /// `Client.listTools() called but server does not advertise tools
    /// capability - returning empty list` -- after the object, and `JSONDecoder`
    /// rejects the whole stream over the trailing text. So the intermittent
    /// half of these readings returned nothing, the windows went unavailable,
    /// and nothing tried again for a minute. Decoding line by line ignores
    /// company the object did not ask for.
    ///
    /// Made `static` and non-private for the same reason
    /// ``ClaudeCodeUsageUtilization/windows(in:now:ceiling:)`` is: it is a rule
    /// about someone else's output, so it is tested against captured bytes
    /// rather than by running anything.
    nonisolated static func usageText(in data: Data) -> String? {
        guard let envelope = envelope(in: data), envelope.isError != true else {
            return nil
        }
        return envelope.result
    }

    /// The answer object in a stream that may hold more than it.
    ///
    /// Taking the first line that *decodes* was the whole test until
    /// CR-Fable-040, and it tested nothing: ``Envelope/isAnswer`` says why an
    /// empty object passes it. One JSON line ahead of the answer -- an MCP
    /// server's, or a future `claude` build's -- and the empty envelope won:
    /// no `result`, so the caller counted a reading that had in fact answered
    /// correctly as a failure, escalated the retry interval, and blanked the
    /// windows once the trust ceiling passed. No `session_id` either, so the
    /// transcript that reading had just left behind was never named and the
    /// disk-footprint row never got a figure.
    ///
    /// `result` is what the reading is for, so a line carrying it wins outright
    /// over one that merely names a session -- `--output-format stream-json`
    /// stamps `session_id` on every line it writes, and a stream that somehow
    /// arrived in that shape must not have its answer outranked by its own
    /// preamble.
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
