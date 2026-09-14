import Foundation
import Sparkle

/// Checks the feed on `master` for a newer build and installs it (`docs/adr/0022`).
///
/// Sparkle trusts an update if its archive carries an EdDSA signature from the key named by
/// `SUPublicEDKey`, or if the new bundle satisfies this one's designated requirement. The release
/// certificate keeps that requirement stable across builds, which is also what keeps the
/// Automation grant.
@MainActor
final class AppUpdater: NSObject {
    static let shared = AppUpdater()

    private var controller: SPUStandardUpdaterController?

    /// Starts scheduled checks. It does nothing while hosting tests, and nothing in a build with no
    /// public key: without the key there is nothing to verify an update against, and Sparkle would
    /// raise an alert on every launch.
    func start() {
        guard controller == nil, !AppProcess.isHostingTests, Self.hasPublicKey(Bundle.main)
        else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }

    /// The About panel's check. It also brings an update session that is already open to the front.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    nonisolated static func hasPublicKey(_ bundle: Bundle) -> Bool {
        guard let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }
        return !key.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

extension AppUpdater: SPUStandardUserDriverDelegate {
    /// An `LSUIElement` app has no Dock icon to badge. Declaring gentle reminders makes Sparkle
    /// show a scheduled update's alert behind the front app instead of taking focus from it.
    var supportsGentleScheduledUpdateReminders: Bool { true }
}
