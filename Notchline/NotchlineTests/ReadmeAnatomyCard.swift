// The README's anatomy figure: the collapsed pill and the expanded panel, with
// every part named.
//
// **The specimens are the product**, on `OnboardingAnatomy.swift`'s terms: each
// is `NotchOverlayView` over a `MonitorStore` built from fixed snapshots, at the
// size `PanelMetrics` composes for that state. What this file adds is the white
// card around them and the leaders that name their parts.
//
// Every anchor is asked of `PanelMetrics` and of the store, never read off a
// screenshot, so a change to the mark, the counts column, a row's shape or the
// footer's arithmetic moves the label with the part it names.
import AppKit
import SwiftUI

@testable import Notchline

// MARK: - Callouts

/// One label and the hairline that ties it to a part.
struct AnatomyCallout: Identifiable {
    enum Side {
        /// The label sits in the margin on that side of the figure.
        case leading, trailing
        /// The label sits above or below the figure, centred on the target.
        case above, below
    }

    let id: Int
    let text: String
    let side: Side
    /// The point on the figure the leader arrives at, in the figure's own
    /// coordinates.
    let target: CGPoint
    /// How far the leader runs before its label.
    ///
    /// For `.leading` and `.trailing` it is measured from the target, which is
    /// on the drawing. For `.above` and `.below` it is measured from the
    /// specimen's own top or bottom **edge**, because those targets are inside
    /// the drawing: a stem measured from one of them would leave the label
    /// standing on the panel it is naming.
    var stem: CGFloat = 24
    /// How far the label sits off the target's own line, for two parts that
    /// share one. Zero draws a straight leader.
    ///
    /// Vertical for `.leading` and `.trailing`, and **horizontal** for `.above`
    /// and `.below`, which is the axis those two crowd on: three answers `70`
    /// pt apart carry labels twice that wide, so one of them steps sideways to
    /// clear the leader of the one behind it.
    var drop: CGFloat = 0
}

/// The card's typography and inks: one grey for labels, one hairline, one
/// darker ink for the two captions.
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
    /// The hairline stops this far short of the part it names, so it points at
    /// a glyph rather than touching it.
    static let standoff: CGFloat = 2
    /// The clear space between a leader's end and the first glyph of its label.
    static let labelGap: CGFloat = 8
    /// How much room a label column is given. Two-line labels wrap inside it.
    ///
    /// `270` rather than `168` since the two figures took a shared page width:
    /// the room that buys goes to the labels, and every one of them now stands
    /// on a single line. It is bounded by the trailing column, which has the
    /// less of the two margins — `274` before a label would reach past the
    /// page's own padding.
    static let labelColumn: CGFloat = 270
    static let stackedLabelColumn: CGFloat = 190
}

/// A figure with its callouts: the specimen drawn at its own size, and the
/// labels standing in the margins around it.
///
/// The figure's own coordinates are the specimen's; the margins are laid out
/// around it, so a callout is placed by naming a point on the drawing rather
/// than a point on the card.
struct CalloutFigure<Specimen: View>: View {
    let callouts: [AnatomyCallout]
    let specimenSize: CGSize
    /// The room the labels are given on each side of the specimen.
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

    /// The target in the card's own coordinates.
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

/// Where a callout's label stands, and which way it reads.
private struct CalloutLabelPlacement: ViewModifier {
    let callout: AnatomyCallout
    let target: CGPoint
    /// The specimen's top and bottom edges, which is where an `.above` or
    /// `.below` stem is measured from.
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

/// The hairline itself: straight where the label sits on its target's own line,
/// and an elbow where it has been dropped off it.
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

/// Every anchor both figures need, asked of ``PanelMetrics`` and of the store
/// rather than read off a rendering.
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

    /// The counts column's own middle: both numerals are drawn from its leading
    /// edge and the narrower one sits under a point of this, so one x serves
    /// the stack.
    var countsX: CGFloat {
        matrixLeft
            + matrixSize
            + PanelMetrics.aggregateCountsGap
            + PanelMetrics.countsDigitWidth / 2
    }

    // MARK: The collapsed pill

    /// The pill's middle. The name is drawn from the slot's leading edge and
    /// faded off its trailing one, so the label goes on the name rather than on
    /// the slot.
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

    /// The bottom of a single line of text centred in the band — its baseline,
    /// since neither reading the pill draws has a descender below it.
    ///
    /// SwiftUI centres the *line box*, not the cap, so the baseline sits half
    /// the box's own asymmetry below the middle. Both readings are `13` pt
    /// Light: the timer's monospaced-digit face is the same font with tabular
    /// figures on, and carries the same ascender and descender, so one figure
    /// serves the pair.
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

    /// A row's text column, and the trailing edge its mark ends on. The rail
    /// takes its lane out of the second for as long as the list scrolls.
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

    /// The seam and the footer keep the full lane whatever the live list is
    /// doing: only the live rows give the rail its width.
    var seamChevronRight: CGFloat {
        shoulder
            + PanelMetrics.sessionRowGutter
            + PanelMetrics.sessionViewportWidth(panelWidth: bodyWidth)
            - PanelMetrics.sessionRowPadding
    }

    /// A retired row's age. The Recent queue has its own viewport and its own
    /// rail, and three rows do not fill five, so it keeps the whole lane.
    var retiredAgeRight: CGFloat { seamChevronRight }

    /// The rail stands on the panel's own `12` pt inset and never in it.
    var railLeft: CGFloat { trailingEdge - PanelMetrics.scrollRailWidth }

    func rowTop(_ index: Int) -> CGFloat {
        band + PanelMetrics.sessionRowHeight * CGFloat(index)
    }

    /// The row's three lines, at the offsets the row's own content block puts
    /// them at: `55` points of text centred in `80`.
    private var rowContentTop: CGFloat {
        let content = PanelMetrics.sessionRowCaptionHeight
            + PanelMetrics.sessionRowLineSpacing
            + PanelMetrics.sessionRowTitleHeight
            + PanelMetrics.sessionRowLineSpacing
            + PanelMetrics.sessionRowPreviewHeight
        return (PanelMetrics.sessionRowHeight - content) / 2
    }

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

    func retiredRowY(_ index: Int) -> CGFloat {
        seamTop
            + PanelMetrics.recentSeamHeight
            + PanelMetrics.retiredRowHeight * (CGFloat(index) + 0.5)
    }

    var footerTop: CGFloat {
        seamTop
            + PanelMetrics.recentSeamHeight
            + PanelMetrics.recentViewportHeight(retiredRowCount: store.recentDepartures.count)
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

/// The README's anatomy: both forms of the surface, on one white page, with
/// every part named.
@MainActor
struct ReadmeAnatomyCard: View {
    let compact: MonitorStore
    let expanded: MonitorStore

    /// The pill is `238 × 32`, which is too small an object to name six parts
    /// around, and too narrow to sit under the panel without leaving a third of
    /// its row empty. It is drawn at **the panel's own width** — the same
    /// drawing at the same proportions — so the two specimens share a left and
    /// a right edge and the page reads as a grid rather than as two figures
    /// that happen to be stacked.
    private var compactScale: CGFloat {
        expandedAnchors.windowWidth / compactAnchors.windowWidth
    }

    static let padding: CGFloat = 56

    /// The width both README figures are drawn at.
    ///
    /// **Set by the answering figure, which cannot be narrower.** Two request
    /// plates side by side are twice the panel's own width whatever else
    /// happens, so a page that holds them is `1364`; drawing the anatomy at
    /// anything less would put the two figures on the README at two widths and
    /// two scales, and a reader comparing a plate with the panel it opens on
    /// would be comparing two zoom levels.
    static let pageWidth: CGFloat = 1364

    /// The room a figure's labels stand in, either side of the specimen: what
    /// the page has left once the widest specimen has taken its share.
    ///
    /// Split `55 : 45`, because the labels are: the leading column is
    /// right-aligned and hugs the drawing while the trailing column is
    /// left-aligned and its longest label is shorter. One figure for both left
    /// the page visibly heavier on the left.
    static func margins(specimenWidth: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        let slack = max(0, pageWidth - padding * 2 - specimenWidth)
        // `47 : 53`, measured against the labels themselves rather than
        // guessed: with both columns at ``AnatomyCardStyle/labelColumn`` and
        // every label on one line, the longest trailing label is the longer of
        // the two, so the page balances a little the other way from the split
        // the narrow columns wanted.
        return (leading: slack * 0.47, trailing: slack * 0.53)
    }

    /// One margin pair for both figures, taken from the wider of the two
    /// specimens — so the pill and the panel stand on one left edge rather than
    /// each being centred on a block of its own.
    private var margins: (leading: CGFloat, trailing: CGFloat) {
        Self.margins(specimenWidth: max(compactSize.width, expandedSize.width))
    }
    /// And above and below it, for the labels that stand there. The panel
    /// carries none below it and gives that room back.
    static let stackMargin: CGFloat = 46
    /// The second row a stacked label drops to when the one beside it is too
    /// wide to share the first. `The project being worked on` and
    /// `Subagents running` are `94` pt apart on the pill and `175` and `118`
    /// wide, so one row cannot hold both.
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

    /// One width for the page, shared with the answering figure.
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

    private var compactCallouts: [AnatomyCallout] {
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

    private var expandedCallouts: [AnatomyCallout] {
        let a = expandedAnchors
        return [
            // The band, which the collapsed bar draws identically.
            AnatomyCallout(
                id: 1,
                text: "Status of everything at once",
                side: .leading,
                target: CGPoint(x: a.matrixLeft, y: a.matrixMidY),
                stem: 26,
                drop: -12
            ),
            AnatomyCallout(
                id: 2,
                text: "Sessions and subagents",
                side: .above,
                target: CGPoint(x: a.countsX, y: a.matrixTop),
                stem: 22
            ),
            AnatomyCallout(
                id: 3,
                text: "Settings",
                side: .trailing,
                target: CGPoint(x: a.gearGlyphRight, y: a.matrixMidY),
                stem: 26
            ),

            // One live row, line by line.
            AnatomyCallout(
                id: 4,
                text: "Product and project",
                side: .leading,
                target: CGPoint(x: a.rowTextLeft, y: a.rowCaptionY(0)),
                stem: 26,
                drop: -18
            ),
            AnatomyCallout(
                id: 5,
                text: "What the turn is doing",
                side: .leading,
                target: CGPoint(x: a.rowTextLeft, y: a.rowTitleY(0)),
                stem: 26
            ),
            AnatomyCallout(
                id: 6,
                text: "The latest thing it said",
                side: .leading,
                target: CGPoint(x: a.rowTextLeft, y: a.rowPreviewY(0)),
                stem: 26,
                drop: 18
            ),
            AnatomyCallout(
                id: 7,
                text: "Answer an approval without leaving",
                side: .trailing,
                target: CGPoint(x: a.rowTextRight, y: a.rowTitleY(0)),
                stem: 26
            ),
            AnatomyCallout(
                id: 8,
                text: "How long the turn has been running",
                side: .trailing,
                target: CGPoint(x: a.rowTextRight, y: a.rowTitleY(1)),
                stem: 26
            ),
            AnatomyCallout(
                id: 9,
                text: "Subagents still running",
                side: .trailing,
                target: CGPoint(x: a.rowTextRight, y: a.rowTitleY(2)),
                stem: 26
            ),
            AnatomyCallout(
                id: 10,
                text: "More sessions below",
                side: .trailing,
                target: CGPoint(x: a.railLeft, y: (a.rowTitleY(1) + a.rowTitleY(2)) / 2),
                stem: 22
            ),

            // The two sections under the live list.
            AnatomyCallout(
                id: 11,
                text: "Sessions that have left the list",
                side: .leading,
                target: CGPoint(x: a.rowTextLeft, y: a.seamY),
                stem: 26
            ),
            AnatomyCallout(
                id: 12,
                text: "Fold a section away",
                side: .trailing,
                target: CGPoint(x: a.seamChevronRight, y: a.seamY),
                stem: 26
            ),
            AnatomyCallout(
                id: 13,
                text: "Product, project and title",
                side: .leading,
                target: CGPoint(x: a.rowTextLeft, y: a.retiredRowY(1)),
                stem: 26
            ),
            AnatomyCallout(
                id: 14,
                text: "How long ago it left",
                side: .trailing,
                target: CGPoint(x: a.retiredAgeRight, y: a.retiredRowY(1)),
                stem: 26
            ),
            AnatomyCallout(
                id: 15,
                text: "Tokens spent today",
                side: .leading,
                target: CGPoint(x: a.rowTextLeft, y: a.spendY),
                stem: 26
            ),
            AnatomyCallout(
                id: 16,
                text: "Each product's own quota windows",
                side: .leading,
                target: CGPoint(x: a.windowLineLeft, y: a.windowLineY),
                stem: 34
            )
        ]
    }
}
