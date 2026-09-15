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

    /// The grouped list draws at the height the panel was sized to, with the headings the store
    /// counted: window and list compose heights separately, so hosting the real list catches a
    /// heading counted in one and not the other.
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

        #expect(
            store.sessionViewportHeight
                == PanelMetrics.sessionRowHeight * 3
                    + PanelMetrics.groupHeadingsHeight(count: 2)
        )
        #expect(abs(host.fittingSize.height - store.sessionViewportHeight) < 0.01)

        #expect(store.sessionGroupHeaderCount == 2)
    }

    /// The heading is its chip plus slack, with all slack above the chip. Read off the bitmap,
    /// since `productGroupHeaderHeight` agrees with itself by definition. No run loop needed: the
    /// bar is not in a `ScrollView`.
    @Test @MainActor
    func theBlockHeadingIsItsChipAndItsSlackAboveIt() throws {
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
        // The rep is in backing pixels, not points.
        let across = CGFloat(rep.pixelsWide) / host.bounds.width
        let down = CGFloat(rep.pixelsHigh) / host.bounds.height
        func brightest(from top: CGFloat, to bottom: CGFloat) -> CGFloat {
            var found: CGFloat = 0
            // The chip starts at the panel's `12` and spans the product name, so this box is inside it.
            for x in stride(from: 14.0, to: 70.0, by: 1) {
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

        let slack = PanelMetrics.productGroupHeaderHeight - PanelMetrics.productBadgeHeight
        #expect(slack > PanelMetrics.sessionRowLineSpacing)
        #expect(
            brightest(from: 1, to: slack - 1) < 0.2,
            "the heading's slack is not all above its chip"
        )
        let lit = brightest(from: slack + 3, to: PanelMetrics.productGroupHeaderHeight - 3)
        #expect(lit > 0.8, "the heading drew no chip — brightest value was \(lit)")
    }

    /// The heading's separator is the seam's dot (`captionSeparatorDotSize`, caption ink), on the
    /// rule's line, centred in the gap. Read off the bar's centre row, whose ink runs are the
    /// chip, the dot, the count and the rule.
    @Test @MainActor
    func theHeadingsSeparatorIsTheSeamsDotInTheMiddleOfItsGap() throws {
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
        host.frame = NSRect(
            x: 0, y: 0, width: width, height: PanelMetrics.productGroupHeaderHeight
        )
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()

        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let across = CGFloat(rep.pixelsWide) / host.bounds.width
        let down = CGFloat(rep.pixelsHigh) / host.bounds.height

        // The bar centres its contents, so the rule's line is the chip's middle.
        let line = PanelMetrics.productGroupHeaderHeight
            - PanelMetrics.productBadgeHeight / 2
        struct Run { var from: CGFloat; var to: CGFloat; var peak: CGFloat }
        var runs: [Run] = []
        // Tenth-point steps, so a `3` pt disc is measured rather than rounded.
        for step in 0...Int(width * 10) {
            let x = CGFloat(step) / 10
            let colour = rep
                .colorAt(x: Int(x * across), y: Int(line * down))?
                .usingColorSpace(.deviceRGB)
            // Above the panel's black, below the chip's ground: the chip reads as one run.
            let value = colour?.brightnessComponent ?? 0
            if value > 0.06 {
                if var last = runs.last, x - last.to < 0.2 {
                    last.to = x
                    last.peak = max(last.peak, value)
                    runs[runs.count - 1] = last
                } else {
                    runs.append(Run(from: x, to: x, peak: value))
                }
            }
        }

        #expect(runs.count == 4, "expected chip, separator, count and rule")
        let chip = try #require(runs.first)
        let dot = try #require(runs.count > 1 ? runs[1] : nil)
        let count = try #require(runs.count > 2 ? runs[2] : nil)
        let rule = try #require(runs.last)

        // Against the caption ink's value, not the count's drawn peak: one row through an `11` pt
        // glyph samples well under the `#7C7C80` it is set in.
        let caption = try #require(
            NotchPalette.labelDrawingColor.usingColorSpace(.deviceRGB)
        )
        #expect(
            abs(dot.peak - caption.brightnessComponent) < 0.05,
            "the separator is \(dot.peak), the caption \(caption.brightnessComponent)"
        )
        #expect(
            dot.peak > rule.peak * 2,
            "the separator is \(dot.peak) against the rule's \(rule.peak)"
        )

        #expect(abs((dot.to - dot.from) - PanelMetrics.captionSeparatorDotSize) < 0.6)
        let before = dot.from - chip.to
        let after = count.from - dot.to
        // Slack for the chip's `5` pt corner, whose antialiasing reads as ink past `chip.to`.
        #expect(abs(before - PanelMetrics.productBadgeCountSpacing) < 0.7)
        // The count's left bearing puts `after` about 2 pt past `before`; not chased, as it differs
        // per digit.
        #expect(after >= before)
        #expect(after - before < 2.5)
    }

    /// The seam's separator is the row's dot on the rule's own line (`expanded-panel-v2.md` §2.2).
    /// A `·` set in the caption sits a point below that line and is two thirds the row's size.
    @Test @MainActor
    func theSeamsSeparatorIsTheRowsDotOnTheRulesOwnLine() throws {
        let store = MonitorStore(preferences: nil)
        store.isExpanded = true
        store.isRecentExpanded = true
        // The flat queue: grouped, the open seam gives its rule up to the first heading (§4.7), and
        // this measures the dot against that rule.
        store.groupsRecentByProduct = false
        store.stageSpecimenQueue([
            RecentDeparture(
                session: MonitoredSession(
                    agent: .codex,
                    threadID: "a", turnID: "u", projectName: "p", title: "t",
                    preview: nil, status: .completed, startedAt: nil
                ),
                departedAt: Date(),
                reason: .read
            )
        ])

        // At the store's panel width: narrower, the bar overflows and takes its label off the left.
        let width = PanelMetrics.sessionViewportWidth(
            panelWidth: store.currentPanelSize.width
        )
        let height = PanelMetrics.recentSectionHeight(
            retiredRowCount: 1,
            isRecentExpanded: true
        )
        // The anatomy renderer gives SwiftUI a run-loop turn; a bare `cacheDisplay` catches the bar
        // mid-layout, its label measuring zero.
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("seam-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        try AnatomyFigureRenderer.png(
            RecentSessionSection()
                .environmentObject(store)
                .background(Color.black),
            size: CGSize(width: width, height: height),
            to: file
        )
        let rep = try #require(NSBitmapImageRep(data: try Data(contentsOf: file)))
        let across = CGFloat(rep.pixelsWide) / width
        let down = CGFloat(rep.pixelsHigh) / height

        func ink(from: CGFloat, to: CGFloat) -> (middle: CGFloat, height: CGFloat, peak: CGFloat) {
            var weight: CGFloat = 0
            var moment: CGFloat = 0
            var top = CGFloat.greatestFiniteMagnitude
            var bottom = -CGFloat.greatestFiniteMagnitude
            var peak: CGFloat = 0
            for row in 0..<Int(PanelMetrics.recentSeamHeight * down) {
                let y = (CGFloat(row) + 0.5) / down
                for step in 0...Int((to - from) * across) {
                    let x = from + CGFloat(step) / across
                    let value = rep
                        .colorAt(x: Int(x * across), y: row)?
                        .usingColorSpace(.deviceRGB)?
                        .brightnessComponent ?? 0
                    guard value > 0.06 else { continue }
                    weight += value
                    moment += value * y
                    top = min(top, y)
                    bottom = max(bottom, y)
                    peak = max(peak, value)
                }
            }
            return (moment / weight, bottom - top, peak)
        }

        // The gap from the label's right edge to the count, shy of each by 0.5 pt so a bearing
        // cannot reach in.
        let word = PanelMetrics.sessionRowPadding
            + PanelMetrics.textWidth("Recent", font: PanelMetrics.captionFont)
        let gap = PanelMetrics.textWidth(" · ", font: PanelMetrics.captionFont)
        let dot = ink(from: word + 0.5, to: word + gap - 0.5)
        let rule = ink(from: 200, to: 300)

        #expect(
            abs(dot.middle - rule.middle) < 1 / down,
            "the dot's middle is \(dot.middle) against the rule's \(rule.middle)"
        )
        #expect(abs(rule.middle - PanelMetrics.recentSeamHeight / 2) < 1 / down)

        // The row's dot: `2` pt of ink, where a `·` set at `11` pt Light draws `1.13`.
        #expect(
            abs(dot.height - PanelMetrics.captionSeparatorDotSize) < 0.6,
            "the separator drew \(dot.height) pt"
        )
        let caption = try #require(
            NotchPalette.labelDrawingColor.usingColorSpace(.deviceRGB)
        )
        // A ratio rather than a value: the figure's colour space comes back through a file.
        #expect(dot.peak > rule.peak * 2)
        #expect(dot.peak < caption.brightnessComponent * 1.25)
    }

    /// A washed row's ground stands off the chip above it by ``PanelMetrics/sessionRowGroundInset``;
    /// without it the hovered row's `72` ground meets the chip's and reads as one notched shape.
    @Test @MainActor
    func aWashedRowsGroundStandsOffTheChipAboveIt() throws {
        let session = MonitoredSession(
            agent: .codex,
            threadID: "a", turnID: "u", projectName: "notchline", title: "A title",
            preview: nil, status: .running, startedAt: nil
        )
        let store = MonitorStore(preferences: nil)
        store.isExpanded = true

        let width = PanelMetrics.sessionViewportWidth(
            panelWidth: store.currentPanelSize.width
        )
        let height = PanelMetrics.leadingProductGroupHeaderHeight
            + PanelMetrics.sessionRowHeight
        // A bare hosting view, not a window: a window takes the answering suite's synthesised clicks.
        let host = NSHostingView(
            rootView: VStack(spacing: 0) {
                ProductGroupHeader(
                    group: MonitorAggregation.SessionGroup(
                        agent: .codex,
                        sessions: [session],
                        wantsAttention: false
                    ),
                    isLeading: true
                )
                // Hovered: also the state an open row is in permanently.
                SessionRowContent(session: session, isHovered: true)
                    .frame(height: PanelMetrics.sessionRowHeight)
            }
            .environmentObject(store)
            .background(Color.black)
            .frame(width: width, height: height)
        )
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()

        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let across = CGFloat(rep.pixelsWide) / host.bounds.width
        let down = CGFloat(rep.pixelsHigh) / host.bounds.height

        // Inside the chip and past the row ground's `12` pt corner.
        let column = Int(30 * across)
        var runs: [(from: CGFloat, to: CGFloat)] = []
        for row in 0..<rep.pixelsHigh {
            let value = rep
                .colorAt(x: column, y: row)?
                .usingColorSpace(.deviceRGB)?
                .brightnessComponent ?? 0
            let y = CGFloat(row) / down
            guard value > 0.06 else { continue }
            if var last = runs.last, y - last.to < 1 / down + 0.01 {
                last.to = y
                runs[runs.count - 1] = last
            } else {
                runs.append((from: y, to: y))
            }
        }

        #expect(runs.count >= 2, "expected the chip's ground and the row's")
        let chip = try #require(runs.first)
        let ground = try #require(runs.count > 1 ? runs[1] : nil)
        #expect(abs(chip.to - PanelMetrics.leadingProductGroupHeaderHeight) < 1)
        #expect(ground.to > PanelMetrics.leadingProductGroupHeaderHeight + 40)

        let gap = ground.from - chip.to
        #expect(
            abs(gap - PanelMetrics.sessionRowGroundInset) < 0.6,
            "the wash stands \(gap) pt off the chip"
        )
    }

    /// The finished-turn dot stands the same gap off the digits on bar and row
    /// (`compact-view-v2.md` §4.3). The wing's gap includes its `.clear` ``ReadingGround`` padding
    /// and a row's has none, so the two are measured against each other, not a shared metric.
    @Test @MainActor
    func theFinishedDotStandsOffTheDigitsByTheSameGapOnBarAndRow() throws {
        let started = Date(timeIntervalSince1970: 1_000)
        let session = MonitoredSession(
            agent: .codex,
            threadID: "a", turnID: "u", projectName: "p", title: "t",
            preview: nil, status: .completed,
            startedAt: started, finishedAt: started.addingTimeInterval(83)
        )
        let store = MonitorStore(services: [], preferences: nil)
        store.applyForTesting(
            AgentSnapshot(
                agent: .codex, availability: .ready, sessions: [session],
                quota: .unavailable, diagnostic: nil, setupStatus: .active,
                presence: .open
            )
        )
        #expect(store.compactTrailingReading.timerText == "1:23")
        #expect(store.compactTrailingReading.drawsFinishedDot)

        // Both parts are views here, so their laid-out frames are measured without a bitmap.
        let wing = NSHostingView(
            rootView: CompactTrailingSlot().environmentObject(store)
        )
        wing.frame = NSRect(origin: .zero, size: wing.fittingSize)
        wing.layoutSubtreeIfNeeded()
        let wingDot = try #require(firstDescendant(BreathingDotView.self, in: wing))
        let wingDigits = try #require(firstDescendant(ElapsedReadoutView.self, in: wing))
        let wingGap = wingDigits.convert(wingDigits.bounds, to: wing).minX
            - wingDot.convert(wingDot.bounds, to: wing).maxX
        #expect(
            abs(wingGap - PanelMetrics.drawnFinishDotGap) < 0.01,
            "the wing draws its dot \(wingGap) pt off the digits"
        )

        let width = PanelMetrics.sessionViewportWidth(
            panelWidth: store.currentPanelSize.width
        )
        let height = PanelMetrics.sessionRowHeight
        let row = NSHostingView(
            rootView: SessionRowContent(session: session, isHovered: false)
                .environmentObject(store)
                .background(Color.black)
                .frame(width: width, height: height)
        )
        row.frame = NSRect(x: 0, y: 0, width: width, height: height)
        row.appearance = NSAppearance(named: .darkAqua)
        row.layoutSubtreeIfNeeded()

        let rowDigits = try #require(firstDescendant(ElapsedReadoutView.self, in: row))
        let digitsBox = rowDigits.convert(rowDigits.bounds, to: row)

        let rep = try #require(row.bitmapImageRepForCachingDisplay(in: row.bounds))
        row.cacheDisplay(in: row.bounds, to: rep)
        let across = CGFloat(rep.pixelsWide) / row.bounds.width
        // The only ink in front of the digits is the dot.
        var weight: CGFloat = 0
        var moment: CGFloat = 0
        var lit = 0
        for column in 0..<rep.pixelsWide {
            let x = (CGFloat(column) + 0.5) / across
            guard x > digitsBox.minX - 24, x < digitsBox.minX else { continue }
            var peak: CGFloat = 0
            for pixel in 0..<rep.pixelsHigh {
                peak = max(
                    peak,
                    rep.colorAt(x: column, y: pixel)?
                        .usingColorSpace(.deviceRGB)?
                        .brightnessComponent ?? 0
                )
            }
            guard peak > 0.3 else { continue }
            lit += 1
            weight += peak
            moment += peak * x
        }
        #expect(lit > 0, "the row drew no dot in front of its reading")
        // Weighted centre, so a soft edge on one side cannot move it.
        let centre = moment / max(weight, 0.000_1)
        let rowGap = digitsBox.minX - (centre + PanelMetrics.buriedFinishDotSize / 2)
        #expect(
            abs(rowGap - wingGap) < 0.75,
            "the row stands its dot \(rowGap) pt off the digits and the bar \(wingGap)"
        )
    }

    /// One product is drawn as one block with a heading (2026-09-09). Read off the drawing, since
    /// the store can group a list the view never heads: the chip's text is
    /// ``NotchPalette/themeInk``'s lit value, the caption grey.
    @Test @MainActor
    func aOneProductListIsDrawnAsOneBlock() throws {
        let store = MonitorStore(services: [], preferences: nil)
        store.isExpanded = true
        store.applyForTesting(
            AgentSnapshot(
                agent: .codex,
                availability: .ready,
                sessions: [
                    MonitoredSession(
                        agent: .codex,
                        threadID: "a", turnID: "u", projectName: "notchline",
                        title: "A title", preview: "A preview",
                        status: .running, startedAt: nil
                    )
                ],
                quota: .unavailable, diagnostic: nil, setupStatus: .active,
                presence: .open
            )
        )
        // A leading heading also takes the panel's own top rule away.
        #expect(store.sessionGroups.map(\.agent) == [.codex])
        #expect(store.sessionGroupHeaderCount == 1)
        #expect(store.listLeadsWithABlockHeading)

        let width = PanelMetrics.sessionViewportWidth(
            panelWidth: store.currentPanelSize.width
        )
        let height = store.sessionViewportHeight
        #expect(
            height
                == PanelMetrics.leadingProductGroupHeaderHeight
                    + PanelMetrics.sessionRowHeight
        )

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

        /// A box, not a line: one pixel row through a `10` pt glyph samples arbitrary antialiasing.
        func peak(from top: CGFloat, to bottom: CGFloat) -> CGFloat {
            var found: CGFloat = 0
            for x in stride(from: PanelMetrics.sessionRowPadding + 1, to: 60.0, by: 1) {
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

        let heading = peak(from: 1.5, to: PanelMetrics.leadingProductGroupHeaderHeight - 1.5)
        #expect(heading > 0.8, "the list drew no heading — brightest value was \(heading)")

        // Three lines fill the row's `72`, so the caption stands on its top padding; a two-line row
        // would put it `10` lower.
        let captionTop = PanelMetrics.leadingProductGroupHeaderHeight
            + PanelMetrics.sessionRowVerticalPadding
            + 1.5
        let row = peak(from: captionTop, to: captionTop + PanelMetrics.sessionRowCaptionHeight - 3)
        let caption = try #require(
            NotchPalette.labelDrawingColor.usingColorSpace(.deviceRGB)
        )
        #expect(
            row < caption.brightnessComponent * 1.25,
            "the row drew more than its Project — brightest value was \(row)"
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

    /// The About panel draws inside ``PanelMetrics/aboutPanelHeight`` and spends it where the
    /// composition says. The sum cannot see a lockup against the rule or a cropped control.
    @Test @MainActor
    func theAboutPanelSpendsItsHeightWhereItSaysItDoes() throws {
        let width = PanelMetrics.expandedBaselineWidth
        let height = PanelMetrics.aboutPanelHeight
        let host = NSHostingView(rootView: AboutPanelContent().frame(width: width))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()

        // One caption line must measure ``PanelMetrics/aboutTextLineHeight``: SwiftUI draws `14`, not
        // `NSLayoutManager`'s `13`, and the fixed frame below hides the overflow.
        let line = NSHostingView(
            rootView: Text("Version 0.0.0 Alpha (0)")
                .font(Font(PanelMetrics.captionFont))
                .monospacedDigit()
        )
        line.layoutSubtreeIfNeeded()
        #expect(abs(line.fittingSize.height - PanelMetrics.aboutTextLineHeight) < 0.01)

        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let across = CGFloat(rep.pixelsWide) / host.bounds.width
        let down = CGFloat(rep.pixelsHigh) / host.bounds.height
        // Whole width: the panel is a centred column, so no side band is safely empty.
        func brightest(from top: CGFloat, to bottom: CGFloat) -> CGFloat {
            var found: CGFloat = 0
            for y in stride(from: top, to: bottom, by: 1) {
                for x in stride(from: 1.0, to: width - 1, by: 2) {
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

        #expect(brightest(from: 0, to: 1) > 0.05, "the band's rule is not drawn")
        #expect(
            brightest(from: 2, to: PanelMetrics.aboutTopMargin - 1) < 0.05,
            "something is standing in the About panel's top margin"
        )
        let lockupTop = PanelMetrics.aboutTopMargin
        #expect(
            brightest(from: lockupTop + 8, to: lockupTop + PanelMetrics.aboutLockupHeight - 8) > 0.8,
            "the lockup is not where the composition puts it"
        )
        #expect(
            brightest(from: height - PanelMetrics.aboutBottomMargin + 1, to: height - 1) < 0.05,
            "the About panel's content runs into its bottom margin"
        )
    }
}

@MainActor
private func firstDescendant<V: NSView>(_ kind: V.Type, in view: NSView) -> V? {
    if let found = view as? V { return found }
    for child in view.subviews {
        if let found = firstDescendant(kind, in: child) { return found }
    }
    return nil
}
