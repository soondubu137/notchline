import Foundation

/// Claude Code's own record of its rate-limit windows, read where the product
/// keeps it rather than out of the sentence it prints.
///
/// `~/.claude.json` carries a `cachedUsageUtilization` object: the answer the
/// product's usage endpoint last gave, stamped with when it was fetched. It is
/// written by the CLI itself whenever a usage fetch lands — which is what
/// `claude -p "/usage"` performs — throttled so a fetch inside five minutes of
/// the last one writes nothing.
///
/// **This replaces reading the numbers out of the paragraph.** The command's
/// prose was the source under ADR 0007, and every figure came off a regular
/// expression matched against a format nobody guarantees. The same run leaves
/// this object behind, holding the same numbers as JSON, plus two things the
/// paragraph never had:
///
/// - **The per-model window's model, as a field.** `limits` names it in
///   `scope.model.display_name`, so the label that varies is read rather than
///   pulled out from between a `(` and a `)` on a line that also has to be
///   told apart from `94% of your usage was at >150k context`.
/// - **When the answer was fetched.** The paragraph said nothing about its own
///   age, so the reader could only date an answer by when it ran the command.
///   `fetchedAtMs` dates the *reading*, which is the thing that can be stale:
///   a command that answers from a cache it did not refresh now reads as old,
///   instead of as new.
///
/// A shape change here fails as a decode, not as a number quietly gone
/// missing, which is the whole reason the source moved.
nonisolated enum ClaudeCodeUsageUtilization {
    /// The two windows this product always reports, and what this app calls
    /// them.
    ///
    /// The names are unchanged from the prose era (`quota-footer-v2.md` §12.4)
    /// — they were the output's own words then and they are the same windows
    /// now. `Current week (all models)` still shortens to `All models`: the
    /// product name stands above the group, and the week is the only period
    /// that line has.
    static let sessionLabel = "Current session"
    static let allModelsLabel = "All models"

    /// What `limits` calls each window. The two fixed ones are matched by
    /// `kind`; anything else with a model on it is a per-model cap.
    private static let sessionKind = "session"
    private static let weeklyAllKind = "weekly_all"
    private static let weeklyScopedKind = "weekly_scoped"

    /// The object as `~/.claude.json` holds it.
    ///
    /// Every field this app reads is optional, because the product adds and
    /// drops windows per account and this must degrade to "nothing known about
    /// that window" rather than refuse the whole reading.
    private struct Cached: Decodable {
        let fetchedAtMs: Double?
        let utilization: Utilization?
    }

    private struct Utilization: Decodable {
        /// The list form, which is the one that names a per-model cap.
        let limits: [Limit]?
        /// The two fixed windows, also published on their own. Read only when
        /// `limits` is absent — an older shape, or an account the product
        /// reports the short way.
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
        /// Reported as **used**; a rule draws what is left.
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
        /// Also used, on the same 0–100 scale as `Limit.percent` — checked
        /// against an account reporting both, where `five_hour.utilization`
        /// and the `session` limit's `percent` were the same number.
        let utilization: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    /// The root of `~/.claude.json`, of which exactly one key is read.
    private struct Configuration: Decodable {
        let cachedUsageUtilization: Cached?
    }

    /// The windows this app draws, or nil when the file says nothing this app
    /// may use.
    ///
    /// Nil covers three different facts and deliberately does not tell them
    /// apart, because the surface draws the same `--` for all three: the file
    /// could not be read, it holds no reading, or the reading it holds is past
    /// `ceiling`.
    ///
    /// - Parameters:
    ///   - ceiling: How old a fetch may be and still be evidence. **Claude
    ///     Code's own reader stops trusting this object at one hour**, and
    ///     matching that is the whole argument: a number the product itself
    ///     has expired is not one this app should be drawing beside it. It is
    ///     counted from `fetchedAtMs` — the moment the figures were fetched —
    ///     rather than from when this app last ran a command, so an answer
    ///     that came out of somebody else's cache is dated by the fetch behind
    ///     it and not by the run that repeated it.
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

        // A stamp in the future is not a fresh reading, it is a clock that
        // disagrees; it fails the same way a stale one does.
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

    /// The two fixed windows first, then every per-model cap in the order the
    /// file reports them (`quota-footer-v2.md` §5). Nothing sorts.
    ///
    /// The fixed two are drawn whether or not the list names them: the footer
    /// expects two labelled rules from this product, and a window the file
    /// omits is one nothing is known about — which is a `--`, not a missing
    /// row.
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
            // A scoped week with no model on it names nothing, so there is no
            // label to draw it under and it is dropped rather than given one.
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
            // Reported as used; the rule draws what is left. A figure outside
            // the scale is not rounded into it -- it is a shape this app does
            // not recognise, and unavailable is what it says about those.
            remainingPercent: usedPercent
                .filter { $0.isFinite && (0 ... 100).contains($0) }
                .map { 100 - Int($0.rounded()) },
            resetsAt: resetsAt.flatMap(date(from:))
        )
    }

    /// `2026-09-08T07:10:00.303358+00:00` to an instant.
    ///
    /// The fraction is dropped before parsing rather than parsed: the product
    /// writes six digits of it, `ISO8601DateFormatter` is specified for three,
    /// and a reset drawn as a countdown in hours has no use for either. What
    /// is left is a plain internet date-time, which one formatter reads.
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
    /// `nil` unless the value is there *and* passes.
    func filter(_ isIncluded: (Wrapped) -> Bool) -> Wrapped? {
        guard let self, isIncluded(self) else { return nil }
        return self
    }
}
