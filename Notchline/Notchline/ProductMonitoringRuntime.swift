import AppKit
import Foundation

// The shared monitoring runtime and the evidence shapes a product hands it (`tiered-support.md`
// §5.4). Read evidence, usage and transport shapes live beside their implementations.

/// Whether a product is open, as the user would judge it (``AgentPresence``).
protocol ProductPresenceReporting: Sendable {
    func presence() async -> AgentPresence
}

/// A desktop product's presence: whether an application with one of these bundle identifiers is
/// running. Never `unknown`. Returns the pid too, so hook evidence bound to it (CR-Fable-007) and
/// presence come from the same look.
struct RunningApplicationPresence: ProductPresenceReporting {
    private let runningProcessIdentifier: @MainActor @Sendable () -> pid_t?

    init(bundleIdentifiers: [String]) {
        runningProcessIdentifier = {
            Self.runningProcessIdentifier(bundleIdentifiers: bundleIdentifiers)
        }
    }

    /// For tests that must not depend on what is open on the machine.
    init(processIdentifier: @escaping @MainActor @Sendable () -> pid_t?) {
        runningProcessIdentifier = processIdentifier
    }

    func processIdentifier() async -> pid_t? {
        await runningProcessIdentifier()
    }

    func presence() async -> AgentPresence {
        Self.presence(of: await processIdentifier())
    }

    nonisolated static func presence(of processIdentifier: pid_t?) -> AgentPresence {
        processIdentifier == nil ? .closed : .open
    }

    /// The first live process with one of these bundle identifiers. Terminated instances are
    /// skipped: the workspace lists an app for a moment after it quits.
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

/// Which observed Threads the product still vouches for (ADR 0017): the only way a Turn is
/// retired because its Thread has gone.
enum ThreadAdmission: Sendable, Equatable {
    /// The product keeps no list this app can ask; Threads stay until their own exits apply.
    case everyObservedThread
    /// Exactly these Threads exist, per a read started at `readAt`. An absent Thread's Turn is
    /// retired only if its last event predates `readAt`.
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

/// One reading of a product's own list: presence, admitted Threads, and why it is unwatchable.
nonisolated struct SessionReading: Sendable, Equatable {
    let presence: AgentPresence
    let admission: ThreadAdmission
    /// A sentence the user can act on while presence is `unknown`; nil for the generic one.
    let unwatchableReason: String?

    init(presence: AgentPresence, admission: ThreadAdmission, unwatchableReason: String? = nil) {
        self.presence = presence
        self.admission = admission
        self.unwatchableReason = unwatchableReason
    }
}

/// A product's presence and admission, read together once per refresh so both come from one
/// list (two reads could straddle a change). Separate sources use ``SeparateSessionReading``.
protocol ProductSessionReading: Sendable {
    /// One reading for this refresh.
    ///
    /// - Parameter state: The Turns the reducer holds after the drain, for a product whose list can
    ///   be shown to be behind them.
    func read(observing state: MonitoringStateSnapshot) async -> SessionReading
    /// Nothing is being monitored: stop any watcher on the product's own records.
    func stopWatching() async
}

/// Presence and admission from two sources that need not agree on an instant.
struct SeparateSessionReading: ProductSessionReading {
    let presence: any ProductPresenceReporting
    let admission: any ThreadAdmitting

    func read(observing state: MonitoringStateSnapshot) async -> SessionReading {
        SessionReading(presence: await presence.presence(), admission: await admission.admission())
    }

    func stopWatching() async {}
}

/// Evidence about a held Turn that is not a hook event: a recorded interrupt, a dialog answered
/// in the product's window, the Turn a thread's record names (ADR 0011).
///
/// It hands facts to the reducer and decides nothing: a source may end a Turn, close a wait or
/// settle which Turn a thread is on, never open, name or describe one.
protocol TurnEvidenceSource: Sendable {
    /// Ordered readings, so a record-confirmed held start applies before termination is asked.
    /// Sources receive values, never a reducer.
    nonisolated var phases: [TurnEvidencePhase] { get }
    func observations(in state: MonitoringStateSnapshot, phase: TurnEvidencePhase) async -> TurnEvidenceBatch
    /// Points watchers at the records of Turns still open after the refresh, so a Turn just ended
    /// stops being watched in the same pass.
    func watch(openTurnsIn state: MonitoringStateSnapshot) async
    func stopWatching() async
}

extension MonitoringRepository {
    /// Holds the Turns to the Threads a product vouches for (ADR 0017). Only an exact list retires,
    /// and only Turns whose last event predates the reading.
    func applying(_ admission: ThreadAdmission, to state: MonitoringStateSnapshot) -> MonitoringStateSnapshot {
        guard case let .exactly(threadIDs, readAt) = admission else { return state }
        return removeThreads(notIn: threadIDs, snapshotStartedAt: readAt)
    }
}

nonisolated struct RowContent: Sendable, Equatable {
    let projectName: String
    let title: String
    let preview: String?
}

/// A product's project, title and line for each Turn, and whether a Turn draws a row at all;
/// everything else on a row is the reducer's.
protocol RowContentSource: Sendable {
    /// Content for each Turn that draws a row, keyed by Thread. A Turn with no entry draws none.
    func content(
        for turns: [MonitoredTurnState],
        messages: TurnMessageReading
    ) async -> [String: RowContent]
    /// Finished Turns whose rows are over, Thread to Turn: read, or removed by the user. Nothing
    /// draws them again, so content kept for a later refresh can go.
    func releaseEndedRows(_ turnIDsByThread: [String: String]) async
}

extension RowContentSource {
    func releaseEndedRows(_ turnIDsByThread: [String: String]) async {}
}

/// The L2 context fallback: directory name for project, prompt for title, closing words or newest
/// message for line.
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
                        // Empty falls back to ``RowContentFallback/title`` in ``MonitoredSession/init``.
                        title: turn.promptPreview ?? "",
                        // Unlike Claude Code's row, not the prompt: it is already the title.
                        preview: turn.assistantPreview
                            ?? messages.preview(forSession: turn.threadID, inTurn: turn.turnID)
                    )
                )
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The submission directory's last component (`tech-design.md` §5); empty maps to
    /// ``RowContentFallback/projectName``.
    nonisolated static func projectName(forWorkingDirectory path: String?) -> String {
        let component = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        return component == "/" ? "" : component
    }
}

/// Shared source-driven monitoring runtime. Codex keeps its own App Server orchestration.
actor ProductMonitoringRuntime: AgentMonitoring, DiskFootprintReporting {
    nonisolated let agent: AgentKind
    nonisolated let stateChangeEvents: AsyncStream<Void>

    private let connectionMonitor: ProductConnectionMonitor?
    private let composition: MonitoringSourceComposition
    private var isObserving = false
    private var lifecycleRevision = 0
    private var lastSetupStatus: IntegrationSetupStatus?
    private let lifecycle: any MonitoringLifecycleSource
    private let sessions: any ProductSessionReading
    private let turnEvidence: [any TurnEvidenceSource]
    private let rowContent: any RowContentSource
    private let readEvidence: (any ReadEvidenceSource)?
    private let usage: (any UsageReading)?
    private let footprint: (any DiskFootprintReporting)?
    /// Keeps a finished row listed until it has been read, and retires it the moment it has been.
    private var readGate: TerminalUnreadRowFilter
    private let clock: any MonitorClock

    init(
        agent: AgentKind,
        connectionMonitor: ProductConnectionMonitor? = nil,
        lifecycle: any MonitoringLifecycleSource,
        sessions: any ProductSessionReading,
        turnEvidence: [any TurnEvidenceSource] = [],
        rowContent: any RowContentSource = WorkingDirectoryRowContent(),
        /// Without one, a finished row stays until the Thread's next submission, its departure from the
        /// admission list or a right-click.
        readEvidence: (any ReadEvidenceSource)? = nil,
        /// Its reads land on an edge the composer merges into `changeEvents`.
        usage: (any UsageReading)? = nil,
        footprint: (any DiskFootprintReporting)? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard,
        changeEvents: [AsyncStream<Void>] = []
    ) {
        self.connectionMonitor = connectionMonitor
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
                + (connectionMonitor.map { [$0.changes.events()] } ?? [])
                // Screen wake/unlock: a row waiting to be read books no re-check without a visible screen, so
                // this edge restarts the re-checks.
                + (readEvidence.map { [$0.screen.changeEvents()] } ?? [])
        )
    }

    func recheckConnection() async { await connectionMonitor?.invalidate() }

    func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot {
        let snapshot = await fetchMonitoringSnapshot(dismissedRowIDs: dismissedRowIDs)
        let revision = lifecycleRevision
        let checked = await connectionMonitor?.inspect(snapshot) ?? snapshot
        guard revision == lifecycleRevision else { return stoppedSnapshot() }
        return checked
    }

    private func fetchMonitoringSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot {
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
            // Stop watchers and the read gate: otherwise a descriptor stays open, re-checks run every
            // second for invisible rows, and a session seen then would come back still claiming it.
            lifecycle.disconnect()
            if availability == .setupRequired {
                await lifecycle.repository.resetIntegrationObservation(clearTurns: true)
            }
            await stopEverything(keepingReadAmong: heldRowIDs(in: await lifecycle.repository.observedState()))
            return snapshot(
                availability: availability,
                sessions: [],
                setupStatus: closedStatus,
                diagnostic: diagnostic,
                // Limits exist whether or not hooks are registered; they are just not read.
                quota: usage == nil ? .noneReported : .unavailable,
                // These branches did not look at the product's list, so presence is `unknown`.
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
        // After the reduction, so a Turn just ended stops being watched in the same pass.
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
                // Later of the Turn's last event and the last subagent boundary; the settling window only.
                terminalBoundaryAt: turn.terminalBoundaryAt
            )
        }

        var rows: [MonitoredSession] = []
        var readDiagnostic: String?
        // A Turn with no content this refresh is still the Turn that was read.
        let held = heldRowIDs(in: state)
        if presence == .closed {
            readGate.reset(keepingReadAmong: held)
            await readEvidence?.forget()
        } else {
            // Judged even while presence is `unknown`, then withheld: an unreadable list is not evidence a
            // session ended, and a row hidden for being read must not return (CC-024).
            (rows, readDiagnostic) = await rowsStillWorthShowing(
                candidates,
                dismissedRowIDs: dismissedRowIDs,
                heldRowIDs: held
            )
            // A candidate the gate did not return was hidden as read; a removed one is returned.
            let returned = Set(rows.map(\.id))
            let ended = candidates.map(\.row).filter {
                MonitorAggregation.effectiveStatus(of: $0) == .completed
                    && (dismissedRowIDs.contains($0.id) || !returned.contains($0.id))
            }
            if !ended.isEmpty {
                await rowContent.releaseEndedRows(
                    Dictionary(ended.map { ($0.threadID, $0.turnID) }, uniquingKeysWith: { first, _ in first })
                )
            }
        }
        // Live text is kept for Threads the product lists (row or not) and for rows built rather than
        // shown, so a withheld row keeps its words; the kept set also lets a later message wake the
        // panel (``TurnPreviewStore/fold``).
        guard revision == lifecycleRevision else {
            if !isObserving {
                readGate.reset(keepingReadAmong: heldRowIDs(in: await lifecycle.repository.observedState()))
                await readEvidence?.forget()
            }
            return stoppedSnapshot()
        }
        var retainedThreadIDs = Set(candidates.map(\.row.threadID))
        if case let .exactly(listed, _) = reading.admission {
            retainedThreadIDs.formUnion(listed)
        }
        lifecycle.repository.retainPreviews(
            forSessions: presence == .closed ? [] : retainedThreadIDs
        )

        // Unknown presence is reported as unwatchable: claiming Connected while drawing nothing is the
        // guess PRD §12 forbids.
        let unwatchable: String? = presence == .unknown
            ? reading.unwatchableReason
                ?? "\(agent.displayName) is registered, but this app cannot tell whether it is open."
            : nil
        // Not awaited, so a hook event's row never waits on the read.
        await usage?.readIfStale()
        let diagnostic = MonitorDiagnostics.combined(unwatchable, state.diagnostic, readDiagnostic,
            await composition.diagnostic(), await usage?.quotaDiagnostic())
        let quota = await usage?.currentQuota() ?? .noneReported
        guard revision == lifecycleRevision else { return stoppedSnapshot() }
        return snapshot(
            availability: unwatchable == nil ? .ready : .disconnected,
            // A product that is not open contributes no rows: the surface reads rows before presence, so a
            // stale last reading left a `Running` row after the product's mark had gone.
            sessions: presence.isOpen ? rows : [],
            setupStatus: status,
            diagnostic: diagnostic,
            quota: quota,
            // Not "has rows": an open product with nothing in flight is still open.
            presence: presence
        )
    }

    /// - Parameter heldRowIDs: Turns the reducer keeps through the stop; their read verdicts stay.
    private func stopEverything(keepingReadAmong heldRowIDs: Set<String> = []) async {
        lifecycleRevision += 1
        isObserving = false
        await composition.stop()
        readGate.reset(keepingReadAmong: heldRowIDs)
        await readEvidence?.forget()
        await sessions.stopWatching()
        for source in turnEvidence {
            await source.stopWatching()
        }
    }

    /// The rows to list, minus finished ones the user has read. Rows are withheld only on read
    /// evidence from a ``ReadEvidenceSource``; no reading happens unless a finished, undismissed row
    /// is listed (CR-Fable-041, CR-Fable-003).
    private func rowsStillWorthShowing(
        _ candidates: [ReadGateCandidate],
        dismissedRowIDs: Set<String>,
        heldRowIDs: Set<String>
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
            let rows = readGate.rows(candidates, dismissedRowIDs: dismissedRowIDs, now: now,
                                     heldRowIDs: heldRowIDs) { _ in
                .cannotBeAsked
            }
            return (rows, nil)
        }
        let judgement = await readEvidence.verdicts(
            for: candidates.filter { !dismissedRowIDs.contains($0.row.id) },
            now: now
        )
        let rows = readGate.rows(candidates, dismissedRowIDs: dismissedRowIDs, now: now,
                                 heldRowIDs: heldRowIDs) {
            judgement.verdicts[$0.row.id] ?? .cannotBeAsked
        }
        // A list with nothing to judge says nothing about readings it did not take.
        return (rows, judgement.diagnostic)
    }

    /// Every timed source's next moment: the usage reader's next read and a finished row waiting to
    /// be read. A deadline a refresh could not advance would be a busy-wait.
    ///
    /// Unread rows need re-checks because some evidence (a terminal's access time, the front
    /// application) moves with nothing to watch. No cost while no such row is listed or no one can
    /// see the screen.
    func nextRefreshDeadline() async -> Date? {
        let connectionDeadline = await connectionMonitor?.nextDeadline()
        guard isObserving else { return connectionDeadline }
        return [
            connectionDeadline,
            await composition.nextDeadline(),
            // A held answer window expiring: that refresh turns the mark from `Answer` to `Read`.
            lifecycle.repository.nextAnswerExpiry(),
            await usage?.nextReadDeadline(),
            readEvidence.flatMap {
                readGate.nextDeadline(now: clock.now(), screenIsAvailable: $0.screen.isAvailable())
            }
        ]
        .compactMap { $0 }
        .min()
    }

    func diskFootprint() async -> AgentDiskFootprintReport {
        await footprint?.diskFootprint() ?? .leavesNothing
    }

    func disconnect() async {
        lifecycleRevision += 1
        await connectionMonitor?.reset()
        isObserving = false
        lifecycle.disconnect()
        await lifecycle.repository.resetIntegrationObservation(clearTurns: true, preserveBoundaryObservation: true)
        await stopEverything()
    }

    private func stoppedSnapshot() -> AgentSnapshot {
        snapshot(availability: .disconnected, sessions: [], setupStatus: lastSetupStatus,
                 diagnostic: nil, quota: usage == nil ? .noneReported : .unavailable, presence: .unknown)
    }

    private func heldRowIDs(in state: MonitoringStateSnapshot) -> Set<String> {
        Set(state.turns.map { MonitoredSession.id(agent: agent, threadID: $0.threadID, turnID: $0.turnID) })
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
            // A Turn can end with work it started still in flight.
            runningSubagentCount: turn.runningSubagentIDs.count,
            subagentsAwaitingApprovalCount: turn.subagentsAwaitingApprovalCount,
            // A Turn that stopped to wait is not a finished thread.
            isPausedForBackgroundWork: turn.pausedForBackgroundWork,
            // `lastEventAt` is the Turn's own last moment, held against a subagent's chatter.
            finishedAt: turn.status == .completed ? turn.lastEventAt : nil,
            requests: turn.requestsAwaitingAnAnswer
        )
    }

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
            // No usage reader means no quota, not an unreadable one (`quota-footer-v2.md` §5).
            quota: quota,
            diagnostic: diagnostic,
            setupStatus: setupStatus ?? .notRequired,
            presence: presence
        )
    }
}
