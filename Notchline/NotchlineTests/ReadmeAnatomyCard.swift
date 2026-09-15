// The README's anatomy figure: the real overlay over fixed snapshots, every part named.
// Every anchor comes from `PanelMetrics` and the store, never a screenshot.
import AppKit
import SwiftUI

@testable import Notchline

// MARK: - Callouts

/// One label and the hairline that ties it to a part.
struct AnatomyCallout: Identifiable {
    enum Side {
        case leading, trailing
        /// Above or below the figure, centred on the target.
        case above, below
    }

    /// Renumbered as the key is assembled, so an optional callout leaves no gap.
    var id: Int
    let text: String
    let side: Side
    /// In the figure's own coordinates.
    let target: CGPoint
    /// From the target for `.leading`/`.trailing`; from the specimen's edge for `.above`/`.below`,
    /// whose targets are inside the drawing.
    var stem: CGFloat = 24
    /// Offset off the target's line (zero is straight): vertical for `.leading`/`.trailing`,
    /// horizontal for `.above`/`.below`.
    var drop: CGFloat = 0
}

enum AnatomyCardStyle {
    static let background = Color.white
    static let label = Color(white: 0.36)
    static let caption = Color(white: 0.10)
    static let captionDetail = Color(white: 0.48)
    static let leader = Color(white: 0.74)

    static let labelFont = Font.system(size: 13, weight: .regular)
    static let captionFont = Font.system(size: 15, weight: .semibold)
    static let captionDetailFont = Font.system(size: 13, weight: .regular)

    static let leaderWidth: CGFloat = 1
    static let standoff: CGFloat = 2
    static let labelGap: CGFloat = 8
    /// Bounded by the trailing column: `274` would reach past the page padding.
    static let labelColumn: CGFloat = 270
    static let stackedLabelColumn: CGFloat = 190
}

/// A specimen at its own size with labelled callouts in the margins.
struct CalloutFigure<Specimen: View>: View {
    let callouts: [AnatomyCallout]
    let specimenSize: CGSize
    let margin: EdgeInsets
    @ViewBuilder let specimen: () -> Specimen

    var body: some View {
        ZStack(alignment: .topLeading) {
            specimen()
                .frame(width: specimenSize.width, height: specimenSize.height)
                .offset(x: margin.leading, y: margin.top)

            ForEach(callouts) { callout in
                leader(for: callout)
                label(for: callout)
            }
        }
        .frame(
            width: margin.leading + specimenSize.width + margin.trailing,
            height: margin.top + specimenSize.height + margin.bottom,
            alignment: .topLeading
        )
    }

    private func point(_ callout: AnatomyCallout) -> CGPoint {
        CGPoint(
            x: margin.leading + callout.target.x,
            y: margin.top + callout.target.y
        )
    }

    private func leader(for callout: AnatomyCallout) -> some View {
        LeaderPath(
            callout: callout,
            target: point(callout),
            top: margin.top,
            bottom: margin.top + specimenSize.height
        )
        .stroke(AnatomyCardStyle.leader, lineWidth: AnatomyCardStyle.leaderWidth)
        .frame(
            width: margin.leading + specimenSize.width + margin.trailing,
            height: margin.top + specimenSize.height + margin.bottom
        )
    }

    @ViewBuilder
    private func label(for callout: AnatomyCallout) -> some View {
        Text(callout.text)
            .font(AnatomyCardStyle.labelFont)
            .foregroundStyle(AnatomyCardStyle.label)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(
                CalloutLabelPlacement(
                    callout: callout,
                    target: point(callout),
                    top: margin.top,
                    bottom: margin.top + specimenSize.height,
                    column: AnatomyCardStyle.labelColumn,
                    gap: AnatomyCardStyle.labelGap
                )
            )
    }
}

private struct CalloutLabelPlacement: ViewModifier {
    let callout: AnatomyCallout
    let target: CGPoint
    let top: CGFloat
    let bottom: CGFloat
    let column: CGFloat
    let gap: CGFloat

    func body(content: Content) -> some View {
        switch callout.side {
        case .leading:
            content
                .multilineTextAlignment(.trailing)
                .frame(width: column, alignment: .trailing)
                .position(
                    x: target.x - callout.stem - gap - column / 2,
                    y: target.y + callout.drop
                )
        case .trailing:
            content
                .multilineTextAlignment(.leading)
                .frame(width: column, alignment: .leading)
                .position(
                    x: target.x + callout.stem + gap + column / 2,
                    y: target.y + callout.drop
                )
        case .above:
            content
                .multilineTextAlignment(.center)
                .frame(width: AnatomyCardStyle.stackedLabelColumn)
                .position(x: target.x + callout.drop, y: top - callout.stem - gap - 9)
        case .below:
            content
                .multilineTextAlignment(.center)
                .frame(width: AnatomyCardStyle.stackedLabelColumn)
                .position(x: target.x + callout.drop, y: bottom + callout.stem + gap + 9)
        }
    }
}

private struct LeaderPath: Shape {
    let callout: AnatomyCallout
    let target: CGPoint
    let top: CGFloat
    let bottom: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch callout.side {
        case .leading:
            let bend = CGPoint(x: target.x - callout.stem, y: target.y)
            path.move(to: CGPoint(x: target.x - AnatomyCardStyle.standoff, y: target.y))
            path.addLine(to: bend)
            if callout.drop != 0 {
                path.addLine(to: CGPoint(x: bend.x, y: target.y + callout.drop))
            }
        case .trailing:
            let bend = CGPoint(x: target.x + callout.stem, y: target.y)
            path.move(to: CGPoint(x: target.x + AnatomyCardStyle.standoff, y: target.y))
            path.addLine(to: bend)
            if callout.drop != 0 {
                path.addLine(to: CGPoint(x: bend.x, y: target.y + callout.drop))
            }
        case .above:
            let head = top - callout.stem
            path.move(to: CGPoint(x: target.x, y: target.y - AnatomyCardStyle.standoff))
            path.addLine(to: CGPoint(x: target.x, y: head))
            if callout.drop != 0 {
                path.addLine(to: CGPoint(x: target.x + callout.drop, y: head))
            }
        case .below:
            let foot = bottom + callout.stem
            path.move(to: CGPoint(x: target.x, y: target.y + AnatomyCardStyle.standoff))
            path.addLine(to: CGPoint(x: target.x, y: foot))
            if callout.drop != 0 {
                path.addLine(to: CGPoint(x: target.x + callout.drop, y: foot))
            }
        }
        return path
    }
}

// MARK: - Where the parts are

/// Anchors asked of ``PanelMetrics`` and the store rather than read off a rendering.
@MainActor
struct AnatomyAnchors {
    let store: MonitorStore

    var shoulder: CGFloat { store.surfaceShoulderRadius }
    var band: CGFloat { store.compactHeight }
    var bodyWidth: CGFloat { store.currentPanelSize.width }
    var windowWidth: CGFloat { bodyWidth + shoulder * 2 }
    var pad: CGFloat { PanelMetrics.expandedHorizontalPadding }
    var matrixSize: CGFloat { PanelMetrics.statusMatrixSize }

    // MARK: The leading group, which both forms draw identically

    var matrixLeft: CGFloat { shoulder + pad }
    var matrixTop: CGFloat { (band - matrixSize) / 2 }
    var matrixBottom: CGFloat { matrixTop + matrixSize }
    var matrixMidY: CGFloat { band / 2 }

    /// Both numerals start at the column's leading edge, so one x serves the stack.
    var countsX: CGFloat {
        matrixLeft
            + matrixSize
            + PanelMetrics.aggregateCountsGap
            + PanelMetrics.countsDigitWidth / 2
    }

    // MARK: The collapsed pill

    /// The name is faded off the slot's trailing edge, so the label targets the name.
    var projectNameX: CGFloat {
        let slot = PanelMetrics.pillMiddleWidth(trailing: store.compactTrailingReading)
        let name = store.compactProjectNames.first ?? ""
        return matrixLeft
            + PanelMetrics.reservedLeadingGroupWidth
            + PanelMetrics.expandedNotchClearance
            + min(
                PanelMetrics.textWidth(name, font: PanelMetrics.projectNameFont),
                slot
            ) / 2
    }

    /// The reading's ground ends one trailing padding in; the dot and its `8`
    /// stand before it.
    private var trailingEdge: CGFloat { windowWidth - shoulder - pad }

    private var readingWidth: CGFloat {
        guard let text = store.compactTimerText else { return 0 }
        return PanelMetrics.drawnCompactReadingWidth(text)
    }

    var timerX: CGFloat { trailingEdge - readingWidth / 2 }

    var buriedDotX: CGFloat {
        trailingEdge
            - readingWidth
            - PanelMetrics.buriedFinishDotSpacing
            - PanelMetrics.buriedFinishDotSize / 2
    }

    var buriedDotTop: CGFloat { matrixMidY - PanelMetrics.buriedFinishDotSize / 2 }

    /// Baseline of a line centred in the band: SwiftUI centres the line box, not the cap. Both
    /// readings are `13` pt Light with the same metrics.
    var readingGlyphBottom: CGFloat {
        let font = PanelMetrics.projectNameFont
        return matrixMidY + (font.ascender + font.descender) / 2
    }

    // MARK: The expanded panel

    /// The gear's own glyph, not the `32` pt button around it: `gearshape` at
    /// `13` pt draws `13.5` wide, centred in the button.
    var gearGlyphRight: CGFloat {
        trailingEdge - (PanelMetrics.settingsButtonSize(compactHeight: band) - 13.5) / 2
    }

    /// The About button is flush before the gear: one and a half boxes in.
    var aboutGlyphMidX: CGFloat {
        trailingEdge - PanelMetrics.settingsButtonSize(compactHeight: band) * 1.5
    }

    /// The rail takes its lane from the trailing edge while the list scrolls.
    var rowTextLeft: CGFloat {
        shoulder + PanelMetrics.sessionRowGutter + PanelMetrics.sessionRowPadding
    }

    var isScrolling: Bool {
        store.sessionListContentHeight > store.sessionViewportHeight
    }

    var rowTextRight: CGFloat {
        shoulder
            + PanelMetrics.sessionRowGutter
            + PanelMetrics.sessionViewportWidth(panelWidth: bodyWidth, isScrolling: isScrolling)
            - PanelMetrics.sessionRowPadding
    }

    /// Only the live rows give the rail its width.
    var seamChevronRight: CGFloat {
        shoulder
            + PanelMetrics.sessionRowGutter
            + PanelMetrics.sessionViewportWidth(panelWidth: bodyWidth)
            - PanelMetrics.sessionRowPadding
    }

    /// The Recent queue has its own rail and three rows do not fill five, so it keeps the lane.
    var retiredAgeRight: CGFloat { seamChevronRight }

    /// The rail stands on the panel's own `12` pt inset and never in it.
    var railLeft: CGFloat { trailingEdge - PanelMetrics.scrollRailWidth }

    /// In drawing order: grouped, headings push rows, so walk the blocks.
    func rowTop(_ index: Int) -> CGFloat {
        let groups = store.sessionGroups
        guard !groups.isEmpty else {
            return band + PanelMetrics.sessionRowHeight * CGFloat(index)
        }
        var drawn = 0
        var y = band
        for (block, group) in groups.enumerated() {
            // The first block's heading is the short one: it replaces the panel's own top rule.
            y += block == 0
                ? PanelMetrics.leadingProductGroupHeaderHeight
                : PanelMetrics.productGroupHeaderHeight
            for _ in group.sessions {
                if drawn == index { return y }
                drawn += 1
                y += PanelMetrics.sessionRowHeight
            }
        }
        return y
    }

    /// The heading directly above the row at `index`, if it starts its block.
    func headingAboveRow(_ index: Int) -> CGFloat? {
        var drawn = 0
        for (block, group) in store.sessionGroups.enumerated() {
            if drawn == index {
                let bar = block == 0
                    ? PanelMetrics.leadingProductGroupHeaderHeight
                    : PanelMetrics.productGroupHeaderHeight
                return rowTop(index) - bar / 2
            }
            drawn += group.sessions.count
        }
        return nil
    }

    /// `55` points of text under the row's own vertical padding.
    private var rowContentTop: CGFloat { PanelMetrics.sessionRowVerticalPadding }

    func rowCaptionY(_ index: Int) -> CGFloat {
        rowTop(index) + rowContentTop + PanelMetrics.sessionRowCaptionHeight / 2
    }

    func rowTitleY(_ index: Int) -> CGFloat {
        rowTop(index)
            + rowContentTop
            + PanelMetrics.sessionRowCaptionHeight
            + PanelMetrics.sessionRowLineSpacing
            + PanelMetrics.sessionRowTitleHeight / 2
    }

    func rowPreviewY(_ index: Int) -> CGFloat {
        rowTop(index)
            + rowContentTop
            + PanelMetrics.sessionRowCaptionHeight
            + PanelMetrics.sessionRowLineSpacing
            + PanelMetrics.sessionRowTitleHeight
            + PanelMetrics.sessionRowLineSpacing
            + PanelMetrics.sessionRowPreviewHeight / 2
    }

    var seamTop: CGFloat { band + store.sessionViewportHeight }
    var seamY: CGFloat { seamTop + PanelMetrics.recentSeamHeight / 2 }

    /// In drawing order: grouped, headings push retired rows as they push live ones.
    func retiredRowY(_ index: Int) -> CGFloat {
        var y = seamTop + PanelMetrics.recentSeamHeight
        let groups = store.recentGroups
        guard !groups.isEmpty else {
            return y + PanelMetrics.retiredRowHeight * (CGFloat(index) + 0.5)
        }
        var drawn = 0
        for (block, group) in groups.enumerated() {
            y += block == 0
                ? PanelMetrics.leadingProductGroupHeaderHeight
                : PanelMetrics.productGroupHeaderHeight
            for _ in group.departures {
                if drawn == index { return y + PanelMetrics.retiredRowHeight / 2 }
                drawn += 1
                y += PanelMetrics.retiredRowHeight
            }
        }
        return y
    }

    var footerTop: CGFloat {
        seamTop
            + PanelMetrics.recentSeamHeight
            + store.recentViewportHeight
    }

    var spendY: CGFloat { footerTop + PanelMetrics.recentSeamHeight / 2 }

    private var tableTop: CGFloat {
        footerTop + PanelMetrics.recentSeamHeight + PanelMetrics.footerRuleSpacing
    }

    var productLineY: CGFloat { tableTop + PanelMetrics.footerCaptionHeight / 2 }

    var windowLineY: CGFloat {
        tableTop
            + PanelMetrics.footerCaptionHeight
            + PanelMetrics.footerCaptionSpacing
            + PanelMetrics.footerCaptionHeight / 2
    }

    var windowLineLeft: CGFloat { shoulder + pad + PanelMetrics.footerWindowIndent }
}

// MARK: - The card

@MainActor
struct ReadmeAnatomyCard: View {
    let compact: MonitorStore
    let expanded: MonitorStore

    /// The `238 × 32` pill is drawn at the panel's width so both specimens share their edges.
    private var compactScale: CGFloat {
        expandedAnchors.windowWidth / compactAnchors.windowWidth
    }

    static let padding: CGFloat = 56

    /// Set by the answering figure: two request plates side by side need `1364`.
    static let pageWidth: CGFloat = 1364

    static func margins(specimenWidth: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        let slack = max(0, pageWidth - padding * 2 - specimenWidth)
        // `47 : 53`, measured: with every label on one line, the trailing column's longest is longer.
        return (leading: slack * 0.47, trailing: slack * 0.53)
    }

    /// From the wider specimen, so both figures share one left edge.
    private var margins: (leading: CGFloat, trailing: CGFloat) {
        Self.margins(specimenWidth: max(compactSize.width, expandedSize.width))
    }
    static let stackMargin: CGFloat = 46
    /// `The project being worked on` and `Subagents running` are `94` pt apart on the pill but
    /// `175` and `118` wide.
    static let stackedRowStep: CGFloat = 26
    static let captionGap: CGFloat = 24
    static let sectionGap: CGFloat = 52

    private var compactAnchors: AnatomyAnchors { AnatomyAnchors(store: compact) }
    private var expandedAnchors: AnatomyAnchors { AnatomyAnchors(store: expanded) }

    private var compactSize: CGSize {
        CGSize(
            width: compactAnchors.windowWidth * compactScale,
            height: compactAnchors.band * compactScale
        )
    }

    private var expandedSize: CGSize {
        CGSize(
            width: expandedAnchors.windowWidth,
            height: expanded.currentPanelSize.height
        )
    }

    static func width(compact: MonitorStore, expanded: MonitorStore) -> CGFloat {
        pageWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.sectionGap) {
            figure(
                caption: "Compact view",
                detail: "At rest on the notch or the menu bar.",
                size: compactSize,
                callouts: compactCallouts,
                margin: EdgeInsets(
                    top: Self.stackMargin,
                    leading: margins.leading,
                    bottom: Self.stackMargin + Self.stackedRowStep,
                    trailing: margins.trailing
                )
            ) {
                NotchOverlayView()
                    .environmentObject(compact)
                    .frame(
                        width: compactAnchors.windowWidth,
                        height: compactAnchors.band
                    )
                    .scaleEffect(compactScale, anchor: .topLeading)
                    .frame(
                        width: compactSize.width,
                        height: compactSize.height,
                        alignment: .topLeading
                    )
                    .allowsHitTesting(false)
            }

            figure(
                caption: "Expanded view",
                detail: "On hover: the live list, the recent queue and usage.",
                size: expandedSize,
                callouts: expandedCallouts,
                margin: EdgeInsets(
                    top: Self.stackMargin,
                    leading: margins.leading,
                    bottom: 0,
                    trailing: margins.trailing
                )
            ) {
                NotchOverlayView()
                    .environmentObject(expanded)
                    .frame(width: expandedSize.width, height: expandedSize.height)
                    .allowsHitTesting(false)
            }
        }
        .padding(Self.padding)
        .frame(width: Self.width(compact: compact, expanded: expanded), alignment: .center)
        .background(AnatomyCardStyle.background)
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private func figure<Specimen: View>(
        caption: String,
        detail: String,
        size: CGSize,
        callouts: [AnatomyCallout],
        margin: EdgeInsets,
        @ViewBuilder specimen: @escaping () -> Specimen
    ) -> some View {
        VStack(alignment: .leading, spacing: Self.captionGap) {
            VStack(alignment: .leading, spacing: 3) {
                Text(caption)
                    .font(AnatomyCardStyle.captionFont)
                    .foregroundStyle(AnatomyCardStyle.caption)
                Text(detail)
                    .font(AnatomyCardStyle.captionDetailFont)
                    .foregroundStyle(AnatomyCardStyle.captionDetail)
            }

            CalloutFigure(
                callouts: callouts,
                specimenSize: size,
                margin: margin,
                specimen: specimen
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: The pill's parts

    /// Internal for `theReadmeCalloutsStandApartInTheirColumns`.
    var compactCallouts: [AnatomyCallout] {
        let a = compactAnchors
        let s = compactScale
        return [
            AnatomyCallout(
                id: 1,
                text: "Status of everything at once",
                side: .leading,
                target: CGPoint(x: a.matrixLeft * s, y: a.matrixMidY * s),
                stem: 30
            ),
            AnatomyCallout(
                id: 2,
                text: "Sessions on the list",
                side: .above,
                target: CGPoint(x: a.countsX * s, y: a.matrixTop * s),
                stem: 20
            ),
            AnatomyCallout(
                id: 3,
                text: "Subagents running",
                side: .below,
                target: CGPoint(x: a.countsX * s, y: a.matrixBottom * s),
                stem: 20
            ),
            AnatomyCallout(
                id: 4,
                text: "The project being worked on",
                side: .below,
                target: CGPoint(x: a.projectNameX * s, y: a.readingGlyphBottom * s),
                stem: 20 + Self.stackedRowStep
            ),
            AnatomyCallout(
                id: 5,
                text: "A finished turn, unread",
                side: .above,
                target: CGPoint(x: a.buriedDotX * s, y: a.buriedDotTop * s),
                stem: 20
            ),
            AnatomyCallout(
                id: 6,
                text: "The longest running turn",
                side: .below,
                target: CGPoint(x: a.timerX * s, y: a.readingGlyphBottom * s),
                stem: 20
            )
        ]
    }

    // MARK: The panel's parts

    var expandedCallouts: [AnatomyCallout] {
        let a = expandedAnchors
        return [
            AnatomyCallout(
                id: 0,
                text: "Status of everything at once",
                side: .leading,
                target: CGPoint(x: a.matrixLeft, y: a.matrixMidY),
                stem: 26,
                drop: -12
            ),
            AnatomyCallout(
                id: 0,
                text: "Sessions and subagents",
                side: .above,
                target: CGPoint(x: a.countsX, y: a.matrixTop),
                stem: 22
            ),
            AnatomyCallout(
                id: 0,
                text: "Settings",
                side: .trailing,
                target: CGPoint(x: a.gearGlyphRight, y: a.matrixMidY),
                stem: 26
            ),
            // From above: the pair is flush, so two trailing leaders would land a button apart.
            AnatomyCallout(
                id: 0,
                text: "What this app is",
                side: .above,
                target: CGPoint(x: a.aboutGlyphMidX, y: a.matrixTop),
                stem: 22
            ),

            // Lifted `-12`: its part is `24.5` from the Project's, whose label is already lifted `18`.
            AnatomyCallout(
                id: 0,
                text: "One block per product",
                side: .leading,
                target: CGPoint(x: a.rowTextLeft, y: a.headingAboveRow(0) ?? a.rowCaptionY(0)),
                stem: 26,
                drop: -12
            ),

            AnatomyCallout(
                id: 0,
                text: "Project",
                side: .leading,
                target: CGPoint(x: a.rowTextLeft, y: a.rowCaptionY(0)),
                stem: 26,
                drop: -18
            ),
            AnatomyCallout(
                id: 0,
                text: "What the turn is doing",
                side: .leading,
                target: CGPoint(x: a.rowTextLeft, y: a.rowTitleY(0)),
                stem: 26
            ),
            AnatomyCallout(
                id: 0,
                text: "The latest thing it said",
                side: .leading,
                target: CGPoint(x: a.rowTextLeft, y: a.rowPreviewY(0)),
                stem: 26,
                drop: 18
            ),
            AnatomyCallout(
                id: 0,
                text: "Answer an approval without leaving",
                side: .trailing,
                target: CGPoint(x: a.rowTextRight, y: a.rowTitleY(0)),
                stem: 26
            ),
            AnatomyCallout(
                id: 0,
                text: "How long the turn has been running",
                side: .trailing,
                target: CGPoint(x: a.rowTextRight, y: a.rowTitleY(1)),
                stem: 26
            ),
            AnatomyCallout(
                id: 0,
                text: "Subagents still running",
                side: .trailing,
                target: CGPoint(x: a.rowTextRight, y: a.rowTitleY(2)),
                stem: 26
            ),
            AnatomyCallout(
                id: 0,
                text: "More sessions below",
                side: .trailing,
                target: CGPoint(x: a.railLeft, y: (a.rowTitleY(1) + a.rowTitleY(2)) / 2),
                stem: 22
            ),

            AnatomyCallout(
                id: 0,
                text: "Sessions that have left the list",
                side: .leading,
                target: CGPoint(x: a.rowTextLeft, y: a.seamY),
                stem: 26
            ),
            AnatomyCallout(
                id: 0,
                text: "Fold a section away",
                side: .trailing,
                target: CGPoint(x: a.seamChevronRight, y: a.seamY),
                stem: 26
            ),
            AnatomyCallout(
                id: 0,
                text: "Product, project and title",
                side: .leading,
                target: CGPoint(x: a.rowTextLeft, y: a.retiredRowY(1)),
                stem: 26
            ),
            AnatomyCallout(
                id: 0,
                text: "How long ago it left",
                side: .trailing,
                target: CGPoint(x: a.retiredAgeRight, y: a.retiredRowY(1)),
                stem: 26
            ),
            AnatomyCallout(
                id: 0,
                text: "Tokens spent today",
                side: .leading,
                target: CGPoint(x: a.rowTextLeft, y: a.spendY),
                stem: 26
            ),
            AnatomyCallout(
                id: 0,
                text: "Each product's own quota windows",
                side: .leading,
                target: CGPoint(x: a.windowLineLeft, y: a.windowLineY),
                stem: 34
            )
        ]
        .enumerated()
        .map { index, callout in
            var renumbered = callout
            renumbered.id = index + 1
            return renumbered
        }
    }
}
