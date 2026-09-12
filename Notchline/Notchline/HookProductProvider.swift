import AppKit
import Foundation

// The Provider a hook-based product gets by default, and the two facts it has
// to supply from outside the hooks: whether the product is open, and which of
// the Threads the hooks name the product vouches for. Everything else a Tier 0
// row needs — setup, the helper and its socket, the reducer, the row built from
// a Turn — is here once. This is the destination `tiered-support.md` §5.4
// describes; the two shipping products still run their own actors, which carry
// the product-specific evidence (read state, interruption, Project, quota)
// this skeleton does not yet have seams for.

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

/// Which of the Threads the hooks have named the product still vouches for
/// (ADR 0017): the answer that lets a Turn be retired because its Thread has
/// gone, and the only thing that may retire one this way.
enum ThreadAdmission: Sendable, Equatable {
    /// The product keeps no list this app can ask. Every Thread a live hook
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
    func read(observing state: HookStateSnapshot) async -> SessionReading
    /// Nothing is being monitored: stop any watcher the readings pointed at
    /// the product's own records.
    func stopWatching() async
}

/// Presence and admission answered by two sources that need not agree on an
/// instant — a running-application list and "every observed Thread", say.
struct SeparateSessionReading: ProductSessionReading {
    let presence: any ProductPresenceReporting
    let admission: any ThreadAdmitting

    func read(observing state: HookStateSnapshot) async -> SessionReading {
        SessionReading(presence: await presence.presence(), admission: await admission.admission())
    }

    func stopWatching() async {}
}

extension HookEventRepository {
    /// Holds the Turns to the Threads a product vouches for (ADR 0017).
    ///
    /// Only an exact list retires anything, and only a Turn whose last event
    /// predates the reading: a list that could not be read, or a product with
    /// no list, retires nothing on a failure to ask.
    func applying(_ admission: ThreadAdmission, to state: HookStateSnapshot) -> HookStateSnapshot {
        guard case let .exactly(threadIDs, readAt) = admission else { return state }
        return removeThreads(notIn: threadIDs, snapshotStartedAt: readAt)
    }
}

/// One hook-based product's Provider: setup, transport, the shared reducer and
/// a row per Turn, with presence and admission supplied by the product
/// (``ProductSessionReading``).
///
/// What the row can say is decided by the vocabulary handed in. A vocabulary
/// that maps only a start and an end gives Tier 0: rows appear on submission,
/// show the elapsed time, turn `Completed` on the end event and name their work
/// by the submission directory's last component. A vocabulary that maps wait
/// events gives Tier 1, and one with an `answering` encoding and a definition
/// carrying the answering argument gives Tier 2 — nothing here changes between
/// them.
///
/// **What this deliberately does not do.** No interruption evidence beyond
/// what the hooks say, no title beyond the prompt. Each of those is a
/// capability a product adds beside this, not a flag on it. A quota is one a
/// product hands in (``UsageReading``); with none, the footer draws the
/// product's name and no lines.
///
/// **Read state is the one of those capabilities this now composes**, because
/// for a terminal product it costs the product nothing: hand in
/// ``TerminalReadEvidence`` and a `Completed` row is retired once the user has
/// been at the terminal its Thread is running in. A product that hands in none
/// keeps the lifecycle `CONTEXT.md` defines for a Turn whose read state cannot
/// be asked about — the row stays until the Thread's next submission, its
/// disappearance from the admission list, or a right-click.
actor HookProductProvider: AgentMonitoring, IntegrationConfiguring, AnswerDelivering {
    nonisolated let agent: AgentKind
    nonisolated let stateChangeEvents: AsyncStream<Void>

    private let hooks: HookLifecycleSource
    private let sessions: any ProductSessionReading
    /// What the terminal a Thread runs in says about the user having read its
    /// finished answer, or nil for a product that supplies no such evidence.
    private let readEvidence: (any ReadEvidenceSource)?
    /// How much of the product's limits is left, or nil for a product that
    /// reports none (``UsageReading``).
    private let usage: (any UsageReading)?
    /// Keeps a finished row listed until it has been read, and retires it the
    /// moment it has been.
    ///
    /// The same filter both shipping products use, given the same shape of
    /// answer: the verdicts are computed per refresh from readings taken in
    /// that refresh, so the unread set handed over is always current.
    private var readGate: TerminalUnreadRowFilter
    private let clock: any MonitorClock

    /// A product whose presence and admission are two separate answers.
    init(
        agent: AgentKind,
        paths: HookIntegrationPaths,
        vocabulary: any AgentHookVocabulary,
        presence: any ProductPresenceReporting,
        admission: any ThreadAdmitting = AdmitsEveryObservedThread(),
        readEvidence: (any ReadEvidenceSource)? = nil,
        usage: (any UsageReading)? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard,
        fileManager: FileManager = .default,
        changeEvents: [AsyncStream<Void>] = []
    ) {
        self.init(
            agent: agent,
            paths: paths,
            vocabulary: vocabulary,
            sessions: SeparateSessionReading(presence: presence, admission: admission),
            readEvidence: readEvidence,
            usage: usage,
            clock: clock,
            timing: timing,
            fileManager: fileManager,
            changeEvents: changeEvents
        )
    }

    init(
        agent: AgentKind,
        paths: HookIntegrationPaths,
        vocabulary: any AgentHookVocabulary,
        /// Whether the product is open and which Threads it vouches for, read
        /// together once per refresh.
        sessions: any ProductSessionReading,
        /// What retires a finished row once it has been read. A terminal
        /// product supplies it by naming the process each Thread runs in; a
        /// product that supplies none keeps a finished row until the Thread's
        /// next submission, its departure from the admission list or a
        /// right-click.
        readEvidence: (any ReadEvidenceSource)? = nil,
        /// The product's quota, for one that reports limits. Its reads land on
        /// an edge the composer merges into `changeEvents`.
        usage: (any UsageReading)? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard,
        fileManager: FileManager = .default,
        /// Edges from the presence or admission source that mean "ask me
        /// again", merged with the reducer's own.
        changeEvents: [AsyncStream<Void>] = []
    ) {
        self.agent = agent
        let hooks = HookLifecycleSource(
            paths: paths,
            vocabulary: vocabulary,
            clock: clock,
            timing: timing,
            fileManager: fileManager
        )
        self.hooks = hooks
        self.sessions = sessions
        self.readEvidence = readEvidence
        self.usage = usage
        self.readGate = TerminalUnreadRowFilter(timing: timing)
        self.clock = clock
        self.stateChangeEvents = DirectoryChangeWatcher.merged(
            [hooks.changeEvents()] + changeEvents
                // The display waking or the screen unlocking. A row waiting to
                // be read books no re-check while neither is true, because the
                // only route that could retire it needs a screen somebody can
                // see; this is the edge that starts the re-checks again.
                + (readEvidence.map { [$0.screen.changeEvents()] } ?? [])
        )
    }

    /// The reducer, for a test that reads what landed.
    nonisolated var repository: HookEventRepository { hooks.repository }

    /// One payload as the product's helper would deliver it, for a test that
    /// hands payloads over without a socket — through the product's translator,
    /// exactly as the socket's arrive.
    @discardableResult
    nonisolated func deliver(_ body: Data, at receivedAt: Date) -> AgentHookListener.Disposition {
        hooks.deliver(body, at: receivedAt)
    }

    func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot {
        let status: IntegrationSetupStatus
        switch await hooks.gate(productName: agent.displayName) {
        case let .open(openStatus):
            status = openStatus
        case let .closed(availability, closedStatus, diagnostic):
            // Nothing is listed, so nothing is waiting to be read. Left
            // standing, the gate's entries would go on booking a re-check a
            // second for rows nobody can see.
            readGate.reset()
            await readEvidence?.forget()
            await sessions.stopWatching()
            return snapshot(
                availability: availability,
                sessions: [],
                setupStatus: closedStatus,
                diagnostic: diagnostic,
                // A product with limits has them whether or not its hooks are
                // registered; they are simply not being read.
                quota: usage == nil ? .noneReported : .unavailable,
                presence: .unknown
            )
        }

        var state = await hooks.repository.drainDeliveredEvents()
        let reading = await sessions.read(observing: state)
        let presence = reading.presence
        state = await hooks.repository.applying(reading.admission, to: state)

        // Presence unknown is the one state this skeleton reports as
        // unwatchable: the product may be open and busy, and drawing nothing
        // while claiming Connected would be the guess PRD §12 forbids.
        let unwatchable: String? = presence == .unknown
            ? reading.unwatchableReason
                ?? "\(agent.displayName) is registered, but this app cannot tell whether it is open."
            : nil
        var rows: [MonitoredSession] = []
        var readDiagnostic: String?
        if presence.isOpen {
            (rows, readDiagnostic) = await rowsStillWorthShowing(
                state.turns,
                dismissedRowIDs: dismissedRowIDs
            )
        } else {
            readGate.reset()
            await readEvidence?.forget()
        }
        // Live text for a Thread this refresh does not list is pruned, and the
        // listed set is also what lets a message arriving later wake the panel
        // (``HookSessionPreviewStore/fold``). Held to the Turns the reducer
        // holds rather than to the rows drawn, so a row the read gate withheld
        // keeps its words for the next refresh that asks.
        hooks.repository.retainPreviews(
            forSessions: presence.isOpen ? Set(state.turns.map(\.threadID)) : []
        )
        // Whatever is known right now, with a read started behind it. Awaiting
        // the read here would make a hook event's row wait on it.
        await usage?.readIfStale()
        return snapshot(
            availability: unwatchable == nil ? .ready : .disconnected,
            sessions: rows,
            setupStatus: status,
            diagnostic: MonitorDiagnostics.combined(
                unwatchable,
                state.diagnostic,
                readDiagnostic,
                // Last, because it is the least urgent: the rows are all there
                // and what is missing is the footer's lines.
                await usage?.quotaDiagnostic()
            ),
            quota: await usage?.currentQuota() ?? .noneReported,
            presence: presence
        )
    }

    /// The rows to list, with a finished one the user has already read taken
    /// off.
    ///
    /// **A row is withheld only on evidence that somebody read it**, and only a
    /// product that supplied a ``ReadEvidenceSource`` has any —
    /// ``TerminalReadEvidence`` for a CLI product: with none, every row the
    /// reducer holds is listed and the gate is never consulted.
    ///
    /// Which rows are judged at all, and how, is ``TerminalUnreadRowFilter``'s
    /// — the rules every Provider shares. What is this Provider's is only the
    /// verdict, and it is taken only for a row that could be withheld: no
    /// reading happens unless a finished row the user has not waved away is
    /// listed (CR-Fable-041, CR-Fable-003), and a row whose thread is still
    /// working is handed to the gate without one.
    private func rowsStillWorthShowing(
        _ turns: [HookTurnState],
        dismissedRowIDs: Set<String>
    ) async -> (rows: [MonitoredSession], diagnostic: String?) {
        let candidates = turns.map { turn in
            ReadGateCandidate(
                row: row(for: turn),
                turnEndedAt: turn.turnEndedAt,
                terminalBoundaryAt: turn.terminalBoundaryAt
            )
        }
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

    /// Two timed sources and nothing else: the usage reader's next read, and a
    /// finished row waiting to be read. The reducer's edges and the store's
    /// heartbeat are the only other reasons to ask again.
    ///
    /// That row waits on the user rather than on time, so its deadline is a
    /// floor under the edges — and the access time it is waiting for moves in
    /// the kernel with nothing to watch it, so it can only be asked at a
    /// re-check. It costs nothing while no such row is listed, and nothing at
    /// all while the screen is one nobody could read it on.
    func nextRefreshDeadline() async -> Date? {
        [
            await usage?.nextReadDeadline(),
            readEvidence.flatMap {
                readGate.nextDeadline(now: clock.now(), screenIsAvailable: $0.screen.isAvailable())
            }
        ]
        .compactMap { $0 }
        .min()
    }

    func disconnect() async {
        hooks.disconnect()
    }

    func answer(_ answer: AgentAnswer, on handle: AnswerHandle) async -> Bool {
        await hooks.answer(answer, on: handle)
    }

    func setupStatus() async -> IntegrationSetupStatus {
        await hooks.setupStatus()
    }

    func installIntegration() async throws {
        try await hooks.install()
    }

    func removeIntegration() async throws {
        try await hooks.remove()
    }

    private func row(for turn: HookTurnState) -> MonitoredSession {
        MonitoredSession(
            agent: agent,
            threadID: turn.threadID,
            turnID: turn.turnID,
            projectName: Self.projectName(forWorkingDirectory: turn.workingDirectory),
            title: turn.promptPreview ?? "Untitled",
            // The closing words once the Turn has ended with some, and until
            // then the newest message this Turn has said, for a product whose
            // vocabulary names a message event. The prompt is not the fallback
            // here, as it is on Claude Code's row: it is already the title.
            preview: turn.assistantPreview
                ?? hooks.repository.preview(forSession: turn.threadID, inTurn: turn.turnID),
            status: turn.status,
            startedAt: turn.startedAt,
            runningSubagentCount: turn.runningSubagentIDs.count,
            subagentsAwaitingApprovalCount: turn.subagentsAwaitingApprovalCount,
            isPausedForBackgroundWork: turn.pausedForBackgroundWork,
            finishedAt: turn.status == .completed ? turn.lastEventAt : nil,
            request: turn.requestAwaitingAnAnswer
        )
    }

    /// The submission directory's last component, which `tech-design.md` §5
    /// permits as a project name; `Untitled folder` when there is none.
    nonisolated static func projectName(forWorkingDirectory path: String?) -> String {
        let component = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        return component.isEmpty || component == "/" ? "Untitled folder" : component
    }

    private func snapshot(
        availability: MonitorAvailability,
        sessions: [MonitoredSession],
        setupStatus: IntegrationSetupStatus,
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
            setupStatus: setupStatus,
            presence: presence
        )
    }
}
