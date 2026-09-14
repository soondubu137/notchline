// How an update is told and installed (`docs/updates-on-the-notch.md`), as values: what Sparkle
// and a press did, the phase that leaves the panel in, and what About and Settings draw for it.
// `AppUpdater` turns Sparkle's callbacks into ``UpdateEvent``s and carries out the effects.
import Foundation

/// A version the feed offers, named the way the panel names it.
nonisolated struct UpdateVersion: Equatable, Sendable {
    /// `0.5.0`, `CFBundleShortVersionString`.
    let shortVersion: String
    /// `0.5.0 Alpha`: the item's title without `Notchline `. `build-release.sh` writes that title
    /// from the changelog heading, so the stage word comes from the release, not from this build.
    let name: String
    /// `17`, `CFBundleVersion`, which is what Sparkle compares.
    let build: String
    /// The version's GitHub release page.
    let releaseNotesURL: URL

    init(shortVersion: String, title: String?, build: String, releaseNotesURL: URL? = nil) {
        self.shortVersion = shortVersion
        let prefix = "Notchline "
        let named = title.map { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : $0 }?
            .trimmingCharacters(in: .whitespaces)
        name = named.flatMap { $0.isEmpty ? nil : $0 } ?? shortVersion
        self.build = build
        self.releaseNotesURL = releaseNotesURL
            ?? AppVersion.repositoryURL.appendingPathComponent("releases/tag/v\(shortVersion)")
    }
}

/// What a check you asked for says when it finds no version.
nonisolated enum UpdateAnswer: Equatable, Sendable {
    /// 03.
    case upToDate(checkedAt: Date)
    /// 10: never called up to date (rule 10).
    case newerThanLatest(latestName: String)
    /// 11: offline, a 404 and a feed that does not parse all read the same.
    case feedUnreachable
}

/// The About panel's thirteen states, less the three that are this one read another way: 09 is
/// ``idle`` with a receipt, 13 is ``waiting`` in a copy that cannot be replaced, and 05 is
/// ``waiting`` already downloaded.
nonisolated indirect enum UpdatePhase: Equatable, Sendable {
    /// 01.
    case idle
    /// 02. An answer arriving before ``UpdateFlow/minimumCheckingTime`` waits here (rule 4).
    case checking(since: Date, answer: UpdatePhase?)
    /// 03, 10 and 11, until About closes.
    case answered(UpdateAnswer)
    /// 04, or 05 when the archive is already here.
    case waiting(UpdateVersion, downloaded: Bool)
    /// 06.
    case downloading(UpdateVersion, received: UInt64, expected: UInt64?)
    /// 07.
    case verifying(UpdateVersion)
    /// 08: ready, and waiting for rows that a relaunch would cut off (rule 7).
    case holdingRelaunch(UpdateVersion)
    /// 12: nothing was replaced.
    case failed(UpdateVersion)

    /// The version the panel is about, which the version line points to.
    var version: UpdateVersion? {
        switch self {
        case .idle, .checking, .answered: nil
        case let .waiting(version, _), let .downloading(version, _, _), let .verifying(version),
             let .holdingRelaunch(version), let .failed(version):
            version
        }
    }
}

/// Sparkle's `SPUUserUpdateStage`.
nonisolated enum UpdateStage: Equatable, Sendable {
    case notDownloaded
    case downloaded
    /// Downloaded and handed to the installer: replying Install relaunches at once.
    case installing
}

/// Sparkle's `SPUUserUpdateChoice`.
nonisolated enum UpdateChoice: Equatable, Sendable {
    case install
    case skip
    case dismiss
}

/// Which of Sparkle's reply blocks is being held for a press.
nonisolated enum UpdateReply: Equatable, Sendable {
    case none
    /// `showUpdateFoundWithAppcastItem:state:reply:`.
    case found(UpdateStage)
    /// `showReadyToInstallAndRelaunch:`.
    case readyToInstall
    /// The delegate's `immediateInstallationBlock` for a background download.
    case installOnQuit
}

/// A press made while no reply was held, carried out when Sparkle offers that build again.
nonisolated enum UpdateIntent: Equatable, Sendable {
    case install(build: String)
    case skip(build: String)

    var build: String {
        switch self {
        case let .install(build), let .skip(build): build
        }
    }
}

/// The rows a relaunch would cut off (rule 7). A request answered on the notch goes back through
/// Notchline to the hook's stdout. A Turn still running would lose its next hook event, `Stop`
/// included, because launch restores nothing (`system-architecture.md` §2.1), so it holds too.
nonisolated struct RelaunchHold: Equatable, Sendable {
    var approvals = 0
    var questions = 0
    var runningTurns = 0

    static let none = RelaunchHold()

    var isEmpty: Bool { approvals + questions + runningTurns == 0 }

    /// The gloss after `Ready.`: `Relaunches once the approval is answered.`
    var sentence: String {
        let requests = approvals + questions
        switch (requests, runningTurns) {
        case (0, 0): return "Relaunches now."
        case (1, 0): return "Relaunches once the \(approvals == 1 ? "approval" : "question") is answered."
        case (_, 0): return "Relaunches once the requests are answered."
        case (0, 1): return "Relaunches once the running turn finishes."
        case (0, _): return "Relaunches once the running turns finish."
        default: return "Relaunches once every turn is done."
        }
    }
}

/// Something that happened: a Sparkle callback, a press, or the panel opening or closing.
nonisolated enum UpdateEvent: Equatable, Sendable {
    /// `showUserInitiatedUpdateCheckWithCancellation:`.
    case checkStarted
    /// `showUpdateFoundWithAppcastItem:state:reply:`.
    case found(UpdateVersion, stage: UpdateStage, userInitiated: Bool)
    /// `showUpdateNotFoundWithError:acknowledgement:`, which only a check you asked for reaches.
    case notFound(UpdateAnswer)
    /// `showUpdaterError:acknowledgement:`, which a scheduled check never reaches (rule 3).
    case failed
    case downloadStarted
    case expectedLength(UInt64)
    case received(UInt64)
    case extracting
    /// `showReadyToInstallAndRelaunch:`, after an Install press.
    case readyToInstall
    /// The delegate's `willInstallUpdateOnQuit`: a background download finished.
    case installOnQuitReady(UpdateVersion)
    /// `dismissUpdateInstallation`.
    case sessionEnded
    case minimumCheckingTimeElapsed
    case aboutVisibilityChanged(Bool)
    case holdChanged(RelaunchHold)
    case checkPressed
    case installPressed
    case skipPressed
    case cancelPressed
    case relaunchNowPressed
    case tryAgainPressed
}

/// What `AppUpdater` must do with Sparkle, the clock or the defaults.
nonisolated enum UpdateEffect: Equatable, Sendable {
    case answerFound(UpdateChoice)
    case answerReadyToInstall(UpdateChoice)
    case installNow
    case cancelDownload
    case check
    case endMinimumCheckingTime(at: Date)
    /// Written just before the relaunch, so the next launch can draw 09.
    case recordReceipt(UpdateVersion)
    case clearReceipt
}

nonisolated struct UpdateFlow: Equatable, Sendable {
    /// Rule 4: a fast answer does not flash past.
    static let minimumCheckingTime: TimeInterval = 0.6

    private(set) var phase: UpdatePhase = .idle
    /// The dot on the About mark (§2).
    private(set) var hasUnreadVersion = false
    /// 09: the version this launch was updated to, until About has closed once.
    private(set) var receipt: UpdateVersion?
    private(set) var reply: UpdateReply = .none
    private(set) var intent: UpdateIntent?
    private(set) var hold: RelaunchHold = .none
    /// A copy macOS translocated, or one on a read-only volume, cannot be replaced (13).
    let cannotBeReplaced: Bool

    private var pendingRelaunch: UpdateEffect?
    private var isAboutVisible = false
    private var receiptWasShown = false

    init(cannotBeReplaced: Bool = false, receipt: UpdateVersion? = nil) {
        self.cannotBeReplaced = cannotBeReplaced
        self.receipt = receipt
    }

    mutating func receive(_ event: UpdateEvent, at now: Date) -> [UpdateEffect] {
        switch event {
        case .checkStarted:
            // A press carried out through a fresh check says what it is doing, not "Checking…".
            guard intent == nil else { return [] }
            phase = .checking(since: now, answer: nil)
            return [.endMinimumCheckingTime(at: now.addingTimeInterval(Self.minimumCheckingTime))]

        case let .found(version, stage, userInitiated):
            reply = .found(stage)
            if let intent, intent.build == version.build {
                self.intent = nil
                switch intent {
                case .install: return install(version, stage: stage)
                case .skip: return skip()
                }
            }
            intent = nil
            let waiting = UpdatePhase.waiting(version, downloaded: stage != .notDownloaded)
            if userInitiated {
                settle(on: waiting, at: now)
            } else {
                phase = waiting
                hasUnreadVersion = !isAboutVisible
            }
            return []

        case let .notFound(answer):
            reply = .none
            if intent != nil {
                intent = nil
                phase = .answered(answer)
            } else {
                settle(on: .answered(answer), at: now)
            }
            return []

        case .failed:
            intent = nil
            pendingRelaunch = nil
            switch phase {
            case let .downloading(version, _, _), let .verifying(version), let .holdingRelaunch(version):
                phase = .failed(version)
            default:
                settle(on: .answered(.feedUnreachable), at: now)
            }
            return []

        case .downloadStarted:
            if let version = phase.version {
                phase = .downloading(version, received: 0, expected: nil)
            }
            return []

        case let .expectedLength(length):
            if case let .downloading(version, received, _) = phase {
                phase = .downloading(version, received: received, expected: length)
            }
            return []

        case let .received(length):
            if case let .downloading(version, received, expected) = phase {
                phase = .downloading(version, received: received + length, expected: expected)
            }
            return []

        case .extracting:
            if let version = phase.version {
                phase = .verifying(version)
            }
            return []

        case .readyToInstall:
            reply = .readyToInstall
            guard let version = phase.version else { return [] }
            return relaunch(version, through: .answerReadyToInstall(.install))

        case let .installOnQuitReady(version):
            reply = .installOnQuit
            phase = .waiting(version, downloaded: true)
            hasUnreadVersion = !isAboutVisible
            return []

        case .sessionEnded:
            if reply != .installOnQuit { reply = .none }
            switch phase {
            case .checking(_, nil):
                phase = .idle
            case let .downloading(version, _, _), let .verifying(version):
                // Cancel goes back to 04.
                phase = .waiting(version, downloaded: false)
            case let .holdingRelaunch(version) where reply == .none:
                pendingRelaunch = nil
                phase = .waiting(version, downloaded: true)
            default:
                break
            }
            intent = nil
            return []

        case .minimumCheckingTimeElapsed:
            if case let .checking(_, answer?) = phase {
                phase = answer
            }
            return []

        case .aboutVisibilityChanged(true):
            isAboutVisible = true
            hasUnreadVersion = false
            receiptWasShown = receipt != nil
            return []

        case .aboutVisibilityChanged(false):
            isAboutVisible = false
            var effects: [UpdateEffect] = []
            if receiptWasShown {
                receipt = nil
                receiptWasShown = false
                effects.append(.clearReceipt)
            }
            switch phase {
            case .answered:
                phase = .idle
            case let .failed(version):
                phase = .waiting(version, downloaded: false)
            case .waiting:
                // Closed without a choice: Sparkle offers it again at its next daily check (q05).
                if case .found = reply {
                    reply = .none
                    effects.append(.answerFound(.dismiss))
                }
            default:
                break
            }
            return effects

        case let .holdChanged(newHold):
            hold = newHold
            guard newHold.isEmpty, case let .holdingRelaunch(version) = phase,
                  let pending = pendingRelaunch else { return [] }
            pendingRelaunch = nil
            return [.recordReceipt(version), pending]

        case .checkPressed:
            switch phase {
            case .idle, .answered: return [.check]
            default: return []
            }

        case .tryAgainPressed:
            switch phase {
            case let .failed(version):
                // Downloads the archive afresh.
                intent = .install(build: version.build)
                phase = .downloading(version, received: 0, expected: nil)
                return [.check]
            case .answered(.feedUnreachable):
                return [.check]
            default:
                return []
            }

        case .installPressed:
            guard !cannotBeReplaced, case let .waiting(version, downloaded) = phase else { return [] }
            hasUnreadVersion = false
            switch reply {
            case let .found(stage):
                return install(version, stage: stage)
            case .installOnQuit:
                return relaunch(version, through: .installNow)
            case .none, .readyToInstall:
                intent = .install(build: version.build)
                phase = downloaded
                    ? .verifying(version)
                    : .downloading(version, received: 0, expected: nil)
                return [.check]
            }

        case .skipPressed:
            guard case let .waiting(version, _) = phase else { return [] }
            if case .found = reply { return skip() }
            // Skipping a background download also cancels its install on quit.
            intent = .skip(build: version.build)
            phase = .idle
            hasUnreadVersion = false
            return [.check]

        case .cancelPressed:
            guard case let .downloading(version, _, _) = phase else { return [] }
            phase = .waiting(version, downloaded: false)
            return [.cancelDownload]

        case .relaunchNowPressed:
            guard case let .holdingRelaunch(version) = phase, let pending = pendingRelaunch else {
                return []
            }
            pendingRelaunch = nil
            return [.recordReceipt(version), pending]
        }
    }

    private mutating func install(_ version: UpdateVersion, stage: UpdateStage) -> [UpdateEffect] {
        hasUnreadVersion = false
        switch stage {
        case .installing:
            // Replying Install here quits and relaunches at once, so it is the relaunch.
            return relaunch(version, through: .answerFound(.install))
        case .downloaded:
            reply = .none
            phase = .verifying(version)
            return [.answerFound(.install)]
        case .notDownloaded:
            reply = .none
            phase = .downloading(version, received: 0, expected: nil)
            return [.answerFound(.install)]
        }
    }

    private mutating func skip() -> [UpdateEffect] {
        reply = .none
        phase = .idle
        hasUnreadVersion = false
        return [.answerFound(.skip)]
    }

    /// Rule 7: only once nothing on the notch would be cut off, or on Relaunch Now.
    private mutating func relaunch(
        _ version: UpdateVersion,
        through effect: UpdateEffect
    ) -> [UpdateEffect] {
        guard hold.isEmpty else {
            phase = .holdingRelaunch(version)
            pendingRelaunch = effect
            return []
        }
        phase = .verifying(version)
        return [.recordReceipt(version), effect]
    }

    /// A check you asked for answers no sooner than ``minimumCheckingTime`` after it began.
    private mutating func settle(on target: UpdatePhase, at now: Date) {
        if case let .checking(since, _) = phase,
           now < since.addingTimeInterval(Self.minimumCheckingTime) {
            phase = .checking(since: since, answer: target)
        } else {
            phase = target
        }
    }
}

// MARK: - What the surfaces draw

/// What a press asks for.
nonisolated enum UpdateAction: Equatable, Sendable {
    case check
    case install
    case skip
    case cancel
    case relaunchNow
    case tryAgain
    case whatsNew(URL)
    case showInFinder
}

/// One control on the About panel's row (§3's weights).
nonisolated struct AboutUpdateControlSpec: Equatable, Sendable {
    enum Weight: Equatable, Sendable {
        /// `label` on nothing; takes the quiet ground under the pointer.
        case bare
        /// `themeInk.on` at `0.14`.
        case quiet
        /// `themeInk.on` at `1.0`: at most one, on the step that changes the app.
        case ground
    }

    let label: String
    let weight: Weight
    /// `nil` takes no press and dims its label (02).
    let action: UpdateAction?
    /// Drawn at another label's width, so the tile does not change size (02).
    var widthOf: String?
}

/// The About panel's control row: a reading, an optional meter inside it, then controls.
nonisolated struct AboutUpdateRow: Equatable, Sendable {
    /// Light 13 in `reading`.
    var lead: String?
    /// A `120 × 3` meter after the lead, filled this far.
    var meter: Double?
    /// In `label`.
    var gloss: String?
    var controls: [AboutUpdateControlSpec] = []

    static let checkLabel = "Check for Updates"

    init(lead: String? = nil, meter: Double? = nil, gloss: String? = nil,
         controls: [AboutUpdateControlSpec] = []) {
        self.lead = lead
        self.meter = meter
        self.gloss = gloss
        self.controls = controls
    }

    init(_ flow: UpdateFlow, timeZone: TimeZone = .current, locale: Locale = .current) {
        switch flow.phase {
        case .idle:
            if let receipt = flow.receipt {
                self.init(controls: [.init(
                    label: "What’s New in \(receipt.shortVersion) ↗",
                    weight: .quiet,
                    action: .whatsNew(receipt.releaseNotesURL)
                )])
            } else {
                self.init(controls: [.init(label: Self.checkLabel, weight: .quiet, action: .check)])
            }
        case .checking:
            self.init(controls: [.init(
                label: "Checking…", weight: .quiet, action: nil, widthOf: Self.checkLabel
            )])
        case let .answered(.upToDate(checkedAt)):
            self.init(
                lead: "Up to date",
                gloss: "  ·  checked \(UpdateWording.time(checkedAt, timeZone: timeZone, locale: locale))"
            )
        case let .answered(.newerThanLatest(latestName)):
            self.init(lead: "Newer than \(latestName),", gloss: " the latest release")
        case .answered(.feedUnreachable):
            self.init(
                lead: "Couldn’t reach the update feed.",
                controls: [.init(label: "Try Again", weight: .quiet, action: .check)]
            )
        case let .waiting(version, downloaded):
            if flow.cannotBeReplaced {
                self.init(
                    lead: "Move Notchline to Applications",
                    gloss: " to update it.",
                    controls: [.init(label: "Show in Finder", weight: .quiet, action: .showInFinder)]
                )
            } else {
                self.init(controls: [
                    .init(label: "Skip This Version", weight: .bare, action: .skip),
                    .init(label: "What’s New ↗", weight: .quiet, action: .whatsNew(version.releaseNotesURL)),
                    .init(
                        label: downloaded ? "Relaunch to Update" : "Install and Relaunch",
                        weight: .ground,
                        action: .install
                    ),
                ])
            }
        case let .downloading(_, received, expected):
            self.init(
                lead: "Downloading",
                meter: UpdateWording.fraction(received: received, expected: expected),
                gloss: UpdateWording.amount(received: received, expected: expected),
                controls: [.init(label: "Cancel", weight: .bare, action: .cancel)]
            )
        case let .verifying(version):
            self.init(lead: "Verifying \(version.name)", meter: 1)
        case .holdingRelaunch:
            self.init(
                lead: "Ready.",
                gloss: " \(flow.hold.sentence)",
                controls: [.init(label: "Relaunch Now", weight: .quiet, action: .relaunchNow)]
            )
        case let .failed(version):
            self.init(
                lead: "\(version.shortVersion) didn’t verify,",
                gloss: " so nothing was installed.",
                controls: [.init(label: "Try Again", weight: .quiet, action: .tryAgain)]
            )
        }
    }
}

/// The Updates pane's `Notchline` row (§5): a caption with a status dot, or a meter, then capsules.
nonisolated struct UpdateSettingsRow: Equatable, Sendable {
    enum Tone: Equatable, Sendable {
        case idle
        case pending
        case warning
    }

    struct Control: Equatable, Sendable {
        let label: String
        let action: UpdateAction?
        var isProminent = false
    }

    var tone: Tone = .idle
    var caption: String
    var meter: Double?
    var controls: [Control]

    init(tone: Tone = .idle, caption: String, meter: Double? = nil, controls: [Control]) {
        self.tone = tone
        self.caption = caption
        self.meter = meter
        self.controls = controls
    }

    init(
        _ flow: UpdateFlow,
        lastAnsweredCheck: Date?,
        now: Date,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) {
        let checkNow = Control(label: "Check Now", action: .check)
        switch flow.phase {
        case .idle, .answered(.upToDate):
            let checked = lastAnsweredCheck.map {
                "Up to date · checked \(UpdateWording.day($0, now: now, timeZone: timeZone, locale: locale))"
            }
            self.init(caption: checked ?? "Not checked yet", controls: [checkNow])
        case .checking:
            self.init(caption: "Checking…", controls: [Control(label: "Check Now", action: nil)])
        case let .answered(.newerThanLatest(latestName)):
            self.init(caption: "Newer than \(latestName), the latest release", controls: [checkNow])
        case .answered(.feedUnreachable):
            self.init(
                tone: .warning,
                caption: "Couldn’t reach the update feed.",
                controls: [Control(label: "Try Again", action: .check)]
            )
        case let .waiting(version, downloaded):
            if flow.cannotBeReplaced {
                self.init(
                    tone: .warning,
                    caption: "Move Notchline to Applications to update it.",
                    controls: [Control(label: "Show in Finder", action: .showInFinder)]
                )
            } else {
                self.init(
                    tone: .pending,
                    caption: "\(version.name) is waiting",
                    controls: [
                        Control(label: "What’s New", action: .whatsNew(version.releaseNotesURL)),
                        Control(
                            label: downloaded ? "Relaunch to Update" : "Install and Relaunch",
                            action: .install,
                            isProminent: true
                        ),
                    ]
                )
            }
        case let .downloading(_, received, expected):
            self.init(
                caption: UpdateWording.amount(received: received, expected: expected),
                meter: UpdateWording.fraction(received: received, expected: expected),
                controls: [Control(label: "Cancel", action: .cancel)]
            )
        case let .verifying(version):
            self.init(caption: "Verifying \(version.name)", meter: 1, controls: [])
        case .holdingRelaunch:
            self.init(
                tone: .pending,
                caption: "Ready. \(flow.hold.sentence)",
                controls: [Control(label: "Relaunch Now", action: .relaunchNow)]
            )
        case let .failed(version):
            self.init(
                tone: .warning,
                caption: "\(version.shortVersion) didn’t verify, so nothing was installed.",
                controls: [Control(label: "Try Again", action: .tryAgain)]
            )
        }
    }
}

nonisolated enum UpdateWording {
    /// `3.1 of 8.4 MB`. Decimal megabytes, as Finder counts; the received figure is never rounded
    /// up, so it cannot read complete before it is.
    static func amount(received: UInt64, expected: UInt64?) -> String {
        let megabyte = 1_000_000.0
        func figure(_ bytes: UInt64) -> String {
            let tenths = (Double(bytes) / megabyte * 10).rounded(.down) / 10
            return String(format: "%.1f", tenths)
        }
        guard let expected, expected > 0 else { return "\(figure(received)) MB" }
        return "\(figure(min(received, expected))) of \(figure(expected)) MB"
    }

    /// `0` while the length is unknown; never above `1`.
    static func fraction(received: UInt64, expected: UInt64?) -> Double {
        guard let expected, expected > 0 else { return 0 }
        return min(Double(received) / Double(expected), 1)
    }

    /// `14:02`, in the reader's own clock.
    static func time(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        style.locale = locale
        return date.formatted(style)
    }

    /// `today at 14:02`, `yesterday at 09:15`, or `on 12 Sept`.
    static func day(_ date: Date, now: Date, timeZone: TimeZone, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let clock = time(date, timeZone: timeZone, locale: locale)
        if calendar.isDate(date, inSameDayAs: now) {
            return "today at \(clock)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday at \(clock)"
        }
        var style = Date.FormatStyle().day().month(.abbreviated)
        style.timeZone = timeZone
        style.locale = locale
        return "on \(date.formatted(style))"
    }
}
