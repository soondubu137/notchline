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
///
/// **None of the three is a ceiling** — all three are proportional to how much
/// Claude Code wrote today, and nothing bounds that (CC-009). So a pass also
/// carries a byte budget, and a pass that exhausts it stops where it is, keeps
/// what it counted, and reports *no figure* rather than the part it reached.
/// The next pass continues from there, so a backlog drains over a few passes
/// instead of one long one. Priced on this machine's transcripts (`-O`, warm):
/// the whole pipeline — `read(2)`, `memchr`, the `usage` test and the decode of
/// the lines that pass it — runs at 600 MB/s, and the read alone at 1.0 GB/s
/// with the page cache bypassed (`F_NOCACHE`), so the cold first scan is not
/// the expense it was assumed to be: 163 MB of *all* transcripts ever written
/// costs 0.16 s of I/O. The budget is therefore set in bytes and converted:
/// 128 MiB is about 0.2 s of one core, and about four times the heaviest day
/// measured here (33 MB written on 2026-08-20).
actor ClaudeCodeTokenCounter {
    private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "ClaudeCodeTokenCounter"
    )

    private static let chunkBytes = 1 << 20
    /// The most one pass will read. See the note above for how it was priced.
    static let defaultPassByteBudget: UInt64 = 128 << 20

    /// Today is the UTC day, because the records' timestamps are.
    ///
    /// This is the same calendar the bucket key uses, and it has to be: the
    /// mtime test decides which files can hold today's records, so a local
    /// midnight would move that line away from the one the records are sorted
    /// by. East of UTC the local day starts first, and every file written
    /// between the two midnights — the first eight hours of the UTC day in
    /// `+08` — would have been skipped while holding records dated today.
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// The marker a line must carry before it is worth decoding.
    ///
    /// Held rather than built, because it is built once per line otherwise --
    /// an allocation and a copy per line of every transcript touched today, for
    /// a value that never changes.
    private static let usageMarker = Data("\"usage\"".utf8)

    private struct FileProgress {
        var scannedBytes: UInt64
        var tokens: Int64
    }

    /// What a pass managed. Only a complete one is worth a number.
    private enum PassOutcome {
        case complete
        /// Nothing could be listed. The one reason to report no figure at all.
        case unreadable
        /// The budget ran out with files still unread. What was counted stays
        /// counted, and the next pass carries on from there.
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

    /// Today's total, or nil when nothing could be read.
    ///
    /// Zero and nil are different answers and both are true ones: zero means
    /// the transcripts were read and today has no records yet; nil means they
    /// could not be read, and the footer says so rather than claiming a quiet
    /// day.
    func todayTokens() -> Int64? {
        let now = clock.now()
        let today = Self.dayKey(for: now)
        if day != today {
            // A new day invalidates every running total, not the files.
            day = today
            progress = [:]
        }

        // Nothing readable is the only reason to report no figure. Once the
        // directory has been listed, an answer of zero is a true one: the
        // transcripts were read and today has nothing in them yet.
        //
        // The whole pass is pooled. Listing the projects is bridged Foundation
        // -- `NSURL`s out of the enumerator, and the resource values fetched
        // with them -- and all of it autoreleased. Measured against this
        // machine's 480-odd transcripts that was 0.93 MB per pass when every
        // file's attributes came back as an `NSDictionary` of its own; the
        // bulk fetch in ``transcripts()`` has since taken the per-file
        // dictionary out of it, and the pool stays because the listing itself
        // still allocates and this pass runs whether or not a single byte has
        // been appended.
        let outcome = autoreleasepool {
            scanTranscripts(now: now, today: today)
        }
        switch outcome {
        case .unreadable:
            return nil
        case .halted:
            // Everything read so far is still counted and still remembered;
            // what is missing is the rest of the list. A sum over part of the
            // transcripts is a small wrong number, so it is not offered.
            Self.log.notice(
                "Today's token scan reached its \(self.passByteBudget, privacy: .public) byte budget with transcripts left unread; reporting no figure until a pass finishes."
            )
            return nil
        case .complete:
            return progress.values.reduce(0) { $0 + $1.tokens }
        }
    }

    /// One pass over the transcripts, within one pass's worth of reading.
    ///
    /// The budget is spent only on bytes actually read: a file already scanned
    /// to its current size costs a `stat` and nothing else, so a pass that
    /// halted resumes at the first file it did not finish rather than paying
    /// again for the ones it did.
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

            // Untouched since this UTC day began, so it cannot hold a record
            // dated today. This is what keeps the usual pass down to the few
            // files actually in use rather than every transcript ever written:
            // measured here at 00:20 UTC, 72 of 516 files and 4.3 MB of 163 MB
            // -- and 72 rather than the 277 the local midnight used to admit.
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

            guard budget > 0 else { return .halted }

            if buffer.isEmpty {
                // Allocated on the first file that actually needs reading, and
                // reused by every one after it. Most passes find nothing to
                // read and never allocate it at all.
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
    /// **`resourceValues`, not `attributesOfItem`.** The two answer the same
    /// two questions and cost an order of magnitude apart, because
    /// `attributesOfItem` answers a dozen more on the way: measured over this
    /// machine's 691 transcripts in Release, a pass of
    /// `attributesOfItem(atPath:)` costs 27.3 ms against 5.7 ms for this, and
    /// a `sample` of the live app puts the majority of that difference inside
    /// `_FileManagerImpl._extendedAttributes` -- extended attributes and ACLs
    /// nothing here reads. See ``scanKeys`` for where the remaining 5.7 ms
    /// goes.
    ///
    /// Read off the URL rather than the path so the values ``transcripts()``
    /// has already fetched in bulk are the ones used. A URL caches what it was
    /// asked for, which is why these are re-listed every pass rather than
    /// held: a cached size that never refreshes would freeze every transcript
    /// at the length it had when the app started.
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

    /// What every pass wants to know about a transcript, named once so the
    /// bulk fetch below and the read above cannot drift apart.
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
            // The keys are asked for **here**, in the directory read, not left
            // to the per-file read that wants them. `contentsOfDirectory`
            // fetches them in bulk for the whole directory, and every
            // ``sizeAndModification(of:)`` afterwards is then a lookup on the
            // URL rather than a trip to the file system: measured in Release
            // over 691 transcripts, 5.7 ms a pass becomes 3.2 ms, of which 3.2
            // ms is this listing and the stats are free.
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
        /// What this cost the pass's budget, which is not `scannedTo - offset`:
        /// the half-written tail was read too, and is read again next time.
        let bytesRead: UInt64
    }

    /// Reads forward from `offset`, in chunks, stopping on the last whole line.
    ///
    /// Stopping short is deliberate: the file is being appended to while this
    /// runs, so the final line is very often half-written. Counting it would be
    /// wrong once and counting it again next pass would be wrong twice.
    ///
    /// **`read(2)` into one reused buffer, not `FileHandle`.** That reads like
    /// a micro-optimisation and is not one: `FileHandle.read(upToCount:)` hands
    /// back an *autoreleased* `Data`, and this runs inside a synchronous actor
    /// method with no pool of its own, so nothing drains until the whole pass
    /// is over. Measured here: 93 MB read that way grows the process by 94 MB
    /// and it stays; the identical reads through a reused buffer cost 0.2 MB.
    /// The app's memory was the day's transcripts, one megabyte of footprint
    /// per megabyte ever read -- which is why it settled tens of megabytes
    /// higher after a heavy day of Claude Code than after a quiet one.
    ///
    /// `limit` is what is left of the pass's budget. A file longer than that
    /// is read as far as the budget goes and picked up next pass -- except
    /// while nothing whole has come out of it yet, because the offset only
    /// advances to a newline and a record longer than the entire budget would
    /// otherwise be re-read by every pass and counted by none of them. The
    /// overshoot is therefore one line, never one file.
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
        // The tail of a line that ran past the end of a chunk. Empty except at
        // a chunk boundary, and the one place a very long record is held whole.
        var pending = Data()
        // Whether anything whole has come out of this file yet. Until it has,
        // the budget cannot stop the read -- see the note above.
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
                // The newlines are found with `memchr`, not by looking at every
                // byte from Swift. A megabyte of transcript is a megabyte of
                // iterations, and an iteration over an `UnsafeRawBufferPointer`
                // is only cheap once the optimiser has specialised it:
                // unspecialised it goes through `IndexingIterator.next()`, a
                // protocol witness for `formIndex(after:)` and a generic
                // metadata lookup, per byte. Measured against this machine's
                // 42 MB of same-day transcripts, that pass cost **2.8 seconds
                // of a core** in a debug build -- the whole of the launch spike
                // this file was blamed for -- against 0.1 s for the identical
                // pass optimised. `memchr` costs the same in both builds, so
                // the spike stops depending on which configuration is running.
                // The work per *line* is unchanged.
                while start < count,
                      let newline = memchr(
                          base + start,
                          Int32(UInt8(ascii: "\n")),
                          count - start
                      ) {
                    let index = UnsafeRawPointer(newline) - base
                    // Copied by `memcpy` rather than element by element, for
                    // the reason above: `Data(someRawBufferSlice)` is a generic
                    // sequence copy, and there is one per line.
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
        // Everything up to the last newline seen. What is still pending is the
        // half-written line, and the next pass starts at it.
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

    /// One line's contribution, or zero.
    ///
    /// The cheap test comes first on purpose. Most lines in a transcript are
    /// user messages, tool results and bookkeeping; decoding all of them to
    /// find the assistant ones is the difference between a scan that costs
    /// nothing and one that shows up in a CPU measurement.
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

    /// The day a record's timestamp starts with. Records carry UTC, so the
    /// bucket is UTC too -- comparing a UTC prefix against a local calendar day
    /// would move the boundary by the timezone offset.
    nonisolated private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
