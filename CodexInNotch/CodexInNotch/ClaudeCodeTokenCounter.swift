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
        //
        // The whole pass is pooled. Listing the projects and stat-ing every
        // transcript in them is all bridged Foundation -- `NSURL`s out of the
        // enumerator, an `NSDictionary` of `NSNumber`s and `NSDate`s out of
        // every `attributesOfItem` -- and all of it autoreleased. Measured
        // against this machine's 480-odd transcripts that is 0.93 MB per pass,
        // and this pass runs whether or not a single byte has been appended.
        let listed = autoreleasepool {
            scanTranscripts(now: now, today: today)
        }
        guard listed else { return nil }

        return progress.values.reduce(0) { $0 + $1.tokens }
    }

    /// One pass over the transcripts. False only when nothing could be listed,
    /// which is the one reason to report no figure at all.
    private func scanTranscripts(now: Date, today: String) -> Bool {
        guard let transcripts = transcripts() else { return false }
        let startOfDay = calendar.startOfDay(for: now)
        var buffer: [UInt8] = []

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
                buffer: &buffer
            )
            entry.tokens += result.tokens
            entry.scannedBytes = result.scannedTo
            progress[key] = entry
        }
        return true
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
    private func scan(
        _ url: URL,
        from offset: UInt64,
        today: String,
        buffer: inout [UInt8]
    ) -> ScanResult {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return ScanResult(tokens: 0, scannedTo: offset) }
        defer { close(descriptor) }
        guard lseek(descriptor, off_t(offset), SEEK_SET) >= 0 else {
            return ScanResult(tokens: 0, scannedTo: offset)
        }

        var tokens: Int64 = 0
        var read: UInt64 = 0
        // The tail of a line that ran past the end of a chunk. Empty except at
        // a chunk boundary, and the one place a very long record is held whole.
        var pending = Data()

        while true {
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
            scannedTo: offset + read - UInt64(pending.count)
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
    nonisolated private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
