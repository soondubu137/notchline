import AppKit
import SwiftUI

/// Whether this process is the product or a host for its tests.
///
/// `TEST_HOST` is this binary, so every `xcodebuild test` launches the product; unguarded, it
/// draws a second overlay and binds the live hook sockets. Reads `XCTestConfigurationFilePath`
/// and whether XCTest is loaded.
nonisolated enum AppProcess {
    static let isHostingTests: Bool = {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }()
}

/// Makes a write to a closed pipe throw instead of killing the process.
///
/// `SIGPIPE`'s default is terminate, before `FileHandle.write(contentsOf:)` sees `EPIPE`. The
/// `codex app-server` stdin closes when the child dies, and Notchline died on the next request
/// (CR-Fable-006). Process-wide because the disposition is, and `SO_NOSIGPIPE` does not apply to
/// pipes. The transport treats `EPIPE` as a disconnect.
nonisolated enum BrokenPipeSignal {
    /// Idempotent.
    static func ignore() {
        signal(SIGPIPE, SIG_IGN)
    }

    /// Read back from the kernel, not from a flag ``ignore()`` set.
    static var isIgnored: Bool {
        var current = sigaction()
        guard sigaction(SIGPIPE, nil, &current) == 0 else { return false }
        return unsafeBitCast(current.__sigaction_u.__sa_handler, to: UInt.self)
            == unsafeBitCast(SIG_IGN, to: UInt.self)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayController: OverlayPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosting tests is not running the product (``AppProcess``); the store makes the same call.
        guard !AppProcess.isHostingTests else { return }
        overlayController = OverlayPanelController(store: .shared)
        overlayController?.show()
        AppUpdater.shared.start()

        // Onboarding needs the foreground: an `LSUIElement` app does not activate at launch, so the
        // window would sit behind others and miss Return. Later launches must not activate.
        // `ignoringOtherApps:` because the cooperative `NSApp.activate()` is refused here (measured,
        // Chrome frontmost, launched by `open`).
        guard !MonitorStore.shared.hasCompletedOnboarding else { return }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !AppProcess.isHostingTests else { return }
        MonitorStore.shared.stopMonitoring()
    }
}

@main
struct NotchlineApp: App {
    /// The onboarding-and-settings window's id, also the key AppKit saves its position under.
    private static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Not observed here: as a `@StateObject`, every publish re-evaluated the scenes and cost the
    /// Settings window `14`–`18 ms` of CPU (Release). Computed so it is not built before ``init()``.
    private var store: MonitorStore { .shared }

    /// ``BrokenPipeSignal/ignore()`` must run before the store starts the App Server transport,
    /// which happens when the scenes are first evaluated, before `applicationDidFinishLaunching(_:)`.
    init() {
        BrokenPipeSignal.ignore()
    }

    var body: some Scene {
        // A `Window` suppressed after onboarding: a `WindowGroup` always opens one at launch
        // (`defaultLaunchBehavior(.suppressed)` ignored on macOS 26.5), which was half of launch CPU
        // (`system-architecture.md` §6). Only the first launch needs it, for onboarding.
        Window("Notchline", id: Self.mainWindowID) {
            ProductRootView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(
            store.hasCompletedOnboarding ? .suppressed : .presented
        )

        // The tracker hands this window to ``SettingsWindowPresenter`` so the gear opens it on the
        // user's current display.
        Settings {
            AppSettingsView()
                .environmentObject(store)
                .background(SettingsWindowTracker())
        }
        .windowResizability(.contentSize)
    }
}
