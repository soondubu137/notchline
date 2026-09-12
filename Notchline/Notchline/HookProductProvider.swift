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
/// **What this deliberately does not do.** No read state: a `Completed` row
/// stays until the Thread's next submission, its disappearance from the
/// admission list, or a right-click, which is the lifecycle `CONTEXT.md`
/// defines for a Turn whose read state cannot be asked about. No quota, no
/// interruption evidence beyond what the hooks say, no title beyond the
/// prompt. Each of those is a capability a product adds beside this, not a
/// flag on it.
actor HookProductProvider: AgentMonitoring, IntegrationConfiguring, AnswerDelivering {
    nonisolated let agent: AgentKind
    nonisolated let stateChangeEvents: AsyncStream<Void>

    private let hooks: HookLifecycleSource
    private let presence: any ProductPresenceReporting
    private let admission: any ThreadAdmitting

    init(
        agent: AgentKind,
        paths: HookIntegrationPaths,
        vocabulary: any AgentHookVocabulary,
        presence: any ProductPresenceReporting,
        admission: any ThreadAdmitting = AdmitsEveryObservedThread(),
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
        self.stateChangeEvents = DirectoryChangeWatcher.merged(
            [hooks.changeEvents()] + changeEvents
        )
    }

    /// The reducer, for a test that hands payloads over without a socket.
    nonisolated var repository: HookEventRepository { hooks.repository }

    func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot {
        let status = await hooks.setupStatus()
        guard status == .active else {
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
        let rows = state.turns
            .map(row(for:))
            .sorted(by: MonitorAggregation.rowOrder)
        return snapshot(
            availability: unwatchable == nil ? .ready : .disconnected,
            sessions: presence.isOpen ? rows : [],
            setupStatus: status,
            diagnostic: MonitorDiagnostics.combined(unwatchable, state.diagnostic),
            presence: presence
        )
    }

    /// Nothing timed: the reducer's edges and the store's heartbeat are the
    /// only reasons to ask again. A product with a timed source of its own
    /// composes it beside this Provider.
    func nextRefreshDeadline() async -> Date? { nil }

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
            preview: turn.assistantPreview,
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
            quota: .unavailable,
            diagnostic: diagnostic,
            setupStatus: setupStatus,
            presence: presence
        )
    }
}
