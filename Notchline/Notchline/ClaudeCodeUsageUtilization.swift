import Foundation

/// Claude Code's own record of its rate-limit windows: `cachedUsageUtilization` in
/// `~/.claude.json`, written by the CLI when a usage fetch lands (throttled to one write per five
/// minutes).
///
/// Replaces parsing the command's prose (ADR 0007). Adds the per-model window's model
/// (`scope.model.display_name`) and `fetchedAtMs`, so an answer from an unrefreshed cache reads as
/// old. A shape change fails as a decode, not as a silently missing number.
nonisolated enum ClaudeCodeUsageUtilization {
    /// The two windows this product always reports, and this app's names for them
    /// (`quota-footer-v2.md` §12.4). `Current week (all models)` shortens to `All models`.
    static let sessionLabel = "Current session"
    static let allModelsLabel = "All models"

    /// What `limits` calls each window. The two fixed ones are matched by `kind`; anything else with
    /// a model on it is a per-model cap.
    private static let sessionKind = "session"
    private static let weeklyAllKind = "weekly_all"
    private static let weeklyScopedKind = "weekly_scoped"

    /// The object as `~/.claude.json` holds it; all optional, as windows vary per account.
    private struct Cached: Decodable {
        let fetchedAtMs: Double?
        let utilization: Utilization?
    }

    private struct Utilization: Decodable {
        /// The list form, which is the one that names a per-model cap.
        let limits: [Limit]?
        /// The two fixed windows, published separately; read only when `limits` is absent.
        let fiveHour: Window?
        let sevenDay: Window?

        enum CodingKeys: String, CodingKey {
            case limits
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    private struct Limit: Decodable {
        let kind: String?
        /// Reported as used; a rule draws what is left.
        let percent: Double?
        let resetsAt: String?
        let scope: Scope?

        enum CodingKeys: String, CodingKey {
            case kind
            case percent
            case resetsAt = "resets_at"
            case scope
        }
    }

    private struct Scope: Decodable {
        let model: Model?
    }

    private struct Model: Decodable {
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }

    private struct Window: Decodable {
        /// Also used, 0–100 like `Limit.percent`.
        let utilization: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    /// The root of `~/.claude.json`; only one key is read.
    private struct Configuration: Decodable {
        let cachedUsageUtilization: Cached?
    }

    /// The windows this app draws, or nil when the file is unreadable, empty, or past `ceiling`.
    ///
    /// - Parameter ceiling: Maximum age from `fetchedAtMs`; Claude Code's own reader stops at one hour.
    static func windows(
        in data: Data,
        now: Date,
        ceiling: TimeInterval
    ) -> [QuotaWindow]? {
        guard let decoded = try? JSONDecoder().decode(Configuration.self, from: data),
              let cached = decoded.cachedUsageUtilization,
              let fetchedAtMs = cached.fetchedAtMs,
              let utilization = cached.utilization else {
            return nil
        }

        // A stamp in the future is a disagreeing clock, not a fresh reading; it fails like a stale one.
        let age = now.timeIntervalSince(Date(timeIntervalSince1970: fetchedAtMs / 1000))
        guard age >= 0, age <= ceiling else { return nil }

        if let limits = utilization.limits, !limits.isEmpty {
            return windows(fromLimits: limits)
        }
        return [
            window(
                labelled: sessionLabel,
                usedPercent: utilization.fiveHour?.utilization,
                resetsAt: utilization.fiveHour?.resetsAt
            ),
            window(
                labelled: allModelsLabel,
                usedPercent: utilization.sevenDay?.utilization,
                resetsAt: utilization.sevenDay?.resetsAt
            )
        ]
    }

    /// The two fixed windows (always drawn, `--` if omitted), then per-model caps in file order
    /// (`quota-footer-v2.md` §5).
    private static func windows(fromLimits limits: [Limit]) -> [QuotaWindow] {
        let session = limits.first { $0.kind == sessionKind }
        let weekly = limits.first { $0.kind == weeklyAllKind }
        var parsed = [
            window(
                labelled: sessionLabel,
                usedPercent: session?.percent,
                resetsAt: session?.resetsAt
            ),
            window(
                labelled: allModelsLabel,
                usedPercent: weekly?.percent,
                resetsAt: weekly?.resetsAt
            )
        ]
        for limit in limits {
            // A scoped week with no model has no label, so it is dropped.
            guard limit.kind == weeklyScopedKind,
                  let model = limit.scope?.model?.displayName,
                  !model.isEmpty else {
                continue
            }
            parsed.append(
                window(
                    labelled: model,
                    usedPercent: limit.percent,
                    resetsAt: limit.resetsAt
                )
            )
        }
        return parsed
    }

    private static func window(
        labelled label: String,
        usedPercent: Double?,
        resetsAt: String?
    ) -> QuotaWindow {
        QuotaWindow(
            label: label,
            // Reported as used. A figure outside 0–100 is an unrecognised shape: unavailable, not clamped.
            remainingPercent: usedPercent
                .filter { $0.isFinite && (0 ... 100).contains($0) }
                .map { 100 - Int($0.rounded()) },
            resetsAt: resetsAt.flatMap(date(from:))
        )
    }

    /// `2026-09-08T07:10:00.303358+00:00` to an instant; the six-digit fraction is dropped first
    /// (`ISO8601DateFormatter` expects three).
    private static func date(from stamp: String) -> Date? {
        let withoutFraction = stamp.replacingOccurrences(
            of: #"\.\d+"#,
            with: "",
            options: .regularExpression
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: withoutFraction)
    }
}

private extension Optional {
    func filter(_ isIncluded: (Wrapped) -> Bool) -> Wrapped? {
        guard let self, isIncluded(self) else { return nil }
        return self
    }
}
