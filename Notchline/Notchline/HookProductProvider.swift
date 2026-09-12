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
/// own machine (``AgentPresence``). Codex reads the running-application list;
/// Claude Code reads its own session list, with a trust ceiling.
protocol ProductPresenceReporting: Sendable {
    func presence() async -> AgentPresence
}

/// A desktop product's presence: is an application with one of these bundle
/// identifiers running. A kernel fact, so never `unknown`.
struct RunningApplicationPresence: ProductPresenceReporting {
    let bundleIdentifiers: [String]

    func presence() async -> AgentPresence {
        let identifiers = bundleIdentifiers
        let isOpen = await MainActor.run {
            identifiers.contains { identifier in
                !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty
            }
        }
        return isOpen ? .open : .closed
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
    /// The same gate both shipping products use, given the same shape of
    /// answer: the verdicts are computed per refresh from readings taken in
    /// that refresh, so the unread set handed over is always current.
    private var readGate: TerminalUnreadMembershipGate
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
        self.readGate = TerminalUnreadMembershipGate(
            settlingInterval: timing.terminalReadSettlingInterval,
            unreadRecheckInterval: timing.terminalUnreadRecheckInterval
        )
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
        let status = await hooks.setupStatus()
        guard status == .active else {
            // Nothing is listed, so nothing is waiting to be read. Left
            // standing, the gate's entries would go on booking a re-check a
            // second for rows nobody can see.
            readGate.reset()
            return snapshot(
                availability: .setupRequired,
                sessions: [],
                setupStatus: status,
                diagnostic: status == .repairRequired
                    ? "The \(agent.displayName) hook registration is not what this "
                        + "version writes; turn its switch on in Settings to rewrite it."
                    : "The \(agent.displayName) integration is not registered yet.",
                presence: .unknown
            )
        }
        guard await hooks.prepareTransport() else {
            readGate.reset()
            return snapshot(
                availability: .disconnected,
                sessions: [],
                setupStatus: status,
                diagnostic: "Cannot open the hook helper or bind its socket in this "
                    + "app's support folder. Either the folder is not writable, or "
                    + "another copy of this app is already running and receiving the "
                    + "events — only one copy can.",
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
    /// The shape is the Claude Code service's, minus the four routes that go
    /// through Claude Desktop, and the departures from it are the two costs
    /// that service pays for and this one must not pay twice:
    ///
    /// - **No reading at all happens unless a finished row is listed.** Every
    ///   row in a list of running rows would be shown outright and drop its
    ///   gate entry, so the whole pass collapses to emptying the gate
    ///   (CR-Fable-041).
    /// - **A row the user has waved away is judged by nobody.** It has already
    ///   left the list at their asking, so no reading can add anything to it —
    ///   and an entry in the gate books a re-check a second whether or not the
    ///   row is on the notch (CR-Fable-003). It is still *reported*: what this
    ///   product lists is what it knows about, and a Provider that stopped
    ///   listing the Turn would be telling the store the Turn had ended.
    private func rowsStillWorthShowing(
        _ turns: [HookTurnState],
        dismissedRowIDs: Set<String>
    ) async -> [MonitoredSession] {
        let built = turns.map { (row: row(for: $0), turn: $0) }
        func listed() -> [MonitoredSession] {
            built.map(\.row).sorted(by: MonitorAggregation.rowOrder)
        }
        guard let readEvidence else { return listed() }
        guard built.contains(where: {
            TerminalUnreadMembershipGate
                .isTerminal(MonitorAggregation.effectiveStatus(of: $0.row))
                && !dismissedRowIDs.contains($0.row.id)
        }) else {
            readGate.reset()
            return listed()
        }

        let now = clock.now()
        var shown: [MonitoredSession] = []
        var judged: [(row: MonitoredSession, turn: HookTurnState)] = []
        var unreadThreadIDs: Set<String> = []
        for (row, turn) in built {
            guard !dismissedRowIDs.contains(row.id) else {
                shown.append(row)
                continue
            }
            // The gate is asked whether this *thread* is still working rather
            // than what the row says, so a finished Turn with a subagent still
            // in flight takes the running path — shown outright, entry
            // dropped — and the one row carrying the evidence that anything is
            // still running cannot be erased a settling interval after an end
            // the user has already read.
            let status = MonitorAggregation.effectiveStatus(of: row)
            guard TerminalUnreadMembershipGate.isTerminal(status) else {
                judged.append((row, turn))
                continue
            }
            switch await readEvidence.verdict(
                forThreadID: row.threadID,
                turnEndedAt: turn.turnEndedAt
            ) {
            case .cannotBeAsked:
                // No terminal, or one whose host can never hold the front.
                // Kept out of the gate rather than reported unread, so it books
                // no re-check for a question with no possible answer: such a
                // row leaves the way a Tier 0 row always did, on the next
                // submission, when the Thread goes away, or when the user
                // removes it.
                shown.append(row)
            case .read:
                judged.append((row, turn))
            case .unread:
                unreadThreadIDs.insert(row.threadID)
                judged.append((row, turn))
            }
        }
        // Authoritative and current by construction: every verdict above was
        // computed in this call, from a kernel reading that cannot be a
        // generation behind. A reading that failed answered `cannotBeAsked` and
        // took its row out of the gate rather than into it with a stale
        // verdict.
        let unreadState = DesktopUnreadStateSnapshot(
            unreadThreadIDs: unreadThreadIDs,
            source: .current,
            currentAsOf: now
        )
        for (row, turn) in judged where readGate.shouldDisplay(
            sessionID: row.id,
            threadID: row.threadID,
            status: MonitorAggregation.effectiveStatus(of: row),
            turnEndedAt: turn.turnEndedAt,
            terminalBoundaryAt: turn.terminalBoundaryAt,
            unreadState: unreadState,
            now: now
        ) {
            shown.append(row)
        }
        readGate.retain(sessionIDs: Set(judged.map(\.row.id)))
        return shown.sorted(by: MonitorAggregation.rowOrder)
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
