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
/// per-thread map is the fact about this row, and measured 2026-08-22 it
/// covered every `user` thread of the last forty; the only ones missing were
/// `subagent` threads, which never become rows.
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
