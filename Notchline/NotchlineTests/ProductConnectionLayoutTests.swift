import AppKit
import SwiftUI
import Testing
@testable import Notchline

struct ProductConnectionLayoutTests {
    @Test @MainActor func productStatesAndRepairActionsFitTheSettingsPane() throws {
        let store = MonitorStore(displays: [], services: [])
        let snapshots = [
            AgentSnapshot(agent: .codex, availability: .ready, sessions: [], quota: .noneReported,
                          diagnostic: nil, setupStatus: .reviewRequired, presence: .open),
            AgentSnapshot(agent: .claudeCode, availability: .ready, sessions: [], quota: .noneReported,
                          diagnostic: nil, presence: .open),
            AgentSnapshot(agent: .antigravity, availability: .setupRequired, sessions: [], quota: .noneReported,
                          diagnostic: nil, setupStatus: .repairRequired, presence: .closed),
            AgentSnapshot(agent: .trae, availability: .disconnected, sessions: [], quota: .noneReported,
                          diagnostic: nil, setupStatus: .reviewRequired, presence: .closed)
        ]
        store.applyForTesting(AgentSnapshot(agent: .antigravity, availability: .ready, sessions: [],
                                           quota: .noneReported, diagnostic: nil))
        for snapshot in snapshots { store.applyForTesting(snapshot) }
        let view = SettingsPaneContent { ProductsSettingsPane() }
            .environmentObject(store)
            .frame(width: SettingsWindowLayout.width)
            .background(MacOSWindowColor.windowBackground)
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        #expect(size.width == SettingsWindowLayout.width)
        #expect(size.height < SettingsWindowLayout.paneHeight)
        host.frame.size = size
        host.layoutSubtreeIfNeeded()
        if let path = ProcessInfo.processInfo.environment["NOTCHLINE_CONNECTION_FIGURE"] {
            for (appearance, suffix) in [(NSAppearance.Name.aqua, ""), (.darkAqua, "-dark")] {
                host.appearance = NSAppearance(named: appearance)
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let output = URL(fileURLWithPath: path).deletingPathExtension().path + suffix + ".png"
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: output))
            }
        }
    }
}
