import Foundation

/// Which Claude Code sessions exist, read once per refresh after the drain: presence, admission
/// (``ProductSessionReading``), and the list other Claude Code sources read.
///
/// Other sources read this, not the registry: a second read could launch `claude` mid-refresh
/// and describe a different instant. Owns the two edges that invalidate the registry: the
/// sessions directory and the listed sessions' records.
actor ClaudeCodeSessionSource: ProductSessionReading, ManagedMonitoringSource, SessionProcessLocating {
    nonisolated struct Reading: Sendable {
        let presence: AgentPresence
        let sessions: [ClaudeCodeSession]
        let sessionsByID: [String: ClaudeCodeSession]
        let readStartedAt: Date

        static let none = Reading(
            presence: .unknown,
            sessions: [],
            sessionsByID: [:],
            readStartedAt: .distantPast
        )
    }

    private let listing: any ClaudeCodeSessionListing
    /// Whether a `claude` exists to run; asked only when the registry has stopped answering.
    nonisolated private let commandIsInstalled: @Sendable () -> Bool
    /// Held: ``AsyncStream`` does not retain its watcher, and a released watcher ends its streams.
    nonisolated private let sessionsWatcher: DirectoryChangeWatcher
    /// Records of sessions whose turn is still going; an interrupt changes no directory entry.
    /// Not private so a test can count them: each rewrite costs a `claude` launch, so watching only
    /// while the turn runs is an invariant.
    nonisolated let recordWatcher: ClaudeCodeSessionRecordWatcher
    /// Used only to spot attaching, an edge the watcher cannot deliver (see ``read(observing:)``).
    private var wasWatchingSessionsDirectory: Bool
    private var latest = Reading.none
    private var observationGeneration = 0
    /// Made once: a stream is consumed by whoever merges it.
    nonisolated let changeEvents: [AsyncStream<Void>]

    init(
        listing: any ClaudeCodeSessionListing,
        sessionsDirectory: URL? = nil,
        /// Which entries belong to a `claude` this app launched; see
        /// ``sessionsChanged(_:invalidating:in:ownedBy:)``.
        ownsSessionRecord: (@Sendable (String) -> Bool)? = nil,
        commandIsInstalled: (@Sendable () -> Bool)? = nil,
        timing: MonitorTiming = .standard
    ) {
        self.listing = listing
        self.commandIsInstalled = commandIsInstalled
            ?? { ClaudeExecutableLocator.locate() != nil }
        // Two edges, no cadence. The sessions directory is the only way a dead session's row retires,
        // since SessionEnd is not registered.
        let watched = sessionsDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/sessions", isDirectory: true)
        let sessionsWatcher = DirectoryChangeWatcher(
            directoryURL: watched,
            debounceInterval: timing.unreadStateDebounceInterval
        )
        self.sessionsWatcher = sessionsWatcher
        // Seeded from init's attach, so an ordinary launch reports no edge.
        self.wasWatchingSessionsDirectory = sessionsWatcher.isAttached
        let recordWatcher = ClaudeCodeSessionRecordWatcher(
            directory: watched,
            debounceInterval: timing.unreadStateDebounceInterval
        )
        self.recordWatcher = recordWatcher
        self.changeEvents = [
            Self.sessionsChanged(
                sessionsWatcher.events(),
                invalidating: listing,
                in: watched,
                ownedBy: ownsSessionRecord ?? ClaudeCommand.ownsSessionRecord(named:)
            ),
            // Directory edges: the list is wrong; record rewrites: it is out of date. Both invalidate.
            Self.sessionsChanged(
                recordWatcher.events(),
                invalidating: listing
            ),
        ]
    }

    /// The list, read once for this refresh.
    ///
    /// - Parameter state: Turns after this refresh's drain; an unlisted Turn that moved since the
    ///   list was read triggers an immediate re-read.
    func read(observing state: HookStateSnapshot) async -> SessionReading {
        let generation = observationGeneration
        // `~/.claude/sessions` does not exist until Claude Code first runs, so attach is retried here.
        // Attaching is itself an edge (CR-Fable-002): the first session creates the directory and would
        // go unlisted until its first hook, and the watcher yields nothing on attach.
        let watchingSessionsDirectory = sessionsWatcher.attachIfNeeded()
        if watchingSessionsDirectory, !wasWatchingSessionsDirectory {
            await listing.invalidate()
        }
        wasWatchingSessionsDirectory = watchingSessionsDirectory

        // Presence first, and once, so it and the list come from the same reading.
        func readSessions() async -> (
            presence: AgentPresence,
            live: [ClaudeCodeSession],
            byID: [String: ClaudeCodeSession]
        ) {
            let presence = await listing.presence()
            let live = await listing.liveSessions()
            return (
                presence,
                live,
                Dictionary(
                    live.map { ($0.sessionID, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            )
        }
        var (presence, live, liveByID) = await readSessions()

        // A hook event newer than the reading proves its session exists and outranks the list.
        // `/clear` and in-session `/resume` rotate the session id in place (same pid, record and inode;
        // measured 2026-08-21), so no directory edge fires. An unlisted Turn that moved since the read
        // triggers an immediate re-read; Turns that have not moved never ask, and ``edgeFloor`` caps
        // re-reads at one every two seconds.
        var readStartedAt = await listing.listReadStartedAt()
        let heardFromAnUnlistedSession = state.turns.contains { turn in
            liveByID[turn.threadID] == nil && turn.lastEventAt > readStartedAt
        }
        if heardFromAnUnlistedSession {
            await listing.invalidate()
            (presence, live, liveByID) = await readSessions()
            // Re-asked so this stays the reading `liveByID` came from; the pruning below relies on it.
            readStartedAt = await listing.listReadStartedAt()
        }

        guard generation == observationGeneration else {
            return SessionReading(presence: .unknown, admission: .unknown)
        }
        latest = Reading(
            presence: presence,
            sessions: live,
            sessionsByID: liveByID,
            readStartedAt: readStartedAt
        )

        // Watch every listed session's record, not only those with a Turn in flight: `/clear` rotates
        // an idle session's id, and its record is the only edge that reports it (otherwise up to 30 s
        // with no row). Cheap: no record rewritten in 90 s across six live sessions (2026-08-21);
        // writes come on `busy`/`waiting`/`idle` flips, capped by ``edgeFloor``.
        recordWatcher.watch(processIdentifiers: Set(live.map(\.processIdentifier)))

        // Prune held Turns to what this reading says exists (CR-Fable-008): `HookEventRepository`
        // sorts every held turn per event (~2.2 µs each; 5.3 ms at 2000, Release), and `/clear` mints a
        // dead entry each time. Only when the list is knowledge: `unknown` is a missing reading, not an
        // ended session (`AGENTS.md` §6.2), so it withholds rows without forgetting; `closed` prunes.
        let admission: ThreadAdmission = presence == .unknown
            ? .unknown
            : .exactly(Set(liveByID.keys), readAt: readStartedAt)

        // The card may not say Connected while the mark is absent: `unknown` means no reading
        // (`AGENTS.md` §6.7). `closed` is `claude` answering that nothing is open, which is healthy.
        return SessionReading(
            presence: presence,
            admission: admission,
            unwatchableReason: presence == .unknown ? unwatchableReason() : nil
        )
    }

    /// Stops watching so a switched-off integration keeps no descriptor open on a record.
    nonisolated var sourceChanges: [AsyncStream<Void>] { changeEvents }
    func stopMonitoring() async {
        observationGeneration += 1
        stopWatching(); sessionsWatcher.pause()
        await (listing as? any ManagedMonitoringSource)?.stopMonitoring()
    }
    func startMonitoring() async {
        await (listing as? any ManagedMonitoringSource)?.startMonitoring()
        sessionsWatcher.resume()
    }

    func stopWatching() {
        recordWatcher.watch(processIdentifiers: [])
    }

    func currentReading() -> Reading {
        latest
    }

    /// The process each session ran as in the current reading, for a source that must ask the list
    /// that proved its rows exist.
    nonisolated var listedProcesses: ListedProcesses {
        ListedProcesses(source: self)
    }

    nonisolated struct ListedProcesses: SessionProcessLocating {
        let source: ClaudeCodeSessionSource

        func processIdentifier(forThreadID threadID: String) async -> Int32? {
            await source.currentReading().sessionsByID[threadID]?.processIdentifier
        }
    }

    /// The process running a session, for navigation. Asked of the live list at click time, so an
    /// ended session fails the click (the PRD's re-confirmation) rather than using a recorded pid.
    func processIdentifier(forThreadID threadID: String) async -> Int32? {
        await listing.liveSessions()
            .first { $0.sessionID == threadID }?
            .processIdentifier
    }

    /// The sessions-directory edge, with the session list invalidated before the yield wakes anyone,
    /// so the refresh this edge causes re-reads. It yields even when the list declines to re-read.
    ///
    /// - Parameter directory: The sessions directory, when this is its edge. Skips ``invalidate()``
    ///   only when every name that moved is a record of a `claude` this app launched (the quota
    ///   reading, which otherwise bought a `claude agents --json` per reading); see
    ///   ``ClaudeCommand/ownsSessionRecord(named:)``. Unlistable or unclaimable changes invalidate.
    ///   Nil for the record-file edge, which never watches this app's own sessions.
    nonisolated private static func sessionsChanged(
        _ events: AsyncStream<Void>,
        invalidating sessions: any ClaudeCodeSessionListing,
        in directory: URL? = nil,
        ownedBy isOwnRecord: @escaping @Sendable (String) -> Bool =
            ClaudeCommand.ownsSessionRecord(named:)
    ) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let forwarder = Task {
                var known = directory.map(Self.entryNames(of:)) ?? []
                for await _ in events {
                    var isOursAlone = false
                    if let directory {
                        let current = Self.entryNames(of: directory)
                        let moved = current.symmetricDifference(known)
                        known = current
                        isOursAlone = !moved.isEmpty && moved.allSatisfy(isOwnRecord)
                    }
                    if !isOursAlone {
                        await sessions.invalidate()
                    }
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in forwarder.cancel() }
        }
    }

    /// The names in a directory. Record contents are a private schema this app does not read; names
    /// only answer whether what moved belongs to a process this app started.
    nonisolated private static func entryNames(of directory: URL) -> Set<String> {
        let names = try? FileManager.default.contentsOfDirectory(
            atPath: directory.path
        )
        return Set(names ?? [])
    }

    /// Why this app has no reading of Claude Code's sessions, in words a user can act on.
    ///
    /// Asked only where presence is already `unknown`, without re-reading it. Two failures reach it:
    /// no `claude` at all (neither CLI nor Desktop's copy), or a `claude` that will not answer (e.g.
    /// wedged behind an MCP server), which must not be told to install. A sentence, not a state.
    private func unwatchableReason() -> String? {
        if commandIsInstalled() {
            return "Claude Code is registered, but `claude agents --json` is "
                + "not answering, so this app cannot see which sessions are "
                + "open. It is the command Claude Code itself provides; try "
                + "running it in a terminal to see what it says."
        }
        return "Claude Code is registered, but no `claude` command could be "
            + "found to ask which sessions are open — not in ~/.local/bin, "
            + "Homebrew, /usr/local/bin, this app's PATH, or Claude Desktop's "
            + "own copy. Install Claude Code, or set NOTCHLINE_CLAUDE_PATH to "
            + "where it lives."
    }
}
