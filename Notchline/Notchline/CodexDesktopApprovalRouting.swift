import Darwin
import Foundation

/// Who answers a thread's approval requests.
///
/// Codex Desktop offers "Approval for me" (the `guardian-approvals` agent mode,
/// the `--approve-for-me` flag on the CLI), which routes every approval request
/// to an automatic reviewer instead of to the person. The reviewer is a model
/// turn of its own, and its answer is only ever *allow* or *deny* — it has no
/// outcome that escalates back to the human. A thread in that mode therefore
/// cannot park on an approval the user has to clear.
nonisolated protocol DesktopApprovalRoutingProviding: Sendable {
    func snapshot() async -> DesktopApprovalRoutingSnapshot
}

/// Which threads Codex answers approvals for, as Desktop last recorded it.
///
/// Deliberately one-sided: it names only the threads *proven* to be reviewed
/// automatically. The absent case and the unrecognised case are the same
/// answer, and it is the answer that changes nothing — because the claim this
/// snapshot exists to make is "nobody will be asked", and an unreadable file,
/// a thread Desktop has not recorded, or a reviewer name a later Desktop
/// invents are all failures to make it. Getting that backwards would silence
/// the one state the product exists to show.
struct DesktopApprovalRoutingSnapshot: Equatable, Sendable {
    /// Threads whose approval requests Codex answers on the user's behalf.
    let automaticallyReviewedThreadIDs: Set<String>

    nonisolated static let unknown = Self(automaticallyReviewedThreadIDs: [])

    nonisolated init(automaticallyReviewedThreadIDs: Set<String>) {
        self.automaticallyReviewedThreadIDs = automaticallyReviewedThreadIDs
    }

    /// Whether an approval request on this thread can still reach the user.
    nonisolated func approvalsReachTheUser(for threadID: String) -> Bool {
        !automaticallyReviewedThreadIDs.contains(threadID)
    }
}

/// The routing answer each live Turn started under, held for that Turn's life.
///
/// **The map is a fact about the thread now; a row is a fact about the Turn
/// that is running.** Codex Desktop rewrites
/// `heartbeat-thread-permissions-by-id` the instant the thread's reviewer
/// changes, and a `ThreadSettings` override does not retarget the turn already
/// in flight. Measured 2026-08-24 against this machine's Desktop log: thread
/// `01a03241` started under `user` at 22:32:13, was switched to `auto_review`
/// at 22:37:35, and went on opening approval dialogs the user answered by hand
/// at 22:40:07, 22:40:28, 22:41:10, 22:42:10 and 22:42:28 — the `rm -rf` this
/// was reported against among them. The rollout's
/// `turn_context.approvals_reviewer`, which is the authority the running turn
/// actually used, still read `user` through all of it. Asking the map at
/// projection time silenced every one of those dialogs, and the row sat on
/// *Running* while the user was being asked. Thread `01a03130` shows the same
/// shape five hours earlier: switched at 17:34:53, answered by hand at
/// 17:36:01.
///
/// The map is right far more often than not — over the 42 threads whose
/// rollout was still on disk it agreed with `turn_context` 39 times — but all
/// three disagreements were threads whose reviewer changed mid-turn, and all
/// three fell in the one direction that hides the state the product exists to
/// show.
///
/// So the answer is taken once, when a Turn is first seen, and reused until
/// that Turn is gone. Symmetric on purpose: a thread switched *to* `user`
/// mid-turn is still being reviewed automatically for the rest of that turn,
/// and the row must not start asking the user to clear a prompt nobody will
/// be shown.
///
/// **The map is the fallback now, not the source.** An earlier version of this
/// comment left the map as the only source and named its remaining hole — a
/// Turn whose first refresh lands before Desktop has persisted a switch pins
/// the stale answer for that Turn's whole life — as an escalation to pay for
/// only if it ever proved itself. It proved itself: reported 2026-08-25 as
/// *Approval needed* on rows where nobody was being asked, on sessions whose
/// mode had been switched from manual to automatic partway through and never on
/// sessions started in automatic mode. That is the signature of a stale map
/// exactly, because a session started in automatic mode has nothing to persist.
///
/// So ``CodexRolloutTurnReviewerReader`` is asked first, and this holds what it
/// said. The map answers only while that reading is outstanding and for the
/// Turns it cannot answer for at all.
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

    /// What is known about one Turn's routing.
    ///
    /// The two fields answer different questions and neither implies the other:
    /// `value` is the answer the row uses, `hasReadRollout` is whether the
    /// authority has already been asked. A Turn whose rollout answered has
    /// both; a Turn whose rollout could not be read has only the second, and
    /// falls back to the map for the rest of its life rather than re-reading a
    /// file that will not gain the record it is missing.
    private struct Answer: Sendable {
        var value: Bool?
        var hasReadRollout = false
    }

    private var answersByTurn: [TurnIdentity: Answer] = [:]

    nonisolated init() {}

    /// Whether the Turn's own `turn_context` has yet to be looked for.
    ///
    /// Asked once per Turn and not once per refresh: the record is written
    /// *before* the hook that makes this app aware of the Turn — measured
    /// 2026-08-25 against CLI `0.149.0-alpha.4.3`, `turn_context` at
    /// `…491.593` and `UserPromptSubmit` at `…491.660`, and again 65 ms apart
    /// on an `--approve-for-me` run — so a look that finds nothing is looking
    /// at a rollout that will never carry it, not at one that has not caught
    /// up.
    nonisolated func awaitsRolloutReading(forTurn turn: TurnIdentity) -> Bool {
        !(answersByTurn[turn]?.hasReadRollout ?? false)
    }

    /// Records what the Turn's own `turn_context` said, or that it said nothing.
    ///
    /// `nil` is the second case, and it is deliberately not the same as an
    /// answer: it closes the reading without claiming anything, leaving the map
    /// to supply the value exactly as it did before this reading existed.
    nonisolated mutating func recordRolloutReading(
        _ approvalsReachTheUser: Bool?,
        forTurn turn: TurnIdentity
    ) {
        guard let approvalsReachTheUser else {
            answersByTurn[turn, default: Answer()].hasReadRollout = true
            return
        }
        // Overwrites a map answer this Turn may already have been given. That
        // is the whole point: the map is a fact about the thread now, and this
        // is the reviewer the running Turn was handed.
        answersByTurn[turn] = Answer(
            value: approvalsReachTheUser,
            hasReadRollout: true
        )
    }

    /// The answer for this Turn, recording it the first time the Turn is seen.
    nonisolated mutating func approvalsReachTheUser(
        forTurn turn: TurnIdentity,
        in snapshot: DesktopApprovalRoutingSnapshot
    ) -> Bool {
        if let pinned = answersByTurn[turn]?.value {
            return pinned
        }
        let answer = snapshot.approvalsReachTheUser(for: turn.threadID)
        answersByTurn[turn, default: Answer()].value = answer
        return answer
    }

    /// Forgets every Turn not named here.
    ///
    /// Without it the table grows by one entry per Turn for as long as the app
    /// is open, which on this machine's usage is a few thousand a week — small,
    /// but unbounded, and the caller already walks exactly the set that is
    /// still live.
    nonisolated mutating func retain(turns: Set<TurnIdentity>) {
        answersByTurn = answersByTurn.filter { turns.contains($0.key) }
    }
}

/// The reviewer one running Turn was actually handed.
///
/// Split from ``DesktopApprovalRoutingProviding`` because the two answer
/// different questions from different sources: that one reads what Desktop last
/// recorded about a *thread*, this one reads what Codex wrote down when it
/// started this *Turn*.
nonisolated protocol TurnReviewerReading: Sendable {
    /// Whether an approval on this Turn can still reach the user.
    ///
    /// `nil` means the rollout did not say — no such file, no `turn_context`
    /// near its end, or none recent enough to be this Turn's. It is not an
    /// answer and must not be treated as one.
    func approvalsReachTheUser(
        forTurnStartedAt turnStartedAt: Date,
        inRolloutAt rolloutPath: String
    ) async -> Bool?
}

/// Reads `turn_context.approvals_reviewer` from the tail of a thread's rollout.
///
/// **This is the authority, and the only one.** Codex writes a `turn_context`
/// record at the head of every Turn naming the reviewer that Turn will use, and
/// that value is what the turn goes on to obey for its whole life — a
/// `ThreadSettings` override applied mid-turn changes the *thread*, not the
/// turn in flight (the timings for that are in ``TurnApprovalRoutingPin``).
/// Desktop's `heartbeat-thread-permissions-by-id` is a copy of the thread's
/// current setting, written by a different process at a time nobody here
/// controls; this record is the turn's own.
///
/// **Reading it is cheap at the only moment it is read.** The p90 of "how far
/// is the last `turn_context` from EOF" over this machine's rollouts is ~950 KB
/// and the worst is 20 MB, but those are rollouts at rest, with a turn's worth
/// of items appended after the record. This reader looks when the Turn has just
/// begun, which is when the record is the newest thing in the file: measured
/// 2026-08-25 against CLI `0.149.0-alpha.4.3`, ~1 KB from EOF at the moment
/// `UserPromptSubmit` fired. ``maximumTailByteCount`` is sized for the case
/// where a refresh is late rather than for the case where it is on time.
///
/// **And it is read before the app has heard of the Turn.** Same measurement,
/// twice: `turn_context` at `…491.593` against `UserPromptSubmit` at
/// `…491.660`, and on an `--approve-for-me` run `…561.167` against `…561.232`.
/// 65 ms and 67 ms — the record is on disk first, so a look that comes up empty
/// is looking at a rollout that has nothing to give rather than one that is
/// behind. That is what lets the caller ask once per Turn instead of once per
/// refresh.
actor CodexRolloutTurnReviewerReader: TurnReviewerReading {
    /// The one reviewer name that means "not the user".
    ///
    /// One-sided for the same reason the map is: an unreadable file, a record
    /// this build does not recognise, or a reviewer a later Codex invents all
    /// fail to prove "nobody will be asked", and the answer to a failed proof
    /// is the state that keeps the row honest.
    nonisolated private static let automaticReviewer = "auto_review"
    /// How much of the end of the rollout is scanned for the record.
    nonisolated private static let maximumTailByteCount = 512 * 1_024
    /// How much older than the Turn its own `turn_context` may be.
    ///
    /// The record precedes the Turn's first hook by ~65 ms measured, and the
    /// Turn's `startedAt` is that hook's arrival, so this Turn's record is
    /// always a little *older* than `startedAt` and the previous Turn's is
    /// older by however long the user took to type. Two seconds separates them
    /// with three orders of magnitude of headroom, and where it does not — two
    /// Turns opened on one thread inside two seconds — the two share a
    /// reviewer anyway, because nobody switched a mode in between.
    nonisolated private static let recordTolerance: TimeInterval = 2

    private enum RolloutReadError: Error {
        case unsafeFile
    }

    private struct TurnContextRecord: Decodable {
        let timestamp: Date
        let approvalsReviewer: String?

        private enum CodingKeys: String, CodingKey {
            case timestamp
            case type
            case payload
        }

        private struct Payload: Decodable {
            let approvalsReviewer: String?

            private enum CodingKeys: String, CodingKey {
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
            approvalsReviewer = try container.decodeIfPresent(
                Payload.self,
                forKey: .payload
            )?.approvalsReviewer
        }
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func approvalsReachTheUser(
        forTurnStartedAt turnStartedAt: Date,
        inRolloutAt rolloutPath: String
    ) async -> Bool? {
        guard let record = newestTurnContext(inRolloutAt: rolloutPath) else {
            return nil
        }
        // A record from the Turn before this one describes a reviewer that has
        // already been superseded, which is the whole failure being fixed here.
        // Better to say nothing and let the map answer than to pin it.
        guard record.timestamp
            >= turnStartedAt.addingTimeInterval(-Self.recordTolerance) else {
            return nil
        }
        guard let reviewer = record.approvalsReviewer else { return nil }
        return reviewer != Self.automaticReviewer
    }

    private func newestTurnContext(
        inRolloutAt rolloutPath: String
    ) -> TurnContextRecord? {
        guard let tail = try? readValidatedTail(ofFileAt: rolloutPath) else {
            return nil
        }
        let decoder = JSONDecoder()
        // Backwards: the newest record wins, and stopping at the first match is
        // what keeps the rest of the tail from being decoded at all.
        for line in tail.split(separator: UInt8(ascii: "\n")).reversed() {
            // The decode is the test of what a line is. This only keeps the
            // other ninety-nine in a hundred from reaching it, and a rollout
            // line can be tens of kilobytes of assistant text.
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

    /// The last ``maximumTailByteCount`` bytes of the file, minus a partial
    /// first line.
    ///
    /// Validated the way the sibling adapter validates its state file, and for
    /// the same reason: the path is handed over by the App Server, so it is
    /// only ever read when it is a regular file this user owns.
    private func readValidatedTail(ofFileAt path: String) throws -> Data {
        let url = URL(fileURLWithPath: path)
        let resourceValues = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ])
        guard resourceValues.isRegularFile == true,
              resourceValues.isSymbolicLink != true else {
            throw RolloutReadError.unsafeFile
        }
        let attributes = try fileManager.attributesOfItem(atPath: path)
        if let owner = attributes[.ownerAccountID] as? NSNumber,
           owner.uint32Value != getuid() {
            throw RolloutReadError.unsafeFile
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = resourceValues.fileSize ?? 0
        let startsAtHead = size <= Self.maximumTailByteCount
        if !startsAtHead {
            try handle.seek(toOffset: UInt64(size - Self.maximumTailByteCount))
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

/// The one timestamp format every rollout record is stamped with.
///
/// `2026-08-26T04:44:51.593Z`: internet date time, fractional seconds, always
/// UTC. Held here rather than built per read because `ISO8601DateFormatter` is
/// expensive to create and this one is immutable once configured.
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
/// **Why this is read at all.** `PermissionRequest` fires when the permission
/// pipeline runs, not when a person is asked — measured 2026-08-22 against CLI
/// `0.149.0-alpha.4.1`, in a non-interactive `codex exec --approve-for-me` run
/// where nobody could be asked: `PreToolUse(exec-…)`, `PermissionRequest`
/// 10 ms later, and the paired `PostToolUse` 2.5 s after that, once the
/// reviewer had answered and the command had run. The reducer's borrowed wait
/// spans exactly that gap, so on this setting a row announced *Approval
/// needed* for every reviewed call and cleared itself again with nothing for
/// the user to do. The official `permission-request.command.input` schema
/// carries no field that separates the two cases — `permission_mode` is
/// `default` in both — so the separation has to come from the thread.
///
/// **Not the rollout, and not the host-level setting.** The value is also in
/// each rollout's `turn_context.approvals_reviewer`, which is the authority the
/// running turn actually used; reading it means tail-scanning a JSONL whose
/// last `turn_context` sits arbitrarily far from the end once the turn has
/// produced items. The same file also holds a host-level
/// `permission-selection-by-host-id:local`, but that describes what the *next*
/// thread will be started with, not what this one is running under. The
/// per-thread map is the fact this adapter can read cheaply, and measured
/// 2026-08-22 it covered every `user` thread of the last forty; the only ones
/// missing were `subagent` threads, which never become rows.
///
/// **It is a fact about the thread now, and not about the Turn on the row.**
/// An earlier version of this comment claimed the map *was* the fact about the
/// row, and that was wrong: Desktop rewrites the entry the moment the reviewer
/// is changed, while the turn already in flight keeps the reviewer it started
/// with and goes on asking the person. Measured 2026-08-24, and the reason
/// ``TurnApprovalRoutingPin`` sits between this snapshot and the row — the
/// timings are recorded there. Nothing about this adapter changed for it; a
/// snapshot is still what Desktop last recorded, and it is the caller's job to
/// hold the answer still for the Turn it applies to.
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

        /// Only the reviewer is decoded. The sibling `approvalPolicy` is
        /// sometimes a string and sometimes an object with a `granular` table,
        /// and reading it would make this adapter fail on a shape it has no
        /// question about.
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
    /// The last map that decoded.
    ///
    /// Kept for the same reason the sibling adapters keep theirs, and with a
    /// smaller consequence: Desktop rewrites this file atomically and often,
    /// so a read that lands mid-replacement is ordinary. Dropping to "nothing
    /// is automatic" for that one refresh would put *Approval needed* back on
    /// the row for a beat — the exact flicker this adapter exists to end —
    /// while a mode the user changed in the meantime is corrected by the next
    /// successful read, which the Desktop's own write triggers.
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

    /// No change stream of its own: this fact shares a file with the unread
    /// state, whose watcher already wakes a refresh on every write to it.
    func snapshot() async -> DesktopApprovalRoutingSnapshot {
        let currentRevision = try? revision(of: stateFileURL)
        if currentRevision != nil,
           currentRevision == lastSuccessfulRevision,
           let lastKnownGood {
            return lastKnownGood
        }

        do {
            let data = try readValidatedData(from: stateFileURL)
            let state = try JSONDecoder().decode(GlobalState.self, from: data)
            let snapshot = DesktopApprovalRoutingSnapshot(
                automaticallyReviewedThreadIDs: Set(
                    state.reviewersByThreadID
                        .filter { $0.value == Self.automaticReviewer }
                        .keys
                )
            )
            lastKnownGood = snapshot
            lastSuccessfulRevision = currentRevision
            return snapshot
        } catch {
            // Nothing is reported to the user here, and that is deliberate:
            // the failure lands on the answer that keeps every state the row
            // could already show, so there is nothing for them to act on.
            return lastKnownGood ?? .unknown
        }
    }

    private func readValidatedData(from url: URL) throws -> Data {
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
        return data
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
