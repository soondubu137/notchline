import AppKit
import Foundation

protocol CodexMonitoring: Sendable {
    func fetchSnapshot(showsContentPreviews: Bool) async -> MonitorSnapshot
    func hookSetupStatus() async -> HookSetupStatus
    func installHooks(showsContentPreviews: Bool) async throws
    func removeHooks() async throws
    func clearSessions() async
    func updateHookSettings(showsContentPreviews: Bool) async
    func disconnect() async
}

actor LiveCodexMonitorService: CodexMonitoring, CodexNavigationTargetChecking {
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
    private let hookInstaller: CodexHookInstaller
    private let projectMetadata: any DesktopProjectMetadataProviding
    private let unreadState: any DesktopUnreadStateProviding
    nonisolated let desktopStateChangeEvents: AsyncStream<Void>
    private let desktopProcessIdentifierProvider: @MainActor @Sendable () -> pid_t?
    private var cachedQuota = QuotaSnapshot.unavailable
    private var quotaReadAt: Date?
    private var cachedAccountFingerprint: String?
    private var accountReadAt: Date?
    private var threadRecords: [String: ThreadRecord] = [:]
    private var listedThreadIDs: Set<String> = []
    private var threadListReadAt: Date?
    private var threadListRefreshTask: Task<Void, Never>?
    private var threadListRetryAfter: Date?
    private var threadMetadataRefreshTask: Task<Void, Never>?
    private var threadMetadataRetryAfter: Date?
    private var supportsThreadMetadataRead = true
    private var observedDesktopProcessIdentifier: pid_t?
    private var quotaRefreshTask: Task<Void, Never>?
    private var quotaRetryAfter: Date?
    private var lastTrustedSnapshot: MonitorSnapshot?
    private var terminalUnreadMembershipGate: TerminalUnreadMembershipGate

    init(
        client: any CodexAppServerCommunicating = CodexAppServerClient(),
        hookEvents: HookEventRepository = HookEventRepository(),
        hookInstaller: CodexHookInstaller = CodexHookInstaller(),
        projectMetadata: any DesktopProjectMetadataProviding =
            CodexDesktopProjectMetadataRepository(),
        unreadState: any DesktopUnreadStateProviding =
            CodexDesktopUnreadStateRepository(),
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
        self.hookInstaller = hookInstaller
        self.projectMetadata = projectMetadata
        self.unreadState = unreadState
        self.desktopStateChangeEvents = unreadState.changeEvents()
        self.terminalUnreadMembershipGate = TerminalUnreadMembershipGate(
            settlingInterval: timing.terminalReadSettlingInterval
        )
        self.desktopProcessIdentifierProvider = desktopProcessIdentifierProvider
    }

    func fetchSnapshot(showsContentPreviews: Bool) async -> MonitorSnapshot {
        let hookUpgradeDiagnostic: String?
        do {
            try await hookInstaller.upgradeManagedHookIfNeeded()
            hookUpgradeDiagnostic = nil
        } catch {
            hookUpgradeDiagnostic = "Codex Hook helper 更新失败；继续使用已安装版本：\(error.localizedDescription)"
        }
        var hookState = await hookEvents.consumeEvents()
        let hookDiagnostic = hookState.diagnostic ?? hookUpgradeDiagnostic
        let desktopProcessIdentifier = await desktopProcessIdentifierProvider()
        if hookState.didConsumeEvents {
            observedDesktopProcessIdentifier = desktopProcessIdentifier
        }

        let hasLiveHookObservation = hasCurrentHookObservation(
            hookState: hookState,
            desktopProcessIdentifier: desktopProcessIdentifier
        )
        let setupStatus = await hookInstaller.status(
            hasObservedEvent: hookState.hasObservedEvent
        )
        guard setupStatus.isIntegrationEnabled else {
            let diagnostic = setupStatus == .repairRequired
                ? "Codex integration is incomplete and must be repaired."
                : "Codex integration has not been installed."
            return remember(
                MonitorSnapshot(
                    availability: .setupRequired,
                    sessions: [],
                    quota: .unavailable,
                    diagnostic: diagnostic
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
                    showsContentPreviews: showsContentPreviews
                )
                scheduleQuotaRefreshIfNeeded()
                return remember(
                    MonitorSnapshot(
                        availability: .ready,
                        sessions: sessions.sorted(by: CodexSnapshotParser.monitorOrder),
                        quota: cachedQuota,
                        diagnostic: combinedDiagnostic(
                            hookDiagnostic,
                            unreadSnapshot.diagnostic,
                            projectDiagnostic(
                                for: sessions,
                                metadata: projectSnapshot
                            )
                        )
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
            _ = try await readAllUnarchivedThreads(
                forceRefresh: false,
                timeoutNanoseconds: nanoseconds(timing.coreRequestTimeout)
            )
            scheduleQuotaRefreshIfNeeded()
            return remember(
                MonitorSnapshot(
                    availability: .ready,
                    sessions: [],
                    quota: cachedQuota,
                    diagnostic: nil
                )
            )
        } catch let error as CodexAppServerError {
            if error.isUnsupportedMethod {
                return MonitorSnapshot(
                    availability: .unsupportedVersion,
                    sessions: [],
                    quota: .unavailable,
                    diagnostic: error.localizedDescription
                )
            }
            if error.isTransientRequestFailure {
                guard appServerResponded else {
                    await client.disconnect()
                    return MonitorSnapshot(
                        availability: .disconnected,
                        sessions: [],
                        quota: .unavailable,
                        diagnostic: "Codex App Server 未响应：\(error.localizedDescription)"
                    )
                }
                return snapshotPreservingTrustedState(after: error)
            }
            if error.requiresConnectionReset {
                await client.disconnect()
            }
            return MonitorSnapshot(
                availability: .disconnected,
                sessions: [],
                quota: .unavailable,
                diagnostic: error.localizedDescription
            )
        } catch {
            await client.disconnect()
            return MonitorSnapshot(
                availability: .disconnected,
                sessions: [],
                quota: .unavailable,
                diagnostic: error.localizedDescription
            )
        }
    }

    func disconnect() async {
        threadListRefreshTask?.cancel()
        threadListRefreshTask = nil
        threadMetadataRefreshTask?.cancel()
        threadMetadataRefreshTask = nil
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

    func hookSetupStatus() async -> HookSetupStatus {
        let state = await hookEvents.consumeEvents()
        let desktopProcessIdentifier = await desktopProcessIdentifierProvider()
        if state.didConsumeEvents {
            observedDesktopProcessIdentifier = desktopProcessIdentifier
        }
        return await hookInstaller.status(
            hasObservedEvent: state.hasObservedEvent
        )
    }

    func installHooks(showsContentPreviews: Bool) async throws {
        try await hookInstaller.install(
            showsContentPreviews: showsContentPreviews
        )
    }

    func removeHooks() async throws {
        await hookEvents.resetIntegrationObservation(clearTurns: true)
        try await hookInstaller.uninstall()
        observedDesktopProcessIdentifier = nil
        threadListRefreshTask?.cancel()
        threadListRefreshTask = nil
        threadListRetryAfter = nil
        threadMetadataRefreshTask?.cancel()
        threadMetadataRefreshTask = nil
        threadMetadataRetryAfter = nil
        lastTrustedSnapshot = nil
        terminalUnreadMembershipGate.reset()
    }

    func clearSessions() async {
        await hookEvents.clearTurnsPreservingObservation()
        terminalUnreadMembershipGate.reset()
        if let snapshot = lastTrustedSnapshot {
            lastTrustedSnapshot = MonitorSnapshot(
                availability: snapshot.availability,
                sessions: [],
                quota: snapshot.quota,
                diagnostic: snapshot.diagnostic
            )
        }
    }

    func updateHookSettings(showsContentPreviews: Bool) async {
        try? await hookInstaller.updateSettings(
            showsContentPreviews: showsContentPreviews
        )
        if !showsContentPreviews {
            await hookEvents.clearContentPreviews()
        }
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
        let quotaNeedsRefresh = quotaReadAt == nil
            || now.timeIntervalSince(quotaReadAt ?? .distantPast) >= 60
        guard accountNeedsRefresh || quotaNeedsRefresh else { return }

        quotaRefreshTask = Task { [weak self] in
            await self?.refreshQuotaInBackground()
        }
    }

    private func refreshQuotaInBackground() async {
        defer { quotaRefreshTask = nil }
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
        showsContentPreviews: Bool
    ) async -> [MonitoredSession] {
        var sessions: [MonitoredSession] = []
        terminalUnreadMembershipGate.retain(
            sessionIDs: Set(states.map { "\($0.threadID):\($0.turnID)" })
        )

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
                showsContentPreviews: showsContentPreviews
            ) else {
                continue
            }

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
        return sessions
    }

    private var threadListRefreshIsDue: Bool {
        guard let threadListReadAt else { return true }
        return clock.now().timeIntervalSince(threadListReadAt)
            >= timing.threadListRefreshInterval
    }

    private func scheduleThreadListRefreshIfNeeded() {
        let now = clock.now()
        guard threadListRefreshTask == nil,
              threadListRetryAfter.map({ now >= $0 }) ?? true else {
            return
        }

        threadListRefreshTask = Task { [weak self] in
            await self?.refreshThreadListInBackground()
        }
    }

    /// Refreshes thread-level metadata for the threads the Hook reducer tracks.
    ///
    /// This is the read that follows Hook activity. `thread/read` returns the
    /// same `Thread` payload as `thread/list` for a single thread, so it covers
    /// title, preview, root-thread eligibility and `status.activeFlags` at a
    /// fraction of the cost of paginating every unarchived thread.
    private func scheduleThreadMetadataRefreshIfNeeded(for threadIDs: Set<String>) {
        let now = clock.now()
        guard supportsThreadMetadataRead,
              threadMetadataRefreshTask == nil,
              threadMetadataRetryAfter.map({ now >= $0 }) ?? true else {
            return
        }

        let staleThreadIDs = threadIDs.filter { threadID in
            guard let record = threadRecords[threadID] else { return true }
            return now.timeIntervalSince(record.observedAt)
                >= timing.threadMetadataRefreshInterval
        }
        guard !staleThreadIDs.isEmpty else { return }

        threadMetadataRefreshTask = Task { [weak self] in
            await self?.refreshThreadMetadataInBackground(
                threadIDs: staleThreadIDs
            )
        }
    }

    private func refreshThreadMetadataInBackground(
        threadIDs: Set<String>
    ) async {
        defer { threadMetadataRefreshTask = nil }

        var didReadAnyThread = false
        for threadID in threadIDs.sorted() {
            guard !Task.isCancelled else { return }

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
                    supportsThreadMetadataRead = false
                    return
                }
                if error.requiresConnectionReset {
                    await client.disconnect()
                    return
                }
                // One unreadable thread is metadata loss, not state loss:
                // membership and Turn status both come from elsewhere.
                continue
            } catch {
                continue
            }
        }

        guard !Task.isCancelled else { return }
        threadMetadataRetryAfter = didReadAnyThread
            ? nil
            : clock.now().addingTimeInterval(timing.requestRetryInterval)
    }

    private func refreshThreadListInBackground() async {
        defer { threadListRefreshTask = nil }

        do {
            _ = try await readAllUnarchivedThreads(
                forceRefresh: true,
                timeoutNanoseconds: nanoseconds(timing.backgroundThreadListTimeout)
            )
            guard !Task.isCancelled else { return }
            threadListRetryAfter = nil
        } catch let error as CodexAppServerError {
            guard !Task.isCancelled else { return }
            threadListRetryAfter = clock.now().addingTimeInterval(
                timing.requestRetryInterval
            )
            if error.requiresConnectionReset {
                await client.disconnect()
            }
        } catch {
            guard !Task.isCancelled else { return }
            threadListRetryAfter = clock.now().addingTimeInterval(
                timing.requestRetryInterval
            )
        }
    }

    private func remember(_ snapshot: MonitorSnapshot) -> MonitorSnapshot {
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
            ? "\(unavailableCount) 个会话缺少可验证的 Desktop Project 映射；未回退为 Chats。"
            : nil
        return combinedDiagnostic(metadata.diagnostic, unresolvedDiagnostic)
    }

    private func combinedDiagnostic(_ diagnostics: String?...) -> String? {
        let messages: [String] = diagnostics.compactMap { diagnostic -> String? in
            guard let diagnostic,
                  !diagnostic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return diagnostic
        }
        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    private func snapshotPreservingTrustedState(
        after error: CodexAppServerError
    ) -> MonitorSnapshot {
        let diagnostic = "App Server 请求暂时失败，保留最近状态：\(error.localizedDescription)"
        guard let lastTrustedSnapshot else {
            return MonitorSnapshot(
                availability: .connecting,
                sessions: [],
                quota: cachedQuota,
                diagnostic: diagnostic
            )
        }

        let quota = cachedQuota.remainingPercent == nil
            ? lastTrustedSnapshot.quota
            : cachedQuota
        return MonitorSnapshot(
            availability: lastTrustedSnapshot.availability,
            sessions: lastTrustedSnapshot.sessions,
            quota: quota,
            diagnostic: diagnostic
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
    nonisolated static func session(
        from state: HookTurnState,
        thread: JSONValue?,
        projectName: String,
        showsContentPreviews: Bool = true
    ) -> MonitoredSession? {
        if let thread, !isEligibleRootThread(thread) {
            return nil
        }

        let privacySafeTitle = normalizedTitle(thread?["name"]?.stringValue)
            ?? "Untitled"
        let threadPreview = showsContentPreviews
            ? normalizedPreview(thread?["preview"]?.stringValue)
            : nil
        let title = normalizedTitle(thread?["name"]?.stringValue)
            ?? threadPreview
            ?? (showsContentPreviews ? normalizedPreview(state.promptPreview) : nil)
            ?? "Untitled"
        let status = state.status
        let preview: String?
        if !showsContentPreviews {
            preview = nil
        } else if status == .completed {
            preview = normalizedPreview(state.assistantPreview)
        } else {
            preview = normalizedPreview(state.promptPreview)
        }

        return MonitoredSession(
            threadID: state.threadID,
            turnID: state.turnID,
            projectName: projectName,
            title: title,
            privacySafeTitle: privacySafeTitle,
            preview: preview,
            status: status,
            startedAt: state.startedAt
        )
    }

    nonisolated static func monitorOrder(_ lhs: MonitoredSession, _ rhs: MonitoredSession) -> Bool {
        let priority: [SessionStatus: Int] = [
            .inputNeeded: 0,
            .approvalNeeded: 1,
            .running: 2,
            .completed: 3
        ]
        let lhsPriority = priority[lhs.status] ?? Int.max
        let rhsPriority = priority[rhs.status] ?? Int.max
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return (lhs.startedAt ?? .distantPast) > (rhs.startedAt ?? .distantPast)
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
