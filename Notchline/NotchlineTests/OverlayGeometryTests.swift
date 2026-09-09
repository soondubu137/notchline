import AppKit
import SwiftUI
import Testing
@testable import Notchline

struct OverlayGeometryTests {
    @Test @MainActor
    func closingKeepsTheLiveBodyUntilItsFadeEndsThenReleasesIt() async {
        let clock = TestClock()
        let presentation = OverlayBodyPresentation(clock: clock)
        presentation.setExpanded(true)
        presentation.setExpanded(false)
        await clock.settle()
        #expect(presentation.isMounted)
        #expect(clock.sleeperCount == 1)
        await clock.advance(by: PanelMotion.duration / 2)
        #expect(presentation.isMounted)
        await clock.advance(by: PanelMotion.duration / 2 + 0.001)
        #expect(!presentation.isMounted)
        #expect(clock.sleeperCount == 0)
    }

    @Test @MainActor
    func reopeningCancelsRemovalAndDisappearanceLeavesNoSleeper() async {
        let clock = TestClock()
        let presentation = OverlayBodyPresentation(clock: clock)
        presentation.setExpanded(true)
        presentation.setExpanded(false)
        await clock.settle()
        await clock.advance(by: PanelMotion.duration / 2)
        presentation.setExpanded(true)
        await clock.advance(by: PanelMotion.duration)
        #expect(presentation.isMounted)
        #expect(clock.sleeperCount == 0)
        presentation.setExpanded(false)
        await clock.settle()
        presentation.cancel()
        await clock.settle()
        #expect(!presentation.isMounted)
        #expect(clock.sleeperCount == 0)
    }

    @Test @MainActor
    func theLiveListKeepsThePresentedWidthWhenExpansionChangesItsTarget() {
        let store = MonitorStore(preferences: nil)
        for width in [CGFloat(280), 420, 610] {
            let host = NSHostingView(
                rootView: ActiveSessionList()
                    .environmentObject(store)
                    .environment(\.overlayBodyWidth, width)
            )
            host.frame.size = NSSize(width: width, height: store.sessionViewportHeight)
            for expanded in [true, false, true] {
                store.isExpanded = expanded
                host.layoutSubtreeIfNeeded()
                #expect(
                    abs(host.fittingSize.width
                        - PanelMetrics.sessionViewportWidth(panelWidth: width)) < 0.01
                )
            }
        }
    }

    /// The grouped list draws at the height the panel was sized to, and the
    /// blocks it draws are the ones the store counted.
    ///
    /// **The fault this exists for is a disagreement, not a wrong number.**
    /// Every height on this panel is composed twice — once to size the window
    /// and once to lay the list out — and the two are only the same while they
    /// are the same call. An open question got a panel sized for its `400` pt
    /// row and a viewport still capped at `240` that way, and a heading is a
    /// second term with exactly the same shape: counted in the window and
    /// forgotten in the list, it would clip the last row under the footer and
    /// paint a strip of panel below it.
    ///
    /// So this hosts the real list, at the real viewport height, and asks the
    /// laid-out tree how many headings it actually put in — `AnatomyPin`'s own
    /// lesson, that a formula still evaluating is not the same as a part still
    /// being drawn.
    @Test @MainActor
    func theGroupedListDrawsTheHeadingsThePanelWasSizedFor() {
        let store = MonitorStore(services: [], preferences: nil)
        func session(_ agent: AgentKind, _ id: String) -> MonitoredSession {
            MonitoredSession(
                agent: agent,
                threadID: id, turnID: "u-\(id)", projectName: "p", title: "t",
                preview: nil, status: .running, startedAt: nil
            )
        }
        func snapshot(_ agent: AgentKind, _ sessions: [MonitoredSession]) -> AgentSnapshot {
            AgentSnapshot(
                agent: agent, availability: .ready, sessions: sessions,
                quota: .unavailable, diagnostic: nil, setupStatus: .active,
                presence: .open
            )
        }
        store.isExpanded = true
        store.applyForTesting(snapshot(.codex, [session(.codex, "a"), session(.codex, "b")]))
        store.applyForTesting(snapshot(.claudeCode, [session(.claudeCode, "c")]))

        let width = store.currentPanelSize.width
        let host = NSHostingView(
            rootView: ActiveSessionList()
                .environmentObject(store)
                .environment(\.overlayBodyWidth, width)
        )
        host.frame.size = NSSize(width: width, height: store.sessionViewportHeight)
        host.layoutSubtreeIfNeeded()

        // The list stands in exactly the room the window gave it -- three
        // rows and two headings, and nothing left over.
        #expect(
            store.sessionViewportHeight
                == PanelMetrics.sessionRowHeight * 3
                    + PanelMetrics.productGroupHeaderHeight * 2
        )
        #expect(abs(host.fittingSize.height - store.sessionViewportHeight) < 0.01)

        #expect(store.sessionGroupHeaderCount == 2)
    }

    /// The heading itself is the `32` the arithmetic above spends on it, and
    /// it draws the chip and the rule that make it one.
    ///
    /// Hosted on its own and read off the bitmap rather than off the metric,
    /// because the metric is the thing under test: `productGroupHeaderHeight`
    /// is `recentSeamHeight` by definition and would agree with itself however
    /// the bar were drawn. What cannot agree with itself is the ink — the
    /// chip's lit text is the brightest value in the bar's own band, and a
    /// heading that had quietly lost its badge would leave that band as dark
    /// as the panel behind it.
    ///
    /// No run loop is turned here: the bar is not in a `ScrollView`, so it is
    /// laid out and drawn in the same pass. See ``AnatomyFigureRenderer`` for
    /// what a specimen that does hold the actor costs the answering suite.
    @Test @MainActor
    func theBlockHeadingIsThirtyTwoAndDrawsItsChip() throws {
        let header = ProductGroupHeader(
            group: MonitorAggregation.SessionGroup(
                agent: .codex,
                sessions: [
                    MonitoredSession(
                        agent: .codex,
                        threadID: "a", turnID: "u", projectName: "p", title: "t",
                        preview: nil, status: .running, startedAt: nil
                    )
                ],
                wantsAttention: false
            )
        )
        let width = PanelMetrics.sessionViewportWidth(panelWidth: 520)
        let host = NSHostingView(rootView: header.frame(width: width))
        host.frame = NSRect(x: 0, y: 0, width: width, height: PanelMetrics.productGroupHeaderHeight)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()

        #expect(
            abs(host.fittingSize.height - PanelMetrics.productGroupHeaderHeight) < 0.01
        )

        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        // The rep is in backing pixels, which are not points on every machine.
        let across = CGFloat(rep.pixelsWide) / host.bounds.width
        let down = CGFloat(rep.pixelsHigh) / host.bounds.height
        // The chip stands on the panel's own `12`, `8` down and `16` tall, so
        // its text is inside this box wherever the product's name ends.
        var brightest: CGFloat = 0
        for x in stride(from: 14.0, to: 70.0, by: 1) {
            for y in stride(from: 10.0, to: 22.0, by: 1) {
                guard
                    let colour = rep
                        .colorAt(x: Int(x * across), y: Int(y * down))?
                        .usingColorSpace(.deviceRGB)
                else { continue }
                brightest = max(brightest, colour.brightnessComponent)
            }
        }
        #expect(
            brightest > 0.8,
            "the heading drew no chip — brightest value in its band was \(brightest)"
        )
    }

    @Test @MainActor
    func aStandaloneListStillUsesItsSpecimensChosenWidth() {
        let store = MonitorStore(preferences: nil)
        store.isExpanded = true
        let host = NSHostingView(rootView: ActiveSessionList().environmentObject(store))
        host.layoutSubtreeIfNeeded()
        #expect(
            abs(host.fittingSize.width
                - PanelMetrics.sessionViewportWidth(panelWidth: store.currentPanelSize.width)) < 0.01
        )
    }
}
