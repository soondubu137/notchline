import Darwin
import Dispatch
import Foundation

nonisolated protocol DesktopUnreadStateProviding: Sendable {
    func snapshot() async -> DesktopUnreadStateSnapshot
    nonisolated func changeEvents() -> AsyncStream<Void>
}

struct DesktopUnreadStateSnapshot: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case current
        case backup
        case lastKnownGood
        case unavailable

        nonisolated var isAuthoritative: Bool {
            if case .current = self {
                return true
            }
            return false
        }
    }

    let unreadThreadIDs: Set<String>
    let source: Source
    let diagnostic: String?

    nonisolated init(
        unreadThreadIDs: Set<String>,
        source: Source,
        diagnostic: String? = nil
    ) {
        self.unreadThreadIDs = unreadThreadIDs
        self.source = source
        self.diagnostic = diagnostic
    }

    nonisolated static func unavailable(_ diagnostic: String) -> Self {
        Self(
            unreadThreadIDs: [],
            source: .unavailable,
            diagnostic: diagnostic
        )
    }

    nonisolated func retainingData(
        source: Source,
        diagnostic: String
    ) -> Self {
        Self(
            unreadThreadIDs: unreadThreadIDs,
            source: source,
            diagnostic: diagnostic
        )
    }
}

struct TerminalUnreadMembershipGate: Sendable {
    private struct Entry: Sendable {
        var terminalObservedAt: Date
        var hasObservedUnread: Bool
        var isHidden: Bool
        /// Whether the last evaluation could act on unread evidence at all.
        ///
        /// Only an authoritative reading can hide a row, so only then does the
        /// settling window describe something the passage of time will change.
        var canSettle: Bool
    }

    private let settlingInterval: TimeInterval
    private var entries: [String: Entry] = [:]

    nonisolated init(settlingInterval: TimeInterval = 2) {
        self.settlingInterval = settlingInterval
    }

    nonisolated mutating func shouldDisplay(
        sessionID: String,
        threadID: String,
        status: SessionStatus,
        terminalBoundaryAt: Date,
        unreadState: DesktopUnreadStateSnapshot,
        now: Date
    ) -> Bool {
        guard Self.isTerminal(status) else {
            entries.removeValue(forKey: sessionID)
            return true
        }

        var entry = entries[sessionID] ?? Entry(
            terminalObservedAt: terminalBoundaryAt,
            hasObservedUnread: false,
            isHidden: false,
            canSettle: false
        )
        entry.terminalObservedAt = max(
            entry.terminalObservedAt,
            terminalBoundaryAt
        )
        entry.canSettle = unreadState.source.isAuthoritative

        guard unreadState.source.isAuthoritative else {
            entries[sessionID] = entry
            return !entry.isHidden
        }

        if unreadState.unreadThreadIDs.contains(threadID) {
            entry.hasObservedUnread = true
            entry.isHidden = false
        } else if entry.hasObservedUnread
                    || now.timeIntervalSince(entry.terminalObservedAt)
                        >= settlingInterval {
            entry.isHidden = true
        }

        entries[sessionID] = entry
        return !entry.isHidden
    }

    /// When a still-visible terminal row would next become hideable.
    ///
    /// Without this the settling window could only expire on some unrelated
    /// refresh happening to land after it, which is what the one-second poll
    /// was really paying for.
    ///
    /// Rows that cannot settle are excluded. While the unread state is
    /// unreadable no amount of waiting hides anything, so reporting their window
    /// would ask the store to wake for work that will not happen -- and once
    /// that window is past, to keep waking forever.
    nonisolated var nextSettlingDeadline: Date? {
        entries.values
            .filter { !$0.isHidden && $0.canSettle }
            .map { $0.terminalObservedAt.addingTimeInterval(settlingInterval) }
            .min()
    }

    nonisolated mutating func retain(sessionIDs: Set<String>) {
        entries = entries.filter { sessionIDs.contains($0.key) }
    }

    nonisolated mutating func reset() {
        entries.removeAll()
    }

    nonisolated private static func isTerminal(_ status: SessionStatus) -> Bool {
        status == .completed
    }
}

actor CodexDesktopUnreadStateRepository: DesktopUnreadStateProviding {
    nonisolated private static let stateFileName = ".codex-global-state.json"
    nonisolated private static let maximumStateFileSize = 4 * 1_024 * 1_024

    private struct FileRevision: Equatable {
        let size: UInt64
        let modificationDate: Date?
        let fileNumber: UInt64?
    }

    private struct GlobalState: Decodable {
        let unreadThreadIDsByHost: [String: [String]]

        private enum CodingKeys: String, CodingKey {
            case persistedAtomState = "electron-persisted-atom-state"
        }

        private struct PersistedAtomState: Decodable {
            let unreadThreadIDsByHost: [String: [String]]

            private enum CodingKeys: String, CodingKey {
                case unreadThreadIDsByHost = "unread-thread-ids-by-host-v1"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                guard container.contains(.unreadThreadIDsByHost) else {
                    throw UnreadStateError.incompatibleSchema
                }
                unreadThreadIDsByHost = try container.decode(
                    [String: [String]].self,
                    forKey: .unreadThreadIDsByHost
                )
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.persistedAtomState) else {
                throw UnreadStateError.incompatibleSchema
            }
            unreadThreadIDsByHost = try container.decode(
                PersistedAtomState.self,
                forKey: .persistedAtomState
            ).unreadThreadIDsByHost
        }
    }

    private enum UnreadStateError: LocalizedError {
        case incompatibleSchema
        case oversizedFile(Int)
        case unsafeFile
        case invalidHostIdentifier
        case invalidThreadIdentifier
        case duplicateThreadIdentifier

        var errorDescription: String? {
            switch self {
            case .incompatibleSchema:
                "Desktop 未读状态 schema 不兼容。"
            case let .oversizedFile(size):
                "Desktop 未读状态文件异常过大（\(size) bytes）。"
            case .unsafeFile:
                "Desktop 未读状态文件不是当前用户拥有的普通文件。"
            case .invalidHostIdentifier:
                "Desktop 未读状态包含空 host 标识。"
            case .invalidThreadIdentifier:
                "Desktop 未读状态包含空 thread 标识。"
            case .duplicateThreadIdentifier:
                "Desktop 未读状态包含重复 thread 标识。"
            }
        }
    }

    private let stateFileURL: URL
    private let fileManager: FileManager
    nonisolated private let directoryWatcher: DirectoryChangeWatcher
    private var lastKnownGood: DesktopUnreadStateSnapshot?
    private var lastSuccessfulPrimaryRevision: FileRevision?

    nonisolated static func liveStateFileURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        let configuredHome = environment["CODEX_IN_NOTCH_CODEX_HOME"]
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
        stateFileURL: URL = CodexDesktopUnreadStateRepository.liveStateFileURL(),
        fileManager: FileManager = .default,
        changeDebounceInterval: TimeInterval = 0.25
    ) {
        self.stateFileURL = stateFileURL
        self.fileManager = fileManager
        self.directoryWatcher = DirectoryChangeWatcher(
            directoryURL: stateFileURL.deletingLastPathComponent(),
            debounceInterval: changeDebounceInterval
        )
    }

    nonisolated func changeEvents() -> AsyncStream<Void> {
        directoryWatcher.events()
    }

    func snapshot() async -> DesktopUnreadStateSnapshot {
        // Same reason as the Hook event queue: the watcher may have failed to
        // attach at launch, or Codex may have replaced this directory since.
        // Retrying on a read that was happening anyway restores the 250 ms
        // unread path without a wake-up of its own (CR-018).
        directoryWatcher.attachIfNeeded()

        let primaryRevision = try? revision(of: stateFileURL)
        if primaryRevision != nil,
           primaryRevision == lastSuccessfulPrimaryRevision,
           let lastKnownGood,
           lastKnownGood.source.isAuthoritative {
            return lastKnownGood
        }

        do {
            let snapshot = try loadSnapshot(from: stateFileURL, source: .current)
            lastKnownGood = snapshot
            lastSuccessfulPrimaryRevision = primaryRevision
            return snapshot
        } catch {
            let primaryError = error
            do {
                let backupURL = URL(fileURLWithPath: stateFileURL.path + ".bak")
                let backup = try loadSnapshot(from: backupURL, source: .backup)
                    .retainingData(
                        source: .backup,
                        diagnostic: "Desktop 未读主状态不可读，已使用备份但不会据此隐藏会话：\(primaryError.localizedDescription)"
                    )
                lastKnownGood = backup
                lastSuccessfulPrimaryRevision = nil
                return backup
            } catch {
                let diagnostic = "无法读取 Codex Desktop 未读状态：\(primaryError.localizedDescription)"
                if let lastKnownGood {
                    return lastKnownGood.retainingData(
                        source: .lastKnownGood,
                        diagnostic: diagnostic + " 已保留最近一次有效数据，且不会据此隐藏新会话。"
                    )
                }
                return .unavailable(diagnostic + " 已保守保留终态会话。")
            }
        }
    }

    private func loadSnapshot(
        from url: URL,
        source: DesktopUnreadStateSnapshot.Source
    ) throws -> DesktopUnreadStateSnapshot {
        let data = try readValidatedData(from: url)
        let state = try JSONDecoder().decode(GlobalState.self, from: data)

        for (hostID, threadIDs) in state.unreadThreadIDsByHost {
            guard !hostID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw UnreadStateError.invalidHostIdentifier
            }
            guard threadIDs.allSatisfy({
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) else {
                throw UnreadStateError.invalidThreadIdentifier
            }
            guard Set(threadIDs).count == threadIDs.count else {
                throw UnreadStateError.duplicateThreadIdentifier
            }
        }

        return DesktopUnreadStateSnapshot(
            unreadThreadIDs: Set(state.unreadThreadIDsByHost["local"] ?? []),
            source: source
        )
    }

    private func readValidatedData(from url: URL) throws -> Data {
        let resourceValues = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ])
        guard resourceValues.isRegularFile == true,
              resourceValues.isSymbolicLink != true else {
            throw UnreadStateError.unsafeFile
        }
        let fileSize = resourceValues.fileSize ?? 0
        guard fileSize <= Self.maximumStateFileSize else {
            throw UnreadStateError.oversizedFile(fileSize)
        }

        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        if let owner = attributes[.ownerAccountID] as? NSNumber,
           owner.uint32Value != getuid() {
            throw UnreadStateError.unsafeFile
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Self.maximumStateFileSize else {
            throw UnreadStateError.oversizedFile(data.count)
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
