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
    ///
    /// `thread` is nil when the App Server *answered* that it has no such
    /// thread. That is a different fact from having no record at all -- one is
    /// "not asked yet", the other is "asked, and the answer was no" -- and only
    /// the second one settles anything: it is what stops this service asking
    /// again in a loop, and what keeps a thread Codex will never list from
    /// re-paginating the user's whole history on every refresh.
    private struct ThreadRecord: Sendable {
        let thread: JSONValue?
        let observedAt: Date

        /// Whether the App Server answered with a thread this app can address.
        var isAddressable: Bool { thread != nil }
    }

    /// What one turn had most recently said when it was last read.
    ///
    /// `text` is deliberately allowed to survive a read that found nothing.
    /// A page of the newest items is a window, not the whole turn, and a turn
    /// that runs a long command produces items that push its last words out of
    /// that window -- but those words are still the step it is on. Only the
    /// turn changing clears them, and the turn changing replaces the record
    /// outright.
    private struct TurnProgress: Sendable {
        let turnID: String
        var text: String?
        /// The turn's own `lastEventAt` when this read was *issued*.
        ///
        /// The issue stamp rather than the completion stamp, for the reason
        /// ``ThreadRecord/observedAt`` uses the same one: an event that lands
        /// while the read is in flight must still count as unread-for, or the
        /// text it announced would wait for the event after it.
        var readAtEventStamp: Date
    }

    /// One outstanding progress read.
    private struct TurnProgressRequest: Sendable {
        let turnID: String
        let eventStamp: Date
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
    /// When `thread/list` last answered, for either of the two jobs it does.
    ///
    /// Separate from ``threadListReadAt`` because the two questions are: that
    /// one is "how fresh is the membership set", this one is "does the
    /// transport answer a real read". The no-hook branch asks only the second,
    /// with a call bounded to one row, and must never leave a mark that says
    /// the membership set was re-read -- a truncated `listedThreadIDs` with a
    /// current timestamp would retire live Hook Turns whose thread it did not
    /// happen to contain.
    ///
    /// It is a ceiling on how often the confirmation is bought, never a reason
    /// to wake: nothing is published for it in `nextRefreshDeadline()`, so it
    /// rides on the wake-ups quota already causes.
    private var threadListAnsweredAt: Date?
    private var threadListGate = SingleFlightGate()
    private var threadListRefreshTask: Task<Void, Never>?
    private var threadListRetryAfter: Date?
    private var threadMetadataGate = SingleFlightGate()
    private var threadMetadataRefreshTask: Task<Void, Never>?
    private var threadMetadataRetryAfter: Date?
    /// Threads a metadata read was asked for but has not yet covered.
    private var pendingMetadataThreadIDs: Set<String> = []
    private var supportsThreadMetadataRead = true
    /// The newest thing each unfinished turn has said, by thread.
    ///
    /// This is the row's live progress on this product, and it is read rather
    /// than received: no Codex hook carries assistant text before the turn ends
    /// -- `last_assistant_message` is on `stop.command.input` and
    /// `subagent-stop.command.input` and nowhere else, checked against the
    /// schemas the CLI itself ships (0.149.0-alpha.4.3). Without it a Running
    /// row shows the prompt the user typed for the whole turn, which is the one
    /// thing about the turn that cannot change.
    private var turnProgressByThreadID: [String: TurnProgress] = [:]
    private var turnProgressGate = SingleFlightGate()
    private var turnProgressRefreshTask: Task<Void, Never>?
    private var turnProgressRetryAfter: Date?
    /// Turns a progress read was asked for but has not yet covered, by thread.
    private var pendingProgressReads: [String: TurnProgressRequest] = [:]
    /// Threads that answered `thread/items/list` with "method not found".
    ///
    /// **Per thread rather than per server, because the refusal is.** Codex
    /// answers `-32601 "thread/items/list is not supported yet"` for a thread
    /// whose `historyMode` is `legacy`, and `paginated` threads on the same
    /// server answer it fine -- measured 2026-08-25 against CLI
    /// `0.149.0-alpha.4.3`, where a thread started without
    /// `historyMode: "paginated"` refused while every thread Codex Desktop had
    /// created answered. Held server-wide, one legacy thread would have taken
    /// the live progress off every other row in the panel.
    ///
    /// A Codex with no such method at all lands here too, one refused call per
    /// thread rather than one per run. That is the whole cost of not telling
    /// the two cases apart by their message text.
    private var threadsWithoutItemsRead: Set<String> = []
    private var observedDesktopProcessIdentifier: pid_t?
    private var quotaRefreshTask: Task<Void, Never>?
    private var quotaRetryAfter: Date?
    /// Cool-off after a connect that never reached a working transport.
    ///
    /// The one backoff here that guards a subprocess rather than a request. See
    /// ``connectToAppServer()``.
    private var connectRetryAfter: Date?
    /// Why the last connect failed, replayed for the refreshes the cool-off
    /// turns away.
    private var lastConnectFailure: (any Error)?
    private var lastTrustedSnapshot: AgentSnapshot?
    /// Whether this run has already compared the installed helper's bytes.
    private var didCompareHelperThisLaunch = false
    private var terminalUnreadMembershipGate: TerminalUnreadMembershipGate
    /// The routing answer each live Turn started under.
    ///
    /// The snapshot beside it says what Desktop records for the thread *now*,
    /// which stops being an answer about this row the moment the reviewer is
    /// changed under a running turn. See ``TurnApprovalRoutingPin``.
    private var approvalRoutingPin = TurnApprovalRoutingPin()

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
            try await connectToAppServer()
            appServerResponded = true
            let projectSnapshot = await projectMetadata.snapshot()

            if hasLiveHookObservation {
                let unreadSnapshot = await unreadState.snapshot()
                let hookThreadIDs = Set(hookState.turns.map(\.threadID))
                hookTrackedThreadIDs = hookThreadIDs
                // A thread the last sweep did not carry is a reason to sweep
                // again -- unless the App Server has already answered that it
                // has no such thread. Re-paginating the user's whole history to
                // look for a thread its owner says does not exist buys nothing,
                // and a Codex side chat would otherwise ask for that sweep on
                // every refresh for as long as it ran.
                let containsUnlistedHookThread = hookThreadIDs.contains { threadID in
                    guard !listedThreadIDs.contains(threadID) else { return false }
                    guard let record = threadRecords[threadID] else { return true }
                    return record.isAddressable
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
                // After the reconciliation above, so a turn this refresh is
                // about to drop is never asked about -- and, like the two reads
                // above it, in the background: what it fetches is the row's
                // third line, and a slow request for it must not hold up the
                // status the first two lines carry.
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
            //
            // The confirmation is one bounded page, not the membership sweep
            // (CR-Fable-023). The sweep answered this question by accident and
            // charged the whole user history for it: nothing here consumes a
            // membership set -- sessions cannot exist without a live Hook, by
            // rule -- so with Codex Desktop closed all day the App Server was
            // re-paginating every unarchived thread every thirty seconds to
            // answer "does the transport work", for data no layer would read.
            hookTrackedThreadIDs = []
            // And the reads that only the live-Hook branch can consume or clear
            // go with it. A membership or metadata request parked by a backoff
            // publishes its retry marker as a deadline, and nothing reachable
            // from here picks it back up: the store would wake at the marker,
            // find it still in the past, and spin at the refresh floor for as
            // long as Desktop stayed shut. Same shape as CR-Fable-050, one
            // branch further down.
            stopThreadReadsWithNoConsumer()
            try await confirmAppServerAnswersReads(
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

    /// Brings the App Server transport up, behind a cool-off after a failure.
    ///
    /// This is the only backoff in this service that guards a *subprocess*.
    /// Every other one parks a request on a transport that already exists; a
    /// connect in the `.disconnected` phase forks and execs `codex app-server`
    /// before it can find out whether that was going to work.
    ///
    /// So the failure it exists for is not a slow server, it is a broken one. A
    /// `codex` that launches and exits -- a version mismatch after Codex
    /// updates underneath a running app, a partially-installed binary -- ends
    /// its stream immediately and fails the connect in milliseconds. Nothing
    /// then throttles the next attempt: `fetchSnapshot` connects unconditionally
    /// once the registration gate passes, and a refresh reaches every product
    /// no matter which one asked for it. One Claude Code row waiting on the
    /// user re-checks at 1 Hz, and that alone was enough to fork a Codex app
    /// server every second, for as long as the app stayed open (CR-Fable-014).
    ///
    /// The cool-off is a floor on the *attempt*, not a suppression of the
    /// answer: the refresh it turns away still reports the failure, replayed
    /// from the connect that actually happened, so the notch says the same
    /// thing it would have said had this refresh paid for a spawn to be told
    /// it again.
    ///
    /// - Parameter bypassingCoolOff: For a connect the user asked for by
    ///   clicking something. A cool-off is a budget on work nobody is waiting
    ///   for; a click is somebody waiting. The attempt still records its
    ///   outcome, so a click that succeeds clears the backoff for everyone and
    ///   a click that fails does not shorten it.
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

    /// Earliest moment a refresh could produce different output.
    ///
    /// Every deadline here must be one a refresh can actually clear. The store
    /// wakes at whatever this reports and refreshes; if the refresh leaves the
    /// deadline where it was, the same wake-up fires again immediately and the
    /// monitor spins. So each entry mirrors the exact condition its scheduler
    /// tests, and a source with no pending work reports nothing at all.
    func nextRefreshDeadline() -> Date? {
        var deadlines: [Date] = []

        // Membership reconciliation, and only while a Hook-tracked Turn gives
        // the set a consumer (CR-Fable-023).
        //
        // The condition mirrors its scheduler exactly, like every other entry
        // here: the re-read is reachable only from the live-Hook branch, so
        // with no Hook observation this deadline is one no refresh can clear --
        // the store would wake at it, find it unmoved, and spin. It is also the
        // honest answer on its own terms. `threadRecords` decorates Hook Turns
        // and `removeThreads(notIn:)` reconciles them; with none of them held,
        // re-paginating the user's whole history buys nothing anyone reads.
        // Freshness is a ceiling on how stale an answer may get, not a reason
        // to buy one nobody asked for (CR-Fable-002).
        //
        // Nothing is lost when a Turn does appear: a Hook naming a thread the
        // last list did not carry schedules a read on the spot, and a Hook
        // event is itself a wake-up.
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
        if turnProgressGate.isPending, let turnProgressRetryAfter {
            deadlines.append(turnProgressRetryAfter)
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
        stopThreadReadsWithNoConsumer()
        // The text goes with the connection that answered for it. It is a fact
        // about a turn that is still running, and this call is the app deciding
        // it no longer knows what is running.
        turnProgressByThreadID.removeAll()
        // And so does the refusal: it was this server's answer about this
        // thread, and the next connection is entitled to be asked again.
        threadsWithoutItemsRead.removeAll()
        // And so does the confirmation that it answers reads at all: the next
        // connection is a different process, and may be a different build.
        threadListAnsweredAt = nil
        quotaRefreshTask?.cancel()
        quotaRefreshTask = nil
        terminalUnreadMembershipGate.reset()
        connectRetryAfter = nil
        lastConnectFailure = nil
        await client.disconnect()
    }

    func isThreadNavigable(_ threadID: String) async throws -> Bool {
        guard !threadID.isEmpty else { return false }

        // The user clicked a row. Whatever the last refresh concluded about the
        // server, this is worth one spawn to find out for certain.
        try await connectToAppServer(bypassingCoolOff: true)
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
        stopThreadReadsWithNoConsumer()
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
        // Every Turn this pass walked, whether or not it produced a row: the
        // pin is retained on what the reducer still holds, not on what the
        // panel happens to draw.
        var observedTurns: Set<TurnApprovalRoutingPin.TurnIdentity> = []

        for state in states {
            let turn = TurnApprovalRoutingPin.TurnIdentity(
                threadID: state.threadID,
                turnID: state.turnID
            )
            observedTurns.insert(turn)
            // Asked for every Turn rather than only for the ones sitting on an
            // approval, because the question is what this Turn *started* under
            // and a Turn that has reached Approval needed is already too late
            // to ask it.
            let approvalsReachTheUser = approvalRoutingPin.approvalsReachTheUser(
                forTurn: turn,
                in: approvalRouting
            )
            // Pinned to the turn it was read for. A record left over from
            // the turn before this one describes work that has already
            // finished, and the row must not present it as what is happening
            // now.
            let liveProgress = turnProgressByThreadID[state.threadID]
                .flatMap { $0.turnID == state.turnID ? $0.text : nil }
            // Status is the reducer's alone: an independent App Server reports
            // every thread as `notLoaded` even while a turn is running, so it
            // has no runtime evidence to correct with. The thread record is
            // what says the row may exist at all -- both "not asked yet" and
            // "asked, and Codex has no such thread" arrive here as no payload,
            // and neither is grounds for a row (see
            // ``CodexSnapshotParser/session(from:thread:projectName:approvalsReachTheUser:liveProgress:)``).
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

            // The gate asks whether this thread is still working, so it is
            // given that answer rather than the row's own status: a finished
            // row with a subagent still in flight takes the running path --
            // shown outright, entry dropped, no re-check booked -- and the row
            // carrying the only evidence that anything is still running cannot
            // be erased a settling interval after the main agent's `Stop`.
            //
            // Its boundary moves with it. Once the last subagent stops the row
            // is terminal again, and the window has to start from that instant
            // instead of from a `Stop` that may be minutes old, or the row
            // disappears the moment it stops saying anything is working.
            if terminalUnreadMembershipGate.shouldDisplay(
                sessionID: session.id,
                threadID: session.threadID,
                status: MonitorAggregation.effectiveStatus(of: session),
                terminalBoundaryAt: state.terminalBoundaryAt,
                unreadState: unreadState,
                now: clock.now()
            ) {
                sessions.append(session)
            }
        }

        terminalUnreadMembershipGate.retain(sessionIDs: evaluatedSessionIDs)
        approvalRoutingPin.retain(turns: observedTurns)
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

    // MARK: - Live progress

    /// How many of a turn's newest items one progress read asks for.
    ///
    /// A window, and a small one on purpose. Every item in the page is decoded,
    /// and a `commandExecution` item carries its own `aggregatedOutput` --
    /// measured over the 381 command items in this machine's rollouts, the
    /// largest is 290 KB, so the page size is also the multiplier on the worst
    /// case. Six is enough to see past the reasoning and command items Codex
    /// interleaves between two things it says (measured against
    /// 0.149.0-alpha.4.3: at most four such items separated two consecutive
    /// `agentMessage`s across three instrumented turns), and a message that
    /// does fall out of the window is not lost -- ``TurnProgress/text`` keeps
    /// the last one that was seen.
    private static let turnProgressItemLimit = 6

    /// Records which unfinished turns need their progress re-read.
    ///
    /// Keyed on the turn's own `lastEventAt` rather than on a clock interval:
    /// this read has nothing to say until the turn does something, and the
    /// events that move that stamp are the same ones the reducer wakes the
    /// refresh for. So a turn sitting on a ten-minute command is read once and
    /// then left alone, and a turn calling tools in a burst is read once per
    /// call rather than once per second.
    private func scheduleTurnProgressRefreshIfNeeded(for states: [HookTurnState]) {
        // Whatever the reducer still holds, finished or not: the pruning below
        // is against the threads that exist, not against the ones being read.
        let liveThreadIDs = Set(states.map(\.threadID))
        turnProgressByThreadID = turnProgressByThreadID.filter {
            liveThreadIDs.contains($0.key)
        }
        pendingProgressReads = pendingProgressReads.filter {
            liveThreadIDs.contains($0.key)
        }
        threadsWithoutItemsRead.formIntersection(liveThreadIDs)

        for state in states {
            // A finished turn already has its own last word, carried by the
            // `Stop` that ended it. Asking the App Server for it again would
            // be a request for something this process was handed.
            guard state.status != .completed else { continue }
            // A thread that has already refused is not asked twice.
            guard !threadsWithoutItemsRead.contains(state.threadID) else { continue }
            // Neither is one the App Server has said it does not have. This
            // read fetches the third line of a row that is not being drawn.
            if let record = threadRecords[state.threadID], !record.isAddressable {
                continue
            }
            let held = turnProgressByThreadID[state.threadID]
            if held?.turnID == state.turnID,
               held?.readAtEventStamp == state.lastEventAt {
                continue
            }
            // Replaced rather than accumulated, unlike the metadata read: a
            // second request for the same thread is the same question asked
            // about a later moment, and only the later answer is wanted.
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
        let requests = pendingProgressReads
        pendingProgressReads.removeAll()
        guard !requests.isEmpty else {
            _ = turnProgressGate.endRun(covered: true)
            return false
        }

        let succeeded = await refreshTurnProgressInBackground(requests: requests)
        if !succeeded {
            // Put back only what a later request has not already superseded.
            for (threadID, request) in requests where pendingProgressReads[threadID] == nil {
                pendingProgressReads[threadID] = request
            }
        }
        return turnProgressGate.endRun(covered: succeeded)
    }

    private func clearTurnProgressRefreshTask() {
        turnProgressRefreshTask = nil
    }

    /// Reads the newest thing each of these turns has said.
    ///
    /// Returns whether the read covered them, on the same terms as the metadata
    /// read beside it: one unreadable turn is a line of text missing from one
    /// row, and every other fact about that row comes from somewhere else.
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
                        // Scoped to the turn the reducer owns, and never
                        // widened to the thread. Without it a turn that has not
                        // said anything yet answers with the *previous* turn's
                        // closing words, which is the row confidently
                        // describing work that is over.
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
                    // A window that found nothing keeps what the last one saw.
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
                    // Two different absences arrive as the same code, and both
                    // are expected answers rather than faults: a thread whose
                    // `historyMode` is `legacy` (`thread/items/list is not
                    // supported yet`), and a Codex without this experimental
                    // method at all. Recorded against the thread either way --
                    // see ``threadsWithoutItemsRead`` for why the difference is
                    // not worth reading out of the message text. This row falls
                    // back to the prompt preview, which is what every Codex row
                    // showed before this read existed.
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
                // Every other remote error is the App Server *answering* about
                // this thread: it took the request and rejected it. Recording
                // the refusal is what makes it worth something -- an ephemeral
                // thread refuses forever, and without a record this read is
                // reissued on every refresh and the membership sweep is
                // requested alongside it. It is deliberately not read for its
                // wording or its code: whatever the reason, a thread the App
                // Server will not hand over is one this app cannot address.
                //
                // The distinction that matters is against the errors above and
                // below -- a reset transport and a timeout answered nothing, so
                // they leave no record and the next refresh asks again.
                if case .remote = error {
                    threadRecords[threadID] = ThreadRecord(
                        thread: nil,
                        observedAt: startedAt
                    )
                    // And it counts as a read, so a batch of nothing but
                    // refusals does not park every later metadata read behind
                    // a request-failure cool-off. A row now waits on this read,
                    // so a side chat must not be able to delay a real thread's
                    // row by a minute.
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

    /// One page of `thread/list`, asked for only to see it answered.
    ///
    /// This is what the no-hook branch needs and the whole of it: a real read,
    /// on the same method and the same parameter shape the membership sweep
    /// uses, so a Codex that does not support it fails here exactly as it would
    /// there and the branch can report `unsupportedVersion` rather than an
    /// empty Ready. One row is enough to be answered; the rows themselves are
    /// discarded unread.
    ///
    /// Nothing it learns is written into the membership caches. A first page is
    /// not the membership set, and a truncated `listedThreadIDs` stamped with a
    /// current `threadListReadAt` would make the next live-Hook refresh retire
    /// every Turn whose thread did not happen to be on it.
    ///
    /// The freshness window is a ceiling, not a cadence: `nextRefreshDeadline()`
    /// never wakes for it, so the confirmation is bought only when a refresh
    /// was going to happen anyway. Its consumer is the collapsed mark --
    /// Connected against Disconnected -- which is what separates it from the
    /// membership set, whose consumers are all in the live-Hook branch.
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

    /// One page's worth of `thread/list` parameters.
    ///
    /// Shared by the membership sweep and the bounded confirmation so the two
    /// present the same request to the server and differ only in how much they
    /// ask for. A confirmation that narrowed the shape as well as the size
    /// could be answered by a build whose real `thread/list` this app cannot
    /// use.
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

    /// Drops the reads only a live Hook observation can consume or clear.
    ///
    /// Called from the branch that has no such observation. Membership and
    /// per-thread metadata are both scheduled from the live-Hook branch alone,
    /// so a request left outstanding here has nobody to run it and a backoff
    /// marker left behind it has nobody to clear it -- and
    /// `nextRefreshDeadline()` publishes a parked request's marker as a wake-up.
    ///
    /// Only the pending work is dropped, not what it had already read: the
    /// cached thread metadata is still the best answer there is about those
    /// threads, and the next Hook to name one is entitled to draw a title
    /// immediately rather than after a round trip.
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
        turnProgressRefreshTask?.cancel()
        turnProgressRefreshTask = nil
        turnProgressGate.reset()
        turnProgressRetryAfter = nil
        pendingProgressReads.removeAll()
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
        threadRecords = threadRecords.filter { threadID, record in
            if listedIDs.contains(threadID) { return true }
            // A refusal survives the sweep that could never have carried it.
            // Dropping it here would restore exactly the loop it exists to
            // stop: the thread goes back to "not asked yet", the next refresh
            // asks again and requests another full pagination alongside. It is
            // kept only while a Turn still names the thread, so the set cannot
            // outgrow what the reducer holds.
            return !record.isAddressable
                && hookTrackedThreadIDs.contains(threadID)
        }
        listedThreadIDs = listedIDs
        threadListReadAt = snapshotStartedAt
        // The sweep answers the transport's question too, so a Desktop that
        // quits just after one does not pay for a confirmation of what was
        // confirmed a moment ago.
        threadListAnsweredAt = snapshotStartedAt
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
    /// `thread` decides eligibility and supplies title and preview; status and
    /// timing come from the reducer, because no field of a Thread payload
    /// carries Turn-level runtime truth for this topology.
    ///
    /// **A Turn with no Thread payload gets no row.** Eligibility fails closed
    /// here rather than open: "the App Server has not handed us this thread" is
    /// not evidence that it is a navigable root thread, and a row is a promise
    /// that clicking it goes somewhere. Codex Desktop runs threads it never
    /// materialises -- the one the user meets is a side chat, and Desktop
    /// starts others of its own -- and such a thread is absent from
    /// `thread/list`, refused by `thread/read`, and unreachable by deep link.
    /// Failing open drew a row for the ones that fire Turn hooks: no Project,
    /// no way back, and gone again a reconciliation grace later. Nothing is
    /// lost on a real thread, which is already written to disk before its first
    /// Hook fires (measured 2026-08-25, CLI `0.149.0-alpha.4.3`: at
    /// `UserPromptSubmit` the rollout exists and an independent App Server
    /// reads the thread), so the wait this adds is one local `thread/read`.
    ///
    /// `approvalsReachTheUser` is the one exception, and it subtracts rather
    /// than adds: the reducer proves a permission pipeline opened over a call
    /// that is still open, which on a thread reviewed by Codex itself is not a
    /// person being asked anything. See
    /// ``CodexDesktopApprovalRoutingRepository``. It defaults to the answer
    /// that changes nothing, so a caller with no evidence keeps every state
    /// the reducer reached.
    ///
    /// `liveProgress` is the newest thing this turn has said, read from the App
    /// Server against this exact turn. It defaults to absent, which is the
    /// answer that leaves a Running row showing the prompt it started from --
    /// what every Codex row showed before that read existed, and what one still
    /// shows on a Codex that cannot answer it.
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
        let title = normalizedTitle(thread["name"]?.stringValue)
            ?? threadPreview
            ?? normalizedPreview(state.promptPreview)
            ?? "Untitled"
        // Only the approval wait is answered elsewhere. `request_user_input`
        // still asks the person -- the automatic reviewer decides approvals
        // and nothing else -- so Input needed is left exactly as it was.
        let status = approvalsReachTheUser || state.status != .approvalNeeded
            ? state.status
            : .running
        // The same subtraction, for the same reason, on the thread's subagents.
        // A subagent inherits the thread's reviewer: measured 2026-08-23 over
        // the 119 rollouts on one machine, every one of the 72 subagent
        // rollouts whose parent was also on disk carried the parent's
        // `approvals_reviewer` as it stood when the subagent was spawned, with
        // both values represented. So on a thread Codex reviews itself, a
        // subagent's `PermissionRequest` is not a person being asked either.
        let subagentsAwaitingApprovalCount = approvalsReachTheUser
            ? state.subagentsAwaitingApprovalCount
            : 0
        // A finished turn's last word is carried by the `Stop` that ended it,
        // which is the turn's own answer and needs no read. An unfinished one
        // shows the step it is on, and falls back to the prompt only when
        // nothing has been read for it yet -- the first seconds of a turn, a
        // Codex without `thread/items/list`, or a read that failed.
        let preview = status == .completed
            ? normalizedPreview(state.assistantPreview)
            : (normalizedPreview(liveProgress) ?? normalizedPreview(state.promptPreview))

        return MonitoredSession(
            threadID: state.threadID,
            turnID: state.turnID,
            projectName: projectName,
            title: title,
            preview: preview,
            status: status,
            startedAt: state.startedAt,
            runningSubagentCount: state.runningSubagentIDs.count,
            subagentsAwaitingApprovalCount: subagentsAwaitingApprovalCount
        )
    }

    /// The item type Codex files an assistant message under.
    nonisolated static let agentMessageItemType = "agentMessage"

    /// The newest assistant message in one `thread/items/list` page.
    ///
    /// The page is requested newest-first, so this is the first match rather
    /// than the last. Every other item type is skipped rather than described:
    /// the row reports what the agent *said* it is doing, which is the same
    /// thing Claude Code's row reports, and a tool name is neither the agent's
    /// words nor a sentence.
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
