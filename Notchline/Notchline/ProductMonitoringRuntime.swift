import AppKit
import Foundation

// The shared monitoring runtime, and the shapes of the evidence
// a product hands it: whether the product is open and which Threads it vouches
// for, what it writes down about a Turn beyond live events, and what each row
// says. Read evidence, usage and the transport have their shapes beside the
// types that implement them (`TerminalUnreadRowFilter.swift`,
// `ProductContracts.swift`, `MonitoringLifecycleSource.swift`). `tiered-support.md`
// §5.4 is the design; Claude Code and Antigravity CLI are compositions of it.

/// Whether a product is open, as the user would judge it by glancing at their
/// own machine (``AgentPresence``). Codex reads the running-application list
/// (``RunningApplicationPresence``); Claude Code reads its own session list,
/// with a trust ceiling (``ClaudeCodeSessionListing``); Antigravity CLI reads
/// the presence locks its processes hold.
protocol ProductPresenceReporting: Sendable {
    func presence() async -> AgentPresence
}

/// A desktop product's presence: is an application with one of these bundle
/// identifiers running. A kernel fact, so never `unknown`.
///
/// **The process as well as the answer**, because a desktop product's
/// presence is one reading of the running-application list and a Provider may
/// need both halves of it at once. Codex binds its hook evidence to the pid
/// that vouched for it (CR-Fable-007), so the pid and the presence drawn beside
/// it must come from the same look, not from two looks either side of a quit.
struct RunningApplicationPresence: ProductPresenceReporting {
    private let runningProcessIdentifier: @MainActor @Sendable () -> pid_t?

    init(bundleIdentifiers: [String]) {
        runningProcessIdentifier = {
            Self.runningProcessIdentifier(bundleIdentifiers: bundleIdentifiers)
        }
    }

    /// A list standing in for the running-application list, for a test that
    /// must not answer with whatever happens to be open on the machine.
    init(processIdentifier: @escaping @MainActor @Sendable () -> pid_t?) {
        runningProcessIdentifier = processIdentifier
    }

    /// The running process, or nil when none is.
    func processIdentifier() async -> pid_t? {
        await runningProcessIdentifier()
    }

    func presence() async -> AgentPresence {
        Self.presence(of: await processIdentifier())
    }

    /// What one reading says: open while a process runs, closed otherwise.
    nonisolated static func presence(of processIdentifier: pid_t?) -> AgentPresence {
        processIdentifier == nil ? .closed : .open
    }

    /// The first live process with one of these bundle identifiers.
    ///
    /// A terminated instance is skipped: the workspace keeps listing an
    /// application for a moment after it has quit, and presence is the
    /// user's judgement of their own machine, on which it is gone.
    @MainActor
    static func runningProcessIdentifier(bundleIdentifiers: [String]) -> pid_t? {
        for identifier in bundleIdentifiers {
            if let running = NSRunningApplication
                .runningApplications(withBundleIdentifier: identifier)
                .first(where: { !$0.isTerminated }) {
                return running.processIdentifier
            }
        }
        return nil
    }
}

/// Which of the observed Threads the product still vouches for
/// (ADR 0017): the answer that lets a Turn be retired because its Thread has
/// gone, and the only thing that may retire one this way.
enum ThreadAdmission: Sendable, Equatable {
    /// The product keeps no list this app can ask. Every Thread live evidence
    /// named stays until its own exits apply — the next submission, dismissal.
    case everyObservedThread
    /// Exactly these Threads exist, as a read that started at `readAt` found
    /// them. A Turn whose last event predates that read and whose Thread is
    /// absent is retired; one that spoke after the read began is kept, because
    /// the read cannot have seen it.
    case exactly(Set<String>, readAt: Date)
    /// The list could not be read. Nothing is retired on a failure to ask.
    case unknown
}

protocol ThreadAdmitting: Sendable {
    func admission() async -> ThreadAdmission
}

struct AdmitsEveryObservedThread: ThreadAdmitting {
    func admission() async -> ThreadAdmission { .everyObservedThread }
}

/// What one reading of a product's own list says: whether the product is open,
/// which Threads it vouches for, and why it cannot be watched when that is the
/// answer.
nonisolated struct SessionReading: Sendable, Equatable {
    let presence: AgentPresence
    let admission: ThreadAdmission
    /// A sentence the user can act on while presence is `unknown`; nil to have
    /// the Provider say the generic one.
    let unwatchableReason: String?

    init(presence: AgentPresence, admission: ThreadAdmission, unwatchableReason: String? = nil) {
        self.presence = presence
        self.admission = admission
        self.unwatchableReason = unwatchableReason
    }
}

/// A product's presence and admission, read together once per refresh.
///
/// **Together, because a product that has a list answers both from it** and
/// two askings could land either side of a change: Claude Code's presence is
/// its session list being non-empty, Antigravity CLI's is a process holding a
/// presence lock, and each also names the Threads it vouches for. A product
/// whose two answers really are separate hands them in apart
/// (``SeparateSessionReading``).
protocol ProductSessionReading: Sendable {
    /// One reading for this refresh.
    ///
    /// - Parameter state: The Turns the reducer holds after the refresh's
    ///   drain, for a product whose list can be shown to be behind them — a
    ///   Turn it does not name that moved after it was read.
    func read(observing state: MonitoringStateSnapshot) async -> SessionReading
    /// Nothing is being monitored: stop any watcher the readings pointed at
    /// the product's own records.
    func stopWatching() async
}

/// Presence and admission answered by two sources that need not agree on an
/// instant — a running-application list and "every observed Thread", say.
struct SeparateSessionReading: ProductSessionReading {
    let presence: any ProductPresenceReporting
    let admission: any ThreadAdmitting

    func read(observing state: MonitoringStateSnapshot) async -> SessionReading {
        SessionReading(presence: await presence.presence(), admission: await admission.admission())
    }

    func stopWatching() async {}
}

/// Evidence about a Turn the reducer holds that is not a hook event: an
/// interrupt the product wrote down, a dialog answered in the product's own
/// window, the Turn a thread's own record says it is on
/// ([ADR 0011](../../docs/adr/0011-a-turn-may-end-on-evidence-that-is-not-a-hook-event.md)).
///
/// **It hands facts to the reducer and decides nothing.** The reducer stays the
/// only thing that computes Turn state, applying to each fact the ordering
/// guards any event gets; a source may end a Turn, close a wait or settle
/// which Turn a thread is on, and never open, name or describe one. Claude
/// Code's is ``ClaudeCodeTurnEvidence``, Codex's ``CodexRolloutTurnEvidence``.
protocol TurnEvidenceSource: Sendable {
    /// Ordered readings, allowing a record-confirmed held start to be applied
    /// before asking about termination. Sources receive values, never a reducer.
    nonisolated var phases: [TurnEvidencePhase] { get }
    func observations(in state: MonitoringStateSnapshot, phase: TurnEvidencePhase) async -> TurnEvidenceBatch
    /// Points any watcher at the records of the Turns still open once the
    /// refresh has settled them, and at nothing else, so a Turn the refresh
    /// just ended stops being watched in the pass that ended it.
    func watch(openTurnsIn state: MonitoringStateSnapshot) async
    /// Nothing is being monitored.
    func stopWatching() async
}

extension MonitoringRepository {
    /// Holds the Turns to the Threads a product vouches for (ADR 0017).
    ///
    /// Only an exact list retires anything, and only a Turn whose last event
    /// predates the reading: a list that could not be read, or a product with
    /// no list, retires nothing on a failure to ask.
    func applying(_ admission: ThreadAdmission, to state: MonitoringStateSnapshot) -> MonitoringStateSnapshot {
        guard case let .exactly(threadIDs, readAt) = admission else { return state }
        return removeThreads(notIn: threadIDs, snapshotStartedAt: readAt)
    }
}

/// What a row says beyond its Turn's own state.
nonisolated struct RowContent: Sendable, Equatable {
    let projectName: String
    let title: String
    let preview: String?
}

/// A product's project, title and line for each Turn, and whether a Turn draws
/// a row at all.
///
/// Everything else on a row — status, clock, subagents, the request — is the
/// reducer's, and the Provider writes it; this is only what each product knows
/// differently. ``WorkingDirectoryRowContent`` is what a product with nothing
/// of its own gets; Claude Code's is ``ClaudeCodeRowContent``.
protocol RowContentSource: Sendable {
    /// Content for each Turn that draws a row, keyed by Thread. A Turn with no
    /// entry draws none.
    ///
    /// - Parameter messages: The store of what each Turn has said, for a
    ///   product whose vocabulary names a message event.
    func content(
        for turns: [MonitoredTurnState],
        messages: TurnMessageReading
    ) async -> [String: RowContent]
}

/// The L2 context fallback: the submission directory's last component for a project,
/// the prompt for a title, and the Turn's closing words or its newest message
/// for a line.
struct WorkingDirectoryRowContent: RowContentSource {
    func content(
        for turns: [MonitoredTurnState],
        messages: TurnMessageReading
    ) async -> [String: RowContent] {
        Dictionary(
            turns.map { turn in
                (
                    turn.threadID,
                    RowContent(
                        projectName: Self.projectName(forWorkingDirectory: turn.workingDirectory),
                        // Empty when the Turn has not printed a prompt either;
                        // ``MonitoredSession/init`` supplies
                        // ``RowContentFallback/title`` for the row.
                        title: turn.promptPreview ?? "",
                        // The closing words once the Turn has ended with some,
                        // and until then the newest message this Turn has said,
                        // for a product whose vocabulary names a message event.
                        // The prompt is not the fallback here, as it is on Claude
                        // Code's row: it is already the title.
                        preview: turn.assistantPreview
                            ?? messages.preview(forSession: turn.threadID, inTurn: turn.turnID)
                    )
                )
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The submission directory's last component, which `tech-design.md` §5
    /// permits as a project name; empty when there is none, which
    /// ``MonitoredSession/init`` reads as ``RowContentFallback/projectName``.
    nonisolated static func projectName(forWorkingDirectory path: String?) -> String {
        let component = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        return component == "/" ? "" : component
    }
}

/// Shared source-driven monitoring runtime. Hooks are one composition; a
/// source with no setup supplies its typed repository and readiness directly.
/// Codex continues to own its separate App Server orchestration.
actor ProductMonitoringRuntime: AgentMonitoring, DiskFootprintReporting {
    nonisolated let agent: AgentKind
    nonisolated let stateChangeEvents: AsyncStream<Void>

    private let composition: MonitoringSourceComposition
    private var isObserving = false
    private var lifecycleRevision = 0
    private var lastSetupStatus: IntegrationSetupStatus?
    private let lifecycle: any MonitoringLifecycleSource
    private let sessions: any ProductSessionReading
    /// What the product writes down about its Turns beyond the hooks, applied
    /// in order after admission (``TurnEvidenceSource``).
    private let turnEvidence: [any TurnEvidenceSource]
    private let rowContent: any RowContentSource
    /// What says the user has read a finished answer, or nil for a product
    /// that supplies no such evidence.
    private let readEvidence: (any ReadEvidenceSource)?
    /// How much of the product's limits is left, or nil for a product that
    /// reports none (``UsageReading``).
    private let usage: (any UsageReading)?
    /// What the product leaves on disk, or nil for one that leaves nothing.
    private let footprint: (any DiskFootprintReporting)?
    /// Keeps a finished row listed until it has been read, and retires it the
    /// moment it has been.
    private var readGate: TerminalUnreadRowFilter
    private let clock: any MonitorClock

    init(
        agent: AgentKind,
        /// The product's transport, wired once.
        lifecycle: any MonitoringLifecycleSource,
        /// Whether the product is open and which Threads it vouches for, read
        /// together once per refresh.
        sessions: any ProductSessionReading,
        /// Interrupts and answered waits the product records somewhere a hook
        /// does not reach, in the order they are to be applied.
        turnEvidence: [any TurnEvidenceSource] = [],
        /// What each row says beyond its Turn's state, and which Turns draw
        /// one.
        rowContent: any RowContentSource = WorkingDirectoryRowContent(),
        /// What retires a finished row once it has been read. A product that
        /// supplies none keeps a finished row until the Thread's next
        /// submission, its departure from the admission list or a right-click.
        readEvidence: (any ReadEvidenceSource)? = nil,
        /// The product's quota, for one that reports limits. Its reads land on
        /// an edge the composer merges into `changeEvents`.
        usage: (any UsageReading)? = nil,
        /// What the product leaves on disk, for one that leaves anything.
        footprint: (any DiskFootprintReporting)? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard,
        /// Edges from the product's sources that mean "ask me again", merged
        /// with the reducer's own.
        changeEvents: [AsyncStream<Void>] = []
    ) {
        self.agent = agent
        self.lifecycle = lifecycle
        self.sessions = sessions
        self.turnEvidence = turnEvidence
        self.rowContent = rowContent
        self.readEvidence = readEvidence
        self.usage = usage
        self.footprint = footprint
        self.readGate = TerminalUnreadRowFilter(timing: timing)
        self.clock = clock
        let sources: [any Sendable] = [lifecycle, sessions, rowContent]
            + turnEvidence.map { $0 as any Sendable }
            + (readEvidence.map { [$0 as any Sendable] } ?? [])
            + (usage.map { [$0 as any Sendable] } ?? [])
        let composition = MonitoringSourceComposition(sources, clock: clock)
        self.composition = composition
        self.stateChangeEvents = DirectoryChangeWatcher.merged(
            [lifecycle.repository.changeEvents()] + composition.changeEvents + changeEvents
                // The display waking or the screen unlocking. A row waiting to
                // be read books no re-check while neither is true, because
                // every route that could retire it needs a screen somebody can
                // see; this is the edge that starts the re-checks again.
                // Without it such a row would sit until the heartbeat, at the
                // one moment the user is most likely to be looking.
                + (readEvidence.map { [$0.screen.changeEvents()] } ?? [])
        )
    }

    func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot {
        let revision = lifecycleRevision
        let status: IntegrationSetupStatus?
        let gate = await lifecycle.gate(productName: agent.displayName)
        guard revision == lifecycleRevision else { return stoppedSnapshot() }
        switch gate {
        case let .open(openStatus):
            status = openStatus
            lastSetupStatus = openStatus
        case let .closed(availability, closedStatus, diagnostic):
            lastSetupStatus = closedStatus
            // Nothing is being monitored, so nothing is worth an edge, and
            // nothing is listed, so nothing is waiting to be read. Left
            // standing, a watcher would keep a descriptor open on the records
            // of whatever Turn was running when the integration went, the
            // gate's entries would go on booking a re-check a second for rows
            // nobody can see, and a session seen on a screen then would come
            // back still claiming it.
            lifecycle.disconnect()
            if availability == .setupRequired {
                await lifecycle.repository.resetIntegrationObservation(clearTurns: true)
            }
            await stopEverything()
            return snapshot(
                availability: availability,
                sessions: [],
                setupStatus: closedStatus,
                diagnostic: diagnostic,
                // A product with limits has them whether or not its hooks are
                // registered; they are simply not being read.
                quota: usage == nil ? .noneReported : .unavailable,
                // The branches that do not reach the product's list genuinely
                // did not look, and none of them is `ready` whatever presence
                // would say.
                presence: .unknown
            )
        }

        guard revision == lifecycleRevision else { return stoppedSnapshot() }
        isObserving = true
        await composition.refresh(at: clock.now())
        guard revision == lifecycleRevision else { return stoppedSnapshot() }
        var state = await lifecycle.repository.drainDeliveredEvents()
        let reading = await sessions.read(observing: state)
        guard revision == lifecycleRevision else { return stoppedSnapshot() }
        let presence = reading.presence
        state = await lifecycle.repository.applying(reading.admission, to: state)
        for source in turnEvidence {
            state = await SupplementaryEvidenceApplication.settle(source, from: state, in: lifecycle.repository)
            guard revision == lifecycleRevision else { return stoppedSnapshot() }
        }
        // After the reduction, so a Turn this refresh just ended stops being
        // watched in the same pass that ended it.
        for source in turnEvidence {
            await source.watch(openTurnsIn: state)
            guard revision == lifecycleRevision else {
                if !isObserving { await source.stopWatching() }
                return stoppedSnapshot()
            }
        }

        let content = await rowContent.content(for: state.turns, messages: lifecycle.repository.messageReader)
        guard revision == lifecycleRevision else { return stoppedSnapshot() }
        let candidates = state.turns.compactMap { turn -> ReadGateCandidate? in
            guard let content = content[turn.threadID] else { return nil }
            return ReadGateCandidate(
                row: row(for: turn, content: content),
                turnEndedAt: turn.turnEndedAt,
                // The later of the Turn's own last event and the last subagent
                // boundary: only the settling window is measured from it.
                terminalBoundaryAt: turn.terminalBoundaryAt
            )
        }

        var rows: [MonitoredSession] = []
        var readDiagnostic: String?
        if presence == .closed {
            // The product's own list says nothing is open, so nothing listed
            // is waiting to be read.
            readGate.reset()
            await readEvidence?.forget()
        } else {
            // Judged even while presence is `unknown`, and withheld below. A
            // list nobody could read is not evidence a session ended, and a
            // row already hidden for having been read must not come back the
            // moment the list answers again (CC-024).
            (rows, readDiagnostic) = await rowsStillWorthShowing(
                candidates,
                dismissedRowIDs: dismissedRowIDs
            )
        }
        // Live text for a Thread the product no longer lists and that draws no
        // row is pruned, and the set kept is also what lets a message arriving
        // later wake the panel (``TurnPreviewStore/fold``). So it is the
        // Threads the product's own list names, whether or not the reducer
        // holds a Turn for them yet -- text arriving for a listed session with
        // no row is exactly the text that has nothing else to draw it -- and
        // the rows built rather than the rows shown, so a row the read gate
        // withheld keeps its words for the next refresh that asks.
        guard revision == lifecycleRevision else {
            if !isObserving { readGate.reset(); await readEvidence?.forget() }
            return stoppedSnapshot()
        }
        var retainedThreadIDs = Set(candidates.map(\.row.threadID))
        if case let .exactly(listed, _) = reading.admission {
            retainedThreadIDs.formUnion(listed)
        }
        lifecycle.repository.retainPreviews(
            forSessions: presence == .closed ? [] : retainedThreadIDs
        )

        // Presence unknown is the one state reported as unwatchable: the
        // product may be open and busy, and drawing nothing while claiming
        // Connected would be the guess PRD §12 forbids.
        let unwatchable: String? = presence == .unknown
            ? reading.unwatchableReason
                ?? "\(agent.displayName) is registered, but this app cannot tell whether it is open."
            : nil
        // Whatever is known right now, with a read started behind it. Awaiting
        // the read here would make a hook event's row wait on it.
        await usage?.readIfStale()
        let diagnostic = MonitorDiagnostics.combined(unwatchable, state.diagnostic, readDiagnostic,
            await composition.diagnostic(), await usage?.quotaDiagnostic())
        let quota = await usage?.currentQuota() ?? .noneReported
        guard revision == lifecycleRevision else { return stoppedSnapshot() }
        return snapshot(
            availability: unwatchable == nil ? .ready : .disconnected,
            // A product that is not open contributes no rows.
            //
            // A list that fails to answer goes on handing back its last
            // reading, because a failed read is not evidence a session ended,
            // and it does so on the understanding that the surface retires the
            // rows by the product going Disconnected. The surface reads the
            // rows before it reads presence, so a product whose mark had
            // already gone still had its row on screen saying `Running` --
            // the state a user sees as the product vanishing while it carries
            // on working.
            sessions: presence.isOpen ? rows : [],
            setupStatus: status,
            diagnostic: diagnostic,
            quota: quota,
            // Not "has rows": a product open with nothing in flight is still
            // open. The list answers which sessions exist and the reducer what
            // they are doing.
            presence: presence
        )
    }

    /// Everything a closed integration stops.
    private func stopEverything() async {
        lifecycleRevision += 1
        isObserving = false
        await composition.stop()
        readGate.reset()
        await readEvidence?.forget()
        await sessions.stopWatching()
        for source in turnEvidence {
            await source.stopWatching()
        }
    }

    /// The rows to list, with a finished one the user has already read taken
    /// off.
    ///
    /// **A row is withheld only on evidence that somebody read it**, and only a
    /// product that supplied a ``ReadEvidenceSource`` has any: with none, every
    /// row is listed and the gate is never consulted.
    ///
    /// Which rows are judged at all, and how, is ``TerminalUnreadRowFilter``'s.
    /// What is the product's is only the verdict, and it is taken only for a row
    /// that could be withheld: no reading happens unless a finished row the
    /// user has not waved away is listed (CR-Fable-041, CR-Fable-003).
    private func rowsStillWorthShowing(
        _ candidates: [ReadGateCandidate],
        dismissedRowIDs: Set<String>
    ) async -> (rows: [MonitoredSession], diagnostic: String?) {
        guard let readEvidence else {
            return (candidates.map(\.row).sorted(by: MonitorAggregation.rowOrder), nil)
        }
        let now = clock.now()
        guard TerminalUnreadRowFilter.needsReadEvidence(
            candidates.map(\.row),
            dismissedRowIDs: dismissedRowIDs
        ) else {
            await readEvidence.forget()
            let rows = readGate.rows(candidates, dismissedRowIDs: dismissedRowIDs, now: now) { _ in
                .cannotBeAsked
            }
            return (rows, nil)
        }
        let judgement = await readEvidence.verdicts(
            for: candidates.filter { !dismissedRowIDs.contains($0.row.id) },
            now: now
        )
        let rows = readGate.rows(candidates, dismissedRowIDs: dismissedRowIDs, now: now) {
            judgement.verdicts[$0.row.id] ?? .cannotBeAsked
        }
        // The diagnostic goes with the reading that produced it, so a list with
        // nothing to judge says nothing about readings it did not take.
        return (rows, judgement.diagnostic)
    }

    /// Every timed source's next moment, and nothing else: the usage reader's
    /// next read, and a finished row waiting to be read. The reducer's edges,
    /// the sources' own and the store's heartbeat are the only other reasons
    /// to ask again, and a deadline a refresh could not advance would be a
    /// busy-wait wearing a deadline's clothes.
    ///
    /// A row waiting to be read waits on the user rather than on time, so its
    /// deadline is a floor under the edges — and some of what it waits for (a
    /// terminal's access time, whether an application holds the front) moves
    /// with nothing to watch it, so it can only be asked at a re-check. It
    /// costs nothing while no such row is listed, and nothing at all while the
    /// screen is one nobody could read it on.
    func nextRefreshDeadline() async -> Date? {
        guard isObserving else { return nil }
        return [
            await composition.nextDeadline(),
            // A held answer window running out: the refresh that withdraws
            // the handle is what turns the mark from `Answer` to `Read`.
            lifecycle.repository.nextAnswerExpiry(),
            await usage?.nextReadDeadline(),
            readEvidence.flatMap {
                readGate.nextDeadline(now: clock.now(), screenIsAvailable: $0.screen.isAvailable())
            }
        ]
        .compactMap { $0 }
        .min()
    }

    /// What the product leaves on disk; nothing, for a product that supplied
    /// no reporter.
    func diskFootprint() async -> AgentDiskFootprintReport {
        await footprint?.diskFootprint() ?? .leavesNothing
    }

    func disconnect() async {
        lifecycleRevision += 1
        isObserving = false
        lifecycle.disconnect()
        await lifecycle.repository.resetIntegrationObservation(clearTurns: true, preserveBoundaryObservation: true)
        await stopEverything()
    }

    private func stoppedSnapshot() -> AgentSnapshot {
        snapshot(availability: .disconnected, sessions: [], setupStatus: lastSetupStatus,
                 diagnostic: nil, quota: usage == nil ? .noneReported : .unavailable, presence: .unknown)
    }

    private func row(for turn: MonitoredTurnState, content: RowContent) -> MonitoredSession {
        MonitoredSession(
            agent: agent,
            threadID: turn.threadID,
            turnID: turn.turnID,
            projectName: content.projectName,
            title: content.title,
            preview: content.preview,
            status: turn.status,
            startedAt: turn.startedAt,
            // What the row says once its own Turn has stopped and the thread
            // has not: a Turn can reach its end with work it started still in
            // flight.
            runningSubagentCount: turn.runningSubagentIDs.count,
            subagentsAwaitingApprovalCount: turn.subagentsAwaitingApprovalCount,
            // What the row says between its subagent stopping and the Turn the
            // product opens next: a Turn that stopped in order to wait is not a
            // thread that has finished.
            isPausedForBackgroundWork: turn.pausedForBackgroundWork,
            // How long the Turn took, for the row that draws it once the clock
            // has stopped. `lastEventAt` is the Turn's own last moment and is
            // held there against a subagent's chatter.
            finishedAt: turn.status == .completed ? turn.lastEventAt : nil,
            requests: turn.requestsAwaitingAnAnswer
        )
    }

    /// The submission directory's last component — see
    /// ``WorkingDirectoryRowContent/projectName(forWorkingDirectory:)``.
    nonisolated static func projectName(forWorkingDirectory path: String?) -> String {
        WorkingDirectoryRowContent.projectName(forWorkingDirectory: path)
    }

    private func snapshot(
        availability: MonitorAvailability,
        sessions: [MonitoredSession],
        setupStatus: IntegrationSetupStatus?,
        diagnostic: String?,
        quota: QuotaSnapshot,
        presence: AgentPresence
    ) -> AgentSnapshot {
        AgentSnapshot(
            agent: agent,
            availability: availability,
            sessions: sessions,
            // For a product with no usage reader, no quota rather than a quota
            // that could not be read: its footer group is a name and a spend
            // with no lines under it (`quota-footer-v2.md` §5).
            quota: quota,
            diagnostic: diagnostic,
            // No setup is distinct from installed and from channel readiness.
            setupStatus: setupStatus ?? .notRequired,
            presence: presence
        )
    }
}
