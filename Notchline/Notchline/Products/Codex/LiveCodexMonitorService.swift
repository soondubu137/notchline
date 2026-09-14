import Foundation

actor LiveCodexMonitorService: AgentMonitoring, IntegrationConfiguring, AnswerDelivering,
    DiskFootprintReporting, CodexNavigationTargetChecking {
    nonisolated let agent = AgentKind.codex

    /// - `observedAt` is the request start, so a Hook arriving mid-read still wins freshness.
    /// - `thread` nil means the App Server answered "no such thread", which stops re-asking.
    /// - A thread with no transcript is never asked and has no record
    ///   (``HookTurnState/threadHasNoTranscript``).
    private struct ThreadRecord: Sendable {
        let thread: JSONValue?
        let observedAt: Date

        var isAddressable: Bool { thread != nil }
    }

    /// `text` survives an empty read: newer items can push the turn's last words off the page.
    private struct TurnProgress: Sendable {
        let turnID: String
        var text: String?
        /// The issue stamp, not completion, so an event landing mid-read still counts as unread-for.
        var readAtEventStamp: Date
    }

    private struct TurnProgressRequest: Sendable {
        let turnID: String
        let eventStamp: Date
    }

    private let connectionMonitor: ProductConnectionMonitor?
    private var connectionRevision = 0
    private let clock: any MonitorClock
    private let timing: MonitorTiming
    private let client: any CodexAppServerCommunicating
    /// Codex's hook transport; reducer and registrar are also kept by name.
    private let hooks: HookLifecycleSource
    private let hookEvents: HookEventRepository
    private let hookActivation: CodexHookActivation
    private var hookActivationRetryAllowed = false
    private let hookRegistrar: CodexHookRegistrar
    private let projectMetadata: any DesktopProjectMetadataProviding
    private let unreadState: any DesktopUnreadStateProviding
    /// Which threads Codex answers approval requests for on the user's behalf. Decided here, not
    /// in the reducer, which cannot tell a reviewer-decided request from a human one.
    private let approvalRouting: any DesktopApprovalRoutingProviding
    /// The reviewer each running Turn was handed, from its rollout. Consulted ahead of
    /// `approvalRouting`, Desktop's copy, which lags a switch until Desktop persists it.
    private let turnReviewer: any TurnReviewerReading
    /// Rollout evidence no hook reports: which held Turn a thread is on, and user aborts.
    private let rolloutEvidence: CodexRolloutTurnEvidence
    /// The rollouts of still-running Turns only. Not private, for tests.
    nonisolated var rolloutWatcher: PathSetChangeWatcher {
        rolloutEvidence.rolloutWatcher
    }
    /// Whether there is a screen to read this app's output on. Gates the unread re-check
    /// (``TerminalUnreadMembershipGate/nextDeadline(now:screenIsAvailable:)``) and the account and
    /// quota reads (``CodexUsageReader/readIfStale()``).
    nonisolated private let screenAvailability: any ScreenAvailabilityReporting
    /// Account and quota, read over the App Server on their own clock (``UsageReading``).
    private let usage: CodexUsageReader
    nonisolated let stateChangeEvents: AsyncStream<Void>
    nonisolated private let snapshotInvalidations: AsyncStream<Void>.Continuation
    /// Whether Codex Desktop is running, and its pid, from one reading so hook evidence and
    /// presence describe the same instant (``RunningApplicationPresence``).
    private let presence: RunningApplicationPresence
    private var threadRecords: [String: ThreadRecord] = [:]
    /// The threads the metadata read revisits (Hook-tracked only); staleness over all of
    /// `threadRecords` would report a deadline no refresh can clear.
    private var hookTrackedThreadIDs: Set<String> = []
    private var listedThreadIDs: Set<String> = []
    private var threadListReadAt: Date?
    /// When `thread/list` last answered at all, separate from ``threadListReadAt``: the no-hook
    /// branch reads one row and must not mark membership fresh, or a truncated `listedThreadIDs`
    /// would retire live Hook Turns. A ceiling only; never published as a deadline.
    private var threadListAnsweredAt: Date?
    private var threadListGate = SingleFlightGate()
    private var threadListRefreshTask: Task<Void, Never>?
    private var threadListRetryAfter: Date?
    private var threadMetadataGate = SingleFlightGate()
    private var threadMetadataRefreshTask: Task<Void, Never>?
    private var threadMetadataRetryAfter: Date?
    private var pendingMetadataThreadIDs: Set<String> = []
    /// Threads a metadata read has been issued for, until it answers, so a re-entrant refresh
    /// does not queue the same read again (open mainly on a slow `thread/list`).
    private var inFlightMetadataThreadIDs: Set<String> = []

    /// The Turn each thread's path was last asked about. A Turn resumed after an interrupt gets a
    /// new rollout file, so a new Turn re-asks once
    /// (``scheduleThreadMetadataRefreshIfNeeded(for:)``).
    private var metadataReadTurnIDsByThreadID: [String: String] = [:]
    private var supportsThreadMetadataRead = true
    /// The newest thing each unfinished turn has said, by thread. Read, not received: no Codex
    /// hook carries assistant text before `Stop`/`SubagentStop` (CLI schemas, 0.149.0-alpha.4.3).
    private var turnProgressByThreadID: [String: TurnProgress] = [:]
    private var turnProgressGate = SingleFlightGate()
    private var turnProgressRefreshTask: Task<Void, Never>?
    private var turnProgressRetryAfter: Date?
    private var pendingProgressReads: [String: TurnProgressRequest] = [:]
    /// Turns a progress read has been issued for, by thread, until it answers. Without it,
    /// refreshes re-entrant with the `await` re-queued the same read (seen only under load).
    /// Only an identical question (same turn, same `lastEventAt`) is suppressed.
    private var inFlightProgressReads: [String: TurnProgressRequest] = [:]
    /// Threads that answered `thread/items/list` with "method not found". Per thread: Codex
    /// answers `-32601` for `historyMode` `legacy` threads while `paginated` ones work (measured
    /// 2026-08-25, CLI `0.149.0-alpha.4.3`).
    private var threadsWithoutItemsRead: Set<String> = []
    private var observedDesktopProcessIdentifier: pid_t?
    /// Cool-off after a failed connect; guards a subprocess. See ``connectToAppServer()``.
    private var connectRetryAfter: Date?
    /// Replayed for refreshes the cool-off turns away.
    private var lastConnectFailure: (any Error)?
    private var lastTrustedSnapshot: AgentSnapshot?
    private var observationStopped = false
    /// Keeps a finished row listed until Desktop no longer reports it unread
    /// (``TerminalUnreadRowFilter``).
    private var terminalUnreadMembershipGate: TerminalUnreadRowFilter
    /// The routing each live Turn started under; Desktop's current value stops describing a row
    /// once the reviewer changes mid-turn (``TurnApprovalRoutingPin``).
    private var approvalRoutingPin = TurnApprovalRoutingPin()

    init(
        client: any CodexAppServerCommunicating = CodexAppServerClient(),
        connectionMonitor: ProductConnectionMonitor? = nil,
        hookEvents: HookEventRepository = HookEventRepository(),
        hookRegistrar: CodexHookRegistrar = CodexHookRegistrar(),
        hookListener: AgentHookListener? = nil,
        projectMetadata: any DesktopProjectMetadataProviding =
            CodexDesktopProjectMetadataRepository(),
        unreadState: any DesktopUnreadStateProviding =
            CodexDesktopUnreadStateRepository(),
        approvalRouting: any DesktopApprovalRoutingProviding =
            CodexDesktopApprovalRoutingRepository(),
        turnReviewer: any TurnReviewerReading = CodexRolloutTurnReviewerReader(),
        turnAbort: any CodexTurnAbortReading & CodexTurnOnRecordReading =
            CodexRolloutTurnAbortReader(),
        screenAvailability: any ScreenAvailabilityReporting =
            ScreenAvailabilityWatcher(),
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard,
        desktopProcessIdentifierProvider: @escaping @MainActor @Sendable () -> pid_t? = {
            RunningApplicationPresence.runningProcessIdentifier(
                bundleIdentifiers: [CodexDesktopNavigator.desktopBundleIdentifier]
            )
        }
    ) {
        self.connectionMonitor = connectionMonitor
        self.clock = clock
        self.timing = timing
        self.client = client
        self.hookEvents = hookEvents
        self.hookRegistrar = hookRegistrar
        let hookActivation = CodexHookActivation(paths: hookRegistrar.integrationPaths, clock: clock)
        self.hookActivation = hookActivation
        // The transport belongs to this service, so the store stays a reducer with an inbox.
        // Delivery on the listener's serial read queue keeps arrival order.
        self.hooks = HookLifecycleSource(
            setup: hookRegistrar,
            repository: hookEvents,
            listener: hookListener,
            clock: clock
        )
        self.projectMetadata = projectMetadata
        self.unreadState = unreadState
        self.approvalRouting = approvalRouting
        self.turnReviewer = turnReviewer
        let rolloutEvidence = CodexRolloutTurnEvidence(turnAbort: turnAbort, timing: timing)
        self.rolloutEvidence = rolloutEvidence
        self.screenAvailability = screenAvailability
        // Background reads land after their snapshot was published, so they need their own trigger.
        let (invalidations, invalidationContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.snapshotInvalidations = invalidationContinuation
        self.usage = CodexUsageReader(
            client: client,
            clock: clock,
            timing: timing,
            screenAvailability: screenAvailability,
            onUpdate: { invalidationContinuation.yield(()) }
        )
        self.stateChangeEvents = DirectoryChangeWatcher.merged([
            // The store signals only when what a row draws changed, so a 17-event turn is one wake-up.
            // No debounce: it delayed the path a user watches.
            hookEvents.changeEvents(),
            // The registration changing: the user running `/hooks` or editing the file.
            hookRegistrar.changeEvents(),
            hookActivation.changeEvents(),
            unreadState.changeEvents(),
            // The screen returning re-arms re-checks booked off while locked, instead of waiting out
            // the heartbeat after an unlock.
            screenAvailability.changeEvents(),
            // A running Turn's rollout gaining a record: a signal only; the abort no hook reports is
            // what matters (``rolloutWatcher``).
            rolloutEvidence.rolloutWatcher.events(),
            invalidations
        ] + (connectionMonitor.map { [$0.changes.events()] } ?? []))
        self.terminalUnreadMembershipGate = TerminalUnreadRowFilter(timing: timing)
        self.presence = RunningApplicationPresence(
            processIdentifier: desktopProcessIdentifierProvider
        )
    }

    func recheckConnection() async {
        await hookRegistrar.invalidateRegistration()
        await hookActivation.invalidate()
        await connectionMonitor?.invalidate()
    }

    func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot {
        let revision = connectionRevision
        let snapshot = await fetchMonitoringSnapshot(dismissedRowIDs: dismissedRowIDs)
        let checked = await connectionMonitor?.inspect(snapshot) ?? snapshot
        guard revision == connectionRevision else {
            return AgentSnapshot(agent: .codex, availability: .disconnected, sessions: [], quota: .unavailable,
                                 diagnostic: nil, setupStatus: snapshot.setupStatus, presence: .unknown)
        }
        hookActivationRetryAllowed = checked.availability == .ready && checked.presence == .open
        return checked
    }

    private func fetchMonitoringSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot {
        observationStopped = false
        // Before the status gate: an already-running Codex fires trusted definitions immediately.
        await hooks.prepareTransport()
        // Branches that return without evaluating rows must reset the gate, or its entries re-issue
        // a 1 Hz re-check forever (CR-Fable-050). A `defer` over one flag so new branches are covered.
        var didEvaluateRows = false
        defer {
            if !didEvaluateRows {
                terminalUnreadMembershipGate.reset()
                // Likewise the rollout watches: a stale watch wakes a refresh that will not read it.
                rolloutWatcher.watch(paths: [])
            }
        }
        let desktopProcessIdentifier = await self.presence.processIdentifier()
        // A pid change retires the Turns the old process vouched for. Desktop dying mid-turn sends
        // no `Stop` and writes no `turn_aborted`, and its Running Turn returned on the relaunched
        // process's first event with nothing to clear it (CR-Fable-007; no activity-status read as
        // ADR 0011 gives Claude Code). Retired before the drain so new events cannot mix in.
        if let vouchingProcessIdentifier = observedDesktopProcessIdentifier,
           vouchingProcessIdentifier != desktopProcessIdentifier {
            await retireHookTurns()
        }
        var hookState = await hookEvents.drainDeliveredEvents()
        let hookDiagnostic = hookState.diagnostic
        if desktopProcessIdentifier == nil {
            // And after the drain while nothing runs: a dying process's helper can still deliver.
            hookState = await retireHookTurns(
                didConsumeEvents: hookState.didConsumeEvents
            )
        } else if hookState.didConsumeEvents {
            observedDesktopProcessIdentifier = desktopProcessIdentifier
        }
        // Presence is kernel truth, never `unknown`, and known before anything about turns.
        let presence = RunningApplicationPresence.presence(of: desktopProcessIdentifier)

        let hasLiveHookObservation = hasCurrentHookObservation(
            hookState: hookState,
            desktopProcessIdentifier: desktopProcessIdentifier
        )
        var setupStatus = IntegrationSetupStatus.card(
            registration: await hookRegistrar.registration(),
            hasObservedEvent: hookState.hasObservedEvent
        )
        guard setupStatus.isIntegrationEnabled else {
            let diagnostic = setupStatus == .repairRequired
                ? "Codex integration is incomplete and must be repaired."
                : "Codex integration has not been installed."
            return remember(
                AgentSnapshot(
                    availability: .setupRequired,
                    sessions: [],
                    quota: .unavailable,
                    diagnostic: diagnostic,
                    setupStatus: setupStatus,
                    presence: presence
                )
            )
        }

        var appServerResponded = false
        do {
            try await connectToAppServer()
            appServerResponded = true
            if presence == .open, let verified = await hookActivation.verified(using: client) {
                setupStatus = verified ? .active : .reviewRequired
            }
            let projectSnapshot = await projectMetadata.snapshot()

            if hasLiveHookObservation {
                let unreadSnapshot = await unreadState.snapshot()
                let hookThreadIDs = Set(hookState.turns.map(\.threadID))
                hookTrackedThreadIDs = hookThreadIDs
                // Resweep for a thread the last sweep missed, unless the App Server or the product has said
                // it does not exist (a Codex side chat would otherwise resweep every refresh).
                let containsUnlistedHookThread = hookState.turns.contains { state in
                    let threadID = state.threadID
                    guard !listedThreadIDs.contains(threadID) else { return false }
                    guard !state.threadHasNoTranscript else { return false }
                    guard let record = threadRecords[threadID] else { return true }
                    return record.isAddressable
                }

                // Hook state is the low-latency source; App Server reads only decorate it, in the background
                // so a slow request cannot hold Idle -> Running. Cheap per-thread metadata follows Hook
                // activity; the paginated full list only reconciles membership, at low frequency.
                scheduleThreadMetadataRefreshIfNeeded(for: hookState.turns)
                let fullListMustSupplyMetadata = !supportsThreadMetadataRead
                    && hookState.didConsumeEvents
                if containsUnlistedHookThread
                    || threadListRefreshIsDue
                    || fullListMustSupplyMetadata {
                    scheduleThreadListRefreshIfNeeded()
                }
                // Picks up a request parked by a backoff once the cool-off expires.
                startThreadListRefreshIfPossible()
                startThreadMetadataRefreshIfPossible()

                hookState = await hookEvents.applying(threadAdmission, to: hookState)
                // Rollout evidence (``CodexRolloutTurnEvidence``): aborts with no hook, and the real Turn
                // behind a held prompt. After reconciliation, before rows are built, so an abort is Completed
                // in this snapshot.
                await rolloutEvidence.hold(rolloutPaths: rolloutPaths(ofThreadsIn: hookState))
                hookState = await SupplementaryEvidenceApplication.settle(rolloutEvidence, from: hookState, in: hookEvents)
                // After the reduction, so a Turn just ended stops being watched in the same pass.
                await rolloutEvidence.watch(openTurnsIn: hookState)
                // In the background: the row's third line must not hold up its status.
                scheduleTurnProgressRefreshIfNeeded(for: hookState.turns)
                startTurnProgressRefreshIfPossible()
                let sessions = await sessions(
                    from: hookState.turns,
                    threadRecords: threadRecords,
                    projectMetadata: projectSnapshot,
                    unreadState: unreadSnapshot,
                    approvalRouting: await approvalRouting.snapshot(),
                    dismissedRowIDs: dismissedRowIDs
                )
                // The only branch that prunes the gate against every listed row.
                didEvaluateRows = true
                await usage.readIfStale()
                return remember(
                    AgentSnapshot(
                        availability: .ready,
                        sessions: sessions.sorted(by: MonitorAggregation.rowOrder),
                        quota: await usage.currentQuota(),
                        diagnostic: MonitorDiagnostics.combined(
                            hookDiagnostic,
                            unreadSnapshot.diagnostic,
                            projectDiagnostic(
                                for: sessions,
                                metadata: projectSnapshot
                            )
                        ),
                        setupStatus: setupStatus,
                        presence: presence
                    )
                )
            }

            // No post-launch Hook observation yet: build no sessions, only confirm the App Server answers
            // a real read (Ready vs Disconnected, unsupported protocol). Nothing started before launch is
            // reconstructed: an independent App Server reports every thread `notLoaded` and no
            // `inProgress` turn (measured CLI 0.148.0-alpha.9). One bounded page, not the membership
            // sweep (CR-Fable-023).
            hookTrackedThreadIDs = []
            // Stop reads only the live-Hook branch consumes, or a parked retry marker becomes a deadline
            // nothing clears and the store spins at the refresh floor (as CR-Fable-050).
            stopThreadReadsWithNoConsumer()
            try await confirmAppServerAnswersReads(
                timeoutNanoseconds: nanoseconds(timing.coreRequestTimeout)
            )
            await usage.readIfStale()
            return remember(
                AgentSnapshot(
                    availability: .ready,
                    sessions: [],
                    quota: await usage.currentQuota(),
                    diagnostic: nil,
                    setupStatus: setupStatus,
                    presence: presence
                )
            )
        } catch let error as CodexAppServerError {
            if error.isUnsupportedMethod {
                return AgentSnapshot(
                    availability: .unsupportedVersion,
                    sessions: [],
                    quota: .unavailable,
                    diagnostic: error.localizedDescription,
                    setupStatus: setupStatus,
                    presence: presence
                )
            }
            if error.isTransientRequestFailure {
                guard appServerResponded else {
                    await client.disconnect()
                    return AgentSnapshot(
                        availability: .disconnected,
                        sessions: [],
                        quota: .unavailable,
                        diagnostic: "The Codex App Server is not responding: \(error.localizedDescription)",
                        setupStatus: setupStatus,
                        presence: presence
                    )
                }
                return await snapshotPreservingTrustedState(
                    after: error,
                    setupStatus: setupStatus,
                    presence: presence
                )
            }
            if error.requiresConnectionReset {
                await client.disconnect()
            }
            return AgentSnapshot(
                availability: .disconnected,
                sessions: [],
                quota: .unavailable,
                diagnostic: error.localizedDescription,
                setupStatus: setupStatus,
                presence: presence
            )
        } catch {
            await client.disconnect()
            return AgentSnapshot(
                availability: .disconnected,
                sessions: [],
                quota: .unavailable,
                diagnostic: error.localizedDescription,
                setupStatus: setupStatus,
                presence: presence
            )
        }
    }

    /// Brings the App Server transport up, behind a cool-off after a failure. The only backoff
    /// that guards a subprocess: a broken `codex` exits in milliseconds, and a 1 Hz re-check
    /// forked `codex app-server` every second (CR-Fable-014). Refreshes turned away replay the
    /// last failure.
    ///
    /// - Parameter bypassingCoolOff: for a user click. The outcome is still recorded: success
    ///   clears the backoff; failure does not shorten it.
    private func connectToAppServer(bypassingCoolOff: Bool = false) async throws {
        if !bypassingCoolOff,
           let connectRetryAfter,
           clock.now() < connectRetryAfter {
            throw lastConnectFailure ?? CodexAppServerError.disconnected
        }

        do {
            try await client.connect()
            connectRetryAfter = nil
            lastConnectFailure = nil
        } catch {
            connectRetryAfter = clock.now()
                .addingTimeInterval(timing.connectRetryInterval)
            lastConnectFailure = error
            throw error
        }
    }

    /// Earliest moment a refresh could produce different output. Every deadline must be one a
    /// refresh can clear, or the store spins: each entry mirrors its scheduler's condition.
    func nextRefreshDeadline() async -> Date? {
        guard !observationStopped else { return nil }
        var deadlines: [Date] = []
        if let deadline = await connectionMonitor?.nextDeadline() { deadlines.append(deadline) }
        if hookActivationRetryAllowed, let deadline = await hookActivation.nextDeadline() {
            deadlines.append(deadline)
        }
        // Asked once, so both entries that consult it agree with their schedulers.
        let screenIsAvailable = screenAvailability.isAvailable()

        // Membership reconciliation, only while a Hook-tracked Turn consumes it (CR-Fable-023,
        // CR-Fable-002): the re-read is reachable only from the live-Hook branch. A new Turn's Hook
        // schedules a read and wakes the store itself.
        if let threadListReadAt, !hookTrackedThreadIDs.isEmpty {
            deadlines.append(
                deferred(
                    threadListReadAt.addingTimeInterval(
                        timing.threadListRefreshInterval
                    ),
                    by: threadListRetryAfter
                )
            )
        }

        // Only Hook-tracked threads; the rest of `threadRecords` refreshes with the membership read,
        // so measuring it here reports a deadline twenty seconds early.
        if supportsThreadMetadataRead,
           let oldestMetadata = hookTrackedThreadIDs
            .compactMap({ threadRecords[$0]?.observedAt })
            .min() {
            deadlines.append(
                deferred(
                    oldestMetadata.addingTimeInterval(
                        timing.threadMetadataRefreshInterval
                    ),
                    by: threadMetadataRetryAfter
                )
            )
        }

        // Quota and account: see ``CodexUsageReader/nextReadDeadline()``.
        if let quota = await usage.nextReadDeadline() {
            deadlines.append(quota)
        }

        // Only while backing off: a pending request with no cool-off is already looping, and a
        // deadline the refresh cannot clear makes the loop spin.
        if threadListGate.isPending, let threadListRetryAfter {
            deadlines.append(threadListRetryAfter)
        }
        if threadMetadataGate.isPending, let threadMetadataRetryAfter {
            deadlines.append(threadMetadataRetryAfter)
        }
        if turnProgressGate.isPending, let turnProgressRetryAfter {
            deadlines.append(turnProgressRetryAfter)
        }

        // Measured partly from now: the row waits on the user, not on an interval.
        if let terminal = terminalUnreadMembershipGate.nextDeadline(
            now: clock.now(),
            screenIsAvailable: screenIsAvailable
        ) {
            deadlines.append(terminal)
        }
        // A held answer window expiring: the refresh that withdraws the handle turns `Answer` into `Read`.
        if let expiry = hookEvents.nextAnswerExpiry() { deadlines.append(expiry) }
        return deadlines.min()
    }

    /// A due date pushed out by its source's retry backoff. A backoff floors the next attempt and
    /// never wakes on its own: a bare retry marker can stay in the past forever.
    nonisolated private func deferred(_ due: Date, by retryAfter: Date?) -> Date {
        guard let retryAfter else { return due }
        return max(due, retryAfter)
    }

    func disconnect() async {
        connectionRevision += 1
        await hookActivation.stop()
        await connectionMonitor?.reset()
        observationStopped = true
        hookActivationRetryAllowed = false
        hooks.disconnect()
        await hookEvents.resetIntegrationObservation(clearTurns: true, preserveBoundaryObservation: true)
        hookTrackedThreadIDs = []
        observedDesktopProcessIdentifier = nil
        lastTrustedSnapshot = nil
        stopThreadReadsWithNoConsumer()
        await rolloutEvidence.stopMonitoring()
        // Turn text belongs to the connection that answered for it.
        turnProgressByThreadID.removeAll()
        // So does the refusal: the next connection is entitled to be asked again.
        threadsWithoutItemsRead.removeAll()
        // And the read confirmation: the next connection may be a different build.
        threadListAnsweredAt = nil
        await usage.cancel()
        terminalUnreadMembershipGate.reset()
        connectRetryAfter = nil
        lastConnectFailure = nil
        await client.disconnect()
    }

    /// Whether the App Server still hands this thread over as a navigable root (ADR 0017).
    ///
    /// - One `thread/read` (1.4ms median), not a full pagination (2.2s at 799 threads, measured
    ///   2026-08-26 on CLI `0.149.0-alpha.4.3`), which was the 1-2s click lag.
    /// - Archiving is left to the membership sweep (`removeThreads(notIn:)`): `thread/read`
    ///   returns an archived thread unmarked.
    /// - A refusal retires the row.
    func isThreadNavigable(_ threadID: String) async throws -> Bool {
        guard !threadID.isEmpty else { return false }

        // A click is worth one spawn, whatever the last refresh concluded.
        try await connectToAppServer(bypassingCoolOff: true)

        if supportsThreadMetadataRead,
           let isNavigable = try await readNavigableRootThread(threadID) {
            return isNavigable
        }

        // Without `thread/read` only the paginated list can be asked.
        let listedThreads = try await readAllUnarchivedThreads(
            forceRefresh: true,
            timeoutNanoseconds: nanoseconds(timing.coreRequestTimeout)
        )
        return listedThreads.contains { thread in
            thread["id"]?.stringValue == threadID
                && CodexSnapshotParser.isEligibleRootThread(thread)
        }
    }

    /// Reads one thread and judges it; `nil` only on `-32601` (clears the metadata path's flag).
    /// Other remote errors are a refusal (`false`); a transport failure is rethrown, since it is
    /// not an answer.
    private func readNavigableRootThread(
        _ threadID: String
    ) async throws -> Bool? {
        let startedAt = clock.now()
        let response: JSONValue
        do {
            response = try await client.request(
                method: "thread/read",
                params: .object([
                    "threadId": .string(threadID),
                    // Never the turn history: see `refreshThreadMetadataInBackground`.
                    "includeTurns": .bool(false)
                ]),
                timeoutNanoseconds: nanoseconds(timing.coreRequestTimeout)
            )
        } catch let error as CodexAppServerError {
            if error.isUnsupportedMethod {
                supportsThreadMetadataRead = false
                return nil
            }
            guard case .remote = error else { throw error }
            recordThreadRead(
                threadID: threadID,
                thread: nil,
                observedAt: startedAt
            )
            return false
        }

        guard let thread = response["thread"] else { return false }
        recordThreadRead(
            threadID: threadID,
            thread: thread,
            observedAt: startedAt
        )
        return CodexSnapshotParser.isEligibleRootThread(thread)
    }

    /// Files a click's read: a fresher title, or a refusal.
    private func recordThreadRead(
        threadID: String,
        thread: JSONValue?,
        observedAt: Date
    ) {
        threadRecords[threadID] = ThreadRecord(
            thread: thread,
            observedAt: observedAt
        )
        invalidatePublishedSnapshot()
    }

    /// One answer, on the connection its request is still held on. A pass-through: the bytes are
    /// ``RequestAnswering``'s business, the connection the registry's.
    func answer(_ answer: AgentAnswer, on handle: AnswerHandle) async -> AnswerOutcome {
        await hooks.answer(answer, on: handle)
    }

    /// Nothing: the quota arrives over the App Server.
    func diskFootprint() async -> AgentDiskFootprintReport { .leavesNothing }

    func setupStatus() async -> IntegrationSetupStatus {
        await hookRegistrar.invalidateRegistration()
        return await hooks.setupStatus()
    }

    func installIntegration() async throws {
        await hookActivation.invalidate()
        try await hooks.install()
        // On a first run the socket could not bind at launch; binding now keeps the first turn from
        // waiting out a refresh deadline.
        await hooks.prepareTransport()
    }

    func removeIntegration() async throws {
        await hookEvents.resetIntegrationObservation(clearTurns: true)
        hooks.disconnect()
        try await hooks.remove()
        await disconnect()
    }

    nonisolated private func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }

    /// Every background read must end in this, or its result waits for an unrelated deadline.
    nonisolated private func invalidatePublishedSnapshot() {
        snapshotInvalidations.yield(())
    }

    private func sessions(
        from states: [HookTurnState],
        threadRecords: [String: ThreadRecord],
        projectMetadata: DesktopProjectMetadataSnapshot,
        unreadState: DesktopUnreadStateSnapshot,
        approvalRouting: DesktopApprovalRoutingSnapshot,
        dismissedRowIDs: Set<String>
    ) async -> [MonitoredSession] {
        // Only built rows go to the gate: keying on states left a sub-agent's entry frozen with a
        // deadline nothing could clear.
        var candidates: [ReadGateCandidate] = []
        // Every Turn walked, row or not: the pin is retained on what the reducer holds.
        var observedTurns: Set<TurnApprovalRoutingPin.TurnIdentity> = []

        // Reviewer readings first, for every Turn, so the loop below has no await mid-mutation.
        for state in states {
            let turn = TurnApprovalRoutingPin.TurnIdentity(
                threadID: state.threadID,
                turnID: state.turnID
            )
            // The path's stamp goes in too: resuming a Turn rotates the rollout, and the pin uses it
            // to tell an absent record from one read in the wrong file.
            guard let record = threadRecords[state.threadID],
                  let rolloutPath = record.thread?["path"]?.stringValue else {
                continue
            }
            guard approvalRoutingPin.awaitsRolloutReading(
                forTurn: turn,
                startedAt: state.startedAt,
                inRolloutReportedAt: record.observedAt
            ) else {
                continue
            }
            approvalRoutingPin.recordRolloutReading(
                await turnReviewer.approvalsReachTheUser(
                    forTurn: state.turnID,
                    startedAt: state.startedAt,
                    inRolloutAt: rolloutPath
                ),
                forTurn: turn,
                inRolloutReportedAt: record.observedAt
            )
        }

        for state in states {
            let turn = TurnApprovalRoutingPin.TurnIdentity(
                threadID: state.threadID,
                turnID: state.turnID
            )
            observedTurns.insert(turn)
            // The map answers for Turns the rollout could not, only if written after the Turn started.
            let approvalsReachTheUser = approvalRoutingPin.approvalsReachTheUser(
                forTurn: turn,
                startedAt: state.startedAt,
                in: approvalRouting
            )
            // Pinned to the turn it was read for: a previous turn's record describes finished work.
            let liveProgress = turnProgressByThreadID[state.threadID]
                .flatMap { $0.turnID == state.turnID ? $0.text : nil }
            // Status is the reducer's alone: an independent App Server reports every
            // thread `notLoaded` even mid-turn. A missing thread record (not asked,
            // refused, or no transcript) means no row; see
            // ``CodexSnapshotParser/session(from:thread:projectName:approvalsReachTheUser:liveProgress:)``.
            guard let session = CodexSnapshotParser.session(
                from: state,
                thread: threadRecords[state.threadID].flatMap(\.thread),
                projectName: projectMetadata.resolution(
                    for: state.threadID
                ).displayName,
                approvalsReachTheUser: approvalsReachTheUser,
                liveProgress: liveProgress
            ) else {
                continue
            }
            // Do not collapse these: the window measures thread quiet, the blue dot a Turn's answer.
            candidates.append(
                ReadGateCandidate(
                    row: session,
                    turnEndedAt: state.turnEndedAt,
                    terminalBoundaryAt: state.terminalBoundaryAt
                )
            )
        }

        approvalRoutingPin.retain(turns: observedTurns)
        // Every row is judged against Desktop's own unread set.
        return terminalUnreadMembershipGate.rows(
            candidates,
            dismissedRowIDs: dismissedRowIDs,
            now: clock.now()
        ) { _ in .judged(by: unreadState) }
    }

    /// Threads Codex vouches for (ADR 0017): the membership sweep's set as of that sweep's start.
    private var threadAdmission: ThreadAdmission {
        guard let threadListReadAt else { return .unknown }
        return .exactly(listedThreadIDs, readAt: threadListReadAt)
    }

    private var threadListRefreshIsDue: Bool {
        guard let threadListReadAt else { return true }
        return clock.now().timeIntervalSince(threadListReadAt)
            >= timing.threadListRefreshInterval
    }

    /// Recorded before the backoff is consulted, so a request mid-read or in cool-off is not
    /// dropped (CR-003).
    private func scheduleThreadListRefreshIfNeeded() {
        threadListGate.request()
        startThreadListRefreshIfPossible()
    }

    private func startThreadListRefreshIfPossible() {
        let now = clock.now()
        guard threadListGate.isPending else { return }
        guard threadListRetryAfter.map({ now >= $0 }) ?? true else { return }
        guard threadListGate.beginRun() else { return }

        threadListRefreshTask = Task { [weak self] in
            guard let self else { return }
            while await self.runThreadListRefresh() {}
            await self.clearThreadListRefreshTask()
        }
    }

    /// Returns whether another read should follow now. A failure leaves the request outstanding
    /// for `nextRefreshDeadline` to retry.
    private func runThreadListRefresh() async -> Bool {
        let succeeded = await refreshThreadListInBackground()
        return threadListGate.endRun(covered: succeeded)
    }

    private func clearThreadListRefreshTask() {
        threadListRefreshTask = nil
    }

    /// `thread/read` returns the same `Thread` payload as `thread/list` at a fraction of the cost.
    private func scheduleThreadMetadataRefreshIfNeeded(for states: [HookTurnState]) {
        guard supportsThreadMetadataRead else { return }

        let now = clock.now()
        var staleThreadIDs: Set<String> = []
        var observedThreadIDs: Set<String> = []
        for state in states {
            let threadID = state.threadID
            // Never asked: `thread/read` refuses it and no row is drawn. No record is written, keeping it
            // out of `nextRefreshDeadline()`'s metadata staleness.
            guard !state.threadHasNoTranscript else { continue }
            observedThreadIDs.insert(threadID)
            // An in-flight read will write the record the checks below look for.
            guard !inFlightMetadataThreadIDs.contains(threadID) else { continue }
            // A held prompt counts as the newest Turn: settling it reads this record's rollout path
            // (``CodexRolloutTurnEvidence``), which a resumed Turn moves.
            let newestTurn: (id: String, startedAt: Date) =
                if let held = state.heldTurnStart, held.startedAt > state.startedAt {
                    (held.turnID, held.startedAt)
                } else {
                    (state.turnID, state.startedAt)
                }
            guard let record = threadRecords[threadID] else {
                staleThreadIDs.insert(threadID)
                metadataReadTurnIDsByThreadID[threadID] = newestTurn.id
                continue
            }
            // A record older than the Turn is re-read regardless of interval: a resumed Turn gets its
            // own rollout (measured 2026-08-31, CLI `0.151.0-alpha.7.2`), and a stale path sent
            // ``TurnApprovalRoutingPin`` to the old file. Once per Turn; retries are the gate's job.
            let isFirstLookAtThisTurn =
                metadataReadTurnIDsByThreadID[threadID] != newestTurn.id
            let isBehindTheTurn = isFirstLookAtThisTurn
                && record.observedAt < newestTurn.startedAt
            let isBehindTheInterval = now.timeIntervalSince(record.observedAt)
                >= timing.threadMetadataRefreshInterval
            if isBehindTheTurn {
                metadataReadTurnIDsByThreadID[threadID] = newestTurn.id
            }
            if isBehindTheTurn || isBehindTheInterval {
                staleThreadIDs.insert(threadID)
            }
        }
        // Held to the threads the reducer still tracks.
        metadataReadTurnIDsByThreadID = metadataReadTurnIDsByThreadID.filter {
            observedThreadIDs.contains($0.key)
        }
        guard !staleThreadIDs.isEmpty else { return }

        // Accumulated: threads that went stale mid-read belong to the next read.
        pendingMetadataThreadIDs.formUnion(staleThreadIDs)
        threadMetadataGate.request()
        startThreadMetadataRefreshIfPossible()
    }

    private func startThreadMetadataRefreshIfPossible() {
        let now = clock.now()
        guard threadMetadataGate.isPending,
              supportsThreadMetadataRead,
              threadMetadataRetryAfter.map({ now >= $0 }) ?? true else {
            return
        }
        guard threadMetadataGate.beginRun() else { return }

        threadMetadataRefreshTask = Task { [weak self] in
            guard let self else { return }
            while await self.runThreadMetadataRefresh() {}
            await self.clearThreadMetadataRefreshTask()
        }
    }

    private func runThreadMetadataRefresh() async -> Bool {
        // Checked at dispatch: the "no `thread/read`" answer arrives mid-run. The request is settled,
        // since this build never grows the method.
        guard supportsThreadMetadataRead else {
            pendingMetadataThreadIDs.removeAll()
            _ = threadMetadataGate.endRun(covered: true)
            return false
        }

        let threadIDs = pendingMetadataThreadIDs
        pendingMetadataThreadIDs.removeAll()
        guard !threadIDs.isEmpty else {
            _ = threadMetadataGate.endRun(covered: true)
            return false
        }

        inFlightMetadataThreadIDs = threadIDs
        let succeeded = await refreshThreadMetadataInBackground(
            threadIDs: threadIDs
        )
        inFlightMetadataThreadIDs.removeAll()
        if !succeeded {
            pendingMetadataThreadIDs.formUnion(threadIDs)
        }
        return threadMetadataGate.endRun(covered: succeeded)
    }

    private func clearThreadMetadataRefreshTask() {
        threadMetadataRefreshTask = nil
    }

    // MARK: - Live progress

    /// Kept small: a `commandExecution` item carries `aggregatedOutput` (up to 290 KB measured).
    /// At most four items separated two `agentMessage`s (0.149.0-alpha.4.3).
    private static let turnProgressItemLimit = 6

    /// Keyed on `lastEventAt`, not an interval: a long command is read once, a tool burst once
    /// per call.
    private func scheduleTurnProgressRefreshIfNeeded(for states: [HookTurnState]) {
        // Pruned against threads that exist, finished or not.
        let liveThreadIDs = Set(states.map(\.threadID))
        turnProgressByThreadID = turnProgressByThreadID.filter {
            liveThreadIDs.contains($0.key)
        }
        pendingProgressReads = pendingProgressReads.filter {
            liveThreadIDs.contains($0.key)
        }
        inFlightProgressReads = inFlightProgressReads.filter {
            liveThreadIDs.contains($0.key)
        }
        threadsWithoutItemsRead.formIntersection(liveThreadIDs)

        for state in states {
            // A finished turn's last word came with its `Stop`.
            guard state.status != .completed else { continue }
            guard !threadsWithoutItemsRead.contains(state.threadID) else { continue }
            // Skip a thread the App Server lacks or with no transcript: its row is not drawn.
            if let record = threadRecords[state.threadID], !record.isAddressable {
                continue
            }
            guard !state.threadHasNoTranscript else { continue }
            let held = turnProgressByThreadID[state.threadID]
            if held?.turnID == state.turnID,
               held?.readAtEventStamp == state.lastEventAt {
                continue
            }
            if let inFlight = inFlightProgressReads[state.threadID],
               inFlight.turnID == state.turnID,
               inFlight.eventStamp == state.lastEventAt {
                continue
            }
            // Replaced, unlike the metadata read: only the later answer is wanted.
            pendingProgressReads[state.threadID] = TurnProgressRequest(
                turnID: state.turnID,
                eventStamp: state.lastEventAt
            )
        }
        guard !pendingProgressReads.isEmpty else { return }
        turnProgressGate.request()
    }

    private func startTurnProgressRefreshIfPossible() {
        let now = clock.now()
        guard turnProgressGate.isPending,
              turnProgressRetryAfter.map({ now >= $0 }) ?? true else {
            return
        }
        guard turnProgressGate.beginRun() else { return }

        turnProgressRefreshTask = Task { [weak self] in
            guard let self else { return }
            while await self.runTurnProgressRefresh() {}
            await self.clearTurnProgressRefreshTask()
        }
    }

    private func runTurnProgressRefresh() async -> Bool {
        // Filtered at dispatch: a thread may have refused while its own read was in flight.
        let requests = pendingProgressReads.filter {
            !threadsWithoutItemsRead.contains($0.key)
        }
        pendingProgressReads.removeAll()
        guard !requests.isEmpty else {
            _ = turnProgressGate.endRun(covered: true)
            return false
        }

        inFlightProgressReads = requests
        let succeeded = await refreshTurnProgressInBackground(requests: requests)
        inFlightProgressReads.removeAll()
        if !succeeded {
            for (threadID, request) in requests where pendingProgressReads[threadID] == nil {
                pendingProgressReads[threadID] = request
            }
        }
        return turnProgressGate.endRun(covered: succeeded)
    }

    private func clearTurnProgressRefreshTask() {
        turnProgressRefreshTask = nil
    }

    /// Returns whether the read covered these turns.
    @discardableResult
    private func refreshTurnProgressInBackground(
        requests: [String: TurnProgressRequest]
    ) async -> Bool {
        defer { invalidatePublishedSnapshot() }

        var didReadAnyTurn = false
        for (threadID, request) in requests.sorted(by: { $0.key < $1.key }) {
            guard !Task.isCancelled else { return false }

            do {
                let response = try await client.request(
                    method: "thread/items/list",
                    params: .object([
                        "threadId": .string(threadID),
                        // Scoped to the turn: otherwise a silent turn answers with
                        // the previous turn's closing words.
                        "turnId": .string(request.turnID),
                        "sortDirection": .string("desc"),
                        "limit": .number(Double(Self.turnProgressItemLimit))
                    ]),
                    timeoutNanoseconds: nanoseconds(timing.turnProgressTimeout)
                )
                didReadAnyTurn = true
                let text = CodexSnapshotParser.newestAgentMessage(in: response)
                if var held = turnProgressByThreadID[threadID],
                   held.turnID == request.turnID {
                    if let text {
                        held.text = text
                    }
                    held.readAtEventStamp = request.eventStamp
                    turnProgressByThreadID[threadID] = held
                } else {
                    turnProgressByThreadID[threadID] = TurnProgress(
                        turnID: request.turnID,
                        text: text,
                        readAtEventStamp: request.eventStamp
                    )
                }
            } catch let error as CodexAppServerError {
                if error.isUnsupportedMethod {
                    // Same code for a `legacy` `historyMode` thread and a Codex
                    // without this experimental method; both are recorded (see
                    // ``threadsWithoutItemsRead``). The row falls back to the
                    // prompt preview.
                    threadsWithoutItemsRead.insert(threadID)
                    turnProgressByThreadID.removeValue(forKey: threadID)
                    didReadAnyTurn = true
                    continue
                }
                if error.requiresConnectionReset {
                    await client.disconnect()
                    return false
                }
                continue
            } catch {
                continue
            }
        }

        guard !Task.isCancelled else { return false }
        turnProgressRetryAfter = didReadAnyTurn
            ? nil
            : clock.now().addingTimeInterval(timing.requestRetryInterval)
        return didReadAnyTurn
    }

    /// Returns whether the read covered `threadIDs`; the gate owns the state.
    @discardableResult
    private func refreshThreadMetadataInBackground(
        threadIDs: Set<String>
    ) async -> Bool {
        defer { invalidatePublishedSnapshot() }

        var didReadAnyThread = false
        for threadID in threadIDs.sorted() {
            guard !Task.isCancelled else { return false }

            let startedAt = clock.now()
            do {
                let response = try await client.request(
                    method: "thread/read",
                    params: .object([
                        "threadId": .string(threadID),
                        // `includeTurns` would return the whole rollout (hundreds
                        // of KB); the Hook reducer has the Turn facts.
                        "includeTurns": .bool(false)
                    ]),
                    timeoutNanoseconds: nanoseconds(timing.threadMetadataTimeout)
                )
                didReadAnyThread = true
                guard let thread = response["thread"] else { continue }
                threadRecords[threadID] = ThreadRecord(
                    thread: thread,
                    observedAt: startedAt
                )
            } catch let error as CodexAppServerError {
                if error.isUnsupportedMethod {
                    // Older builds fall back to whole-list metadata; the request
                    // is settled.
                    supportsThreadMetadataRead = false
                    return true
                }
                if error.requiresConnectionReset {
                    await client.disconnect()
                    return false
                }
                // Any other remote error is a refusal about this thread, recorded whatever
                // its wording: an ephemeral thread refuses forever and would otherwise be
                // reissued every refresh. A reset transport or timeout leaves no record.
                if case .remote = error {
                    threadRecords[threadID] = ThreadRecord(
                        thread: nil,
                        observedAt: startedAt
                    )
                    // Counts as a read, so a batch of refusals (a side chat)
                    // does not park later reads behind a request-failure cool-off.
                    didReadAnyThread = true
                }
                continue
            } catch {
                continue
            }
        }

        guard !Task.isCancelled else { return false }
        threadMetadataRetryAfter = didReadAnyThread
            ? nil
            : clock.now().addingTimeInterval(timing.requestRetryInterval)
        return didReadAnyThread
    }

    @discardableResult
    private func refreshThreadListInBackground() async -> Bool {
        defer { invalidatePublishedSnapshot() }

        do {
            _ = try await readAllUnarchivedThreads(
                forceRefresh: true,
                timeoutNanoseconds: nanoseconds(timing.backgroundThreadListTimeout)
            )
            guard !Task.isCancelled else { return false }
            threadListRetryAfter = nil
            return true
        } catch let error as CodexAppServerError {
            guard !Task.isCancelled else { return false }
            threadListRetryAfter = clock.now().addingTimeInterval(
                timing.requestRetryInterval
            )
            if error.requiresConnectionReset {
                await client.disconnect()
            }
            return false
        } catch {
            guard !Task.isCancelled else { return false }
            threadListRetryAfter = clock.now().addingTimeInterval(
                timing.requestRetryInterval
            )
            return false
        }
    }

    private func remember(_ snapshot: AgentSnapshot) -> AgentSnapshot {
        lastTrustedSnapshot = snapshot
        return snapshot
    }

    private func projectDiagnostic(
        for sessions: [MonitoredSession],
        metadata: DesktopProjectMetadataSnapshot
    ) -> String? {
        let unavailableCount = sessions.filter {
            $0.projectName == RowContentFallback.unavailableProjectName
        }.count
        let unresolvedDiagnostic = unavailableCount > 0
            ? "\(unavailableCount) sessions have no verifiable Desktop Project mapping; they were not fallen back to Chats."
            : nil
        return MonitorDiagnostics.combined(metadata.diagnostic, unresolvedDiagnostic)
    }

    /// Keeps the last trusted observation while a request is transiently failing. Presence and
    /// setup are passed in: the initialiser's `.open`/`.active` defaults would draw Connected for
    /// a closed Desktop (PRD §6.3, §12).
    private func snapshotPreservingTrustedState(
        after error: CodexAppServerError,
        setupStatus: IntegrationSetupStatus,
        presence: AgentPresence
    ) async -> AgentSnapshot {
        let cachedQuota = await usage.currentQuota()
        let diagnostic = "An App Server request failed for the moment; the most recent state has been kept: \(error.localizedDescription)"
        guard let lastTrustedSnapshot else {
            return AgentSnapshot(
                availability: .connecting,
                sessions: [],
                quota: cachedQuota,
                diagnostic: diagnostic,
                setupStatus: setupStatus,
                presence: presence
            )
        }

        let quota = cachedQuota.remainingPercent == nil
            ? lastTrustedSnapshot.quota
            : cachedQuota
        return AgentSnapshot(
            availability: lastTrustedSnapshot.availability,
            sessions: lastTrustedSnapshot.sessions,
            quota: quota,
            diagnostic: diagnostic,
            setupStatus: setupStatus,
            presence: presence
        )
    }

    /// One page of `thread/list`, asked for only to see it answered, so an unsupported Codex
    /// reports `unsupportedVersion` rather than an empty Ready.
    ///
    /// Nothing is written into the membership caches: a truncated `listedThreadIDs` with a current
    /// `threadListReadAt` would retire every Turn not on the first page. The freshness window is a
    /// ceiling, not a cadence: `nextRefreshDeadline()` never wakes for it.
    private func confirmAppServerAnswersReads(
        timeoutNanoseconds: UInt64
    ) async throws {
        if let threadListAnsweredAt,
           clock.now().timeIntervalSince(threadListAnsweredAt)
               < timing.threadListRefreshInterval {
            return
        }

        let startedAt = clock.now()
        _ = try await client.request(
            method: "thread/list",
            params: threadListParameters(limit: 1),
            timeoutNanoseconds: timeoutNanoseconds
        )
        threadListAnsweredAt = startedAt
    }

    /// Shared by the membership sweep and the confirmation so both send the same request shape and
    /// differ only in size.
    nonisolated private func threadListParameters(
        limit: Int,
        cursor: String? = nil
    ) -> JSONValue {
        var params: [String: JSONValue] = [
            "archived": .bool(false),
            "limit": .number(Double(limit)),
            "sortKey": .string("updated_at"),
            "sortDirection": .string("desc"),
            "sourceKinds": .array([
                .string("cli"),
                .string("vscode"),
                .string("appServer"),
                .string("unknown")
            ])
        ]
        if let cursor {
            params["cursor"] = .string(cursor)
        }
        return .object(params)
    }

    /// Drops the reads only a live Hook observation can consume or clear: left here, a request has
    /// nobody to run it and `nextRefreshDeadline()` publishes its backoff marker as a wake-up.
    /// Cached thread metadata is kept.
    private func stopThreadReadsWithNoConsumer() {
        threadListRefreshTask?.cancel()
        threadListRefreshTask = nil
        threadListGate.reset()
        threadListRetryAfter = nil
        threadMetadataRefreshTask?.cancel()
        threadMetadataRefreshTask = nil
        threadMetadataGate.reset()
        threadMetadataRetryAfter = nil
        pendingMetadataThreadIDs.removeAll()
        inFlightMetadataThreadIDs.removeAll()
        turnProgressRefreshTask?.cancel()
        turnProgressRefreshTask = nil
        turnProgressGate.reset()
        turnProgressRetryAfter = nil
        pendingProgressReads.removeAll()
        inFlightProgressReads.removeAll()
    }

    /// The rollout this thread is written to; the App Server is the only source.
    private func rolloutPath(ofThread threadID: String) -> String? {
        guard let path = threadRecords[threadID]?.thread?["path"]?.stringValue,
              !path.isEmpty else {
            return nil
        }
        return path
    }

    private func rolloutPaths(ofThreadsIn hookState: HookStateSnapshot) -> [String: String] {
        var paths: [String: String] = [:]
        for turn in hookState.turns {
            paths[turn.threadID] = rolloutPath(ofThread: turn.threadID)
        }
        return paths
    }

    /// Reads every unarchived thread: the most expensive call, used only to establish which threads
    /// still exist (and for `threadRecords` on builds without `thread/read`).
    private func readAllUnarchivedThreads(
        forceRefresh: Bool,
        timeoutNanoseconds: UInt64
    ) async throws -> [JSONValue] {
        if !forceRefresh,
           let threadListReadAt,
           clock.now().timeIntervalSince(threadListReadAt)
               < timing.threadListRefreshInterval {
            return listedThreadIDs.compactMap { threadRecords[$0].flatMap(\.thread) }
        }

        var threads: [JSONValue] = []
        var cursor: String?
        var observedCursors = Set<String>()
        let snapshotStartedAt = clock.now()

        repeat {
            if let cursor, !observedCursors.insert(cursor).inserted {
                throw CodexAppServerError.protocolViolation(
                    "thread/list returned a repeated cursor"
                )
            }

            let page = try await client.request(
                method: "thread/list",
                params: threadListParameters(limit: 100, cursor: cursor),
                timeoutNanoseconds: timeoutNanoseconds
            )
            threads.append(contentsOf: page["data"]?.arrayValue ?? [])
            cursor = page["nextCursor"]?.stringValue
        } while cursor != nil

        // Request start is the freshness boundary: a Hook can arrive mid-pagination.
        let listedIDs = Set(threads.compactMap { $0["id"]?.stringValue })
        for thread in threads {
            guard let threadID = thread["id"]?.stringValue else { continue }
            // A newer single-thread read must not be overwritten by an older list.
            if let existing = threadRecords[threadID],
               existing.observedAt > snapshotStartedAt {
                continue
            }
            threadRecords[threadID] = ThreadRecord(
                thread: thread,
                observedAt: snapshotStartedAt
            )
        }
        threadRecords = threadRecords.filter { threadID, record in
            if listedIDs.contains(threadID) { return true }
            // A refusal survives the sweep, or the thread is re-asked with a full pagination every
            // refresh. Kept only while a Turn names the thread.
            return !record.isAddressable
                && hookTrackedThreadIDs.contains(threadID)
        }
        listedThreadIDs = listedIDs
        threadListReadAt = snapshotStartedAt
        // The sweep also confirms the transport answers reads.
        threadListAnsweredAt = snapshotStartedAt
        return threads
    }

    /// Drops the Hook evidence held for a Desktop process that is no longer running, with its
    /// reads. The next process binds with its own first event; `hookTrackedThreadIDs` goes too so
    /// retired threads stop asking to be re-read.
    @discardableResult
    private func retireHookTurns(
        didConsumeEvents: Bool = false
    ) async -> HookStateSnapshot {
        observedDesktopProcessIdentifier = nil
        hookTrackedThreadIDs = []
        return await hookEvents.discardTurns(didConsumeEvents: didConsumeEvents)
    }

    private func hasCurrentHookObservation(
        hookState: HookStateSnapshot,
        desktopProcessIdentifier: pid_t?
    ) -> Bool {
        guard hookState.hasObservedLiveEvent,
              let desktopProcessIdentifier,
              observedDesktopProcessIdentifier == desktopProcessIdentifier else {
            return false
        }
        return true
    }
}

enum CodexSnapshotParser {
    nonisolated static func accountFingerprint(from response: JSONValue) -> String {
        let account = response["account"]
        return [
            account?["type"]?.stringValue,
            account?["email"]?.stringValue,
            account?["planType"]?.stringValue,
            account?["chatgptAccountId"]?.stringValue
        ]
        .map { $0 ?? "-" }
        .joined(separator: "|")
    }

    /// Both of the account's rate-limit windows, `primary` first, so ``QuotaSnapshot/remainingPercent``
    /// and ``QuotaSnapshot/resetsAt`` still read it (`quota-footer-v2.md` §5). `secondary` is null
    /// for most accounts. `rateLimitsByLimitId` is not read: the response does not say which
    /// model-specific cap binds.
    nonisolated static func quota(from response: JSONValue) -> QuotaSnapshot {
        guard let limits = response["rateLimits"] else { return .unavailable }

        let windows = ["primary", "secondary"].compactMap { key -> QuotaWindow? in
            guard let window = limits[key],
                  let usedPercent = window["usedPercent"]?.intValue else {
                return nil
            }
            return QuotaWindow(
                label: windowLabel(minutes: window["windowDurationMins"]?.intValue),
                // Reported as used.
                remainingPercent: 100 - usedPercent,
                resetsAt: window["resetsAt"]?.doubleValue.map {
                    Date(timeIntervalSince1970: $0)
                }
            )
        }
        guard !windows.isEmpty else { return .unavailable }
        return QuotaSnapshot(windows: windows)
    }

    /// A window's label from its duration, the only thing Codex publishes about one: `300` is the
    /// 5-hour limit, `10080` the weekly one; others are written out from the minutes, and no
    /// duration keeps the empty label.
    nonisolated static func windowLabel(minutes: Int?) -> String {
        switch minutes {
        case 300: "5h limit"
        case 10_080: "Weekly limit"
        case .some(let minutes) where minutes > 0 && minutes % 1_440 == 0:
            "\(minutes / 1_440)d limit"
        case .some(let minutes) where minutes > 0 && minutes % 60 == 0:
            "\(minutes / 60)h limit"
        case .some(let minutes) where minutes > 0: "\(minutes)m limit"
        default: ""
        }
    }

    nonisolated static func todayTokenCount(
        from response: JSONValue,
        now: Date,
        calendar: Calendar? = nil
    ) -> Int64? {
        guard let buckets = response["dailyUsageBuckets"]?.arrayValue else {
            return nil
        }

        let calendar = calendar ?? localGregorianCalendar()
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: now
        )
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return nil
        }
        let todayKey = String(
            format: "%04d-%02d-%02d",
            year,
            month,
            day
        )

        return buckets.last {
            $0["startDate"]?.stringValue == todayKey
        }?["tokens"]?.int64Value ?? 0
    }

    nonisolated private static func localGregorianCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    nonisolated static func isEligibleRootThread(_ thread: JSONValue) -> Bool {
        guard thread["ephemeral"]?.boolValue != true else { return false }
        guard thread["parentThreadId"]?.stringValue == nil else { return false }
        guard thread["agentRole"]?.stringValue == nil else { return false }
        guard thread["agentNickname"]?.stringValue == nil else { return false }

        // `threadSource == user` is the root-thread discriminator; older versions omit it in
        // thread/list, so a missing value is tolerated.
        if let source = thread["threadSource"]?.stringValue {
            return source == "user"
        }
        return true
    }

    /// Builds a display row for a Turn the Hook reducer already owns: `thread` decides eligibility
    /// and supplies title and preview; status and timing come from the reducer.
    ///
    /// - No Thread payload, no row: Desktop runs unmaterialised threads (side chats) that no
    ///   deep link reaches. A real thread is on disk before its first Hook (measured 2026-08-25,
    ///   CLI `0.149.0-alpha.4.3`).
    /// - `approvalsReachTheUser` only subtracts: on a thread Codex reviews itself, an open
    ///   permission call asks nobody (``CodexDesktopApprovalRoutingRepository``).
    /// - `liveProgress` is this turn's newest message; absent, a Running row shows its prompt.
    nonisolated static func session(
        from state: HookTurnState,
        thread: JSONValue?,
        projectName: String,
        approvalsReachTheUser: Bool = true,
        liveProgress: String? = nil
    ) -> MonitoredSession? {
        guard let thread, isEligibleRootThread(thread) else {
            return nil
        }

        let threadPreview = normalizedPreview(thread["preview"]?.stringValue)
        // Empty here; ``MonitoredSession/init`` supplies ``RowContentFallback/title``.
        let title = normalizedTitle(thread["name"]?.stringValue)
            ?? threadPreview
            ?? normalizedPreview(state.promptPreview)
            ?? ""
        // Only the approval wait is subtracted: the reviewer never answers `request_user_input`.
        let status = approvalsReachTheUser || state.status != .approvalNeeded
            ? state.status
            : .running
        // Subagents inherit the thread's `approvals_reviewer` (measured 2026-08-23: all 72 subagent
        // rollouts with a parent on disk).
        let subagentsAwaitingApprovalCount = approvalsReachTheUser
            ? state.subagentsAwaitingApprovalCount
            : 0
        // - Completed: the `Stop`'s last word, then a question asked without waiting, then the prompt.
        //   A stopped turn has no last word (ADR 0011, ``CodexRolloutTurnAbortReader``).
        // - Running: a question asked without waiting (`request_user_input_async` keeps working and
        //   overwrites it within seconds), then the step read, then the prompt.
        // Neither claims anybody is waiting (``HookTurnState/questionAskedWithoutWaiting``).
        let preview = status == .completed
            ? (normalizedPreview(state.assistantPreview)
                ?? normalizedPreview(state.questionAskedWithoutWaiting)
                ?? normalizedPreview(liveProgress)
                ?? normalizedPreview(state.promptPreview))
            : (normalizedPreview(state.questionAskedWithoutWaiting)
                ?? normalizedPreview(liveProgress)
                ?? normalizedPreview(state.promptPreview))

        return MonitoredSession(
            threadID: state.threadID,
            turnID: state.turnID,
            projectName: projectName,
            title: title,
            preview: preview,
            status: status,
            startedAt: state.startedAt,
            runningSubagentCount: state.runningSubagentIDs.count,
            subagentsAwaitingApprovalCount: subagentsAwaitingApprovalCount,
            // `lastEventAt` is held against a subagent's chatter, so it is a fixed end.
            finishedAt: status == .completed ? state.lastEventAt : nil,
            // Same subtraction as the status: no `Answer` control over an approval the reviewer handles.
            // `inputNeeded` is never reviewed away.
            requests: approvalsReachTheUser || status == .inputNeeded
                ? state.requestsAwaitingAnAnswer
                : []
        )
    }

    nonisolated static let agentMessageItemType = "agentMessage"

    /// The newest assistant message in one newest-first `thread/items/list` page. Other item types
    /// are skipped: the row reports what the agent said, as Claude Code's row does.
    nonisolated static func newestAgentMessage(in response: JSONValue) -> String? {
        guard let entries = response["data"]?.arrayValue else { return nil }
        for entry in entries {
            guard let item = entry["item"],
                  item["type"]?.stringValue == agentMessageItemType,
                  let text = item["text"]?.stringValue else { continue }
            guard let normalized = normalizedPreview(text) else { continue }
            return normalized
        }
        return nil
    }

    nonisolated private static func normalizedTitle(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    nonisolated private static func normalizedPreview(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(240))
    }
}
