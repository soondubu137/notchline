import AppKit
import Foundation

/// One product's boundary, reduced to what the store needs.
///
/// The shape was always general — nothing in it names Codex — so a second
/// product does not widen it, it just means there is more than one of them.
protocol AgentMonitoring: Sendable {
    /// Which product this provider speaks for.
    nonisolated var agent: AgentKind { get }
    /// Edges that mean "ask me again", merged by the store into one wake-up
    /// stream. A provider whose answer arrives late reports it here rather than
    /// through a deadline, which is what lets a slow provider not hold up a
    /// fast one.
    nonisolated var stateChangeEvents: AsyncStream<Void> { get }
    /// This product's answer, told which of its rows the user has already taken
    /// off the list.
    ///
    /// A removed row is still this product's row -- nothing was deleted, and
    /// the record of the removal belongs to the store, which is the only layer
    /// that can tell "the user waved it away" from "the Turn is over"
    /// (CR-Fable-004). What changes here is that the row is no longer waiting
    /// for anything, and only the provider can act on that: an entry in the
    /// terminal gate books a re-check once a second, and it does so for a row
    /// nobody can see as readily as for one on the notch. Removal used to stop
    /// at the top layer, so both products went on sampling read state for a row
    /// the user had already dismissed, for as long as its session lived
    /// (CR-Fable-003).
    ///
    /// Ids are ``MonitoredSession/id``, and only this product's.
    func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot
    /// Earliest moment a refresh could produce different output.
    ///
    /// The store sleeps until this instead of sampling on a fixed cadence, so a
    /// quiet monitor does no work at all and a due window is served exactly when
    /// it comes due.
    func nextRefreshDeadline() async -> Date?
    /// What this product's monitoring has left on disk, or why there is not a
    /// figure for it yet.
    ///
    /// Reporting only. Nothing in this app deletes them — the folder they go to
    /// can hold a user's own sessions as well, so the decision is theirs. A
    /// product that leaves files answers even before it can measure them, so
    /// that Settings can draw the row it is going to draw anyway.
    func diskFootprint() async -> AgentDiskFootprintReport
    func hookSetupStatus() async -> HookSetupStatus
    func installHooks() async throws
    func removeHooks() async throws
    func disconnect() async
}

extension AgentMonitoring {
    /// Nothing removed, which is what a caller with no removal record of its
    /// own is saying. The store holds the only one there is.
    func fetchSnapshot() async -> AgentSnapshot {
        await fetchSnapshot(dismissedRowIDs: [])
    }

    /// Nothing, which is the ordinary case and the one Codex is in: its quota
    /// arrives over the app server and leaves no files anywhere. Only a product
    /// that writes something the user might want back overrides this.
    func diskFootprint() async -> AgentDiskFootprintReport { .leavesNothing }
}

actor LiveCodexMonitorService: AgentMonitoring, CodexNavigationTargetChecking {
    nonisolated let agent = AgentKind.codex

    /// Thread-level metadata cached for one thread.
    ///
    /// `observedAt` is the request start, not its completion, so a Hook that
    /// arrives while the read is in flight still wins the freshness comparison.
    private struct ThreadRecord: Sendable {
        let thread: JSONValue
        let observedAt: Date
    }

    private let clock: any MonitorClock
    private let timing: MonitorTiming
    private let client: any CodexAppServerCommunicating
    private let hookEvents: HookEventRepository
    private let hookRegistrar: CodexHookRegistrar
    nonisolated private let hookListener: AgentHookListener
    private let projectMetadata: any DesktopProjectMetadataProviding
    private let unreadState: any DesktopUnreadStateProviding
    /// Which threads Codex answers approval requests for on the user's behalf.
    ///
    /// A decision spanning two sources, so it is made here rather than in the
    /// reducer: the reducer sees only that a permission pipeline opened over a
    /// call that is still open, which is as true of a request the automatic
    /// reviewer is deciding as of one a person is looking at.
    private let approvalRouting: any DesktopApprovalRoutingProviding
    /// Whether there is a screen the user could read a thread on.
    ///
    /// Only the gate's re-check consults it: a row Desktop still reports unread
    /// is cleared by somebody opening it in Desktop, which a locked screen
    /// makes impossible. See
    /// ``TerminalUnreadMembershipGate/nextDeadline(now:screenIsAvailable:)``.
    nonisolated private let screenAvailability: any ScreenAvailabilityReporting
    nonisolated let stateChangeEvents: AsyncStream<Void>
    nonisolated private let snapshotInvalidations: AsyncStream<Void>.Continuation
    private let desktopProcessIdentifierProvider: @MainActor @Sendable () -> pid_t?
    private var cachedQuota = QuotaSnapshot.unavailable
    private var quotaReadAt: Date?
    private var cachedAccountFingerprint: String?
    private var accountReadAt: Date?
    private var threadRecords: [String: ThreadRecord] = [:]
    /// The threads the per-thread metadata read actually revisits.
    ///
    /// `threadRecords` caches every unarchived thread the membership read
    /// returned, but only Hook-tracked threads are ever re-read. Measuring
    /// staleness over the whole cache therefore reports a deadline that no
    /// refresh can clear.
    private var hookTrackedThreadIDs: Set<String> = []
    private var listedThreadIDs: Set<String> = []
    private var threadListReadAt: Date?
    private var threadListGate = SingleFlightGate()
    private var threadListRefreshTask: Task<Void, Never>?
    private var threadListRetryAfter: Date?
    private var threadMetadataGate = SingleFlightGate()
    private var threadMetadataRefreshTask: Task<Void, Never>?
    private var threadMetadataRetryAfter: Date?
    /// Threads a metadata read was asked for but has not yet covered.
    private var pendingMetadataThreadIDs: Set<String> = []
    private var supportsThreadMetadataRead = true
    private var observedDesktopProcessIdentifier: pid_t?
    private var quotaRefreshTask: Task<Void, Never>?
    private var quotaRetryAfter: Date?
    private var lastTrustedSnapshot: AgentSnapshot?
    /// Whether this run has already compared the installed helper's bytes.
    private var didCompareHelperThisLaunch = false
    private var terminalUnreadMembershipGate: TerminalUnreadMembershipGate

    init(
        client: any CodexAppServerCommunicating = CodexAppServerClient(),
        hookEvents: HookEventRepository = HookEventRepository(),
        hookRegistrar: CodexHookRegistrar = CodexHookRegistrar(),
        hookListener: AgentHookListener? = nil,
        projectMetadata: any DesktopProjectMetadataProviding =
            CodexDesktopProjectMetadataRepository(),
        unreadState: any DesktopUnreadStateProviding =
            CodexDesktopUnreadStateRepository(),
        approvalRouting: any DesktopApprovalRoutingProviding =
            CodexDesktopApprovalRoutingRepository(),
        screenAvailability: any ScreenAvailabilityReporting =
            ScreenAvailabilityWatcher(),
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard,
        desktopProcessIdentifierProvider: @escaping @MainActor @Sendable () -> pid_t? = {
            LiveCodexMonitorService.desktopProcessIdentifier()
        }
    ) {
        self.clock = clock
        self.timing = timing
        self.client = client
        self.hookEvents = hookEvents
        self.hookRegistrar = hookRegistrar
        // The transport belongs to this service rather than to the store, so
        // the store stays a reducer with an inbox and nothing that binds. One
        // connection carries one payload; the closure below is called on the
        // listener's serial read queue, which is what keeps arrival order.
        self.hookListener = hookListener ?? AgentHookListener(clock: clock) {
            [hookEvents] body, receivedAt in
            hookEvents.deliver(body, at: receivedAt)
        }
        self.projectMetadata = projectMetadata
        self.unreadState = unreadState
        self.approvalRouting = approvalRouting
        self.screenAvailability = screenAvailability
        // Background reads land after the snapshot that started them has already
        // been published, so their results need a trigger of their own. The
        // one-second poll used to supply that by accident.
        let (invalidations, invalidationContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.snapshotInvalidations = invalidationContinuation
        self.stateChangeEvents = DirectoryChangeWatcher.merged([
            // The store signals only when what a row draws has changed, so a
            // 17-event turn is one wake-up rather than seventeen. There is no
            // debounce in front of it any more: the 100 ms the queue watcher
            // added landed on the one path where a user is watching for a row
            // to change, and it was there to collapse a burst of files that no
            // longer exists.
            hookEvents.changeEvents(),
            // The registration changing underneath us -- the user running
            // `/hooks`, or editing the file. It is what replaced re-deriving
            // installation health on a 60-second cadence.
            hookRegistrar.changeEvents(),
            unreadState.changeEvents(),
            // The screen coming back. A row waiting on the user books no
            // re-check while there is no screen to read it on, so this is what
            // re-arms it -- without it the row would wait out the heartbeat
            // after an unlock, which is the one moment the user is most likely
            // to be looking at the notch.
            screenAvailability.changeEvents(),
            invalidations
        ])
        self.terminalUnreadMembershipGate = TerminalUnreadMembershipGate(
            settlingInterval: timing.terminalReadSettlingInterval,
            unreadRecheckInterval: timing.terminalUnreadRecheckInterval
        )
        self.desktopProcessIdentifierProvider = desktopProcessIdentifierProvider
    }

    func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot {
        // The transport, before the status gate. A trusted definition can fire
        // before this app decides the registration is complete -- a Codex that
        // was already running has them loaded -- so the socket has to be bound
        // by then, not after.
        await prepareTransport()
        // Every branch below that returns without evaluating rows has to say so,
        // because the gate is the one piece of state here that a refresh must
        // *touch* to keep honest. Its entries are pruned and hidden inside
        // `sessions(from:)`, which only the live-hook branch reaches; left
        // alone by the others they freeze in place, unhidden, and go on
        // re-issuing a re-check one second forward from now. Nothing can clear
        // them, because no refresh reachable from those branches evaluates a
        // row -- so losing Desktop with one unread row left the app waking at
        // 1 Hz forever, with nothing on screen (CR-Fable-050).
        //
        // Written as a `defer` over one flag rather than a `reset()` at each
        // `return`: the branches here are the ones that exist today, and the
        // failure was a branch added later that nobody remembered to teach.
        // The Claude Code service does the same thing at each of its two early
        // returns, which is the same rule with a smaller surface.
        var didEvaluateRows = false
        defer {
            if !didEvaluateRows {
                terminalUnreadMembershipGate.reset()
            }
        }
        let desktopProcessIdentifier = await desktopProcessIdentifierProvider()
        // The pid binds the Turns, not just the decision to publish them.
        //
        // `hasCurrentHookObservation` gates whether this refresh trusts the
        // reducer, and that gate was the whole of the pid binding: the Turns
        // themselves were never bound to anything. So a Desktop that died
        // mid-turn -- a crash or an update sends no `Stop`, and a user quitting
        // it has not been measured either way -- left its Running Turn in the
        // reducer. It correctly vanished from the notch while Desktop was
        // closed, and then came back in full on the first hook event from the
        // *relaunched* process, elapsed clock still counting from before the
        // crash, because that event rebound the observation to the new pid and
        // republished everything the reducer held (CR-Fable-007). Nothing
        // could clear it afterwards: membership reconciliation kept the row
        // because the thread is still listed and unarchived, no hook will ever
        // name that retired `turn_id` again, and
        // Codex has no activity-status read to settle
        // it the way `claude agents --json` does for Claude Code (ADR 0011).
        // Only resuming that exact thread, or dismissing the row by hand, took
        // it off the notch.
        //
        // Retired *before* the drain, so the relaunched process's events land
        // in a reducer that no longer holds its predecessor's Turns -- after
        // the drain they would be indistinguishable from them.
        if let vouchingProcessIdentifier = observedDesktopProcessIdentifier,
           vouchingProcessIdentifier != desktopProcessIdentifier {
            await retireHookTurns()
        }
        var hookState = await hookEvents.drainDeliveredEvents()
        let hookDiagnostic = hookState.diagnostic
        if desktopProcessIdentifier == nil {
            // And *after* the drain while nothing is running, because a helper
            // spawned by the dying process can still deliver on its way out.
            // That payload is no better vouched for than the Turn it belongs
            // to, and left in the reducer it would outlive this window and be
            // adopted by the next Desktop exactly as above.
            hookState = await retireHookTurns(
                didConsumeEvents: hookState.didConsumeEvents
            )
        } else if hookState.didConsumeEvents {
            observedDesktopProcessIdentifier = desktopProcessIdentifier
        }
        // Presence is kernel truth here, so it is never `unknown`: the running
        // application list cannot go stale or fail to answer the way a cached
        // command output can. It is also knowable before anything is known
        // about turns, which is the asymmetry worth keeping — a just-launched
        // app can say Codex is open while still knowing nothing about its work.
        let presence: AgentPresence = desktopProcessIdentifier == nil
            ? .closed
            : .open

        let hasLiveHookObservation = hasCurrentHookObservation(
            hookState: hookState,
            desktopProcessIdentifier: desktopProcessIdentifier
        )
        let setupStatus = HookSetupStatus.card(
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
            try await client.connect()
            appServerResponded = true
            let projectSnapshot = await projectMetadata.snapshot()

            if hasLiveHookObservation {
                let unreadSnapshot = await unreadState.snapshot()
                let hookThreadIDs = Set(hookState.turns.map(\.threadID))
                hookTrackedThreadIDs = hookThreadIDs
                let containsUnlistedHookThread = hookThreadIDs.contains {
                    !listedThreadIDs.contains($0)
                }

                // Hook state is the low-latency source; App Server reads only
                // decorate it, so both refreshes stay in the background where a
                // slow request cannot hold an Idle -> Running transition.
                //
                // The two reads are deliberately split by cost. Per-thread
                // metadata covers the Hook reducer's own threads and is cheap
                // enough to follow Hook activity; the paginated full list is
                // needed only to reconcile membership, so it keeps the low
                // frequency the design calls for.
                scheduleThreadMetadataRefreshIfNeeded(for: hookThreadIDs)
                let fullListMustSupplyMetadata = !supportsThreadMetadataRead
                    && hookState.didConsumeEvents
                if containsUnlistedHookThread
                    || threadListRefreshIsDue
                    || fullListMustSupplyMetadata {
                    scheduleThreadListRefreshIfNeeded()
                }
                // A request parked by a backoff is still outstanding; this is
                // where it gets picked back up once the cool-off expires.
                startThreadListRefreshIfPossible()
                startThreadMetadataRefreshIfPossible()

                if let threadListReadAt {
                    hookState = await hookEvents.removeThreads(
                        notIn: listedThreadIDs,
                        snapshotStartedAt: threadListReadAt
                    )
                }
                let sessions = await sessions(
                    from: hookState.turns,
                    threadRecords: threadRecords,
                    projectMetadata: projectSnapshot,
                    unreadState: unreadSnapshot,
                    approvalRouting: await approvalRouting.snapshot(),
                    dismissedRowIDs: dismissedRowIDs
                )
                // The one branch that looked at every listed row and pruned the
                // gate to match. Anything it hid or dropped is hidden or
                // dropped; anything still in there is there because this pass
                // put it there.
                didEvaluateRows = true
                scheduleQuotaRefreshIfNeeded()
                return remember(
                    AgentSnapshot(
                        availability: .ready,
                        sessions: sessions.sorted(by: MonitorAggregation.rowOrder),
                        quota: cachedQuota,
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

            // No post-launch Hook observation yet. The product deliberately does
            // not reconstruct anything that started before this launch, so this
            // branch never builds sessions — it only confirms that the App
            // Server answers a real read, which separates Ready from
            // Disconnected and surfaces an unsupported protocol version.
            //
            // Reconstruction was removed rather than fixed: measured against
            // Codex CLI 0.148.0-alpha.9 with a live turn running, an
            // independent App Server reports `thread/loaded/list` empty, every
            // thread `notLoaded`, and never a single `inProgress` turn. There is
            // no supported read that answers "what is Codex Desktop doing right
            // now", so any startup list would have been a guess.
            hookTrackedThreadIDs = []
            _ = try await readAllUnarchivedThreads(
                forceRefresh: false,
                timeoutNanoseconds: nanoseconds(timing.coreRequestTimeout)
            )
            scheduleQuotaRefreshIfNeeded()
            return remember(
                AgentSnapshot(
                    availability: .ready,
                    sessions: [],
                    quota: cachedQuota,
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
                return snapshotPreservingTrustedState(
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

    /// Earliest moment a refresh could produce different output.
    ///
    /// Every deadline here must be one a refresh can actually clear. The store
    /// wakes at whatever this reports and refreshes; if the refresh leaves the
    /// deadline where it was, the same wake-up fires again immediately and the
    /// monitor spins. So each entry mirrors the exact condition its scheduler
    /// tests, and a source with no pending work reports nothing at all.
    func nextRefreshDeadline() -> Date? {
        var deadlines: [Date] = []

        // Membership reconciliation.
        if let threadListReadAt {
            deadlines.append(
                deferred(
                    threadListReadAt.addingTimeInterval(
                        timing.threadListRefreshInterval
                    ),
                    by: threadListRetryAfter
                )
            )
        }

        // Per-thread metadata, over the threads that read actually revisits --
        // and only while this Codex build supports it. The rest of
        // `threadRecords` is refreshed by the membership read above, on its own
        // interval, so measuring it here would report a deadline that comes due
        // twenty seconds before anything is scheduled to clear it.
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

        // Quota and account. A nil read date means the read is already due, and
        // the next refresh schedules it without needing a wake-up of its own.
        if let quotaReadAt {
            deadlines.append(
                deferred(
                    quotaReadAt.addingTimeInterval(timing.quotaRefreshInterval),
                    by: quotaRetryAfter
                )
            )
        }
        if let accountReadAt {
            deadlines.append(
                deferred(
                    accountReadAt.addingTimeInterval(timing.accountRefreshInterval),
                    by: quotaRetryAfter
                )
            )
        }

        // Work a backoff parked. Reported only while backing off: a pending
        // request with no cool-off is already looping, and publishing a
        // deadline the refresh cannot clear is how the loop starts spinning.
        if threadListGate.isPending, let threadListRetryAfter {
            deadlines.append(threadListRetryAfter)
        }
        if threadMetadataGate.isPending, let threadMetadataRetryAfter {
            deadlines.append(threadMetadataRetryAfter)
        }

        // Both the settling window and the floor under the unread watcher. This
        // is the one deadline here measured partly forward from now rather than
        // from when its work became due, because the row it covers is waiting
        // on the user and not on an interval that started somewhere.
        if let terminal = terminalUnreadMembershipGate.nextDeadline(
            now: clock.now(),
            screenIsAvailable: screenAvailability.isAvailable()
        ) {
            deadlines.append(terminal)
        }
        return deadlines.min()
    }

    /// A due date pushed out by its source's retry backoff.
    ///
    /// A backoff is a floor on the *next attempt*, never a reason to wake on its
    /// own: waking at a bare retry marker asks a scheduler that may have decided
    /// it has nothing to do, which leaves the marker in the past forever.
    nonisolated private func deferred(_ due: Date, by retryAfter: Date?) -> Date {
        guard let retryAfter else { return due }
        return max(due, retryAfter)
    }

    func disconnect() async {
        threadListRefreshTask?.cancel()
        threadListRefreshTask = nil
        threadListGate.reset()
        threadMetadataRefreshTask?.cancel()
        threadMetadataRefreshTask = nil
        threadMetadataGate.reset()
        pendingMetadataThreadIDs.removeAll()
        quotaRefreshTask?.cancel()
        quotaRefreshTask = nil
        terminalUnreadMembershipGate.reset()
        await client.disconnect()
    }

    func isThreadNavigable(_ threadID: String) async throws -> Bool {
        guard !threadID.isEmpty else { return false }

        try await client.connect()
        let listedThreads = try await readAllUnarchivedThreads(
            forceRefresh: true,
            timeoutNanoseconds: nanoseconds(timing.coreRequestTimeout)
        )
        return listedThreads.contains { thread in
            thread["id"]?.stringValue == threadID
                && CodexSnapshotParser.isEligibleRootThread(thread)
        }
    }

    /// Reads integration health without draining the store.
    ///
    /// Draining here would reduce payloads the snapshot path is about to look
    /// at, costing a full refresh cycle of latency for whatever it swallowed.
    ///
    /// The user asking for a re-check is one of the two moments registration
    /// health can change without this app having caused it, so the cached
    /// reading is dropped here. The other is the file changing underneath us,
    /// which the registrar watches for itself.
    func hookSetupStatus() async -> HookSetupStatus {
        await hookRegistrar.invalidateRegistration()
        return HookSetupStatus.card(
            registration: await hookRegistrar.registration(),
            hasObservedEvent: await hookEvents.observedState().hasObservedEvent
        )
    }

    func installHooks() async throws {
        try await hookRegistrar.install()
        didCompareHelperThisLaunch = true
        // The support directory exists now. On a first run the socket could not
        // bind at launch because there was nowhere to bind it; this is the
        // moment it becomes possible, and doing it here is what keeps the first
        // turn after setup from waiting out a refresh deadline.
        await prepareTransport()
    }

    func removeHooks() async throws {
        await hookEvents.resetIntegrationObservation(clearTurns: true)
        hookListener.stop()
        try await hookRegistrar.uninstall()
        observedDesktopProcessIdentifier = nil
        hookTrackedThreadIDs = []
        threadListRefreshTask?.cancel()
        threadListRefreshTask = nil
        threadListRetryAfter = nil
        threadListGate.reset()
        threadMetadataRefreshTask?.cancel()
        threadMetadataRefreshTask = nil
        threadMetadataRetryAfter = nil
        threadMetadataGate.reset()
        pendingMetadataThreadIDs.removeAll()
        lastTrustedSnapshot = nil
        terminalUnreadMembershipGate.reset()
    }

    /// Binds the socket, and writes the helper on the two occasions it can be
    /// wrong.
    ///
    /// The bind returns immediately once the descriptor is held, so repeating
    /// it costs nothing. The helper is a different matter: comparing its bytes
    /// used to sit on the refresh path as `upgradeManagedHookIfNeeded()`,
    /// reading a file to answer a question that can only change when the app
    /// itself is upgraded. So the comparison happens once per launch, and again
    /// only if a `stat` says the file has gone -- which a user emptying the
    /// support folder can cause, and which is loud when it happens: `/bin/sh`
    /// on a missing path writes to stderr, and Codex renders that as a hook
    /// error in the user's session (ADR 0013).
    private func prepareTransport() async {
        let helperIsInstalled = await hookRegistrar.isHelperInstalled
        if !didCompareHelperThisLaunch || !helperIsInstalled {
            didCompareHelperThisLaunch = true
            await hookRegistrar.prepareHelper()
        }
        hookListener.start(socketURL: hookRegistrar.socketURL)
    }

    nonisolated private func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }

    private func scheduleQuotaRefreshIfNeeded() {
        let now = clock.now()
        guard quotaRefreshTask == nil,
              quotaRetryAfter.map({ now >= $0 }) ?? true else {
            return
        }

        let accountNeedsRefresh = accountReadAt == nil
            || now.timeIntervalSince(accountReadAt ?? .distantPast)
                >= timing.accountRefreshInterval
        // The same window `nextRefreshDeadline` publishes for quota. A literal
        // here would let the wake-up and the work it wakes for disagree.
        let quotaNeedsRefresh = quotaReadAt == nil
            || now.timeIntervalSince(quotaReadAt ?? .distantPast)
                >= timing.quotaRefreshInterval
        guard accountNeedsRefresh || quotaNeedsRefresh else { return }

        quotaRefreshTask = Task { [weak self] in
            await self?.refreshQuotaInBackground()
        }
    }

    /// Tells the store that background work changed what a snapshot would say.
    ///
    /// Every background read must end in this, or its result sits in the actor
    /// until some unrelated deadline happens to fire.
    nonisolated private func invalidatePublishedSnapshot() {
        snapshotInvalidations.yield(())
    }

    private func refreshQuotaInBackground() async {
        defer {
            quotaRefreshTask = nil
            invalidatePublishedSnapshot()
        }
        do {
            _ = try await readAccountUsageIfNeeded()
            quotaRetryAfter = nil
        } catch {
            cachedQuota = .unavailable
            quotaReadAt = nil
            quotaRetryAfter = clock.now().addingTimeInterval(timing.requestRetryInterval)
        }
    }

    private func readAccountUsageIfNeeded() async throws -> QuotaSnapshot {
        let now = clock.now()
        if accountReadAt == nil
            || now.timeIntervalSince(accountReadAt ?? .distantPast)
                >= timing.accountRefreshInterval {
            let account = try await client.request(
                method: "account/read",
                params: .object(["refreshToken": .bool(false)])
            )
            let fingerprint = CodexSnapshotParser.accountFingerprint(from: account)
            accountReadAt = now
            if cachedAccountFingerprint != fingerprint {
                cachedAccountFingerprint = fingerprint
                cachedQuota = .unavailable
                quotaReadAt = nil
            }
        }

        if let quotaReadAt,
           now.timeIntervalSince(quotaReadAt) < timing.quotaRefreshInterval {
            return cachedQuota
        }

        async let rateLimitsResponse = try? await client.request(
            method: "account/rateLimits/read",
            params: .object([:])
        )
        async let tokenUsageResponse = try? await client.request(
            method: "account/usage/read",
            params: nil
        )
        let responses = await (rateLimitsResponse, tokenUsageResponse)
        let rateLimitQuota = responses.0.map {
            CodexSnapshotParser.quota(from: $0)
        }
            ?? .unavailable
        let quota = QuotaSnapshot(
            remainingPercent: rateLimitQuota.remainingPercent,
            resetsAt: rateLimitQuota.resetsAt,
            todayTokens: responses.1.flatMap {
                CodexSnapshotParser.todayTokenCount(from: $0, now: clock.now())
            }
        )
        cachedQuota = quota
        quotaReadAt = now
        return quota
    }

    private func sessions(
        from states: [HookTurnState],
        threadRecords: [String: ThreadRecord],
        projectMetadata: DesktopProjectMetadataSnapshot,
        unreadState: DesktopUnreadStateSnapshot,
        approvalRouting: DesktopApprovalRoutingSnapshot,
        dismissedRowIDs: Set<String>
    ) async -> [MonitoredSession] {
        var sessions: [MonitoredSession] = []
        // Keyed on what was actually evaluated, not on every Hook state. A
        // state whose thread turns out to be a sub-agent stops producing a
        // session at all, and keying on states kept its gate entry alive,
        // frozen mid-window, reporting a deadline that could never be cleared
        // because nothing evaluated it again.
        var evaluatedSessionIDs: Set<String> = []

        for state in states {
            // Thread records only supply metadata. Status is the reducer's
            // alone: an independent App Server reports every thread as
            // `notLoaded` even while a turn is running, so it has no runtime
            // evidence to correct with.
            guard let session = CodexSnapshotParser.session(
                from: state,
                thread: threadRecords[state.threadID]?.thread,
                projectName: projectMetadata.resolution(
                    for: state.threadID
                ).displayName,
                approvalsReachTheUser: approvalRouting.approvalsReachTheUser(
                    for: state.threadID
                )
            ) else {
                continue
            }
            // A row the user has taken off the list is not evaluated, and so
            // leaves the gate on the retain below. Read state is the only
            // question the gate asks, and that question has already been
            // answered by the user in the one way that outranks every source:
            // they said they are done with the row. Left in, its entry went on
            // booking a re-check a second for a row the panel no longer draws
            // -- each one a full snapshot, LaunchServices round trip included
            // (CR-Fable-003).
            //
            // It is still reported. Withholding it would tell the store the
            // Turn had gone, which is the one thing that makes the store forget
            // a removal -- and a forgotten removal is a dismissed row back on
            // the notch at the next hook event (CR-Fable-004).
            guard !dismissedRowIDs.contains(session.id) else {
                sessions.append(session)
                continue
            }
            evaluatedSessionIDs.insert(session.id)

            if terminalUnreadMembershipGate.shouldDisplay(
                sessionID: session.id,
                threadID: session.threadID,
                status: session.status,
                terminalBoundaryAt: state.lastEventAt,
                unreadState: unreadState,
                now: clock.now()
            ) {
                sessions.append(session)
            }
        }

        terminalUnreadMembershipGate.retain(sessionIDs: evaluatedSessionIDs)
        return sessions
    }

    private var threadListRefreshIsDue: Bool {
        guard let threadListReadAt else { return true }
        return clock.now().timeIntervalSince(threadListReadAt)
            >= timing.threadListRefreshInterval
    }

    /// Records that membership needs re-reading, and starts a read if idle.
    ///
    /// The request is recorded before the backoff is consulted, so an
    /// invalidation that arrives during a read -- or during its cool-off -- is
    /// still outstanding afterwards rather than dropped on the floor (CR-003).
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

    /// Runs one membership read; returns whether another should follow now.
    ///
    /// A failed read leaves its request outstanding and stops here; the retry
    /// is scheduled by `nextRefreshDeadline` reporting the backoff.
    private func runThreadListRefresh() async -> Bool {
        let succeeded = await refreshThreadListInBackground()
        return threadListGate.endRun(covered: succeeded)
    }

    private func clearThreadListRefreshTask() {
        threadListRefreshTask = nil
    }

    /// Refreshes thread-level metadata for the threads the Hook reducer tracks.
    ///
    /// This is the read that follows Hook activity. `thread/read` returns the
    /// same `Thread` payload as `thread/list` for a single thread, so it covers
    /// title, preview, root-thread eligibility and `status.activeFlags` at a
    /// fraction of the cost of paginating every unarchived thread.
    private func scheduleThreadMetadataRefreshIfNeeded(for threadIDs: Set<String>) {
        guard supportsThreadMetadataRead else { return }

        let now = clock.now()
        let staleThreadIDs = threadIDs.filter { threadID in
            guard let record = threadRecords[threadID] else { return true }
            return now.timeIntervalSince(record.observedAt)
                >= timing.threadMetadataRefreshInterval
        }
        guard !staleThreadIDs.isEmpty else { return }

        // Accumulated rather than replaced: threads that went stale while a
        // read was in flight belong to the next read, not to nobody.
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
        let threadIDs = pendingMetadataThreadIDs
        pendingMetadataThreadIDs.removeAll()
        guard !threadIDs.isEmpty else {
            _ = threadMetadataGate.endRun(covered: true)
            return false
        }

        let succeeded = await refreshThreadMetadataInBackground(
            threadIDs: threadIDs
        )
        if !succeeded {
            // Put them back so the retry has something to read.
            pendingMetadataThreadIDs.formUnion(threadIDs)
        }
        return threadMetadataGate.endRun(covered: succeeded)
    }

    private func clearThreadMetadataRefreshTask() {
        threadMetadataRefreshTask = nil
    }

    /// Reads metadata for `threadIDs`; returns whether the read covered them.
    ///
    /// The task handle and the loop belong to the caller now, so this reports
    /// its outcome instead of clearing state the gate owns.
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
                        // Turn history is never requested. `includeTurns` would
                        // return the thread's entire rollout — hundreds of KB
                        // for a long thread — and every Turn-level fact this
                        // product needs already comes from the Hook reducer.
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
                    // Older Codex builds fall back to whole-list metadata.
                    // Nothing more to ask for, so the request is settled.
                    supportsThreadMetadataRead = false
                    return true
                }
                if error.requiresConnectionReset {
                    await client.disconnect()
                    return false
                }
                // One unreadable thread is metadata loss, not state loss:
                // membership and Turn status both come from elsewhere.
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

    /// Reads membership; returns whether the read succeeded.
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
            $0.projectName == DesktopProjectMetadataSnapshot.unavailableProjectName
        }.count
        let unresolvedDiagnostic = unavailableCount > 0
            ? "\(unavailableCount) sessions have no verifiable Desktop Project mapping; they were not fallen back to Chats."
            : nil
        return MonitorDiagnostics.combined(metadata.diagnostic, unresolvedDiagnostic)
    }

    /// Keeps the last trusted *observation* while a request is transiently
    /// failing -- and only that.
    ///
    /// Presence and registration health are not part of what failed. Both were
    /// measured by this same refresh: presence from the running-application
    /// list, which is kernel truth and cannot time out, and setup from the
    /// registrar, which never asked the App Server anything. So both are
    /// passed in and used rather than inherited from the kept snapshot or left
    /// to the initialiser's defaults -- which claim `.open` and `.active`, and
    /// would have this branch draw a Connected mark for a Codex Desktop the
    /// user can see is not running (PRD §6.3, §12), and report a healthy
    /// integration over a `reviewRequired` the Settings row exists to surface.
    private func snapshotPreservingTrustedState(
        after error: CodexAppServerError,
        setupStatus: HookSetupStatus,
        presence: AgentPresence
    ) -> AgentSnapshot {
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

    /// Reads every unarchived thread.
    ///
    /// This is the transport's most expensive call, so it exists for exactly one
    /// job the cheap per-thread read cannot do: establishing which threads still
    /// exist. It also refreshes `threadRecords` in bulk, which keeps the whole
    /// pipeline working on builds without `thread/read`.
    private func readAllUnarchivedThreads(
        forceRefresh: Bool,
        timeoutNanoseconds: UInt64
    ) async throws -> [JSONValue] {
        if !forceRefresh,
           let threadListReadAt,
           clock.now().timeIntervalSince(threadListReadAt)
               < timing.threadListRefreshInterval {
            return listedThreadIDs.compactMap { threadRecords[$0]?.thread }
        }

        var threads: [JSONValue] = []
        var cursor: String?
        var observedCursors = Set<String>()
        let snapshotStartedAt = clock.now()

        repeat {
            var params: [String: JSONValue] = [
                "archived": .bool(false),
                "limit": .number(100),
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
                guard observedCursors.insert(cursor).inserted else {
                    throw CodexAppServerError.protocolViolation(
                        "thread/list returned a repeated cursor"
                    )
                }
                params["cursor"] = .string(cursor)
            }

            let page = try await client.request(
                method: "thread/list",
                params: .object(params),
                timeoutNanoseconds: timeoutNanoseconds
            )
            threads.append(contentsOf: page["data"]?.arrayValue ?? [])
            cursor = page["nextCursor"]?.stringValue
        } while cursor != nil

        // Use the request start, not completion, as the freshness boundary.
        // A Hook can arrive while a slow paginated list is still in flight.
        let listedIDs = Set(threads.compactMap { $0["id"]?.stringValue })
        for thread in threads {
            guard let threadID = thread["id"]?.stringValue else { continue }
            // A newer single-thread read must not be overwritten by an older
            // list that happened to finish after it.
            if let existing = threadRecords[threadID],
               existing.observedAt > snapshotStartedAt {
                continue
            }
            threadRecords[threadID] = ThreadRecord(
                thread: thread,
                observedAt: snapshotStartedAt
            )
        }
        threadRecords = threadRecords.filter { listedIDs.contains($0.key) }
        listedThreadIDs = listedIDs
        threadListReadAt = snapshotStartedAt
        return threads
    }

    /// Drops the Hook evidence held for a Desktop process that is not the one
    /// running now, along with the reads that were following it.
    ///
    /// The binding goes with the Turns: nothing is left that a later pid could
    /// be matched against, so the next process starts from an empty reducer and
    /// binds itself with its own first event. `hookTrackedThreadIDs` goes too
    /// -- it is what `nextRefreshDeadline()` measures per-thread metadata
    /// staleness over, and threads whose Turn has been retired must stop asking
    /// to be re-read.
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

    @MainActor
    private static func desktopProcessIdentifier() -> pid_t? {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.openai.codex"
        ).first(where: { !$0.isTerminated })?.processIdentifier
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

    nonisolated static func quota(from response: JSONValue) -> QuotaSnapshot {
        guard let primary = response["rateLimits"]?["primary"],
              let usedPercent = primary["usedPercent"]?.intValue else {
            return .unavailable
        }

        let resetDate = primary["resetsAt"]?.doubleValue.map {
            Date(timeIntervalSince1970: $0)
        }
        return QuotaSnapshot(
            remainingPercent: 100 - usedPercent,
            resetsAt: resetDate
        )
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

        // `threadSource == user` is the public root-thread discriminator in the
        // current schema. A missing value is tolerated because older versions do
        // not populate it in thread/list; thread/read normally supplies it.
        if let source = thread["threadSource"]?.stringValue {
            return source == "user"
        }
        return true
    }

    // A Thread-only session builder used to live here so a launch could
    // reconstruct whatever Codex Desktop was already doing. That capability is
    // out of scope: sessions now only ever originate from a Hook received after
    // this process started, so there is no caller that builds a session from a
    // Thread payload alone.

    /// Builds a display row for a Turn the Hook reducer already owns.
    ///
    /// `thread` contributes presentation only — eligibility, title, preview.
    /// Status and timing come from the reducer, because no field of a Thread
    /// payload carries Turn-level runtime truth for this topology.
    ///
    /// `approvalsReachTheUser` is the one exception, and it subtracts rather
    /// than adds: the reducer proves a permission pipeline opened over a call
    /// that is still open, which on a thread reviewed by Codex itself is not a
    /// person being asked anything. See
    /// ``CodexDesktopApprovalRoutingRepository``. It defaults to the answer
    /// that changes nothing, so a caller with no evidence keeps every state
    /// the reducer reached.
    nonisolated static func session(
        from state: HookTurnState,
        thread: JSONValue?,
        projectName: String,
        approvalsReachTheUser: Bool = true
    ) -> MonitoredSession? {
        if let thread, !isEligibleRootThread(thread) {
            return nil
        }

        let threadPreview = normalizedPreview(thread?["preview"]?.stringValue)
        let title = normalizedTitle(thread?["name"]?.stringValue)
            ?? threadPreview
            ?? normalizedPreview(state.promptPreview)
            ?? "Untitled"
        // Only the approval wait is answered elsewhere. `request_user_input`
        // still asks the person -- the automatic reviewer decides approvals
        // and nothing else -- so Input needed is left exactly as it was.
        let status = approvalsReachTheUser || state.status != .approvalNeeded
            ? state.status
            : .running
        let preview = status == .completed
            ? normalizedPreview(state.assistantPreview)
            : normalizedPreview(state.promptPreview)

        return MonitoredSession(
            threadID: state.threadID,
            turnID: state.turnID,
            projectName: projectName,
            title: title,
            preview: preview,
            status: status,
            startedAt: state.startedAt,
            runningSubagentCount: state.runningSubagentIDs.count
        )
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
