import Foundation

/// Which Claude Code sessions exist, read once per refresh: this product's
/// presence and admission (``ProductSessionReading``), and the list every
/// other Claude Code source answers about.
///
/// **Taken out of `ClaudeCodeMonitorService` on 2026-09-12.** The session list
/// is the one reading everything else about this product hangs off -- a row
/// exists because its session is listed, an interrupt is read off the listed
/// session's status, a terminal is found through the listed session's process
/// -- so it is read here, once, after the refresh has drained its events, and
/// held until the next refresh reads again. The other sources ask what this
/// reading said rather than asking the registry a second time: a second
/// reading could launch a `claude` in the middle of a refresh, and would
/// describe a different instant from the rows it is about.
///
/// It owns the two edges the list is kept honest by -- the sessions directory
/// and the records of the listed sessions -- because both do one thing: tell
/// the registry its answer is out of date before anybody is woken to ask it.
actor ClaudeCodeSessionSource: ProductSessionReading, SessionProcessLocating {
    /// One reading of the list, and what every Claude Code source reads off it.
    nonisolated struct Reading: Sendable {
        let presence: AgentPresence
        let sessions: [ClaudeCodeSession]
        let sessionsByID: [String: ClaudeCodeSession]
        /// When the reading behind ``sessions`` began.
        let readStartedAt: Date

        static let none = Reading(
            presence: .unknown,
            sessions: [],
            sessionsByID: [:],
            readStartedAt: .distantPast
        )
    }

    private let listing: any ClaudeCodeSessionListing
    /// Whether there is a `claude` on this machine for the registry to run.
    ///
    /// Asked only when the registry has stopped answering, so on a healthy
    /// machine it costs nothing: a list that came back is itself proof that
    /// an executable was found. Injected so the suite's own answer does not
    /// depend on whether Claude Code happens to be installed beside it.
    nonisolated private let commandIsInstalled: @Sendable () -> Bool
    /// Held, because a watcher nobody holds is a watcher that has already
    /// stopped.
    ///
    /// It used to be built inline and only its stream kept. ``AsyncStream``
    /// does not retain the object that vends it -- the subscription is a
    /// continuation stored *in* the watcher, and the termination handler holds
    /// the watcher weakly -- so the instance died at the end of the expression
    /// that created it, and its `deinit` finished every continuation and
    /// cancelled the dispatch source. The stream was therefore not merely
    /// silent: it was over before `init` returned. This is the only watcher in
    /// the app that was built that way; the Hook queue's and the Codex unread
    /// adapter's have always been stored properties.
    nonisolated private let sessionsWatcher: DirectoryChangeWatcher
    /// The records of the sessions whose turn is still going.
    ///
    /// Held for the same reason ``sessionsWatcher`` is, and answering what that
    /// one cannot: a session being interrupted neither creates nor removes a
    /// file, so the directory says nothing about it.
    ///
    /// Not private, so a test can read how many records are being watched.
    /// What it costs to watch one is a `claude` launch per rewrite, so "only
    /// while that turn is going" is a real invariant and not an implementation
    /// detail -- and asserting it through the change stream instead means
    /// asserting that an edge did *not* arrive, which any other source firing
    /// would make untrue.
    nonisolated let recordWatcher: ClaudeCodeSessionRecordWatcher
    /// Whether ``sessionsWatcher`` was attached at the end of the last refresh.
    ///
    /// Only ever used to spot it becoming attached, which is an edge the
    /// watcher has no way to deliver -- see ``read(observing:)``.
    private var wasWatchingSessionsDirectory: Bool
    /// The reading the current refresh took.
    private var latest = Reading.none
    /// The two edges, made once: a stream is consumed by whoever merges it.
    nonisolated let changeEvents: [AsyncStream<Void>]

    init(
        listing: any ClaudeCodeSessionListing,
        sessionsDirectory: URL? = nil,
        /// Which entries of that directory belong to a `claude` this app
        /// launched. Injected only so the rule can be tested without launching
        /// one — see ``sessionsChanged(_:invalidating:in:ownedBy:)``.
        ownsSessionRecord: (@Sendable (String) -> Bool)? = nil,
        /// Whether a `claude` executable can be found at all. Injected so a
        /// test does not answer with whatever the developer happens to have
        /// installed.
        commandIsInstalled: (@Sendable () -> Bool)? = nil,
        timing: MonitorTiming = .standard
    ) {
        self.listing = listing
        self.commandIsInstalled = commandIsInstalled
            ?? { ClaudeExecutableLocator.locate() != nil }
        // Two edges, no cadence. An event arriving means a turn moved; the
        // sessions directory changing means one appeared or went away, which is
        // the only way a row whose session died can be retired now that
        // SessionEnd is not registered.
        let watched = sessionsDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/sessions", isDirectory: true)
        let sessionsWatcher = DirectoryChangeWatcher(
            directoryURL: watched,
            debounceInterval: timing.unreadStateDebounceInterval
        )
        self.sessionsWatcher = sessionsWatcher
        // Seeded from the attach `init` has just attempted, so an ordinary
        // launch -- the directory already there -- does not report an edge for
        // a watcher that was never off.
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
            // Two edges from one directory, answering two different questions.
            // The one above is a session appearing or going away, which is the
            // list being *wrong*; this one is a record being rewritten, which
            // is the list being *out of date* about what that session is doing.
            // Both invalidate it, because in both cases the held answer cannot
            // be the current one.
            Self.sessionsChanged(
                recordWatcher.events(),
                invalidating: listing
            ),
        ]
    }

    /// The list, read once for this refresh.
    ///
    /// - Parameter state: The Turns the reducer holds after this refresh's
    ///   drain. A Turn the list does not name, and that has moved since the
    ///   list was read, is the one reason to read again on the spot.
    func read(observing state: HookStateSnapshot) async -> SessionReading {
        // `~/.claude/sessions` does not exist until Claude Code has run once,
        // so the attach made in `init` fails for a user who registered the
        // hooks first. Retried here, on work this refresh was doing anyway, for
        // the reason the Hook queue's watcher is: nothing else would ever ask
        // again, and one failed `open` per refresh is cheaper than a timer.
        //
        // **Attaching is itself an edge**, and it has to be reported as one
        // now that a known-empty session list is held rather than re-read on a
        // cadence (CR-Fable-002). Until this moment nothing was watching the
        // directory, so the emptiness the registry is holding was read blind:
        // the very first Claude Code session a user ever starts is the one
        // that *creates* this directory, and it would otherwise go unlisted
        // until it fired a hook. The watcher itself cannot deliver this --
        // attaching bumps its change count but yields nothing to a stream that
        // had no event -- so the transition is noticed here.
        let watchingSessionsDirectory = sessionsWatcher.attachIfNeeded()
        if watchingSessionsDirectory, !wasWatchingSessionsDirectory {
            await listing.invalidate()
        }
        wasWatchingSessionsDirectory = watchingSessionsDirectory

        // Presence first, and once. It is asked before the list rather than
        // after it so both come from the same reading: asked afterwards, the
        // two calls could land either side of a refresh and describe different
        // instants.
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

        // **A hook event is itself evidence that its session exists**, and
        // when it is newer than the reading, it outranks it.
        //
        // Every route by which the list goes wrong is meant to be reported by
        // an edge, and one route had none: a session id is not fixed for the
        // life of a process. `/clear` and an in-session `/resume` rotate it in
        // place -- same pid, same `~/.claude/sessions/<pid>.json`, same inode,
        // a new `sessionId` written into it. Measured on this machine
        // 2026-08-21: a record still naming the pid and start time of a process
        // launched at 23:14 carried a session id whose transcript begins at
        // 01:14, two hours later. Nothing is created and nothing is removed, so
        // the directory source cannot see it; the record source is the one that
        // can, and it is now pointed at every listed session for exactly this
        // reason (below).
        //
        // This is the fail-safe behind that, and it is stated in terms of the
        // evidence rather than of any one way the list can rot: the reducer is
        // holding a Turn whose session the list does not name, and that Turn
        // has moved since the reading was taken. A reading that started before
        // the event cannot have seen what the event is reporting, so it is the
        // reading that is wrong, not the Turn -- and the row that would
        // otherwise be dropped below is drawn in this same refresh instead of
        // whenever the next reading happens to land.
        //
        // Bounded on both sides. Turns that have *not* moved since the reading
        // -- a session that really did end without a `Stop` -- never ask for
        // anything, so a Turn the list will never name cannot become a `claude`
        // launch every refresh. And what an invalidation costs is the
        // registry's decision, not this one's: ``edgeFloor`` holds the extra
        // reading to one every two seconds however many events arrive.
        var readStartedAt = await listing.listReadStartedAt()
        let heardFromAnUnlistedSession = state.turns.contains { turn in
            liveByID[turn.threadID] == nil && turn.lastEventAt > readStartedAt
        }
        if heardFromAnUnlistedSession {
            await listing.invalidate()
            (presence, live, liveByID) = await readSessions()
            // Re-asked so this stays the reading `liveByID` actually came from.
            // It is the left-hand side of the pruning below as well as of the
            // test above, and a list re-read on the spot can speak for
            // everything up to the moment it started -- which is the whole
            // point of having asked for it again.
            readStartedAt = await listing.listReadStartedAt()
        }

        latest = Reading(
            presence: presence,
            sessions: live,
            sessionsByID: liveByID,
            readStartedAt: readStartedAt
        )

        // Watch every listed session's record -- not only the ones with a Turn
        // in flight.
        //
        // It used to be only those, on the argument that a session sitting at
        // its prompt needs no edge because "the turn it starts next announces
        // itself with a hook, and its record flips `busy` in the same moment,
        // which would have bought a launch for an answer already on its way".
        // That argument holds only while the hook and the list agree on what
        // the session is called, and the record of an idle session is where
        // they stop agreeing: `/clear` rotates the session id in place, so the
        // list goes on naming the id the session had before while every hook
        // from then on carries the new one. The idle record is not the one
        // edge that could be spared, it is the one edge that reports the
        // rename -- and the app was blind to it for the whole freshness
        // window, which is up to thirty seconds of a turn drawing no row at
        // all.
        //
        // The cost of an edge is still one `claude agents --json`, and it is
        // small because these files are quiet. Measured here 2026-08-21, one
        // sample a second for ninety seconds across six live sessions -- two
        // of them interactive and sitting at their prompt: **not one record was
        // rewritten**. A record is written when a session flips `busy`,
        // `waiting` or `idle`, several times a turn, and the registry's
        // ``edgeFloor`` caps a burst of those at one reading every two seconds
        // whatever their source.
        //
        // Taken from the list rather than from the rows, which also settles
        // what the old comment had to argue around: a row withheld for presence
        // is a Turn this app still holds and still has to be able to end, and
        // its session is listed either way.
        recordWatcher.watch(processIdentifiers: Set(live.map(\.processIdentifier)))

        // What this reading says exists is what the Turns behind the rows are
        // held to.
        //
        // This was the one pruning missing (CR-Fable-008). Rows were right
        // without it -- a turn whose session is not listed draws nothing -- so
        // what grew was not the panel but the work behind it:
        // `HookEventRepository` builds and sorts one string per held turn on
        // *every* reduced batch of events, and sorts them all again on every
        // refresh. Both therefore scaled with everything the process had ever
        // seen rather than with what was on screen, and each dead entry also
        // held its two previews and a `retiredTurnIDs` set for the life of the
        // app. Measured under Release at ~2.2 µs per held turn per event, which
        // puts one event at 5.3 ms once 2000 entries have collected -- 2.5x
        // what CC-015 priced the whole transport at (`system-architecture.md`
        // §6).
        //
        // A session count understates how fast that arrives here. `/clear` and
        // an in-session `/resume` rotate the session id in place, so a single
        // long-lived CLI mints a fresh dead entry every time the user clears
        // context -- the same behaviour the unlisted-session check above exists
        // for, seen from the other end.
        //
        // **Only where the list is knowledge.** Presence `unknown` is `claude`
        // having failed to answer past the trust ceiling, and a list nobody has
        // confirmed is not evidence that a session ended (`AGENTS.md` §6.2) --
        // it is the reading that is missing, not the session. `closed` is the
        // opposite and prunes like any other answer: it is the command saying
        // nothing is running. The rows are withheld either way, and the
        // difference is that only one of the two may also *forget*.
        let admission: ThreadAdmission = presence == .unknown
            ? .unknown
            : .exactly(Set(liveByID.keys), readAt: readStartedAt)

        // **The card may not say Connected while the mark is absent.**
        //
        // Registration used to be the whole of what this product reported, so
        // `Connected · hooks installed` was said on a machine where nothing was
        // being watched at all -- the notch drew no Claude Code mark, no row
        // ever appeared, and the one surface with room to explain that agreed
        // with none of it. `unknown` is the registry saying it has no reading
        // to offer, which is `AGENTS.md` §6.7's plain sense of the word: there
        // is no working connection to report on. `closed` is not the same
        // sentence and must not be caught by it -- that is `claude` answering
        // that nothing is open, which is a healthy machine with no session
        // running.
        return SessionReading(
            presence: presence,
            admission: admission,
            unwatchableReason: presence == .unknown ? unwatchableReason() : nil
        )
    }

    /// Nothing is being monitored, so nothing is worth an edge. Left alone, an
    /// integration switched off would keep a descriptor open on the record of
    /// whatever turn happened to be running when it was.
    func stopWatching() {
        recordWatcher.watch(processIdentifiers: [])
    }

    /// What the current refresh's reading said.
    func currentReading() -> Reading {
        latest
    }

    /// The process each session ran as in the current refresh's reading, for a
    /// source that must ask about the list that proved its rows exist.
    nonisolated var listedProcesses: ListedProcesses {
        ListedProcesses(source: self)
    }

    nonisolated struct ListedProcesses: SessionProcessLocating {
        let source: ClaudeCodeSessionSource

        func processIdentifier(forThreadID threadID: String) async -> Int32? {
            await source.currentReading().sessionsByID[threadID]?.processIdentifier
        }
    }

    /// The process running a session, for navigation.
    ///
    /// The same list the rows come from, asked again at click time. A session
    /// that has ended is no longer in it, so the click fails and the store
    /// corrects the set -- which is the re-confirmation the PRD asks for before
    /// a click, done against the product's own answer rather than against a pid
    /// this app wrote down when the row was drawn.
    func processIdentifier(forThreadID threadID: String) async -> Int32? {
        await listing.liveSessions()
            .first { $0.sessionID == threadID }?
            .processIdentifier
    }

    /// The sessions-directory edge, with the session list told before anyone is
    /// woken by it.
    ///
    /// The order is the entire point, and getting it wrong is what the bug was.
    /// The edge already woke a refresh; what it did not do was tell the list,
    /// so the refresh it caused asked a cache that was up to a ``freshness``
    /// old and got back the answer from before the session existed. Telling the
    /// registry inside the forwarder -- before the yield the consumer is
    /// waiting on -- means the refresh this edge causes is the one that re-reads.
    ///
    /// A yield still happens when the list refuses to re-read that soon: the
    /// edge is also how a row whose session died gets retired, and the
    /// consumer's own reasons for refreshing are none of this function's
    /// business.
    ///
    /// - Parameter directory: The sessions directory, when this edge is the
    ///   directory's own. Given, the forwarder skips ``invalidate()`` for the
    ///   one change that cannot mean anything: the appearance or removal of a
    ///   record belonging to a `claude` **this app launched itself**. The quota
    ///   reading is such a session, so every reading used to buy a `claude
    ///   agents --json` -- a Node launch -- to be re-told about a session the
    ///   registry filters out anyway. See ``ClaudeCommand/ownsSessionRecord(named:)``.
    ///
    ///   Narrow on purpose, and in the safe direction on every other input: an
    ///   edge that changes no name at all, one that changes a name this app
    ///   cannot claim, or a directory that cannot be listed all invalidate
    ///   exactly as before. Only "every name that moved is one of ours" is
    ///   quiet. Nil for the record-file edge, which watches sessions this app
    ///   is drawing rows for and can therefore never be looking at its own.
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

    /// The names in a directory, and nothing else about it.
    ///
    /// Names, deliberately: a session record's *contents* are a private schema
    /// this app does not read, and the rule that the directory is a change
    /// signal rather than a source of truth still holds -- what sessions exist
    /// still comes only from `claude agents --json`. A name is used here for
    /// one question and it is a question about this app: "did the thing that
    /// moved belong to a process I started?"
    nonisolated private static func entryNames(of directory: URL) -> Set<String> {
        let names = try? FileManager.default.contentsOfDirectory(
            atPath: directory.path
        )
        return Set(names ?? [])
    }

    /// Why this app has no reading of Claude Code's sessions, in words a user
    /// can act on.
    ///
    /// Asked only where presence is already `unknown`, and never re-asking it:
    /// presence is read once per refresh so the rows and the mark describe one
    /// instant, and a second reading here could land the other side of one.
    ///
    /// **Two failures reach that one word, and they ask opposite things of the
    /// person reading it.** One is that there is no `claude` on the machine to
    /// run at all -- the ordinary shape of which was a user with Claude Desktop
    /// who never installed the terminal command, invisible until
    /// ``ClaudeExecutableLocator`` learned to fall back to Desktop's own copy,
    /// so reaching this now means neither exists. The other is a `claude` that
    /// is there and will not answer, which is where a command wedged behind an
    /// MCP server lands; telling that user to install what they already have
    /// would send them the wrong way entirely.
    ///
    /// It is a sentence and not a state. Nothing branches on which of the two
    /// it is -- the availability is `.disconnected` either way -- and the card
    /// draws this underneath a headline that claims neither.
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
