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
        subsystem: "com.yinfenglu.CodexInNotch",
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
    private let tokens: ClaudeCodeTokenCounter?
    private let clock: any MonitorClock
    private let freshness: TimeInterval
    private var cached = QuotaSnapshot.unavailable
    private var readAt: Date?

    init(
        clock: any MonitorClock = SystemMonitorClock(),
        freshness: TimeInterval = 60,
        workingDirectory: URL? = nil,
        tokens: ClaudeCodeTokenCounter? = nil,
        read: (@Sendable () async -> String?)? = nil
    ) {
        self.tokens = tokens
        self.clock = clock
        self.freshness = freshness
        let directory = workingDirectory
        self.read = read ?? { await Self.runUsageCommand(in: directory) }
    }

    func quota() async -> QuotaSnapshot {
        if let readAt, clock.now().timeIntervalSince(readAt) < freshness {
            return cached
        }
        readAt = clock.now()
        // Counted separately from the windows: the two come from different
        // places and one failing must not blank the other.
        let todayTokens = await tokens?.todayTokens()
        guard let output = await read() else {
            // Never a stale figure and never a zero. A quota that cannot be
            // obtained is drawn as unavailable, which is a thing the surface
            // knows how to say.
            cached = QuotaSnapshot(
                windows: Self.parseWindows("", now: clock.now()),
                todayTokens: todayTokens
            )
            return cached
        }
        cached = QuotaSnapshot(
            windows: Self.parseWindows(output, now: clock.now()),
            todayTokens: todayTokens
        )
        return cached
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
    nonisolated private static func resetDate(in body: String, now: Date) -> Date? {
        guard let range = body.range(
            of: #"resets ([A-Z][a-z]{2} \d{1,2} at \d{1,2}:\d{2}(am|pm))"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let stamp = String(body[range].dropFirst("resets ".count))

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

    /// Runs the reading, pinned to a directory of its own.
    ///
    /// It is a real session and fires real hooks. `UserPromptSubmit` would have
    /// separated it from a human's prompt by its `source` field, except that
    /// field was measured absent from every event including a human's — so the
    /// working directory is what tells them apart, and this is the other half
    /// of that arrangement. Each call also leaves a few kilobytes of transcript
    /// behind, and pinning collects them all in one directory that can be
    /// cleaned.
    private static func runUsageCommand(in directory: URL?) async -> String? {
        guard let executable = ClaudeExecutableLocator.locate() else { return nil }
        if let directory {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["-p", "/usage", "--output-format", "json"]
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            Self.log.error("could not read usage: \(error.localizedDescription)")
            return nil
        }
        let data = try? output.fileHandleForReading.readToEnd()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let data else { return nil }

        struct Envelope: Decodable {
            let result: String?
            let isError: Bool?

            enum CodingKeys: String, CodingKey {
                case result
                case isError = "is_error"
            }
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.isError != true else {
            return nil
        }
        return envelope.result
    }
}
