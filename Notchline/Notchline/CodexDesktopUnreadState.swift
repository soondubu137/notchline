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
    /// The instant this reading is a complete account up to.
    ///
    /// A thread's absence from the set means "read" only if the reading reaches past the Turn
    /// (``TerminalUnreadMembershipGate``). Codex Desktop writes `.codex-global-state.json` through
    /// a trailing 500 ms debounce with no maximum wait, shared by every persisted atom including
    /// the per-keystroke composer draft: 165 typed characters produced one write, 45.4 s after the
    /// previous (Desktop `26.820.60940`, 2026-08-26). A snapshot built in memory answers `now`.
    let currentAsOf: Date
    let diagnostic: String?

    nonisolated init(
        unreadThreadIDs: Set<String>,
        source: Source,
        currentAsOf: Date,
        diagnostic: String? = nil
    ) {
        self.unreadThreadIDs = unreadThreadIDs
        self.source = source
        self.currentAsOf = currentAsOf
        self.diagnostic = diagnostic
    }

    /// A reading with no data that reaches no further than the beginning of time, so it judges
    /// no Turn.
    nonisolated static func unavailable(_ diagnostic: String) -> Self {
        Self(
            unreadThreadIDs: [],
            source: .unavailable,
            currentAsOf: .distantPast,
            diagnostic: diagnostic
        )
    }

    /// Keeps the data and its `currentAsOf`: demotion to a non-hiding source does not move it forward.
    nonisolated func retainingData(
        source: Source,
        diagnostic: String
    ) -> Self {
        Self(
            unreadThreadIDs: unreadThreadIDs,
            source: source,
            currentAsOf: currentAsOf,
            diagnostic: diagnostic
        )
    }
}

struct TerminalUnreadMembershipGate: Sendable {
    private struct Entry: Sendable {
        /// When this Turn's own terminal arrived; unread readings are dated against this, not
        /// ``terminalObservedAt``, which a subagent pushes forward.
        var turnEndedAt: Date
        /// When this thread stopped working, subagents included. Only the settling window uses it.
        var terminalObservedAt: Date
        var hasObservedUnread: Bool
        var isHidden: Bool
        /// Whether waiting, and nothing else, could still hide this row. False for an unreadable
        /// state, a reading taken before the Turn ended, or a row Desktop still reports unread.
        /// See ``nextDeadline(now:screenIsAvailable:)``.
        var canHideByWaiting: Bool
        /// Whether only the *user* can hide this row (Desktop reports it unread), which needs a
        /// visible screen; a row waiting on the file does not. See ``nextDeadline(now:screenIsAvailable:)``.
        var waitsOnTheUser: Bool
    }

    private let settlingInterval: TimeInterval
    private let unreadRecheckInterval: TimeInterval
    private var entries: [String: Entry] = [:]

    nonisolated init(
        settlingInterval: TimeInterval = 2,
        unreadRecheckInterval: TimeInterval = 1
    ) {
        self.settlingInterval = settlingInterval
        self.unreadRecheckInterval = unreadRecheckInterval
    }

    /// - Parameters:
    ///   - turnEndedAt: When this Turn's own terminal arrived; the unread reading is dated
    ///     against it.
    ///   - terminalBoundaryAt: When this *thread* stopped working, subagents included. Only the
    ///     settling window uses it: dating the reading against it (a `SubagentStop` 91 s after
    ///     `Stop`, 2026-08-22) discarded the write recording the user reading the thread.
    nonisolated mutating func shouldDisplay(
        sessionID: String,
        threadID: String,
        status: SessionStatus,
        turnEndedAt: Date,
        terminalBoundaryAt: Date,
        unreadState: DesktopUnreadStateSnapshot,
        now: Date
    ) -> Bool {
        guard Self.isTerminal(status) else {
            entries.removeValue(forKey: sessionID)
            return true
        }

        var entry = entries[sessionID] ?? Entry(
            turnEndedAt: turnEndedAt,
            terminalObservedAt: terminalBoundaryAt,
            hasObservedUnread: false,
            isHidden: false,
            canHideByWaiting: false,
            waitsOnTheUser: false
        )
        // Only a *newer* Turn ending may bring a hidden row back; read before folding in the stamp.
        // Covers a Turn that started and ended between two refreshes. Uses the Turn's own terminal,
        // not `terminalBoundaryAt`: a subagent stopping is not a Turn ending (cf.
        // ``HookEventRepository/reduceSubagentBoundary(_:agentID:threadID:at:)``).
        let endedAgain = turnEndedAt > entry.turnEndedAt
        entry.turnEndedAt = max(entry.turnEndedAt, turnEndedAt)
        entry.terminalObservedAt = max(
            entry.terminalObservedAt,
            terminalBoundaryAt
        )
        if endedAgain {
            entry.isHidden = false
            entry.hasObservedUnread = false
        }
        let isCurrentlyUnread = unreadState.unreadThreadIDs.contains(threadID)
        // Needs an authoritative source *and* a reading that reaches this Turn's end; an earlier
        // reading's silence is not evidence. Desktop's debounce kept a finished Turn out of the file
        // for 45.4 s while the user typed elsewhere, and the row was hidden for good (2026-08-26).
        // No settling interval bounds that. Same rule as ADR 0012 第一条.
        let canAnswer = unreadState.source.isAuthoritative
            && unreadState.currentAsOf >= entry.turnEndedAt
        entry.canHideByWaiting = canAnswer && !isCurrentlyUnread
        entry.waitsOnTheUser = canAnswer && isCurrentlyUnread

        guard canAnswer else {
            entries[sessionID] = entry
            return !entry.isHidden
        }

        // Hiding is final for this Turn: sources written by other apps disagree routinely, and a
        // provisional hide flashed retired rows back (CC-024). A running row drops its entry above.
        if isCurrentlyUnread {
            entry.hasObservedUnread = true
        } else if entry.hasObservedUnread
                    || now.timeIntervalSince(entry.terminalObservedAt)
                        >= settlingInterval {
            entry.isHidden = true
        }

        entries[sessionID] = entry
        return !entry.isHidden
    }

    /// When a still-visible terminal row should next be looked at again. Every such row reports:
    ///
    /// - Inside its settling window: the instant the window expires.
    /// - Unread, unreadable, or read before this Turn ended: a re-check measured from `now`. The
    ///   watcher is only a hint; without this a late edge left rows listed (8 s, traced live).
    ///   Never a stale `terminalObservedAt + settlingInterval`: clamped to the 1 s floor, that is
    ///   a busy loop.
    ///
    /// - Parameter screenIsAvailable: Whether the display is awake and the session unlocked and
    ///   on the console. A row waiting on the *user* books nothing while false, since every route
    ///   that retires it needs the screen; ungated it woke every second all night on battery
    ///   (CR-Fable-018). It waits on ``ScreenAvailabilityReporting/changeEvents()`` instead.
    ///   Rows waiting on the file are unaffected. Defaults to `true` for tests.
    nonisolated func nextDeadline(
        now: Date,
        screenIsAvailable: Bool = true
    ) -> Date? {
        entries.values
            .filter { !$0.isHidden }
            .compactMap { entry -> Date? in
                if entry.canHideByWaiting {
                    return entry.terminalObservedAt
                        .addingTimeInterval(settlingInterval)
                }
                guard screenIsAvailable || !entry.waitsOnTheUser else {
                    return nil
                }
                return now.addingTimeInterval(unreadRecheckInterval)
            }
            .min()
    }

    nonisolated mutating func retain(sessionIDs: Set<String>) {
        entries = entries.filter { sessionIDs.contains($0.key) }
    }

    nonisolated mutating func reset() {
        entries.removeAll()
    }

    /// Whether this gate has anything to say about a row in this status. Internal so a caller can
    /// skip assembling expensive read state when no such row is listed.
    nonisolated static func isTerminal(_ status: SessionStatus) -> Bool {
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

    /// The blue-dot set, out of whichever shape Codex Desktop keeps it in.
    ///
    /// Up to `26.820.60940`: `electron-persisted-atom-state.unread-thread-ids-by-host-v1`, keyed
    /// by host id. `26.903.61454` (measured 2026-09-09) moves it to a top-level
    /// `electron-thread-read-state-v1` and deletes the atom:
    ///
    /// ```
    /// electron-thread-read-state-v1: {
    ///   version: 1,
    ///   unreadByIdentity: { <identityKey>: { <executionHostKey>: [threadId] } },
    ///   legacyMigration?: { identityKey, unreadThreadIdsByHostId, adoptedHostIds, cleared? }
    /// }
    /// ```
    ///
    /// - Every identity is merged: `identityKey` is a SHA-256 over the account, a thread id
    ///   belongs to one identity, and a stale identity can only keep a row listed.
    /// - `legacyMigration` is ignored: written once at adoption and never revised.
    /// - The new key wins when both are present: the file is mid-migration.
    private struct GlobalState: Decodable {
        /// One host's unread array, flattened rather than merged so duplicate-id checks stay per array.
        struct HostMembership {
            let hostKey: String
            let threadIDs: [String]
        }

        let memberships: [HostMembership]

        private enum CodingKeys: String, CodingKey {
            case threadReadState = "electron-thread-read-state-v1"
            case persistedAtomState = "electron-persisted-atom-state"
        }

        private struct ThreadReadState: Decodable {
            let version: Int
            let unreadByIdentity: [String: [String: [String]]]
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

            if container.contains(.threadReadState) {
                let state = try container.decode(
                    ThreadReadState.self,
                    forKey: .threadReadState
                )
                // Desktop declares a literal `1`; an unknown version is a shape this cannot read.
                guard state.version == 1 else {
                    throw UnreadStateError.incompatibleSchema
                }
                memberships = try state.unreadByIdentity
                    .flatMap { identityKey, byHost -> [HostMembership] in
                        guard !identityKey.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty else {
                            throw UnreadStateError.invalidIdentityKey
                        }
                        return byHost.map {
                            HostMembership(hostKey: $0.key, threadIDs: $0.value)
                        }
                    }
                return
            }

            guard container.contains(.persistedAtomState) else {
                throw UnreadStateError.incompatibleSchema
            }
            memberships = try container.decode(
                PersistedAtomState.self,
                forKey: .persistedAtomState
            ).unreadThreadIDsByHost.map {
                HostMembership(hostKey: $0.key, threadIDs: $0.value)
            }
        }
    }

    /// Whether a host key names the local Codex: bare `local` (pre-migration schema) or the
    /// migrated execution-host form `local:…`.
    nonisolated private static func isLocalHost(_ hostKey: String) -> Bool {
        hostKey == "local" || hostKey.hasPrefix("local:")
    }

    private enum UnreadStateError: LocalizedError {
        case incompatibleSchema
        case oversizedFile(Int)
        case unsafeFile
        case invalidIdentityKey
        case invalidHostIdentifier
        case invalidThreadIdentifier
        case duplicateThreadIdentifier

        var errorDescription: String? {
            switch self {
            case .incompatibleSchema:
                "The Desktop unread state schema is not compatible."
            case let .oversizedFile(size):
                "The Desktop unread state file is implausibly large (\(size) bytes)."
            case .unsafeFile:
                "The Desktop unread state file is not a regular file owned by the current user."
            case .invalidIdentityKey:
                "The Desktop unread state contains an empty identity key."
            case .invalidHostIdentifier:
                "The Desktop unread state contains an empty host identifier."
            case .invalidThreadIdentifier:
                "The Desktop unread state contains an empty thread identifier."
            case .duplicateThreadIdentifier:
                "The Desktop unread state contains a duplicate thread identifier."
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
        stateFileURL: URL = CodexDesktopUnreadStateRepository.liveStateFileURL(),
        fileManager: FileManager = .default,
        changeDebounceInterval: TimeInterval =
            MonitorTiming.standard.unreadStateDebounceInterval
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
        // Re-attach if the watcher failed at launch or the directory was replaced; restores the
        // 250 ms unread path without a wake-up of its own (CR-018).
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
                        diagnostic: "The primary Desktop unread state is unreadable; the backup was used, but no session will be hidden on its say-so: \(primaryError.localizedDescription)"
                    )
                lastKnownGood = backup
                lastSuccessfulPrimaryRevision = nil
                return backup
            } catch {
                let diagnostic = "Could not read the Codex Desktop unread state: \(primaryError.localizedDescription)"
                if let lastKnownGood {
                    return lastKnownGood.retainingData(
                        source: .lastKnownGood,
                        diagnostic: diagnostic + " The last valid data has been kept, and no new session will be hidden on its say-so."
                    )
                }
                return .unavailable(diagnostic + " Finished sessions have been kept, to be safe.")
            }
        }
    }

    private func loadSnapshot(
        from url: URL,
        source: DesktopUnreadStateSnapshot.Source
    ) throws -> DesktopUnreadStateSnapshot {
        let (data, writtenAt) = try readValidatedData(from: url)
        let state = try JSONDecoder().decode(GlobalState.self, from: data)

        // Every host is checked, only the local one kept: a malformed array anywhere rejects the file.
        var localUnreadThreadIDs: Set<String> = []
        for membership in state.memberships {
            guard !membership.hostKey.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty else {
                throw UnreadStateError.invalidHostIdentifier
            }
            guard membership.threadIDs.allSatisfy({
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) else {
                throw UnreadStateError.invalidThreadIdentifier
            }
            guard Set(membership.threadIDs).count == membership.threadIDs.count else {
                throw UnreadStateError.duplicateThreadIdentifier
            }
            guard Self.isLocalHost(membership.hostKey) else { continue }
            localUnreadThreadIDs.formUnion(membership.threadIDs)
        }

        return DesktopUnreadStateSnapshot(
            unreadThreadIDs: localUnreadThreadIDs,
            source: source,
            // Desktop rewrites the file whole from one in-memory map, so its modification date is how
            // far the reading reaches. Unreadable fails closed.
            currentAsOf: writtenAt ?? .distantPast
        )
    }

    /// - Returns: the file's bytes, and the instant it was last written.
    ///
    /// The date is read before the bytes: under atomic replace that pairs an older date with newer
    /// content, keeping a row a moment longer; the reverse order retires rows.
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
