//
//  CodexInNotchApp.swift
//  CodexInNotch
//
//  Created by Yinfeng Lu on 8/10/26.
//

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayController: OverlayPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlayController = OverlayPanelController(store: .shared)
        overlayController?.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        MonitorStore.shared.stopMonitoring()
    }
}

@main
struct CodexInNotchApp: App {
    /// The identifier of the onboarding-and-settings window.
    ///
    /// A `Window` scene needs one, and it is also the key AppKit remembers the
    /// window's position under -- so it is spelled once here rather than
    /// written out wherever it happens to be needed.
    private static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = MonitorStore.shared

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
        Window("Codex in Notch", id: Self.mainWindowID) {
            ProductRootView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(
            store.hasCompletedOnboarding ? .suppressed : .presented
        )

        Settings {
            AppSettingsView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
    }
}
