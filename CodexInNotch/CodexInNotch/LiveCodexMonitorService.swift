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
    nonisolated private static let accountRefreshInterval: TimeInterval = 30
    nonisolated private static let threadListRefreshInterval: TimeInterval = 30
    nonisolated private static let requestRetryInterval: TimeInterval = 60
    nonisolated private static let coreRequestTimeoutNanoseconds: UInt64 = 5_000_000_000
    nonisolated private static let backgroundThreadListTimeoutNanoseconds: UInt64 = 15_000_000_000
    nonisolated private static let detailReadTimeoutNanoseconds: UInt64 = 5_000_000_000
    private let client: any CodexAppServerCommunicating
    private let hookEvents: HookEventRepository
    private let hookInstaller: CodexHookInstaller
    private let desktopProcessIdentifierProvider: @MainActor @Sendable () -> pid_t?
    private var cachedQuota = QuotaSnapshot.unavailable
    private var quotaReadAt: Date?
    private var cachedAccountFingerprint: String?
    private var accountReadAt: Date?
    private var cachedListedThreads: [JSONValue] = []
    private var threadListReadAt: Date?
    private var threadListRefreshTask: Task<Void, Never>?
    private var threadListRetryAfter: Date?
    private var observedDesktopProcessIdentifier: pid_t?
    private var threadDetailsCache: [String: CachedThreadDetails] = [:]
    private var detailReadRetryAfter: [String: Date] = [:]
    private var detailReadTasks: [String: Task<Void, Never>] = [:]
    private var quotaRefreshTask: Task<Void, Never>?
    private var quotaRetryAfter: Date?
    private var lastTrustedSnapshot: MonitorSnapshot?
    private var contentPreviewsEnabled = true

    private struct CachedThreadDetails {
        let turnID: String
        let updatedAt: Double?
        let thread: JSONValue
    }

    init(
        client: any CodexAppServerCommunicating = CodexAppServerClient(),
        hookEvents: HookEventRepository = HookEventRepository(),
        hookInstaller: CodexHookInstaller = CodexHookInstaller(),
        desktopProcessIdentifierProvider: @escaping @MainActor @Sendable () -> pid_t? = {
            LiveCodexMonitorService.desktopProcessIdentifier()
        }
    ) {
        self.client = client
        self.hookEvents = hookEvents
        self.hookInstaller = hookInstaller
        self.desktopProcessIdentifierProvider = desktopProcessIdentifierProvider
    }

    func fetchSnapshot(showsContentPreviews: Bool) async -> MonitorSnapshot {
        contentPreviewsEnabled = showsContentPreviews
        if !showsContentPreviews {
            threadDetailsCache.removeAll()
        }
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
        if hookState.hasObservedEvent,
           hookState.didConsumeEvents || observedDesktopProcessIdentifier == nil {
            observedDesktopProcessIdentifier = desktopProcessIdentifier
        }

        let hasLiveHookObservation = hasCurrentHookObservation(
            hookState: hookState,
            desktopProcessIdentifier: desktopProcessIdentifier
        )
        let setupStatus = await hookInstaller.status(
            hasObservedEvent: hasLiveHookObservation
        )
        guard setupStatus != .notInstalled else {
            return remember(
                MonitorSnapshot(
                    availability: .setupRequired,
                    sessions: [],
                    quota: .unavailable,
                    diagnostic: "Codex integration has not been installed."
                )
            )
        }

        do {
            try await client.connect()

            if hasLiveHookObservation {
                let cachedThreadIDs = Set(
                    cachedListedThreads.compactMap { $0["id"]?.stringValue }
                )
                let containsUnlistedHookThread = hookState.turns.contains {
                    !cachedThreadIDs.contains($0.threadID)
                }
                if hookState.didConsumeEvents
                    || containsUnlistedHookThread
                    || threadListRefreshIsDue {
                    // Hook state is the low-latency source. Full-list metadata
                    // and activeFlags are refreshed in the background so a slow
                    // thread/list cannot hold an Idle -> Running transition for
                    // the entire request timeout.
                    scheduleThreadListRefreshIfNeeded()
                }

                let listedThreads = cachedListedThreads
                let listedThreadsObservedAt = threadListReadAt
                if let listedThreadsObservedAt {
                    let unarchivedThreadIDs = Set(
                        listedThreads.compactMap { $0["id"]?.stringValue }
                    )
                    hookState = await hookEvents.removeThreads(
                        notIn: unarchivedThreadIDs,
                        snapshotStartedAt: listedThreadsObservedAt
                    )
                }
                let sessions = await sessions(
                    from: hookState.turns,
                    listedThreads: listedThreads,
                    listedThreadsObservedAt: listedThreadsObservedAt,
                    showsContentPreviews: showsContentPreviews
                )
                scheduleQuotaRefreshIfNeeded()
                return remember(
                    MonitorSnapshot(
                        availability: .ready,
                        sessions: sessions.sorted(by: CodexSnapshotParser.monitorOrder),
                        quota: cachedQuota,
                        diagnostic: hookDiagnostic
                            ?? (sessions.contains(where: { $0.status == .completed })
                            ? "已完成轮次会保留到归档或删除；当前公开协议尚未提供 Desktop 已读状态。"
                            : nil)
                    )
                )
            }

            let listedThreads = try await readAllUnarchivedThreads(
                forceRefresh: false,
                timeoutNanoseconds: Self.coreRequestTimeoutNanoseconds
            )

            let loadedList = try await client.request(
                method: "thread/loaded/list",
                params: .object([:]),
                timeoutNanoseconds: Self.coreRequestTimeoutNanoseconds
            )
            let loadedIDs = Set(
                loadedList["data"]?.arrayValue?.compactMap(\.stringValue) ?? []
            )

            // A newly launched App Server can read persisted Desktop history, but
            // that does not prove it is observing the Desktop runtime. Only loaded
            // threads are eligible for the live monitor.
            guard !loadedIDs.isEmpty else {
                scheduleQuotaRefreshIfNeeded()
                return remember(
                    MonitorSnapshot(
                        availability: .disconnected,
                        sessions: [],
                        quota: cachedQuota,
                        diagnostic: "App Server 已连接，但当前进程没有加载 Codex Desktop 的实时 thread。"
                    )
                )
            }

            var sessions = listedThreads.compactMap { thread -> MonitoredSession? in
                guard let threadID = thread["id"]?.stringValue,
                      loadedIDs.contains(threadID),
                      CodexSnapshotParser.isEligibleRootThread(thread) else {
                    return nil
                }
                return CodexSnapshotParser.activeSession(
                    from: thread,
                    showsContentPreviews: showsContentPreviews
                )
            }

            sessions.sort(by: CodexSnapshotParser.monitorOrder)
            scheduleQuotaRefreshIfNeeded()
            return remember(
                MonitorSnapshot(
                    availability: .ready,
                    sessions: sessions,
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
        quotaRefreshTask?.cancel()
        quotaRefreshTask = nil
        cancelDetailReadTasks()
        await client.disconnect()
    }

    func isThreadNavigable(_ threadID: String) async throws -> Bool {
        guard !threadID.isEmpty else { return false }

        try await client.connect()
        let listedThreads = try await readAllUnarchivedThreads(
            forceRefresh: true,
            timeoutNanoseconds: Self.coreRequestTimeoutNanoseconds
        )
        return listedThreads.contains { thread in
            thread["id"]?.stringValue == threadID
                && CodexSnapshotParser.isEligibleRootThread(thread)
        }
    }

    func hookSetupStatus() async -> HookSetupStatus {
        let state = await hookEvents.consumeEvents()
        let desktopProcessIdentifier = await desktopProcessIdentifierProvider()
        if state.hasObservedEvent,
           state.didConsumeEvents || observedDesktopProcessIdentifier == nil {
            observedDesktopProcessIdentifier = desktopProcessIdentifier
        }
        return await hookInstaller.status(
            hasObservedEvent: hasCurrentHookObservation(
                hookState: state,
                desktopProcessIdentifier: desktopProcessIdentifier
            )
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
        threadDetailsCache.removeAll()
        detailReadRetryAfter.removeAll()
        cancelDetailReadTasks()
        lastTrustedSnapshot = nil
    }

    func clearSessions() async {
        await hookEvents.clearTurnsPreservingObservation()
        threadDetailsCache.removeAll()
        detailReadRetryAfter.removeAll()
        cancelDetailReadTasks()
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
        contentPreviewsEnabled = showsContentPreviews
        try? await hookInstaller.updateSettings(
            showsContentPreviews: showsContentPreviews
        )
        if !showsContentPreviews {
            await hookEvents.clearContentPreviews()
            threadDetailsCache.removeAll()
        }
    }

    private func scheduleQuotaRefreshIfNeeded() {
        let now = Date()
        guard quotaRefreshTask == nil,
              quotaRetryAfter.map({ now >= $0 }) ?? true else {
            return
        }

        let accountNeedsRefresh = accountReadAt == nil
            || now.timeIntervalSince(accountReadAt ?? .distantPast)
                >= Self.accountRefreshInterval
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
            quotaRetryAfter = Date().addingTimeInterval(Self.requestRetryInterval)
        }
    }

    private func readAccountUsageIfNeeded() async throws -> QuotaSnapshot {
        let now = Date()
        if accountReadAt == nil
            || now.timeIntervalSince(accountReadAt ?? .distantPast)
                >= Self.accountRefreshInterval {
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
           now.timeIntervalSince(quotaReadAt) < 60 {
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
                CodexSnapshotParser.todayTokenCount(from: $0)
            }
        )
        cachedQuota = quota
        quotaReadAt = now
        return quota
    }

    private func sessions(
        from states: [HookTurnState],
        listedThreads: [JSONValue],
        listedThreadsObservedAt: Date?,
        showsContentPreviews: Bool
    ) async -> [MonitoredSession] {
        var sessions: [MonitoredSession] = []
        let listedByID = Dictionary(
            uniqueKeysWithValues: listedThreads.compactMap { thread in
                thread["id"]?.stringValue.map { ($0, thread) }
            }
        )
        let activeThreadIDs = Set(states.map(\.threadID))
        let activeTurnKeys = Set(states.map(Self.detailReadKey))
        threadDetailsCache = threadDetailsCache.filter {
            activeThreadIDs.contains($0.key)
        }
        detailReadRetryAfter = detailReadRetryAfter.filter {
            activeTurnKeys.contains($0.key)
        }
        let obsoleteTaskKeys = Set(detailReadTasks.keys).subtracting(activeTurnKeys)
        for key in obsoleteTaskKeys {
            detailReadTasks.removeValue(forKey: key)?.cancel()
        }

        for state in states {
            let canApplyListedStatus = listedThreadsObservedAt.map {
                $0 >= state.lastEventAt
            } ?? false
            let listedThread = listedByID[state.threadID]
            let listedUpdatedAt = listedThread?["updatedAt"]?.doubleValue
            let cached = threadDetailsCache[state.threadID]
            let cachedMatchesList = cached != nil
                && cached?.turnID == state.turnID
                && cached?.updatedAt == listedUpdatedAt
            let fullThread = cachedMatchesList
                ? cached?.thread
                : listedThread
            let detailKey = Self.detailReadKey(state)
            let retryAllowed = detailReadRetryAfter[detailKey].map {
                Date() >= $0
            } ?? true
            let shouldReadDetails = state.lifecycleStatus == .unknown
                && listedThread != nil
                && retryAllowed
                && detailReadTasks[detailKey] == nil

            if shouldReadDetails {
                scheduleDetailRead(
                    for: state,
                    listedUpdatedAt: listedUpdatedAt,
                    showsContentPreviews: showsContentPreviews
                )
            }

            if let session = CodexSnapshotParser.session(
                from: state,
                thread: fullThread,
                allowsAppServerStatusCorrection: canApplyListedStatus,
                showsContentPreviews: showsContentPreviews
            ) {
                sessions.append(session)
                if canApplyListedStatus,
                   let listedThreadsObservedAt,
                   [.completed, .error, .cancelled].contains(session.status) {
                    _ = await hookEvents.resolveTerminalStatus(
                        threadID: session.threadID,
                        turnID: session.turnID,
                        status: session.status,
                        snapshotStartedAt: listedThreadsObservedAt
                    )
                } else if canApplyListedStatus,
                          let listedThreadsObservedAt,
                          let activeEvidence = CodexSnapshotParser.activeEvidence(
                    from: fullThread,
                    forTurnID: state.turnID,
                    allowThreadLevelEvidence: state.hasLiveBoundary
                ) {
                    _ = await hookEvents.reconcileActiveStatus(
                        threadID: state.threadID,
                        turnID: state.turnID,
                        isInputPending: activeEvidence.isInputPending,
                        isApprovalPending: activeEvidence.isApprovalPending,
                        snapshotStartedAt: listedThreadsObservedAt
                    )
                }
            }
        }
        return sessions
    }

    private func scheduleDetailRead(
        for state: HookTurnState,
        listedUpdatedAt: Double?,
        showsContentPreviews: Bool
    ) {
        let detailKey = Self.detailReadKey(state)
        guard detailReadTasks[detailKey] == nil else { return }

        detailReadTasks[detailKey] = Task { [weak self] in
            await self?.resolveDetailsInBackground(
                for: state,
                listedUpdatedAt: listedUpdatedAt,
                showsContentPreviews: showsContentPreviews
            )
        }
    }

    private func resolveDetailsInBackground(
        for state: HookTurnState,
        listedUpdatedAt: Double?,
        showsContentPreviews: Bool
    ) async {
        let detailKey = Self.detailReadKey(state)
        defer { detailReadTasks.removeValue(forKey: detailKey) }
        let snapshotStartedAt = Date()

        do {
            let response = try await client.request(
                method: "thread/read",
                params: .object([
                    "threadId": .string(state.threadID),
                    "includeTurns": .bool(true)
                ]),
                timeoutNanoseconds: Self.detailReadTimeoutNanoseconds
            )
            guard !Task.isCancelled else { return }

            let fullThread = response["thread"]
            detailReadRetryAfter.removeValue(forKey: detailKey)
            if let fullThread,
               showsContentPreviews,
               contentPreviewsEnabled {
                threadDetailsCache[state.threadID] = CachedThreadDetails(
                    turnID: state.turnID,
                    updatedAt: listedUpdatedAt,
                    thread: fullThread
                )
            }
            if let fullThread,
               let session = CodexSnapshotParser.session(
                   from: state,
                   thread: fullThread,
                   showsContentPreviews: showsContentPreviews
               ) {
                if [.completed, .error, .cancelled].contains(session.status) {
                    _ = await hookEvents.resolveTerminalStatus(
                        threadID: session.threadID,
                        turnID: session.turnID,
                        status: session.status,
                        snapshotStartedAt: snapshotStartedAt
                    )
                } else if let activeEvidence = CodexSnapshotParser.activeEvidence(
                    from: fullThread,
                    forTurnID: state.turnID,
                    allowThreadLevelEvidence: state.hasLiveBoundary
                ) {
                    _ = await hookEvents.reconcileActiveStatus(
                        threadID: state.threadID,
                        turnID: state.turnID,
                        isInputPending: activeEvidence.isInputPending,
                        isApprovalPending: activeEvidence.isApprovalPending,
                        snapshotStartedAt: snapshotStartedAt
                    )
                }
            }
            _ = await hookEvents.markTerminalStatusUnresolved(
                threadID: state.threadID,
                turnID: state.turnID,
                snapshotStartedAt: snapshotStartedAt
            )
        } catch let error as CodexAppServerError {
            guard !Task.isCancelled else { return }
            _ = await hookEvents.markTerminalStatusUnresolved(
                threadID: state.threadID,
                turnID: state.turnID,
                snapshotStartedAt: snapshotStartedAt
            )
            detailReadRetryAfter[detailKey] = Date().addingTimeInterval(
                Self.requestRetryInterval
            )
            if error.requiresConnectionReset {
                await client.disconnect()
            }
        } catch {
            guard !Task.isCancelled else { return }
            _ = await hookEvents.markTerminalStatusUnresolved(
                threadID: state.threadID,
                turnID: state.turnID,
                snapshotStartedAt: snapshotStartedAt
            )
            detailReadRetryAfter[detailKey] = Date().addingTimeInterval(
                Self.requestRetryInterval
            )
        }
    }

    private func cancelDetailReadTasks() {
        for task in detailReadTasks.values {
            task.cancel()
        }
        detailReadTasks.removeAll()
    }

    nonisolated private static func detailReadKey(_ state: HookTurnState) -> String {
        "\(state.threadID):\(state.turnID)"
    }

    private var threadListRefreshIsDue: Bool {
        guard let threadListReadAt else { return true }
        return Date().timeIntervalSince(threadListReadAt)
            >= Self.threadListRefreshInterval
    }

    private func scheduleThreadListRefreshIfNeeded() {
        let now = Date()
        guard threadListRefreshTask == nil,
              threadListRetryAfter.map({ now >= $0 }) ?? true else {
            return
        }

        threadListRefreshTask = Task { [weak self] in
            await self?.refreshThreadListInBackground()
        }
    }

    private func refreshThreadListInBackground() async {
        defer { threadListRefreshTask = nil }

        do {
            _ = try await readAllUnarchivedThreads(
                forceRefresh: true,
                timeoutNanoseconds: Self.backgroundThreadListTimeoutNanoseconds
            )
            guard !Task.isCancelled else { return }
            threadListRetryAfter = nil
        } catch let error as CodexAppServerError {
            guard !Task.isCancelled else { return }
            threadListRetryAfter = Date().addingTimeInterval(
                Self.requestRetryInterval
            )
            if error.requiresConnectionReset {
                await client.disconnect()
            }
        } catch {
            guard !Task.isCancelled else { return }
            threadListRetryAfter = Date().addingTimeInterval(
                Self.requestRetryInterval
            )
        }
    }

    private func remember(_ snapshot: MonitorSnapshot) -> MonitorSnapshot {
        lastTrustedSnapshot = snapshot
        return snapshot
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

    private func readAllUnarchivedThreads(
        forceRefresh: Bool,
        timeoutNanoseconds: UInt64
    ) async throws -> [JSONValue] {
        if !forceRefresh,
           let threadListReadAt,
           Date().timeIntervalSince(threadListReadAt)
               < Self.threadListRefreshInterval {
            return cachedListedThreads
        }

        var threads: [JSONValue] = []
        var cursor: String?
        var observedCursors = Set<String>()
        let snapshotStartedAt = Date()

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

        cachedListedThreads = threads
        // Use the request start, not completion, as the freshness boundary.
        // A Hook can arrive while a slow paginated list is still in flight.
        threadListReadAt = snapshotStartedAt
        return threads
    }

    private func hasCurrentHookObservation(
        hookState: HookStateSnapshot,
        desktopProcessIdentifier: pid_t?
    ) -> Bool {
        guard hookState.hasObservedEvent,
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
    struct ActiveEvidence: Sendable {
        let isInputPending: Bool
        let isApprovalPending: Bool

        nonisolated var status: MonitorStatus {
            if isInputPending {
                return .inputNeeded
            }
            if isApprovalPending {
                return .approvalNeeded
            }
            return .running
        }
    }

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
        now: Date = Date(),
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

    nonisolated static func activeSession(
        from thread: JSONValue,
        showsContentPreviews: Bool = true
    ) -> MonitoredSession? {
        guard isEligibleRootThread(thread),
              let threadID = thread["id"]?.stringValue,
              let activeEvidence = activeEvidence(from: thread) else {
            return nil
        }

        let turns = thread["turns"]?.arrayValue ?? []
        let activeTurn = turns.last {
            $0["status"]?.stringValue == "inProgress"
        }
        guard let turnID = activeTurn?["id"]?.stringValue else {
            return nil
        }
        let startedAt = activeTurn?["startedAt"]?.doubleValue.map {
            Date(timeIntervalSince1970: $0)
        }

        let projectName = thread["section"]?["name"]?.stringValue ?? "Chats"
        let privacySafeTitle = normalizedTitle(thread["name"]?.stringValue)
            ?? "Untitled"
        let threadPreview = showsContentPreviews
            ? normalizedPreview(thread["preview"]?.stringValue)
            : nil
        let title = normalizedTitle(thread["name"]?.stringValue)
            ?? threadPreview
            ?? "Untitled"

        return MonitoredSession(
            threadID: threadID,
            turnID: turnID,
            projectName: projectName,
            title: title,
            privacySafeTitle: privacySafeTitle,
            preview: showsContentPreviews ? publicPreview(from: activeTurn) : nil,
            status: activeEvidence.status,
            startedAt: startedAt
        )
    }

    nonisolated static func activeEvidence(
        from thread: JSONValue?,
        forTurnID turnID: String? = nil,
        allowThreadLevelEvidence: Bool = true
    ) -> ActiveEvidence? {
        guard thread?["status"]?["type"]?.stringValue == "active" else {
            return nil
        }

        if let turnID {
            let inProgressTurnIDs: [String] = thread?["turns"]?.arrayValue?.compactMap { turn in
                guard turn["status"]?.stringValue == "inProgress" else {
                    return nil
                }
                return turn["id"]?.stringValue
            } ?? []
            if !inProgressTurnIDs.isEmpty,
               !inProgressTurnIDs.contains(turnID) {
                return nil
            }
            if inProgressTurnIDs.isEmpty,
               !allowThreadLevelEvidence {
                return nil
            }
        }

        let flags = Set(
            thread?["status"]?["activeFlags"]?.arrayValue?.compactMap(\.stringValue) ?? []
        )
        return ActiveEvidence(
            isInputPending: flags.contains("waitingOnUserInput"),
            isApprovalPending: flags.contains("waitingOnApproval")
        )
    }

    nonisolated static func session(
        from state: HookTurnState,
        thread: JSONValue?,
        allowsAppServerStatusCorrection: Bool = true,
        showsContentPreviews: Bool = true
    ) -> MonitoredSession? {
        if let thread, !isEligibleRootThread(thread) {
            return nil
        }

        let turns = thread?["turns"]?.arrayValue ?? []
        let matchingTurn = turns.last {
            $0["id"]?.stringValue == state.turnID
        }
        let startedAt = matchingTurn?["startedAt"]?.doubleValue.map {
            Date(timeIntervalSince1970: $0)
        } ?? state.startedAt

        let privacySafeTitle = normalizedTitle(thread?["name"]?.stringValue)
            ?? "Untitled"
        let threadPreview = showsContentPreviews
            ? normalizedPreview(thread?["preview"]?.stringValue)
            : nil
        let title = normalizedTitle(thread?["name"]?.stringValue)
            ?? threadPreview
            ?? (showsContentPreviews ? normalizedPreview(state.promptPreview) : nil)
            ?? "Untitled"
        let persistedTerminalStatus: MonitorStatus? = [
            .completed, .error, .cancelled
        ].contains(state.lifecycleStatus) ? state.lifecycleStatus : nil
        let appServerTerminalStatus = allowsAppServerStatusCorrection
            ? terminalStatus(from: matchingTurn)
            : nil
        let appServerActiveStatus = allowsAppServerStatusCorrection
            ? activeEvidence(
                from: thread,
                forTurnID: state.turnID,
                allowThreadLevelEvidence: state.hasLiveBoundary
            )?.status
            : nil
        let status = appServerTerminalStatus
            ?? persistedTerminalStatus
            ?? appServerActiveStatus
            ?? state.status
        let preview: String?
        if !showsContentPreviews {
            preview = nil
        } else if status == .completed {
            preview = normalizedPreview(state.assistantPreview)
                ?? publicPreview(from: matchingTurn)
        } else {
            preview = publicPreview(from: matchingTurn)
                ?? normalizedPreview(state.promptPreview)
        }

        return MonitoredSession(
            threadID: state.threadID,
            turnID: state.turnID,
            projectName: thread?["section"]?["name"]?.stringValue ?? "Chats",
            title: title,
            privacySafeTitle: privacySafeTitle,
            preview: preview,
            status: status,
            startedAt: startedAt
        )
    }

    nonisolated static func terminalStatus(from turn: JSONValue?) -> MonitorStatus? {
        switch turn?["status"]?.stringValue {
        case "completed":
            .completed
        case "failed":
            .error
        case "interrupted":
            .cancelled
        default:
            nil
        }
    }

    nonisolated static func monitorOrder(_ lhs: MonitoredSession, _ rhs: MonitoredSession) -> Bool {
        let priority: [MonitorStatus: Int] = [
            .inputNeeded: 0,
            .approvalNeeded: 1,
            .running: 2,
            .error: 3,
            .completed: 4,
            .cancelled: 5,
            .unknown: 6
        ]
        let lhsPriority = priority[lhs.status] ?? Int.max
        let rhsPriority = priority[rhs.status] ?? Int.max
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return (lhs.startedAt ?? .distantPast) > (rhs.startedAt ?? .distantPast)
    }

    nonisolated private static func publicPreview(from turn: JSONValue?) -> String? {
        let items = turn?["items"]?.arrayValue ?? []
        for item in items.reversed() {
            let type = item["type"]?.stringValue
            guard type == "agentMessage" || type == "userMessage" || type == "plan" else {
                continue
            }

            if let text = normalizedPreview(item["text"]?.stringValue) {
                return text
            }

            let content = item["content"]?.arrayValue ?? []
            for part in content.reversed() {
                if let text = normalizedPreview(
                    part["text"]?.stringValue ?? part["content"]?.stringValue
                ) {
                    return text
                }
            }
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
