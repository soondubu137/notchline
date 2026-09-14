import AppKit
import Foundation
import Testing
@testable import Notchline

/// `docs/updates-on-the-notch.md`: the thirteen About states, the rules, and the Updates pane, as
/// the flow decides them. Sparkle's reply blocks are effects here, so every rule is checked
/// without a feed.
@MainActor
struct UpdateFlowTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let version = UpdateVersion(shortVersion: "0.5.0", title: "Notchline 0.5.0 Alpha", build: "17")
    private let london = TimeZone(identifier: "Europe/London")!
    private let british = Locale(identifier: "en_GB")

    private func row(_ flow: UpdateFlow) -> AboutUpdateRow {
        AboutUpdateRow(flow, timeZone: london, locale: british)
    }

    // MARK: - Naming

    @Test func aFeedItemIsNamedByItsTitleWithoutTheAppName() {
        #expect(version.name == "0.5.0 Alpha")
        #expect(version.releaseNotesURL.absoluteString
            == "https://github.com/soondubu137/notchline/releases/tag/v0.5.0")
        #expect(UpdateVersion(shortVersion: "0.6.0", title: nil, build: "20").name == "0.6.0")
        #expect(UpdateVersion(shortVersion: "1.0.0", title: "Notchline 1.0.0", build: "30").name == "1.0.0")
    }

    // MARK: - §2 and rules 2, 3: a check nobody asked for

    @Test func aScheduledVersionIsTheDotAndNothingElse() {
        var flow = UpdateFlow()
        #expect(flow.receive(.found(version, stage: .notDownloaded, userInitiated: false), at: start).isEmpty)
        #expect(flow.hasUnreadVersion)
        #expect(flow.phase == .waiting(version, downloaded: false))

        _ = flow.receive(.aboutVisibilityChanged(true), at: start)
        #expect(!flow.hasUnreadVersion)
        #expect(row(flow).controls.map(\.label) == ["Skip This Version", "What’s New ↗", "Install and Relaunch"])
        #expect(row(flow).controls.map(\.weight) == [.bare, .quiet, .ground])

        // q05: closed without a choice, Sparkle's next daily check brings the dot back.
        #expect(flow.receive(.aboutVisibilityChanged(false), at: start) == [.answerFound(.dismiss)])
        #expect(!flow.hasUnreadVersion)
        #expect(flow.phase == .waiting(version, downloaded: false))
        _ = flow.receive(.found(version, stage: .notDownloaded, userInitiated: false), at: start + 86_400)
        #expect(flow.hasUnreadVersion)
    }

    @Test func aVersionFoundWhileAboutIsOpenIsAlreadyRead() {
        var flow = UpdateFlow()
        _ = flow.receive(.aboutVisibilityChanged(true), at: start)
        _ = flow.receive(.found(version, stage: .notDownloaded, userInitiated: false), at: start)
        #expect(!flow.hasUnreadVersion)
    }

    // MARK: - Rule 4: a check you asked for always answers

    @Test func aFastAnswerWaitsOutCheckingForSixTenthsOfASecond() {
        var flow = UpdateFlow()
        #expect(flow.receive(.checkPressed, at: start) == [.check])
        #expect(flow.receive(.checkStarted, at: start)
            == [.endMinimumCheckingTime(at: start.addingTimeInterval(0.6))])
        #expect(row(flow).controls == [.init(
            label: "Checking…", weight: .quiet, action: nil, widthOf: "Check for Updates"
        )])

        let answer = UpdateAnswer.upToDate(checkedAt: start.addingTimeInterval(0.2))
        _ = flow.receive(.notFound(answer), at: start.addingTimeInterval(0.2))
        _ = flow.receive(.sessionEnded, at: start.addingTimeInterval(0.2))
        #expect(row(flow).controls.first?.label == "Checking…")

        _ = flow.receive(.minimumCheckingTimeElapsed, at: start.addingTimeInterval(0.6))
        #expect(flow.phase == .answered(answer))
        #expect(row(flow).lead == "Up to date")
        #expect(row(flow).gloss?.hasPrefix("  ·  checked ") == true)

        // Until About closes; opening it again brings the button back.
        _ = flow.receive(.aboutVisibilityChanged(true), at: start.addingTimeInterval(1))
        _ = flow.receive(.aboutVisibilityChanged(false), at: start.addingTimeInterval(2))
        #expect(row(flow).controls.map(\.label) == ["Check for Updates"])
    }

    @Test func aSlowAnswerLandsAtOnce() {
        var flow = UpdateFlow()
        _ = flow.receive(.checkStarted, at: start)
        _ = flow.receive(.found(version, stage: .notDownloaded, userInitiated: true), at: start.addingTimeInterval(2))
        #expect(flow.phase == .waiting(version, downloaded: false))
        #expect(!flow.hasUnreadVersion)
    }

    @Test func aBuildAheadOfTheFeedIsNeverCalledUpToDate() {
        var flow = UpdateFlow()
        _ = flow.receive(.checkStarted, at: start)
        _ = flow.receive(.notFound(.newerThanLatest(latestName: "0.4.3 Alpha")), at: start.addingTimeInterval(1))
        #expect(row(flow) == AboutUpdateRow(lead: "Newer than 0.4.3 Alpha,", gloss: " the latest release"))
    }

    @Test func anUnreachableFeedOffersTryAgain() {
        var flow = UpdateFlow()
        _ = flow.receive(.checkStarted, at: start)
        _ = flow.receive(.failed, at: start.addingTimeInterval(1))
        #expect(row(flow) == AboutUpdateRow(
            lead: "Couldn’t reach the update feed.",
            controls: [.init(label: "Try Again", weight: .quiet, action: .check)]
        ))
        #expect(flow.receive(.checkPressed, at: start.addingTimeInterval(2)) == [.check])
    }

    // MARK: - Installing

    @Test func installDownloadsVerifiesAndRelaunchesWhenNothingWouldBeCutOff() {
        var flow = UpdateFlow()
        _ = flow.receive(.found(version, stage: .notDownloaded, userInitiated: false), at: start)
        #expect(flow.receive(.installPressed, at: start) == [.answerFound(.install)])
        #expect(!flow.hasUnreadVersion)

        _ = flow.receive(.downloadStarted, at: start)
        _ = flow.receive(.expectedLength(8_400_000), at: start)
        _ = flow.receive(.received(3_100_000), at: start)
        let downloading = row(flow)
        #expect(downloading.lead == "Downloading")
        #expect(downloading.gloss == "3.1 of 8.4 MB")
        #expect(downloading.meter.map { abs($0 - 3.1 / 8.4) < 0.0001 } == true)
        #expect(downloading.controls == [.init(label: "Cancel", weight: .bare, action: .cancel)])

        _ = flow.receive(.extracting, at: start)
        #expect(row(flow) == AboutUpdateRow(lead: "Verifying 0.5.0 Alpha", meter: 1))

        #expect(flow.receive(.readyToInstall, at: start)
            == [.recordReceipt(version), .answerReadyToInstall(.install)])
    }

    @Test func aRelaunchWaitsForEveryRowItWouldCutOff() {
        var flow = UpdateFlow()
        _ = flow.receive(.holdChanged(RelaunchHold(approvals: 1)), at: start)
        _ = flow.receive(.found(version, stage: .notDownloaded, userInitiated: false), at: start)
        _ = flow.receive(.installPressed, at: start)
        _ = flow.receive(.extracting, at: start)

        #expect(flow.receive(.readyToInstall, at: start).isEmpty)
        #expect(row(flow) == AboutUpdateRow(
            lead: "Ready.",
            gloss: " Relaunches once the approval is answered.",
            controls: [.init(label: "Relaunch Now", weight: .quiet, action: .relaunchNow)]
        ))

        #expect(flow.receive(.holdChanged(RelaunchHold(runningTurns: 1)), at: start).isEmpty)
        #expect(row(flow).gloss == " Relaunches once the running turn finishes.")

        #expect(flow.receive(.holdChanged(.none), at: start)
            == [.recordReceipt(version), .answerReadyToInstall(.install)])
    }

    @Test func relaunchNowDoesNotWait() {
        var flow = UpdateFlow()
        _ = flow.receive(.holdChanged(RelaunchHold(questions: 2)), at: start)
        _ = flow.receive(.found(version, stage: .downloaded, userInitiated: true), at: start)
        _ = flow.receive(.installPressed, at: start)
        _ = flow.receive(.readyToInstall, at: start)
        #expect(flow.receive(.relaunchNowPressed, at: start)
            == [.recordReceipt(version), .answerReadyToInstall(.install)])
    }

    @Test func cancelGoesBackToTheVersionAndInstallFindsItAgain() {
        var flow = UpdateFlow()
        _ = flow.receive(.found(version, stage: .notDownloaded, userInitiated: false), at: start)
        _ = flow.receive(.installPressed, at: start)
        _ = flow.receive(.downloadStarted, at: start)
        #expect(flow.receive(.cancelPressed, at: start) == [.cancelDownload])
        _ = flow.receive(.sessionEnded, at: start)
        #expect(flow.phase == .waiting(version, downloaded: false))

        // No reply is held any more, so Install goes through a fresh check without saying Checking…
        #expect(flow.receive(.installPressed, at: start) == [.check])
        #expect(flow.receive(.checkStarted, at: start).isEmpty)
        #expect(row(flow).lead == "Downloading")
        #expect(flow.receive(.found(version, stage: .notDownloaded, userInitiated: true), at: start)
            == [.answerFound(.install)])
    }

    // MARK: - Rule 9: Skip hides one version

    @Test func skipHidesOneVersionUntilANewerOne() {
        var flow = UpdateFlow()
        _ = flow.receive(.found(version, stage: .notDownloaded, userInitiated: false), at: start)
        #expect(flow.receive(.skipPressed, at: start) == [.answerFound(.skip)])
        #expect(flow.phase == .idle)
        #expect(!flow.hasUnreadVersion)

        let newer = UpdateVersion(shortVersion: "0.5.1", title: "Notchline 0.5.1 Alpha", build: "18")
        _ = flow.receive(.found(newer, stage: .notDownloaded, userInitiated: false), at: start + 86_400)
        #expect(flow.hasUnreadVersion)
    }

    // MARK: - Rule 8: a background download relaunches only on a press

    @Test func aBackgroundDownloadWaitsForRelaunchToUpdate() {
        var flow = UpdateFlow()
        #expect(flow.receive(.installOnQuitReady(version), at: start).isEmpty)
        #expect(flow.hasUnreadVersion)
        #expect(row(flow).controls.last == .init(label: "Relaunch to Update", weight: .ground, action: .install))
        #expect(flow.receive(.installPressed, at: start) == [.recordReceipt(version), .installNow])
    }

    @Test func skippingABackgroundDownloadAsksSparkleToCancelIt() {
        var flow = UpdateFlow()
        _ = flow.receive(.installOnQuitReady(version), at: start)
        #expect(flow.receive(.skipPressed, at: start) == [.check])
        #expect(flow.receive(.found(version, stage: .installing, userInitiated: true), at: start)
            == [.answerFound(.skip)])
    }

    // MARK: - 12 and 13

    @Test func aDownloadThatDidNotVerifyInstallsNothingAndTriesAfresh() {
        var flow = UpdateFlow()
        _ = flow.receive(.found(version, stage: .notDownloaded, userInitiated: false), at: start)
        _ = flow.receive(.installPressed, at: start)
        _ = flow.receive(.downloadStarted, at: start)
        _ = flow.receive(.failed, at: start)
        #expect(row(flow) == AboutUpdateRow(
            lead: "0.5.0 didn’t verify,",
            gloss: " so nothing was installed.",
            controls: [.init(label: "Try Again", weight: .quiet, action: .tryAgain)]
        ))
        #expect(flow.receive(.tryAgainPressed, at: start) == [.check])
        #expect(flow.intent == .install(build: "17"))
    }

    @Test func aCopyThatCannotBeReplacedIsNeverOfferedInstall() {
        var flow = UpdateFlow(cannotBeReplaced: true)
        _ = flow.receive(.found(version, stage: .notDownloaded, userInitiated: false), at: start)
        #expect(row(flow) == AboutUpdateRow(
            lead: "Move Notchline to Applications",
            gloss: " to update it.",
            controls: [.init(label: "Show in Finder", weight: .quiet, action: .showInFinder)]
        ))
        #expect(flow.receive(.installPressed, at: start).isEmpty)
        #expect(AppUpdater.cannotBeReplaced(URL(fileURLWithPath:
            "/private/var/folders/x/T/AppTranslocation/ABC/d/Notchline.app")))
    }

    // MARK: - 09

    @Test func theFirstAboutAfterTheRelaunchIsTheReceipt() {
        var flow = UpdateFlow(receipt: version)
        #expect(row(flow).controls == [.init(
            label: "What’s New in 0.5.0 ↗", weight: .quiet, action: .whatsNew(version.releaseNotesURL)
        )])
        // A panel that closes without About having been on it keeps the receipt.
        #expect(flow.receive(.aboutVisibilityChanged(false), at: start).isEmpty)
        _ = flow.receive(.aboutVisibilityChanged(true), at: start)
        #expect(flow.receive(.aboutVisibilityChanged(false), at: start) == [.clearReceipt])
        #expect(row(flow).controls.map(\.label) == ["Check for Updates"])
    }

    @Test func theReceiptIsReadOnlyForTheBuildItWasRecordedFor() throws {
        // Unique per run: the suite is hosted by more than one test process at a time.
        let suite = "notchline.update-receipt.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let build = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)

        defaults.set(build, forKey: AppUpdater.receiptDefaultsKey)
        #expect(AppUpdater(defaults: defaults).status.flow.receipt?.build == build)

        defaults.set("\(build)0", forKey: AppUpdater.receiptDefaultsKey)
        #expect(AppUpdater(defaults: defaults).status.flow.receipt == nil)
        #expect(defaults.string(forKey: AppUpdater.receiptDefaultsKey) == nil)
    }

    // MARK: - Rule 7's count

    @Test func theHoldCountsAnswerableRequestsAndWorkingTurns() {
        func session(_ id: String, _ status: SessionStatus, requests: [AgentRequest] = []) -> MonitoredSession {
            MonitoredSession(
                agent: .claudeCode, threadID: id, turnID: "t-\(id)", projectName: "p", title: "t",
                preview: nil, status: status, startedAt: nil, requests: requests
            )
        }
        let answerable = AgentRequest(
            id: "r", toolName: "Bash", form: .command("ls"), answerHandle: AnswerHandle(ticket: 1)
        )
        let readingOnly = AgentRequest(id: "q", toolName: "Bash", form: .command("ls"))
        let hold = RelaunchHold(sessions: [
            session("a", .approvalNeeded, requests: [answerable]),
            session("b", .approvalNeeded, requests: [readingOnly]),
            session("c", .running),
            session("d", .completed),
        ])
        #expect(hold == RelaunchHold(approvals: 1, runningTurns: 1))
        #expect(hold.sentence == "Relaunches once every turn is done.")
        #expect(RelaunchHold(questions: 1).sentence == "Relaunches once the question is answered.")
        #expect(RelaunchHold(approvals: 2).sentence == "Relaunches once the requests are answered.")
        #expect(RelaunchHold(runningTurns: 3).sentence == "Relaunches once the running turns finish.")
    }

    // MARK: - Drawing

    @Test func theAmountIsNeverRoundedUp() {
        #expect(UpdateWording.amount(received: 3_150_000, expected: 8_400_000) == "3.1 of 8.4 MB")
        #expect(UpdateWording.amount(received: 8_399_999, expected: 8_400_000) == "8.3 of 8.4 MB")
        #expect(UpdateWording.amount(received: 3_100_000, expected: nil) == "3.1 MB")
        #expect(UpdateWording.fraction(received: 9, expected: 8) == 1)
        #expect(PanelMetrics.updateMeterFill(0.999) == 119)
        #expect(PanelMetrics.updateMeterFill(1) == 120)
    }

    /// §2: centred on empty cell (4, 4), overhanging the `13` pt glyph by `0.87`, `4.0` clear of
    /// the nearest lit cell (2, 2), whose far corner sits `2 × 32 + 27` of `155` units in.
    @Test func theDotSitsInTheTerracesEmptyCorner() {
        let glyph = PanelMetrics.bandControlGlyphSize
        let centre = PanelMetrics.aboutUpdateDotCentre
        let radius = PanelMetrics.aboutUpdateDotDiameter / 2
        #expect(abs(centre - 11.87) < 0.005)
        #expect(abs(centre + radius - glyph - 0.87) < 0.005)
        let litCorner = glyph * (2 * 32 + 27) / 155
        let clearance = hypot(centre - litCorner, centre - litCorner) - radius
        #expect(abs(clearance - 4.0) < 0.05)
        #expect(centre + radius < PanelMetrics.settingsButtonSize(compactHeight: PanelMetrics.referenceCompactHeight))
    }

    /// Rule 5 means the row can never wrap: the widest thing each state draws fits About's body.
    @Test func everyAboutRowFitsThePanel() {
        let body = PanelMetrics.expandedBaselineWidth - 2 * PanelMetrics.expandedHorizontalPadding
        let font = PanelMetrics.requestControlFont
        func width(_ row: AboutUpdateRow) -> CGFloat {
            var parts: [CGFloat] = []
            let reading = [row.lead, row.gloss].compactMap { $0 }.map { PanelMetrics.textWidth($0, font: font) }
            if !reading.isEmpty || row.meter != nil {
                parts.append(reading.reduce(0, +)
                    + (row.meter == nil ? 0 : PanelMetrics.updateMeterWidth + 2 * PanelMetrics.aboutUpdateRowSpacing))
            }
            parts += row.controls.map { PanelMetrics.drawnAnswerControlWidth($0.widthOf ?? $0.label) }
            return parts.reduce(0, +) + CGFloat(max(parts.count - 1, 0)) * PanelMetrics.aboutUpdateRowSpacing
        }

        var flows: [(String, UpdateFlow)] = []
        func add(_ name: String, _ events: [UpdateEvent], cannotBeReplaced: Bool = false) {
            var flow = UpdateFlow(cannotBeReplaced: cannotBeReplaced)
            for event in events { _ = flow.receive(event, at: start.addingTimeInterval(5)) }
            flows.append((name, flow))
        }
        let found = UpdateEvent.found(version, stage: .notDownloaded, userInitiated: false)
        add("04", [found])
        add("05", [.found(version, stage: .downloaded, userInitiated: false)])
        add("06", [found, .installPressed, .downloadStarted, .expectedLength(88_800_000), .received(88_700_000)])
        add("08", [.holdChanged(RelaunchHold(approvals: 3, runningTurns: 2)), found, .installPressed, .readyToInstall])
        add("10", [.notFound(.newerThanLatest(latestName: "10.44.33 Alpha"))])
        add("11", [.checkPressed, .failed])
        add("12", [found, .installPressed, .downloadStarted, .failed])
        add("13", [found], cannotBeReplaced: true)
        for (name, flow) in flows {
            let drawn = width(row(flow))
            #expect(drawn <= body, "\(name) is \(drawn) pt, past \(body)")
        }
    }

    @Test func thePaneSaysWhatAboutSaysInTheWindowsWords() {
        let noon = try! Date("2026-09-14T13:02:00Z", strategy: .iso8601)
        func settings(_ flow: UpdateFlow, checked: Date? = noon) -> UpdateSettingsRow {
            UpdateSettingsRow(flow, lastAnsweredCheck: checked, now: noon, timeZone: london, locale: british)
        }
        #expect(settings(UpdateFlow()) == UpdateSettingsRow(
            caption: "Up to date · checked today at 14:02",
            controls: [.init(label: "Check Now", action: .check)]
        ))
        #expect(settings(UpdateFlow(), checked: nil).caption == "Not checked yet")
        #expect(settings(UpdateFlow(), checked: noon.addingTimeInterval(-86_400)).caption
            == "Up to date · checked yesterday at 14:02")

        var waiting = UpdateFlow()
        _ = waiting.receive(.found(version, stage: .notDownloaded, userInitiated: false), at: noon)
        #expect(settings(waiting) == UpdateSettingsRow(
            tone: .pending,
            caption: "0.5.0 Alpha is waiting",
            controls: [
                .init(label: "What’s New", action: .whatsNew(version.releaseNotesURL)),
                .init(label: "Install and Relaunch", action: .install, isProminent: true),
            ]
        ))

        _ = waiting.receive(.installPressed, at: noon)
        _ = waiting.receive(.downloadStarted, at: noon)
        #expect(settings(waiting).meter == 0)
        #expect(settings(waiting).controls == [.init(label: "Cancel", action: .cancel)])
    }

    /// The pane's footnote runs the card's width, like every group's.
    @Test func theUpdatesFootnoteFitsOnOneLine() {
        let font = NSFont.systemFont(ofSize: 11)
        let width = (SettingsCaption.updatesFootnote as NSString).size(withAttributes: [.font: font]).width
        #expect(width <= 532 - 2)
    }

    /// One line each, in the row's caption column less its widest capsules.
    @Test func everyUpdatesCaptionFitsOnOneLine() {
        let font = NSFont.systemFont(ofSize: 11)
        let column: CGFloat = 532 - 2 * 14 - 12 - 200
        let captions = [
            "Up to date · checked yesterday at 23:59",
            "Newer than 10.44.33 Alpha, the latest release",
            "Couldn’t reach the update feed.",
            "Move Notchline to Applications to update it.",
            "10.44.33 Alpha is waiting",
            "Ready. \(RelaunchHold(approvals: 1).sentence)",
            "Ready. \(RelaunchHold(runningTurns: 2).sentence)",
            "10.44.33 didn’t verify, so nothing was installed.",
        ]
        for caption in captions {
            let width = (caption as NSString).size(withAttributes: [.font: font]).width
            #expect(width <= column, "\(caption) is \(width) pt, past \(column)")
        }
    }
}
