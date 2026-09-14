import Foundation

/// Codex's account and quota, read over the App Server and held between reads
/// (`tiered-support.md` §5.4). Never connects: ``readIfStale()`` is called only from refresh
/// branches that just connected, since a read on a down transport would blank the figures.
actor CodexUsageReader: UsageReading {
    private let client: any CodexAppServerCommunicating
    private let clock: any MonitorClock
    private let timing: MonitorTiming
    private let screenAvailability: any ScreenAvailabilityReporting
    /// Called when a read lands; the snapshot that started it is already published.
    private let onUpdate: @Sendable () -> Void

    private var cachedQuota = QuotaSnapshot.unavailable
    private var quotaReadAt: Date?
    private var cachedAccountFingerprint: String?
    private var accountReadAt: Date?
    private var refreshTask: Task<Void, Never>?
    private var retryAfter: Date?

    init(
        client: any CodexAppServerCommunicating,
        clock: any MonitorClock,
        timing: MonitorTiming,
        screenAvailability: any ScreenAvailabilityReporting,
        onUpdate: @escaping @Sendable () -> Void
    ) {
        self.client = client
        self.clock = clock
        self.timing = timing
        self.screenAvailability = screenAvailability
        self.onUpdate = onUpdate
    }

    /// What was last read. Never starts a read: only the refresh knows whether there is a transport.
    func currentQuota() -> QuotaSnapshot {
        cachedQuota
    }

    /// Nothing actionable to report; a failed read blanks the figures and the next one retries.
    func quotaDiagnostic() -> String? {
        nil
    }

    /// Starts the account and quota reads if either is stale and there is a screen to draw them
    /// on (as ``ClaudeCodeUsageReader``). Ungated, an idle machine issued three App Server requests
    /// a minute all night. The screen returning is an edge on the service's change stream, so the
    /// first refresh after an unlock reads.
    func readIfStale() {
        let now = clock.now()
        guard refreshTask == nil,
              screenAvailability.isAvailable(),
              retryAfter.map({ now >= $0 }) ?? true else {
            return
        }

        let accountNeedsRefresh = accountReadAt == nil
            || now.timeIntervalSince(accountReadAt ?? .distantPast)
                >= timing.accountRefreshInterval
        // Same window ``nextReadDeadline()`` publishes, so the wake-up and its work cannot disagree.
        let quotaNeedsRefresh = quotaReadAt == nil
            || now.timeIntervalSince(quotaReadAt ?? .distantPast)
                >= timing.quotaRefreshInterval
        guard accountNeedsRefresh || quotaNeedsRefresh else { return }

        refreshTask = Task { [weak self] in
            await self?.refreshInBackground()
        }
    }

    /// When the figures want reading again; nil while there is no screen (as ``readIfStale()``),
    /// else a past deadline no refresh could clear. A retry backoff defers each due date rather
    /// than waking on its own, which would leave the marker in the past forever.
    func nextReadDeadline() -> Date? {
        guard screenAvailability.isAvailable() else { return nil }
        return [
            quotaReadAt.map {
                Self.deferred($0.addingTimeInterval(timing.quotaRefreshInterval), by: retryAfter)
            },
            accountReadAt.map {
                Self.deferred($0.addingTimeInterval(timing.accountRefreshInterval), by: retryAfter)
            }
        ]
        .compactMap { $0 }
        .min()
    }

    /// Stops a read in flight: its connection is going away.
    func cancel() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    nonisolated private static func deferred(_ due: Date, by retryAfter: Date?) -> Date {
        guard let retryAfter else { return due }
        return max(due, retryAfter)
    }

    private func refreshInBackground() async {
        defer {
            refreshTask = nil
            onUpdate()
        }
        do {
            _ = try await readAccountUsageIfNeeded()
            retryAfter = nil
        } catch {
            cachedQuota = .unavailable
            quotaReadAt = nil
            retryAfter = clock.now().addingTimeInterval(timing.requestRetryInterval)
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
        // Every window, not just the first: the single-window initialiser drops the rest.
        let quota = QuotaSnapshot(
            windows: rateLimitQuota.windows,
            todayTokens: responses.1.flatMap {
                CodexSnapshotParser.todayTokenCount(from: $0, now: clock.now())
            }
        )
        cachedQuota = quota
        quotaReadAt = now
        return quota
    }
}
