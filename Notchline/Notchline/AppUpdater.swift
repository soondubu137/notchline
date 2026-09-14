import AppKit
import Combine
import Foundation
import Observation
import Sparkle
import os

/// What About and Settings draw about updates, and nothing else (`updates-on-the-notch.md`).
///
/// Observable per property, so the About mark, which reads only ``dot``, is not redrawn by a
/// download's progress. A property is written only when its value changes.
@MainActor
@Observable
final class UpdateStatus {
    /// Every phase, for the About row and the Settings pane. Progress arrives at most 4 times a second.
    private(set) var flow = UpdateFlow()
    /// The version the About mark's dot stands for, while it is unread.
    private(set) var dot: UpdateVersion?
    /// The version the version line and the closing row point to.
    private(set) var version: UpdateVersion?
    /// When a check last got an answer from the feed, scheduled or asked for.
    private(set) var lastAnsweredCheck: Date?
    /// `false` while hosting tests or in a build with no public key; the controls then do nothing.
    private(set) var isAvailable = false
    private(set) var automaticallyChecks = false
    private(set) var automaticallyDownloads = false

    func publish(_ flow: UpdateFlow) {
        if self.flow != flow { self.flow = flow }
        let dot = flow.hasUnreadVersion ? flow.phase.version : nil
        if self.dot != dot { self.dot = dot }
        if version != flow.phase.version { version = flow.phase.version }
    }

    fileprivate func setLastAnsweredCheck(_ date: Date?) {
        if lastAnsweredCheck != date { lastAnsweredCheck = date }
    }

    fileprivate func setSettings(available: Bool, checks: Bool, downloads: Bool) {
        if isAvailable != available { isAvailable = available }
        if automaticallyChecks != checks { automaticallyChecks = checks }
        if automaticallyDownloads != downloads { automaticallyDownloads = downloads }
    }
}

/// Checks the feed on `master` and installs what it finds (ADR 0022), drawn on the notch rather
/// than in Sparkle's windows (`updates-on-the-notch.md` §1).
///
/// Sparkle trusts an update whose archive carries an EdDSA signature from the key named by
/// `SUPublicEDKey`, or whose bundle satisfies this one's designated requirement. This class only
/// turns Sparkle's callbacks into ``UpdateEvent``s for ``UpdateFlow`` and carries out the effects;
/// every decision is the flow's.
@MainActor
final class AppUpdater: NSObject {
    static let shared = AppUpdater()

    let status = UpdateStatus()

    /// Build that the last relaunch installed; its launch draws 09.
    nonisolated static let receiptDefaultsKey = "updateReceiptBuild"
    /// When a check last got an answer, for the Updates pane's caption.
    nonisolated static let answeredCheckDefaultsKey = "updateCheckAnsweredAt"
    /// Progress redraws at most this often (§3, 06).
    static let progressInterval: TimeInterval = 0.25

    private static let log = Logger(subsystem: "com.yinfenglu.Notchline", category: "AppUpdater")

    private let defaults: UserDefaults
    private var updater: SPUUpdater?
    private var flow: UpdateFlow
    private var subscriptions: Set<AnyCancellable> = []

    private var foundReply: ((SPUUserUpdateChoice) -> Void)?
    private var readyReply: ((SPUUserUpdateChoice) -> Void)?
    private var immediateInstallation: (() -> Void)?
    private var downloadCancellation: (() -> Void)?
    private var lastProgressPublish = Date.distantPast
    private var progressPublishScheduled = false

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        flow = UpdateFlow(
            cannotBeReplaced: Self.cannotBeReplaced(bundle.bundleURL),
            receipt: Self.receipt(in: defaults, bundle: bundle)
        )
        super.init()
        status.publish(flow)
        status.setLastAnsweredCheck(defaults.object(forKey: Self.answeredCheckDefaultsKey) as? Date)
    }

    /// Starts scheduled checks and watches the panel. Does nothing while hosting tests, or in a
    /// build with no public key: nothing could verify an update, and Sparkle would put up an alert
    /// on every launch.
    func start(store: MonitorStore) {
        guard updater == nil, !AppProcess.isHostingTests, Self.hasPublicKey(Bundle.main) else { return }
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: self,
            delegate: self
        )
        do {
            try updater.start()
        } catch {
            Self.log.error("The updater did not start: \(error.localizedDescription, privacy: .public)")
            return
        }
        self.updater = updater
        refreshSettings()

        // About is open while the panel is expanded on it; hover closing the panel closes About too.
        Publishers.CombineLatest(store.$isExpanded, store.$isShowingAbout)
            .map { $0 && $1 }
            .removeDuplicates()
            .sink { [weak self] visible in self?.receive(.aboutVisibilityChanged(visible)) }
            .store(in: &subscriptions)
        store.$sessions
            .map(RelaunchHold.init(sessions:))
            .removeDuplicates()
            .sink { [weak self] hold in self?.receive(.holdChanged(hold)) }
            .store(in: &subscriptions)
    }

    // MARK: - Presses

    func perform(_ action: UpdateAction) {
        switch action {
        case .check: receive(.checkPressed)
        case .install: receive(.installPressed)
        case .skip: receive(.skipPressed)
        case .cancel: receive(.cancelPressed)
        case .relaunchNow: receive(.relaunchNowPressed)
        case .tryAgain: receive(.tryAgainPressed)
        case let .whatsNew(url): NSWorkspace.shared.open(url)
        case .showInFinder: NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        }
    }

    func setAutomaticallyChecks(_ isOn: Bool) {
        updater?.automaticallyChecksForUpdates = isOn
        refreshSettings()
    }

    func setAutomaticallyDownloads(_ isOn: Bool) {
        updater?.automaticallyDownloadsUpdates = isOn
        refreshSettings()
    }

    nonisolated static func hasPublicKey(_ bundle: Bundle) -> Bool {
        guard let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }
        return !key.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Opened straight from Downloads, macOS runs a translocated copy that cannot be replaced;
    /// a disk image cannot be written at all. Sparkle refuses both, so 13 replaces 04 up front.
    nonisolated static func cannotBeReplaced(_ bundleURL: URL) -> Bool {
        if bundleURL.path.contains("/AppTranslocation/") { return true }
        let readOnly = try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly
        return readOnly == true
    }

    /// 09 only for the build the relaunch was for; anything else is a stale key.
    private static func receipt(in defaults: UserDefaults, bundle: Bundle) -> UpdateVersion? {
        guard let recorded = defaults.string(forKey: receiptDefaultsKey) else { return nil }
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard recorded == build,
              let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else {
            defaults.removeObject(forKey: receiptDefaultsKey)
            return nil
        }
        return UpdateVersion(shortVersion: shortVersion, title: AppVersion.name, build: recorded)
    }

    // MARK: - The flow

    private func receive(_ event: UpdateEvent) {
        let effects = flow.receive(event, at: Date())
        switch event {
        case .expectedLength, .received:
            publishProgress()
        default:
            status.publish(flow)
        }
        carryOut(effects)
    }

    private func publishProgress() {
        let now = Date()
        guard now.timeIntervalSince(lastProgressPublish) < Self.progressInterval else {
            lastProgressPublish = now
            status.publish(flow)
            return
        }
        guard !progressPublishScheduled else { return }
        progressPublishScheduled = true
        let delay = Self.progressInterval - now.timeIntervalSince(lastProgressPublish)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            self.progressPublishScheduled = false
            self.lastProgressPublish = Date()
            self.status.publish(self.flow)
        }
    }

    private func carryOut(_ effects: [UpdateEffect]) {
        for effect in effects {
            switch effect {
            case let .answerFound(choice):
                let reply = foundReply
                foundReply = nil
                reply?(choice.sparkle)
            case let .answerReadyToInstall(choice):
                let reply = readyReply
                readyReply = nil
                reply?(choice.sparkle)
            case .installNow:
                // Kept: Sparkle lets it be called again if termination is cancelled.
                immediateInstallation?()
            case .cancelDownload:
                let cancel = downloadCancellation
                downloadCancellation = nil
                cancel?()
            case .check:
                updater?.checkForUpdates()
            case let .endMinimumCheckingTime(deadline):
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(max(deadline.timeIntervalSinceNow, 0)))
                    self?.receive(.minimumCheckingTimeElapsed)
                }
            case let .recordReceipt(version):
                defaults.set(version.build, forKey: Self.receiptDefaultsKey)
            case .clearReceipt:
                defaults.removeObject(forKey: Self.receiptDefaultsKey)
            }
        }
    }

    private func refreshSettings() {
        status.setSettings(
            available: updater != nil,
            checks: updater?.automaticallyChecksForUpdates ?? false,
            downloads: updater?.automaticallyDownloadsUpdates ?? false
        )
    }

    private func recordAnsweredCheck() {
        let now = Date()
        defaults.set(now, forKey: Self.answeredCheckDefaultsKey)
        status.setLastAnsweredCheck(now)
    }

    private static func version(of item: SUAppcastItem) -> UpdateVersion {
        UpdateVersion(
            shortVersion: item.displayVersionString,
            title: item.title,
            build: item.versionString,
            releaseNotesURL: item.fullReleaseNotesURL
        )
    }
}

// MARK: - SPUUserDriver

extension AppUpdater: SPUUserDriver {
    /// Never reached: the build sets `SUEnableAutomaticChecks`.
    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        receive(.checkStarted)
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        // An information-only item has nothing to install; this feed never writes one.
        guard !appcastItem.isInformationOnlyUpdate else {
            reply(.dismiss)
            return
        }
        foundReply = reply
        let stage: UpdateStage = switch state.stage {
        case .downloaded: .downloaded
        case .installing: .installing
        default: .notDownloaded
        }
        receive(.found(Self.version(of: appcastItem), stage: stage, userInitiated: state.userInitiated))
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        let info = (error as NSError).userInfo
        let reason = (info[SPUNoUpdateFoundReasonKey] as? NSNumber)?.int32Value
        let latest = info[SPULatestAppcastItemFoundKey] as? SUAppcastItem
        let answer: UpdateAnswer = if reason == SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue,
                                      let latest {
            .newerThanLatest(latestName: Self.version(of: latest).name)
        } else {
            .upToDate(checkedAt: Date())
        }
        acknowledgement()
        receive(.notFound(answer))
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        Self.log.error("Update failed: \(error.localizedDescription, privacy: .public)")
        acknowledgement()
        receive(.failed)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        downloadCancellation = cancellation
        receive(.downloadStarted)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        receive(.expectedLength(expectedContentLength))
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receive(.received(length))
    }

    func showDownloadDidStartExtractingUpdate() {
        downloadCancellation = nil
        receive(.extracting)
    }

    /// 07's meter is full and still; extraction progress changes nothing drawn.
    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        readyReply = reply
        receive(.readyToInstall)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {}

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        foundReply = nil
        readyReply = nil
        downloadCancellation = nil
        receive(.sessionEnded)
    }

    /// There is no window to bring forward.
    func showUpdateInFocus() {}
}

// MARK: - SPUUpdaterDelegate

extension AppUpdater: SPUUpdaterDelegate {
    /// A background download is ready. Taking the block holds the relaunch for a press (rule 8);
    /// Sparkle still installs it when Notchline quits.
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        immediateInstallation = immediateInstallHandler
        receive(.installOnQuitReady(Self.version(of: item)))
        return true
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        recordAnsweredCheck()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        recordAnsweredCheck()
    }
}

private extension UpdateChoice {
    var sparkle: SPUUserUpdateChoice {
        switch self {
        case .install: .install
        case .skip: .skip
        case .dismiss: .dismiss
        }
    }
}

extension RelaunchHold {
    /// Counted off the rows on the notch: a request still answerable there, and a Turn still
    /// working by the derived status the summary uses.
    nonisolated init(sessions: [MonitoredSession]) {
        self.init()
        for session in sessions {
            for request in session.requests where request.canBeAnswered {
                switch request.form {
                case .question, .questions: questions += 1
                default: approvals += 1
                }
            }
            if MonitorAggregation.effectiveStatus(of: session) == .running {
                runningTurns += 1
            }
        }
    }
}
