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
        /// Whether waiting -- and nothing else -- could still hide this row.
        ///
        /// Two things make waiting pointless. An unreadable state cannot hide
        /// anything however long it is given. And a row Desktop still reports
        /// as *unread* is not waiting on a window at all: only the user reading
        /// it changes that, which arrives as a file change on the watcher, not
        /// as time passing.
        ///
        /// This decides *which* deadline the row reports, not whether it
        /// reports one -- see ``nextDeadline(now:screenIsAvailable:)``.
        var canHideByWaiting: Bool
        /// Whether the *user* is the only thing that can hide this row.
        ///
        /// The complement of `canHideByWaiting` splits in two, and the halves
        /// wait on different things. A row Desktop reports unread waits on
        /// somebody reading it, which needs a screen they can see. A row whose
        /// unread state could not be read waits on that file becoming legible,
        /// which happens whatever the screen is doing.
        ///
        /// Only the first may be deferred for an unusable screen -- see
        /// ``nextDeadline(now:screenIsAvailable:)``.
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
            canHideByWaiting: false,
            waitsOnTheUser: false
        )
        // Whether a *newer* Turn has ended than the one this entry describes,
        // which is the only thing allowed to bring a hidden row back -- see
        // below. Read before the boundary is folded in, because folding it in
        // is what makes the two equal.
        //
        // A new Turn normally passes through a running status, and the guard
        // above drops the entry outright when it does. This covers the case
        // where no refresh saw it: a Turn that started and ended between two
        // looks is still a Turn the user has not read.
        let endedAgain = terminalBoundaryAt > entry.terminalObservedAt
        entry.terminalObservedAt = max(
            entry.terminalObservedAt,
            terminalBoundaryAt
        )
        if endedAgain {
            entry.isHidden = false
            entry.hasObservedUnread = false
        }
        let isCurrentlyUnread = unreadState.unreadThreadIDs.contains(threadID)
        entry.canHideByWaiting = unreadState.source.isAuthoritative
            && !isCurrentlyUnread
        entry.waitsOnTheUser = unreadState.source.isAuthoritative
            && isCurrentlyUnread

        guard unreadState.source.isAuthoritative else {
            entries[sessionID] = entry
            return !entry.isHidden
        }

        // Hiding is final for the Turn it was decided for. It used to be
        // provisional -- a row reported unread again came back -- and that made
        // the row a live readout of whatever the sources happened to say rather
        // than a record of a decision. Every source behind that decision is
        // assembled from files written by another application at times it
        // chooses, so a moment where they disagree is ordinary rather than
        // exceptional, and each one flashed a retired row back onto the notch
        // (CC-024). Nothing is lost by refusing: within one finished Turn there
        // is no way to become unread again, and a row that starts running has
        // dropped its entry above before it can ask.
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

    /// When a still-visible terminal row should next be looked at again.
    ///
    /// Every listed terminal row reports something, because every one of them
    /// is waiting -- but not on the same thing, and the deadline has to say
    /// which:
    ///
    /// - Inside its settling window a row waits on *time*. Report the instant
    ///   the window expires; a refresh then genuinely clears it.
    /// - A row Desktop still reports as unread waits on the *user*, and one
    ///   whose unread state is unreadable waits on the file becoming legible.
    ///   Both arrive on the watcher, and the watcher is a low-latency hint,
    ///   never a source of truth. Report a re-check measured forward from now.
    ///
    /// Excluding that second group entirely is what regressed this. Waiting
    /// cannot hide those rows, which is true and was the wrong conclusion: the
    /// store then had no scheduled wake-up at all for the product's core
    /// interaction, so a watcher edge that arrived late -- or never -- left the
    /// row listed until some unrelated refresh happened along. Traced on the
    /// live app: eight seconds of complete silence between a finished Turn
    /// being listed and the user reading it, the disappearance resting entirely
    /// on one edge landing.
    ///
    /// The mistake worth not repeating is reporting a *stale* deadline rather
    /// than none. `terminalObservedAt + settlingInterval` for an unread row
    /// sits permanently in the past, the store clamps it to its one-second
    /// floor, and no refresh can move it -- a busy loop wearing a deadline's
    /// clothes. A re-check measured from `now` is clearable by construction:
    /// the refresh at that instant either hides the row or books the next look.
    ///
    /// - Parameter screenIsAvailable: Whether the display is awake and the
    ///   login session unlocked and on the console. A row waiting on the *user*
    ///   books nothing while that is false, because every route that could
    ///   retire it requires the same thing: Claude Code's `isInFrontOfThem` and
    ///   its terminal-gesture route both fail
    ///   ``DesktopReadingWatcher/systemScreenIsAvailable()`` outright, and a
    ///   Codex thread is marked read by somebody opening it in Desktop. The
    ///   defence of the one-second sample above is a good one, and it is made
    ///   for a screen somebody might be looking at; through a locked screen the
    ///   answer is knowably "no" before the work is done, so the sample is not
    ///   a sample of anything. Left ungated this ran all night -- a wake-up a
    ///   second, on battery, for a row nobody could see (CR-Fable-018).
    ///
    ///   The row is not abandoned: it waits on
    ///   ``ScreenAvailabilityReporting/changeEvents()`` instead, which fires
    ///   when the screen comes back, ahead of anything the user could then do.
    ///
    ///   Defaults to `true` so a test of the deadline logic states only what it
    ///   is about. Both callers in the product pass the live reading.
    ///
    ///   A row waiting on an unreadable *file* is unaffected: that becomes
    ///   legible whether or not anybody is at the machine.
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
                "The Desktop unread state schema is not compatible."
            case let .oversizedFile(size):
                "The Desktop unread state file is implausibly large (\(size) bytes)."
            case .unsafeFile:
                "The Desktop unread state file is not a regular file owned by the current user."
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
