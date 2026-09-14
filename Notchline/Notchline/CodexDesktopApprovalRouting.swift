import Darwin
import Foundation

/// Who answers a thread's approval requests.
///
/// Codex Desktop's "Approval for me" (`guardian-approvals` agent mode, CLI `--approve-for-me`)
/// sends every request to a reviewer that only allows or denies, so the thread never waits on
/// the user.
nonisolated protocol DesktopApprovalRoutingProviding: Sendable {
    func snapshot() async -> DesktopApprovalRoutingSnapshot
}

/// Which threads Codex answers approvals for, as Desktop last recorded it.
///
/// One-sided: names only threads proven automatic; anything unknown means approvals reach the user.
struct DesktopApprovalRoutingSnapshot: Equatable, Sendable {
    let automaticallyReviewedThreadIDs: Set<String>
    /// The instant this reading is a complete account up to (as
    /// ``DesktopUnreadStateSnapshot/currentAsOf``): typing holds `.codex-global-state.json` still
    /// (45.4 s, Desktop `26.820.60940`, 2026-08-26), so after change reviewer, type, send, the file
    /// still names the old reviewer. ``TurnApprovalRoutingPin`` acts on it.
    let currentAsOf: Date

    /// A reading that proves no thread automatic and against which no Turn can be judged.
    nonisolated static let unknown = Self(
        automaticallyReviewedThreadIDs: [],
        currentAsOf: .distantPast
    )

    nonisolated init(
        automaticallyReviewedThreadIDs: Set<String>,
        currentAsOf: Date
    ) {
        self.automaticallyReviewedThreadIDs = automaticallyReviewedThreadIDs
        self.currentAsOf = currentAsOf
    }

    nonisolated func approvalsReachTheUser(for threadID: String) -> Bool {
        !automaticallyReviewedThreadIDs.contains(threadID)
    }
}

/// The routing answer each live Turn started under, held for that Turn's life.
///
/// A `ThreadSettings` override does not retarget the Turn in flight, but Desktop rewrites
/// `heartbeat-thread-permissions-by-id` at once: thread `01a03241`, switched to `auto_review`
/// mid-turn, kept asking by hand while `turn_context` read `user` (measured 2026-08-24; the
/// map disagreed on 3 of 42 threads, all this way). Symmetric for a switch *to* `user`.
/// ``CodexRolloutTurnReviewerReader`` answers first; the map only fills in.
struct TurnApprovalRoutingPin: Sendable {
    /// A Turn, by the only pair that identifies one across threads.
    nonisolated struct TurnIdentity: Hashable, Sendable {
        let threadID: String
        let turnID: String

        nonisolated init(threadID: String, turnID: String) {
            self.threadID = threadID
            self.turnID = turnID
        }
    }

    /// `value` is the answer the row uses; `rolloutReading` is what the authority has been asked,
    /// and of which file.
    private struct Answer: Sendable {
        var value: Bool?
        var rolloutReading: RolloutReading = .notAsked
    }

    /// How far the Turn's own `turn_context` has been looked for. Not a `Bool`: resuming an
    /// interrupted Turn rotates the rollout and the held path can be stale, so an empty reading
    /// records the file it was made against and is final only for the Turn's own file.
    private enum RolloutReading: Sendable {
        case notAsked
        case answered
        /// Asked of the rollout the App Server named at this instant; that file lacked this Turn's record.
        case silent(pathReportedAt: Date)
    }

    /// How far into a Turn Desktop's map may have been written and still describe what that Turn
    /// started under. Mirrors ``CodexRolloutTurnReviewerReader/recordTolerance``: 4x headroom over
    /// the 500 ms debounce; deliberate mid-turn switches were measured 5:22 and 1:08 in.
    nonisolated private static let mapWindow: TimeInterval = 2

    private var answersByTurn: [TurnIdentity: Answer] = [:]

    nonisolated init() {}

    /// Whether the Turn's own `turn_context` is still worth looking for in the rollout the App
    /// Server named at `pathReportedAt`. One reading per path.
    ///
    /// - The record precedes the Turn's first hook (65 ms, CLI `0.149.0-alpha.4.3`, 2026-08-25;
    ///   34 ms on a resumed Turn, 2026-08-31), so an empty look in the Turn's own rollout is final.
    /// - The path is cached from `thread/read`, and a Turn resumed after an interrupt writes a new
    ///   rollout (thread `01a058c7`, CLI `0.151.0-alpha.7.2`, 2026-08-31); reading the old one
    ///   announced every auto-reviewed call as *Approval needed*. So an empty reading is final
    ///   only against a path reported at or after the Turn began.
    nonisolated func awaitsRolloutReading(
        forTurn turn: TurnIdentity,
        startedAt turnStartedAt: Date,
        inRolloutReportedAt pathReportedAt: Date
    ) -> Bool {
        switch answersByTurn[turn]?.rolloutReading ?? .notAsked {
        case .notAsked:
            return true
        case .answered:
            return false
        case .silent(let readPathReportedAt):
            guard readPathReportedAt < turnStartedAt else { return false }
            return pathReportedAt > readPathReportedAt
        }
    }

    /// Records what the Turn's own `turn_context` said, or (`nil`) that the rollout named at
    /// `pathReportedAt` did not carry it. `nil` claims nothing and leaves the map to answer.
    nonisolated mutating func recordRolloutReading(
        _ approvalsReachTheUser: Bool?,
        forTurn turn: TurnIdentity,
        inRolloutReportedAt pathReportedAt: Date
    ) {
        guard let approvalsReachTheUser else {
            answersByTurn[turn, default: Answer()].rolloutReading =
                .silent(pathReportedAt: pathReportedAt)
            return
        }
        // Overwrites any map answer: the map describes the thread now, this the running Turn.
        answersByTurn[turn] = Answer(
            value: approvalsReachTheUser,
            rolloutReading: .answered
        )
    }

    /// The answer for this Turn, recording it the first time the Turn is seen.
    ///
    /// - Parameter turnStartedAt: when this Turn began. Only a map written in this Turn's opening
    ///   window may answer. Too old: typing starves Desktop's debounced write
    ///   (``DesktopApprovalRoutingSnapshot/currentAsOf``), so it can name the reviewer the user
    ///   just left. Too new: it may describe a switch made after the Turn started (`01a03241`).
    ///   A refused reading pins nothing and reports that approvals reach the user. Sending clears
    ///   the persisted draft, landing the held write about half a second in.
    nonisolated mutating func approvalsReachTheUser(
        forTurn turn: TurnIdentity,
        startedAt turnStartedAt: Date,
        in snapshot: DesktopApprovalRoutingSnapshot
    ) -> Bool {
        if let pinned = answersByTurn[turn]?.value {
            return pinned
        }
        let age = snapshot.currentAsOf.timeIntervalSince(turnStartedAt)
        guard age >= 0, age <= Self.mapWindow else {
            return true
        }
        let answer = snapshot.approvalsReachTheUser(for: turn.threadID)
        answersByTurn[turn, default: Answer()].value = answer
        return answer
    }

    /// Forgets every Turn not named here; otherwise the table grows by a few thousand a week.
    nonisolated mutating func retain(turns: Set<TurnIdentity>) {
        answersByTurn = answersByTurn.filter { turns.contains($0.key) }
    }
}

/// The reviewer one running Turn was actually handed, from what Codex wrote when it started
/// the Turn (``DesktopApprovalRoutingProviding`` reads Desktop's per-thread record instead).
nonisolated protocol TurnReviewerReading: Sendable {
    /// Whether an approval on this Turn can still reach the user. `nil` means the rollout did not
    /// say (no file, no `turn_context` near its end, or another Turn's) and is not an answer.
    func approvalsReachTheUser(
        forTurn turnID: String,
        startedAt turnStartedAt: Date,
        inRolloutAt rolloutPath: String
    ) async -> Bool?
}

/// Reads `turn_context.approvals_reviewer` from the tail of a thread's rollout: the authority,
/// written at the head of every Turn and obeyed for its whole life.
///
/// - Read as the Turn begins, the record is ~1 KB from EOF (at rest: p90 ~950 KB, worst
///   20 MB). ``maximumTailByteCount`` is sized for a late refresh.
/// - The record is on disk 65–67 ms before `UserPromptSubmit` (CLI `0.149.0-alpha.4.3`,
///   2026-08-25), so an empty look means there is nothing to give, not that it is behind.
actor CodexRolloutTurnReviewerReader: TurnReviewerReading {
    /// The one reviewer name that means "not the user". An unreadable file or unknown reviewer
    /// fails to prove nobody will be asked, so it keeps approvals reaching the user.
    nonisolated private static let automaticReviewer = "auto_review"
    nonisolated private static let maximumTailByteCount = 512 * 1_024
    /// How much older than the Turn its own `turn_context` may be, for a record that does not
    /// name its Turn. The record precedes the first hook by ~65 ms; two Turns on one thread inside
    /// 2 s share a reviewer anyway.
    nonisolated private static let recordTolerance: TimeInterval = 2

    private struct TurnContextRecord: Decodable {
        let timestamp: Date
        /// The Turn this record was written for: the same id as the hook's `turn_id` (measured
        /// 2026-08-29, ADR 0011). Optional so a build without it falls back to the time window.
        let turnID: String?
        let approvalsReviewer: String?

        private enum CodingKeys: String, CodingKey {
            case timestamp
            case type
            case payload
        }

        private struct Payload: Decodable {
            let turnID: String?
            let approvalsReviewer: String?

            private enum CodingKeys: String, CodingKey {
                case turnID = "turn_id"
                case approvalsReviewer = "approvals_reviewer"
            }
        }

        private enum DecodingFailure: Error {
            case notATurnContext
            case unreadableTimestamp
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard try container.decode(String.self, forKey: .type)
                == "turn_context" else {
                throw DecodingFailure.notATurnContext
            }
            let stamp = try container.decode(String.self, forKey: .timestamp)
            guard let timestamp = CodexRolloutTimestamp.date(from: stamp) else {
                throw DecodingFailure.unreadableTimestamp
            }
            self.timestamp = timestamp
            let payload = try container.decodeIfPresent(
                Payload.self,
                forKey: .payload
            )
            turnID = payload?.turnID
            approvalsReviewer = payload?.approvalsReviewer
        }
    }

    /// The end of the file, validated once for both rollout readers.
    private let tail: CodexRolloutTail

    init(fileManager: FileManager = .default) {
        tail = CodexRolloutTail(
            maximumByteCount: Self.maximumTailByteCount,
            fileManager: fileManager
        )
    }

    func approvalsReachTheUser(
        forTurn turnID: String,
        startedAt turnStartedAt: Date,
        inRolloutAt rolloutPath: String
    ) async -> Bool? {
        guard let record = newestTurnContext(inRolloutAt: rolloutPath) else {
            return nil
        }
        // A previous Turn's record names a superseded reviewer: return nil and let the map answer.
        // A record that names its Turn settles it; the window below is a proxy that a resumed
        // Turn's old rollout can satisfy.
        if let recordedTurnID = record.turnID {
            guard recordedTurnID == turnID else { return nil }
        } else if record.timestamp
            < turnStartedAt.addingTimeInterval(-Self.recordTolerance) {
            return nil
        }
        guard let reviewer = record.approvalsReviewer else { return nil }
        return reviewer != Self.automaticReviewer
    }

    private func newestTurnContext(
        inRolloutAt rolloutPath: String
    ) -> TurnContextRecord? {
        guard let tail = try? tail.read(ofFileAt: rolloutPath) else {
            return nil
        }
        let decoder = JSONDecoder()
        // Backwards: the newest record wins, and the rest of the tail is never decoded.
        for line in tail.split(separator: UInt8(ascii: "\n")).reversed() {
            // Cheap prefilter; the decode decides. A rollout line can be tens of KB of assistant text.
            guard line.range(of: Self.turnContextMarker) != nil else { continue }
            if let record = try? decoder.decode(
                TurnContextRecord.self,
                from: line
            ) {
                return record
            }
        }
        return nil
    }

    /// The substring every `turn_context` line carries, whatever the spacing.
    nonisolated private static let turnContextMarker = Data("turn_context".utf8)
}

/// The rollout record timestamp format (`2026-08-26T04:44:51.593Z`, always UTC). The
/// formatter is cached because `ISO8601DateFormatter` is expensive to create.
nonisolated enum CodexRolloutTimestamp {
    nonisolated private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated static func date(from stamp: String) -> Date? {
        formatter.date(from: stamp)
    }
}

/// Reads the automatic-review membership out of Codex Desktop's state file.
///
/// `PermissionRequest` fires when the permission pipeline runs, not when a person is asked
/// (measured 2026-08-22, CLI `0.149.0-alpha.4.1`, `codex exec --approve-for-me`), and its
/// schema cannot tell the cases apart (`permission_mode` is `default` in both). The per-thread
/// map covered every `user` thread of the last forty (only `subagent` threads were missing).
/// `permission-selection-by-host-id:local` describes the next thread, not this one. The map is
/// a fact about the thread now, not the running Turn; ``TurnApprovalRoutingPin`` holds that.
actor CodexDesktopApprovalRoutingRepository: DesktopApprovalRoutingProviding {
    nonisolated private static let stateFileName = ".codex-global-state.json"
    nonisolated private static let maximumStateFileSize = 4 * 1_024 * 1_024
    /// The one reviewer name that means "not the user".
    nonisolated private static let automaticReviewer = "auto_review"

    private struct FileRevision: Equatable {
        let size: UInt64
        let modificationDate: Date?
        let fileNumber: UInt64?
    }

    private struct GlobalState: Decodable {
        let reviewersByThreadID: [String: String]

        private enum CodingKeys: String, CodingKey {
            case persistedAtomState = "electron-persisted-atom-state"
        }

        private struct PersistedAtomState: Decodable {
            let permissionsByThreadID: [String: ThreadPermissions]

            private enum CodingKeys: String, CodingKey {
                case permissionsByThreadID = "heartbeat-thread-permissions-by-id"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                permissionsByThreadID = try container.decodeIfPresent(
                    [String: ThreadPermissions].self,
                    forKey: .permissionsByThreadID
                ) ?? [:]
            }
        }

        /// Only the reviewer is decoded: `approvalPolicy` is sometimes a string, sometimes an object.
        private struct ThreadPermissions: Decodable {
            let approvalsReviewer: String?
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let state = try container.decodeIfPresent(
                PersistedAtomState.self,
                forKey: .persistedAtomState
            )
            reviewersByThreadID = (state?.permissionsByThreadID ?? [:])
                .compactMapValues(\.approvalsReviewer)
        }
    }

    private enum ApprovalRoutingError: Error {
        case oversizedFile(Int)
        case unsafeFile
    }

    private let stateFileURL: URL
    private let fileManager: FileManager
    /// The last map that decoded, with the instant it was written. Desktop rewrites the file
    /// atomically and often, so a mid-replacement read must not flicker *Approval needed*.
    private var lastKnownGood: DesktopApprovalRoutingSnapshot?
    private var lastSuccessfulRevision: FileRevision?

    nonisolated static func liveStateFileURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        let configuredHome = environment["NOTCHLINE_CODEX_HOME"]
            ?? environment["CODEX_HOME"]
        let codexHome: URL
        if let configuredHome, !configuredHome.isEmpty {
            codexHome = URL(
                fileURLWithPath: (configuredHome as NSString).expandingTildeInPath,
                isDirectory: true
            )
        } else {
            codexHome = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }
        return codexHome.appendingPathComponent(Self.stateFileName)
    }

    init(
        stateFileURL: URL =
            CodexDesktopApprovalRoutingRepository.liveStateFileURL(),
        fileManager: FileManager = .default
    ) {
        self.stateFileURL = stateFileURL
        self.fileManager = fileManager
    }

    /// No change stream of its own: the unread-state watcher already wakes a refresh on every
    /// write to this file.
    func snapshot() async -> DesktopApprovalRoutingSnapshot {
        let currentRevision = try? revision(of: stateFileURL)
        if currentRevision != nil,
           currentRevision == lastSuccessfulRevision,
           let lastKnownGood {
            return lastKnownGood
        }

        do {
            let (data, writtenAt) = try readValidatedData(from: stateFileURL)
            let state = try JSONDecoder().decode(GlobalState.self, from: data)
            let snapshot = DesktopApprovalRoutingSnapshot(
                automaticallyReviewedThreadIDs: Set(
                    state.reviewersByThreadID
                        .filter { $0.value == Self.automaticReviewer }
                        .keys
                ),
                // Desktop rewrites the file whole, so its modification date is when all of it was last true.
                currentAsOf: writtenAt ?? .distantPast
            )
            lastKnownGood = snapshot
            lastSuccessfulRevision = currentRevision
            return snapshot
        } catch {
            // Deliberately unreported: the fallback keeps every state the row could already show.
            return lastKnownGood ?? .unknown
        }
    }

    /// - Returns: the file's bytes, and the instant it was last written.
    ///
    /// The date is read before the bytes (see ``CodexDesktopUnreadStateRepository``): under the
    /// atomic replace that pairs an older date with newer content; the reverse silences a row.
    private func readValidatedData(
        from url: URL
    ) throws -> (data: Data, writtenAt: Date?) {
        let resourceValues = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ])
        guard resourceValues.isRegularFile == true,
              resourceValues.isSymbolicLink != true else {
            throw ApprovalRoutingError.unsafeFile
        }
        let fileSize = resourceValues.fileSize ?? 0
        guard fileSize <= Self.maximumStateFileSize else {
            throw ApprovalRoutingError.oversizedFile(fileSize)
        }

        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        if let owner = attributes[.ownerAccountID] as? NSNumber,
           owner.uint32Value != getuid() {
            throw ApprovalRoutingError.unsafeFile
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Self.maximumStateFileSize else {
            throw ApprovalRoutingError.oversizedFile(data.count)
        }
        return (data, attributes[.modificationDate] as? Date)
    }

    private func revision(of url: URL) throws -> FileRevision {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return FileRevision(
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            modificationDate: attributes[.modificationDate] as? Date,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        )
    }
}
