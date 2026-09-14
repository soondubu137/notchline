import Foundation
import os

/// Counts the tokens Claude Code has spent today: all input including cache reads, plus output
/// (ADR 0008; matches Codex, and the candidate definitions differ by 237×).
///
/// Private dependency: the transcript record structure is unpublished and registered; it fails
/// closed to no figure, never a small one.
///
/// - Skips files untouched today, resumes each file from its last offset, and decodes only lines
///   containing `usage`.
/// - None of that is a ceiling (CC-009), so a pass has a byte budget; exhausting it keeps counts,
///   reports no figure, and the next pass continues. Pipeline 600 MB/s (`-O`, warm), read 1.0
///   GB/s with `F_NOCACHE`; 128 MiB ≈ 0.2 s of one core, ~4× the heaviest day (33 MB, 2026-08-20).
actor ClaudeCodeTokenCounter {
    private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "ClaudeCodeTokenCounter"
    )

    private static let chunkBytes = 1 << 20
    /// The most one pass will read; priced in the type's doc comment.
    static let defaultPassByteBudget: UInt64 = 128 << 20

    /// Today is the UTC day, as the records' timestamps are. The mtime test must use the same
    /// calendar, or east of UTC files written between the two midnights are skipped.
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// Held so it is not built once per line.
    private static let usageMarker = Data("\"usage\"".utf8)

    private struct FileProgress {
        var scannedBytes: UInt64
        var tokens: Int64
    }

    private enum PassOutcome {
        case complete
        /// Nothing could be listed: the one reason to report no figure at all.
        case unreadable
        /// The budget ran out with files unread; counts stay and the next pass carries on.
        case halted
    }

    private let projectsDirectory: URL
    private let clock: any MonitorClock
    private let fileManager: FileManager
    private let passByteBudget: UInt64
    private var day: String?
    private var progress: [String: FileProgress] = [:]

    init(
        projectsDirectory: URL? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        fileManager: FileManager = .default,
        passByteBudget: UInt64 = ClaudeCodeTokenCounter.defaultPassByteBudget
    ) {
        self.projectsDirectory = projectsDirectory
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true)
        self.clock = clock
        self.fileManager = fileManager
        self.passByteBudget = passByteBudget
    }

    /// Today's total, or nil when nothing could be read. Zero means read with no records today; nil
    /// means unreadable, so the footer does not claim a quiet day.
    func todayTokens() -> Int64? {
        let now = clock.now()
        let today = Self.dayKey(for: now)
        if day != today {
            // A new day invalidates every running total, not the files.
            day = today
            progress = [:]
        }

        // Pooled: listing the projects is bridged, autoreleased Foundation, and this runs every pass
        // even when nothing was appended (was 0.93 MB per pass over ~480 transcripts).
        let outcome = autoreleasepool {
            scanTranscripts(now: now, today: today)
        }
        switch outcome {
        case .unreadable:
            return nil
        case .halted:
            // Counts so far stay remembered, but a partial sum is a small wrong number, so none is offered.
            Self.log.notice(
                "Today's token scan reached its \(self.passByteBudget, privacy: .public) byte budget with transcripts left unread; reporting no figure until a pass finishes."
            )
            return nil
        case .complete:
            return progress.values.reduce(0) { $0 + $1.tokens }
        }
    }

    /// One pass over the transcripts, within the byte budget. Only bytes read are charged, so a
    /// halted pass resumes at the first unfinished file.
    private func scanTranscripts(now: Date, today: String) -> PassOutcome {
        guard let transcripts = transcripts() else { return .unreadable }
        let startOfDay = Self.utcCalendar.startOfDay(for: now)
        var buffer: [UInt8] = []
        var budget = passByteBudget

        for url in transcripts {
            guard let (size, modifiedAt) = Self.sizeAndModification(of: url) else {
                continue
            }
            let key = url.path

            // Untouched since this UTC day began, so no record dated today. Measured at 00:20 UTC: 72 of
            // 516 files, 4.3 MB of 163 MB.
            guard modifiedAt >= startOfDay else { continue }

            var entry = progress[key] ?? FileProgress(scannedBytes: 0, tokens: 0)
            // Shrunk means replaced, not appended to.
            if size < entry.scannedBytes {
                entry = FileProgress(scannedBytes: 0, tokens: 0)
            }
            guard size > entry.scannedBytes else {
                progress[key] = entry
                continue
            }

            guard budget > 0 else { return .halted }

            if buffer.isEmpty {
                // Allocated lazily and reused; most passes never need it.
                buffer = [UInt8](repeating: 0, count: Self.chunkBytes)
            }
            let result = scan(
                url,
                from: entry.scannedBytes,
                today: today,
                limit: budget,
                buffer: &buffer
            )
            budget -= min(budget, result.bytesRead)
            entry.tokens += result.tokens
            entry.scannedBytes = result.scannedTo
            progress[key] = entry
        }
        return .complete
    }

    /// One transcript's size and last write, or nil when it cannot be read.
    ///
    /// `resourceValues`, not `attributesOfItem`: 5.7 ms vs 27.3 ms over 691 transcripts (Release),
    /// the gap in `_FileManagerImpl._extendedAttributes`. Read off the URL so the bulk-fetched values
    /// from ``transcripts()`` are used; URLs cache, so they are re-listed every pass, never held.
    nonisolated private static func sizeAndModification(
        of url: URL
    ) -> (size: UInt64, modifiedAt: Date)? {
        guard let values = try? url.resourceValues(forKeys: Set(scanKeys)),
              let size = values.fileSize else {
            return nil
        }
        return (
            UInt64(max(0, size)),
            values.contentModificationDate ?? .distantPast
        )
    }

    /// Named once so the bulk fetch and the per-file read cannot drift apart.
    nonisolated private static let scanKeys: [URLResourceKey] = [
        .fileSizeKey, .contentModificationDateKey
    ]

    private func transcripts() -> [URL]? {
        guard let projects = try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        return projects.flatMap { project in
            // Keys fetched here in bulk so ``sizeAndModification(of:)`` is a URL lookup: 5.7 ms a pass
            // becomes 3.2 ms over 691 transcripts (Release), all of it this listing.
            ((try? fileManager.contentsOfDirectory(
                at: project,
                includingPropertiesForKeys: Self.scanKeys
            )) ?? []).filter { $0.pathExtension == "jsonl" }
        }
    }

    // MARK: - Scanning

    private struct ScanResult {
        let tokens: Int64
        let scannedTo: UInt64
        /// Budget cost, not `scannedTo - offset`: the half-written tail was read too, and is read again.
        let bytesRead: UInt64
    }

    /// Reads forward from `offset` in chunks, stopping on the last whole line (the file is being
    /// appended to, so the last line is often half-written).
    ///
    /// `read(2)` into one reused buffer, not `FileHandle`: its autoreleased `Data` is not drained
    /// in this pool-less synchronous method (93 MB read grew the process 94 MB; 0.2 MB this way).
    /// `limit` is the remaining budget, ignored until one whole line is out, so a record longer than
    /// the budget is not re-read forever; the overshoot is one line.
    private func scan(
        _ url: URL,
        from offset: UInt64,
        today: String,
        limit: UInt64,
        buffer: inout [UInt8]
    ) -> ScanResult {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            return ScanResult(tokens: 0, scannedTo: offset, bytesRead: 0)
        }
        defer { close(descriptor) }
        guard lseek(descriptor, off_t(offset), SEEK_SET) >= 0 else {
            return ScanResult(tokens: 0, scannedTo: offset, bytesRead: 0)
        }

        var tokens: Int64 = 0
        var read: UInt64 = 0
        // The tail of a line that ran past a chunk boundary.
        var pending = Data()
        // Until a whole line has come out, the budget cannot stop the read.
        var completedALine = false

        while read < limit || !completedALine {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, Self.chunkBytes)
            }
            guard count > 0 else { break }
            read += UInt64(count)
            var start = 0
            buffer.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                // `memchr`, not a Swift byte loop: unspecialised, the loop cost 2.8 s of a core over 42 MB in
                // Debug (the launch spike) vs 0.1 s optimised; `memchr` is the same in both builds.
                while start < count,
                      let newline = memchr(
                          base + start,
                          Int32(UInt8(ascii: "\n")),
                          count - start
                      ) {
                    let index = UnsafeRawPointer(newline) - base
                    // A `memcpy`; `Data(someRawBufferSlice)` is a generic copy per line.
                    let line = Data(bytes: base + start, count: index - start)
                    tokens += Self.tokens(
                        inLine: pending.isEmpty ? line : pending + line,
                        today: today
                    )
                    if !pending.isEmpty { pending = Data() }
                    start = index + 1
                    completedALine = true
                }
                if start < count {
                    pending.append(Data(bytes: base + start, count: count - start))
                }
            }
        }
        // Up to the last newline; the next pass starts at the half-written line.
        return ScanResult(
            tokens: tokens,
            scannedTo: offset + read - UInt64(pending.count),
            bytesRead: read
        )
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

    /// One line's contribution, or zero. The cheap `usage` test comes first; most lines are not
    /// assistant records.
    nonisolated private static func tokens(inLine line: Data, today: String) -> Int64 {
        guard line.range(of: Self.usageMarker) != nil,
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

    /// The day a record's timestamp starts with, in UTC like the records.
    nonisolated private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
