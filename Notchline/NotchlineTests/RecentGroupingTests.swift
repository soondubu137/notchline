import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Notchline

/// The Recent queue grouped by product (`expanded-panel-v2.md` §4.7): the live list's blocks,
/// headings and trails, at the retired row's height and on a switch of its own.
struct RecentGroupingTests {
    private func departure(
        _ agent: AgentKind,
        _ id: String,
        ago minutes: Int,
        now: Date,
        status: SessionStatus = .completed
    ) -> RecentDeparture {
        RecentDeparture(
            session: MonitoredSession(
                agent: agent,
                threadID: id, turnID: "u-\(id)", projectName: "p", title: "t",
                preview: nil, status: status, startedAt: nil
            ),
            departedAt: now.addingTimeInterval(-TimeInterval(minutes * 60)),
            reason: .read
        )
    }

    /// Codex and Claude Code leaving turn about, Claude Code most recently, so the flat queue and
    /// the grouped one disagree about what comes first.
    private func interleaved(codex: Int, claude: Int, now: Date) -> [RecentDeparture] {
        let codexRows = (0..<codex).map { departure(.codex, "c\($0)", ago: 2 * $0 + 2, now: now) }
        let claudeRows = (0..<claude).map { departure(.claudeCode, "k\($0)", ago: 2 * $0 + 1, now: now) }
        return codexRows + claudeRows
    }

    @MainActor
    private func store(_ departures: [RecentDeparture], expanded: Bool = true) -> MonitorStore {
        let store = MonitorStore(services: [], preferences: nil)
        store.isExpanded = true
        // Without this, a store with no service carries Codex's two preview rows.
        store.applyForTesting(
            AgentSnapshot(
                agent: .codex, availability: .ready, sessions: [],
                quota: .unavailable, diagnostic: nil, setupStatus: .active, presence: .open
            )
        )
        store.isRecentExpanded = expanded
        store.stageSpecimenQueue(departures)
        return store
    }

    /// A trail, five retired rows and a trail: the flat queue shows the same five, so the switch
    /// never changes how many rows are on screen.
    @Test
    func theGroupedQueueIsATrailFiveRowsAndATrail() {
        #expect(PanelMetrics.recentViewportCap == PanelMetrics.retiredRowHeight * 5)
        #expect(PanelMetrics.groupedRecentViewportCap == CGFloat(16 + 180 + 16))

        #expect(
            PanelMetrics.recentContentHeight(retiredRowCount: 8, groupHeaderCount: 2)
                == PanelMetrics.retiredRowHeight * 8 + PanelMetrics.groupHeadingsHeight(count: 2)
        )
        #expect(
            PanelMetrics.recentViewportHeight(retiredRowCount: 8, groupHeaderCount: 2)
                == PanelMetrics.groupedRecentViewportCap
        )
        #expect(
            PanelMetrics.recentViewportHeight(retiredRowCount: 2, groupHeaderCount: 2)
                == PanelMetrics.retiredRowHeight * 2 + PanelMetrics.groupHeadingsHeight(count: 2)
        )
        #expect(
            PanelMetrics.recentViewportHeight(retiredRowCount: 8) == PanelMetrics.recentViewportCap
        )
        // An empty queue has no heading to pay for, grouped or not.
        #expect(PanelMetrics.recentContentHeight(retiredRowCount: 0, groupHeaderCount: 2) == 0)
        #expect(
            PanelMetrics.recentSectionHeight(retiredRowCount: 3, isRecentExpanded: false, groupHeaderCount: 2)
                == PanelMetrics.recentSeamHeight
        )
    }

    /// The live list's layout at `36`: a block below the fold waits on the foot line, and its chip
    /// stands in the flow where the queue's own rows put it.
    @Test
    func aQueueBlockBelowTheFoldWaitsOnTheFootLine() {
        let now = Date()
        let groups = MonitorAggregation.groups(of: interleaved(codex: 6, claude: 2, now: now))
        let content = PanelMetrics.recentContentHeight(retiredRowCount: 8, groupHeaderCount: 2)
        let viewport = PanelMetrics.recentViewportHeight(retiredRowCount: 8, groupHeaderCount: 2)
        let rest = ProductTrailLayout.laidOut(
            groups: groups,
            badgeWidths: groups.map { PanelMetrics.productBadgeWidth($0.agent.displayName) },
            offset: 0,
            viewportHeight: viewport,
            contentHeight: content,
            rowHeight: PanelMetrics.retiredRowHeight
        )

        #expect(rest.scrolls)
        #expect(rest.drawsFootLine)
        #expect(rest.headings.map(\.agent) == [.codex, .claudeCode])
        #expect(rest.headings[0].y == 0)
        #expect(rest.headings[0].tail == 1)

        let claude = rest.headings[1]
        #expect(claude.y == viewport - PanelMetrics.productTrailHeight)
        #expect(claude.tail == 0)
        #expect(claude.trailed == 1)
        #expect(
            claude.flowChip
                == PanelMetrics.leadingProductGroupHeaderHeight
                    + PanelMetrics.retiredRowHeight * 6
                    + PanelMetrics.productGroupHeaderSlack
        )
    }

    /// The blocks keep the live list's order, and inside each the queue's own: most recently
    /// departed first. Nothing below the seam wants a person, whatever it was last drawn as.
    @Test
    func aQueueBlockKeepsTheQueuesOrderAndWantsNobody() {
        let now = Date()
        let rows = interleaved(codex: 3, claude: 2, now: now)
            + [departure(.claudeCode, "asked", ago: 30, now: now, status: .approvalNeeded)]
        let newestFirst = rows.sorted { $0.departedAt > $1.departedAt }
        let groups = MonitorAggregation.groups(of: newestFirst)

        #expect(newestFirst.first?.session.agent == .claudeCode)
        #expect(groups.map(\.agent) == [.codex, .claudeCode])
        #expect(groups.map(\.rowCount) == [3, 3])
        for group in groups {
            #expect(group.departures == group.departures.sorted { $0.departedAt > $1.departedAt })
            #expect(!group.wantsAttention)
        }
        #expect(groups.flatMap(\.departures).count == rows.count, "every row is under a heading")
    }

    /// Its own switch, default on: turning the live list's off leaves the queue grouped, and
    /// turning the queue's off is the flat queue in departure order, heights and all.
    @Test @MainActor
    func groupingTheQueueIsASwitchOfItsOwn() {
        let now = Date()
        let store = store(interleaved(codex: 6, claude: 2, now: now))

        #expect(store.groupsRecentByProduct)
        #expect(store.recentGroups.map(\.agent) == [.codex, .claudeCode])
        #expect(store.recentGroupHeaderCount == 2)
        #expect(store.queueLeadsWithABlockHeading)
        #expect(
            store.recentContentHeight
                == PanelMetrics.retiredRowHeight * 8 + PanelMetrics.groupHeadingsHeight(count: 2)
        )
        #expect(store.recentViewportHeight == PanelMetrics.groupedRecentViewportCap)
        #expect(store.recentSectionHeight == PanelMetrics.recentSeamHeight + PanelMetrics.groupedRecentViewportCap)

        store.groupsSessionsByProduct = false
        #expect(store.recentGroups.map(\.agent) == [.codex, .claudeCode], "the live switch is not this one")
        store.groupsSessionsByProduct = true

        let grouped = store.expandedContentHeight
        store.groupsRecentByProduct = false
        #expect(store.recentGroups.isEmpty)
        #expect(store.recentGroupHeaderCount == 0)
        #expect(!store.queueLeadsWithABlockHeading)
        #expect(store.recentContentHeight == PanelMetrics.retiredRowHeight * 8)
        #expect(store.recentViewportHeight == PanelMetrics.recentViewportCap)
        #expect(grouped - store.expandedContentHeight == PanelMetrics.productTrailHeight * 2)
        #expect(store.recentDepartures.first?.session.agent == .claudeCode, "one descent across products")

        // Folded, nothing is drawn below the seam, so neither form moves the panel.
        store.isRecentExpanded = false
        let flatFolded = store.expandedContentHeight
        store.groupsRecentByProduct = true
        #expect(!store.queueLeadsWithABlockHeading)
        #expect(store.expandedContentHeight == flatFolded)
    }

    /// Remembered like every other Display switch.
    @Test @MainActor
    func theQueuesSwitchIsRemembered() throws {
        // A fresh suite per run: the suite is shared by both test host processes.
        let name = "RecentGroupingTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let first = MonitorStore(services: [], preferences: defaults)
        #expect(first.groupsRecentByProduct)
        first.groupsRecentByProduct = false

        let second = MonitorStore(services: [], preferences: defaults)
        #expect(!second.groupsRecentByProduct)
        #expect(second.groupsSessionsByProduct, "the live list's switch is a different key")
    }

    /// Drawn: the open grouped queue leads with Codex's chip under the seam, which gives up its
    /// rule to it; its rows carry no chip; Claude Code waits on the foot line. Off, the seam's
    /// rule and every row's chip come back.
    @Test @MainActor
    func theOpenQueueDrawsItsHeadingsAndItsRowsGiveUpTheirChips() throws {
        let now = Date()
        let store = store(interleaved(codex: 6, claude: 2, now: now))
        let width = PanelMetrics.sessionViewportWidth(panelWidth: store.currentPanelSize.width)
        let seam = PanelMetrics.recentSeamHeight
        let line = PanelMetrics.productTrailHeight

        func render() throws -> (NSBitmapImageRep, CGFloat, CGFloat, CGFloat) {
            let height = store.recentSectionHeight
            let file = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("recent-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: file) }
            // The anatomy renderer gives SwiftUI a run-loop turn, so the lazy rows are laid out.
            try AnatomyFigureRenderer.png(
                RecentSessionSection()
                    .environmentObject(store)
                    .background(Color.black),
                size: CGSize(width: width, height: height),
                to: file
            )
            let rep = try #require(NSBitmapImageRep(data: try Data(contentsOf: file)))
            return (rep, CGFloat(rep.pixelsWide) / width, CGFloat(rep.pixelsHigh) / height, height)
        }

        func brightest(
            _ rep: NSBitmapImageRep, _ across: CGFloat, _ down: CGFloat,
            x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>
        ) -> CGFloat {
            var found: CGFloat = 0
            for px in stride(from: x.lowerBound, through: x.upperBound, by: 0.5) {
                for py in stride(from: y.lowerBound, through: y.upperBound, by: 0.5) {
                    let value = rep
                        .colorAt(x: Int(px * across), y: Int(py * down))?
                        .usingColorSpace(.deviceRGB)?
                        .brightnessComponent ?? 0
                    found = max(found, value)
                }
            }
            return found
        }

        // A chip's ground, one point inside its top edge and left of its name: dark but not black.
        // A row with no chip has nothing there — its text starts lower.
        let chipX = PanelMetrics.sessionRowPadding + 1.5 ... PanelMetrics.sessionRowPadding + 4
        let chipTopInset = (PanelMetrics.retiredRowHeight - PanelMetrics.productBadgeHeight) / 2 + 1.5
        func rowChipGround(_ rep: NSBitmapImageRep, _ across: CGFloat, _ down: CGFloat, rowTop: CGFloat) -> CGFloat {
            brightest(rep, across, down, x: chipX, y: rowTop + chipTopInset ... rowTop + chipTopInset + 1)
        }
        let seamRule: ClosedRange<CGFloat> = 200 ... 300

        let (grouped, across, down, height) = try render()
        #expect(height == seam + PanelMetrics.groupedRecentViewportCap)
        let top = brightest(grouped, across, down, x: 13 ... 60, y: seam + 1.5 ... seam + line - 1.5)
        #expect(top > 0.8, "no chip under the seam — brightest \(top)")
        let foot = brightest(grouped, across, down, x: 13 ... 60, y: height - line + 1.5 ... height - 1.5)
        #expect(foot > 0.25, "no badge on the foot line — brightest \(foot)")
        let groupedRow = rowChipGround(grouped, across, down, rowTop: seam + line)
        #expect(groupedRow < 0.03, "a grouped row drew a chip — \(groupedRow)")
        let groupedRule = brightest(grouped, across, down, x: seamRule, y: seam / 2 - 0.5 ... seam / 2 + 0.5)
        #expect(groupedRule < 0.05, "the seam drew its rule over the heading's — \(groupedRule)")

        store.groupsRecentByProduct = false
        let (flat, flatAcross, flatDown, _) = try render()
        let flatRow = rowChipGround(flat, flatAcross, flatDown, rowTop: seam)
        #expect(flatRow > 0.05, "a flat row drew no chip — \(flatRow)")
        let flatRule = brightest(flat, flatAcross, flatDown, x: seamRule, y: seam / 2 - 0.5 ... seam / 2 + 0.5)
        #expect(flatRule > 0.1, "the flat queue's seam lost its rule — \(flatRule)")
    }
}
