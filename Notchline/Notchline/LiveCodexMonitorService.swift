import Foundation

actor LiveCodexMonitorService: AgentMonitoring, IntegrationConfiguring, AnswerDelivering,
    DiskFootprintReporting, CodexNavigationTargetChecking {
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
    ///
    /// A third fact never reaches this table at all: a thread the product's own
    /// hooks say it is writing down nowhere is not asked about, so it has no
    /// record and needs none (``HookTurnState/threadHasNoTranscript``). It
    /// settles what a refusal settles, one round trip earlier, and leaving the
    /// record absent is what keeps a thread nothing will ever re-read out of
    /// the metadata staleness `nextRefreshDeadline()` measures.
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
    /// The hook transport, wired once (``HookLifecycleSource``) with Codex's
    /// registrar as its setup. The reducer and the registrar are kept under
    /// their own names as well: this actor reads the one constantly, and asks
    /// the other what only a trust-step policy has -- the cached registration
    /// and the file's own edge.
    private let hooks: HookLifecycleSource
    private let hookEvents: HookEventRepository
    private let hookRegistrar: CodexHookRegistrar
    private let projectMetadata: any DesktopProjectMetadataProviding
    private let unreadState: any DesktopUnreadStateProviding
    /// Which threads Codex answers approval requests for on the user's behalf.
    ///
    /// A decision spanning two sources, so it is made here rather than in the
    /// reducer: the reducer sees only that a permission pipeline opened over a
    /// call that is still open, which is as true of a request the automatic
    /// reviewer is deciding as of one a person is looking at.
    private let approvalRouting: any DesktopApprovalRoutingProviding
    /// The reviewer each running Turn was handed, read from its own rollout.
    ///
    /// Consulted ahead of `approvalRouting`, which is Desktop's copy of the
    /// thread's current setting and lags a switch by however long Desktop takes
    /// to persist one.
    private let turnReviewer: any TurnReviewerReading
    /// Whether a Turn this app still holds open was stopped by the user, and
    /// which Turn that thread's rollout says it is on.
    ///
    /// The Codex half of [ADR 0011](../../docs/adr/0011-a-turn-may-end-on-evidence-that-is-not-a-hook-event.md):
    /// pressing stop sends no `Stop` and no `PostToolUse` for the call left
    /// open, so without this the row says *Running* until the user resumes that
    /// thread or waves the row away. The same rollout the reviewer is read
    /// from carries the answer — see ``CodexRolloutTurnAbortReader``.
    ///
    /// **One reader, two questions, one read.** They are the two halves of what
    /// a file can settle about a Turn this app is holding open — whose it is
    /// and whether it is over — and both are answered from the same cached tail
    /// of the same rollout, so the second costs nothing the first had not
    /// already spent. See ``CodexTurnOnRecordReading`` for the identity half.
    private let turnAbort: any CodexTurnAbortReading & CodexTurnOnRecordReading
    /// The rollouts of the Turns that are still going, and nothing else.
    ///
    /// The edge under the reading above, and the same shape as the Claude Code
    /// side's `transcriptWatcher`: an abort appends a record to a file inside a
    /// directory, which produces no directory-level event, so the file itself
    /// is watched. Without it the abort waits for whatever wakes this service
    /// next — at best the metadata interval, and on a thread that had gone
    /// quiet, the heartbeat.
    ///
    /// **Pointed at open Turns only.** A finished row's rollout is not watched,
    /// and neither is a thread this app has no live Turn for, so a quiet
    /// monitor still watches nothing at all. What it costs while a Turn runs is
    /// one wake-up per append, and a Codex turn appends 0.17–0.3 records a
    /// second over its life (measured over this machine's rollouts, with bursts
    /// to ~6/s that the debounce collapses).
    ///
    /// It reads nothing itself: an edge means *this file changed*, and the
    /// refresh it wakes is what asks the reader the question.
    ///
    /// Not private, so a test can state what is watched and for how long.
    nonisolated let rolloutWatcher: PathSetChangeWatcher
    /// Whether there is a screen the user could read this app's output on.
    ///
    /// Two things consult it, both because the work behind them is only worth
    /// buying for somebody who can look at the result. The unread gate's
    /// re-check: a row Desktop still reports unread is cleared by somebody
    /// opening it in Desktop, which a locked screen makes impossible -- see
    /// ``TerminalUnreadMembershipGate/nextDeadline(now:screenIsAvailable:)``.
    /// And the account and quota reads, whose figures are drawn only in a
    /// footer the user reaches by hovering the notch -- see
    /// ``CodexUsageReader/readIfStale()``.
    nonisolated private let screenAvailability: any ScreenAvailabilityReporting
    /// The account and its quota, read over the App Server on a clock of their
    /// own (``UsageReading``).
    private let usage: CodexUsageReader
    nonisolated let stateChangeEvents: AsyncStream<Void>
    nonisolated private let snapshotInvalidations: AsyncStream<Void>.Continuation
    /// Whether Codex Desktop is running, and as which process.
    ///
    /// One reading answers both, because the pid is what binds hook evidence to
    /// the process that vouched for it and the presence drawn beside it must
    /// describe the same instant (``RunningApplicationPresence``).
    private let presence: RunningApplicationPresence
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
    /// Threads a metadata read has been *issued* for, until it answers.
    ///
    /// The same window ``inFlightProgressReads`` covers, on the read beside it:
    /// ``ThreadRecord`` is written when the answer arrives, so a refresh that
    /// runs re-entrant with the read finds no record, calls the thread stale
    /// and queues it again -- and that question is dispatched the moment the
    /// read in flight ends, by which point the answer it was asking for is in
    /// hand and good for the next ten seconds.
    ///
    /// Narrower than the progress read's version of the same hole, because the
    /// membership read writes every listed thread's record in bulk: on a fast
    /// `thread/list` that record lands part-way through the single-thread read
    /// and the re-queue never happens. It is the slow list -- the case
    /// pagination exists to be -- that leaves the window open.
    private var inFlightMetadataThreadIDs: Set<String> = []

    /// The Turn each thread's path was last asked about, and nothing else.
    ///
    /// A thread's rollout path is not a fixed property of the thread: Codex
    /// writes a Turn resumed after an interrupt into a new file, and the
    /// reviewer this app reads out of that file is read once, at the moment
    /// the Turn opens. So a Turn new to this thread asks for the path again
    /// instead of waiting out the refresh interval -- once, which is what this
    /// records. See
    /// ``scheduleThreadMetadataRefreshIfNeeded(for:)``.
    private var metadataReadTurnIDsByThreadID: [String: String] = [:]
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
    /// Turns a progress read has been *issued* for, by thread, until it answers.
    ///
    /// The queue above empties the moment a run picks it up, and
    /// ``TurnProgress`` is not written until the answer comes back -- so
    /// between those two moments nothing in this actor said the question had
    /// been asked. The read is an `await` on another actor, every refresh in
    /// that window is re-entrant with it, and each one saw an unread stamp and
    /// queued the identical question again. One hop is too short for that to
    /// happen on a quiet machine, which is the whole reason it only ever
    /// surfaced as a test failing under load.
    ///
    /// Only an *identical* question is suppressed -- same turn, same
    /// `lastEventAt`. A turn that does something while its read is in flight
    /// has a different stamp, and that is a new question the in-flight answer
    /// cannot contain.
    private var inFlightProgressReads: [String: TurnProgressRequest] = [:]
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
    /// Cool-off after a connect that never reached a working transport.
    ///
    /// The one backoff here that guards a subprocess rather than a request. See
    /// ``connectToAppServer()``.
    private var connectRetryAfter: Date?
    /// Why the last connect failed, replayed for the refreshes the cool-off
    /// turns away.
    private var lastConnectFailure: (any Error)?
    private var lastTrustedSnapshot: AgentSnapshot?
    /// Keeps a finished row listed until Desktop no longer reports it unread
    /// (``TerminalUnreadRowFilter``, the rules every product shares).
    private var terminalUnreadMembershipGate: TerminalUnreadRowFilter
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
        self.clock = clock
        self.timing = timing
        self.client = client
        self.hookEvents = hookEvents
        self.hookRegistrar = hookRegistrar
        // The transport belongs to this service rather than to the store, so
        // the store stays a reducer with an inbox and nothing that binds. One
        // connection carries one payload, delivered on the listener's serial
        // read queue, which is what keeps arrival order.
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
        self.turnAbort = turnAbort
        let rolloutWatcher = PathSetChangeWatcher(
            debounceInterval: timing.unreadStateDebounceInterval
        )
        self.rolloutWatcher = rolloutWatcher
        self.screenAvailability = screenAvailability
        // Background reads land after the snapshot that started them has already
        // been published, so their results need a trigger of their own. The
        // one-second poll used to supply that by accident.
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
            // A running Turn's rollout gaining a record. It is a signal and not
            // a reading -- what arrived is answered by the refresh, in the
            // reader that knows how to answer it -- and the one record that
            // matters is the abort no hook reports. See ``rolloutWatcher``.
            rolloutWatcher.events(),
            invalidations
        ])
        self.terminalUnreadMembershipGate = TerminalUnreadRowFilter(timing: timing)
        self.presence = RunningApplicationPresence(
            processIdentifier: desktopProcessIdentifierProvider
        )
    }

    func fetchSnapshot(dismissedRowIDs: Set<String>) async -> AgentSnapshot {
        // The transport, before the status gate. A trusted definition can fire
        // before this app decides the registration is complete -- a Codex that
        // was already running has them loaded -- so the socket has to be bound
        // by then, not after.
        await hooks.prepareTransport()
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
                // And the rollout watches, for the same reason and by the same
                // rule. Only the live-Hook branch has Turns to watch the
                // rollouts of; a watcher left pointing at a file from a branch
                // that publishes no rows goes on waking a refresh that will
                // not read it, once per record the turn appends.
                rolloutWatcher.watch(paths: [])
            }
        }
        let desktopProcessIdentifier = await self.presence.processIdentifier()
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
        // ``endAbortedTurns(in:)`` does not rescue this one, and the difference
        // is worth naming: that reading answers a Turn Codex *stopped*, and a
        // Desktop that died wrote no `turn_aborted` any more than it sent a
        // `Stop`. The evidence for a dead producer is the dead producer.
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
        let presence = RunningApplicationPresence.presence(of: desktopProcessIdentifier)

        let hasLiveHookObservation = hasCurrentHookObservation(
            hookState: hookState,
            desktopProcessIdentifier: desktopProcessIdentifier
        )
        let setupStatus = IntegrationSetupStatus.card(
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
                // has no such thread, or the product has said the same thing
                // itself. Re-paginating the user's whole history to look for a
                // thread its owner says does not exist buys nothing, and a
                // Codex side chat would otherwise ask for that sweep on every
                // refresh for as long as it ran.
                //
                // The second of those arrives on the thread's first event and
                // the first only after a round trip, so this is also the sweep
                // a side chat used to get before the refusal landed.
                let containsUnlistedHookThread = hookState.turns.contains { state in
                    let threadID = state.threadID
                    guard !listedThreadIDs.contains(threadID) else { return false }
                    guard !state.threadHasNoTranscript else { return false }
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
                scheduleThreadMetadataRefreshIfNeeded(for: hookState.turns)
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
                // The one thing that ends a Codex Turn without a hook event,
                // and the reason it has to exist: pressing stop in Desktop
                // sends nothing at all -- no `Stop`, and not even the
                // `PostToolUse` for the call that was still open -- so the row
                // said *Running* with its timer counting until the user
                // resumed that exact thread or waved the row away. Codex does
                // write the abort down, in the same rollout the reviewer is
                // read from (ADR 0011, ``CodexRolloutTurnAbortReader``).
                //
                // Identity before termination: a prompt held back is settled
                // first, so that a Turn resumed and then stopped again inside
                // one refresh interval is the Turn the abort reading below is
                // asked about. The same rollout answers both, and the two
                // questions are the two halves of ADR 0011 — which Turn this
                // thread is on, and whether it is over.
                hookState = await adoptTurnsOnRecord(in: hookState)
                // After the reconciliation above, so a Turn this refresh is
                // about to drop is never asked about, and before the rows are
                // built, so an abort found here is a Completed row in this
                // snapshot rather than in the next one.
                hookState = await endAbortedTurns(in: hookState)
                // After the reduction, so a Turn this refresh just ended stops
                // being watched in the same pass that ended it.
                await watchRollouts(ofOpenTurnsIn: hookState)
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
    func nextRefreshDeadline() async -> Date? {
        var deadlines: [Date] = []
        // Asked once. Two entries below consult it, and a deadline that
        // disagreed with the guard its scheduler tests is the busy-wait this
        // whole doc comment is about.
        let screenIsAvailable = screenAvailability.isAvailable()

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

        // Quota and account, mirroring the reader's own scheduler -- see
        // ``CodexUsageReader/nextReadDeadline()``.
        if let quota = await usage.nextReadDeadline() {
            deadlines.append(quota)
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
            screenIsAvailable: screenIsAvailable
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
        rolloutWatcher.watch(paths: [])
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
        await usage.cancel()
        terminalUnreadMembershipGate.reset()
        connectRetryAfter = nil
        lastConnectFailure = nil
        await client.disconnect()
    }

    /// Whether the App Server still hands this thread over as a navigable root.
    ///
    /// **It asks about one thread, not about the whole history.** This is the
    /// question [ADR 0017](../../docs/adr/0017-a-row-requires-a-thread-the-app-server-vouches-for.md)
    /// already puts to the App Server before a row is drawn, asked again at the
    /// moment the user clicks -- so the click can never demand more evidence
    /// than the row was admitted on. It used to be answered by re-paginating
    /// every unarchived thread, which is the transport's most expensive call
    /// and grows with the user's history: measured 2026-08-26 against CLI
    /// `0.149.0-alpha.4.3`, a full pagination costs 51ms at 50 threads, 335ms
    /// at 199, 754ms at 400 and **2.2s at 799**, against 1.4ms median for one
    /// `thread/read`. That was the whole of the 1-2s lag between clicking a
    /// Codex row and Codex Desktop coming forward.
    ///
    /// **Archiving is not this gate's question.** A thread the user archived is
    /// still a thread Codex Desktop holds and a deep link still names; what
    /// archiving ends is the row's monitoring lifecycle, and that is already
    /// owned by the membership sweep, which retires the Turn outright via
    /// `removeThreads(notIn:)` within `threadListRefreshInterval`. So a row the
    /// user can still see is a row the last sweep still listed, and re-asking
    /// here bought a second copy of an answer the row already carries. It could
    /// not be asked cheaply either: `thread/read` returns an archived thread
    /// with no marker of it (measured against a real `thread/archive` in an
    /// isolated `CODEX_HOME`), and the `thread/archived` notification that
    /// would have carried it reaches only the client that did the archiving --
    /// never this app's independent App Server.
    ///
    /// A refusal is recorded exactly as the metadata read records one, and for
    /// the same reason: it is an *answer* about this thread, so it retires the
    /// row rather than being asked again on every refresh.
    func isThreadNavigable(_ threadID: String) async throws -> Bool {
        guard !threadID.isEmpty else { return false }

        // The user clicked a row. Whatever the last refresh concluded about the
        // server, this is worth one spawn to find out for certain.
        try await connectToAppServer(bypassingCoolOff: true)

        if supportsThreadMetadataRead,
           let isNavigable = try await readNavigableRootThread(threadID) {
            return isNavigable
        }

        // A Codex without `thread/read` has only the paginated list left to be
        // asked, which is the shape this check had for every build.
        let listedThreads = try await readAllUnarchivedThreads(
            forceRefresh: true,
            timeoutNanoseconds: nanoseconds(timing.coreRequestTimeout)
        )
        return listedThreads.contains { thread in
            thread["id"]?.stringValue == threadID
                && CodexSnapshotParser.isEligibleRootThread(thread)
        }
    }

    /// Reads one thread and judges it; `nil` when this build cannot be asked.
    ///
    /// Only `-32601` answers `nil`, and it answers it once: the flag it clears
    /// is the same one the metadata path keeps, so a build without the method
    /// falls back to the list here and everywhere else. Every other remote
    /// error is the App Server *answering* about this thread -- it took the
    /// request and refused it -- which is `false`, not a reason to go and
    /// paginate. A transport failure is not an answer at all and is rethrown,
    /// so the user is told the target could not be confirmed rather than told
    /// their session is gone.
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
                    // Never the turn history -- see
                    // `refreshThreadMetadataInBackground` for why.
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

    /// Files what the App Server just said about one thread.
    ///
    /// The click pays for a read either way, so the row it came from gets the
    /// fresher title, and a refusal gets filed as a refusal.
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

    /// Reads integration health without draining the store.
    ///
    /// Draining here would reduce payloads the snapshot path is about to look
    /// at, costing a full refresh cycle of latency for whatever it swallowed.
    ///
    /// The user asking for a re-check is one of the two moments registration
    /// health can change without this app having caused it, so the cached
    /// reading is dropped here. The other is the file changing underneath us,
    /// which the registrar watches for itself.
    /// One answer, on the connection its request is still being held on.
    ///
    /// A pass-through, and deliberately nothing more: which bytes a product
    /// will act on is its vocabulary's business (``RequestAnswering``), and
    /// which connection they go down is the registry's. This is the boundary
    /// the store reaches both through.
    func answer(_ answer: AgentAnswer, on handle: AnswerHandle) async -> Bool {
        await hooks.answer(answer, on: handle)
    }

    /// Nothing: the quota arrives over the App Server and leaves no files
    /// anywhere.
    func diskFootprint() async -> AgentDiskFootprintReport { .leavesNothing }

    func setupStatus() async -> IntegrationSetupStatus {
        await hookRegistrar.invalidateRegistration()
        return await hooks.setupStatus()
    }

    func installIntegration() async throws {
        try await hooks.install()
        // The support directory exists now. On a first run the socket could not
        // bind at launch because there was nowhere to bind it; this is the
        // moment it becomes possible, and doing it here is what keeps the first
        // turn after setup from waiting out a refresh deadline.
        await hooks.prepareTransport()
    }

    func removeIntegration() async throws {
        await hookEvents.resetIntegrationObservation(clearTurns: true)
        hooks.disconnect()
        try await hooks.remove()
        observedDesktopProcessIdentifier = nil
        hookTrackedThreadIDs = []
        stopThreadReadsWithNoConsumer()
        lastTrustedSnapshot = nil
        terminalUnreadMembershipGate.reset()
    }

    nonisolated private func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }

    /// Tells the store that background work changed what a snapshot would say.
    ///
    /// Every background read must end in this, or its result sits in the actor
    /// until some unrelated deadline happens to fire.
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
        // Only the rows built are handed to the gate, not every Hook state. A
        // state whose thread turns out to be a sub-agent stops producing a
        // session at all, and keying on states kept its gate entry alive,
        // frozen mid-window, reporting a deadline that could never be cleared
        // because nothing evaluated it again.
        var candidates: [ReadGateCandidate] = []
        // Every Turn this pass walked, whether or not it produced a row: the
        // pin is retained on what the reducer still holds, not on what the
        // panel happens to draw.
        var observedTurns: Set<TurnApprovalRoutingPin.TurnIdentity> = []

        // The reviewer readings first, and all of them, so the loop below --
        // which mutates the pin and the two gates -- has nothing to await in
        // the middle of it. Asked for every Turn rather than only for the ones
        // sitting on an approval, because the question is what this Turn
        // *started* under and a Turn that has reached Approval needed is
        // already too late to ask it.
        for state in states {
            let turn = TurnApprovalRoutingPin.TurnIdentity(
                threadID: state.threadID,
                turnID: state.turnID
            )
            // The rollout's own path, as the App Server reports it. A thread
            // this app has not been handed yet is one it draws no row for
            // either, so there is nothing to be early for -- and the reading is
            // simply made on the refresh that does have the path.
            //
            // **When the path was reported goes in with it.** The path is not
            // a fixed property of the thread: resuming an interrupted Turn
            // rotates the rollout, so a record read a metadata interval ago
            // can name the file the *previous* Turn was written to. The pin
            // uses the stamp to tell a Turn whose record is genuinely absent
            // from a Turn that was looked for in the wrong file.
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
            // Whatever the rollout said, if it said anything. The map answers
            // for the Turns it could not -- and only where it was written late
            // enough to be describing them, which is why the Turn's own start
            // goes in with it.
            let approvalsReachTheUser = approvalRoutingPin.approvalsReachTheUser(
                forTurn: turn,
                startedAt: state.startedAt,
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
            // what says the row may exist at all -- "not asked yet", "asked,
            // and Codex has no such thread" and "Codex says it is writing this
            // thread down nowhere, so it was never asked" all arrive here as no
            // payload, and none of the three is grounds for a row (see
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
            // The Turn's own terminal goes in beside the thread's boundary and
            // the two must not be collapsed back into one. The window is about
            // how long this thread has been quiet; the blue dot is about a
            // Turn's answer, and that answer was there to be read from the
            // moment the Turn ended.
            candidates.append(
                ReadGateCandidate(
                    row: session,
                    turnEndedAt: state.turnEndedAt,
                    terminalBoundaryAt: state.terminalBoundaryAt
                )
            )
        }

        approvalRoutingPin.retain(turns: observedTurns)
        // Every row this product can draw is judged against Desktop's own
        // unread set; there is no row here nothing can speak for. A row the
        // user has taken off the list is still reported and judged by nobody,
        // and a finished row whose thread is still working takes the running
        // path -- both the filter's rules, shared with every product.
        return terminalUnreadMembershipGate.rows(
            candidates,
            dismissedRowIDs: dismissedRowIDs,
            now: clock.now()
        ) { _ in .judged(by: unreadState) }
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
    private func scheduleThreadMetadataRefreshIfNeeded(for states: [HookTurnState]) {
        guard supportsThreadMetadataRead else { return }

        let now = clock.now()
        var staleThreadIDs: Set<String> = []
        var observedThreadIDs: Set<String> = []
        for state in states {
            let threadID = state.threadID
            // **A thread the product says it is writing down nowhere is never
            // asked about.** This read is the one a row waits on, and its
            // answer for such a thread is already known: `thread/read` refuses
            // it, once per interval for as long as it runs, and the row it
            // would decide is a row that is not drawn either way. See
            // ``HookTurnState/threadHasNoTranscript``.
            //
            // No record is written in its place. "The product says there is
            // nothing to ask about" and "asked, and the answer was no" reach
            // every consumer as the same absence of a Thread -- no row, no
            // rollout to read -- and leaving the record absent is what keeps
            // this thread out of `nextRefreshDeadline()`'s metadata staleness,
            // which measures stamps that only a read can move.
            guard !state.threadHasNoTranscript else { continue }
            observedThreadIDs.insert(threadID)
            // A read already out for this thread is going to write the record
            // the checks below are looking for, stamped when it was issued.
            guard !inFlightMetadataThreadIDs.contains(threadID) else { continue }
            // **A prompt this thread is holding back counts as its newest
            // Turn here.** Settling one reads the rollout path this record
            // carries (``adoptTurnsOnRecord(in:)``), and the resumed-Turn case
            // is the very one that moves that path -- so a hold is behind the
            // record for the same reason a Turn is, and asks again on the same
            // terms. Without it the path stayed up to an interval behind and
            // the resumed Turn waited that long to take its row back.
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
            // **A record older than the Turn is a reason to ask again,
            // whatever the interval says.** The record carries the thread's
            // rollout path, and that path moves: Codex writes a Turn resumed
            // after an interrupt into a rollout of its own (measured
            // 2026-08-31 on thread `01a058c7`, CLI `0.151.0-alpha.7.2` --
            // interrupted at `…38.039`, new rollout at `…44.592`, the resumed
            // Turn's own hook at `…46.263`). Held to the interval alone the
            // path stayed up to ten seconds behind the Turn -- 6.7 s in that
            // measurement -- and the reviewer reading
            // ``TurnApprovalRoutingPin`` makes went to the file the
            // interrupted Turn was written to, which is what put *Approval
            // needed* on a row nobody was being asked about.
            //
            // **Once per Turn, not once per refresh.** The read is asked for
            // when the Turn is new to this thread and its path predates it;
            // whether the answer arrives is then the retry machinery's
            // business rather than this condition's, which must not go on
            // re-asking on a clock that has not caught up with the Turn's own
            // stamp. One extra `thread/read` per Turn buys the row its own
            // rollout, and it is the same read the title and preview already
            // come from.
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
        // Held to the threads the reducer still tracks, like every other table
        // keyed on one.
        metadataReadTurnIDsByThreadID = metadataReadTurnIDsByThreadID.filter {
            observedThreadIDs.contains($0.key)
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
        // Checked at dispatch and not only where the read was queued: the
        // answer that this build has no `thread/read` arrives mid-run, and
        // whatever the loop had queued behind it must not go out anyway. The
        // request is settled rather than left pending -- there is no later
        // moment at which this build grows the method.
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
        inFlightProgressReads = inFlightProgressReads.filter {
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
            // Neither is one the App Server has said it does not have, nor one
            // the product says it is writing down nowhere. This read fetches
            // the third line of a row that is not being drawn.
            if let record = threadRecords[state.threadID], !record.isAddressable {
                continue
            }
            guard !state.threadHasNoTranscript else { continue }
            let held = turnProgressByThreadID[state.threadID]
            if held?.turnID == state.turnID,
               held?.readAtEventStamp == state.lastEventAt {
                continue
            }
            // Nor is a question already out there waiting for its answer.
            if let inFlight = inFlightProgressReads[state.threadID],
               inFlight.turnID == state.turnID,
               inFlight.eventStamp == state.lastEventAt {
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
        // Filtered here and not only where it was queued: a thread that refused
        // while its own read was in flight had already had the next question
        // queued behind it, and "a thread that has already refused is not asked
        // twice" is a fact about the moment the read goes out.
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
        inFlightMetadataThreadIDs.removeAll()
        turnProgressRefreshTask?.cancel()
        turnProgressRefreshTask = nil
        turnProgressGate.reset()
        turnProgressRetryAfter = nil
        pendingProgressReads.removeAll()
        inFlightProgressReads.removeAll()
    }

    /// Gives a thread the held Turn its own rollout names, and only that one.
    ///
    /// **The Codex side of "a Turn's identity may be settled by evidence that
    /// is not a hook event"**, and the companion to the abort reading below.
    /// A prompt naming a Turn the reducer was not holding is held back rather
    /// than adopted, because a nested agent runs under the parent thread's
    /// `session_id` with a turn id of its own and no `agent_id` to be told
    /// apart by (``HookTurnState/heldTurnStart``). Its own events prove nothing
    /// — they carry that same id — so what settles it is the thread's rollout,
    /// where Codex writes each Turn's `turn_context` ~65 ms *before* that
    /// Turn's first hook. A reviewer's turns are written to a rollout of its
    /// own, so this thread's record never names one.
    ///
    /// Asked only of threads with a prompt actually held, which is a thread
    /// with something nested running on it or a Turn the user has just resumed
    /// — and asked of the same cached tail the abort reading below already
    /// takes of the same file on the same refresh, so it adds no read. Nothing
    /// is asked about a thread whose rollout the App Server has not handed
    /// over, on the same terms as that reading: a row this app cannot draw is
    /// not one worth reading a file for.
    ///
    /// **Deliberately not held to Turns that are still going**, which is the
    /// one place it differs from the abort reading. The resumed-Turn case ends
    /// with the interrupted Turn *finished* — by that reading, a refresh
    /// earlier — and the prompt held during it still waiting to be adopted, so
    /// a `keepsTiming` filter here would close the door on the very case this
    /// exists to open. A hold left on a finished Turn costs one `lstat`: its
    /// rollout has stopped changing, so the reader answers from its cache.
    private func adoptTurnsOnRecord(in hookState: HookStateSnapshot) async -> HookStateSnapshot {
        var records: [TurnOnRecord] = []
        for turn in hookState.turns {
            guard let held = turn.heldTurnStart,
                  let rolloutPath = rolloutPath(ofThread: turn.threadID) else {
                continue
            }
            guard await turnAbort.turnOnRecord(inRolloutAt: rolloutPath)
                == held.turnID else {
                continue
            }
            records.append(
                TurnOnRecord(threadID: turn.threadID, turnID: held.turnID)
            )
        }
        guard !records.isEmpty else { return hookState }
        return await hookEvents.adoptTurnsOnRecord(records)
    }

    /// Ends the Turns Codex recorded as aborted, and only those.
    ///
    /// **The Codex side of "a Turn may end on evidence that is not a Hook
    /// event"** (ADR 0011). A user pressing stop in Codex Desktop produces no
    /// hook of any kind, so the reducer holds that Turn open for ever: no event
    /// will name its `turn_id` again, membership reconciliation keeps the row
    /// because the thread is still listed, and this product has no
    /// activity-status read like `claude agents --json` to fall back on. What
    /// Codex leaves instead is a `turn_aborted` record in the thread's own
    /// rollout, and it names the Turn.
    ///
    /// The reducer stays the only thing that computes Turn state: this hands it
    /// a fact about a Turn Codex wrote down and lets
    /// ``HookEventRepository/endInterruptedTurns(_:)`` apply the rules any
    /// event gets. Held to Turns that are still going and to threads the App
    /// Server has handed over a path for -- a row this app cannot draw is not
    /// one worth reading a file for.
    private func endAbortedTurns(in hookState: HookStateSnapshot) async -> HookStateSnapshot {
        var interruptions: [TurnInterruption] = []
        for turn in hookState.turns where turn.sessionStatus.keepsTiming {
            guard let rolloutPath = rolloutPath(ofThread: turn.threadID) else {
                continue
            }
            guard let endedAt = await turnAbort.abortedAt(
                turnID: turn.turnID,
                inRolloutAt: rolloutPath,
                after: turn.lastEventAt
            ) else {
                continue
            }
            interruptions.append(
                TurnInterruption(
                    threadID: turn.threadID,
                    turnID: turn.turnID,
                    endedAt: endedAt,
                    // The stop killed the `wait_agent` this Turn was going to
                    // collect its subagents with, so their results can never
                    // reach it. See ``TurnInterruption/orphansSubagents`` for
                    // the measurement, and why a row that went on counting
                    // them said the thread was working for as long as an
                    // orphan ran -- on a Turn the user ended by hand.
                    orphansSubagents: true
                )
            )
        }
        guard !interruptions.isEmpty else { return hookState }
        return await hookEvents.endInterruptedTurns(interruptions)
    }

    /// Watches the rollouts of the Turns that are still going, and no others.
    ///
    /// The same set the reading above asks about, so the edge and the answer
    /// cannot disagree about which files are worth anything. It doubles as the
    /// reader's retention: a rollout nothing is waiting on is one nothing needs
    /// a cached answer about either.
    private func watchRollouts(ofOpenTurnsIn hookState: HookStateSnapshot) async {
        var paths: Set<String> = []
        for turn in hookState.turns where turn.sessionStatus.keepsTiming {
            guard let rolloutPath = rolloutPath(ofThread: turn.threadID) else {
                continue
            }
            paths.insert(rolloutPath)
        }
        rolloutWatcher.watch(paths: Set(paths.map { URL(fileURLWithPath: $0) }))
        await turnAbort.retain(rolloutPaths: paths)
    }

    /// The rollout this thread is written to, as the App Server reports it.
    ///
    /// The only source for it. A thread this app has not been handed yet draws
    /// no row either, so there is nothing to be early for.
    private func rolloutPath(ofThread threadID: String) -> String? {
        guard let path = threadRecords[threadID]?.thread?["path"]?.stringValue,
              !path.isEmpty else {
            return nil
        }
        return path
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

    /// Both of the account's rate-limit windows, in the order the App Server
    /// reports them.
    ///
    /// `secondary` is null for most accounts and was never read; where it is
    /// present it is a second window of the same limit, and a window is a line
    /// (`quota-footer-v2.md` §5). `primary` stays first, so every surface that
    /// draws one rule — ``QuotaSnapshot/remainingPercent`` and
    /// ``QuotaSnapshot/resetsAt`` both read `windows.first` — reads exactly what
    /// it read before.
    ///
    /// The per-limit map under `rateLimitsByLimitId` is **not** read. It
    /// repeats the account's own limit under the id `codex` and adds one entry
    /// per model-specific cap, and which of those actually binds a given
    /// request is not something this response says.
    nonisolated static func quota(from response: JSONValue) -> QuotaSnapshot {
        guard let limits = response["rateLimits"] else { return .unavailable }

        let windows = ["primary", "secondary"].compactMap { key -> QuotaWindow? in
            guard let window = limits[key],
                  let usedPercent = window["usedPercent"]?.intValue else {
                return nil
            }
            return QuotaWindow(
                label: windowLabel(minutes: window["windowDurationMins"]?.intValue),
                // Reported as used; the rule draws what is left.
                remainingPercent: 100 - usedPercent,
                resetsAt: window["resetsAt"]?.doubleValue.map {
                    Date(timeIntervalSince1970: $0)
                }
            )
        }
        guard !windows.isEmpty else { return .unavailable }
        return QuotaSnapshot(windows: windows)
    }

    /// What Codex calls a window, from the only thing it publishes about one.
    ///
    /// `account/rateLimits/read` names the *limit* — and `limitName` is null
    /// for the account's own — while it gives every window a duration in
    /// minutes. So the name is the duration, in the product's own terms: `300`
    /// is the 5-hour limit and `10080` the weekly one, which is how Codex
    /// presents them to the same account. Anything else is written out from the
    /// minutes rather than guessed at, and a window reporting no duration keeps
    /// the empty label the single unlabelled rule always had.
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
    /// **And on the threads it exists to stop, not even that.** Those hooks
    /// carry `transcript_path: null`, which is the product saying the same
    /// thing the App Server would, so the read is not issued at all and this
    /// check answers on an absent Thread as before
    /// (``HookTurnState/threadHasNoTranscript``).
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
        //
        // **The same fallback serves a turn that ended without a `Stop`.** One
        // the user stopped has no last word, because the event that would have
        // carried it is the one Codex never sends (ADR 0011,
        // ``CodexRolloutTurnAbortReader``) -- so it keeps the last thing it was
        // seen saying, and the prompt behind that, rather than going blank at
        // the moment it stops. Reached only where `assistantPreview` is absent,
        // so a turn that did end on a `Stop` is untouched.
        //
        // **A question the turn asked without waiting outranks the step it is
        // on** (2026-09-08). Codex's `request_user_input_async` asks a person
        // and keeps working, and the CLI's own system prompt tells it to --
        // "continue useful work that does not depend on the answer while
        // waiting" -- so the question is overwritten within seconds by whatever
        // the turn says next, which is how a user came to watch a row report a
        // SQL rewrite while Codex Desktop held an unanswered question card. Of
        // everything a *running* turn has said, the sentence addressed to a
        // person is the one worth the row.
        //
        // **A completed turn keeps its own last word**, and this is the
        // narrower half of the rule on purpose. That word is the turn's answer,
        // written after the question and knowing what came of it, and where the
        // question still mattered the model tends to restate it -- measured on
        // the one async question in this machine's history, whose
        // `last_assistant_message` was the question again. So here the question
        // ranks *below* the final answer and above the prompt, which is where
        // it earns its place: a turn the user stopped has no last word at all
        // (ADR 0011), and the question is a better answer to "what happened"
        // than the prompt it started from.
        //
        // Neither branch claims anybody is waiting. This app cannot see the
        // question answered, skipped, snoozed or auto-resolved, so it says only
        // what the turn said -- see ``HookTurnState/questionAskedWithoutWaiting``.
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
            // How long the turn took, for the row that draws it once the clock
            // has stopped. `lastEventAt` is the turn's own last moment and is
            // held there against a subagent's chatter, which is what makes it
            // an end rather than a moving target.
            finishedAt: status == .completed ? state.lastEventAt : nil,
            // **The same subtraction the status gets, in the same breath.** A
            // thread whose approvals an automatic reviewer is handling does not
            // draw `Approval needed`, and must not offer a request to answer
            // either -- an `Answer` control over a decision nobody is being
            // asked to make is the unsafe direction this reading exists to
            // prevent. `inputNeeded` is the turn's own question and is never
            // reviewed away, so it keeps its request whatever the reviewer is.
            request: approvalsReachTheUser || status == .inputNeeded
                ? state.requestAwaitingAnAnswer
                : nil
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
