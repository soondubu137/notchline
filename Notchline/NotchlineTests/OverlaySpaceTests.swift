import AppKit
import Synchronization
import Testing
@testable import Notchline

@Suite(.serialized) @MainActor
struct OverlaySpaceTests {
    @Test
    func repeatedRecoveryKeepsTheOriginalPolicyAndNeverTakesKeys() async throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        let panel = fixture.panel
        let original = panel.collectionBehavior.union(.ignoresCycle)
        panel.collectionBehavior = original

        panel.recoverSpaceMembership()
        #expect(panel.collectionBehavior.contains(.moveToActiveSpace))
        #expect(!panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(!panel.isKeyWindow)
        // A frame update or another Space notification can arrive before AppKit finishes ordering.
        panel.recoverSpaceMembership()
        #expect(panel.collectionBehavior.contains(.moveToActiveSpace))

        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(panel.collectionBehavior == original)
        #expect(panel.isVisible)
        #expect(!panel.isKeyWindow)
    }

    @Test
    func concealmentDuringRecoveryDoesNotBringTheWindowBack() async throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        let panel = fixture.panel
        let original = panel.collectionBehavior
        panel.recoverSpaceMembership()
        panel.orderOut(nil)

        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(panel.collectionBehavior == original)
        #expect(!panel.isVisible)
    }

    @Test
    func aSpaceChangeRestoresAllSpacesWithoutTakingTheKeyboard() throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        fixture.controller.show()
        let panel = fixture.panel
        let frame = panel.frame
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        panel.collectionBehavior.insert(.ignoresCycle)
        panel.orderOut(nil)

        fixture.changeSpace()

        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.stationary))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.ignoresCycle))
        #expect(!panel.collectionBehavior.contains(.moveToActiveSpace))
        #expect(panel.isVisible)
        #expect(!panel.isKeyWindow)
        #expect(panel.frame == frame)
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost)
    }

    @Test
    func aSpaceChangeReadsTheNewMenuBarBeforeRestoringThePanel() throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        fixture.controller.show()
        #expect(fixture.panel.isVisible)

        fixture.windows.value.withLock { $0 = [] }
        fixture.changeSpace()
        #expect(fixture.watcher.isConcealed)
        #expect(!fixture.panel.isVisible)

        // A second switch with the same verdict must not order the concealed panel front.
        fixture.changeSpace()
        #expect(fixture.panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(!fixture.panel.isVisible)

        fixture.windows.value.withLock { $0 = [Fixture.menuBar] }
        fixture.changeSpace()
        #expect(!fixture.watcher.isConcealed)
        #expect(fixture.panel.isVisible)
    }

    @MainActor private final class Fixture {
        // Real AppKit ordering, off screen; never depend on the user's monitor or lock state.
        static let bounds = CGRect(x: -20_000, y: 0, width: 1_920, height: 1_080)
        static let menuBar = ChromeWindow(
            owner: OverlayConcealment.windowServerOwner,
            layer: OverlayConcealment.menuBarLayer,
            bounds: CGRect(x: -20_000, y: 0, width: 1_920, height: 24)
        )
        let windows = WindowReading([Fixture.menuBar])
        let store: MonitorStore
        let watcher: OverlayConcealmentWatcher
        let controller: OverlayPanelController
        let panel: OverlayPanel

        init() throws {
            let display = DisplayOption(
                id: "space-test", displayID: 7, ordinal: 1, name: "Test display",
                frame: Self.bounds,
                visibleFrame: Self.bounds.insetBy(dx: 0, dy: 24),
                safeAreaInsets: NSEdgeInsets(), auxiliaryTopLeftArea: nil,
                auxiliaryTopRightArea: nil, fallbackMenuBarHeight: 24
            )
            store = MonitorStore(displays: [display], services: [], preferences: nil)
            let windows = windows
            let bounds = Self.bounds
            watcher = OverlayConcealmentWatcher(
                interval: 3_600,
                sampleWindows: { windows.value.withLock { $0 } },
                boundsOfDisplay: { _ in bounds },
                boundsOfActiveDisplays: { [bounds] },
                screenAvailability: AvailableScreen()
            )
            let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
            controller = OverlayPanelController(store: store, concealmentWatcher: watcher)
            panel = try #require(NSApp.windows.first {
                !existing.contains(ObjectIdentifier($0)) && $0 is OverlayPanel
            } as? OverlayPanel)
        }

        func changeSpace() {
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
            )
        }

        func stop() {
            panel.orderOut(nil)
            watcher.stop()
            store.stopMonitoring()
        }
    }

    private nonisolated struct AvailableScreen: ScreenAvailabilityReporting {
        func isAvailable() -> Bool { true }
        func changeEvents() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    }

    private nonisolated final class WindowReading: Sendable {
        let value: Mutex<[ChromeWindow]>
        init(_ windows: [ChromeWindow]) { value = Mutex(windows) }
    }
}
