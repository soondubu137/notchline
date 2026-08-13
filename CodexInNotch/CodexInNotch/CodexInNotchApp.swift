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
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = MonitorStore.shared

    var body: some Scene {
        WindowGroup("Codex in Notch") {
            ProductRootView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)

        Settings {
            AppSettingsView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
    }
}
