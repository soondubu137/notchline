import Foundation

/// The end of a Codex rollout, validated in one place for ``CodexRolloutTurnReviewerReader``
/// and ``CodexRolloutTurnAbortReader``. The path comes from the App Server, so only a regular
/// file this user owns, not a symlink and not oversized, is read. Not `Sendable`: each holder
/// is an actor keeping it private.
nonisolated struct CodexRolloutTail {
    enum ReadError: Error {
        case unsafeFile
    }

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

/// Whether a Turn this app still holds open was aborted; asked for as long as it stays open.
nonisolated protocol CodexTurnAbortReading: Sendable {
    /// When Codex recorded this Turn being aborted, or nil.
    ///
    /// - Parameter after: The Turn's last known moment; an older record settles nothing.
    func abortedAt(
        turnID: String,
        inRolloutAt rolloutPath: String,
        after lastEventAt: Date
    ) async -> Date?

    /// Drops what is remembered about rollouts nothing is waiting on.
    func retain(rolloutPaths: Set<String>) async
}

/// Which Turn a thread's own rollout says the thread is on. Asked of the abort reader, whose
/// cached tail read already happens each refresh. `nil` keeps a held prompt held: a Turn the
/// thread's own record does not name is not adopted.
nonisolated protocol CodexTurnOnRecordReading: Sendable {
    /// The Turn named by the newest `turn_context` in this rollout: the Turn the thread is on.
    func turnOnRecord(inRolloutAt rolloutPath: String) async -> String?
}

/// Reads `turn_aborted` from the tail of a running Thread's rollout.
///
/// A stopped Codex Turn sends no `Stop` hook, not even the open call's `PostToolUse` (measured
/// 2026-08-24 and 2026-08-29, Desktop `26.820.60940`); this record is all it leaves:
///
/// ```text
/// {"timestamp":"2026-08-29T18:19:05.998Z","type":"event_msg",
///  "payload":{"type":"turn_aborted","turn_id":"01a04ebf-1813-…",
///             "reason":"interrupted","duration_ms":4466}}
/// ```
///
/// - It names the Turn, so it may end only that one (ADR 0011); `turn_id` is the hooks' id.
/// - `reason` is not read: a reason a later Codex invents must not leave a row Running.
/// - A left-alone abort sits 249–940 bytes from EOF; ``maximumTailByteCount`` covers a late
///   refresh. Cached on `(size, mtime)`, so the ordinary refresh costs one `lstat`.
actor CodexRolloutTurnAbortReader: CodexTurnAbortReading, CodexTurnOnRecordReading {
    nonisolated private static let maximumTailByteCount = 64 * 1_024
    /// The substring every `turn_aborted` line carries, whatever the spacing.
    nonisolated private static let abortMarker = Data("turn_aborted".utf8)
    /// The substring every `turn_context` line carries, whatever the spacing.
    nonisolated private static let turnContextMarker = Data("turn_context".utf8)

    /// One rollout's two newest records as of one file revision, taken from one read.
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

    /// The record, reduced to the two fields the reading needs; deliberately no text field.
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
            // Both halves: the developer message one line earlier carries `<turn_aborted>` in its text.
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

    /// The record at the head of a Turn, reduced to the Turn it names. Not shared with the
    /// reviewer's reader: its time-window fallback cannot tell a nested agent's Turn from its
    /// parent's, so here the field is required and its absence throws.
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

    /// The newest abort and the newest `turn_context` in the tail; older ones describe Turns since
    /// superseded. Stops once both are in hand.
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
            // Cheap prefilter; the decode decides. A rollout line can be tens of KB of assistant text.
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

    /// The file's size and modification time, or a revision nothing matches. `lstat`, not
    /// `FileManager` (as in ``ClaudeCodeTranscriptReader``): it runs once per open Turn per refresh.
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
