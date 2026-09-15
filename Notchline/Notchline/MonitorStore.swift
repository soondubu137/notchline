// Shared application state and display geometry for the monitor.
import AppKit
import Combine

enum DisplayGeometry: String, CaseIterable, Identifiable {
    case notched
    case noNotch

    var id: Self { self }

    var title: String {
        switch self {
        case .notched:
            "Notched display"
        case .noNotch:
            "Display without a notch"
        }
    }
}

struct DisplayOption: Identifiable {
    let id: String
    /// The window server's handle, `nil` where `id` fell back to a frame description.
    /// ``OverlayConcealment`` needs window-server bounds and cannot derive them from `frame`.
    let displayID: CGDirectDisplayID?
    let ordinal: Int
    let name: String
    let frame: NSRect
    let visibleFrame: NSRect
    let safeAreaInsets: NSEdgeInsets
    let auxiliaryTopLeftArea: NSRect?
    let auxiliaryTopRightArea: NSRect?
    let fallbackMenuBarHeight: CGFloat

    var pickerTitle: String {
        "\(ordinal). \(name)"
    }

    var geometry: DisplayGeometry {
        let hasTopInset = safeAreaInsets.top >= 1
        let hasAuxiliaryArea = [auxiliaryTopLeftArea, auxiliaryTopRightArea]
            .compactMap { $0 }
            .contains { !$0.isEmpty }
        return hasTopInset && hasAuxiliaryArea ? .notched : .noNotch
    }

    /// The larger of `safeAreaInsets.top` (camera housing, `38` on a 14-inch M3 Pro at *More
    /// Space*) and `frame.maxY - visibleFrame.maxY` (the bar, `40`). The panel uses
    /// ``panelBandHeight``.
    var menuBarHeight: CGFloat {
        let occupiedTopHeight = max(0, frame.maxY - visibleFrame.maxY)
        let measuredHeight = max(occupiedTopHeight, safeAreaInsets.top)
        return measuredHeight >= 1
            ? measuredHeight
            : max(1, fallbackMenuBarHeight)
    }

    /// The band the collapsed panel fills: the cut-out on a notched display, the menu bar
    /// otherwise. On a notched display the bar is taller (`40` vs `38`) and would hang the
    /// panel below the hardware. `safeAreaInsets.top` survives an auto-hidden menu bar, and is
    /// read per display because the cut-out's height in points varies with scaling (`38`,
    /// ~`32`, `22`) — never a fixed pixel count.
    var panelBandHeight: CGFloat {
        guard geometry == .notched, safeAreaInsets.top >= 1 else {
            return menuBarHeight
        }
        return safeAreaInsets.top
    }

    var centerOcclusionWidth: CGFloat {
        guard geometry == .notched,
              let auxiliaryTopLeftArea,
              let auxiliaryTopRightArea else {
            return 0
        }

        return max(0, auxiliaryTopRightArea.minX - auxiliaryTopLeftArea.maxX)
    }

    /// The cut-out's trailing edge, in screen coordinates. The compact panel pins to it rather
    /// than centring: rounding against the midpoint leaves a visible seam beside the cut-out.
    var centerOcclusionMaxX: CGFloat? {
        guard geometry == .notched,
              let auxiliaryTopRightArea,
              centerOcclusionWidth >= 1 else {
            return nil
        }

        return auxiliaryTopRightArea.minX
    }

    var configurationSummary: String {
        // Names the band actually drawn; the menu bar on a notched screen is two points off.
        let band = geometry == .notched ? "notch" : "menu bar"
        return "\(geometry.title) · \(band) \(Int(panelBandHeight.rounded())) pt"
    }

    static func currentDisplays() -> [DisplayOption] {
        NSScreen.screens.enumerated().map { index, screen in
            DisplayOption(
                id: identifier(for: screen),
                displayID: screen.cgDirectDisplayID,
                ordinal: index + 1,
                name: screen.localizedName,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                safeAreaInsets: screen.safeAreaInsets,
                auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
                auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
                fallbackMenuBarHeight: NSStatusBar.system.thickness
            )
        }
    }

    static func identifier(for screen: NSScreen) -> String {
        if let displayID = screen.cgDirectDisplayID {
            return "display-\(displayID)"
        }

        if let screenNumber = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber {
            return "display-\(screenNumber.uint32Value)"
        }

        let frame = screen.frame
        return "frame-\(frame.minX)-\(frame.minY)-\(frame.width)-\(frame.height)"
    }
}

/// What the collapsed surface draws on the far side of the notch: the timer reading only;
/// subagents are counted in the leading wing (`compact-view-v2.md` §3, §4). One value, since
/// the panel's width is measured from it.
struct CompactTrailingReading: Equatable {
    var timerText: String?
    /// Whether the digits have stopped: a finished turn freezes at the last value, and
    /// ``drawsFinishedDot`` says so (`compact-view-v2.md` §4.2).
    var isFrozen = false
    /// Whether a finished, unread turn is hidden under a mark drawing something else; the dot
    /// stands in for it (§4.3).
    var buriesAFinishedTurn = false

    static let empty = CompactTrailingReading()

    var isEmpty: Bool { timerText == nil && !buriesAFinishedTurn }

    /// One dot for both a frozen reading and a buried finished turn (`compact-view-v2.md` §4.2,
    /// §4.3). Read by the width composition as well as the view, so drawn and billed width agree.
    var drawsFinishedDot: Bool { buriesAFinishedTurn || isFrozen }
}

enum PanelMetrics {
    static let referenceCompactHeight: CGFloat = 46
    /// The cut-out's upper fillet, half the lower radius. Drawing it at the lower radius reads
    /// as a black box under the bezel rather than the cut-out.
    static let notchUpperRadiusRatio: CGFloat = 1.0 / 8
    /// The cut-out's lower corners, as a share of its height.
    static let notchLowerRadiusRatio: CGFloat = 1.0 / 4
    /// Corner smoothing for the lower corners, as in Figma's control and Apple's continuous
    /// corners: a circular arc's curvature jump reads as a crease against a lit wallpaper.
    /// The curve starts `(1 + smoothing)` radii back, eases curvature up from zero (control
    /// points on the straight edge), holds `90° × (1 - smoothing)` of arc, and eases out.
    /// `0.6` is Figma's 60%; `0` reproduces the circular corner
    /// (`theLowerCornersReduceToCircularArcsWithoutSmoothing`). The upper fillets stay circular
    /// (`docs/figma-design.md` §3.3): smaller, against the screen's top edge, no crease to see.
    static let notchLowerCornerSmoothing: CGFloat = 0.6

    /// How far back along each straight edge a lower corner reaches; this, not the radius, must
    /// fit inside the panel's height and half its width.
    static func smoothCornerReach(radius: CGFloat) -> CGFloat {
        max(0, radius) * (1 + max(0, notchLowerCornerSmoothing))
    }
    /// Drawn inside the contour, so this is the full line width. `0.8` is deliberately off the
    /// pixel grid: antialiased, it reads as the black ending rather than a drawn border. A
    /// constant, not a share of the menu bar height.
    static let surfaceOutlineWidth: CGFloat = 0.8
    static let expandedBaselineWidth: CGFloat = 610
    /// A live row's three lines with their spacing: `16 + 2 + 17 + 2 + 18`.
    static let sessionRowContentHeight: CGFloat = sessionRowCaptionHeight
        + sessionRowLineSpacing
        + sessionRowTitleHeight
        + sessionRowLineSpacing
        + sessionRowPreviewHeight
    /// The air above a live row's first line and below its last. `8.5` leaves `17` between
    /// rows, clear of the `12` pt hover corner; the half point lands on the grid at 2x.
    static let sessionRowVerticalPadding: CGFloat = 8.5
    /// Inset of a row's hover ground inside its frame, so a washed row never shares an edge with
    /// a heading chip's ground (`expanded-panel-v2.md` §4.2). `2` is `4` pixels: a seam, not space.
    static let sessionRowGroundInset: CGFloat = 2
    /// `72` = `8.5 + 55 + 8.5`, composed from ``sessionRowVerticalPadding``, which also keeps
    /// ``OpenRow``'s explicit inset equal to the closed row's.
    static let sessionRowHeight: CGFloat = sessionRowContentHeight
        + sessionRowVerticalPadding * 2
    /// A row that has left the list: half a live row, exactly (`expanded-panel-v2.md` §2.1).
    static let retiredRowHeight: CGFloat = sessionRowHeight / 2
    /// The rule between the list and the Recent queue, and the footer's spend line
    /// (`quota-footer-v2.md` §2): `9` + a `14` pt caption line + `9`.
    static let recentSeamHeight: CGFloat = 32
    /// Shared by the live row's layer mask (``SessionRowTextView``) and a retired row's SwiftUI
    /// gradient, so the two fades cannot drift.
    static let rowTrailingFadeWidth: CGFloat = 48
    /// The tallest the ungrouped live viewport is drawn: four rows, as a height so a taller open
    /// row shares it. Matches ``groupedSessionViewportCap``'s rows, so `Group by product` never
    /// changes the row count. The Recent queue has its own (``recentViewportCap``).
    static let sessionViewportCap: CGFloat = sessionRowHeight * 4
    /// One line of badges at an edge of the grouped viewport (`expanded-panel-v2.md` §4.6): the
    /// badge's own height.
    static var productTrailHeight: CGFloat { productBadgeHeight }
    /// The tallest the grouped live viewport is drawn: a trail, four rows, a trail
    /// (`16 + 288 + 16`), however many products there are.
    static var groupedSessionViewportCap: CGFloat {
        productTrailHeight * 2 + sessionViewportCap
    }
    /// Docking travel: the heading bar's height, so its slack is where the motion happens
    /// (`expanded-panel-v2.md` §4.6).
    static var productTrailDockingDistance: CGFloat { productGroupHeaderHeight }
    /// The panel's *not the subject* weight. A block that wants a person keeps full weight and
    /// flips its badge instead (``NotchPalette/brightGround``).
    static let productTrailBadgeOpacity: Double = 0.45
    /// The fade above the foot line, which draws no rule, so rows scrolling under it fade.
    static var productTrailFadeHeight: CGFloat { productBadgeHeight }
    /// One declaration, so ``productBadgeWidth(_:)`` measures the face the badge is drawn in.
    static let productBadgeFont = NSFont.systemFont(ofSize: 10, weight: .medium)
    /// Padding either side of the rendered name, measured rather than tabulated
    /// (`colour-v2.md` §4).
    static func productBadgeWidth(_ name: String) -> CGFloat {
        productBadgePadding * 2 + textWidth(name, font: productBadgeFont)
    }
    /// A heading's air above its chip, and all that separates two blocks
    /// (`expanded-panel-v2.md` §4.2). `8` puts `16.5` above the chip and `8.5` below, so a block
    /// boundary costs what a row boundary does (`17`).
    static let productGroupHeaderSlack: CGFloat = 8
    /// A block's heading bar: chip plus slack, composed from the slack. No chevron: nothing to
    /// fold, so the hairline runs to the content box's trailing edge (`answer-in-notch.md` §11
    /// rule 03).
    static var productGroupHeaderHeight: CGFloat {
        productBadgeHeight + productGroupHeaderSlack
    }
    /// The first heading drops its slack (the chip alone, `16`): the band above already brings
    /// its air, and its rule replaces the panel's top hairline. See
    /// ``MonitorStore/listLeadsWithABlockHeading``.
    static var leadingProductGroupHeaderHeight: CGFloat { productBadgeHeight }
    static func groupHeadingsHeight(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return leadingProductGroupHeaderHeight
            + productGroupHeaderHeight * CGFloat(count - 1)
    }
    /// The Recent queue's viewport cap: five retired rows.
    static let recentViewportCap: CGFloat = retiredRowHeight * 5
    /// The panel's horizontal inset, collapsed and expanded alike despite the name: compact
    /// margins, wings, expanded rows and footer. See `figma-design.md` §3.3.
    static let expandedHorizontalPadding: CGFloat = 12
    /// The row's block stops short of the panel inset so its hover fill has a gutter; the row's
    /// padding adds it back, so text lands on `expandedHorizontalPadding` whatever that becomes.
    static let sessionRowGutter: CGFloat = 6
    static let sessionRowPadding: CGFloat = expandedHorizontalPadding
        - sessionRowGutter

    /// The scroll rail and its lane. Its right edge lands on ``expandedHorizontalPadding``, so
    /// the `12` pt inset stays empty; the rows narrow by ``scrollRailLane`` only while it shows.
    static let scrollRailWidth: CGFloat = 3
    static let scrollRailGap: CGFloat = 4
    static let scrollRailLane: CGFloat = scrollRailWidth + scrollRailGap

    /// Panel width less the gutters, and less the rail's lane only while `isScrolling`.
    static func sessionViewportWidth(
        panelWidth: CGFloat,
        isScrolling: Bool = false
    ) -> CGFloat {
        panelWidth - sessionRowGutter * 2 - (isScrolling ? scrollRailLane : 0)
    }
    /// Declared here because the row's content block is composed from them. The caption is `16`
    /// with or without a badge (`panel-v2.md` §2), so rows don't move when a product connects.
    static let sessionRowCaptionHeight: CGFloat = 16
    static let sessionRowTitleHeight: CGFloat = 17
    static let sessionRowPreviewHeight: CGFloat = 18
    static let sessionRowLineSpacing: CGFloat = 2

    /// The bar a covered run leaves (`cover-the-words.md` §4): fully rounded, one height for
    /// every line.
    static let coverBarHeight: CGFloat = 6
    /// Fixed lengths, not the text's (`0.13`, `0.32`, `0.45` of the `496` pt content box): a bar
    /// sized to its run leaks the work's shape and twitches as a preview streams.
    static let coverBarProjectLength: CGFloat = 64
    static let coverBarTitleLength: CGFloat = 160
    static let coverBarPreviewLength: CGFloat = 224
    /// A retired row's one line is covered at the title's length.
    static var coverBarBreadcrumbLength: CGFloat { coverBarTitleLength }

    /// The chip that names a product on a row's caption and a retired row's breadcrumb, not the
    /// footer (`colour-v2.md` §4). Width is `6 + measured text + 6`, never tabulated.
    static let productBadgeHeight: CGFloat = 16
    static let productBadgeRadius: CGFloat = 5
    static let productBadgePadding: CGFloat = 6
    static let captionFont = NSFont.systemFont(ofSize: 11, weight: .light)
    /// The room a set `"· "` takes at the caption face, measured, so the badge-to-count gap is
    /// what it would be with a text separator.
    static var captionSeparatorWidth: CGFloat {
        textWidth("· ", font: captionFont)
    }
    static var productBadgeCountGap: CGFloat {
        productBadgePadding + captionSeparatorWidth
    }
    /// The separator dot, drawn rather than set: a `·` glyph at `11` pt Light sits `0.77` below
    /// the bar's centre line, off its hairline. `2`, in caption ink, on heading and seam alike —
    /// the `13` pt Regular `·` measures `1.65` but a `1.65` disc snaps to `1.5` at 2x and reads
    /// lighter.
    static let captionSeparatorDotSize: CGFloat = 2
    /// Spacing either side of the dot, so it centres in ``productBadgeCountGap`` and the count
    /// does not move.
    static var productBadgeCountSpacing: CGFloat {
        (productBadgeCountGap - captionSeparatorDotSize) / 2
    }

    /// Spacing either side of the seam's dot, so the word and figure stay where `" · "` put them.
    static var seamSeparatorSpacing: CGFloat {
        (textWidth(" · ", font: captionFont) - captionSeparatorDotSize) / 2
    }
    static let expandedReadoutSpacing: CGFloat = 12
    static let expandedNotchClearance: CGFloat = 8
    static let footerCaptionSpacing: CGFloat = 5
    static let footerRuleSpacing: CGFloat = 9
    /// One line of the footer's `11pt` caption; every footer height is composed from it. Also the
    /// air between product groups.
    static let footerCaptionHeight: CGFloat = 14

    /// Chosen so the clearance below the spend line's text (this plus the bar's `9` of inner air)
    /// is `12`, the panel's ``expandedHorizontalPadding``.
    static let footerBottomMargin: CGFloat = 3
    /// Table captions occupy only their line height, so they add the resting caption's inner
    /// inset to match its bottom clearance.
    static let footerCaptionBottomMargin: CGFloat = footerBottomMargin
        + (recentSeamHeight - footerCaptionHeight) / 2

    static let footerWindowRowHeight: CGFloat = footerCaptionHeight
        + footerCaptionSpacing
    /// One step of ``expandedHorizontalPadding`` in, putting a window's label at `24` on the panel;
    /// indentation alone carries the level.
    static let footerWindowIndent: CGFloat = expandedHorizontalPadding
    /// The least a product's name stands from its spend, and the gap between a window's name and
    /// its share.
    static let footerColumnGutter: CGFloat = expandedHorizontalPadding * 2
    /// Sized to the widest window name: `Current session` measures `81.56` at 11 pt Light.
    /// Per-model windows are named by the account's model, so a longer name eats the gutter.
    static let footerWindowColumnWidth: CGFloat = 84
    /// The share column: `100% left` is `48.78`, and nothing wider can appear.
    static let footerShareColumnWidth: CGFloat = 52
    /// The share column's trailing edge in the footer's content box, `184` on the panel, composed
    /// from the columns so the share stands beside its window.
    static let footerShareTrailingEdge: CGFloat = footerWindowIndent
        + footerWindowColumnWidth
        + footerColumnGutter
        + footerShareColumnWidth

    /// Both band controls' glyph size. The mark asset is pinned to `13 × 13`: changing this means
    /// regenerating `NotchlineMark.imageset` from `design/assets/05-menubar`.
    static let bandControlGlyphSize: CGFloat = 13

    /// Scales with the menu bar: `32` under a `46pt` bar, `20` under a `24pt` one.
    static func settingsButtonSize(compactHeight: CGFloat) -> CGFloat {
        let ratio = (compactHeight - 24) / (46 - 24)
        return min(32, max(20, 20 + ratio * 12))
    }

    /// The resting pill once hovered: grows sideways to reach the gear and the About mark, and
    /// nothing else (nothing connected means no content to drop). Composed symmetrically, since
    /// the expanded panel is centred: `cut-out + 2 × (8 + mark + gear + 12)` — `247` at
    /// `127 × 22`, `323` at `185 × 32`, `368` at `200 × 46`, `371` at `220 × 38`
    /// (`expanded-header-v2.md` §5).
    static func restingExpandedWidth(
        geometry: DisplayGeometry,
        centerOcclusionWidth: CGFloat,
        compactHeight: CGFloat
    ) -> CGFloat {
        let trailing = expandedTrailingSideWidth(compactHeight: compactHeight)
        guard geometry == .notched, centerOcclusionWidth >= 1 else {
            // Nothing to be symmetric about: the status mark and the two controls, one clearance apart.
            return ceil(
                expandedHorizontalPadding + statusMatrixSize + trailing
            )
        }
        return ceil(centerOcclusionWidth + trailing * 2)
    }

    /// The footer at rest: `35` at every connected form. No window crosses a threshold
    /// (`quota-footer-v2.md` §4), so nothing changes it. The spend line is ``recentSeamHeight``
    /// so the panel's two closing lines match.
    static let restingFooterHeight: CGFloat = recentSeamHeight
        + footerBottomMargin
    /// The chevron glyph's own square, inside the spend line's `32pt` bar.
    static let quotaFoldControlSize: CGFloat = 16

    /// `35` at rest, or `19W + 28P + 39` open: spend line and gap (`32 + 9`), per product a `14`
    /// caption and `19` per window, `14` between groups, `12` below. Nothing connected is no
    /// footer (§8.5 question 07).
    static func footerHeight(
        productCount: Int,
        windowCount: Int,
        isExpanded: Bool = false
    ) -> CGFloat {
        guard productCount > 0 else { return 0 }
        guard isExpanded else { return restingFooterHeight }

        return recentSeamHeight
            + footerRuleSpacing
            + CGFloat(productCount) * footerCaptionHeight
            + CGFloat(windowCount) * footerWindowRowHeight
            + CGFloat(productCount - 1) * footerCaptionHeight
            + footerCaptionBottomMargin
    }

    static func footerHeight(rules: [FooterRule], isExpanded: Bool = false) -> CGFloat {
        footerHeight(
            productCount: rules.count,
            windowCount: rules.reduce(0) { $0 + $1.windows.count },
            isExpanded: isExpanded
        )
    }
    static let thinExpandedBodyHeight: CGFloat = 48
    /// The live viewport over a resting footer: `308`. Not a panel cap — the live list and the
    /// Recent queue each fold on their own caps.
    static let expandedContentHeight: CGFloat = sessionViewportCap
        + restingFooterHeight
    static let thinExpandedContentHeight: CGFloat = thinExpandedBodyHeight
        + restingFooterHeight

    // MARK: - The About panel

    /// The About lockup's box height, clear space included: `36` draws `25.5` of mark (`155` in
    /// `219`), half again the status matrix, so the logo is plainly not a status display.
    static let aboutLockupHeight: CGFloat = 36
    /// The package's box ratio, not a crop, so the baked-in clear space stays intact.
    static let aboutLockupAspect: CGFloat = 1075.15 / 219
    static var aboutLockupWidth: CGFloat { aboutLockupHeight * aboutLockupAspect }

    /// The air above the lockup, measured from the rule that closes the band.
    static let aboutTopMargin: CGFloat = 28
    static let aboutBottomMargin: CGFloat = 24
    static let aboutLockupTextGap: CGFloat = 20
    static let aboutTextLineGap: CGFloat = 4
    static let aboutTextControlGap: CGFloat = 22
    static let aboutLinkHeight: CGFloat = 20

    /// SwiftUI's single-line height for ``captionFont``: it ceils ascent and descent separately
    /// (`14`), not their sum like `NSLayoutManager.defaultLineHeight` (`13`).
    static var aboutTextLineHeight: CGFloat {
        ceil(captionFont.ascender) + ceil(-captionFont.descender)
    }

    /// The update dot on the About mark (`updates-on-the-notch.md` §2): the finished-turn dot's `4`.
    static let aboutUpdateDotDiameter: CGFloat = 4
    /// Centred on the terrace's empty corner cell (4, 4) of the `13` pt glyph: the cell's centre
    /// sits `128 + 13.5` of the mark's `155` units in, so the dot overhangs the glyph by `0.87`.
    static var aboutUpdateDotCentre: CGFloat { bandControlGlyphSize * (128 + 13.5) / 155 }
    /// The About row's controls and readings stand this far apart.
    static let aboutUpdateRowSpacing: CGFloat = 8
    /// The download meter (§3): a `120 × 3` capsule, track `hairline`, fill `themeInk.on`.
    static let updateMeterWidth: CGFloat = 120
    static let updateMeterHeight: CGFloat = 3

    /// Whole points of fill, never rounded up, so the meter cannot read full before it is.
    static func updateMeterFill(_ fraction: Double) -> CGFloat {
        (updateMeterWidth * CGFloat(min(max(fraction, 0), 1))).rounded(.down)
    }

    /// A constant: nothing running changes the About panel's content, so it never moves.
    static var aboutPanelHeight: CGFloat {
        aboutTopMargin
            + aboutLockupHeight
            + aboutLockupTextGap
            + aboutTextLineHeight * 2
            + aboutTextLineGap * 2
            + aboutLinkHeight
            + aboutTextControlGap
            + answerRowHeight
            + aboutBottomMargin
    }
    /// Fixed, not a share of the menu bar, because the 13pt label doesn't scale either. From
    /// loaders.wtf's indicator-to-text ratio (92pt beside 72pt): 13 × 1.2778 ≈ 16.6.
    static let statusMatrixSize: CGFloat = 16.6
    /// Light, as drawn; any other weight over-reserves every compact width.
    private static let statusLabelFont = NSFont.systemFont(ofSize: 13, weight: .light)
    /// Tabular figures, so the width does not change every second.
    private static let timerFont = NSFont.monospacedDigitSystemFont(
        ofSize: 13,
        weight: .light
    )

    // MARK: - The aggregate counts column

    /// `11` pt at the display optical size: AppKit's SF Pro Text digits are `6.99`, the board's
    /// SF Pro Display `6.6`; CoreText's display cut gives `6.616`. Regular, since Light (`6.549`)
    /// and medium (`6.784`) miss the billed `6.6`.
    static let countsSessionFont = countsFont(ofSize: 11)
    /// The subagents numeral: the same face, two steps down (`5.637` cap).
    static let countsSubagentFont = countsFont(ofSize: 8)

    /// Monospaced digits (a proportional `1` resizes the wing, `compact-view-v2.md` §3.2 rule 05)
    /// at the display optical size.
    private static func countsFont(ofSize size: CGFloat) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        let descriptor = base.fontDescriptor.addingAttributes([
            NSFontDescriptor.AttributeName(kCTFontOpticalSizeAttribute as String):
                countsOpticalSize
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// Past SF's `20` pt crossover every value gives the display digits.
    private static let countsOpticalSize: CGFloat = 20

    static let aggregateCountsGap: CGFloat = 4

    /// `6.616`, the drawn advance; the difference from `6.6` is absorbed by each width's `ceil`
    /// (`304`/`310` notched, `250` pill; `compact-view-v2.md` §6.1).
    static var countsDigitWidth: CGFloat {
        textWidth("8", font: countsSessionFont)
    }

    /// Zero sessions is no column (§3.2 rule 03). The subagent numeral is narrower and never
    /// widens this.
    static func countsColumnWidth(sessionCount: Int) -> CGFloat {
        guard sessionCount > 0 else { return 0 }
        return CGFloat(String(sessionCount).count) * countsDigitWidth
    }

    /// The column at two digits, which is what the pill holds open.
    static var reservedCountsColumnWidth: CGFloat { 2 * countsDigitWidth }

    /// The gap belongs to the column, so a bar with no rows gives both back. The pill reserves two
    /// digits whatever it draws.
    static func countsSlotWidth(sessionCount: Int, reserved: Bool) -> CGFloat {
        if reserved { return aggregateCountsGap + reservedCountsColumnWidth }
        guard sessionCount > 0 else { return 0 }
        return aggregateCountsGap + countsColumnWidth(sessionCount: sessionCount)
    }

    /// Sessions numeral baseline above the matrix's bottom: cap-top on the matrix's top edge with
    /// a subagent, optically centred alone — a `4.425` rise when the first subagent starts (§3.4).
    static func countsSessionBaseline(
        hasSubagents: Bool,
        matrixSize: CGFloat = statusMatrixSize
    ) -> CGFloat {
        let cap = countsSessionFont.capHeight
        return hasSubagents ? matrixSize - cap : (matrixSize - cap) / 2
    }

    /// Where the subagents numeral stands: on the matrix's bottom edge.
    static let countsSubagentBaseline: CGFloat = 0

    // MARK: - The expanded band

    /// The band's leading side: `53.8` at every agent count, identical collapsed and expanded
    /// (`colour-v2.md` §3).
    static let expandedLeadingSideWidth: CGFloat = expandedHorizontalPadding
        + statusMatrixSize
        + aggregateCountsGap
        + reservedCountsColumnWidth
        + expandedNotchClearance

    /// The band's trailing side: the About mark, then the gear where macOS puts settings. Flush,
    /// since each ``settingsButtonSize`` box already pads its `13` pt glyph.
    static func expandedTrailingSideWidth(compactHeight: CGFloat) -> CGFloat {
        expandedNotchClearance
            + settingsButtonSize(compactHeight: compactHeight) * 2
            + expandedHorizontalPadding
    }

    /// The gap goes with the column, so a bar with no rows is the matrix alone.
    static func drawnLeadingGroupWidth(sessionCount: Int) -> CGFloat {
        let counts = countsColumnWidth(sessionCount: sessionCount)
        return statusMatrixSize + (counts > 0 ? aggregateCountsGap + counts : 0)
    }

    /// The leading group at the room the pill holds open for it: `33.8`.
    static var reservedLeadingGroupWidth: CGFloat {
        statusMatrixSize + aggregateCountsGap + reservedCountsColumnWidth
    }

    // MARK: - The pill's middle

    /// `13` pt Light; `notchline` measures `55.10`, the figure `compact-view-v2.md` §6.3 fits.
    static let projectNameFont = statusLabelFont

    /// A long name fades rather than clips or ellipsises.
    static let projectNameFadeWidth: CGFloat = 12

    /// How long each Project is named before the next one.
    static let projectNameInterval: TimeInterval = 5





    /// The subagent badge. `15 × 15` (`dual-agent-design.md` §10) is a floor: a count of `10`+
    /// grows it (`figma-design.md` §4.6).
    static let subagentBadgeFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
    static let subagentBadgeMinSize: CGFloat = 15
    static let subagentBadgeCornerRadius: CGFloat = 4
    static let subagentBadgeHorizontalPadding: CGFloat = 4
    static let subagentBadgeTimerSpacing: CGFloat = 8

    /// The ground an elapsed reading sits on (`figma-design.md` page 14): a silhouette one row can
    /// answer alone. Shares the subagent badge's geometry — one family of marks.
    static let readingGroundHeight: CGFloat = 16
    static var readingGroundCornerRadius: CGFloat { subagentBadgeCornerRadius }
    static var readingGroundPadding: CGFloat { subagentBadgeHorizontalPadding }
    static var readingGroundWidthCost: CGFloat { readingGroundPadding * 2 }

    /// One light face for request buttons, the waiting mark and destination control; measurement
    /// and drawing share it.
    static let requestControlFont = NSFont.systemFont(ofSize: 13, weight: .light)

    /// One answer's width: its word plus ``controlHorizontalPadding`` a side. Answers hug; the
    /// first-run window places its pins from this same figure (`figma-design.md` §7.1.2).
    static func drawnAnswerControlWidth(_ label: String) -> CGFloat {
        ceil(textWidth(label, font: requestControlFont)) + controlHorizontalPadding * 2
    }
    static let waitingMarkFont = requestControlFont

    /// Built like a control, not a reading: ``answerRowHeight``, with the answers' corner and
    /// padding, so it is the same object as the affirmative it grows into (`answer-in-notch.md`
    /// §3.1).
    static var waitingMarkHeight: CGFloat { answerRowHeight }
    static var waitingMarkCornerRadius: CGFloat { controlCornerRadius }
    static var waitingMarkPadding: CGFloat { controlHorizontalPadding }

    /// One width whichever word it holds: the widest of ``waitingMarkWords`` (`Approve`, `76`),
    /// so a mixed queue keeps a straight column. The word is decided at rest, and nothing on a
    /// row moves under the pointer (`answer-in-notch.md` §3.3). Derived; a test pins that every
    /// word fits.
    static let waitingMarkWidth: CGFloat = waitingMarkWords
        .map(huggedWaitingMarkWidth)
        .max() ?? 0

    static let waitingMarkWords = [
        waitingMarkApproveWord, waitingMarkAnswerWord, waitingMarkReadWord
    ]

    /// A word's width with ``waitingMarkPadding`` a side; narrower words centre inside the widest.
    static func huggedWaitingMarkWidth(_ word: String) -> CGFloat {
        ceil(textWidth(word, font: waitingMarkFont) + waitingMarkPadding * 2)
    }

    /// A verb offering the act: `Approve` for consent, `Answer` for a question, `Read` where no
    /// connection is held open to answer it (§11 rule 03) — so it is asked of the request, not
    /// only the status. `SessionStatus/displayName` still supplies the accessibility label.
    static func waitingMarkWord(
        for status: SessionStatus,
        canBeAnswered: Bool
    ) -> String {
        guard canBeAnswered else { return waitingMarkReadWord }
        switch status {
        case .approvalNeeded:
            return waitingMarkApproveWord
        case .inputNeeded:
            return waitingMarkAnswerWord
        case .running, .completed:
            return waitingMarkReadWord
        }
    }

    static let waitingMarkApproveWord = "Approve"
    static let waitingMarkAnswerWord = "Answer"
    /// Per row, not per product: what a row can do is a fact about its request.
    static let waitingMarkReadWord = "Read"

    static func subagentBadgeWidth(_ count: Int) -> CGFloat {
        let measured = textWidth("\(count)", font: subagentBadgeFont)
            + subagentBadgeHorizontalPadding * 2
        return max(subagentBadgeMinSize, ceil(measured))
    }

    /// Everything the collapsed trailing slot draws; one expression for both collapsed forms, with
    /// nothing reserved.
    /// - The reading carries a `.clear` ``ReadingGround``, billed by ``readingGroundWidthCost``.
    /// - A new digit steps the panel out: the notched bar on its trailing wing only (its whole
    ///   points cancel from the leading edge's sum), the centred pill by half on each edge.
    /// - Every term is whole (``drawnCompactReadingWidth(_:)`` ceils like the raster), so the
    ///   reading starts ``expandedNotchClearance`` past the cut-out at every length.
    static func drawnTrailingReadingWidth(_ trailing: CompactTrailingReading) -> CGFloat {
        let dot = trailing.drawsFinishedDot ? buriedFinishDotSize : 0
        guard let timerText = trailing.timerText else {
            // Each gap exists only where content stands on both sides.
            return dot
        }
        guard trailing.drawsFinishedDot else {
            return drawnCompactReadingWidth(timerText)
        }
        return dot + buriedFinishDotSpacing + drawnCompactReadingWidth(timerText)
    }

    /// The finished-turn dot: `4`, in ``NotchPalette/finishedDotDrawingColor``, laid out `8` before
    /// the reading. Whole numbers keep the wing integral
    /// (`theTrailingWingIsWholePointsSoTheLeadingEdgeCannotMove`). The wing draws it `12` off the
    /// digits via its ground's padding; rows use ``drawnFinishDotGap`` to match.
    static let buriedFinishDotSize: CGFloat = 4
    static let buriedFinishDotSpacing: CGFloat = 8
    /// The visible dot-to-digit distance: ``buriedFinishDotSpacing`` plus the ground padding that
    /// every grounded reading has, for the one surface that must add it by hand.
    static var drawnFinishDotGap: CGFloat {
        buriedFinishDotSpacing + readingGroundPadding
    }
    /// What the dot costs a wing that is also drawing a reading.
    static var buriedFinishSlotWidth: CGFloat {
        buriedFinishDotSize + buriedFinishDotSpacing
    }


    /// Compact content trailing the notch, including its padding. Zero with no reading, so an idle
    /// notched display draws no blank wing that reads as a second notch.
    static func compactTrailingWidth(trailing: CompactTrailingReading) -> CGFloat {
        guard !trailing.isEmpty else { return 0 }
        return drawnTrailingReadingWidth(trailing) + expandedHorizontalPadding
    }

    /// How far the compact body reaches past the cut-out's trailing edge. The panel is pinned to
    /// that edge, so rounding goes to the leading wing. With nothing to draw it is exactly `0` —
    /// no outward step for the glass flare, which showed as a black nub beside the hardware. Whole
    /// points, so it cancels from `ceil(leading + occlusion + wing)` and the leading edge never
    /// moves (`theLeadingMatrixNeverMovesWhateverTheCountsDo`).
    static func compactTrailingWingWidth(
        trailing: CompactTrailingReading
    ) -> CGFloat {
        let content = compactTrailingWidth(trailing: trailing)
        guard content > 0 else { return 0 }
        return ceil(content + expandedNotchClearance)
    }

    /// Leading wing on a notched display: padding, the mark, the counts, the clearance. No mark
    /// draws nothing — at rest a notched display hides the wing; a no-notch display keeps its mark
    /// so the menu bar doesn't shift. With `Hide Notchline` it comes out whole only when something
    /// waits on a person (`compact-view-v2.md` §9). `47.2` at one digit, `53.8` at two, `36.6`
    /// with no rows.
    private static func notchedLeadingWidth(
        drawsMark: Bool,
        sessionCount: Int
    ) -> CGFloat {
        guard drawsMark else { return 0 }
        return expandedHorizontalPadding
            + drawnLeadingGroupWidth(sessionCount: sessionCount)
            + expandedNotchClearance
    }

    /// The contour's upper fillet, and the shoulder the window needs each side: `PanelContour`
    /// curves inward from the top edge, so widths here describe the body and the window is one
    /// shoulder wider per side (sizing it to the body bit into the notch). Radii are shares of
    /// ``DisplayOption/panelBandHeight`` because the cut-out shrinks in points with scaling
    /// (`220 × 38` to `127 × 22`).
    static func surfaceShoulderRadius(panelHeight: CGFloat) -> CGFloat {
        max(0, panelHeight) * notchUpperRadiusRatio
    }

    /// The lower corners: the only part of the shape checkable against the hardware.
    static func surfaceBottomCornerRadius(panelHeight: CGFloat) -> CGFloat {
        max(0, panelHeight) * notchLowerRadiusRatio
    }

    static func size(
        geometry: DisplayGeometry,
        isExpanded: Bool,
        statusReadoutText: String,
        trailing: CompactTrailingReading,
        centerOcclusionWidth: CGFloat,
        compactHeight: CGFloat,
        status: MonitorStatus = .connected,
        matrixCount: Int = 1,
        // Billed for the numerals, not per product: one mark stands for every product.
        sessionCount: Int = 0,
        // False only when resting with nothing connected, or with wings given up while nothing waits
        // on a person (`MonitorStore.drawsCompactMarks`).
        drawsMark: Bool = true,
        expandsToPillOnly: Bool = false,
        // `MonitorStore.tucksCompactPill`; read only on a display without a notch.
        tucksPill: Bool = false,
        expandedContentHeight: CGFloat = expandedContentHeight
    ) -> CGSize {
        guard !isExpanded else {
            guard !expandsToPillOnly else {
                return CGSize(
                    width: restingExpandedWidth(
                        geometry: geometry,
                        centerOcclusionWidth: centerOcclusionWidth,
                        compactHeight: compactHeight
                    ),
                    height: compactHeight
                )
            }
            return CGSize(
                width: expandedWidth(centerOcclusionWidth: centerOcclusionWidth),
                height: compactHeight + expandedContentHeight
            )
        }

        switch geometry {
        case .notched:
            guard centerOcclusionWidth >= 1 else {
                // No measurable cut-out: lay out as an emulated notch.
                return CGSize(
                    width: fixedCompactWidth(for: status),
                    height: compactHeight
                )
            }
            // The cut-out plus a wing each side, each exactly as wide as its contents; nothing reserved.
            let width = notchedLeadingWidth(
                drawsMark: drawsMark,
                sessionCount: sessionCount
            )
                + centerOcclusionWidth
                + compactTrailingWingWidth(trailing: trailing)
            return CGSize(width: ceil(width), height: compactHeight)
        case .noNotch:
            // Tucked, the pill keeps its width and place and gives up all but a lip of its height.
            return CGSize(
                width: fixedCompactWidth(for: status),
                height: tucksPill ? min(tuckedPillHeight, compactHeight) : compactHeight
            )
        }
    }

    /// The collapsed reading's width, ground included, used by both forms and the first-run pin.
    /// Ceiled because `NotchTextRaster.textSize` rounds the glyph box up; a bare metric clips the
    /// last digit.
    static func drawnCompactReadingWidth(_ text: String) -> CGFloat {
        ceil(textWidth(text, font: timerFont)) + readingGroundWidthCost
    }

    /// Expanded header only; the collapsed forms draw one mark for every product.
    static let compactMatrixSpacing: CGFloat = 6

    /// The notch-less pill: `230` in every connected state. Centred and pinned to nothing, so its
    /// ends are anchored (leading group `33.8`, reading `12` from the trailing edge) and the middle
    /// gives way (``pillMiddleWidth(trailing:)``); only how much of a name fits changes
    /// (`compact-view-v2.md` §6.1). `Disconnected` is sized to itself: no clearance applies.
    static func fixedCompactWidth(for status: MonitorStatus) -> CGFloat {
        status == .disconnected ? disconnectedPillWidth : pillBodyWidth
    }

    /// Stated, not composed: the sum is the contract and the middle absorbs the rest.
    static let pillBodyWidth: CGFloat = 230

    /// What stays on screen of a tucked pill (``MonitorStore/tucksCompactPill``): enough to see
    /// and to hover, since a pointer thrown at the top edge stops inside it, and too little to
    /// cover a menu title. Whole points, so the window height is exact.
    static let tuckedPillHeight: CGFloat = 4

    /// `41` — the mark, and a margin either side of it.
    static var disconnectedPillWidth: CGFloat {
        ceil(expandedHorizontalPadding + statusMatrixSize + expandedHorizontalPadding)
    }

    /// Whatever ``pillBodyWidth`` leaves after the anchored ends and clearances, so a reading
    /// gaining a digit narrows the name by exactly that digit.
    static func pillMiddleWidth(trailing: CompactTrailingReading) -> CGFloat {
        max(
            0,
            pillBodyWidth
                - expandedHorizontalPadding
                - reservedLeadingGroupWidth
                - expandedNotchClearance
                - expandedNotchClearance
                - drawnTrailingReadingWidth(trailing)
                - expandedHorizontalPadding
        )
    }



    /// Statuses either surface draws while connected (pill short name, header long name).
    /// `Disconnected` is excluded: that form is the resting pill (``MonitorStore/expandsToPillOnly``).
    static let workingStatuses = MonitorStatus.collapsedReachable
        .subtracting([.disconnected])

    static func expandedHeight(compactHeight: CGFloat) -> CGFloat {
        compactHeight + expandedContentHeight
    }

    /// What the live list asks for before its viewport caps it. With nothing live it draws its own
    /// `48` empty line; the Recent queue is a separate section, not a fallback.
    static func sessionListContentHeight(
        liveRowCount: Int,
        openRowHeight: CGFloat? = nil,
        groupHeaderCount: Int = 0
    ) -> CGFloat {
        // An open row is added as a difference so opening cannot change the row count.
        let opened = liveRowCount > 0 && openRowHeight != nil
            ? (openRowHeight ?? sessionRowHeight) - sessionRowHeight
            : 0
        // Headers are counted here and in the cap, so they never cost rows on screen.
        return liveRowCount > 0
            ? sessionRowHeight * CGFloat(liveRowCount)
                + opened
                + groupHeadingsHeight(count: max(groupHeaderCount, 0))
            : thinExpandedBodyHeight
    }

    /// That content, capped at what the live viewport draws: at least one
    /// row's worth (the apology, with nothing live), normally at most four.
    /// A taller open question enlarges it enough to keep its footer visible.
    static func sessionViewportHeight(
        liveRowCount: Int,
        openRowHeight: CGFloat? = nil,
        groupHeaderCount: Int = 0
    ) -> CGFloat {
        let content = sessionListContentHeight(
            liveRowCount: liveRowCount,
            openRowHeight: openRowHeight,
            groupHeaderCount: groupHeaderCount
        )
        let cap: CGFloat
        if groupHeaderCount > 0 {
            // Grouped, the cap is a trail, four rows and a trail (`expanded-panel-v2.md` §4.6). An open
            // row un-pins both trails and the viewport grows to fit it under its heading.
            cap = max(
                groupedSessionViewportCap,
                (openRowHeight ?? 0) + leadingProductGroupHeaderHeight
            )
        } else {
            cap = max(sessionViewportCap, openRowHeight ?? 0)
        }
        return min(content, cap)
    }

    /// Nothing with no retired rows; a seam is drawn only with something behind it.
    static func recentContentHeight(retiredRowCount: Int) -> CGFloat {
        retiredRowHeight * CGFloat(max(retiredRowCount, 0))
    }

    /// Past five retired rows the queue scrolls rather than growing the panel.
    static func recentViewportHeight(retiredRowCount: Int) -> CGFloat {
        min(recentContentHeight(retiredRowCount: retiredRowCount), recentViewportCap)
    }

    /// The Recent section as a whole: nothing while the queue is empty, its
    /// seam alone while folded, the seam and its own capped viewport while
    /// open.
    static func recentSectionHeight(
        retiredRowCount: Int,
        isRecentExpanded: Bool
    ) -> CGFloat {
        guard retiredRowCount > 0 else { return 0 }
        return recentSeamHeight
            + (isRecentExpanded ? recentViewportHeight(retiredRowCount: retiredRowCount) : 0)
    }

    // MARK: - The open row

    /// An approval's or a plan's body: what the viewport leaves after the row's fixed parts
    /// (`196`), a subtraction per `answer-in-notch.md` §4.1, so the tallest approval is exactly
    /// the viewport and opening one does not resize the panel. Questions with options use
    /// ``questionBodyMaximumHeight`` and grow the viewport, deliberately (§4.1).
    static var requestBodyMaximumHeight: CGFloat {
        sessionViewportCap - openRowFixedHeight
    }
    static let questionBodyMaximumHeight: CGFloat = 300
    static let optionTitleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let optionDescriptionFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let optionTitleLineHeight: CGFloat = 19
    static let optionDescriptionLineHeight: CGFloat = 18
    static let optionInset: CGFloat = 10
    static let optionHandleWidth: CGFloat = 25
    static let optionSpacing: CGFloat = 6
    static let optionDisclosureHeight: CGFloat = 22

    /// The answers' row. ``waitingMarkHeight`` reads this: the mark is the same control in its
    /// collapsed position, so it travels down the row without resizing (`answer-in-notch.md` §3.1).
    static let answerRowHeight: CGFloat = 28

    /// The field grows a line at a time and stops at four, then scrolls inside its ground
    /// (`answer-in-notch.md` §7.1). One line is ``answerRowHeight``, so an answer that fits moves
    /// nothing.
    static let answerFieldFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    /// The text system's line for ``answerFieldFont``, which is what the field draws with (`16`).
    static let answerFieldLineHeight: CGFloat = 16
    static let answerFieldMaximumLines = 4
    /// `6 + 16 + 6` is the `28` row, and puts the typed baseline on the controls' baseline. The
    /// vertical half stays still while the lines between it scroll.
    static let answerFieldTextInset = NSSize(width: 8, height: 6)
    /// The rail's trailing gap inside the ground, within the text's own `8` pt inset.
    static let answerFieldRailInset: CGFloat = 3

    static func answerFieldHeight(lines: Int) -> CGFloat {
        let drawn = min(max(lines, 1), answerFieldMaximumLines)
        return answerFieldTextInset.height * 2 + CGFloat(drawn) * answerFieldLineHeight
    }

    /// Where the field's text wraps: the row at the body's wrapping width (``requestBodyWidth``),
    /// less every control beside it and the `8` before each, less the field's own inset. Fixed
    /// rather than tracking the view, so the height measured here is the height drawn whether or
    /// not the list's rail is showing.
    static func answerFieldTextWidth(besideControls words: [String]) -> CGFloat {
        let controls = words.reduce(0) { $0 + drawnAnswerControlWidth($1) + 8 }
        return max(requestBodyWidth - controls - answerFieldTextInset.width * 2, 1)
    }

    /// Lines the field draws for `text`, at most ``answerFieldMaximumLines``. Laid out by the same
    /// TextKit 1 stack as ``AnswerFieldView``, in a container only that tall: `0.1` ms for 200
    /// characters, `3.1` ms for 10,000 (`system-architecture.md` §6).
    static func answerFieldLineCount(_ text: String, width: CGFloat) -> Int {
        guard !text.isEmpty else { return 1 }
        let storage = NSTextStorage(string: text, attributes: [.font: answerFieldFont])
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(
            size: NSSize(
                width: width,
                height: answerFieldLineHeight * CGFloat(answerFieldMaximumLines)
            )
        )
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let lines = Int((layout.usedRect(for: container).height / answerFieldLineHeight).rounded(.up))
        return min(max(lines, 1), answerFieldMaximumLines)
    }

    /// Corner and padding shared by the waiting mark and the answers, which are one object moving.
    /// Height, corner, padding and weight are one set; only the mark's width differs
    /// (``waitingMarkWidth``), for a straight column down a mixed queue.
    static let controlCornerRadius: CGFloat = 4
    static let controlHorizontalPadding: CGFloat = 12

    /// Everything an open row is besides its body: `8.5 + 16 + 2 + 17 + 2` above and
    /// `10 + 28 + 8.5` below. The `8.5`s read ``sessionRowVerticalPadding`` so opening a row does
    /// not move its caption and title.
    static let requestNavigationHeight: CGFloat = 24
    static let openRowFixedHeight: CGFloat = sessionRowVerticalPadding
        + sessionRowCaptionHeight
        + sessionRowLineSpacing + sessionRowTitleHeight + sessionRowLineSpacing
        + 10 + answerRowHeight + sessionRowVerticalPadding

    /// The width an open row's body wraps at: `610 − 2 × 12`, less ``scrollRailLane``
    /// unconditionally. An open row is what makes the list scroll, so wrapping at the narrower
    /// width avoids a height that depends on a width that depends on that height.
    static var requestBodyWidth: CGFloat {
        expandedBaselineWidth - expandedHorizontalPadding * 2 - scrollRailLane
    }

    /// §4.2's prose setting: sentences a person is meant to read.
    static let argumentLabelFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let argumentLabelHeight: CGFloat = 15
    static let argumentLabelSpacing: CGFloat = 4
    static let argumentSpacing: CGFloat = 12
    static let argumentBodyInset: CGFloat = 8
    static let proseFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    /// And its machine text: strings a machine will execute.
    static let machineTextFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let machineTextHorizontalInset: CGFloat = 10
    static let machineTextVerticalInset: CGFloat = 8
    static let machineTextCornerRadius: CGFloat = 4
    /// `12`, ``argumentSpacing``, so the question is not closer to the first option than the
    /// options are to each other (`answer-in-notch.md` §5.1).
    static let optionListSpacing: CGFloat = 12

    /// `17` for prose, `18` for machine text (SF Mono's `12/18`).
    static func requestLineHeight(for setting: AgentRequest.Setting) -> CGFloat {
        switch setting {
        case .prose: sessionRowTitleHeight
        case .machineText: 18
        }
    }

    /// Capped by the viewport (§4.1), not by a line count; every height in §12 is this arithmetic.
    static func openRowHeight(bodyHeight: CGFloat) -> CGFloat {
        openRowFixedHeight + min(max(bodyHeight, 0), requestBodyMaximumHeight)
    }

    /// The live viewport, the Recent section and the footer stacked; each answers only to its own
    /// cap, with no ceiling over the sum.
    static func expandedContentHeight(
        liveRowCount: Int,
        openRowHeight: CGFloat? = nil,
        retiredRowCount: Int = 0,
        isRecentExpanded: Bool = false,
        footerHeight: CGFloat = restingFooterHeight,
        groupHeaderCount: Int = 0
    ) -> CGFloat {
        sessionViewportHeight(
            liveRowCount: liveRowCount,
            openRowHeight: openRowHeight,
            groupHeaderCount: groupHeaderCount
        )
            + recentSectionHeight(
                retiredRowCount: retiredRowCount,
                isRecentExpanded: isRecentExpanded
            )
            + footerHeight
    }

    /// The expanded panel's width: `610` at every cut-out a Mac has, and nothing else feeds it —
    /// the band draws no status word (`expanded-header-v2.md` §3) and no per-agent columns
    /// (`colour-v2.md` §3). Sides are doubled because the panel is centred while expanded
    /// (``MonitorStore/currentPanelTrailingAnchor`` is nil). `expandedNotchClearance` guards that
    /// the band clears the hardware, binding only past a `502.4` cut-out.
    static func expandedWidth(centerOcclusionWidth: CGFloat) -> CGFloat {
        guard centerOcclusionWidth >= 1 else {
            return expandedBaselineWidth
        }
        let notchSafeWidth = centerOcclusionWidth + expandedLeadingSideWidth * 2

        return ceil(max(expandedBaselineWidth, notchSafeWidth))
    }


    static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

struct ConnectionStabilityGate {
    let gracePeriod: TimeInterval
    private var disconnectedSince: Date?

    init(gracePeriod: TimeInterval = MonitorTiming.standard.disconnectGracePeriod) {
        self.gracePeriod = gracePeriod
    }

    mutating func shouldPublish(
        candidate: MonitorAvailability,
        current: MonitorAvailability,
        observedAt: Date
    ) -> Bool {
        guard candidate == .disconnected, current != .disconnected else {
            disconnectedSince = nil
            return true
        }

        // Connecting has no trusted snapshot to preserve. Once the startup
        // attempt confirms that App Server is unresponsive, publish that fact
        // immediately; the grace period only protects an established state.
        guard current != .connecting else {
            disconnectedSince = nil
            return true
        }

        guard let disconnectedSince else {
            self.disconnectedSince = observedAt
            return false
        }

        guard observedAt.timeIntervalSince(disconnectedSince) >= gracePeriod else {
            return false
        }
        // Cleared as it publishes, or ``nextPublishDeadline`` reports a past instant and spends a
        // wake-up.
        self.disconnectedSince = nil
        return true
    }

    /// When a suppressed disconnect becomes publishable, so the store wakes for it; otherwise a
    /// disconnect waits for an unrelated wake-up or the 60s heartbeat instead of the 3s budget.
    /// The refresh at this instant always clears `disconnectedSince`.
    var nextPublishDeadline: Date? {
        disconnectedSince?.addingTimeInterval(gracePeriod)
    }
}

@MainActor
final class MonitorStore: ObservableObject {
    static let shared = makeShared()

    /// The store the product runs on, or an empty one when hosting tests: `xcodebuild test`
    /// launches this app beside the running copy (see ``AppProcess``). The services are
    /// `static let`s, so this branch binds no socket and reads no user file. No test uses it.
    private static func makeShared() -> MonitorStore {
        guard !AppProcess.isHostingTests else {
            return MonitorStore(
                services: [],
                initialSnapshot: .connecting,
                preferences: .standard
            )
        }
        // An unregistered product reports setupRequired, which loses to any ready product or any
        // product with a row, so running one product looks like running it alone.
        let modules = ProductRegistry.builtIn.map { descriptor in
            (kind: descriptor.kind, module: descriptor.make())
        }
        return MonitorStore(
            services: modules.map(\.module.service),
            navigator: AgentNavigationRouter(
                Dictionary(uniqueKeysWithValues: modules.map { ($0.kind, $0.module.navigator) })
            ),
            initialSnapshot: .connecting,
            preferences: .standard,
            // Every provider's refresh edges on one stream, so a late answer from any wakes the loop.
            refreshEvents: DirectoryChangeWatcher.merged(
                modules.map(\.module.service.stateChangeEvents)
            )
        )
    }

    @Published private(set) var displays: [DisplayOption]
    @Published private(set) var selectedDisplayID: String
    @Published private(set) var status: MonitorStatus
    /// The products open and reachable, in display order. Published because a second product
    /// connecting may not change the status, and the pill's width depends on it.
    @Published private(set) var connectedAgents: [AgentKind] = []
    /// What the collapsed surface draws, left to right; never empty. Published because a mark can
    /// change without the aggregate status changing.
    @Published private(set) var presenceMarks: [PresenceMark] = [
        PresenceMark(agent: nil, status: .disconnected)
    ]
    /// What each product's monitoring leaves on disk, shown in Settings, never acted on. A key
    /// is absent only for ``AgentDiskFootprintReport/leavesNothing``, so a pending measurement
    /// keeps its row from flickering (CC-020).
    @Published private(set) var diskFootprints: [AgentKind: AgentDiskFootprintReport] = [:]
    @Published private(set) var availability: MonitorAvailability
    @Published private(set) var quota: QuotaSnapshot
    @Published private(set) var sessions: [MonitoredSession] {
        didSet { updateElapsedTicking() }
    }
    /// Advances once a second while a turn is timed; see `updateElapsedTicking`. Not `@Published`:
    /// a store publish re-evaluates the whole overlay (~20ms, ~4% of a core per second); readouts
    /// subscribe and redraw their own layer.
    let elapsedTick: CurrentValueSubject<Date, Never>

    /// Bumped only when a readout's reserved width changes (tabular figures: a minute or hour
    /// boundary), which is all SwiftUI has to re-measure for.
    @Published private(set) var elapsedLayoutRevision = 0
    private var elapsedLayoutSignature: [Int] = []

    var timerNow: Date { elapsedTick.value }
    /// Written only on change: a publish re-evaluates the whole overlay (`AGENTS.md` §7), and a
    /// refresh re-states the status every second.
    @Published private(set) var setupStatusByAgent: [AgentKind: IntegrationSetupStatus] = [:]
    /// Held apart from ``setupStatusByAgent``: while a convergence is in flight the switch shows
    /// what the user chose and the status what the file says.
    @Published private(set) var integrationSwitchIsOnByAgent: [AgentKind: Bool] = [:]
    @Published private(set) var integrationBusyAgents: Set<AgentKind> = []
    @Published var isExpanded = false {
        didSet {
            // Opening the panel reads the queue; eviction is a read-time filter, not a timer (§2.4 rule
            // 11).
            guard isExpanded != oldValue else { return }
            // A peek cannot outlive the panel: its release may land after the panel closed.
            if !isExpanded { isPeeking = false }
            if isExpanded { refreshRecentDepartures(at: clock.now()) }
            updateRecentTicking()
        }
    }
    /// Whether the Recent queue is opened; the design's `recentFolded` (`expanded-panel-v2.md`
    /// §2.4 rule 07), inverted. Remembered; folding never closes the panel, since the footer keeps
    /// the bottom edge from passing a still pointer.
    @Published var isRecentExpanded: Bool {
        didSet {
            preferences?.set(
                isRecentExpanded,
                forKey: Self.recentExpandedDefaultsKey
            )
            guard isRecentExpanded != oldValue else { return }
            // The fold changes which instants matter (``nextRecentReadingChange(at:)``), so cancel the
            // parked wake-up; the refresh re-plans it and reads the ages, which are stale while hidden.
            recentTickTask?.cancel()
            recentTickTask = nil
            refreshRecentDepartures(at: clock.now())
        }
    }
    /// The queue now, most recently departed first: ``departuresByThread`` past ``recentWindow``.
    /// Stored and republished, because a computed clock read would go stale on screen.
    @Published private(set) var recentDepartures: [RecentDeparture] = []
    /// The instant the queue's ages are drawn against. Not ``timerNow``, which freezes when no
    /// Turn is timed. Published only when a reading would move: a publish re-evaluates the whole
    /// overlay (`AGENTS.md` §7).
    @Published private(set) var recentReadAt: Date
    /// Whether the quota table is opened; closed by default (`quota-footer-v2.md` §8.1). One state
    /// for the whole footer, remembered across openings.
    @Published var isQuotaExpanded: Bool {
        didSet {
            preferences?.set(isQuotaExpanded, forKey: Self.quotaExpandedDefaultsKey)
        }
    }
    /// Products left out of the quota table. Stores what is excluded, so a product added in a
    /// later build appears. Table only: today's total always counts every connected product
    /// (`quota-footer-v2.md` §13); with all excluded the control goes (``showsQuotaFoldControl``).
    /// Empty on a fresh install; unknown raw values are dropped on read.
    @Published var productsHiddenFromQuotaTable: Set<AgentKind> {
        didSet {
            guard productsHiddenFromQuotaTable != oldValue else { return }
            preferences?.set(
                productsHiddenFromQuotaTable.sorted().map(\.rawValue),
                forKey: Self.quotaHiddenProductsDefaultsKey
            )
        }
    }
    /// Whether the open panel shows About. Survives collapse (hover closes the panel, so only the
    /// mark closes it), but is not persisted across launches.
    @Published private(set) var isShowingAbout = false
    /// Whether every word is covered (`cover-the-words.md`); `Privacy Mode` in Settings. About
    /// what is drawn on screen, not where text is stored — never cite it against storage or
    /// transport decisions (`PRD.md` §7). Covers names, titles and lines; the mark, counts,
    /// clock, badges and footer stay. Also stops hover-expansion (``pointerEnteredPanel()``):
    /// the leak is a `0.15` s dwell. Remembered; off on a fresh install.
    @Published var privacyMode: Bool {
        didSet {
            guard privacyMode != oldValue else { return }
            preferences?.set(privacyMode, forKey: Self.privacyModeDefaultsKey)
            if !privacyMode { isPeeking = false }
            // `.onHover` only speaks when the pointer moves, and the entry was declined while the mode was
            // on, so offer it again through the ordinary dwell.
            guard !privacyMode, isPointerOnPanel, !isExpanded else { return }
            pointerEnteredPanel()
        }
    }
    /// Whether the covers are lifted while a control is held down (`cover-the-words.md` §7). A
    /// momentary state, cleared by the panel closing and the mode ending, so it cannot be left on.
    @Published private(set) var isPeeking = false
    /// Not `@Published`: nothing draws it. It lets a preference change under a still pointer ask
    /// what the tracking area cannot (`AGENTS.md` §7).
    private(set) var isPointerOnPanel = false
    /// `Hide Notchline`: while nothing waits on a person, a notched display gives up its wings
    /// (``givesUpCompactWings``) and a notch-less one tucks the pill into the top edge
    /// (``tucksCompactPill``).
    ///
    /// Collapsed only: hover still opens the panel, the only entrance (`PRD.md` §11).
    /// Remembered even while the selected display cannot honour it; see ``canHideNotchline``.
    /// Stored under its old name, `hidesCompactWings`, so the answer survives the rename.
    @Published var hidesNotchline: Bool {
        didSet {
            preferences?.set(
                hidesNotchline,
                forKey: Self.hidesNotchlineDefaultsKey
            )
        }
    }
    /// Whether the surface draws a hairline around its own edge, so the black panel has a
    /// shape against a dark wallpaper.
    ///
    /// The colour is ``NotchPalette/surfaceEdge``, below every mark that carries state. The
    /// top line is not drawn: that edge belongs to the screen. Collapsed and expanded alike,
    /// except the wingless form with no mark out; see ``showsSurfaceOutline``. Off by default.
    @Published var drawsSurfaceOutline: Bool {
        didSet {
            preferences?.set(
                drawsSurfaceOutline,
                forKey: Self.drawsSurfaceOutlineDefaultsKey
            )
        }
    }
    /// Whether the notch-less pill names the work between its two ends. Default on.
    ///
    /// Notch-less only: the notched bar would need `102` pt of black beside the hardware
    /// (`compact-view-v2.md` §5.2). Off, the pill holds its `250` so its anchored ends do not
    /// move.
    @Published var namesWorkOnPill: Bool {
        didSet {
            preferences?.set(
                namesWorkOnPill,
                forKey: Self.namesWorkOnPillDefaultsKey
            )
        }
    }
    /// Whether the live list is one block per product (`expanded-panel-v2.md` §4) or one list
    /// with a chip per row. The Recent queue is never grouped (§4.1). Defaults on.
    @Published var groupsSessionsByProduct: Bool {
        didSet {
            preferences?.set(
                groupsSessionsByProduct,
                forKey: Self.groupsSessionsByProductDefaultsKey
            )
        }
    }
    @Published private(set) var lastIntegrationMessage: String
    @Published private(set) var hasCompletedOnboarding: Bool

    private static let quotaExpandedDefaultsKey = "quotaExpanded"
    private static let quotaHiddenProductsDefaultsKey = "quotaHiddenProducts"
    private static let recentExpandedDefaultsKey = "recentExpanded"
    private static let privacyModeDefaultsKey = "privacyMode"
    private static let hidesNotchlineDefaultsKey = "hidesCompactWings"
    private static let drawsSurfaceOutlineDefaultsKey = "drawsSurfaceOutline"
    private static let namesWorkOnPillDefaultsKey = "namesWorkOnPill"
    private static let groupsSessionsByProductDefaultsKey = "groupsSessionsByProduct"
    private static let onboardingDefaultsKey = "hasCompletedOnboarding"
    private static let selectedDisplayDefaultsKey = "selectedDisplayID"
    private let services: [any AgentMonitoring]
    /// Whether this store is watching anything. A test-hosting process builds the shared store
    /// with no services, which keeps a test run off the user's hook sockets and notch.
    var isWatching: Bool { !services.isEmpty }
    private let navigator: (any AgentNavigating)?
    private func integrationService(for agent: AgentKind) -> (any AgentMonitoring)? {
        services.first { $0.agent == agent }
    }
    /// The optional contracts (``ProductContracts.swift``); `nil` means the product does not
    /// implement that one.
    private func configurer(for agent: AgentKind) -> (any IntegrationConfiguring)? {
        integrationService(for: agent) as? any IntegrationConfiguring
    }
    private func answerer(for agent: AgentKind) -> (any AnswerDelivering)? {
        integrationService(for: agent) as? any AnswerDelivering
    }
    private func footprintReporter(for agent: AgentKind) -> (any DiskFootprintReporting)? {
        integrationService(for: agent) as? any DiskFootprintReporting
    }
    /// `nil` in tests, which keeps them off the user's real defaults.
    private let preferences: UserDefaults?
    private let clock: any MonitorClock
    private let timing: MonitorTiming
    private var preferredDisplayID: String?
    private var pendingHoverTask: Task<Void, Never>?
    /// Re-armed at the end of every refresh run. See ``scheduleNextWake()``.
    private var wakeTask: Task<Void, Never>?
    private var refreshEventTask: Task<Void, Never>?
    private var elapsedTickTask: Task<Void, Never>?
    private var recentTickTask: Task<Void, Never>?
    private let refreshEvents: AsyncStream<Void>?
    private var refreshGate = SingleFlightGate()
    private var refreshTask: Task<Void, Never>?
    private var desiredIntegrationEnabled: [AgentKind: Bool] = [:]
    /// One per product, so a slow write on one side cannot hold the other side's switch.
    @Published private var connectionReadings: [AgentKind: AgentSnapshot] = [:]
    @Published private(set) var productOperationFailures: [AgentKind: ProductOperationFailure] = [:]
    private var integrationIntentRevisions: [AgentKind: Int] = [:]
    private var monitoringIntents: [AgentKind: ProductMonitoringIntent] = [:]
    private var integrationTasks: [AgentKind: Task<Void, Never>] = [:]
    private var isNavigationInFlight = false
    /// How long a row stays reachable after it leaves the list. A constant, not a setting
    /// (§2.4 rule 01); it also keeps the age to two characters (§2.3).
    static let recentWindow: TimeInterval = 5 * 60 * 60
    /// A size bound behind the five-hour window, never the visible rule (§8.5 question 08).
    static let recentCeiling = 50
    /// Every row that has left the list, keyed by Thread (see ``RecentDeparture/key(for:)``).
    private var departuresByThread: [String: RecentDeparture] = [:]
    /// The Turns the user has taken off the list, per product: a dismissal may only be dropped
    /// on evidence from the product it came from.
    private var dismissedSessionIDsByAgent: [AgentKind: Set<String>] = [:]
    /// The latest answer from each product, so the merge can be recomputed. One product
    /// answering must never discard what another already said.
    private var latestByAgent: [AgentKind: AgentSnapshot] = [:]
    /// One gate per product. Sharing one made a Codex blip suppress a Claude Code publish.
    private var stabilityGates: [AgentKind: ConnectionStabilityGate] = [:]
    private var diskFootprintTask: Task<Void, Never>?
    /// Deadlines a provider reported and failed to clear, kept out of the shared `min` so they
    /// cannot drag every other provider down to the refresh floor.
    private var stuckDeadlines: [AgentKind: Date] = [:]

    init(
        displays: [DisplayOption]? = nil,
        services: [any AgentMonitoring] = [],
        navigator: (any AgentNavigating)? = nil,
        initialSnapshot: AgentSnapshot? = nil,
        /// Every product's opening answer, for a drawing with no services (``NotchSpecimen``).
        initialSnapshots: [AgentSnapshot]? = nil,
        preferences: UserDefaults? = nil,
        refreshEvents: AsyncStream<Void>? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard
    ) {
        let resolvedDisplays = displays ?? DisplayOption.currentDisplays()
        let snapshots = initialSnapshots ?? [initialSnapshot ?? Self.previewSnapshot]
        let persistedDisplayID = preferences?.string(
            forKey: Self.selectedDisplayDefaultsKey
        )
        let initialDisplayID = persistedDisplayID.flatMap { persistedID in
            resolvedDisplays.first { $0.id == persistedID }?.id
        } ?? resolvedDisplays.first?.id ?? ""
        self.displays = resolvedDisplays
        self.selectedDisplayID = initialDisplayID
        self.preferences = preferences
        self.clock = clock
        self.elapsedTick = CurrentValueSubject(clock.now())
        self.recentReadAt = clock.now()
        self.timing = timing
        self.stuckDeadlines = [:]
        self.preferredDisplayID = persistedDisplayID
            ?? (initialDisplayID.isEmpty ? nil : initialDisplayID)
        self.services = services
        self.navigator = navigator
        self.refreshEvents = refreshEvents
        self.latestByAgent = Dictionary(
            snapshots.map { ($0.agent, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let merged = AgentSnapshotMerge.merge(snapshots)
        self.availability = merged.availability
        self.quota = merged.quota
        self.sessions = merged.sessions
        self.status = merged.status
        self.connectedAgents = merged.connectedAgents
        self.presenceMarks = merged.presenceMarks
        // Through the injected store, not `.standard`, so a test does not inherit the developer's
        // defaults. `object(forKey:)` tells a never-opened install from one that opened and shut it.
        self.isQuotaExpanded = preferences?.object(
            forKey: Self.quotaExpandedDefaultsKey
        ) as? Bool ?? false
        self.productsHiddenFromQuotaTable = Set(
            (preferences?.stringArray(
                forKey: Self.quotaHiddenProductsDefaultsKey
            ) ?? []).compactMap(AgentKind.init(rawValue:))
        )
        // `object(forKey:)`: defaults to folded; `bool` cannot tell never-opened from shut.
        self.isRecentExpanded = preferences?.object(
            forKey: Self.recentExpandedDefaultsKey
        ) as? Bool ?? false
        self.privacyMode = preferences?.bool(
            forKey: Self.privacyModeDefaultsKey
        ) ?? false
        self.hidesNotchline = preferences?.bool(
            forKey: Self.hidesNotchlineDefaultsKey
        ) ?? false
        self.drawsSurfaceOutline = preferences?.bool(
            forKey: Self.drawsSurfaceOutlineDefaultsKey
        ) ?? false
        // `object(forKey:)`: defaults to on; `bool` cannot tell never-seen from turned off.
        self.namesWorkOnPill = preferences?.object(
            forKey: Self.namesWorkOnPillDefaultsKey
        ) as? Bool ?? true
        self.groupsSessionsByProduct = preferences?.object(
            forKey: Self.groupsSessionsByProductDefaultsKey
        ) as? Bool ?? true
        self.hasCompletedOnboarding = preferences?.bool(
            forKey: Self.onboardingDefaultsKey
        ) ?? false
        self.lastIntegrationMessage = snapshots.first?.diagnostic
            ?? "Waiting for the first refresh"

        for agent in AgentKind.allCases {
            if let raw = preferences?.string(forKey: "productMonitoringIntent." + agent.rawValue),
               let intent = ProductMonitoringIntent(rawValue: raw) {
                monitoringIntents[agent] = intent
                integrationSwitchIsOnByAgent[agent] = intent == .enabled
            }
        }
        if !services.isEmpty {
            startMonitoring()
        }
        updateElapsedTicking()
    }

    deinit {
        wakeTask?.cancel()
        refreshEventTask?.cancel()
        pendingHoverTask?.cancel()
        elapsedTickTask?.cancel()
        recentTickTask?.cancel()
        refreshTask?.cancel()
        for task in integrationTasks.values {
            task.cancel()
        }
        diskFootprintTask?.cancel()
    }

    /// Advances the elapsed readout once a second while a turn is being timed.
    ///
    /// Ticks go out on ``elapsedTick``, which no SwiftUI view observes; only a change in the
    /// readouts' reserved width bumps ``elapsedLayoutRevision``.
    private func updateElapsedTicking() {
        guard longestRunningSessionStart != nil else {
            elapsedTickTask?.cancel()
            elapsedTickTask = nil
            return
        }
        guard elapsedTickTask == nil else { return }

        // The tick is older than the new turn; left stale, its first second reads as negative
        // ("not timed") and the row renders blank until the first tick.
        publishTick(clock.now())

        elapsedTickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard let start = self.longestRunningSessionStart else {
                    // `sessions` has cancelled this task; clearing the handle lets a later turn start one.
                    self.elapsedTickTask = nil
                    return
                }
                try? await self.clock.sleep(
                    seconds: Self.secondsUntilNextTick(
                        after: start,
                        now: self.clock.now()
                    )
                )
                guard !Task.isCancelled else { return }
                self.publishTick(self.clock.now())
            }
        }
    }

    /// Sends a tick, and asks SwiftUI to re-measure only if a readout changed width.
    ///
    /// The formatter uses tabular figures, so character count is width. Badge counts and flips
    /// go in directly: either can change what must be drawn without a digit-count change.
    private func publishTick(_ now: Date) {
        elapsedTick.send(now)

        var signature = [aggregateSessionCount, aggregateSubagentCount]
        signature.append(compactTimerText?.count ?? -1)
        signature.append(buriesAFinishedTurn ? 1 : 0)
        signature.append(contentsOf: sessions.map { elapsedText(for: $0)?.count ?? -1 })
        guard signature != elapsedLayoutSignature else { return }
        elapsedLayoutSignature = signature
        elapsedLayoutRevision &+= 1
    }

    /// Time until the timed turn's next whole second. A flat one-second sleep drifts and
    /// eventually skips a digit.
    nonisolated private static func secondsUntilNextTick(
        after start: Date,
        now: Date
    ) -> TimeInterval {
        let elapsed = now.timeIntervalSince(start)
        guard elapsed.isFinite else { return 1 }
        return 1 - (elapsed - elapsed.rounded(.down))
    }

    var selectedDisplay: DisplayOption? {
        displays.first { $0.id == selectedDisplayID } ?? displays.first
    }

    /// The chosen display as an `NSScreen`, matched by identifier (frames swap when displays
    /// are rearranged). `nil` only until ``refreshDisplays()`` catches up with a removed display.
    var selectedScreen: NSScreen? {
        guard let id = selectedDisplay?.id else { return nil }
        return NSScreen.screens.first { DisplayOption.identifier(for: $0) == id }
    }

    var geometry: DisplayGeometry {
        selectedDisplay?.geometry ?? .noNotch
    }

    /// The collapsed panel's height on the selected display, which both corner radii and the
    /// wingless step are shares of. See ``DisplayOption/panelBandHeight``.
    var compactHeight: CGFloat {
        selectedDisplay?.panelBandHeight ?? PanelMetrics.referenceCompactHeight
    }


    /// Whether this surface draws the name of the work: the notch-less pill, collapsed and not
    /// tucked, with something to name.
    ///
    /// ``privacyMode`` silences it rather than drawing a cover bar, so both collapsed forms
    /// behave alike; it does not write ``namesWorkOnPill``. The width never changes.
    var drawsCompactMiddle: Bool {
        namesWorkOnPill
            && !privacyMode
            && !isExpanded
            && geometry == .noNotch
            && !tucksCompactPill
            && !compactProjectNames.isEmpty
    }

    /// Whether this row's words are covered. An open row is uncovered, so a question can still
    /// be answered in privacy mode.
    func coversWords(of session: MonitoredSession) -> Bool {
        privacyMode && !isPeeking && openRowID != session.id
    }

    /// Whether the band keeps the peek's box, drawn or not: ``hasCoveredRows`` minus the mode.
    ///
    /// Keeping the box mounted lets its bars animate on and off rather than a layout change
    /// (as ``FoldSeamRule`` does). The box grows into slack between the counts and the trailing
    /// pair (`cover-the-words.md` §7), so it costs no width. Not on the resting pill, whose
    /// width is exactly two control boxes (``PanelMetrics/restingExpandedWidth``).
    var keepsPeekRoom: Bool {
        isExpanded
            && !isShowingAbout
            && !expandsToPillOnly
            && !(sessions.isEmpty && recentDepartures.isEmpty)
    }

    var hasCoveredRows: Bool {
        privacyMode && keepsPeekRoom
    }

    /// Lift the covers, and put them back. Separate calls because a press and a release drive
    /// them; a toggle would latch when a release went missing. ``togglePeek()`` is the keyboard's.
    func beginPeek() {
        guard privacyMode, isExpanded else { return }
        isPeeking = true
    }

    func endPeek() {
        isPeeking = false
    }

    /// VoiceOver activation, where a press cannot be held: the one latching path, ended when
    /// the panel closes.
    func togglePeek() {
        guard privacyMode, isExpanded else { return }
        isPeeking.toggle()
    }

    /// Triggered by a secondary press on the band; rows keep their own secondary click
    /// (`dismiss`, `removeFromRecent`).
    func togglePrivacyMode() {
        privacyMode.toggle()
    }

    /// Whether the selected display could honour ``namesWorkOnPill`` (it needs no cut-out).
    /// Gates the drawing, never the setting: both rows stay settable on every display.
    var canNameWorkOnPill: Bool { geometry == .noNotch }

    /// Whether the collapsed surface draws its mark, which decides whether the leading wing
    /// exists. Off on a notched bar with nothing connected, or with the wings given up and
    /// nothing waiting on a person (`compact-view-v2.md` §9), and on a tucked pill.
    var drawsCompactMarks: Bool {
        guard !isExpanded else { return true }
        guard !tucksCompactPill else { return false }
        guard geometry == .notched else { return true }
        guard !isRestingOnly else { return false }
        guard givesUpCompactWings else { return true }
        return hasATurnToAttendTo
    }

    /// Whether the selected display could honour ``hidesNotchline``.
    ///
    /// - No notch: always; the pill tucks rather than disappearing, so there is still a place
    ///   to hover.
    /// - A notch with no gap between auxiliary areas is laid out as an emulated notch
    ///   (`PanelMetrics.size`); shrinking onto it would leave a zero-width panel, and a lip
    ///   drawn where the cut-out may be could not be seen.
    ///
    /// Does not grey the switch or touch the preference.
    var canHideNotchline: Bool {
        guard geometry == .notched else { return true }
        return (selectedDisplay?.centerOcclusionWidth ?? 0) >= 1
    }

    /// Whether the preference is in effect on a notched display that can honour it. A Turn
    /// waiting on the user still brings its matrix out; ask ``drawsCompactMarks`` for what is
    /// on screen. Not scoped to hover: every reader is already collapsed-only.
    var givesUpCompactWings: Bool {
        hidesNotchline && geometry == .notched && canHideNotchline
    }

    /// Whether the notch-less pill is tucked into the display's top edge: `Hide Notchline`,
    /// collapsed, with nothing waiting on a person. Only a ``PanelMetrics/tuckedPillHeight``
    /// lip stays on screen, the whole of the hover target, so the menu bar under the pill is
    /// free. Nothing is drawn inside it, so no mark animates out of sight. A Turn to attend to
    /// brings the pill back whole, where a notched display brings its leading wing out.
    var tucksCompactPill: Bool {
        hidesNotchline
            && geometry == .noNotch
            && !isExpanded
            && !hasATurnToAttendTo
    }

    /// Approval, input, or a finished unread Turn, on any product: what brings a hidden surface
    /// back out.
    private var hasATurnToAttendTo: Bool {
        presenceMarks.contains(where: \.hasATurnToAttendTo)
    }

    /// The preference minus the wingless form drawing no mark: that body is the cut-out, and
    /// outlining it draws two grey hooks beside the notch. A wing coming out restores the
    /// outline. Scoped to collapsed here, not in ``givesUpCompactWings``. A tucked pill keeps
    /// it: its lip is there to be found.
    var showsSurfaceOutline: Bool {
        guard drawsSurfaceOutline else { return false }
        return isExpanded || !givesUpCompactWings || drawsCompactMarks
    }

    var isRestingOnly: Bool {
        presenceMarks.allSatisfy(\.isResting)
    }

    /// Hovering grows the pill sideways instead of dropping the panel: true when nothing is
    /// connected, unless the About panel is showing (``isShowingAbout``).
    var expandsToPillOnly: Bool {
        isRestingOnly && !isShowingAbout
    }

    var statusDisplayName: String {
        status.displayName
    }

    /// The turn the notch is timing: the longest-running one. Every state but `completed` is
    /// eligible, so a turn parked on an approval keeps its timer.
    var longestRunningSessionStart: Date? {
        sessions
            .filter { $0.status.keepsTiming }
            .compactMap(\.startedAt)
            .min()
    }

    var compactTimerText: String? {
        // `Hide Notchline` is answered by ``compactReadingSpan``, so the composed width and the
        // drawn figure cannot disagree about whether there is a reading.
        guard let span = compactReadingSpan else { return nil }
        return SessionElapsedFormatter.elapsed(
            since: span.start,
            now: span.end ?? Self.readableNow(timerNow, forStart: span.start)
        )
    }

    /// The two instants the collapsed reading is drawn between: a turn's start, and its end
    /// where it has one.
    ///
    /// - When the last turn ends the reading freezes on that turn's own length rather than
    ///   leaving, so the panel edge does not move (`compact-view-v2.md` §4.2). Among finished
    ///   turns it is the earliest-started, the same turn the live reading was counting.
    /// - Nil while the wings are given up, for the whole trailing slot: a zero-width frame
    ///   does not clip ``ElapsedReadout``, and gating only the string drew `12 + 4.75` pt of
    ///   timer past the cut-out. The dot still comes out (`compact-view-v2.md` §9).
    /// - Nil on a tucked pill, so no readout ticks out of sight.
    var compactReadingSpan: (start: Date, end: Date?)? {
        guard !givesUpCompactWings, !tucksCompactPill else { return nil }
        if let start = longestRunningSessionStart { return (start, nil) }
        let finished = sessions
            .filter { MonitorAggregation.effectiveStatus(of: $0) == .completed }
            .compactMap(finishedElapsed(for:))
            .min { $0.start < $1.start }
        return finished.map { ($0.start, $0.end) }
    }

    /// Whether the list holds a finished, unread turn the aggregate mark is not drawing: the
    /// dot's condition. Asked of the aggregate, because a finished Codex row under a running
    /// Claude Code row is buried for the bar and false for each product's own flag.
    var buriesAFinishedTurn: Bool {
        guard status != .completed else { return false }
        return sessions.contains {
            MonitorAggregation.effectiveStatus(of: $0) == .completed
        }
    }


    /// Every subagent still in flight across listed rows, both products; for VoiceOver's total.
    var compactRunningSubagentCount: Int {
        givesUpCompactWings ? 0 : aggregateSubagentCount
    }

    /// Everything the collapsed surface draws after the notch: subagent badges, the elapsed
    /// timer, or both. One value because the panel width is measured from it.
    var compactTrailingReading: CompactTrailingReading {
        CompactTrailingReading(
            timerText: compactTimerText,
            isFrozen: compactReadingSpan?.end != nil,
            // The reading stays hidden behind a hidden wing; the unread dot does not
            // (`compact-view-v2.md` §9).
            buriesAFinishedTurn: buriesAFinishedTurn
        )
    }

    /// The large numeral: rows on the monitored list, finished ones included
    /// (`compact-view-v2.md` §3.3). Ungated by `Hide Notchline` (§9).
    var aggregateSessionCount: Int { sessions.count }

    /// The small numeral: every subagent in flight, summed off ``presenceMarks`` so both ends
    /// of the bar agree. Ungated.
    var aggregateSubagentCount: Int {
        presenceMarks.reduce(0) { $0 + $1.subagents.count }
    }

    /// Every Project with an active row, deduplicated in ``sessions`` order: the roster the
    /// pill's middle names in turn (`compact-view-v2.md` §6.2).
    var compactProjectNames: [String] {
        var seen: Set<String> = []
        return sessions.map(\.projectName).filter { seen.insert($0).inserted }
    }

    /// The aggregate mark's ink: ``NotchPalette/themeInk`` once a product is
    /// behind it, the resting grey until then.
    var aggregateMatrixInk: NotchPalette.MatrixInk {
        NotchPalette.matrixInk(isConnected: !isRestingOnly)
    }


    var compactDrawnLeadingGroupWidth: CGFloat {
        PanelMetrics.drawnLeadingGroupWidth(sessionCount: aggregateSessionCount)
    }

    /// The trailing reading's billed width on both collapsed forms. The glyphs sit at its
    /// leading edge so the figure stands still while a digit arrives. Zero on an empty reading.
    var compactDrawnTrailingReadingWidth: CGFloat {
        PanelMetrics.drawnTrailingReadingWidth(compactTrailingReading)
    }




    /// The counts column, in words. Names no product, like the numerals; ungated by
    /// `Hide Notchline`.
    var spokenCollapsedCountsText: String? {
        guard aggregateSessionCount > 0 else { return nil }
        let sessions = aggregateSessionCount == 1
            ? "1 session"
            : "\(aggregateSessionCount) sessions"
        guard aggregateSubagentCount > 0 else { return sessions }
        let subagents = aggregateSubagentCount == 1
            ? "1 subagent"
            : "\(aggregateSubagentCount) subagents"
        return "\(sessions), \(subagents)"
    }

    /// What a breathing column says, in words (`figma-design.md` §10: no single channel).
    /// Speaks on ``PresenceMark/buriesAFinishedTurn``'s terms and adds how many.
    var spokenBuriedCompletionText: String? {
        // On the aggregate: a product's own flag cannot see its finished row buried under another
        // product's running one.
        guard buriesAFinishedTurn else { return nil }
        let count = sessions.filter { session in
            MonitorAggregation.effectiveStatus(of: session) == .completed
        }.count
        guard count > 0 else { return nil }
        return count == 1
            ? "1 turn finished and unread"
            : "\(count) turns finished and unread"
    }

    /// The instant the compact readout counts from while the figure is moving, or nil. A frozen
    /// reading is drawn from ``compactReadingSpan`` instead.
    var compactTimerStart: Date? {
        guard compactTimerText != nil else { return nil }
        return longestRunningSessionStart
    }

    /// As ``compactTimerStart``, for one row.
    func elapsedStart(for session: MonitoredSession) -> Date? {
        elapsedText(for: session) == nil ? nil : session.startedAt
    }

    /// The compact timer for VoiceOver, which cannot read `12:34` as a length.
    var spokenLongestElapsedText: String? {
        SessionElapsedFormatter.spokenElapsed(
            since: longestRunningSessionStart,
            now: Self.readableNow(timerNow, forStart: longestRunningSessionStart)
        )
    }

    func elapsedText(for session: MonitoredSession) -> String? {
        guard session.status.keepsTiming else { return nil }
        return SessionElapsedFormatter.elapsed(
            since: session.startedAt,
            now: Self.readableNow(timerNow, forStart: session.startedAt)
        )
    }

    func spokenElapsedText(for session: MonitoredSession) -> String? {
        guard session.status.keepsTiming else { return nil }
        return SessionElapsedFormatter.spokenElapsed(
            since: session.startedAt,
            now: Self.readableNow(timerNow, forStart: session.startedAt)
        )
    }

    /// What a finished row's slot draws: the length of the turn that ended, measured between
    /// its own two stamps. `nil` on a row still timing (see ``elapsedText(for:)``) or one whose
    /// end was never observed.
    func finishedElapsed(for session: MonitoredSession) -> (start: Date, end: Date)? {
        guard !session.status.keepsTiming,
              let startedAt = session.startedAt,
              let finishedAt = session.finishedAt,
              finishedAt >= startedAt
        else { return nil }
        return (startedAt, finishedAt)
    }

    func finishedElapsedText(for session: MonitoredSession) -> String? {
        guard let span = finishedElapsed(for: session) else { return nil }
        return SessionElapsedFormatter.elapsed(since: span.start, now: span.end)
    }

    func spokenFinishedElapsedText(for session: MonitoredSession) -> String? {
        guard let span = finishedElapsed(for: session) else { return nil }
        return SessionElapsedFormatter.spokenElapsed(since: span.start, now: span.end)
    }

    /// Whether a row's body line carries the searchlight: only while the row's own turn keeps
    /// timing, even if its subagents are still working.
    func sweepsBody(for session: MonitoredSession) -> Bool {
        session.status.keepsTiming
    }

    /// The instant a readout is drawn at, never earlier than the turn it draws.
    ///
    /// Between a turn starting and the next once-a-second tick, the tick trails the start and
    /// ``SessionElapsedFormatter`` answers `nil`. Both stamps come from ``MonitorClock``, so this
    /// is not skew. `nil` swaps in the untimed dot, and the width-gated re-measure
    /// (`AGENTS.md` §7) never asks for a re-render: measured on Release 2026-08-24, a running
    /// row lost its timer for good.
    nonisolated private static func readableNow(_ now: Date, forStart start: Date?) -> Date {
        guard let start else { return now }
        return max(now, start)
    }

    /// The live list as blocks: one per product that has a row, whenever
    /// ``groupsSessionsByProduct`` is on (no presence gate, 2026-09-09).
    ///
    /// One product is one block. A gate on connected products made headings come and go while
    /// both stayed open. A product with no rows draws no heading (`expanded-panel-v2.md` §4.3
    /// rule 04). The Recent queue is not grouped (``MonitorAggregation/SessionGroup``). Empty
    /// while the preference is off: the view draws rows in ``MonitorAggregation/rowOrder``.
    var sessionGroups: [MonitorAggregation.SessionGroup] {
        groupsSessionsByProduct ? MonitorAggregation.groups(of: sessions) : []
    }

    /// How many headers the live list draws, counted without building the blocks (read on every
    /// sizing pass). Zero with nothing live.
    var sessionGroupHeaderCount: Int {
        groupsSessionsByProduct ? Set(sessions.map(\.agent)).count : 0
    }

    /// Whether the first thing under the band is a block's heading. The panel's own top hairline
    /// is drawn on the negation of this only, so the two identical rules are never drawn `24`
    /// apart (`panel-v2.md` §3.4); see ``PanelMetrics/leadingProductGroupHeaderHeight``.
    var listLeadsWithABlockHeading: Bool { sessionGroupHeaderCount > 0 }

    /// One group per connected product, in Settings' order, each with its windows in published
    /// order (`quota-footer-v2.md` §5).
    ///
    /// - A product with no limits keeps its group and draws no inner lines.
    /// - Nothing is sorted: a share sort would re-order rows as shares cross, and
    ///   `Quota.remainingPercent` reads `windows.first`.
    /// - Excludes ``productsHiddenFromQuotaTable``.
    var footerRules: [FooterRule] {
        let now = clock.now()
        return quotaTableProducts.map { agent, quota in
            FooterRule(
                agent: agent,
                today: UsageSummaryFormatter.today(tokens: quota.todayTokens),
                windows: quota.windows.map { Self.footerWindow(for: $0, now: now) }
            )
        }
    }

    /// Every connected product with a reading, in Settings' order: the footer's shape without
    /// formatting its strings, so the per-render questions stay cheap (`AGENTS.md` §7).
    private var quotaProducts: [(agent: AgentKind, quota: QuotaSnapshot)] {
        connectedAgents.compactMap { agent in
            latestByAgent[agent].map { (agent, $0.quota) }
        }
    }

    /// Less the products taken out of the table. Today's total never reads this.
    private var quotaTableProducts: [(agent: AgentKind, quota: QuotaSnapshot)] {
        quotaProducts.filter { !productsHiddenFromQuotaTable.contains($0.agent) }
    }

    func showsInQuotaTable(_ agent: AgentKind) -> Bool {
        !productsHiddenFromQuotaTable.contains(agent)
    }

    func setShowsInQuotaTable(_ shows: Bool, for agent: AgentKind) {
        if shows {
            productsHiddenFromQuotaTable.remove(agent)
        } else {
            productsHiddenFromQuotaTable.insert(agent)
        }
    }

    /// One window's line: name, share, and `Resets in` countdown. See
    /// ``UsageSummaryFormatter/resetText(resetsAt:remainingPercent:now:calendar:)``.
    private static func footerWindow(
        for window: QuotaWindow,
        now: Date
    ) -> FooterWindow {
        FooterWindow(
            label: window.label,
            share: UsageSummaryFormatter.share(
                remainingPercent: window.remainingPercent
            ),
            timer: UsageSummaryFormatter.resetText(
                resetsAt: window.resetsAt,
                remainingPercent: window.remainingPercent,
                now: now
            ),
            spokenTimer: UsageSummaryFormatter.spokenResetText(
                resetsAt: window.resetsAt,
                remainingPercent: window.remainingPercent,
                now: now
            )
        )
    }

    /// The footer's one line at rest: every connected product's tokens for today, including
    /// products hidden from the table, not broken into products (§3). Unreadable, it draws
    /// `-- today` (§8.3).
    var footerToday: SpendReading {
        let totals = quotaProducts.compactMap(\.quota.todayTokens)
        guard !totals.isEmpty else {
            return UsageSummaryFormatter.today(tokens: nil)
        }
        return UsageSummaryFormatter.today(tokens: totals.reduce(0, +))
    }

    /// Whether the footer is drawn: at least one connected product (§8.5 question 07).
    var showsQuotaFooter: Bool { !quotaProducts.isEmpty }

    /// Drawn whenever the table would have a group, not only near a limit (§8.5 question 06).
    /// With every connected product taken out, a chevron would open onto nothing (§13).
    var showsQuotaFoldControl: Bool { !quotaTableProducts.isEmpty }

    /// ``isQuotaExpanded`` survives an empty table, so putting a product back restores it.
    var showsQuotaTable: Bool { isQuotaExpanded && showsQuotaFoldControl }

    /// The table opens beneath the always-drawn spend line, so closing it cannot strand the
    /// pointer below the panel's bottom edge.
    func toggleQuotaTable() { isQuotaExpanded.toggle() }

    /// The band's mark: it opens the About panel and is the only thing that closes it.
    func toggleAbout() { isShowingAbout.toggle() }

    var expandedFooterHeight: CGFloat {
        guard showsQuotaFooter else { return 0 }
        // A table with every product taken out still has a total to draw.
        guard showsQuotaTable else { return PanelMetrics.restingFooterHeight }
        let table = quotaTableProducts
        return PanelMetrics.footerHeight(
            productCount: table.count,
            windowCount: table.reduce(0) { $0 + $1.quota.windows.count },
            isExpanded: true
        )
    }

    var emptyListMessage: String {
        availability.emptyListMessage
    }

    var expandedContentHeight: CGFloat {
        // The About panel replaces the body, so it replaces the height arithmetic too.
        guard !isShowingAbout else { return PanelMetrics.aboutPanelHeight }
        return PanelMetrics.expandedContentHeight(
            liveRowCount: sessions.count,
            openRowHeight: openRowHeight,
            retiredRowCount: recentDepartures.count,
            isRecentExpanded: isRecentExpanded,
            footerHeight: expandedFooterHeight,
            groupHeaderCount: sessionGroupHeaderCount
        )
    }

    /// What the live list asks for, and the room it is drawn in. Read here, from the same calls
    /// ``expandedContentHeight`` uses: measuring in the view gave a `400` pt row a `240` viewport.
    var sessionListContentHeight: CGFloat {
        PanelMetrics.sessionListContentHeight(
            liveRowCount: sessions.count,
            openRowHeight: openRowHeight,
            groupHeaderCount: sessionGroupHeaderCount
        )
    }

    var sessionViewportHeight: CGFloat {
        PanelMetrics.sessionViewportHeight(
            liveRowCount: sessions.count,
            openRowHeight: openRowHeight,
            groupHeaderCount: sessionGroupHeaderCount
        )
    }

    // MARK: - The open row

    /// The row whose request is open; one at a time (`answer-in-notch.md` §8.2). Not persisted:
    /// hook payloads never reach disk (`artifacts.md`).
    @Published private(set) var openRowID: String?

    /// Read through the list, so a request settled elsewhere closes the row with nothing to
    /// reconcile (§8).
    var openSession: MonitoredSession? {
        guard let openRowID else { return nil }
        return sessions.first { $0.id == openRowID }
    }

    /// The request the open row is showing, pinned to the one being read (package 2,
    /// 2026-09-12): while the drafts' request is still live it stays shown, even if the product
    /// now ranks another first (``MonitoredSession/requests``). Only its resolution moves on.
    var openRequest: AgentRequest? {
        guard let openRowID, let session = openSession else { return nil }
        if let asked = answerProgress[openRowID]?.request,
           let pinned = session.requests.first(where: { $0.asked == asked }) {
            return pinned
        }
        return session.request
    }

    /// Browsing is independent of answering. Only an explicit click moves
    /// between requests; native arrivals never displace the one being read.
    var openRequestIndex: Int? {
        guard let request = openRequest else { return nil }
        return openSession?.requests.firstIndex { $0.asked == request.asked }
    }
    var openRequestCount: Int { openSession?.requests.count ?? 0 }
    var canGoBackARequest: Bool { !isAnswerInFlight && (openRequestIndex ?? 0) > 0 }
    var canGoForwardARequest: Bool {
        !isAnswerInFlight && openRequestIndex.map { $0 + 1 < openRequestCount } == true
    }
    func stepRequest(_ direction: Int) {
        guard !isAnswerInFlight, let session = openSession, let index = openRequestIndex else { return }
        let next = index + direction
        guard session.requests.indices.contains(next) else { return }
        openRow(session.id, showing: session.requests[next])
        answerRevision &+= 1
    }

    /// The last body laid out, keyed on its inputs so no mutation route can leave it stale.
    private var laidOutBody: (key: RequestBodyKey, layout: RequestBodyLayout?)?

    private struct RequestBodyKey: Equatable {
        let request: AgentRequest
        let question: Int
        let expandedOptions: Set<Int>
    }

    /// How many bodies this store has laid out, so a test can assert ``openRowBody``'s caching.
    /// Never published: reading a body must not invalidate the panel reading it.
    private(set) var bodyLayoutCount = 0

    /// The open row's body at its drawn width, laid out once per change: every height accessor
    /// reads it, and uncached it ran 48 layouts per open at `14 ms` each (Release, 2026-09-07).
    var openRowBody: RequestBodyLayout? {
        guard let request = openRequest else { return nil }
        let key = RequestBodyKey(
            request: request,
            question: openQuestionIndex,
            expandedOptions: openRowID.flatMap { answerProgress[$0]?.expandedOptions } ?? []
        )
        if let laidOutBody, laidOutBody.key == key { return laidOutBody.layout }
        let layout = RequestBodyLayout.laidOut(
            request, showing: key.question, expandedOptions: key.expandedOptions
        )
        laidOutBody = (key, layout)
        bodyLayoutCount &+= 1
        return layout
    }

    var openQuestionIndex: Int {
        guard let openRowID else { return 0 }
        return answerProgress[openRowID]?.questionIndex ?? 0
    }

    /// The open row's answer words at the body's position: `Next` or `Submit` depends on the
    /// index (§5.8), so views must not read the shape off the request alone.
    var openAnswerRow: AnswerRowShape? {
        openRequest?.answerRow(showing: openQuestionIndex)
    }

    var openRowHeight: CGFloat? {
        guard openSession != nil else { return nil }
        return PanelMetrics.openRowFixedHeight + (openRowBody?.drawnHeight ?? 0)
            + (openRequestCount > 1 ? PanelMetrics.requestNavigationHeight + PanelMetrics.sessionRowLineSpacing : 0)
            + answerFieldHeight - PanelMetrics.answerRowHeight
    }

    /// The field's height at what it holds (§7.1): ``PanelMetrics/answerRowHeight`` with no field.
    var answerFieldHeight: CGFloat {
        guard openAnswerRow?.placeholder != nil else { return PanelMetrics.answerRowHeight }
        return PanelMetrics.answerFieldHeight(lines: answerFieldLineCount)
    }

    /// Where the open row's field wraps. `Back` is counted wherever the set has one to show,
    /// including while a send hides it, so an answer in flight keeps its lines (§8 state 01).
    var answerFieldTextWidth: CGFloat {
        guard let shape = openAnswerRow else { return PanelMetrics.requestBodyWidth }
        let hasBack = openRequest?.askedQuestions.isEmpty == false && openQuestionIndex > 0
        let words = (hasBack ? ["Back"] : []) + [shape.refusal, shape.affirmative].compactMap { $0 }
        return PanelMetrics.answerFieldTextWidth(besideControls: words)
    }

    /// The last field measured, keyed on its inputs like ``laidOutBody``: heights are read a few
    /// dozen times a frame, and the draft is measured once per edit.
    private var measuredField: (text: String, width: CGFloat, lines: Int)?

    var answerFieldLineCount: Int {
        let text = answerDraft
        let width = answerFieldTextWidth
        if let measuredField, measuredField.text == text, measuredField.width == width {
            return measuredField.lines
        }
        let lines = PanelMetrics.answerFieldLineCount(text, width: width)
        measuredField = (text, width, lines)
        return lines
    }

    /// Opens this row's request, or closes it if already open. A row with no request does not
    /// open (`answer-in-notch.md` §3).
    func toggleOpenRow(_ session: MonitoredSession) {
        guard session.request != nil else { return }
        if openRowID == session.id {
            closeOpenRow()
        } else {
            openRow(session.id)
        }
    }

    /// Whether the panel holds the keyboard for a row. Only a click on a mark latches; hover
    /// never does (§9.4).
    var isLatched: Bool { openRowID != nil }

    /// Collapses the open row without sending; the chevron's action and `⎋`'s. What was typed is
    /// kept for the row's lifetime (§10).
    func closeOpenRow() {
        guard openRowID != nil else { return }
        openRowID = nil
        armingTask?.cancel()
        armingTask = nil
        isAffirmativeArmed = false
        // ``isAnswerInFlight`` stays set: clearing it would let a ticket be answered twice by
        // closing and reopening the row mid-flight. It clears on landing.
    }

    // MARK: - Answering

    /// Typed text and set progress per row, kept for the row's lifetime, never on disk (§10,
    /// ADR 0015). Not published: a keystroke must not re-render the panel (`AGENTS.md` §7).
    private var answerProgress: [String: AnswerProgress] = [:]
    /// Drafts for other live requests on the same row. Pruned on each snapshot.
    private var savedAnswerProgress: [String: [AnswerProgress]] = [:]

    private func selectProgress(for rowID: String, request: AgentRequest?) {
        let asked = request?.asked
        guard answerProgress[rowID]?.request != asked else { return }
        if let current = answerProgress[rowID],
           sessions.first(where: { $0.id == rowID })?.requests.contains(where: { $0.asked == current.request }) == true {
            var saved = savedAnswerProgress[rowID] ?? []
            saved.removeAll { $0.request == current.request }
            saved.append(current)
            savedAnswerProgress[rowID] = saved
        }
        answerProgress[rowID] = savedAnswerProgress[rowID]?.first { $0.request == asked }
            ?? AnswerProgress(request: asked)
        answerDraftGeneration &+= 1
    }

    /// Every handle an answer has been sent on: one attempt per handle (`answer-in-notch.md` §8),
    /// except an unsupported operation, which wrote nothing. Pruned with the rows.
    private var spentAnswerHandles: Set<AnswerHandle> = []

    /// Which answer the white ground is on, and so what `⏎` does. Derived from what has been
    /// typed, never set, so the drawing and the return key cannot disagree (§6, §6.1).
    @Published private(set) var answerGround: AnswerGround = .affirmative

    /// Bumped only when something drawn changes (the question on screen, and so the height);
    /// publishing ``answerProgress`` would re-render per keystroke (`AGENTS.md` §7).
    @Published private(set) var answerRevision = 0

    /// Bumped when the store replaces the field's text (an answer landed, a new question). The
    /// AppKit field refills only on this or a row change, or the caret would reset.
    @Published private(set) var answerDraftGeneration = 0

    /// Whether an answer is on its way to the product (§8 state 01). The field and controls drop
    /// to `45%` and stop taking keys; nothing resizes.
    @Published private(set) var isAnswerInFlight = false

    /// Whether the affirmative has finished arriving and may be taken (§6.3). Answering opens
    /// the next row under the same pointer (§8.2), so every answer waits for the arrival.
    @Published private(set) var isAffirmativeArmed = false
    private var armingTask: Task<Void, Never>?

    /// What a row's preview line says instead of its preview once an answer has left it (§8
    /// states 02 and 03), in the preview's own ink: there is no failure ink. Stands until
    /// ``forgetNoticesTheProductHasOvertaken()`` clears it.
    @Published private(set) var answerNotices: [String: AnswerNotice] = [:]

    /// The row's notice, the product's preview, or ``RowContentFallback/liveProgress``: never
    /// empty.
    func previewLine(for session: MonitoredSession) -> String {
        answerNotices[session.id]?.text ?? session.preview ?? RowContentFallback.liveProgress
    }

    var answerDraft: String {
        guard let openRowID else { return "" }
        return answerProgress[openRowID]?.draft ?? ""
    }

    /// The field reporting what it now holds, on every edit. Publishes only at the empty/non-empty
    /// boundary and when the field gains or loses a drawn line (§7.1), never per keystroke.
    func answerDraftChanged(to text: String) {
        guard let openRowID else { return }
        let wasTyped = questionUsesTypedAnswer
        let hadLines = answerFieldLineCount
        answerProgress[openRowID, default: AnswerProgress()].draft = text
        refreshAnswerGround()
        if wasTyped != questionUsesTypedAnswer || hadLines != answerFieldLineCount {
            answerRevision &+= 1
        }
    }

    /// Approval controls submit immediately. Question options only change the
    /// draft selection; the affirmative records the current answer and draws the
    /// next question, or on the last one sends the set.
    func takeAnswer(_ ground: AnswerGround) {
        guard !isAnswerInFlight, isAffirmativeArmed,
              let session = openSession,
              let request = openRequest,
              let shape = request.answerRow(showing: openQuestionIndex),
              let ticket = request.answerHandle else { return }

        switch ground {
        case .affirmative where shape.refusal == nil:
            // A question's control sends what the person put in: the field's words or ticked options.
            answerTheQuestion(
                request,
                of: session,
                on: ticket,
                saying: shape.affirmativeNotice
            )
        case .affirmative:
            send(.grant, to: request, for: session, on: ticket, saying: shape.affirmativeNotice)
        case .refusal:
            // No refusal to take; and a refusal with no placeholder draws no field to read.
            guard shape.refusal != nil else { return }
            let note = shape.placeholder == nil
                ? "" : answerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            send(
                .refuse(note.isEmpty ? nil : note),
                to: request,
                for: session,
                on: ticket,
                saying: shape.refusalNotice
            )
        case let .option(index):
            guard openRowBody?.options.contains(where: { $0.id == index }) == true else { return }
            tickOption(index)
        }
    }

    /// Ticks the option at that position in the question showing, as a click does
    /// (`multiSelect`, §5.5). Never submits. Keys arrive only when nothing holds the caret (§9.2).
    @discardableResult
    func takeNumberedOption(_ number: Int) -> Bool {
        guard !isAnswerInFlight, isAffirmativeArmed else { return false }
        let options = openRowBody?.options ?? []
        guard number >= 1, number <= options.count else { return false }
        takeAnswer(.option(options[number - 1].id))
        return true
    }

    /// A key the panel took because nothing in it holds the caret (§9.2); the one place the
    /// unfocused keyboard is decided.
    ///
    /// - Returns: whether anything happened, for tests. Every key stops at
    ///   ``OverlayPanel/keyDown(with:)`` either way.
    @discardableResult
    func takeKey(_ key: PanelKey) -> Bool {
        guard !isAnswerInFlight else { return false }
        if case let .step(direction) = key { return takeQuestionStep(direction) }
        guard openRequest?.answerRow() != nil else { return false }
        switch key {
        case .submit:
            guard isAffirmativeArmed, canSubmitCurrentAnswer else { return false }
            takeAnswer(answerGround)
            return true
        case let .option(number):
            return takeNumberedOption(number)
        case let .step(direction):
            return takeQuestionStep(direction)
        }
    }

    // MARK: - Walking a set backwards

    /// Whether the body can step back a question (§5.7). Not gated on ``isAffirmativeArmed``:
    /// going back sends nothing.
    var canGoBackAQuestion: Bool {
        guard !isAnswerInFlight, openRequest?.askedQuestions.isEmpty == false else { return false }
        return openQuestionIndex > 0
    }

    /// Whether the body can step forward to a question already reached (§5.7). Answerable sets
    /// also need the affirmative's gate, so a short set cannot go back to the product.
    var canGoForwardAQuestion: Bool {
        guard !isAnswerInFlight, let request = openRequest,
              let openRowID, let progress = answerProgress[openRowID] else { return false }
        if !request.canBeAnswered { return progress.questionIndex + 1 < request.askedQuestions.count }
        return progress.questionIndex < progress.furthestQuestionReached
            && canSubmitCurrentAnswer
    }

    /// Draws the question before this one, with what was put into it (§5.7).
    func goBackAQuestion() {
        guard canGoBackAQuestion else { return }
        drawQuestion(openQuestionIndex - 1)
    }

    func goForwardAQuestion() {
        guard canGoForwardAQuestion else { return }
        drawQuestion(openQuestionIndex + 1)
    }

    /// `←` and `→` walk the set while nothing holds the caret (§9.2). `Back` works whatever has
    /// focus.
    ///
    /// - Returns: whether the set actually moved.
    @discardableResult
    func takeQuestionStep(_ direction: Int) -> Bool {
        switch direction {
        case ..<0 where canGoBackAQuestion:
            goBackAQuestion()
        case 1... where canGoForwardAQuestion:
            goForwardAQuestion()
        default:
            return false
        }
        return true
    }

    /// Puts another question of the set on screen, keeping every draft (§5.7). Does not re-arm
    /// the affirmative: the person asked for this question.
    private func drawQuestion(_ index: Int) {
        guard let openRowID,
              let questions = openRequest?.askedQuestions,
              index >= 0, index < questions.count,
              var progress = answerProgress[openRowID],
              progress.questionIndex != index else { return }
        progress.questionIndex = index
        answerProgress[openRowID] = progress
        // The store now decides what the field holds.
        answerDraftGeneration &+= 1
        refreshAnswerGround()
        // A different question is a different height.
        answerRevision &+= 1
    }

    /// Whether one option of the question on screen is ticked (§5.5).
    func isOptionTicked(_ index: Int) -> Bool {
        guard let openRowID else { return false }
        return answerProgress[openRowID]?.ticked.contains(index) ?? false
    }

    var questionUsesTypedAnswer: Bool {
        !answerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether the question showing has an option ticked, which makes the field's text moot
    /// (§5.4).
    var questionHasASelection: Bool {
        openRowBody?.options.contains { isOptionTicked($0.id) } ?? false
    }

    var canSubmitCurrentAnswer: Bool {
        guard let request = openRequest else { return false }
        let questions = request.askedQuestions
        guard !questions.isEmpty else { return true }
        guard let openRowID else { return false }
        // The same gate as the final answer (§5.7 rule 06).
        let position = min(max(openQuestionIndex, 0), questions.count - 1)
        return Self.answer(
            to: questions[position],
            from: answerProgress[openRowID]?.draft(forQuestion: position) ?? AnswerProgress.Draft()
        ) != nil
    }

    func toggleOptionDescription(_ id: Int) {
        guard let openRowID,
              openRowBody?.optionLayouts.contains(where: { $0.id == id && $0.canExpand }) == true else { return }
        var progress = answerProgress[openRowID] ?? AnswerProgress()
        if progress.expandedOptions.contains(id) { progress.expandedOptions.remove(id) }
        else { progress.expandedOptions.insert(id) }
        answerProgress[openRowID] = progress
        answerRevision &+= 1
    }

    private func tickOption(_ index: Int) {
        guard let openRowID else { return }
        var progress = answerProgress[openRowID] ?? AnswerProgress()
        if openRowBody?.allowsSeveralAnswers == false {
            progress.ticked = [index]
        } else if progress.ticked.contains(index) {
            progress.ticked.remove(index)
        } else {
            progress.ticked.insert(index)
        }
        answerProgress[openRowID] = progress
        answerRevision &+= 1
    }

    /// Answers the question on screen, then draws the next or sends the set as one
    /// `updatedInput` (§5.3). Text replaces selected labels. Answers are read from the drafts
    /// when the set leaves, so a revisited answer wins (§5.7).
    private func answerTheQuestion(
        _ request: AgentRequest,
        of session: MonitoredSession,
        on ticket: AnswerHandle,
        saying notice: String
    ) {
        guard let openRowID else { return }
        let questions = request.askedQuestions
        guard !questions.isEmpty else { return }
        var progress = answerProgress[openRowID] ?? AnswerProgress()
        let position = min(max(progress.questionIndex, 0), questions.count - 1)
        guard Self.answer(
            to: questions[position],
            from: progress.draft(forQuestion: position)
        ) != nil else { return }

        if position + 1 < questions.count {
            progress.questionIndex = position + 1
            // The frontier moves forward only here: `Next` reaches a question first (§5.7).
            progress.furthestQuestionReached = max(
                progress.furthestQuestionReached, position + 1
            )
            answerProgress[openRowID] = progress
            answerDraftGeneration &+= 1
            refreshAnswerGround()
            answerRevision &+= 1
            // Armed by the arrival, not a delay of its own (§6.3).
            armTheAffirmativeOnArrival(of: openRowID)
            return
        }

        answerProgress[openRowID] = progress
        send(
            .answers(
                questions.indices.compactMap {
                    Self.answer(to: questions[$0], from: progress.draft(forQuestion: $0))
                }
            ),
            to: request,
            for: session,
            on: ticket,
            saying: notice
        )
    }

    /// What one question's draft answers, or `nil`; the single place a draft becomes an answer.
    /// A chosen option wins over text (§5.4); options travel by identity in listed order (§5.5)
    /// until ``ClaudeCodeRequestAnswering`` encodes them. Stale ticks never leave.
    private static func answer(
        to question: AgentQuestion,
        from draft: AnswerProgress.Draft
    ) -> AgentQuestionAnswer? {
        let chosen = question.options.filter { draft.ticked.contains($0.id) }.map(\.id)
        if !chosen.isEmpty {
            let answer = AgentQuestionAnswer(question: question, selectedOptionIDs: chosen)
            return answer.fitsItsQuestion ? answer : nil
        }
        let typed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard question.acceptsFreeText, !typed.isEmpty else { return nil }
        return AgentQuestionAnswer(question: question, text: typed)
    }

    /// Sends one answer, and turns what comes back into a row (§8).
    private func send(
        _ answer: AgentAnswer,
        to request: AgentRequest,
        for session: MonitoredSession,
        on ticket: AnswerHandle,
        saying notice: String
    ) {
        // Checked here too so no caller (key, click, specimen) can send an undeclared operation.
        // The boundary checks it again.
        guard request.operations.permits(answer),
              // And once per handle, whatever comes back.
              spentAnswerHandles.insert(ticket).inserted else { return }
        isAnswerInFlight = true
        let agent = session.agent
        let rowID = session.id
        // Stripped of its connection, so a result landing on a row another request has since taken
        // annotates nothing.
        let asked = request.asked
        let previewWhenWritten = session.preview
        Task { [weak self] in
            let outcome = await self?.answerer(for: agent)?
                .answer(answer, on: ticket) ?? .expired(.notHeld)
            // Hop back explicitly: under `SWIFT_APPROACHABLE_CONCURRENCY` it is elided, and a panel
            // property written off the main actor draws one publish stale (`AGENTS.md` §7).
            await MainActor.run { [weak self] in
                self?.answerLanded(
                    outcome,
                    rowID: rowID,
                    asked: asked,
                    handle: ticket,
                    previewWhenWritten: previewWhenWritten,
                    notice: notice,
                    product: agent
                )
            }
        }
    }

    /// What the row becomes once the answer has arrived or not (§8). The panel does not close
    /// (§8.3); the row says what ``AnswerOutcome`` proved without moving status (§8.1); a result
    /// for a request the row no longer holds annotates nothing.
    private func answerLanded(
        _ outcome: AnswerOutcome,
        rowID: String,
        asked: AgentRequest,
        handle: AnswerHandle,
        previewWhenWritten: String?,
        notice: String,
        product: AgentKind
    ) {
        isAnswerInFlight = false
        // Nothing was written; the channel may still take what it does carry.
        if outcome == .unsupportedOperation { spentAnswerHandles.remove(handle) }
        guard let current = sessions.first(where: { $0.id == rowID }),
              current.requests.contains(where: { $0.asked == asked }) else {
            requestRefresh()
            return
        }
        let arrived = outcome.answerArrived
        if arrived {
            answerProgress[rowID] = nil
            savedAnswerProgress[rowID]?.removeAll { $0.request == asked }
            answerDraftGeneration &+= 1
        }
        answerNotices[rowID] = AnswerNotice(
            text: arrived ? notice : Self.noticeText(for: outcome, product: product),
            previewWhenWritten: previewWhenWritten
        )
        if openRowID == rowID { closeOpenRow() }
        // The next request opens itself, unarmed, so the answering click cannot answer it (§8.2).
        // Only on an answer that arrived, so `Not sent` stays visible. It may be on this same row.
        if arrived, let next = sessions.lazy.compactMap({ session -> (row: String, request: AgentRequest?)? in
            if session.id == rowID {
                guard let other = session.requests.first(where: { $0.asked != asked && $0.canBeAnswered }) else {
                    return nil
                }
                return (session.id, other)
            }
            return session.request == nil ? nil : (session.id, nil)
        }).first {
            openRow(next.row, showing: next.request)
        }
        // The ticket is spent, so the mark is one publish stale; refresh rather than teach the
        // projection to notice a connection closing.
        requestRefresh()
    }

    /// The preview line for an answer that did not arrive (§8 state 03). Each sentence claims
    /// only what its outcome proved; an uncertain write sends the person to the product rather
    /// than inviting a resend.
    private static func noticeText(for outcome: AnswerOutcome, product: AgentKind) -> String {
        switch outcome {
        case .accepted, .sent:
            // Answered by the shape's own notice; never reached.
            "Answered"
        case .expired(.peerGone):
            "Not sent — the product stopped waiting for this answer"
        case .expired(.timedOut):
            "Not sent — the time for answering here ran out"
        case .expired(.notHeld):
            "Not sent — this request can no longer be answered here"
        case let .rejected(reason):
            "Not accepted — \(reason)"
        case .unsupportedOperation:
            "Not sent — \(product.displayName) does not take this answer here"
        case .uncertain:
            "Sent, but not confirmed — check in \(product.displayName)"
        }
    }

    /// Opens one row and starts the arrival that arms its affirmative.
    ///
    /// - Parameter request: which request to open, when the caller knows better than the
    ///   product's first (the next one after an answer from here). Defaults to the first.
    private func openRow(_ id: String, showing request: AgentRequest? = nil) {
        selectProgress(for: id, request: request ?? sessions.first(where: { $0.id == id })?.request)
        openRowID = id
        refreshAnswerGround()
        armTheAffirmativeOnArrival(of: id)
    }

    /// Holds the affirmative unarmed for as long as it is still arriving (§6.3).
    private func armTheAffirmativeOnArrival(of id: String) {
        isAffirmativeArmed = false
        armingTask?.cancel()
        armingTask = Task { [weak self] in
            // ``PanelMotion/duration`` with `Task.sleep`, not the injected clock: this is the length of a
            // drawing, and a clock a test never advanced would leave the affirmative unarmed.
            try? await Task.sleep(for: .seconds(PanelMotion.duration))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.openRowID == id else { return }
                self.isAffirmativeArmed = true
            }
        }
    }

    private func refreshAnswerGround() {
        let ground = AnswerGround.where(
            openRequest,
            carriesText: !answerDraft.isEmpty
        )
        if answerGround != ground { answerGround = ground }
    }

    /// Closes a row whose request was settled elsewhere, within one publish (§8 state 04),
    /// discarding what was typed.
    ///
    /// Also a row that left the list: ``isLatched`` reads ``openRowID`` directly, and skipping it
    /// kept the panel holding the keyboard over nothing, even collapsed (measured on Release).
    private func closeARowWhoseRequestHasGone() {
        guard let openRowID, !isAnswerInFlight else { return }
        if let session = sessions.first(where: { $0.id == openRowID }), let request = session.request {
            // The request being read is still live, so it stays on screen (``openRequest``).
            if let asked = answerProgress[openRowID]?.request,
               session.requests.contains(where: { $0.asked == asked }) {
                return
            }
            // Otherwise move to the product's first; ticks on the old set do not travel.
            if answerProgress[openRowID]?.request != request.asked {
                selectProgress(for: openRowID, request: request)
                answerRevision &+= 1
                refreshAnswerGround()
                armTheAffirmativeOnArrival(of: openRowID)
            }
            return
        }
        answerProgress[openRowID] = nil
        answerDraftGeneration &+= 1
        closeOpenRow()
    }

    /// Drops every notice the product has since spoken over, and every notice whose row has gone.
    private func forgetNoticesTheProductHasOvertaken() {
        var previews: [String: String?] = [:]
        for session in sessions { previews[session.id] = session.preview }
        answerNotices = answerNotices.filter { id, notice in
            guard let preview = previews[id] else { return false }
            return preview == notice.previewWhenWritten
        }
        answerProgress = answerProgress.filter { id, progress in
            sessions.first(where: { $0.id == id })?.requests.contains(where: { $0.asked == progress.request }) == true
        }
        for id in Array(savedAnswerProgress.keys) {
            let requests = sessions.first { $0.id == id }?.requests ?? []
            let live = savedAnswerProgress[id]?.filter { progress in
                requests.contains { $0.asked == progress.request }
            } ?? []
            savedAnswerProgress[id] = live.isEmpty ? nil : live
        }
        // Remembered while some row still offers the handle.
        spentAnswerHandles = spentAnswerHandles.filter { handle in
            sessions.contains { $0.requests.contains { $0.answerHandle == handle } }
        }
    }

    var currentPanelSize: CGSize {
        PanelMetrics.size(
            geometry: geometry,
            isExpanded: isExpanded,
            statusReadoutText: statusDisplayName,
            trailing: compactTrailingReading,
            centerOcclusionWidth: selectedDisplay?.centerOcclusionWidth ?? 0,
            compactHeight: compactHeight,
            status: status,
            // Every mark the surface could draw (resting counts as one); `drawnMarkCount` is what the
            // notched bar draws, which differs only with the wings given up.
            matrixCount: presenceMarks.count,
            sessionCount: aggregateSessionCount,
            drawsMark: drawsCompactMarks,
            expandsToPillOnly: expandsToPillOnly,
            tucksPill: tucksCompactPill,
            expandedContentHeight: expandedContentHeight
        )
    }

    /// Where the panel body's trailing edge lands, in screen coordinates. Non-`nil` only for a
    /// notched compact panel pinned to the cut-out; everything else is centred.
    var currentPanelTrailingAnchor: CGFloat? {
        guard !isExpanded,
              let occlusionMaxX = selectedDisplay?.centerOcclusionMaxX else {
            return nil
        }

        return occlusionMaxX
            + PanelMetrics.compactTrailingWingWidth(
                trailing: compactTrailingReading
            )
    }

    /// The contour's upper fillet, which is also the shoulder the window leaves outside the body
    /// on each side.
    var surfaceShoulderRadius: CGFloat {
        PanelMetrics.surfaceShoulderRadius(panelHeight: compactHeight)
    }

    var surfaceBottomCornerRadius: CGFloat {
        PanelMetrics.surfaceBottomCornerRadius(panelHeight: compactHeight)
    }

    func selectDisplay(id: String) {
        guard displays.contains(where: { $0.id == id }) else { return }

        if preferredDisplayID != id {
            preferredDisplayID = id
            preferences?.set(id, forKey: Self.selectedDisplayDefaultsKey)
        }

        guard selectedDisplayID != id else { return }

        cancelPendingHoverAction()
        selectedDisplayID = id
    }

    func refreshDisplays(_ refreshedDisplays: [DisplayOption]? = nil) {
        let resolvedDisplays = refreshedDisplays ?? DisplayOption.currentDisplays()
        let previousSelection = selectedDisplayID
        displays = resolvedDisplays

        let restoredPreference = preferredDisplayID.flatMap { preferredID in
            resolvedDisplays.first { $0.id == preferredID }?.id
        }
        let nextSelection = restoredPreference
            ?? resolvedDisplays.first { $0.id == previousSelection }?.id
            ?? resolvedDisplays.first?.id
            ?? ""
        guard nextSelection != previousSelection else { return }

        cancelPendingHoverAction()
        isExpanded = false
        selectedDisplayID = nextSelection
    }

    /// Covered, hovering does not open the panel (`cover-the-words.md` §6): a pointer crossing
    /// to the menu bar would unfurl the prompt after `0.15` s
    /// (``MonitorTiming/hoverExpandDelay``). ``openFromCollapsed()`` is the only way in. Closing
    /// via ``pointerExitedPanel()`` is unchanged.
    func pointerEnteredPanel() {
        isPointerOnPanel = true
        guard !privacyMode else {
            // An entry must still cancel a pending exit: expanding rebuilds the tracking area, which
            // delivers a spurious `exit` ~`105 ms` after the resize and `enter` ~`112 ms` later
            // (measured). Returning early shut a press-opened panel under a still pointer.
            cancelPendingHoverAction()
            return
        }
        scheduleHoverAction(after: timing.hoverExpandDelay) { store in
            store.isExpanded = true
        }
    }

    /// The press that opens a covered panel. A no-op when already open or not covered, so the
    /// opening paths stay decided in one place.
    func openFromCollapsed() {
        guard privacyMode, !isExpanded else { return }
        cancelPendingHoverAction()
        isExpanded = true
    }

    func pointerExitedPanel() {
        isPointerOnPanel = false
        // A row somebody is reading does not close on pointer drift (`answer-in-notch.md` §10).
        guard openRowID == nil else { return }
        scheduleHoverAction(after: timing.hoverCollapseDelay) { store in
            store.isExpanded = false
        }
    }

    /// Re-check the pointer after a resize: a tracking area reports only movement, so shrinking
    /// away from a still pointer delivers no exit. Only leaving is corrected; re-expanding would
    /// undo a ``collapse()`` such as the concealment watcher's.
    func panelResized(to windowFrame: NSRect, pointerAt pointer: NSPoint) {
        guard isExpanded else { return }
        guard !OverlayPanelLayout.bodyContainsPointer(
            pointer,
            windowFrame: windowFrame,
            surfaceShoulder: surfaceShoulderRadius
        ) else { return }

        // The ordinary dwell, so a pointer moving back during the animation cancels it.
        pointerExitedPanel()
    }

    func collapse() {
        cancelPendingHoverAction()
        // Closing the panel ends the open row and returns the keyboard; the row keeps its place.
        openRowID = nil
        isExpanded = false
    }

    func open(_ session: MonitoredSession) {
        Task { [weak self] in
            _ = await self?.openAndWait(session)
        }
    }

    @discardableResult
    func openAndWait(_ session: MonitoredSession) async -> Bool {
        guard !isNavigationInFlight else { return false }
        guard let navigator else {
            lastIntegrationMessage = "Session navigation is only available with a real Codex integration."
            return false
        }

        isNavigationInFlight = true
        defer { isNavigationInFlight = false }

        do {
            let outcome = try await navigator.open(session)
            collapse()
            // What the navigator actually managed, not what Codex would have.
            lastIntegrationMessage = outcome.message(forTitle: session.title)
            return true
        } catch {
            await refreshAndWait()
            let reason = (error as? LocalizedError)?.errorDescription
                ?? "An unknown error occurred."
            lastIntegrationMessage = "Could not open \(session.title): \(reason)"
            return false
        }
    }

    func refreshNow() {
        requestRefresh()
    }

    /// Takes one row off the list at the user's asking, in any status: a Turn stuck open by a
    /// defect is never Completed (``HookTurnState/heldTurnStart``).
    ///
    /// - Keyed by ``MonitoredSession/id`` (the Turn), so the thread's next Turn lists normally;
    ///   dropped via ``forgetDismissalsProvenGone(in:)``.
    /// - Deletes nothing, marks nothing read, and does not stop the Turn.
    /// - The provider is told on each snapshot request, or it keeps sampling read state
    ///   (CR-Fable-003).
    /// - The only way to remove a terminal Claude Code row
    ///   ([ADR 0012](../../docs/adr/0012-read-state-is-answered-per-product-or-not-at-all.md)).
    @discardableResult
    func dismiss(_ session: MonitoredSession) -> Bool {
        guard !isDismissed(session) else { return false }

        dismissedSessionIDsByAgent[session.agent, default: []].insert(session.id)
        // Through the merge, not by editing `sessions`: `apply` keeps the list, summary status and
        // product marks in agreement, so a dismissed row cannot light its mark.
        apply(AgentSnapshotMerge.merge(Array(latestByAgent.values)))
        // Refresh now so the provider stops re-checking read state for the hidden row (CR-Fable-003).
        requestRefresh()
        return true
    }

    func recheckIntegrationAndWait() async {
        for service in services { await service.recheckConnection() }
        await refreshAndWait()
    }

    func installIntegrationHooks(for agent: AgentKind) {
        Task { [weak self] in
            _ = await self?.installIntegrationHooksAndWait(for: agent)
        }
    }

    /// Records the desired integration state for one product and converges to it.
    ///
    /// One convergence task per product re-reads the desired state after each step, so the last
    /// flip wins and intermediate flips are collapsed (CR-017).
    func setIntegrationEnabled(_ isEnabled: Bool, for agent: AgentKind) {
        guard isEnabled != desiredIntegrationEnabled[agent]
            ?? integrationSwitchIsOn(for: agent) else {
            return
        }

        integrationIntentRevisions[agent, default: 0] += 1
        productOperationFailures[agent] = nil
        saveMonitoringIntent(isEnabled ? .enabled : .disabled, for: agent)
        desiredIntegrationEnabled[agent] = isEnabled
        setSwitch(isEnabled, for: agent)
        startIntegrationConvergenceIfNeeded(for: agent)
        if !isEnabled {
            record(AgentSnapshot(agent: agent, availability: .setupRequired, sessions: [],
                quota: .unavailable, diagnostic: nil, setupStatus: setupStatus(for: agent),
                presence: latestByAgent[agent]?.presence ?? .unknown), observedAt: clock.now())
        }
    }

    @discardableResult
    func setIntegrationEnabledAndWait(_ isEnabled: Bool, for agent: AgentKind) async -> Bool {
        setIntegrationEnabled(isEnabled, for: agent)
        await integrationTasks[agent]?.value
        return integrationSwitchIsOn(for: agent) == isEnabled
    }

    /// Starts one product's convergence loop unless one is already running. The loop runs until
    /// the ``desiredIntegrationEnabled`` entry is gone; check and clear share the main actor with
    /// no suspension between them.
    private func startIntegrationConvergenceIfNeeded(for agent: AgentKind) {
        guard configurer(for: agent) != nil,
              integrationTasks[agent] == nil else {
            return
        }
        integrationTasks[agent] = Task { [weak self] in
            guard let self else { return }
            while self.desiredIntegrationEnabled[agent] != nil {
                await self.convergeIntegrationOnce(for: agent)
            }
            self.integrationTasks[agent] = nil
        }
    }

    private func convergeIntegrationOnce(for agent: AgentKind) async {
        guard let desired = desiredIntegrationEnabled[agent] else { return }

        let succeeded = desired
            ? await installIntegrationHooksAndWait(for: agent)
            : await removeIntegrationAndWait(for: agent)

        // A newer flip owns the switch; do not write over it.
        guard desiredIntegrationEnabled[agent] == desired else { return }
        desiredIntegrationEnabled.removeValue(forKey: agent)

        if succeeded {
            // Re-read health: the install may have landed in reviewRequired rather than active.
            if let configurer = configurer(for: agent) {
                let status = await configurer.setupStatus()
                setSetupStatus(status, for: agent)
                setSwitch(desired, for: agent)
            }
        } else {
            // Keep the requested intent visible; failure is an operation result, not a user flip.
            setSwitch(desired, for: agent)
        }
    }

    @discardableResult
    func installIntegrationHooksAndWait(for agent: AgentKind) async -> Bool {
        guard let configurer = configurer(for: agent),
              !integrationBusyAgents.contains(agent) else {
            return false
        }
        integrationIntentRevisions[agent, default: 0] += 1
        integrationBusyAgents.insert(agent)
        defer { integrationBusyAgents.remove(agent); requestRefresh() }

        do {
            try await configurer.installIntegration()
            let status = await configurer.setupStatus()
            guard status.isIntegrationEnabled || status == .notRequired else {
                throw ManagedHooksConfigurationError.verificationFailed
            }
            setSetupStatus(status, for: agent)
            if desiredIntegrationEnabled[agent] != false {
                saveMonitoringIntent(.enabled, for: agent)
                setSwitch(true, for: agent)
            }
            productOperationFailures[agent] = nil
            await services.first(where: { $0.agent == agent })?.recheckConnection()
            lastIntegrationMessage = ProductRegistry.descriptor(for: agent).setup.installedMessage
            return true
        } catch {
            productOperationFailures[agent] = .init(status: "Setup failed", message: error.localizedDescription, action: .repair)
            lastIntegrationMessage = "Could not install the integration: \(error.localizedDescription)"
            return false
        }
    }

    func removeIntegration(for agent: AgentKind) {
        Task { [weak self] in
            _ = await self?.removeIntegrationAndWait(for: agent)
        }
    }

    @discardableResult
    func removeIntegrationAndWait(for agent: AgentKind) async -> Bool {
        guard let configurer = configurer(for: agent),
              !integrationBusyAgents.contains(agent) else {
            return false
        }
        integrationIntentRevisions[agent, default: 0] += 1
        integrationBusyAgents.insert(agent)
        defer { integrationBusyAgents.remove(agent); requestRefresh() }

        do {
            try await configurer.removeIntegration()
            // Drop only this product's half of the merge, replaced with what it would report itself
            // (`setupRequired`, no rows, no quota). Removing the key would let a one-product store fall
            // through to `disconnected`.
            record(
                AgentSnapshot(
                    agent: agent,
                    availability: .setupRequired,
                    sessions: [],
                    quota: .unavailable,
                    diagnostic: nil,
                    setupStatus: .notInstalled,
                    presence: latestByAgent[agent]?.presence ?? .unknown
                ),
                observedAt: clock.now()
            )
            if desiredIntegrationEnabled[agent] != true {
                saveMonitoringIntent(.disabled, for: agent)
                setSwitch(false, for: agent)
            }
            productOperationFailures[agent] = nil
            lastIntegrationMessage = ProductRegistry.descriptor(for: agent).setup.removedMessage
            return true
        } catch {
            await services.first(where: { $0.agent == agent })?.disconnect()
            productOperationFailures[agent] = .init(status: "Removal failed", message: error.localizedDescription, action: .remove)
            lastIntegrationMessage = "Could not remove the integration: \(error.localizedDescription)"
            return false
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        preferences?.set(true, forKey: Self.onboardingDefaultsKey)
        refreshNow()
    }

    func stopMonitoring() {
        wakeTask?.cancel()
        refreshEventTask?.cancel()
        let services = services
        Task {
            for service in services {
                await service.disconnect()
            }
        }
    }

    func refreshAndWaitForTesting() async {
        await refreshAndWait()
    }

    /// The instant the store would next wake for, or nil when only the heartbeat is left.
    func nextWakeUpForTesting() async -> Date? {
        (
            await providerDeadlines() + stabilityGates.values.map(\.nextPublishDeadline)
        ).compactMap { $0 }.min()
    }

    /// Feeds one product's answer through the refresh path, so a test exercises the merge.
    func applyForTesting(
        _ snapshot: AgentSnapshot,
        observedAt: Date? = nil
    ) {
        record(snapshot, observedAt: observedAt ?? clock.now())
    }

    private func scheduleHoverAction(
        after delay: TimeInterval,
        action: @escaping @MainActor (MonitorStore) -> Void
    ) {
        cancelPendingHoverAction()

        pendingHoverTask = Task { [weak self] in
            guard let self else { return }
            try? await clock.sleep(seconds: delay)
            guard !Task.isCancelled else { return }
            // `MainActor.run`: under `SWIFT_APPROACHABLE_CONCURRENCY` the hop back after `clock.sleep` is
            // elided (Release). `isExpanded` written off main drew stale state: 3 failures in 10 hover
            // bursts before, none in 120 after.
            await MainActor.run { action(self) }
        }
    }

    private func cancelPendingHoverAction() {
        pendingHoverTask?.cancel()
        pendingHoverTask = nil
    }

    private func startMonitoring() {
        guard !services.isEmpty else { return }

        if let refreshEvents {
            refreshEventTask = Task { [weak self] in
                for await _ in refreshEvents {
                    guard !Task.isCancelled else { return }
                    // A watcher signal does not wait, but the gate guarantees it is not dropped.
                    self?.requestRefresh()
                }
            }
        }

        // Watchers drive refreshes; otherwise only ``scheduleNextWake`` re-arms after each run, and
        // this first request starts that chain. Nothing samples on a cadence.
        requestRefresh()
    }

    /// Arms the next wake-up; must run at the end of every refresh run
    /// (``startRefreshRunIfNeeded``), or re-checks booked by watcher-driven refreshes are slept
    /// through (a one-second re-check took up to a minute). A task, so ``refreshAndWait`` can end.
    private func scheduleNextWake() {
        wakeTask?.cancel()
        wakeTask = Task { [weak self] in
            guard let self else { return }
            let heartbeat = self.timing.heartbeatInterval
            // Gate deadlines count: a suppressed disconnect is re-examined when its grace expires.
            let deadline = (
                await self.providerDeadlines()
                    + self.stabilityGates.values.map(\.nextPublishDeadline)
            ).compactMap { $0 }.min()
            guard !Task.isCancelled else { return }
            // Clamp an overdue deadline up to the floor: sleeping zero re-runs a full snapshot
            // (a main-thread LaunchServices round trip) in a busy loop.
            let untilDeadline = deadline.map {
                max(
                    self.timing.minimumRefreshInterval,
                    $0.timeIntervalSince(self.clock.now())
                )
            } ?? heartbeat
            try? await self.clock.sleep(seconds: min(heartbeat, untilDeadline))
            guard !Task.isCancelled else { return }
            self.requestRefresh()
        }
    }

    /// Re-stage a specimen store's fixed answers (``NotchSpecimen``) with a fresh start, so its
    /// clock wraps, through the ordinary merge. Refused on a watching store.
    func restageSpecimen(_ snapshots: [AgentSnapshot]) {
        guard services.isEmpty else { return }
        for snapshot in snapshots {
            latestByAgent[snapshot.agent] = snapshot
        }
        apply(AgentSnapshotMerge.merge(Array(latestByAgent.values)))
    }

    /// Show a completed draft in a non-watching tutorial store; a connected store refuses.
    /// - Parameter index: which question of a set is showing. Progress is kept, so calling this
    ///   per question walks a set as answering does.
    func stageSpecimenAnswer(
        selectedOptions: Set<Int>,
        draft: String = "",
        showingQuestion index: Int = 0
    ) {
        guard services.isEmpty, let openRowID,
              let request = openRequest else { return }
        // A non-question form is a set of one at `0` (``AnswerProgress/showing``).
        let questions = request.askedQuestions
        let position = min(max(index, 0), max(questions.count - 1, 0))

        var progress = answerProgress[openRowID] ?? AnswerProgress(request: request.asked)
        if progress.request != request.asked {
            progress = AnswerProgress(request: request.asked)
        }
        progress.questionIndex = position
        progress.furthestQuestionReached = max(progress.furthestQuestionReached, position)

        if let question = questions.indices.contains(position) ? questions[position] : nil {
            let valid = question.options.map(\.id).filter { selectedOptions.contains($0) }
            progress.ticked = Set(question.allowsSeveralAnswers ? valid : Array(valid.prefix(1)))
        }
        progress.draft = draft
        answerProgress[openRowID] = progress

        // Arm the affirmative now: a still taken during the §6.3 `PanelMotion.duration` delay draws
        // every control at `45%`, and a caller may not be able to turn the executor to wait.
        armingTask?.cancel()
        armingTask = nil
        isAffirmativeArmed = true

        answerDraftGeneration &+= 1
        answerRevision &+= 1
        refreshAnswerGround()
    }

    /// Put a specimen's Recent queue in front of it at chosen ages (a merge stamps every
    /// departure with one instant). Refused on a watching store.
    func stageSpecimenQueue(_ departures: [RecentDeparture]) {
        guard services.isEmpty else { return }
        departuresByThread = Dictionary(
            departures.map { (RecentDeparture.key(for: $0.session), $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        refreshRecentDepartures(at: clock.now())
    }

    private func apply(_ snapshot: MonitorSnapshot) {
        let now = clock.now()
        forgetDismissalsProvenGone(in: snapshot)
        let undismissedSessions = snapshot.sessions.filter { !isDismissed($0) }
        let visibleSessions = undismissedSessions
        // Before `sessions` moves: every departure, dismissals included, leaves through here.
        recordDepartures(
            leaving: visibleSessions,
            connectedAgents: Set(snapshot.connectedAgents),
            at: now
        )
        // Re-aggregated so a dismissed row stops counting towards the summary immediately.
        let aggregateStatus = MonitorAggregation.status(
            agents: snapshot.agents,
            sessions: undismissedSessions
        )
        let integrationMessage = snapshot.diagnostic ?? "Data refreshed"

        if availability != snapshot.availability {
            availability = snapshot.availability
        }
        if quota != snapshot.quota {
            quota = snapshot.quota
        }
        if sessions != visibleSessions {
            sessions = visibleSessions
        }
        forgetNoticesTheProductHasOvertaken()
        closeARowWhoseRequestHasGone()
        if status != aggregateStatus {
            status = aggregateStatus
        }
        if connectedAgents != snapshot.connectedAgents {
            connectedAgents = snapshot.connectedAgents
        }
        // Rebuilt from visible rows so a dismissed row stops lighting its product's mark.
        let marks = MonitorAggregation.marks(
            agents: snapshot.agents,
            sessions: undismissedSessions
        )
        if presenceMarks != marks {
            presenceMarks = marks
        }
        if lastIntegrationMessage != integrationMessage {
            lastIntegrationMessage = integrationMessage
        }
        refreshRecentDepartures(at: now)
    }

    /// Archives what this app watched finish and takes out what has come back: Notchline's own
    /// lifecycle, not product history (`PRD.md` §2 goal 9).
    ///
    /// ```text
    /// nothing → Running → Completed ─read→ archived ─┐
    ///                        ▲                       │
    ///                        └───────────────────────┘   submits again
    ///                                 archived ─expire/dismiss→ nothing
    /// ```
    ///
    /// A row that vanishes while last seen working is not archived (`tech-design.md` §15.1). The
    /// return loop also repairs Codex Desktop quitting before presence catches up (§5).
    private func recordDepartures(
        leaving visibleSessions: [MonitoredSession],
        connectedAgents: Set<AgentKind>,
        at now: Date
    ) {
        let surviving = Set(visibleSessions.map(\.id))

        for row in sessions where !surviving.contains(row.id) {
            guard let reason = departureReason(
                for: row,
                connectedAgents: connectedAgents
            ) else { continue }
            departuresByThread[RecentDeparture.key(for: row)] = RecentDeparture(
                session: row,
                departedAt: now,
                reason: reason
            )
        }

        // A Thread that submits again leaves the queue and reappears above the seam.
        for row in visibleSessions {
            departuresByThread.removeValue(forKey: RecentDeparture.key(for: row))
        }
    }

    /// Which arrow into the queue this row took, or `nil` for a row that left without ending.
    private func departureReason(
        for row: MonitoredSession,
        connectedAgents: Set<AgentKind>
    ) -> RecentDeparture.Reason? {
        if isDismissed(row) {
            // The reading is an age, so it stays honest on an unfinished Turn (§2.4 rule 05).
            return row.status.keepsTiming ? .dismissedWhileRunning : .dismissed
        }
        // Terminal when last drawn, then unlisted: the membership gate saying the product recorded
        // the Thread as read (`tech-design.md` §12).
        guard !row.status.keepsTiming else { return nil }
        // A product going dark ends nothing: presence decides whether it was there to read it.
        guard connectedAgents.contains(row.agent) else { return nil }
        return .read
    }

    /// Republishes the queue as of `now`, dropping whatever has aged out. Eviction is a filter,
    /// not a timer (§10).
    private func refreshRecentDepartures(at now: Date) {
        var kept = departuresByThread.filter {
            $0.value.age(at: now) < Self.recentWindow
        }
        // Key breaks ties: rows leaving in one pass share an instant, and dictionary order flaps.
        var ordered = kept.values.sorted {
            $0.departedAt == $1.departedAt
                ? $0.id < $1.id
                : $0.departedAt > $1.departedAt
        }
        if ordered.count > Self.recentCeiling {
            ordered = Array(ordered.prefix(Self.recentCeiling))
            kept = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        }
        if kept.count != departuresByThread.count {
            departuresByThread = kept
        }
        // Publish only while ages are on screen (panel open, queue unfolded): a publish re-renders
        // the overlay (`AGENTS.md` §7).
        if isExpanded, isRecentExpanded, ordered.contains(where: {
            $0.ageText(at: now) != $0.ageText(at: recentReadAt)
        }) {
            recentReadAt = now
        }
        if recentDepartures != ordered {
            recentDepartures = ordered
        }
        updateRecentTicking()
    }

    /// Moves the queue's ages while the panel is open with members, sleeping to the next boundary
    /// any member crosses (a flat minute drifts and skips a reading).
    private func updateRecentTicking() {
        guard isExpanded, !recentDepartures.isEmpty else {
            recentTickTask?.cancel()
            recentTickTask = nil
            return
        }
        guard recentTickTask == nil else { return }

        recentTickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard let deadline = self.nextRecentReadingChange(
                    at: self.clock.now()
                ) else { return }
                try? await self.clock.sleep(
                    seconds: max(deadline.timeIntervalSince(self.clock.now()), 0)
                )
                guard !Task.isCancelled else { return }
                // `MainActor.run`: see ``scheduleHoverAction(after:action:)`` (`AGENTS.md` §7).
                await MainActor.run {
                    self.refreshRecentDepartures(at: self.clock.now())
                }
            }
        }
    }

    /// When the queue's drawn reading next changes, or `nil`: each member's next age boundary when
    /// open, only its expiry when folded.
    private func nextRecentReadingChange(at now: Date) -> Date? {
        recentDepartures.map { departure in
            guard isRecentExpanded else {
                return departure.departedAt.addingTimeInterval(Self.recentWindow)
            }
            let age = max(departure.age(at: now), 0)
            let step: TimeInterval = age < 3600 ? 60 : 3600
            let elapsed = (age / step).rounded(.down) + 1
            return departure.departedAt.addingTimeInterval(elapsed * step)
        }.min()
    }

    /// Takes one row out of the queue at the user's asking (§2.4 rule 09). Nothing is remembered:
    /// the row can only return by departing the live list again.
    @discardableResult
    func removeFromRecent(_ departure: RecentDeparture) -> Bool {
        guard departuresByThread.removeValue(forKey: departure.id) != nil else {
            return false
        }
        refreshRecentDepartures(at: clock.now())
        return true
    }

    func toggleRecent() { isRecentExpanded.toggle() }

    private func isDismissed(_ session: MonitoredSession) -> Bool {
        dismissedSessionIDsByAgent[session.agent]?.contains(session.id) ?? false
    }

    /// Drops dismissals whose Turn its own product stopped listing while observable (open and
    /// answering). Mere absence (Desktop quit, App Server blip, Claude Code with no window,
    /// `tech-design.md` §15.1) put dismissed rows back (CR-Fable-004).
    private func forgetDismissalsProvenGone(in snapshot: MonitorSnapshot) {
        for agentSnapshot in snapshot.agents where agentSnapshot.isConnected {
            guard var dismissed = dismissedSessionIDsByAgent[agentSnapshot.agent],
                  !dismissed.isEmpty else { continue }
            dismissed.formIntersection(agentSnapshot.sessions.map(\.id))
            dismissedSessionIDsByAgent[agentSnapshot.agent] = dismissed.isEmpty
                ? nil
                : dismissed
        }
    }

    /// Records one product's answer and republishes the merge. Gated per product; a suppressed
    /// product keeps its last trusted answer.
    private func record(_ snapshot: AgentSnapshot, observedAt: Date) {
        let agent = snapshot.agent
        if connectionReadings[agent] != snapshot { connectionReadings[agent] = snapshot }
        var gate = stabilityGates[agent] ?? ConnectionStabilityGate(
            gracePeriod: timing.disconnectGracePeriod
        )
        let shouldPublish = gate.shouldPublish(
            candidate: snapshot.availability,
            current: latestByAgent[agent]?.availability ?? .connecting,
            observedAt: observedAt
        )
        stabilityGates[agent] = gate

        guard shouldPublish else {
            let reason = snapshot.diagnostic ?? "\(agent.displayName) is not responding at the moment."
            let retryMessage = "Transient connection trouble detected; retrying: \(reason)"
            if lastIntegrationMessage != retryMessage {
                lastIntegrationMessage = retryMessage
            }
            return
        }

        latestByAgent[agent] = snapshot
        setSetupStatus(snapshot.setupStatus, for: agent)
        refreshDiskFootprintIfNeeded(for: agent)
        apply(AgentSnapshotMerge.merge(Array(latestByAgent.values)))
        applyIntegrationHealth(for: agent)
    }

    /// What a product's own boundary reported, before merging.
    func agentAvailability(for agent: AgentKind) -> MonitorAvailability? {
        latestByAgent[agent]?.availability
    }

    func setupStatus(for agent: AgentKind) -> IntegrationSetupStatus {
        setupStatusByAgent[agent] ?? .notInstalled
    }

    func productSnapshot(for agent: AgentKind) -> AgentSnapshot? { connectionReadings[agent] ?? latestByAgent[agent] }
    func monitoringIntent(for agent: AgentKind) -> ProductMonitoringIntent? { monitoringIntents[agent] }

    private func saveMonitoringIntent(_ intent: ProductMonitoringIntent, for agent: AgentKind) {
        monitoringIntents[agent] = intent
        preferences?.set(intent.rawValue, forKey: "productMonitoringIntent." + agent.rawValue)
    }

    func repairIntegration(for agent: AgentKind) {
        Task { [weak self] in
            guard let self else { return }
            _ = await self.installIntegrationHooksAndWait(for: agent)
            await self.recheckIntegrationAndWait()
        }
    }

    func recheckProduct(_ agent: AgentKind) {
        Task { [weak self] in
            guard let self else { return }
            await self.services.first(where: { $0.agent == agent })?.recheckConnection()
            await self.refreshAndWait()
        }
    }

    func integrationSwitchIsOn(for agent: AgentKind) -> Bool {
        integrationSwitchIsOnByAgent[agent] ?? false
    }

    /// Whether that product's hooks are being written or removed, so its switch refuses input.
    func isIntegrationBusy(for agent: AgentKind) -> Bool {
        integrationBusyAgents.contains(agent)
    }

    /// Publishes only on a real change: a refresh restates the status every second and each
    /// publish re-evaluates the overlay (`AGENTS.md` §7).
    private func setSetupStatus(_ status: IntegrationSetupStatus, for agent: AgentKind) {
        guard setupStatusByAgent[agent] != status else { return }
        setupStatusByAgent[agent] = status
    }

    private func setSwitch(_ isOn: Bool, for agent: AgentKind) {
        guard integrationSwitchIsOnByAgent[agent] != isOn else { return }
        integrationSwitchIsOnByAgent[agent] = isOn
    }

    /// What went wrong on this product's side. Read off the stored answer, not its own
    /// `@Published` (`AGENTS.md` §7; CR-029).
    func diagnostic(for agent: AgentKind) -> String? {
        latestByAgent[agent]?.diagnostic
    }

    /// Re-reads what a product has left on disk, off the refresh because it lists a directory.
    private func refreshDiskFootprintIfNeeded(for agent: AgentKind) {
        guard diskFootprintTask == nil,
              let reporter = footprintReporter(for: agent) else {
            return
        }
        diskFootprintTask = Task { [weak self] in
            let report = await reporter.diskFootprint()
            guard let self else { return }
            self.diskFootprintTask = nil
            // Fold `leavesNothing` into `nil` before comparing, or every refresh publishes the same
            // absence (`AGENTS.md` §7).
            let stored: AgentDiskFootprintReport? =
                report == .leavesNothing ? nil : report
            guard self.diskFootprints[agent] != stored else { return }
            if let stored {
                self.diskFootprints[agent] = stored
            } else {
                self.diskFootprints.removeValue(forKey: agent)
            }
        }
    }

    /// Keeps one product's switch in step with its file, skipped while that product's own write
    /// is in flight so a mid-write refresh cannot flick the switch back.
    private func applyIntegrationHealth(for agent: AgentKind) {
        guard let refreshed = setupStatusByAgent[agent],
              !integrationBusyAgents.contains(agent) else {
            return
        }
        if monitoringIntents[agent] == nil, refreshed.isIntegrationEnabled {
            // Adopt an existing complete setup once. Absence cannot reconstruct past intent.
            saveMonitoringIntent(.enabled, for: agent)
        }
        setSwitch(monitoringIntents[agent] == .enabled, for: agent)
    }

    /// Each provider's next deadline, dropping a provider that reports the same overdue instant
    /// twice, which would pin every provider to the refresh floor.
    private func providerDeadlines() async -> [Date?] {
        var deadlines: [Date?] = []
        let now = clock.now()
        for service in services {
            let agent = service.agent
            guard monitoringIntents[agent] != .disabled else { continue }
            guard let deadline = await service.nextRefreshDeadline() else {
                stuckDeadlines[agent] = nil
                continue
            }
            if deadline <= now, stuckDeadlines[agent] == deadline {
                continue
            }
            stuckDeadlines[agent] = deadline <= now ? deadline : nil
            deadlines.append(deadline)
        }
        return deadlines
    }

    /// Requests a refresh without waiting, for triggers that only need convergence. Never dropped:
    /// a running refresh raises the gate so another follows.
    private func requestRefresh() {
        refreshGate.request()
        startRefreshRunIfNeeded()
    }

    /// Requests a refresh and waits for one that covers this request (Recheck); otherwise it
    /// returned stale status mid-refresh (CR-008).
    private func refreshAndWait() async {
        let revision = refreshGate.request()
        startRefreshRunIfNeeded()

        // At most two iterations: a run that begins after this request covers it.
        while !refreshGate.hasCovered(revision) {
            guard let refreshTask else { break }
            await refreshTask.value
        }
    }

    private func startRefreshRunIfNeeded() {
        guard !services.isEmpty, refreshGate.beginRun() else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                await self.performRefresh()
            } while self.refreshGate.endRun()
            // The gate is idle: arm from here so re-checks booked by watcher-driven refreshes count.
            guard !Task.isCancelled else { return }
            self.scheduleNextWake()
        }
    }

    /// Asks every product at once and publishes each answer as it lands. Nothing cancels a slow
    /// fetch; each provider bounds its own.
    private func performRefresh() async {
        guard !services.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for service in services {
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.monitoringIntents[service.agent] != .disabled else {
                        await service.disconnect()
                        return
                    }
                    // Dismissed rows travel with every request so the provider stops paying for them
                    // (CR-Fable-003).
                    let intentRevision = self.integrationIntentRevisions[service.agent, default: 0]
                    let snapshot = await service.fetchSnapshot(
                        dismissedRowIDs: self.dismissedSessionIDsByAgent[
                            service.agent
                        ] ?? []
                    )
                    if await MainActor.run(body: { self.monitoringIntents[service.agent] == .disabled }) {
                        // A pre-disable fetch may have resumed and restarted a passive source after
                        // removal completed. Stop that late work as well as dropping its snapshot.
                        await service.disconnect()
                        return
                    }
                    // The explicit hop also covers the connection reading's published properties
                    // when Release resumes this task away from the main actor.
                    await MainActor.run {
                        guard !Task.isCancelled, self.monitoringIntents[service.agent] != .disabled,
                              self.integrationIntentRevisions[service.agent, default: 0] == intentRevision else { return }
                        self.record(snapshot, observedAt: self.clock.now())
                    }
                }
            }
        }
    }

    private static var previewSnapshot: AgentSnapshot {
        // SwiftUI preview fixture: display data, not a timing decision.
        let now = Date()
        return AgentSnapshot(
            availability: .ready,
            sessions: [
                MonitoredSession(
                    threadID: "preview-input",
                    turnID: "turn-input",
                    projectName: "notchline",
                    title: "Confirm the final overlay interaction details",
                    preview: "Please choose whether the panel should remain open after a click.",
                    status: .inputNeeded,
                    startedAt: now.addingTimeInterval(-72)
                ),
                MonitoredSession(
                    threadID: "preview-running",
                    turnID: "turn-running",
                    projectName: "notchline",
                    title: "Implement the Codex status event adapter",
                    preview: "Checking event order, status mapping, and reconnect behavior…",
                    status: .running,
                    startedAt: now.addingTimeInterval(-384)
                )
            ],
            quota: QuotaSnapshot(
                remainingPercent: 72,
                resetsAt: Calendar.current.date(
                    byAdding: .day,
                    value: 3,
                    to: now
                ),
                todayTokens: 87_500_000
            ),
            diagnostic: "Preview data"
        )
    }
}
