import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Notchline

/// Where the grouped list's headings stand at each offset — the two badge
/// lines of `expanded-panel-v2.md` §4.6, pinned on the pure layout rather than
/// on a drawing, because the layout is the design: the same offset always
/// gives the same positions, and scrolling back is the same function run in
/// reverse.
struct ProductTrailLayoutTests {
    private func session(_ agent: AgentKind, _ id: String, _ status: SessionStatus = .running) -> MonitoredSession {
        MonitoredSession(
            agent: agent,
            threadID: id, turnID: "u-\(id)", projectName: "p", title: "t",
            preview: nil, status: status, startedAt: nil
        )
    }

    /// Two blocks: Codex holding `first` rows and Claude Code `second`.
    private func groups(first: Int, second: Int, secondWaits: Bool = false) -> [MonitorAggregation.SessionGroup] {
        var sessions = (0..<first).map { session(.codex, "c\($0)") }
        sessions += (0..<second).map { session(.claudeCode, "k\($0)", $0 == 0 && secondWaits ? .approvalNeeded : .running) }
        return MonitorAggregation.groups(of: sessions)
    }

    private func snapshot(_ agent: AgentKind, _ sessions: [MonitoredSession]) -> AgentSnapshot {
        AgentSnapshot(
            agent: agent, availability: .ready, sessions: sessions,
            quota: .unavailable, diagnostic: nil, setupStatus: .active,
            presence: .open
        )
    }

    private func layout(
        _ groups: [MonitorAggregation.SessionGroup],
        offset: CGFloat
    ) -> ProductTrailLayout {
        let content = PanelMetrics.sessionListContentHeight(
            liveRowCount: groups.reduce(0) { $0 + $1.sessions.count },
            groupHeaderCount: groups.count
        )
        let viewport = PanelMetrics.sessionViewportHeight(
            liveRowCount: groups.reduce(0) { $0 + $1.sessions.count },
            groupHeaderCount: groups.count
        )
        return ProductTrailLayout.laidOut(
            groups: groups,
            badgeWidths: groups.map { PanelMetrics.productBadgeWidth($0.agent.displayName) },
            offset: offset,
            viewportHeight: viewport,
            contentHeight: content
        )
    }

    /// **The grouped cap is a badge line, four rows and a badge line**, and
    /// the flat cap is the same four rows without the lines — so the switch
    /// never changes how many rows are on screen.
    @Test
    func theGroupedViewportIsATrailFourRowsAndATrail() {
        #expect(PanelMetrics.productTrailHeight == 16)
        #expect(PanelMetrics.sessionViewportCap == PanelMetrics.sessionRowHeight * 4)
        #expect(PanelMetrics.groupedSessionViewportCap == CGFloat(16 + 288 + 16))

        // Grouped: two blocks and eight rows ask for `16 + 360 + 32 + 216`
        // and are given the cap.
        #expect(
            PanelMetrics.sessionListContentHeight(liveRowCount: 8, groupHeaderCount: 2) == 624
        )
        #expect(
            PanelMetrics.sessionViewportHeight(liveRowCount: 8, groupHeaderCount: 2) == 320
        )
        // A list that fits is given what it asks for, and no more.
        #expect(
            PanelMetrics.sessionViewportHeight(liveRowCount: 2, groupHeaderCount: 2) == 192
        )
        // Flat: the same eight rows are four rows on screen.
        #expect(PanelMetrics.sessionViewportHeight(liveRowCount: 8) == 288)

        // An open row taller than the cap is given its own room under its
        // heading, so nothing is left for a rail to offer.
        #expect(
            PanelMetrics.sessionViewportHeight(liveRowCount: 1, openRowHeight: 400, groupHeaderCount: 1)
                == 416
        )
    }

    /// **At rest, every heading is on screen.** The first holds the top strip
    /// where its chip has always stood; a block below the fold waits on the
    /// foot line as a name alone, and the foot draws its ground.
    @Test
    func aBlockBelowTheFoldWaitsOnTheFootLine() {
        let blocks = groups(first: 5, second: 3)
        let rest = layout(blocks, offset: 0)

        #expect(rest.scrolls)
        #expect(rest.drawsTopStrip)
        #expect(rest.drawsFootLine)
        #expect(rest.headings.count == 2)

        let codex = rest.headings[0]
        #expect(codex.x == PanelMetrics.sessionRowPadding)
        #expect(codex.y == 0)
        #expect(codex.tail == 1)
        #expect(codex.trailed == 0)
        #expect(codex.flowChip == 0)

        let claude = rest.headings[1]
        #expect(claude.x == PanelMetrics.sessionRowPadding, "the next block is first on the foot line")
        #expect(claude.y == 320 - PanelMetrics.productTrailHeight)
        #expect(claude.tail == 0, "a foot badge is a name alone")
        #expect(claude.trailed == 1)
        #expect(claude.isOnTrail)
        // Its chip's own place in the flow: the first heading, five rows and
        // its own slack.
        #expect(claude.flowChip == CGFloat(16 + 5 * 72 + 16))
    }

    /// **Lifting off is the foot line's docking played upward**: over the
    /// bar's own `32` the badge rises at the flow's `x` while its count and
    /// rule come in, and it is in the flow — whole — after that.
    @Test
    func aPendingBadgeLiftsStraightUpIntoItsBar() {
        let blocks = groups(first: 5, second: 3)
        let footLine: CGFloat = 320 - 16

        // Halfway: the chip is `16` above the foot line, half its tail drawn.
        let lifting = layout(blocks, offset: 392 - (footLine - 16)).headings[1]
        #expect(lifting.x == PanelMetrics.sessionRowPadding)
        #expect(abs(lifting.y - (footLine - 16)) < 0.001)
        #expect(abs(lifting.tail - 0.5) < 0.001)
        #expect(abs(lifting.trailed - 0.5) < 0.001)

        // Free of the foot: in the flow, at its flow position, whole.
        let free = layout(blocks, offset: 200)
        let flowing = free.headings[1]
        #expect(flowing.y == CGFloat(392 - 200))
        #expect(flowing.tail == 1)
        #expect(flowing.trailed == 0)
        #expect(!free.drawsFootLine, "nothing is pending, so no foot line")
        #expect(free.drawsTopStrip)
    }

    /// **Docking is scroll-linked over the bar's own `32`**: the arriving chip
    /// slides right into its slot faster than it rises — so it never crosses
    /// the badge already there — while the heading it replaces gives up its
    /// count and rule over the same travel. Docked, the top strip is the
    /// passed badge beside the active one, and only the active one draws a
    /// tail.
    @Test
    func anArrivingHeadingDocksBesideThePassedOne() {
        // Enough list under the second block to carry its heading to the top.
        let blocks = groups(first: 5, second: 6)
        let codexWidth = PanelMetrics.productBadgeWidth(AgentKind.codex.displayName)
        let slot = PanelMetrics.sessionRowPadding + codexWidth + PanelMetrics.productBadgePadding

        // Halfway: the chip is `16` from the top, and `x` is already most of
        // the way there.
        let halfway = layout(blocks, offset: 392 - 16)
        let arriving = halfway.headings[1]
        #expect(abs(arriving.y - 16) < 0.001)
        let expectedX = PanelMetrics.sessionRowPadding + (slot - PanelMetrics.sessionRowPadding) * ProductTrailLayout.ease(0.5)
        #expect(abs(arriving.x - expectedX) < 0.001)
        #expect(arriving.tail == 1, "the arriving heading is whole")
        #expect(arriving.trailed == 0)
        // Clear of the chip already there: `87.5%` of the slot at half the
        // travel is past a badge of any name.
        #expect(arriving.x - PanelMetrics.sessionRowPadding > codexWidth * 0.8)
        let leaving = halfway.headings[0]
        #expect(abs(leaving.tail - 0.5) < 0.001)
        #expect(abs(leaving.trailed - 0.5) < 0.001)
        #expect(leaving.x == PanelMetrics.sessionRowPadding)
        #expect(leaving.y == 0)

        // Docked: one line, two names, one tail.
        let docked = layout(blocks, offset: 430)
        let active = docked.headings[1]
        #expect(active.x == slot)
        #expect(active.y == 0)
        #expect(active.tail == 1)
        let passed = docked.headings[0]
        #expect(passed.tail == 0)
        #expect(passed.trailed == 1)
        #expect(passed.isOnTrail)
        #expect(!docked.drawsFootLine)

        // And a click on either badge has somewhere to go: the offset that
        // puts its chip on the top strip.
        #expect(docked.headings.map(\.flowChip) == [0, 392])
    }

    /// **A list that fits pins nothing.** Every position is the flow position
    /// and neither ground is drawn: the drawing is the one the list always
    /// made.
    @Test
    func aListThatFitsIsDrawnInTheFlow() {
        let blocks = groups(first: 1, second: 1)
        let fits = layout(blocks, offset: 0)

        #expect(!fits.scrolls)
        #expect(!fits.drawsTopStrip)
        #expect(!fits.drawsFootLine)
        #expect(fits.headings.map(\.y) == [0, CGFloat(16 + 72 + 16)])
        #expect(fits.headings.map(\.x) == [PanelMetrics.sessionRowPadding, PanelMetrics.sessionRowPadding])
        #expect(fits.headings.map(\.tail) == [1, 1])
        #expect(fits.headings.map(\.trailed) == [0, 0])
    }

    /// **A block that wants a person is the layout's business only as far as
    /// the drawing's inputs go**: the block says so, the heading's `trailed`
    /// says how far onto a trail it is, and the badge flips by that rather
    /// than dimming. The layout itself does not change.
    @Test
    func wantingAPersonDoesNotMoveAHeading() {
        let quiet = layout(groups(first: 5, second: 3), offset: 0)
        let waiting = layout(groups(first: 5, second: 3, secondWaits: true), offset: 0)
        #expect(quiet.headings.map(\.x) == waiting.headings.map(\.x))
        #expect(quiet.headings.map(\.y) == waiting.headings.map(\.y))
        #expect(quiet.headings.map(\.trailed) == waiting.headings.map(\.trailed))
    }

    /// **`Group by product` off is the flat list**: no blocks, no headings, the
    /// panel's own top rule back, and the same four rows on screen.
    @Test @MainActor
    func groupingIsAPreferenceAndOffIsTheFlatList() {
        let store = MonitorStore(services: [], preferences: nil)
        store.applyForTesting(snapshot(.codex, (0..<5).map { session(.codex, "c\($0)") }))
        store.applyForTesting(snapshot(.claudeCode, [session(.claudeCode, "k")]))

        // On by default, and the list is the grouped one.
        #expect(store.groupsSessionsByProduct)
        #expect(store.sessionGroups.map(\.agent) == [.codex, .claudeCode])
        #expect(store.sessionGroupHeaderCount == 2)
        #expect(store.listLeadsWithABlockHeading)
        #expect(store.sessionViewportHeight == PanelMetrics.groupedSessionViewportCap)

        // Off: one list, nothing to head, and four rows still.
        store.groupsSessionsByProduct = false
        #expect(store.sessionGroups.isEmpty)
        #expect(store.sessionGroupHeaderCount == 0)
        #expect(!store.listLeadsWithABlockHeading)
        #expect(store.sessionListContentHeight == PanelMetrics.sessionRowHeight * 6)
        #expect(store.sessionViewportHeight == PanelMetrics.sessionViewportCap)
        #expect(store.sessions.count == 6, "the rows are the same rows")

        store.groupsSessionsByProduct = true
        #expect(store.sessionGroups.map(\.agent) == [.codex, .claudeCode])
    }

    /// **The trails are drawn, at the height the panel was sized to.** Five
    /// Codex rows and one of Claude Code's is `480` of list in a `320`
    /// viewport: at rest the top strip carries Codex's chip whole, and the
    /// foot line carries Claude Code's — dimmed, a name alone — where the
    /// pinned list used to show nothing of it at all.
    ///
    /// Read off the bitmap, because the layout is pinned above and what can
    /// still be wrong is whether the overlay draws it: the chip's text is the
    /// theme ink's lit value and nothing else near the panel's left margin is
    /// that bright.
    @Test @MainActor
    func theFootLineDrawsThePendingBlocksBadge() throws {
        let store = MonitorStore(services: [], preferences: nil)
        store.isExpanded = true
        store.applyForTesting(snapshot(.codex, (0..<5).map { session(.codex, "c\($0)") }))
        store.applyForTesting(snapshot(.claudeCode, [session(.claudeCode, "k")]))
        #expect(store.sessionListContentHeight == 480)
        #expect(store.sessionViewportHeight == PanelMetrics.groupedSessionViewportCap)

        let width = PanelMetrics.sessionViewportWidth(panelWidth: store.currentPanelSize.width)
        let height = store.sessionViewportHeight
        let host = NSHostingView(
            rootView: ActiveSessionList()
                .environmentObject(store)
                .environment(\.overlayBodyWidth, store.currentPanelSize.width)
                .frame(width: width, height: height)
                .background(Color.black)
        )
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()

        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let across = CGFloat(rep.pixelsWide) / host.bounds.width
        let down = CGFloat(rep.pixelsHigh) / host.bounds.height
        func peak(from top: CGFloat, to bottom: CGFloat) -> CGFloat {
            var found: CGFloat = 0
            for x in stride(from: PanelMetrics.sessionRowPadding + 1, to: 80.0, by: 1) {
                for y in stride(from: top, to: bottom, by: 1) {
                    guard
                        let colour = rep
                            .colorAt(x: Int(x * across), y: Int(y * down))?
                            .usingColorSpace(.deviceRGB)
                    else { continue }
                    found = max(found, colour.brightnessComponent)
                }
            }
            return found
        }

        let line = PanelMetrics.productTrailHeight
        let top = peak(from: 1.5, to: line - 1.5)
        #expect(top > 0.8, "the top strip drew no chip — brightest value was \(top)")

        let foot = peak(from: height - line + 1.5, to: height - 1.5)
        #expect(foot > 0.25, "the foot line drew no badge — brightest value was \(foot)")
        #expect(foot < top, "a foot badge stands at \(PanelMetrics.productTrailBadgeOpacity), not whole")

        // And the fade above the foot is darker than the foot: rows go out
        // under it rather than being cut by a rule.
        let fade = peak(
            from: height - line - PanelMetrics.productTrailFadeHeight + 1,
            to: height - line - 1
        )
        #expect(fade < foot, "the fade above the foot line is brighter than the badge on it")
    }
}
