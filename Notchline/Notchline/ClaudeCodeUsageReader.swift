import Foundation
import os

/// Reads Claude Code's rate-limit windows.
///
/// The command is public and free — `claude -p "/usage" --output-format json`
/// makes no model request at all (measured `total_cost_usd: 0`, `num_turns: 0`,
/// `duration_api_ms: 0`, about two seconds). What is *not* public is the shape
/// of what it prints: the answer is a paragraph written for a person, so
/// reading it is a private dependency and is registered as one.
///
/// That makes the parser's job "refuse confidently" rather than "extract
/// cleverly". It anchors on two whole line prefixes and nothing else, because
/// the same output continues into a free-text section full of other
/// percentages — `94% of your usage was at >150k context` sits a few lines
/// below the numbers this reads. Anything that scanned for a number would find
/// that one eventually.
actor ClaudeCodeUsageReader {
    private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "ClaudeCodeUsageReader"
    )

    /// The two windows this product draws, and their labels in the output.
    ///
    /// A third is reported — a weekly cap for one named model — and is
    /// deliberately ignored. Which model it names varies, so a rule that
    /// sometimes meant one thing and sometimes another would have to be read
    /// rather than glanced at. The risk is recorded rather than designed
    /// around: a user who exhausts the per-model cap sees two healthy rules and
    /// is still refused. If that happens the fix is a third window, not a
    /// second one that changes meaning.
    private static let windows: [(prefix: String, label: String)] = [
        ("Current session:", "5 h"),
        ("Current week (all models):", "7 d")
    ]

    private let read: @Sendable () async -> String?
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
    // Both start as this product's two windows with nothing known about
    // either. `QuotaSnapshot.unavailable` is the single-window form and would
    // draw one unlabelled rule where the footer expects two labelled ones --
    // which nothing could see while every answer came from a completed
    // reading, and everything can now that answers come before one.
    private var cachedWindows = ClaudeCodeUsageReader.unavailableWindows
    private var cached = QuotaSnapshot(
        windows: ClaudeCodeUsageReader.unavailableWindows
    )
    /// When the last attempt finished, successful or not. Paces the next one.
    private var attemptedAt: Date?
    /// When the command last answered at all -- not when it last said something
    /// recognisable. Bounds how long the windows read from that answer may go
    /// on being drawn once the command stops answering.
    private var answeredAt: Date?
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
    ///   - trustCeiling: How long already-parsed windows may still be drawn
    ///     while attempts are failing. The same split the session registry
    ///     makes, for the same reason: `freshness` says when to read again, the
    ///     ceiling says how long the last answer is still evidence. A quota is
    ///     drawn to the percent and moves over hours, so one unlucky attempt is
    ///     no reason to blank it -- but a `claude` that has been uninstalled is
    ///     every reason, and only a ceiling tells those two apart.
    ///
    ///     **It has to clear `freshness`, and that is what sets it.** The
    ///     ceiling is counted from the last *answer*, and the first failed
    ///     attempt cannot happen until a whole freshness window after one. At
    ///     the previous 300/900 the gap left room for two more failures before
    ///     the windows blanked; left at 900 while freshness became 1800, the
    ///     very first failed attempt would have arrived already past the
    ///     ceiling and blanked the quota on one unlucky read — the exact
    ///     behaviour the split exists to prevent. One further whole window is
    ///     the rule, so an uninstalled `claude` still blanks: the retry
    ///     escalation runs about ten attempts inside that hour and none of
    ///     them answers.
    init(
        clock: any MonitorClock = SystemMonitorClock(),
        freshness: TimeInterval = 1800,
        tokensFreshness: TimeInterval = 60,
        retryInterval: TimeInterval = 5,
        trustCeiling: TimeInterval = 3600,
        workingDirectory: URL? = nil,
        screenIsAvailable: @escaping @Sendable () -> Bool = { true },
        tokens: ClaudeCodeTokenCounter? = nil,
        transcripts: ClaudeCodeUsageTranscripts? = nil,
        onUpdate: (@Sendable () -> Void)? = nil,
        read: (@Sendable () async -> String?)? = nil
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
        ClaudeCodeUsageReader(clock: clock, read: { nil })
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

        let output = await read()
        let now = clock.now()
        attemptedAt = now
        consecutiveFailures = output == nil ? consecutiveFailures + 1 : 0

        if let output {
            // An answer that was read and not recognised is still an answer:
            // its windows are unavailable, and they replace the old ones rather
            // than hiding behind them.
            cachedWindows = Self.parseWindows(output, now: now)
            answeredAt = now
        } else if let answeredAt, now.timeIntervalSince(answeredAt) < trustCeiling {
            // Inside the ceiling: keep drawing what was last read. Never a
            // figure invented and never one dressed up as newer than it is --
            // the surface already draws a quota that is up to `freshness` old.
        } else {
            // Past it, nothing here is evidence any more. Unavailable is a
            // thing the surface knows how to say; a stale percentage is not.
            cachedWindows = Self.unavailableWindows
        }

        cached = QuotaSnapshot(windows: cachedWindows, todayTokens: todayTokens)
        return cached
    }

    /// The windows this draws, with nothing known about any of them.
    nonisolated static var unavailableWindows: [QuotaWindow] {
        windows.map {
            QuotaWindow(label: $0.label, remainingPercent: nil, resetsAt: nil)
        }
    }

    /// Pulls the two windows out of the paragraph, or reports neither.
    ///
    /// Made `static` and pure so the whole of this — the one part most likely
    /// to break on a Claude Code update — can be tested against captured output
    /// without running anything.
    nonisolated static func parseWindows(_ output: String, now: Date) -> [QuotaWindow] {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        return windows.map { window in
            guard let line = lines.first(where: { $0.hasPrefix(window.prefix) }) else {
                return QuotaWindow(
                    label: window.label,
                    remainingPercent: nil,
                    resetsAt: nil
                )
            }
            let body = String(line.dropFirst(window.prefix.count))
            return QuotaWindow(
                label: window.label,
                // Reported as used; the rule draws what is left.
                remainingPercent: usedPercent(in: body).map { 100 - $0 },
                resetsAt: resetDate(in: body, now: now)
            )
        }
    }

    nonisolated private static func usedPercent(in body: String) -> Int? {
        guard let range = body.range(of: #"(\d{1,3})% used"#, options: .regularExpression),
              let percent = Int(body[range].prefix { $0.isNumber }),
              (0 ... 100).contains(percent) else {
            return nil
        }
        return percent
    }

    /// Turns `resets Aug 16 at 7:19pm (America/Los_Angeles)` into an instant.
    ///
    /// The year is not printed, so it is inferred: the current one, rolled
    /// forward when that would put the reset in the past. A reset is always
    /// ahead, so a date behind us means the year turned between the two.
    ///
    /// The minutes are not always printed either. On the hour the time is
    /// written `12am`, not `12:00am`, and requiring the colon is what made the
    /// weekly window -- which resets at midnight, and so is on the hour nearly
    /// every time it is read -- report a percentage with no reset beside it,
    /// while the session window a line above parsed fine.
    nonisolated private static func resetDate(in body: String, now: Date) -> Date? {
        guard let range = body.range(
            of: #"resets ([A-Z][a-z]{2} \d{1,2} at \d{1,2}(:\d{2})?(am|pm))"#,
            options: .regularExpression
        ) else {
            return nil
        }
        var stamp = String(body[range].dropFirst("resets ".count))
        if !stamp.contains(":") {
            // `12am` -> `12:00am`, so one format string reads both.
            stamp = stamp.replacingOccurrences(
                of: #"(\d{1,2})(am|pm)"#,
                with: "$1:00$2",
                options: .regularExpression
            )
        }

        let zone = body.range(of: #"\(([^)]+)\)"#, options: .regularExpression)
            .map { String(body[$0].dropFirst().dropLast()) }
            .flatMap(TimeZone.init(identifier:)) ?? .current

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "MMM d 'at' h:mma yyyy"

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let year = calendar.component(.year, from: now)
        guard let parsed = formatter.date(from: "\(stamp) \(year)") else { return nil }
        guard parsed < now else { return parsed }
        return formatter.date(from: "\(stamp) \(year + 1)")
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
    /// Made `static` and non-private for the same reason ``parseWindows`` is:
    /// it is a rule about someone else's output, so it is tested against
    /// captured bytes rather than by running anything.
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
