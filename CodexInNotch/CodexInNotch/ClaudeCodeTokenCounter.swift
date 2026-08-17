import Foundation
import os

/// Counts the tokens Claude Code has spent today.
///
/// The definition is the one ADR 0008 settled, and it is not the obvious one:
/// all input processed *including cache reads*, plus output. Codex counts cache
/// reads inside its input and Claude Code reports them alongside, so matching
/// the two is forced rather than chosen — and the three candidate definitions
/// differ by 237×, on two figures that sit on the same footer line.
///
/// **This is a private dependency.** The transcript's record structure is not a
/// published contract; it is registered, and it fails closed to no figure at
/// all rather than to a small one, because a small wrong number looks like a
/// quiet day.
///
/// Everything here is about not reading 100 MB every minute. Three rules do
/// that work: a file untouched since before today cannot hold today's records
/// and is never opened; a file already scanned is read only from where the last
/// pass stopped; and a line without the word `usage` in it is never decoded.
actor ClaudeCodeTokenCounter {
    private static let log = Logger(
        subsystem: "com.yinfenglu.CodexInNotch",
        category: "ClaudeCodeTokenCounter"
    )

    private static let chunkBytes = 1 << 20

    private struct FileProgress {
        var scannedBytes: UInt64
        var tokens: Int64
    }

    private let projectsDirectory: URL
    private let clock: any MonitorClock
    private let calendar: Calendar
    private let fileManager: FileManager
    private var day: String?
    private var progress: [String: FileProgress] = [:]

    init(
        projectsDirectory: URL? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        calendar: Calendar = .current,
        fileManager: FileManager = .default
    ) {
        self.projectsDirectory = projectsDirectory
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true)
        self.clock = clock
        self.calendar = calendar
        self.fileManager = fileManager
    }

    /// Today's total, or nil when nothing could be read.
    ///
    /// Zero and nil are different answers and both are true ones: zero means
    /// the transcripts were read and today has no records yet; nil means they
    /// could not be read, and the footer says so rather than claiming a quiet
    /// day.
    func todayTokens() -> Int64? {
        let now = clock.now()
        let today = Self.dayKey(for: now, calendar: calendar)
        if day != today {
            // A new day invalidates every running total, not the files.
            day = today
            progress = [:]
        }

        // Nothing readable is the only reason to report no figure. Once the
        // directory has been listed, an answer of zero is a true one: the
        // transcripts were read and today has nothing in them yet.
        guard let transcripts = transcripts() else { return nil }
        let startOfDay = calendar.startOfDay(for: now)

        for url in transcripts {
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let size = (attributes[.size] as? NSNumber)?.uint64Value else {
                continue
            }
            let modifiedAt = (attributes[.modificationDate] as? Date) ?? .distantPast
            let key = url.path

            // Untouched since before today, so it cannot hold today's records.
            // This is what keeps the usual pass down to the few files actually
            // in use rather than every transcript ever written.
            guard modifiedAt >= startOfDay else { continue }

            var entry = progress[key] ?? FileProgress(scannedBytes: 0, tokens: 0)
            // Shrunk means replaced, not appended to; anything remembered about
            // it describes a file that no longer exists.
            if size < entry.scannedBytes {
                entry = FileProgress(scannedBytes: 0, tokens: 0)
            }
            guard size > entry.scannedBytes else {
                progress[key] = entry
                continue
            }

            let result = scan(url, from: entry.scannedBytes, today: today)
            entry.tokens += result.tokens
            entry.scannedBytes = result.scannedTo
            progress[key] = entry
        }

        return progress.values.reduce(0) { $0 + $1.tokens }
    }

    private func transcripts() -> [URL]? {
        guard let projects = try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        return projects.flatMap { project in
            ((try? fileManager.contentsOfDirectory(
                at: project,
                includingPropertiesForKeys: nil
            )) ?? []).filter { $0.pathExtension == "jsonl" }
        }
    }

    // MARK: - Scanning

    private struct ScanResult {
        let tokens: Int64
        let scannedTo: UInt64
    }

    /// Reads forward from `offset`, in chunks, stopping on the last whole line.
    ///
    /// Stopping short is deliberate: the file is being appended to while this
    /// runs, so the final line is very often half-written. Counting it would be
    /// wrong once and counting it again next pass would be wrong twice.
    private func scan(_ url: URL, from offset: UInt64, today: String) -> ScanResult {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ScanResult(tokens: 0, scannedTo: offset)
        }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)

        var tokens: Int64 = 0
        var consumed = offset
        var remainder = Data()

        while let chunk = try? handle.read(upToCount: Self.chunkBytes), !chunk.isEmpty {
            var buffer = remainder + chunk
            guard let lastBreak = buffer.lastIndex(of: UInt8(ascii: "\n")) else {
                remainder = buffer
                continue
            }
            let complete = buffer[buffer.startIndex ... lastBreak]
            remainder = Data(buffer[buffer.index(after: lastBreak)...])
            buffer = Data()

            for line in complete.split(separator: UInt8(ascii: "\n")) {
                tokens += Self.tokens(inLine: Data(line), today: today)
            }
            consumed += UInt64(complete.count)
        }
        return ScanResult(tokens: tokens, scannedTo: consumed)
    }

    private struct UsageRecord: Decodable {
        let type: String?
        let timestamp: String?
        let message: Message?

        struct Message: Decodable {
            let usage: Usage?
        }

        struct Usage: Decodable {
            let inputTokens: Int64?
            let cacheCreationInputTokens: Int64?
            let cacheReadInputTokens: Int64?
            let outputTokens: Int64?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case cacheCreationInputTokens = "cache_creation_input_tokens"
                case cacheReadInputTokens = "cache_read_input_tokens"
                case outputTokens = "output_tokens"
            }
        }
    }

    /// One line's contribution, or zero.
    ///
    /// The cheap test comes first on purpose. Most lines in a transcript are
    /// user messages, tool results and bookkeeping; decoding all of them to
    /// find the assistant ones is the difference between a scan that costs
    /// nothing and one that shows up in a CPU measurement.
    nonisolated private static func tokens(inLine line: Data, today: String) -> Int64 {
        guard line.range(of: Data("\"usage\"".utf8)) != nil,
              let record = try? JSONDecoder().decode(UsageRecord.self, from: line),
              record.type == "assistant",
              let usage = record.message?.usage,
              let timestamp = record.timestamp,
              timestamp.hasPrefix(today) else {
            return 0
        }
        // ADR 0008: everything processed, cache included, plus output.
        return (usage.inputTokens ?? 0)
            + (usage.cacheCreationInputTokens ?? 0)
            + (usage.cacheReadInputTokens ?? 0)
            + (usage.outputTokens ?? 0)
    }

    /// The day a record's timestamp starts with. Records carry UTC, so the
    /// bucket is UTC too -- comparing a UTC prefix against a local calendar day
    /// would move the boundary by the timezone offset.
    nonisolated private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
