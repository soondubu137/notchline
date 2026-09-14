import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Notchline

/// Heading positions at each offset (`expanded-panel-v2.md` §4.6), pinned on the pure layout.
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

    /// The second block's chip in the flow, composed so §4.2's slack is never a literal here.
    private func secondChip(after rows: Int) -> CGFloat {
        PanelMetrics.leadingProductGroupHeaderHeight
            + PanelMetrics.sessionRowHeight * CGFloat(rows)
            + PanelMetrics.productGroupHeaderSlack
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

    /// The grouped cap is a badge line, four rows and a badge line; the flat cap is the same four
    /// rows, so the switch never changes how many rows are on screen.
    @Test
    func theGroupedViewportIsATrailFourRowsAndATrail() {
        #expect(PanelMetrics.productTrailHeight == 16)
        #expect(PanelMetrics.sessionViewportCap == PanelMetrics.sessionRowHeight * 4)
        #expect(PanelMetrics.groupedSessionViewportCap == CGFloat(16 + 288 + 16))

        // Headings named, not added: the cap must not move when §4.2's heading cost does.
        #expect(
            PanelMetrics.sessionListContentHeight(liveRowCount: 8, groupHeaderCount: 2)
                == PanelMetrics.sessionRowHeight * 8 + PanelMetrics.groupHeadingsHeight(count: 2)
        )
        #expect(
            PanelMetrics.sessionViewportHeight(liveRowCount: 8, groupHeaderCount: 2) == 320
        )
        #expect(
            PanelMetrics.sessionViewportHeight(liveRowCount: 2, groupHeaderCount: 2)
                == PanelMetrics.sessionRowHeight * 2 + PanelMetrics.groupHeadingsHeight(count: 2)
        )
        #expect(PanelMetrics.sessionViewportHeight(liveRowCount: 8) == 288)

        // An open row taller than the cap gets its own room under its heading.
        #expect(
            PanelMetrics.sessionViewportHeight(liveRowCount: 1, openRowHeight: 400, groupHeaderCount: 1)
                == 400 + PanelMetrics.leadingProductGroupHeaderHeight
        )
    }

    /// At rest every heading is on screen: a block below the fold waits on the foot line as a name
    /// alone, and the foot draws its ground.
    @Test
    func aBlockBelowTheFoldWaitsOnTheFootLine() {
        let blocks = groups(first: 5, second: 3)
        let rest = layout(blocks, offset: 0)

        #expect(rest.scrolls)
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
        #expect(claude.flowChip == secondChip(after: 5))
    }

    /// Lifting off is docking played upward: over the bar's height the badge rises at the flow's
    /// `x` while its count and rule come in.
    @Test
    func aPendingBadgeLiftsStraightUpIntoItsBar() {
        let blocks = groups(first: 5, second: 3)
        let footLine: CGFloat = 320 - PanelMetrics.productTrailHeight
        let half = PanelMetrics.productTrailDockingDistance / 2
        let chip = secondChip(after: 5)

        let lifting = layout(blocks, offset: chip - (footLine - half)).headings[1]
        #expect(lifting.x == PanelMetrics.sessionRowPadding)
        #expect(abs(lifting.y - (footLine - half)) < 0.001)
        #expect(abs(lifting.tail - 0.5) < 0.001)
        #expect(abs(lifting.trailed - 0.5) < 0.001)

        let free = layout(blocks, offset: 200)
        let flowing = free.headings[1]
        #expect(flowing.y == chip - 200)
        #expect(flowing.tail == 1)
        #expect(flowing.trailed == 0)
        #expect(!free.drawsFootLine, "nothing is pending, so no foot line")
        #expect(free.scrolls)
    }

    /// Docking is scroll-linked over the bar's height: the arriving chip slides right faster than
    /// it rises, so it never crosses the passed badge, and only the active one draws a tail.
    @Test
    func anArrivingHeadingDocksBesideThePassedOne() {
        let blocks = groups(first: 5, second: 6)
        let codexWidth = PanelMetrics.productBadgeWidth(AgentKind.codex.displayName)
        let slot = PanelMetrics.sessionRowPadding + codexWidth + PanelMetrics.productBadgePadding

        let half = PanelMetrics.productTrailDockingDistance / 2
        let chip = secondChip(after: 5)
        let halfway = layout(blocks, offset: chip - half)
        let arriving = halfway.headings[1]
        #expect(abs(arriving.y - half) < 0.001)
        let expectedX = PanelMetrics.sessionRowPadding + (slot - PanelMetrics.sessionRowPadding) * ProductTrailLayout.ease(0.5)
        #expect(abs(arriving.x - expectedX) < 0.001)
        #expect(arriving.tail == 1, "the arriving heading is whole")
        #expect(arriving.trailed == 0)
        // `87.5%` of the slot at half the travel clears a badge of any name.
        #expect(arriving.x - PanelMetrics.sessionRowPadding > codexWidth * 0.8)
        let leaving = halfway.headings[0]
        #expect(abs(leaving.tail - 0.5) < 0.001)
        #expect(abs(leaving.trailed - 0.5) < 0.001)
        #expect(leaving.x == PanelMetrics.sessionRowPadding)
        #expect(leaving.y == 0)

        let docked = layout(blocks, offset: chip + PanelMetrics.productTrailDockingDistance)
        let active = docked.headings[1]
        #expect(active.x == slot)
        #expect(active.y == 0)
        #expect(active.tail == 1)
        let passed = docked.headings[0]
        #expect(passed.tail == 0)
        #expect(passed.trailed == 1)
        #expect(passed.isOnTrail)
        #expect(!docked.drawsFootLine)

        #expect(docked.headings.map(\.flowChip) == [0, chip])
    }

    /// A list that fits pins nothing and draws no foot line. The leading chip's `16` of top-strip
    /// ground is drawn either way (see ``ProductTrails``).
    @Test
    func aListThatFitsIsDrawnInTheFlow() {
        let blocks = groups(first: 1, second: 1)
        let fits = layout(blocks, offset: 0)

        #expect(!fits.scrolls)
        #expect(!fits.drawsFootLine)
        #expect(fits.headings.map(\.y) == [0, secondChip(after: 1)])
        #expect(fits.headings.map(\.x) == [PanelMetrics.sessionRowPadding, PanelMetrics.sessionRowPadding])
        #expect(fits.headings.map(\.tail) == [1, 1])
        #expect(fits.headings.map(\.trailed) == [0, 0])
    }

    /// A block that wants a person moves no heading; the badge flips by `trailed` rather than
    /// dimming.
    @Test
    func wantingAPersonDoesNotMoveAHeading() {
        let quiet = layout(groups(first: 5, second: 3), offset: 0)
        let waiting = layout(groups(first: 5, second: 3, secondWaits: true), offset: 0)
        #expect(quiet.headings.map(\.x) == waiting.headings.map(\.x))
        #expect(quiet.headings.map(\.y) == waiting.headings.map(\.y))
        #expect(quiet.headings.map(\.trailed) == waiting.headings.map(\.trailed))
    }

    /// `Group by product` off is the flat list: no headings, the panel's top rule back, same rows.
    @Test @MainActor
    func groupingIsAPreferenceAndOffIsTheFlatList() {
        let store = MonitorStore(services: [], preferences: nil)
        store.applyForTesting(snapshot(.codex, (0..<5).map { session(.codex, "c\($0)") }))
        store.applyForTesting(snapshot(.claudeCode, [session(.claudeCode, "k")]))

        #expect(store.groupsSessionsByProduct)
        #expect(store.sessionGroups.map(\.agent) == [.codex, .claudeCode])
        #expect(store.sessionGroupHeaderCount == 2)
        #expect(store.listLeadsWithABlockHeading)
        #expect(store.sessionViewportHeight == PanelMetrics.groupedSessionViewportCap)

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

    /// At rest the top strip draws Codex's chip whole and the foot line Claude Code's, dimmed.
    /// Read off the bitmap: the chip's text is the only ink that bright near the left margin.
    @Test @MainActor
    func theFootLineDrawsThePendingBlocksBadge() throws {
        let store = MonitorStore(services: [], preferences: nil)
        store.isExpanded = true
        store.applyForTesting(snapshot(.codex, (0..<5).map { session(.codex, "c\($0)") }))
        store.applyForTesting(snapshot(.claudeCode, [session(.claudeCode, "k")]))
        #expect(
            store.sessionListContentHeight
                == PanelMetrics.sessionRowHeight * 6 + PanelMetrics.groupHeadingsHeight(count: 2)
        )
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

        // The fade above the foot is darker: rows go out under it rather than being cut by a rule.
        let fade = peak(
            from: height - line - PanelMetrics.productTrailFadeHeight + 1,
            to: height - line - 1
        )
        #expect(fade < foot, "the fade above the foot line is brighter than the badge on it")
    }

    /// Opaque even on a list that fits: mid-resize the scroller keeps its old height, so rows slide
    /// under the chip (reported 2026-09-10). Read over white, above the rule.
    @Test @MainActor
    func aHeadingsLineIsOpaqueOnAListThatFits() throws {
        let store = MonitorStore(services: [], preferences: nil)
        store.isExpanded = true
        // Without this, a store with no service carries Codex's two preview rows.
        store.applyForTesting(snapshot(.codex, []))
        store.applyForTesting(
            snapshot(.claudeCode, [session(.claudeCode, "k0"), session(.claudeCode, "k1")])
        )
        // Fits exactly: nothing is pinned and the rail has no lane.
        #expect(store.sessionGroups.count == 1)
        #expect(store.sessionViewportHeight == store.sessionListContentHeight)

        let width = PanelMetrics.sessionViewportWidth(panelWidth: store.currentPanelSize.width)
        let height = store.sessionViewportHeight
        let host = NSHostingView(
            rootView: ActiveSessionList()
                .environmentObject(store)
                .environment(\.overlayBodyWidth, store.currentPanelSize.width)
                .frame(width: width, height: height)
                .background(Color.white)
        )
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()

        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let across = CGFloat(rep.pixelsWide) / host.bounds.width
        let down = CGFloat(rep.pixelsHigh) / host.bounds.height

        // Past the chip and the count, above the rule: where the heading draws nothing.
        let badge = PanelMetrics.sessionRowPadding
            + PanelMetrics.productBadgeWidth(AgentKind.claudeCode.displayName)
        var brightest: CGFloat = 0
        for x in stride(from: badge + 40, to: width - PanelMetrics.sessionRowPadding, by: 4) {
            for y in stride(from: 2.0, to: PanelMetrics.productTrailHeight / 2 - 1, by: 1) {
                guard
                    let colour = rep
                        .colorAt(x: Int(x * across), y: Int(y * down))?
                        .usingColorSpace(.deviceRGB)
                else { continue }
                brightest = max(brightest, colour.brightnessComponent)
            }
        }
        #expect(brightest < 0.2, "the heading's line let the ground through at \(brightest)")
    }
}
