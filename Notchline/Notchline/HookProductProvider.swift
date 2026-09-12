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

/// One hook-based product's Provider: setup, transport, the shared reducer and
/// a row per Turn, with presence and admission supplied by the product.
///
/// What the row can say is decided by the vocabulary handed in. A vocabulary
/// that maps only a start and an end gives Tier 0: rows appear on submission,
/// show the elapsed time, turn `Completed` on the end event and name their work
/// by the submission directory's last component. A vocabulary that maps wait
/// events gives Tier 1, and one with an `answering` encoding and a definition
/// carrying the answering argument gives Tier 2 — nothing here changes between
/// them.
///
/// **What this deliberately does not do.** No quota, no interruption evidence
/// beyond what the hooks say, no title beyond the prompt. Each of those is a
/// capability a product adds beside this, not a flag on it.
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
    private let presence: any ProductPresenceReporting
    private let admission: any ThreadAdmitting
    /// What the terminal a Thread runs in says about the user having read its
    /// finished answer, or nil for a product that supplies no such evidence.
    private let readEvidence: TerminalReadEvidence?
    /// Keeps a finished row listed until it has been read, and retires it the
    /// moment it has been.
    ///
    /// The same filter both shipping products use, given the same shape of
    /// answer: the verdicts are computed per refresh from readings taken in
    /// that refresh, so the unread set handed over is always current.
    private var readGate: TerminalUnreadRowFilter
    private let clock: any MonitorClock

    init(
        agent: AgentKind,
        paths: HookIntegrationPaths,
        vocabulary: any AgentHookVocabulary,
        presence: any ProductPresenceReporting,
        admission: any ThreadAdmitting = AdmitsEveryObservedThread(),
        /// What retires a finished row once it has been read. A terminal
        /// product supplies it by naming the process each Thread runs in; a
        /// product that supplies none keeps a finished row until the Thread's
        /// next submission, its departure from the admission list or a
        /// right-click.
        readEvidence: TerminalReadEvidence? = nil,
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
        self.presence = presence
        self.admission = admission
        self.readEvidence = readEvidence
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
            return snapshot(
                availability: availability,
                sessions: [],
                setupStatus: closedStatus,
                diagnostic: diagnostic,
                presence: .unknown
            )
        }

        var state = await hooks.repository.drainDeliveredEvents()
        let presence = await presence.presence()
        switch await admission.admission() {
        case let .exactly(threadIDs, readAt):
            state = await hooks.repository.removeThreads(notIn: threadIDs, snapshotStartedAt: readAt)
        case .everyObservedThread, .unknown:
            break
        }

        // Presence unknown is the one state this skeleton reports as
        // unwatchable: the product may be open and busy, and drawing nothing
        // while claiming Connected would be the guess PRD §12 forbids.
        let unwatchable: String? = presence == .unknown
            ? "\(agent.displayName) is registered, but this app cannot tell whether it is open."
            : nil
        var rows: [MonitoredSession] = []
        if presence.isOpen {
            rows = await rowsStillWorthShowing(
                state.turns,
                dismissedRowIDs: dismissedRowIDs
            )
        } else {
            readGate.reset()
        }
        // Live text for a Thread this refresh does not list is pruned, and the
        // listed set is also what lets a message arriving later wake the panel
        // (``HookSessionPreviewStore/fold``). Held to the Turns the reducer
        // holds rather than to the rows drawn, so a row the read gate withheld
        // keeps its words for the next refresh that asks.
        hooks.repository.retainPreviews(
            forSessions: presence.isOpen ? Set(state.turns.map(\.threadID)) : []
        )
        return snapshot(
            availability: unwatchable == nil ? .ready : .disconnected,
            sessions: rows,
            setupStatus: status,
            diagnostic: MonitorDiagnostics.combined(unwatchable, state.diagnostic),
            presence: presence
        )
    }

    /// The rows to list, with a finished one the user has already read taken
    /// off.
    ///
    /// **A row is withheld only on evidence that somebody read it**, and only a
    /// product that supplied ``TerminalReadEvidence`` has any: with none, every
    /// row the reducer holds is listed and the gate is never consulted.
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
    ) async -> [MonitoredSession] {
        let candidates = turns.map { turn in
            ReadGateCandidate(
                row: row(for: turn),
                turnEndedAt: turn.turnEndedAt,
                terminalBoundaryAt: turn.terminalBoundaryAt
            )
        }
        guard let readEvidence else {
            return candidates.map(\.row).sorted(by: MonitorAggregation.rowOrder)
        }
        var verdicts: [String: ReadGateVerdict] = [:]
        let now = clock.now()
        if TerminalUnreadRowFilter.needsReadEvidence(
            candidates.map(\.row),
            dismissedRowIDs: dismissedRowIDs
        ) {
            for candidate in candidates where !dismissedRowIDs.contains(candidate.row.id) {
                // A thread still working goes to the gate without a reading:
                // the gate shows it outright and drops its entry, whatever a
                // reading would have said.
                guard TerminalUnreadMembershipGate.isTerminal(
                    MonitorAggregation.effectiveStatus(of: candidate.row)
                ) else {
                    continue
                }
                switch await readEvidence.verdict(
                    forThreadID: candidate.row.threadID,
                    turnEndedAt: candidate.turnEndedAt
                ) {
                case .cannotBeAsked:
                    verdicts[candidate.row.id] = .cannotBeAsked
                case .read:
                    verdicts[candidate.row.id] = .judged(by: Self.terminalReading([], now: now))
                case .unread:
                    verdicts[candidate.row.id] = .judged(
                        by: Self.terminalReading([candidate.row.threadID], now: now)
                    )
                }
            }
        }
        return readGate.rows(candidates, dismissedRowIDs: dismissedRowIDs, now: now) {
            verdicts[$0.row.id] ?? .judged(by: Self.terminalReading([], now: now))
        }
    }

    /// A terminal verdict as the gate reads one: authoritative and current by
    /// construction, because it was computed in this refresh from a kernel
    /// reading that cannot be a generation behind. A reading that failed
    /// answered `cannotBeAsked` and took its row out of the gate rather than
    /// into it with a stale verdict.
    nonisolated private static func terminalReading(
        _ unreadThreadIDs: Set<String>,
        now: Date
    ) -> DesktopUnreadStateSnapshot {
        DesktopUnreadStateSnapshot(
            unreadThreadIDs: unreadThreadIDs,
            source: .current,
            currentAsOf: now
        )
    }

    /// Nothing timed but a finished row waiting to be read: the reducer's edges
    /// and the store's heartbeat are the only other reasons to ask again, and a
    /// product with a timed source of its own composes it beside this Provider.
    ///
    /// That row waits on the user rather than on time, so its deadline is a
    /// floor under the edges — and the access time it is waiting for moves in
    /// the kernel with nothing to watch it, so it can only be asked at a
    /// re-check. It costs nothing while no such row is listed, and nothing at
    /// all while the screen is one nobody could read it on.
    func nextRefreshDeadline() async -> Date? {
        guard let readEvidence else { return nil }
        return readGate.nextDeadline(
            now: clock.now(),
            screenIsAvailable: readEvidence.screen.isAvailable()
        )
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
        presence: AgentPresence
    ) -> AgentSnapshot {
        AgentSnapshot(
            agent: agent,
            availability: availability,
            sessions: sessions,
            // No quota, rather than a quota that could not be read: this
            // Provider reads none and no product built on it has claimed one,
            // so its footer group is a name and a spend with no lines under
            // it (`quota-footer-v2.md` §5). A product that adds a quota
            // reading beside this composes it and publishes its own windows.
            quota: .noneReported,
            diagnostic: diagnostic,
            setupStatus: setupStatus,
            presence: presence
        )
    }
}
