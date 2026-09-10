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
                    + PanelMetrics.groupHeadingsHeight(count: 2)
        )
        #expect(abs(host.fittingSize.height - store.sessionViewportHeight) < 0.01)

        #expect(store.sessionGroupHeaderCount == 2)
    }

    /// The heading is the `32` the arithmetic above spends on it, it draws the
    /// chip that makes it one, and **all of its slack is above that chip**.
    ///
    /// Read off the bitmap rather than off the metric, because the metric is
    /// the thing under test: `productGroupHeaderHeight` is `recentSeamHeight`
    /// by definition and would agree with itself however the bar were drawn.
    /// What cannot agree with itself is where the ink lands — and where it
    /// lands is the whole of the decision. Centred, the chip stood `8` under
    /// the band's hairline and `20.5` from the caption it heads, which is a
    /// heading nearer to what precedes it than to what it heads; taking the
    /// slack above inverts that to `16` and `12.5`, the second of which is the
    /// row's own padding and nothing added. So the top third of the bar has to
    /// be empty and the bottom `16` has to carry the chip, and this checks
    /// both rather than only that something was drawn.
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
        func brightest(from top: CGFloat, to bottom: CGFloat) -> CGFloat {
            var found: CGFloat = 0
            // The chip stands on the panel's own `12` and is as wide as the
            // product's name, so this box is inside it wherever that ends.
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
        // Empty above -- the chip has not crept up into the band's own margin.
        #expect(
            brightest(from: 1, to: slack - 1) < 0.2,
            "the heading's slack is not all above its chip"
        )
        // And lit below, where the chip is.
        let lit = brightest(from: slack + 3, to: PanelMetrics.productGroupHeaderHeight - 3)
        #expect(lit > 0.8, "the heading drew no chip — brightest value was \(lit)")
    }

    /// The separator between the chip and the count is **the seam's own dot,
    /// on the rule's own line, in the middle of the gap the glyph held**.
    ///
    /// Three claims and one drawing, and none of the three is checkable from
    /// the metrics: `productBadgeCountSpacing` is `(gap − dot) / 2` by
    /// construction and would agree with itself however the bar were drawn.
    /// What can be wrong is the ink and the size — this bar is the Recent seam
    /// with a chip standing where the label stands, so the mark it draws
    /// between a chip and a count is the mark the seam draws between a word
    /// and a count, at `captionSeparatorDotSize` in the caption's own ink —
    /// and the placement, which is what "add the dot back without moving the
    /// count" means.
    ///
    /// ~~It was the hairline's own value, on the reading that a separator is
    /// chrome rather than a reading.~~ Superseded 2026-09-09: that made one
    /// bar draw two idioms, and the seam's is the one both keep.
    ///
    /// Read off the bar's own centre row, which is where the rule is: the runs
    /// of ink across it are the chip, the separator, the count and the rule, so
    /// the second one is the mark and the fourth is the rule it stands on.
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

        // The bar centres its contents, so the rule's line is the chip's
        // middle -- and the chip stands on the bar's bottom edge.
        let line = PanelMetrics.productGroupHeaderHeight
            - PanelMetrics.productBadgeHeight / 2
        struct Run { var from: CGFloat; var to: CGFloat; var peak: CGFloat }
        var runs: [Run] = []
        // A tenth of a point, so a `3` pt disc is measured rather than
        // rounded, and the run either side of it is found where it ends.
        for step in 0...Int(width * 10) {
            let x = CGFloat(step) / 10
            let colour = rep
                .colorAt(x: Int(x * across), y: Int(line * down))?
                .usingColorSpace(.deviceRGB)
            // Above the panel's black and below the chip's own ground, which
            // is what makes the chip one run rather than its glyphs several.
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

        // The mark is the caption's ink, not the rule's -- the thing that
        // changed on 2026-09-09. Read against the ink's own value rather than
        // against the count's drawn peak: one row through an `11` pt glyph
        // crosses whatever antialiasing that row happens to carry, so the
        // numeral samples well under the `#7C7C80` it is set in and would make
        // this a weak test of a strong claim.
        let caption = try #require(
            NotchPalette.labelDrawingColor.usingColorSpace(.deviceRGB)
        )
        #expect(
            abs(dot.peak - caption.brightnessComponent) < 0.05,
            "the separator is \(dot.peak), the caption \(caption.brightnessComponent)"
        )
        // And plainly standing on the hairline rather than being one.
        #expect(
            dot.peak > rule.peak * 2,
            "the separator is \(dot.peak) against the rule's \(rule.peak)"
        )

        // Its own width, and the middle of the gap: the space it leaves on the
        // chip's side is the space it leaves on the count's.
        #expect(abs((dot.to - dot.from) - PanelMetrics.captionSeparatorDotSize) < 0.6)
        let before = dot.from - chip.to
        let after = count.from - dot.to
        // Half a point of slack, and it is the chip's edge rather than the
        // arithmetic: a `5` pt corner drawn into a scan this fine reports its
        // own antialiasing as ink, which puts `chip.to` a fraction past where
        // the layout ends it.
        #expect(abs(before - PanelMetrics.productBadgeCountSpacing) < 0.7)
        // The count's glyph carries its own left bearing, so `after` is the
        // spacing plus that: `before` lands on `productBadgeCountSpacing`
        // almost exactly and `after` runs about two points past it. Chasing
        // the bearing itself is declined: it differs per digit, and a
        // separator that moved when a block gained a session would be worse
        // than one half a point off centre.
        #expect(after >= before)
        #expect(after - before < 2.5)
    }

    /// The seam's separator is **the row's dot, standing on the rule's own
    /// line** — the two claims `expanded-panel-v2.md` §2.2 makes about it.
    ///
    /// Neither is checkable from the metrics: ``PanelMetrics``
    /// `seamSeparatorSpacing` is `(gap − dot) / 2` by construction and would
    /// agree with itself whatever the bar drew. What can be wrong is where the
    /// mark lands — a `·` *set* in the caption sits on its own x-height, which
    /// is a point below the line the bar centres its contents on, so the seam's
    /// own hairline ran past the dot rather than through it — and how big it
    /// is, since the caption's glyph is two thirds of the row's.
    ///
    /// Read out of the drawing in two windows: the gap the separator stands in,
    /// found from the label's own measured width, and a stretch of the bar far
    /// enough along to hold nothing but the rule.
    @Test @MainActor
    func theSeamsSeparatorIsTheRowsDotOnTheRulesOwnLine() throws {
        let store = MonitorStore(preferences: nil)
        store.isExpanded = true
        store.isRecentExpanded = true
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

        // The seam sizes itself off the store's own panel, so the figure has
        // to be that wide: drawn narrower, the bar overflows, centres what
        // will not fit and takes its label off the left edge.
        let width = PanelMetrics.sessionViewportWidth(
            panelWidth: store.currentPanelSize.width
        )
        let height = PanelMetrics.recentSectionHeight(
            retiredRowCount: 1,
            isRecentExpanded: true
        )
        // Drawn through the anatomy figures' own renderer, which hosts the
        // view in a window and gives SwiftUI a turn of the loop first. A bare
        // `cacheDisplay` catches this bar mid-layout -- its label measures
        // zero and the whole line lands where nothing is -- for the reason a
        // `ScrollView`'s content comes out empty there.
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

        /// The ink in a slice of the seam: how far down its middle is, how
        /// tall it stands and how bright it gets, in points off the bar's top.
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

        // The gap the separator stands in: from the label's own right edge to
        // where the count begins, both measured off the face the seam sets
        // them in, and shy of each by half a point so a bearing cannot reach
        // in. The dot is `2` pt in the middle of `9.3`, so a fraction of drift
        // between what SwiftUI lays out and what `textWidth` measures cannot
        // move this window off it.
        let word = PanelMetrics.sessionRowPadding
            + PanelMetrics.textWidth("Recent", font: PanelMetrics.captionFont)
        let gap = PanelMetrics.textWidth(" · ", font: PanelMetrics.captionFont)
        let dot = ink(from: word + 0.5, to: word + gap - 0.5)
        // And the rule, well past the count and well short of the chevron.
        let rule = ink(from: 200, to: 300)

        // One line, to the pixel this is drawn at: the bar centres both, so
        // the hairline runs through the dot rather than past it.
        #expect(
            abs(dot.middle - rule.middle) < 1 / down,
            "the dot's middle is \(dot.middle) against the rule's \(rule.middle)"
        )
        #expect(abs(rule.middle - PanelMetrics.recentSeamHeight / 2) < 1 / down)

        // The row's dot rather than the caption's: `2` pt of ink, where a `·`
        // set at `11` pt Light draws `1.13`.
        #expect(
            abs(dot.height - PanelMetrics.captionSeparatorDotSize) < 0.6,
            "the separator drew \(dot.height) pt"
        )
        // Still a reading, unlike the block heading's -- that mark is chrome at
        // the rule's own value, and this one belongs to the label it separates.
        let caption = try #require(
            NotchPalette.labelDrawingColor.usingColorSpace(.deviceRGB)
        )
        // Well clear of the hairline it stands on, and no brighter than the
        // ink it belongs to -- read as a ratio rather than as a value, because
        // a figure's own colour space reaches this back through a file.
        #expect(dot.peak > rule.peak * 2)
        #expect(dot.peak < caption.brightnessComponent * 1.25)
    }

    /// A washed row's ground **stands off the chip above it**.
    ///
    /// `expanded-panel-v2.md` §4.2 gives a block's heading all of its slack
    /// above the chip and none below, on the reading that the row beneath
    /// brings its own top padding. It does — until the row is under the
    /// pointer, when its ground fills the whole `72` and meets the bottom edge
    /// of the chip's own ground, and two filled shapes sharing an edge read as
    /// one shape with a notch cut out of it.
    ///
    /// Read down one column that crosses both: the chip's ground ends, the
    /// panel's black stands for ``PanelMetrics/sessionRowGroundInset``, and the
    /// wash begins. Without the inset the two runs are one run and the gap is
    /// zero, which is the drawing this pins against.
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
        // A bare hosting view, as the heading's own figure is drawn: nothing
        // here is sized by text, so there is no reason to spin a window and a
        // run loop for it -- and a window that exists while the answering
        // suite is synthesising clicks at its own offscreen views takes hits
        // that were meant for theirs.
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
                // The state a pointer would put it in, which a figure cannot
                // hold a pointer over -- and the state an open row is in
                // permanently.
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

        // A column well inside the chip and well past the `12` pt corner the
        // row's ground is drawn with, so both grounds are crossed squarely.
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
        // The chip is the whole of the leading bar, and the wash is what
        // follows it.
        #expect(abs(chip.to - PanelMetrics.leadingProductGroupHeaderHeight) < 1)
        #expect(ground.to > PanelMetrics.leadingProductGroupHeaderHeight + 40)

        let gap = ground.from - chip.to
        #expect(
            abs(gap - PanelMetrics.sessionRowGroundInset) < 0.6,
            "the wash stands \(gap) pt off the chip"
        )
    }

    /// **One product is drawn as one block, not as a list of its own**
    /// (2026-09-09).
    ///
    /// The list used to be grouped only while more than one product was
    /// connected: a machine running one product drew a flat list whose rows
    /// named themselves, and connecting a second rebuilt the whole structure —
    /// the heading arrived, the row's chip left, the panel gave up its own top
    /// rule and the viewport grew. One product is the general form with one
    /// block in it now, and none of that happens at the moment a second
    /// product connects.
    ///
    /// **Read off the drawing rather than off the store**, because the store
    /// can group a list the view never heads: the heading's chip and a row's
    /// caption are told apart by ink, the chip's text being
    /// ``NotchPalette/themeInk``'s lit value and the Project the caption grey.
    /// So the top band is scanned for the chip and the row's own caption line
    /// for the absence of one, on a list hosted at the height the panel would
    /// give it.
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
        // One connected product, one block, and a heading leading the list --
        // which is also what takes the panel's own top rule away.
        #expect(store.sessionGroups.map(\.agent) == [.codex])
        #expect(store.sessionGroupHeaderCount == 1)
        #expect(store.listLeadsWithABlockHeading)

        let width = PanelMetrics.sessionViewportWidth(
            panelWidth: store.currentPanelSize.width
        )
        let height = store.sessionViewportHeight
        // The list is the leading heading and the row, and nothing else: the
        // viewport it asks for is exactly those two, which is the first thing
        // the drawing has to agree with.
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

        /// The brightest ink in a box, taken across the width a chip stands
        /// in. A box rather than a line: a `10` pt glyph crossed by one row of
        /// pixels samples whatever antialiasing that row happens to carry.
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

        // The leading heading is the chip alone, its slack taken off.
        let heading = peak(from: 1.5, to: PanelMetrics.leadingProductGroupHeaderHeight - 1.5)
        #expect(heading > 0.8, "the list drew no heading — brightest value was \(heading)")

        // And the row under it draws the Project alone. The band is the row's
        // own arithmetic, offset by the heading: three lines fill the row's
        // `72` and the caption stands on its top padding, where a two-line row
        // would centre its block and put the caption `10` lower.
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

    /// **The About panel draws inside the height the window was sized to, and
    /// spends it where the composition says.**
    ///
    /// ``PanelMetrics/aboutPanelHeight`` is a sum of layout metrics and would
    /// agree with itself however the body were laid out — the panel could be
    /// the right height with its lockup pressed against the rule and its
    /// control cropped by the bottom edge, and nothing in the arithmetic would
    /// notice. So this lays the body out and reads the ink: nothing in the top
    /// margin but the rule that closes the band, nothing in the bottom margin
    /// at all, and the lockup where the composition puts it.
    @Test @MainActor
    func theAboutPanelSpendsItsHeightWhereItSaysItDoes() throws {
        let width = PanelMetrics.expandedBaselineWidth
        let height = PanelMetrics.aboutPanelHeight
        let host = NSHostingView(rootView: AboutPanelContent().frame(width: width))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()

        // The term the composition cannot check on itself: one caption line at
        // the height ``PanelMetrics/aboutTextLineHeight`` says it is. Composed
        // from `NSLayoutManager`'s `13` rather than the `14` SwiftUI draws,
        // the body came out two points taller than the window and the control
        // sat two points inside its own bottom margin — which the frame below
        // hides, because a fixed frame reports its own height whatever it is
        // given to hold.
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
        // Every row of the body, across its whole width: this panel is a
        // centred column, so there is no band of it a narrow probe could sit
        // beside and call empty.
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

        // The band's closing rule, and then nothing until the lockup.
        #expect(brightest(from: 0, to: 1) > 0.05, "the band's rule is not drawn")
        #expect(
            brightest(from: 2, to: PanelMetrics.aboutTopMargin - 1) < 0.05,
            "something is standing in the About panel's top margin"
        )
        // The lockup, whose ink is the brand's lit end.
        let lockupTop = PanelMetrics.aboutTopMargin
        #expect(
            brightest(from: lockupTop + 8, to: lockupTop + PanelMetrics.aboutLockupHeight - 8) > 0.8,
            "the lockup is not where the composition puts it"
        )
        // And the bottom margin, which the control has to stop above.
        #expect(
            brightest(from: height - PanelMetrics.aboutBottomMargin + 1, to: height - 1) < 0.05,
            "the About panel's content runs into its bottom margin"
        )
    }
}
