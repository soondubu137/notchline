//
//  NotchlineApp.swift
//  Notchline
//
//  Created by Yinfeng Lu on 8/10/26.
//

import AppKit
import SwiftUI

/// What this process is: the product, or a host for the product's own tests.
///
/// **A macOS unit-test bundle has no executable.** It is injected into a host
/// application, and this app is its own host — `TEST_HOST` in the project file
/// names this very binary. So every `xcodebuild test` run *is* a launch of the
/// product, on the developer's own machine, beside whatever copy is already
/// running there. Nothing about the suite asks for that: every test builds its
/// own store, on its own paths under `/tmp`.
///
/// What the second copy did instead was take the running one apart. It drew its
/// own overlay in the notch over the one already there; it bound the live hook
/// sockets, which ``AgentHookListener`` did by unlinking whatever was at the
/// path — so the running copy went on holding a socket no helper could reach,
/// for the rest of its life. From the outside that is a notch that blinks, a
/// row that freezes mid-turn and never moves again, and a session started
/// afterwards that never appears at all.
///
/// The two readings are the documented one and a belt to its braces:
/// `XCTestConfigurationFilePath` is what XCTest puts in a host process's
/// environment, and the framework itself is loaded into that process either
/// way.
nonisolated enum AppProcess {
    static let isHostingTests: Bool = {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }()
}

/// Turns a write to a pipe nobody is reading any more into a thrown error,
/// rather than the end of this process.
///
/// `SIGPIPE` is delivered synchronously to the thread that called `write(2)`,
/// and its default disposition is **terminate**. The throwing
/// `FileHandle.write(contentsOf:)` never gets as far as seeing `EPIPE`.
///
/// The one pipe this app writes to is the `codex app-server` subprocess's
/// stdin, and the child's read end closes the instant it goes away -- a crash,
/// a force-quit, a Codex update replacing the binary underneath it. Between
/// that instant and the termination handler reaching
/// ``CodexAppServerClient`` and dropping the write handle, every request that
/// enters -- the background metadata loop, a quota read, a watcher-driven
/// refresh -- writes into a broken pipe, and Notchline died there: no
/// diagnostic, no crash report the user could act on, and most likely against
/// exactly the server that had just been crashing (CR-Fable-006).
///
/// Ignoring the signal is the standard remedy for any process doing pipe or
/// socket I/O, and it belongs to the **process** rather than to the transport:
/// the disposition is process-wide, the suite's hook-socket writes have the
/// same hazard, and `SO_NOSIGPIPE` -- the per-descriptor remedy used there --
/// does not apply to a pipe at all. With it installed the write fails with
/// `EPIPE`, which the transport already reads as a disconnect and reconnects
/// from.
nonisolated enum BrokenPipeSignal {
    /// Installs the disposition. Idempotent, and one syscall.
    static func ignore() {
        signal(SIGPIPE, SIG_IGN)
    }

    /// Whether this process would survive that write.
    ///
    /// Read back from the kernel rather than from a flag ``ignore()`` set: an
    /// installer that answers questions about its own installation can only
    /// report that it ran, which is not the thing that has to be true.
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
        // Hosting the test bundle is not running the product — see
        // ``AppProcess``. The store answers the same way (it is built with no
        // services at all), so this is the surface half of one decision rather
        // than a second one.
        guard !AppProcess.isHostingTests else { return }
        overlayController = OverlayPanelController(store: .shared)
        overlayController?.show()
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
    /// The identifier of the onboarding-and-settings window.
    ///
    /// A `Window` scene needs one, and it is also the key AppKit remembers the
    /// window's position under -- so it is spelled once here rather than
    /// written out wherever it happens to be needed.
    private static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = MonitorStore.shared

    /// Here rather than in the delegate, because this runs first.
    ///
    /// The store is what starts the App Server transport, and SwiftUI builds it
    /// when it first evaluates the scenes below -- which is after this
    /// initialiser and before `applicationDidFinishLaunching(_:)`. Nothing in
    /// this process may write to a pipe before ``BrokenPipeSignal/ignore()``
    /// has run, and this is the earliest point that is true of.
    init() {
        BrokenPipeSignal.ignore()
    }

    var body: some Scene {
        // A single `Window` rather than a `WindowGroup`, and suppressed at
        // launch once the user has been through onboarding.
        //
        // Both halves are the same decision. A `WindowGroup` opens one of its
        // windows on every launch and there is no way to ask it not to --
        // `defaultLaunchBehavior(.suppressed)` is ignored on the first group,
        // measured on macOS 26.5 -- so this app put its **whole settings
        // window** on screen every time it started, and paid for it: building
        // and laying out that view tree, plus the tracking-area pass the new
        // window triggers, is **half of the launch's CPU** (`0.62 s -> 0.32 s`
        // of a Release launch, peak `%cpu` `55 -> 33`; see
        // `system-architecture.md` §6). Nothing asked for that window: the
        // product is the overlay, and the same view is one `⌘,` away in the
        // `Settings` scene below.
        //
        // There is exactly one launch that does want it, and that is the
        // first: onboarding has to appear without being sent for.
        Window("Notchline", id: Self.mainWindowID) {
            ProductRootView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(
            store.hasCompletedOnboarding ? .suppressed : .presented
        )

        // The tracker hands this scene's window to ``SettingsWindowPresenter``,
        // which is what makes `⌘,` land in front of the user on the display
        // they are working on rather than wherever the window was last closed.
        Settings {
            AppSettingsView()
                .environmentObject(store)
                .background(SettingsWindowTracker())
        }
        .windowResizability(.contentSize)
    }
}
