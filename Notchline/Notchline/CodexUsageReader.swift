import Foundation

/// Codex's account and quota, read over the App Server and held between reads.
///
/// **Taken out of `LiveCodexMonitorService` on 2026-09-12**, where it was six
/// stored properties, a task and three methods threaded through the actor that
/// also owns the thread reads, the pid binding and the connection. It is one
/// capability with one consumer — the footer — and Claude Code's copy of it has
/// always been a reader of its own (``ClaudeCodeUsageReader``); the two now
/// present the same ``UsageReading`` shape to whatever composes them
/// (`tiered-support.md` §5.4).
///
/// **It asks only while the service says the transport answers.** Nothing here
/// connects: ``readIfStale()`` is called from the branches of a refresh that
/// have just connected, and a read issued on a transport that is down would
/// book a retry and blank the held figures for a failure that is not the
/// account's.
actor CodexUsageReader: UsageReading {
    private let client: any CodexAppServerCommunicating
    private let clock: any MonitorClock
    private let timing: MonitorTiming
    /// Whether there is a screen the figures could be drawn on. See
    /// ``readIfStale()``.
    private let screenAvailability: any ScreenAvailabilityReporting
    /// Called when a read lands, because nothing waits for one: the snapshot
    /// that started it has already been published.
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

    /// What was last read. Never starts a read: this product's reads need a
    /// transport, and only the refresh knows whether it has one.
    func currentQuota() -> QuotaSnapshot {
        cachedQuota
    }

    /// Codex says nothing about its account that a user could act on here; a
    /// failed read blanks the figures and the next one tries again.
    func quotaDiagnostic() -> String? {
        nil
    }

    /// Starts the account and quota reads if either has gone stale, and there
    /// is a screen the answer could be drawn on.
    ///
    /// **Nothing is read while there is no screen.** Both figures exist to be
    /// drawn in the panel's footer, which a user reaches by hovering the notch,
    /// so a display that is asleep or a screen that is locked means they cannot
    /// be looked at -- not merely that they are unlikely to be. Left ungated,
    /// an idle machine spent the night issuing three App Server requests a
    /// minute for a footer nobody could open, and unlike Codex Desktop being
    /// shut this cost was paid whenever the transport was alive at all: the
    /// branch of the refresh that finds no Hook observation asks for this too.
    ///
    /// The same rule ``ClaudeCodeUsageReader`` applies to the other product's
    /// copy of this reading, and for the same reason. The wake is an edge the
    /// service's change stream already carries -- the screen coming back is one
    /// of the streams merged into it -- so the first refresh after an unlock
    /// takes the reading, rather than the figures waiting out the interval at
    /// the moment the user is most likely to be looking.
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
        // The same window ``nextReadDeadline()`` publishes for quota. A literal
        // here would let the wake-up and the work it wakes for disagree.
        let quotaNeedsRefresh = quotaReadAt == nil
            || now.timeIntervalSince(quotaReadAt ?? .distantPast)
                >= timing.quotaRefreshInterval
        guard accountNeedsRefresh || quotaNeedsRefresh else { return }

        refreshTask = Task { [weak self] in
            await self?.refreshInBackground()
        }
    }

    /// When the figures want reading again.
    ///
    /// A nil read date means the read is already due, and the next refresh
    /// schedules it without needing a wake-up of its own. Both are skipped
    /// while there is no screen, mirroring the guard in ``readIfStale()``:
    /// left standing they would be deadlines no refresh could clear -- the
    /// store wakes, the read is refused, the deadline is still in the past --
    /// and the screen coming back is already an edge.
    ///
    /// A retry backoff defers each due date rather than being a wake-up of its
    /// own: waking at a bare retry marker asks a reader that may have decided
    /// it has nothing to do, which leaves the marker in the past forever.
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

    /// Stops a read in flight. The connection it was reading over is going
    /// away, and its answer would describe a server this app no longer holds.
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
        // Every window the read produced, not just the first: rebuilding this
        // through the single-window initialiser is what used to throw the
        // second one away before the footer could draw it.
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
