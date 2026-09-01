import Foundation

/// The end of a Codex rollout, read the one safe way.
///
/// Shared by the two readers that ask a rollout a question --
/// ``CodexRolloutTurnReviewerReader`` and ``CodexRolloutTurnAbortReader`` --
/// because the validation is the part that must not be written twice. The path
/// is handed over by the App Server, so a rollout is only ever read when it is
/// a regular file this user owns: no symlink, no other account's file, and
/// nothing large enough to be something else entirely.
///
/// Not `Sendable`, and it does not need to be: both holders are actors that
/// keep it as a private stored property, so it never crosses an isolation
/// boundary — and `FileManager` is not `Sendable` either.
nonisolated struct CodexRolloutTail {
    enum ReadError: Error {
        case unsafeFile
    }

    /// How much of the end of the file is read.
    let maximumByteCount: Int
    let fileManager: FileManager

    nonisolated init(maximumByteCount: Int, fileManager: FileManager = .default) {
        self.maximumByteCount = maximumByteCount
        self.fileManager = fileManager
    }

    /// The last ``maximumByteCount`` bytes of the file, minus a partial first
    /// line.
    func read(ofFileAt path: String) throws -> Data {
        let url = URL(fileURLWithPath: path)
        let resourceValues = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ])
        guard resourceValues.isRegularFile == true,
              resourceValues.isSymbolicLink != true else {
            throw ReadError.unsafeFile
        }
        let attributes = try fileManager.attributesOfItem(atPath: path)
        if let owner = attributes[.ownerAccountID] as? NSNumber,
           owner.uint32Value != getuid() {
            throw ReadError.unsafeFile
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = resourceValues.fileSize ?? 0
        let startsAtHead = size <= maximumByteCount
        if !startsAtHead {
            try handle.seek(toOffset: UInt64(size - maximumByteCount))
        }
        let tail = try handle.readToEnd() ?? Data()
        guard !startsAtHead else { return tail }
        // A seek lands mid-record, and half a JSON object decodes as nothing.
        guard let firstBreak = tail.firstIndex(of: UInt8(ascii: "\n")) else {
            return Data()
        }
        return Data(tail[tail.index(after: firstBreak)...])
    }
}

/// Whether a Turn this app is still holding open was aborted.
///
/// Split from ``TurnReviewerReading`` although both read the same file: that
/// one is asked once, at the head of a Turn, and this one is asked for as long
/// as the Turn stays open.
nonisolated protocol CodexTurnAbortReading: Sendable {
    /// When Codex recorded this Turn being aborted, or nil when it did not.
    ///
    /// - Parameter after: The Turn's last known moment. A record older than
    ///   that describes a Turn that has moved since, so it settles nothing.
    func abortedAt(
        turnID: String,
        inRolloutAt rolloutPath: String,
        after lastEventAt: Date
    ) async -> Date?

    /// Drops what is remembered about rollouts nothing is waiting on.
    func retain(rolloutPaths: Set<String>) async
}

/// Which Turn a thread's own rollout says the thread is on.
///
/// **The second question the tail of a running Thread's rollout answers**, and
/// the reason it is asked of the same reader rather than of the one named for
/// `turn_context`: ``CodexRolloutTurnReviewerReader`` reads that record once,
/// at the head of a Turn, while this is asked for as long as a prompt is being
/// held back — the cadence above, and the cache above, which already pays for a
/// tail read of this file on every refresh. Asking it here costs nothing beyond
/// the decode of the lines already in hand.
///
/// **Its silence is the refusal, and no reading has to produce one.** `nil`
/// means the record was not found — no such file, an unreadable one, or a Turn
/// that has appended more than the tail holds since — and a held prompt that is
/// never answered for simply stays held, which is the safe direction. Nothing
/// here ever has to prove a Turn belongs to *another* agent: a Turn this
/// thread's own record does not name is one this app declines to adopt.
nonisolated protocol CodexTurnOnRecordReading: Sendable {
    /// The Turn named by the newest `turn_context` in this rollout.
    ///
    /// Newest and nothing else, which is what makes it an answer about
    /// identity: at any instant the last `turn_context` a thread's rollout
    /// holds names the Turn that thread is on.
    func turnOnRecord(inRolloutAt rolloutPath: String) async -> String?
}

/// Reads `turn_aborted` from the tail of a running Thread's rollout.
///
/// **A stopped Codex Turn sends nothing, and this is the only thing it leaves.**
/// Pressing stop in Codex Desktop produces no `Stop` hook and not even the
/// `PostToolUse` for the call that was still open (measured 2026-08-24, and
/// again 2026-08-29 against Desktop `26.820.60940`: `turn/interrupt` reaches
/// the App Server and the hook socket stays silent from that moment on). So the
/// row went on saying *Running*, with its timer counting, until the user
/// resumed that exact thread or right-clicked the row away — for ever, on a
/// thread they simply left alone. Archiving a working thread is the same
/// interrupt with a second step after it, so that row said *Running* too, until
/// membership reconciliation retired it a metadata interval later.
///
/// What Codex does do is write the abort into the thread's own rollout:
///
/// ```text
/// {"timestamp":"2026-08-29T18:19:05.998Z","type":"event_msg",
///  "payload":{"type":"turn_aborted","turn_id":"01a04ebf-1813-…",
///             "reason":"interrupted","duration_ms":4466}}
/// ```
///
/// **It names the Turn, so it may only end that one** — the tighter pinning
/// [ADR 0011](../../docs/adr/0011-a-turn-may-end-on-evidence-that-is-not-a-hook-event.md)
/// requires of evidence that carries identity. `turn_id` is the value the hooks
/// carry under the same name: it is the id of the submission that opened the
/// Turn, written into that Turn's own `turn_context` at its head — the record
/// ``CodexRolloutTurnReviewerReader`` already matches to a Turn — and it is the
/// `turnId` `thread/items/list` accepts for this Turn (`tech-design.md` §17).
///
/// **`reason` is deliberately not read.** Every one of the 18 aborts on this
/// machine says `interrupted`, and requiring that word would mean a reason a
/// later Codex invents leaves the row Running for ever, which is the failure
/// this reader exists to end. A `turn_aborted` naming this Turn says the Turn
/// is over whatever ended it, and that is the whole reading.
///
/// **Reading it is cheap at the only moment it is read.** The abort is the last
/// thing written to the rollout when it happens, and what follows it before the
/// user says anything again is a `token_count` and a `thread_settings_applied`:
/// measured over this machine's rollouts, an abort whose thread was left alone
/// sits 249–940 bytes from the end, against tens of megabytes for one the user
/// went on working past. ``maximumTailByteCount`` is sized for a refresh that
/// is late, not for one that is on time. The answer is cached on the file's
/// `(size, mtime)`, so the ordinary refresh — asked once per open Turn — costs
/// one `lstat` and no read at all.
actor CodexRolloutTurnAbortReader: CodexTurnAbortReading, CodexTurnOnRecordReading {
    /// How much of the end of the rollout is scanned for the record.
    nonisolated private static let maximumTailByteCount = 64 * 1_024
    /// The substring every `turn_aborted` line carries, whatever the spacing.
    nonisolated private static let abortMarker = Data("turn_aborted".utf8)
    /// The substring every `turn_context` line carries, whatever the spacing.
    nonisolated private static let turnContextMarker = Data("turn_context".utf8)

    /// One rollout's two newest records, as of one revision of the file.
    ///
    /// **Both, from one read.** They are the two halves of what this app has to
    /// ask a file about a Turn it is holding open — whose Turn it is, and
    /// whether it is over — and they are written to the same file by the same
    /// process. Reading them separately would double a cost that is already
    /// paid once per open Turn per refresh.
    private struct Entry: Sendable {
        let size: Int
        let modifiedAt: Date
        let abort: TurnAbort?
        /// The Turn the newest `turn_context` names, where it names one.
        let turnOnRecord: String?
    }

    private struct TurnAbort: Sendable {
        let turnID: String
        let at: Date
    }

    /// The record, reduced to the two fields the reading needs.
    ///
    /// **There is no text field**, for the reason ``AgentHookListener``'s
    /// decoder has none: what a Turn said is not this reader's question, and
    /// nothing here should be able to hold it by accident.
    private struct TurnAbortRecord: Decodable {
        let timestamp: Date
        let turnID: String

        private enum CodingKeys: String, CodingKey {
            case timestamp
            case type
            case payload
        }

        private struct Payload: Decodable {
            let type: String?
            let turnID: String?

            private enum CodingKeys: String, CodingKey {
                case type
                case turnID = "turn_id"
            }
        }

        private enum DecodingFailure: Error {
            case notATurnAbort
            case unreadableTimestamp
            case unnamedTurn
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Both halves, because the word alone is not the record: the
            // developer message Codex writes one line earlier carries
            // `<turn_aborted>` in its text.
            guard try container.decode(String.self, forKey: .type) == "event_msg",
                  let payload = try container.decodeIfPresent(
                    Payload.self,
                    forKey: .payload
                  ),
                  payload.type == "turn_aborted" else {
                throw DecodingFailure.notATurnAbort
            }
            guard let turnID = payload.turnID, !turnID.isEmpty else {
                throw DecodingFailure.unnamedTurn
            }
            let stamp = try container.decode(String.self, forKey: .timestamp)
            guard let timestamp = CodexRolloutTimestamp.date(from: stamp) else {
                throw DecodingFailure.unreadableTimestamp
            }
            self.timestamp = timestamp
            self.turnID = turnID
        }
    }

    /// The record at the head of a Turn, reduced to the Turn it names.
    ///
    /// The reviewer's reader decodes the same record for the other field it
    /// carries. Not shared, and deliberately: that one falls back to a time
    /// window when the record does not name its Turn, which is a good proxy for
    /// *which reviewer* and no proxy at all for *whose Turn* — a nested agent's
    /// turn begins inside its parent's, which is the one place the two cannot
    /// be told apart by time. Here an unnamed Turn is no answer, so the field
    /// is required and its absence throws.
    private struct TurnContextRecord: Decodable {
        let turnID: String

        private enum CodingKeys: String, CodingKey {
            case type
            case payload
        }

        private struct Payload: Decodable {
            let turnID: String?

            private enum CodingKeys: String, CodingKey {
                case turnID = "turn_id"
            }
        }

        private enum DecodingFailure: Error {
            case notATurnContext
            case unnamedTurn
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard try container.decode(String.self, forKey: .type)
                == "turn_context" else {
                throw DecodingFailure.notATurnContext
            }
            guard let turnID = try container.decodeIfPresent(
                Payload.self,
                forKey: .payload
            )?.turnID, !turnID.isEmpty else {
                throw DecodingFailure.unnamedTurn
            }
            self.turnID = turnID
        }
    }

    private let tail: CodexRolloutTail
    private var entries: [String: Entry] = [:]

    init(fileManager: FileManager = .default) {
        tail = CodexRolloutTail(
            maximumByteCount: Self.maximumTailByteCount,
            fileManager: fileManager
        )
    }

    func abortedAt(
        turnID: String,
        inRolloutAt rolloutPath: String,
        after lastEventAt: Date
    ) -> Date? {
        guard let abort = entry(forRolloutAt: rolloutPath).abort,
              abort.turnID == turnID,
              abort.at > lastEventAt else {
            return nil
        }
        return abort.at
    }

    func turnOnRecord(inRolloutAt rolloutPath: String) -> String? {
        entry(forRolloutAt: rolloutPath).turnOnRecord
    }

    /// This rollout's two newest records, read once per revision of the file.
    private func entry(forRolloutAt rolloutPath: String) -> Entry {
        let (size, modifiedAt) = Self.revision(ofFileAt: rolloutPath)
        if let cached = entries[rolloutPath],
           cached.size == size, cached.modifiedAt == modifiedAt {
            return cached
        }
        let records = newestRecords(inRolloutAt: rolloutPath)
        let entry = Entry(
            size: size,
            modifiedAt: modifiedAt,
            abort: records.abort,
            turnOnRecord: records.turnOnRecord
        )
        entries[rolloutPath] = entry
        return entry
    }

    func retain(rolloutPaths: Set<String>) {
        entries = entries.filter { rolloutPaths.contains($0.key) }
    }

    /// The newest abort and the newest `turn_context` in the tail.
    ///
    /// Newest and nothing else, for both. An older abort naming this Turn would
    /// describe a Turn that ended before one this rollout has since recorded
    /// ending, which is not a thing a Turn this app is still holding open can
    /// be; an older `turn_context` names a Turn this thread has since moved
    /// past. Reading only the last of each is what keeps this to two decodes,
    /// and stopping once both are in hand is what keeps a long tail from being
    /// walked to its head.
    private func newestRecords(
        inRolloutAt rolloutPath: String
    ) -> (abort: TurnAbort?, turnOnRecord: String?) {
        guard let tail = try? tail.read(ofFileAt: rolloutPath) else {
            return (nil, nil)
        }
        let decoder = JSONDecoder()
        var abort: TurnAbort?
        var turnOnRecord: String?
        for line in tail.split(separator: UInt8(ascii: "\n")).reversed() {
            if abort != nil, turnOnRecord != nil { break }
            // The decode is the test of what a line is. These only keep the
            // other lines from reaching it, and a rollout line can be tens of
            // kilobytes of assistant text.
            if abort == nil, line.range(of: Self.abortMarker) != nil,
               let record = try? decoder.decode(TurnAbortRecord.self, from: line) {
                abort = TurnAbort(turnID: record.turnID, at: record.timestamp)
                continue
            }
            if turnOnRecord == nil, line.range(of: Self.turnContextMarker) != nil,
               let record = try? decoder.decode(TurnContextRecord.self, from: line) {
                turnOnRecord = record.turnID
            }
        }
        return (abort, turnOnRecord)
    }

    /// The file's size and modification time, or a revision nothing matches.
    ///
    /// `lstat` rather than `FileManager`, for the reason
    /// ``ClaudeCodeTranscriptReader`` uses it: this runs once per open Turn per
    /// refresh, and it is the whole cost of the cache being worth having.
    nonisolated private static func revision(
        ofFileAt path: String
    ) -> (Int, Date) {
        var status = stat()
        guard lstat(path, &status) == 0 else { return (0, .distantPast) }
        let modified = status.st_mtimespec
        return (
            Int(status.st_size),
            Date(
                timeIntervalSince1970: TimeInterval(modified.tv_sec)
                    + TimeInterval(modified.tv_nsec) / 1_000_000_000
            )
        )
    }
}
