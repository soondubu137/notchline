// Shared application state and display geometry for the Codex monitor.
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
    /// The window server's own handle for this display, when it has one.
    ///
    /// `id` above is a string because it is also a defaults key, and it falls
    /// back to a frame description on a screen that reports no display number.
    /// This is the unfalsified value, and `nil` where that fallback was taken —
    /// ``OverlayConcealment`` needs the display's bounds in window-server
    /// coordinates and has no way to derive them from `frame`.
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

    /// The height the menu bar occupies on this display.
    ///
    /// `NSScreen` offers two measurements of the band at the top of a notched
    /// screen and they disagree. `safeAreaInsets.top` is the camera housing —
    /// on a 14-inch M3 Pro at *More Space*, `38`. `frame.maxY -
    /// visibleFrame.maxY` is what the menu **bar** occupies, `40`, because
    /// `visibleFrame` also leaves a gap under the bar for window content. This
    /// takes the larger of the two, so it answers for the bar and not for the
    /// hardware; ``panelBandHeight`` is the one the panel is drawn at.
    var menuBarHeight: CGFloat {
        let occupiedTopHeight = max(0, frame.maxY - visibleFrame.maxY)
        let measuredHeight = max(occupiedTopHeight, safeAreaInsets.top)
        return measuredHeight >= 1
            ? measuredHeight
            : max(1, fallbackMenuBarHeight)
    }

    /// The band the collapsed panel fills — **the cut-out on a notched
    /// display, the menu bar on every other one.**
    ///
    /// The two are not the same height and the difference is visible. A
    /// notched screen's menu bar is a couple of points taller than the notch
    /// it surrounds (`40` against `38` on a 14-inch M3 Pro at *More Space*),
    /// so a panel drawn at the bar's height hangs below the hardware: the
    /// black continues past the cut-out's lower corners, and the collapsed
    /// surface reads as *taller than the notch* rather than as the notch
    /// carrying on sideways. The whole shape's claim is that it is the same
    /// object as the cut-out, and a couple of points of overhang is enough to
    /// break it — the lower corners are drawn where a person can lay them
    /// against the hardware's own.
    ///
    /// `safeAreaInsets.top` is the cut-out, and it is the measurement to take:
    /// the auxiliary areas beside the notch report the same height (`38` here)
    /// and this one survives the menu bar being auto-hidden, which takes the
    /// occupied band to zero while leaving the hardware where it is.
    ///
    /// **Not a fixed pixel count.** The cut-out is a shape of fixed
    /// millimetres and its height in points falls as the display scaling
    /// coarsens — `38` under *More Space*, about `32` by default, `22` at
    /// *Larger Text* — so a hard-coded `74` device pixels (`37` pt at 2x) is
    /// right at one step, short at the next, and taller than the entire menu
    /// bar at *Larger Text*. Reading it per display is what keeps it exact at
    /// every step.
    ///
    /// A display without a notch keeps the menu bar band: there is no hardware
    /// to agree with, the pill is an imitation of a cut-out, and it should
    /// fill the bar it sits in.
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

    /// The cut-out's trailing edge, in screen coordinates.
    ///
    /// The compact panel is pinned to this edge rather than to the display
    /// centre. Centring assumes the camera housing is centred on the panel --
    /// true on every Mac measured so far, but it also rounds the panel against
    /// the display's midpoint instead of against the one edge it has to meet,
    /// and a fraction of a point there is a visible seam beside a black cut-out.
    var centerOcclusionMaxX: CGFloat? {
        guard geometry == .notched,
              let auxiliaryTopRightArea,
              centerOcclusionWidth >= 1 else {
            return nil
        }

        return auxiliaryTopRightArea.minX
    }

    var configurationSummary: String {
        // The band the panel is actually drawn at, named for what it is on
        // this display: reporting the menu bar on a notched screen would print
        // a number two points off the panel standing under it.
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

/// The collapsed surface's trailing wing: one subagent badge per product,
/// sharing a slot with the elapsed timer exactly as the plain string this
/// replaced (`compactTrailingText`) used to share it.
///
/// One value rather than several views for the same reason the old string was
/// one: the panel's width is measured from it, so badges and a timer that
/// could independently disagree about what they drew would leave the width
/// composed from several readings instead of one.
/// What the collapsed surface draws on the far side of the notch.
///
/// **The badges are gone from it.** Every subagent in flight is counted by the
/// leading wing's second numeral now — one aggregate figure rather than a
/// tinted tile per product — so this end of the bar carries the reading and
/// nothing else (`compact-view-v2.md` §3, §4).
struct CompactTrailingReading: Equatable {
    var timerText: String?
    /// Whether those digits have stopped.
    ///
    /// A turn ending does not take the reading away: it freezes at the last
    /// value the timer showed and the ground it was already standing on fills,
    /// so the panel's edge does not move by a point at that instant. A filled
    /// ground is allowed here where the white flip is not, because "this figure
    /// has stopped" is a property of the figure rather than a comparison with
    /// its neighbours — and it is the one thing the digits cannot say alone
    /// (`compact-view-v2.md` §4.2).
    var isFrozen = false
    /// Whether a finished, unread turn is sitting under a mark that is drawing
    /// something else.
    ///
    /// That turn has no representative: the mark draws the most urgent status
    /// anywhere, and the reading belongs to whatever is being timed. The dot is
    /// its stand-in (§4.3).
    var buriesAFinishedTurn = false

    static let empty = CompactTrailingReading()

    var isEmpty: Bool { timerText == nil && !buriesAFinishedTurn }
}

enum PanelMetrics {
    static let referenceCompactHeight: CGFloat = 46
    /// The cut-out's upper fillet, as a share of its height.
    ///
    /// The notch does not end on a corner where its sides meet the top of the
    /// display: the glass curves back out into the screen. That curve is half
    /// the lower one, and drawing it at the lower radius is what makes an
    /// imitation read as a black box parked under the bezel instead of as the
    /// cut-out carrying on sideways.
    static let notchUpperRadiusRatio: CGFloat = 1.0 / 8
    /// The cut-out's lower corners, as a share of its height.
    static let notchLowerRadiusRatio: CGFloat = 1.0 / 4
    /// How far the lower corners' curvature is spread past a circular arc.
    ///
    /// A circular corner is tangent to the straight edge it leaves but not
    /// *curved* like it: curvature jumps from nothing to `1/r` at the join, in
    /// one step. The eye reads that step as a crease — the edge appears to
    /// stop being straight at a nameable point rather than to bend away — and
    /// it is at its most visible exactly where this shape puts it: a long
    /// straight run of pure black meeting a small radius against a lit
    /// wallpaper. It was the complaint about these two corners.
    ///
    /// So the corner is built the way Apple's own are, and the way Figma's
    /// *corner smoothing* control works: the curve starts `(1 + smoothing)`
    /// radii back along each straight edge instead of one, spends the extra
    /// length easing curvature up from zero, holds a circular arc of
    /// `90° × (1 - smoothing)` through the turn, and eases back down to zero
    /// into the other edge. Both control points of each easing segment lie
    /// **on** the straight edge, which is what makes the curvature there
    /// exactly zero and the join unfindable.
    ///
    /// `0.6` is the value Figma calls 60% and the closest single number to
    /// iOS's own continuous corners. `0` reproduces the plain circular corner
    /// exactly, arc and control handles alike, which is the reduction
    /// `theLowerCornersReduceToCircularArcsWithoutSmoothing` pins.
    ///
    /// **The two upper fillets keep their circular arc.** They are the trace
    /// of where the glass curves back out to the top of the screen (§3.3 of
    /// `docs/figma-design.md`), they are half the size, and they meet the
    /// screen's own top edge rather than a lit background — there is no crease
    /// to see, and widening them would widen the window they are drawn in.
    static let notchLowerCornerSmoothing: CGFloat = 0.6

    /// How far back along each straight edge a lower corner reaches.
    ///
    /// One radius for a circular corner; `1.6` radii at the smoothing above.
    /// This, not the radius, is what has to fit inside the panel's height and
    /// half its width.
    static func smoothCornerReach(radius: CGFloat) -> CGFloat {
        max(0, radius) * (1 + max(0, notchLowerCornerSmoothing))
    }
    /// How thick the optional surface outline is drawn.
    ///
    /// Drawn inside the contour rather than centred on it, so this is the full
    /// width of the line and none of it is lost to the clip.
    ///
    /// `0.8`, which does not land on a pixel boundary: at 2x it covers a pixel
    /// and most of its neighbour, so the line is antialiased rather than
    /// crisp. That is the intended look and not an oversight -- a hard
    /// single-pixel rule reads as a drawn border, and the softer edge is what
    /// makes this read as the black simply ending.
    ///
    /// A constant, not a share of the menu bar height like the two radii:
    /// those follow the hardware's shape, while a boundary does not get
    /// thicker because the menu bar got taller.
    static let surfaceOutlineWidth: CGFloat = 0.8
    static let expandedBaselineWidth: CGFloat = 610
    static let sessionRowHeight: CGFloat = 80
    /// A row that has left the list, drawn under the seam.
    ///
    /// **Half a live row, exactly** (`expanded-panel-v2.md` §2.1) — the
    /// plainest statement of "less than a live row" this surface can make. It
    /// was measured from the half-row it has to equal rather than from the one
    /// line it carries, so nothing about that line's contents moves it.
    static let retiredRowHeight: CGFloat = sessionRowHeight / 2
    /// The rule between the list and what has left it -- and, now, the
    /// footer's own spend line: the two closing bars this panel has, drawn
    /// alike down to the rule each shows only while it is open
    /// (`quota-footer-v2.md` §2).
    ///
    /// `9` + a `14` pt caption line + `9`.
    static let recentSeamHeight: CGFloat = 32
    /// How far a row's last glyphs take to fade out.
    ///
    /// One declaration, because two lines draw it by different means: the live
    /// row's title and body fade inside ``SessionRowTextView``'s own layer
    /// mask, and a retired row — one static line with no sweep to run — fades
    /// under a plain SwiftUI gradient. Written apart they would drift, and the
    /// two are three points from each other on the same panel.
    static let rowTrailingFadeWidth: CGFloat = 48
    /// The tallest the *live* session viewport is ever drawn.
    ///
    /// **A height rather than a row count.** `240` is what `sessionRowHeight ×
    /// 3` already was; saying it in points is what lets an open row (taller
    /// than `80`) still share the same viewport rather than needing a row
    /// count of its own.
    ///
    /// **The live list and the Recent queue no longer share one viewport or
    /// one scroller.** Each folds on its own past its own cap — see
    /// ``recentViewportCap`` for the queue's.
    static let sessionViewportCap: CGFloat = sessionRowHeight * 3
    /// The tallest the Recent queue's own viewport is ever drawn: five retired
    /// rows, half a live row each.
    static let recentViewportCap: CGFloat = retiredRowHeight * 5
    /// The panel's horizontal inset, collapsed and expanded alike.
    ///
    /// `12`, not the `24` this started at. The name says `expanded` because
    /// that is where it was first measured, but it has always governed both:
    /// the compact side margin, the wings around a cut-out, and the inset of
    /// the expanded rows and footer. Halving it moves every one of those, and
    /// the reference widths derived from it move with it — see
    /// `figma-design.md` §3.3 for the numbers this composes.
    static let expandedHorizontalPadding: CGFloat = 12
    /// The session row's block stops short of the panel's own inset, so its
    /// hover fill has a gutter rather than running into the edge.
    ///
    /// The row's padding makes that gutter back up again, which is why the two
    /// are written against each other instead of both being spelled `6`: a row's
    /// text lands on `expandedHorizontalPadding` — the same margin as the matrix
    /// above it and the footer below it — whatever that value becomes.
    ///
    /// **Both are constants again.** The `Colour bar` attribution moved the
    /// gutter to the panel's full inset so its rail would line up with the
    /// matrix above; with the four presentations reduced to the badge
    /// (`colour-v2.md` §6) there is no rail, and no form of the row gives up
    /// its `6 + 6`.
    static let sessionRowGutter: CGFloat = 6
    static let sessionRowPadding: CGFloat = expandedHorizontalPadding
        - sessionRowGutter

    /// The rail a scrolling list draws to report where its reader stands, and
    /// the lane it stands in.
    ///
    /// **The rail is never drawn on the panel's margin.** Its right edge lands
    /// exactly on ``expandedHorizontalPadding`` — the same column a row's text,
    /// the matrix above and the footer below all end on — so the `12` pt inset
    /// stays empty, as it is everywhere else on the panel. Standing it any
    /// further right would put it in that inset; standing it over the rows would
    /// put it on top of what it is reporting about.
    ///
    /// That lane has to come from somewhere, so a list that scrolls hands it
    /// back: the rows narrow by ``scrollRailLane`` for exactly as long as there
    /// is a rail, and take the width back the moment there is not.
    static let scrollRailWidth: CGFloat = 3
    /// Between a row's own trailing text and the rail beside it.
    static let scrollRailGap: CGFloat = 4
    static let scrollRailLane: CGFloat = scrollRailWidth + scrollRailGap

    /// The width either scrolling list (the live rows, the Recent queue) is
    /// drawn at: the panel's own width, less the gutter on each side.
    ///
    /// `isScrolling` is what takes the rail's lane out of it. A list that fits
    /// has no rail and gives up nothing.
    static func sessionViewportWidth(
        panelWidth: CGFloat,
        isScrolling: Bool = false
    ) -> CGFloat {
        panelWidth - sessionRowGutter * 2 - (isScrolling ? scrollRailLane : 0)
    }
    /// The row's three text lines, as the row lays them out.
    ///
    /// They live here rather than as literals in the view because the row's
    /// content block is composed from them, so a line height that changed in
    /// the view and not here would leave the wrong black under it.
    ///
    /// **The caption is `16` whether or not it carries a badge**
    /// (`panel-v2.md` §2). The badge is a point taller than the `11 pt` line it
    /// stands on, and holding the line at the badge's own height is what stops
    /// every row moving at the moment a second product connects. The row is
    /// still `80`: the content block absorbs it at `55`.
    static let sessionRowCaptionHeight: CGFloat = 16
    static let sessionRowTitleHeight: CGFloat = 17
    static let sessionRowPreviewHeight: CGFloat = 18
    static let sessionRowLineSpacing: CGFloat = 2

    /// The chip that names a product on a session row's caption line and on a
    /// retired row's breadcrumb (`colour-v2.md` §4).
    ///
    /// **Not on the footer.** A badge marks a product on something that is
    /// happening, against three other pieces of text; the quota table names a
    /// group in a table somebody opened, where the chip was the only saturated
    /// object among a column of grey figures.
    ///
    /// Its width is `6 + measured text + 6` and is never tabulated — the text
    /// is real rendered text, so the chip is measured by drawing it rather than
    /// by a table this file would have to keep in step with the font.
    static let productBadgeHeight: CGFloat = 16
    static let productBadgeRadius: CGFloat = 5
    static let productBadgePadding: CGFloat = 6
    static let expandedReadoutSpacing: CGFloat = 12
    static let expandedNotchClearance: CGFloat = 8
    /// A table line to the next one.
    static let footerCaptionSpacing: CGFloat = 5
    /// The spend line to whatever the control opened beneath it.
    static let footerRuleSpacing: CGFloat = 9
    /// One line of the footer's `11pt` caption.
    ///
    /// Measured rather than derived, for the same reason
    /// ``sessionRowCaptionHeight`` is: every footer height below is composed
    /// from it, so a caption that changed size in the view and not here would
    /// leave the wrong black under it. It is also the air between one product
    /// group and the next — one line of it.
    static let footerCaptionHeight: CGFloat = 14

    /// The black between the footer's last line and the panel's bottom edge.
    ///
    /// **One number for every shape, which it was not.** The four footers were
    /// four constants, and this margin was whatever each had left once its
    /// content was laid out: `6` with both products, `7` with Claude Code
    /// alone, `16` with Codex alone, `12` folded. So the panel's bottom edge
    /// stood at a different distance from the same line depending on what
    /// happened to be connected — and folding the rules away, which does not
    /// touch that line, moved the edge under it from `6` to `12`. Composing
    /// each height from its content plus this puts the edge in one place, and
    /// the value is the thinnest of the four rather than an average of them:
    /// at `6` the black reads as the panel's own edge, and at `12` or `16` as
    /// a gap left by something that was taken away.
    static let footerBottomMargin: CGFloat = 6

    /// One window's line in the table, and the gap after it.
    static let footerWindowRowHeight: CGFloat = footerCaptionHeight
        + footerCaptionSpacing
    /// The window column's indent inside the footer's own content box.
    ///
    /// One more step of ``expandedHorizontalPadding``, which puts a window's
    /// label at `24` on the panel — one step in from the `12` its product's
    /// name stands on. **Indentation carries the level on its own now**: the
    /// leader that used to help it was a second hairline five per cent away
    /// from the panel's own, and the weight of the product's name says the
    /// same thing without being drawn.
    static let footerWindowIndent: CGFloat = expandedHorizontalPadding
    /// The clear space between two columns on this footer.
    ///
    /// Twice ``expandedHorizontalPadding``, and it does both of the jobs a
    /// gutter has here: the least a product's name may stand from its own
    /// spend, and the space between a window's name and its share.
    static let footerColumnGutter: CGFloat = expandedHorizontalPadding * 2
    /// The window column, sized to the widest name a window can carry.
    ///
    /// `Current session` measures `81.56` at 11 pt Light, which is the widest
    /// this app draws; a per-model window is named for whatever model the
    /// account is capped on, so this is a column rather than a measurement.
    /// The label and the share share one box with the slack between them, so a
    /// longer name eats the gutter instead of colliding with the figure.
    static let footerWindowColumnWidth: CGFloat = 84
    /// The share column: `100% left` is `48.78`, and nothing wider can appear.
    static let footerShareColumnWidth: CGFloat = 52
    /// Where the share column's trailing edge lands, measured inside the
    /// footer's content box: `184` on the panel.
    ///
    /// **It is set rather than chosen.** It was `300`, measured when the panel
    /// was `520` wide; at `610` that is not a margin, an edge or a centre, and
    /// it left the share stranded between two gaps of `216` and `284` with
    /// `74` points of reading on the line. Composed from the columns it
    /// actually holds, the share lands beside the window it belongs to and the
    /// row reads as one phrase.
    static let footerShareTrailingEdge: CGFloat = footerWindowIndent
        + footerWindowColumnWidth
        + footerColumnGutter
        + footerShareColumnWidth

    /// The gear scales with the menu bar: `32` under a `46pt` bar, `20` under a
    /// `24pt` one. It is trailing-aligned inside the footer's content box, which
    /// is where macOS panels put their settings control.
    static func settingsButtonSize(compactHeight: CGFloat) -> CGFloat {
        let ratio = (compactHeight - 24) / (46 - 24)
        return min(32, max(20, 20 + ratio * 12))
    }

    /// The resting pill once it is hovered.
    ///
    /// It grows sideways to put the gear within reach, and does nothing else.
    /// With nothing connected there is no content to drop into a panel, so
    /// dropping one would open an empty box; the reason lives in Settings, and
    /// the gear is the one action that reaches it.
    ///
    /// **Composed symmetrically, like every other width on this panel.** It was
    /// added up instead — `leading + cut-out + trailing` — and the panel is
    /// centred while expanded, so that sum was never the drawing: the room
    /// beside the cut-out is `(width − cut-out) ÷ 2` on *both* sides. The
    /// trailing side is the wider of the two here, so this form is
    /// `cut-out + 2 × (8 + gear + 12)` and the gear keeps its `8` at every
    /// scaling step — `207` at `127 × 22`, `274` at `185 × 32`, `304` at the
    /// reference `200 × 46`, `316` at this machine's `220 × 38`.
    ///
    /// **Dropping the word is what makes that affordable.** The old sum
    /// reserved `Disconnected` on the leading side and drew it there
    /// (`drawsCompactStatusName` is `isExpanded || noNotch`), which put about
    /// `25` pt of that word behind the cut-out on a notched screen; with the
    /// name gone from every surface the leading side falls to `36.6`, the
    /// trailing side binds, and `304` is still `92` narrower than the form that
    /// had the fault. `figma-design.md` §6.4's `400` and its checklist's
    /// `400.6` are void with the rest (`expanded-header-v2.md` §5).
    static func restingExpandedWidth(
        geometry: DisplayGeometry,
        centerOcclusionWidth: CGFloat,
        compactHeight: CGFloat
    ) -> CGFloat {
        let trailing = expandedTrailingSideWidth(compactHeight: compactHeight)
        guard geometry == .notched, centerOcclusionWidth >= 1 else {
            // Nothing to be symmetric about: this form composes to itself, the
            // mark and the gear with one clearance between them.
            return ceil(
                expandedHorizontalPadding + statusMatrixSize + trailing
            )
        }
        return ceil(centerOcclusionWidth + trailing * 2)
    }

    /// The footer at rest: today's spend, the control, and nothing else.
    ///
    /// **`38`, at every connected form** — every product count, every window
    /// count, and every share. It is the only closed height the footer has:
    /// no window speaks, because there is no threshold for one to cross
    /// (`quota-footer-v2.md` §4), so nothing the machine observes changes this
    /// figure at all.
    ///
    /// **The spend line is `32` now, not `16`.** It draws the same bar the
    /// Recent seam does — ``recentSeamHeight`` — so the two closing lines
    /// this panel has match, and its own hover reaches the whole line rather
    /// than the `16pt` chevron alone.
    static let restingFooterHeight: CGFloat = recentSeamHeight
        + footerBottomMargin
    /// The chevron glyph's own square, inside the spend line's `32pt` bar.
    static let quotaFoldControlSize: CGFloat = 16

    /// Footer height: the resting line, or the table somebody opened.
    ///
    /// **`38`, or `19W + 28P + 33`**. The opened form composes as the spend
    /// line and its gap (`32 + 9`), then one group per product — a caption
    /// line at `14`, and `19` for each of its windows — with `14` of air
    /// between groups and `6` below the last line. Multiplied out that is
    /// `47 + Σ(14 + 19w) + 14(P − 1) + …`, which is `19W + 28P + 33`.
    ///
    /// **`28P` is the arithmetic `quota-footer-v2.md` was written with**, before
    /// §2 added a point to every product line so a badge would fit on it. The
    /// badge is gone from this footer and the line is a caption line again.
    ///
    /// **Nothing connected is no footer at all**: no products, no windows and
    /// no tokens is nothing to say, and a wing with nothing to say is removed
    /// rather than left blank (§8.5 question 07).
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
            + footerBottomMargin
    }

    /// The same height, asked of the rules themselves.
    static func footerHeight(rules: [FooterRule], isExpanded: Bool = false) -> CGFloat {
        footerHeight(
            productCount: rules.count,
            windowCount: rules.reduce(0) { $0 + $1.windows.count },
            isExpanded: isExpanded
        )
    }
    static let thinExpandedBodyHeight: CGFloat = 48
    /// The live viewport over a footer at rest: `308` at every connected
    /// form, every working-agent count and every share, with the Recent queue
    /// empty or folded.
    ///
    /// **Not the panel's cap any more.** With the live list and the Recent
    /// queue scrolling on their own (``sessionViewportCap``,
    /// ``recentViewportCap``), a queue somebody opens can stand on top of this
    /// — there is no longer one ceiling the whole panel answers to, only the
    /// two caps each part answers to on its own.
    static let expandedContentHeight: CGFloat = sessionViewportCap
        + restingFooterHeight
    static let thinExpandedContentHeight: CGFloat = thinExpandedBodyHeight
        + restingFooterHeight
    /// The status matrix is a fixed size, not a share of the menu bar.
    ///
    /// Taken from the indicator-to-text ratio at loaders.wtf — a 92pt indicator
    /// beside 72pt text — applied to the label's fixed 13pt: 13 × 1.2778 ≈ 16.6.
    /// Because the label never scaled with the bar either, tying only the
    /// indicator to it left the two drifting apart between a 46pt and a 24pt bar.
    static let statusMatrixSize: CGFloat = 16.6
    /// The notch label renders Light — measure it at the weight it draws at,
    /// or every compact width is over-reserved.
    private static let statusLabelFont = NSFont.systemFont(ofSize: 13, weight: .light)
    /// The elapsed timer uses tabular figures so its width stops changing every
    /// second; measure it with the same metrics.
    private static let timerFont = NSFont.monospacedDigitSystemFont(
        ofSize: 13,
        weight: .light
    )

    // MARK: - The aggregate counts column

    /// The sessions numeral, and the face the whole column is measured from.
    ///
    /// **`11` pt, at the optical size the column was drawn at.** The board's
    /// figures are SF Pro Display's: a `6.6` digit advance, a `7.85` cap, a
    /// `5.71` cap under it. AppKit hands out SF Pro *Text* at `11` pt — the
    /// optical cut macOS uses at small sizes, whose digits are `6.99` — so the
    /// drawing's own `6.6` is unreachable through ``NSFont/systemFont(ofSize:)``
    /// and every published width would have had to move to meet it. Asking
    /// CoreText for the display optical size gives `6.616` and a `7.750` cap:
    /// the drawing, to within a hundredth and a tenth.
    ///
    /// Regular rather than the reading's Light. Light measures `6.549` and
    /// medium `6.784`, so regular is also the weight whose digits land inside
    /// the `6.6` the column is billed at — the reservation and the ink agree by
    /// construction rather than by luck.
    static let countsSessionFont = countsFont(ofSize: 11)
    /// The subagents numeral: the same face, two steps down (`5.637` cap).
    static let countsSubagentFont = countsFont(ofSize: 8)

    /// One counts face: monospaced digits at the display optical size.
    ///
    /// Tabular figures for the reason the reading uses them — a proportional
    /// `1` would resize the leading wing every time a session opened
    /// (`compact-view-v2.md` §3.2 rule 05) — and the optical override so the
    /// digits measure what the column reserves.
    private static func countsFont(ofSize size: CGFloat) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        let descriptor = base.fontDescriptor.addingAttributes([
            NSFontDescriptor.AttributeName(kCTFontOpticalSizeAttribute as String):
                countsOpticalSize
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// Where the display cut begins. Anything past SF's `20` pt crossover
    /// gives the same digits; this is the smallest value that is plainly on
    /// the far side of it.
    private static let countsOpticalSize: CGFloat = 20

    /// Between the mark and the counts beside it.
    static let aggregateCountsGap: CGFloat = 4

    /// One numeral's width, which is every numeral's width.
    ///
    /// `6.616`, the drawn advance rather than the board's nominal `6.6`. The
    /// difference is under a hundredth of a point and it lands inside the
    /// single `ceil` every composed width takes, so the published totals stand:
    /// the notched bar is still `304` at one digit and `310` at two, and the
    /// pill is still `250` because its middle is a subtraction and absorbs it
    /// (`compact-view-v2.md` §6.1).
    static var countsDigitWidth: CGFloat {
        textWidth("8", font: countsSessionFont)
    }

    /// The column at the digits it is drawing: nothing, one numeral, or two.
    ///
    /// Zero sessions is no column at all — a bar at rest is one grey matrix and
    /// never a bar reading `0` (§3.2 rule 03). The subagent numeral is narrower
    /// than the sessions numeral above it and never widens this.
    static func countsColumnWidth(sessionCount: Int) -> CGFloat {
        guard sessionCount > 0 else { return 0 }
        return CGFloat(String(sessionCount).count) * countsDigitWidth
    }

    /// The column at two digits, which is what the pill holds open.
    static var reservedCountsColumnWidth: CGFloat { 2 * countsDigitWidth }

    /// The room the column stands in, gap and all.
    ///
    /// The gap belongs to the column rather than to the mark, so a bar with no
    /// rows gives back both together and the matrix is the whole wing. The pill
    /// holds the room at two digits whatever it is drawing, including nothing.
    static func countsSlotWidth(sessionCount: Int, reserved: Bool) -> CGFloat {
        if reserved { return aggregateCountsGap + reservedCountsColumnWidth }
        guard sessionCount > 0 else { return 0 }
        return aggregateCountsGap + countsColumnWidth(sessionCount: sessionCount)
    }

    /// Where the sessions numeral stands, measured up from the matrix's bottom
    /// edge.
    ///
    /// Two positions and one movement between them. With a subagent under it
    /// the numeral's cap-top is **on the matrix's top edge**; alone it is
    /// optically centred on the matrix's `16.6`, which puts its baseline
    /// exactly half the leftover above the bottom. So the rise when the first
    /// subagent starts is that same half — `4.425` at the drawn cap, where the
    /// board says `4.375` for a `7.85` one (§3.4).
    ///
    /// This takes a vertical move on the figure the eye is on, caused by
    /// something the user did not do. It is taken deliberately: the resting
    /// drawing is the one this surface spends most of its life showing.
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

    /// The band's leading side: the collapsed bar's own group, and nothing
    /// after it.
    ///
    /// **`53.8` at every agent count** (`colour-v2.md` §3). It used to grow
    /// `19.2` an agent, for one column of numbers per working agent in that
    /// agent's own inks; the decomposition is gone with the product hues that
    /// were the only thing on it saying whose a number was, so the band draws
    /// the aggregate mark and the accumulated totals and stops.
    ///
    /// The consequence is that **the leading group is now identical collapsed
    /// and expanded** — mark at `12`, totals at `32.6`, nothing appearing on
    /// hover and nothing moving.
    static let expandedLeadingSideWidth: CGFloat = expandedHorizontalPadding
        + statusMatrixSize
        + aggregateCountsGap
        + reservedCountsColumnWidth
        + expandedNotchClearance

    /// The band's trailing side: the one control this surface has.
    static func expandedTrailingSideWidth(compactHeight: CGFloat) -> CGFloat {
        expandedNotchClearance
            + settingsButtonSize(compactHeight: compactHeight)
            + expandedHorizontalPadding
    }

    /// The leading group at what it draws: the aggregate mark, and the counts
    /// where there are any.
    ///
    /// The gap goes with the column, so a bar with no rows is the matrix alone
    /// and gives back every point the numerals were taking.
    static func drawnLeadingGroupWidth(sessionCount: Int) -> CGFloat {
        let counts = countsColumnWidth(sessionCount: sessionCount)
        return statusMatrixSize + (counts > 0 ? aggregateCountsGap + counts : 0)
    }

    /// The leading group at the room the pill holds open for it: `33.8`.
    static var reservedLeadingGroupWidth: CGFloat {
        statusMatrixSize + aggregateCountsGap + reservedCountsColumnWidth
    }

    // MARK: - The pill's middle

    /// The face the name of the work is drawn in.
    ///
    /// `13` pt Light — the face the status name used to take, and the one this
    /// document's own measurements were made against: `notchline` is `55.10`
    /// here, which is the figure `compact-view-v2.md` §6.3 fits the middle
    /// around. Naming the face therefore moves nothing.
    static let projectNameFont = statusLabelFont

    /// How long the name is faded out over where the middle ends.
    ///
    /// A name too long to fit fades rather than clipping or ellipsing: a reader
    /// can act on the start of a name, and an ellipsis would spend three glyphs
    /// saying that a name exists.
    static let projectNameFadeWidth: CGFloat = 12

    /// How long each Project is named before the next one.
    static let projectNameInterval: TimeInterval = 5





    /// The subagent badge: font, minimum size, and the padding that lets a
    /// two-digit count grow it rather than clip it.
    ///
    /// `dual-agent-design.md` §10 draws the badge at a fixed `15 × 15` for the
    /// single-digit counts every mockup shows; that figure is this type's
    /// floor rather than a hardcoded width -- `figma-design.md` §4.6's one
    /// lesson is that a slot must grow to fit what it actually draws, and a
    /// count of `10` or more is real once a thread has spawned enough
    /// subagents.
    static let subagentBadgeFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
    static let subagentBadgeMinSize: CGFloat = 15
    static let subagentBadgeCornerRadius: CGFloat = 4
    static let subagentBadgeHorizontalPadding: CGFloat = 4
    /// Between the badges and the timer they share the trailing slot with.
    static let subagentBadgeTimerSpacing: CGFloat = 8

    /// The ground an elapsed reading sits on, which is what tells the four
    /// session states apart (`figma-design.md` page 14).
    ///
    /// **The badge's own tile, at reading width.** Presence and brightness were
    /// the only two channels the slot used, and both are comparisons: a row
    /// with no timer only reads as finished beside a row that has one, and a
    /// white timer only reads as waiting beside a dimmer one. Cover the
    /// neighbours and neither answer survives. A ground is a silhouette, which
    /// one row can answer on its own -- bare while the turn runs, white while
    /// it wants a person, dim once it has finished.
    ///
    /// Deliberately the same geometry as ``subagentBadgeCornerRadius`` and
    /// ``subagentBadgeHorizontalPadding`` rather than numbers of its own: the
    /// badge already draws a reading on a ground that flips when a person is
    /// wanted, and this is that mark answering for the turn as well as for its
    /// subagents. Two marks in one family, not two families.
    static let readingGroundHeight: CGFloat = 16
    static var readingGroundCornerRadius: CGFloat { subagentBadgeCornerRadius }
    static var readingGroundPadding: CGFloat { subagentBadgeHorizontalPadding }
    /// What a ground adds to the reading it wraps.
    static var readingGroundWidthCost: CGFloat { readingGroundPadding * 2 }

    /// The word on a waiting row's bright ground.
    ///
    /// Not the timer's monospaced-digit face: this draws a name rather than a
    /// figure. ~~**Semibold rather than the Medium it was**, and that is a
    /// correction for the ground under it rather than a change of emphasis:
    /// dark glyphs on a light field read a weight lighter than light glyphs on
    /// a dark one, so matching the perceived weight of the `13 pt` Medium title
    /// beside it costs one step up.~~
    ///
    /// **Superseded — Medium, the same weight the answers take.** The
    /// correction was sound about the effect and wrong about its scope: the
    /// affirmative this mark grows into (§3.1) sits on the *same*
    /// ``NotchPalette/brightGround`` with the *same*
    /// ``NotchPalette/onBrightGround`` ink, and it was never stepped up. So the
    /// weight was not a correction applied to a light field, it was one control
    /// drawn two ways — the divergence ``controlCornerRadius`` had already been
    /// pulled out of. If dark-on-light really does want a step, it wants it in
    /// both places and belongs to the ground rather than to the mark.
    static let waitingMarkFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    /// The mark is a control, so it is built like one rather than like the
    /// readings it shares the slot with.
    ///
    /// ~~Twice the ``readingGroundHeight`` it used to take, and cut like the
    /// answer it becomes rather than like the reading it replaced. That leaves
    /// it `4` taller than ``answerRowHeight`` — the affirmative it grows into
    /// when the row opens (`answer-in-notch.md` §3.1) — which is the one number
    /// here settled by how it feels under the pointer rather than by the system
    /// it belongs to.~~
    ///
    /// **Superseded — it *is* ``answerRowHeight``, and derived rather than
    /// written down.** `32` was the reading's tile doubled, which is a number
    /// about the mark's ancestry rather than about what it now is; against the
    /// answer row it left the one object §3.1 describes travelling down the row
    /// and shedding four points on the way. The corner, the padding and the
    /// weight are already the answers'; the height was the last of the four
    /// still holding out, and "how it feels under the pointer" is not a
    /// measurement that outranks the three.
    ///
    /// ~~On ``readingGroundHeight``'s own `0.25` corner ratio~~ — **superseded**:
    /// that ratio was the badge family's, inherited from the reading this
    /// replaced, and at `32` tall it drew an `8` pt pill above a row of `4` pt
    /// tiles. The corner and the padding are ``controlCornerRadius`` and
    /// ``controlHorizontalPadding`` now, which the answers already took.
    static var waitingMarkHeight: CGFloat { answerRowHeight }
    static var waitingMarkCornerRadius: CGFloat { controlCornerRadius }
    static var waitingMarkPadding: CGFloat { controlHorizontalPadding }

    /// What the mark takes, and it is one width whichever word it holds.
    ///
    /// ~~**Fixed, and that is the whole point.**~~ ~~Superseded — it hugs the
    /// one word it will ever show.~~ **Fixed again, and for a different
    /// reason.** The first reservation was forced: the word changed to `Answer`
    /// or `Read` under the pointer, *nothing on a row may move* as a pointer
    /// passes over it (`answer-in-notch.md` §3.3), so the ground was measured
    /// against the longest phrase it might have to hold — `113 pt` of the
    /// brightest value on the panel even for a four-letter word, `19%` of the
    /// row's content box spent naming a condition. That is what hugging was
    /// right to remove, and the word no longer changes under the pointer
    /// anyway: ``waitingMarkWord(for:canBeAnswered:)`` decides it from the
    /// row's own request, at rest.
    ///
    /// What hugging cost was the **list**. Three verbs of three lengths, each
    /// right-aligned to its row's trailing edge, left a ragged column down a
    /// mixed queue — and these are one control appearing once per row, not
    /// three controls. So they draw one silhouette: the widest of the three,
    /// which is `Approve` at `76`. `Read` pays `20 pt` for that, against the
    /// `57` the phrase used to cost it, and the reservation is now over the
    /// three words the mark can actually say rather than over the four strings
    /// it once might have.
    ///
    /// **Derived rather than written down**, so a fourth word cannot quietly
    /// outgrow it — the test pins that every word
    /// ``waitingMarkWord(for:canBeAnswered:)`` can return fits.
    static let waitingMarkWidth: CGFloat = waitingMarkWords
        .map(huggedWaitingMarkWidth)
        .max() ?? 0

    /// Every word the mark can say, which is what ``waitingMarkWidth`` is the
    /// widest of.
    static let waitingMarkWords = [
        waitingMarkApproveWord, waitingMarkAnswerWord, waitingMarkReadWord
    ]

    /// What one word would take if the ground still hugged it: the string as
    /// measured, plus ``waitingMarkPadding`` a side.
    ///
    /// Only the widest word is drawn with that padding; the rest keep the width
    /// and centre inside it, which is what makes the column straight.
    static func huggedWaitingMarkWidth(_ word: String) -> CGFloat {
        ceil(textWidth(word, font: waitingMarkFont) + waitingMarkPadding * 2)
    }

    /// What the mark says on a row that wants a person.
    ///
    /// **A verb, and it offers the act rather than naming the condition.** The
    /// two status names it replaces were the longest strings on this panel and
    /// both of them described a state; what a person does about either is one
    /// act, and this is the word for it. The distinction the names carried is
    /// not lost — it decides which verb, and `SessionStatus/displayName` still
    /// spells both of them for the mark's accessibility label.
    ///
    /// `Read` is not a fourth state but the honest answer wherever the act is
    /// not available: a request no connection is being held open for can only
    /// be read here and answered in its product (§11 rule 03). Offering
    /// `Approve` on a row that cannot approve is exactly the quiet promise that
    /// rule forbids, which is why this is asked of the request and not of the
    /// status alone.
    ///
    /// It lives here rather than in the view because it is vocabulary, it
    /// belongs beside the three words themselves, and a private view cannot be
    /// asked what it would say.
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

    /// What the mark says where the wait is a consent.
    static let waitingMarkApproveWord = "Approve"
    /// And where it is a question, whose answer is words rather than consent.
    static let waitingMarkAnswerWord = "Answer"
    /// And where it can only be read — §11, and the three are per row rather
    /// than per product, because what a row can do is a fact about the request
    /// it is holding.
    static let waitingMarkReadWord = "Read"

    /// One badge's width, hugging its digits at the minimum size and growing
    /// only when a wider count needs it.
    static func subagentBadgeWidth(_ count: Int) -> CGFloat {
        let measured = textWidth("\(count)", font: subagentBadgeFont)
            + subagentBadgeHorizontalPadding * 2
        return max(subagentBadgeMinSize, ceil(measured))
    }

    /// Everything the collapsed trailing slot draws: the badges, the timer, and
    /// the gap between them when both are present.
    ///
    /// **One expression for both collapsed forms.** It was two while the
    /// notch-less pill billed the timer for a `00:00:00` slot and the notched
    /// bar billed it for its digits; now that neither reserves, the slot is the
    /// reading on every surface that has one, and a second expression could
    /// only be a second answer to a question with one.
    ///
    /// **The reading carries its ground's room, and its ground is never
    /// filled.** The collapsed reading is drawn one way for every state -- the
    /// waiting flip that used to put it on white was taken out of the bar, and
    /// only the expanded rows read their grounds against each other now. What
    /// stays is the `.clear` ``ReadingGround`` around it, whose padding is what
    /// ``readingGroundWidthCost`` bills for here.
    ///
    /// **Nothing here is held open.** The panel steps outwards when the timer
    /// gains a digit and steps back in when it loses one. The notched bar takes that
    /// on its trailing wing alone, and its leading edge cannot feel any of it
    /// because ``compactTrailingWingWidth(trailing:)`` is a whole number of
    /// points and cancels out of the sum that places it; the pill is centred,
    /// so it takes half on each edge and glides.
    ///
    /// **And it leaves the reading's own leading edge standing still** in the
    /// panel's own coordinates. Every term here is a whole number —
    /// ``drawnCompactReadingWidth(_:)`` ceils the glyph box the way the raster
    /// does — so the notched wing is exactly `reading + 12 + 8` with no
    /// rounding of its own and the reading starts ``expandedNotchClearance``
    /// past the cut-out at every length it can draw, while on the pill the
    /// panel and the box grow by the same amount and their difference is what
    /// places the reading. A digit therefore appears at the trailing end of the
    /// reading and pushes the edge out in front of it, rather than sliding the
    /// whole figure sideways.
    static func drawnTrailingReadingWidth(_ trailing: CompactTrailingReading) -> CGFloat {
        let dot = trailing.buriesAFinishedTurn ? buriedFinishDotSize : 0
        guard let timerText = trailing.timerText else {
            // The dot alone, with nothing for its gap to stand off: each gap on
            // this surface exists only where content stands on both sides of it.
            return dot
        }
        guard trailing.buriesAFinishedTurn else {
            return drawnCompactReadingWidth(timerText)
        }
        return dot + buriedFinishDotSpacing + drawnCompactReadingWidth(timerText)
    }

    /// The buried-finish dot, and the gap it stands off the digits by.
    ///
    /// `4` in the wing's own `#7C7C80`, `8` before the reading. Both whole
    /// numbers, so the wing stays integral and the leading edge still cannot
    /// feel anything the trailing side does
    /// (`theTrailingWingIsWholePointsSoTheLeadingEdgeCannotMove`).
    static let buriedFinishDotSize: CGFloat = 4
    static let buriedFinishDotSpacing: CGFloat = 8
    /// What the dot costs a wing that is also drawing a reading.
    static var buriedFinishSlotWidth: CGFloat {
        buriedFinishDotSize + buriedFinishDotSpacing
    }


        /// Compact content trailing the notch, including its own trailing padding.
    ///
    /// Zero unless the collapsed surface has a reading to put there -- an
    /// elapsed value, a subagent badge, or both. The usage ring used
    /// to sit here unconditionally, which meant an idle notched display
    /// rendered a blank wing that read as a second, fake notch.
    static func compactTrailingWidth(trailing: CompactTrailingReading) -> CGFloat {
        guard !trailing.isEmpty else { return 0 }
        return drawnTrailingReadingWidth(trailing) + expandedHorizontalPadding
    }

    /// How far the compact body reaches past the cut-out's trailing edge.
    ///
    /// A notched panel is pinned to the notch, not the screen: its right edge
    /// sits on the cut-out's right edge, plus whatever trailing wing is drawn.
    /// Everything that rounds -- the ceiled width, a cut-out that is not
    /// perfectly centred -- is absorbed by the leading wing, which is padding
    /// and can take it, rather than by the edge that has to meet the hardware.
    ///
    /// **With nothing to draw out there the wing is nothing**: the body's
    /// right edge lands exactly on the reported one, whether or not the
    /// leading wing is drawing marks.
    ///
    /// It used to step a little past it -- `panelHeight / 16`, `3` pt under a
    /// `38` pt cut-out -- on the argument that `auxiliaryTopRightArea`
    /// describes the cut-out as a rectangle while the hardware flares outward
    /// where the glass meets the top of the display, leaving an edge on the
    /// reported value with the top of its shoulder fillet drawn behind that
    /// flare. **That reasoning was about the top of the shoulder and the step
    /// moved the whole edge.** The flare is a few points tall at the very top
    /// of the screen; the rest of the stepped-out edge -- most of the height,
    /// the lower corner included -- is nowhere near it, and shows as a sliver
    /// of black protruding past the notch onto the wallpaper. A hairline
    /// clipped at the top under an optional outline is the smaller cost than a
    /// visible nub beside the hardware, so the step is gone and the trailing
    /// edge is the reported edge.
    ///
    /// **A whole number of points, and that is what holds the leading edge
    /// still.** The panel is pinned by its trailing edge, so its leading one is
    /// `trailingAnchor − bodyWidth` — and the body width is ceiled while the
    /// anchor was not, so the two rounded apart and the leading edge drifted by
    /// a fraction of a point every time this wing changed. Ceiled here, the
    /// wing enters both sums as the same integer: `ceil(leading + occlusion +
    /// wing)` is `ceil(leading + occlusion) + wing`, the wing cancels, and the
    /// leading edge is a constant that no trailing reading can reach. It is
    /// what lets `theLeadingMatrixNeverMovesWhateverTheCountsDo` assert an
    /// exact edge across a timer arriving, rather than "within a point".
    ///
    /// It no longer answers to whether the surface is drawing marks, or to the
    /// panel's height: an empty trailing reading is an empty wing on every
    /// form, so the resting cut-out and a notch with a leading wing put their
    /// right edge in the same place.
    static func compactTrailingWingWidth(
        trailing: CompactTrailingReading
    ) -> CGFloat {
        let content = compactTrailingWidth(trailing: trailing)
        guard content > 0 else { return 0 }
        return ceil(content + expandedNotchClearance)
    }

    /// Leading wing on a notched display: padding, the marks, and the clearance.
    ///
    /// Zero marks draws nothing at all. A notched display at rest hides the
    /// whole wing rather than parking a grey mark beside the cut-out — the
    /// cut-out is already a shape on the screen, and a second one next to it
    /// carries no information. A no-notch display keeps its mark instead,
    /// because a control that vanishes from the menu bar takes its position
    /// with it and everything to its left slides over.
    ///
    /// **It is a switch and not a count.** There is one mark for every product
    /// at once, so the wing is either drawn or it is not: with `Hide the wings`
    /// on it stays behind the cut-out until something is waiting on a person,
    /// and comes out whole (`compact-view-v2.md` §9). What it costs is no
    /// longer a count of products either — it is the mark, and the numerals
    /// beside it if the list has any rows.
    ///
    /// `47.2` at one session digit, `53.8` at two, `36.6` with no rows at all.
    private static func notchedLeadingWidth(
        drawsMark: Bool,
        sessionCount: Int
    ) -> CGFloat {
        guard drawsMark else { return 0 }
        return expandedHorizontalPadding
            + drawnLeadingGroupWidth(sessionCount: sessionCount)
            + expandedNotchClearance
    }

    /// The contour's upper fillet — and, because of the shape it draws, the
    /// width of the shoulder it needs on each side of the panel.
    ///
    /// `PanelContour` spans its rect only along the very top edge and then
    /// curves inward: its straight sides sit one shoulder in. So every width in
    /// this type describes the **body** — the black surface, the thing that has
    /// to line up with the cut-out — and the window is one shoulder wider on
    /// each side to leave them somewhere to be drawn. Sizing the window to the
    /// body instead was the bug: the compact panel's right edge landed a
    /// shoulder inside the cut-out, and its bottom-right corner curve took
    /// another radius off that, which read as a bite out of the notch.
    ///
    /// Both radii are shares of the panel's own height rather than constants,
    /// because that is how the hardware behaves. The cut-out is a fixed shape
    /// in millimetres and it shrinks in points as the display scaling coarsens
    /// — `220 × 38` at *More Space* down to `127 × 22` at *Larger Text*. A
    /// pinned radius is therefore right at one scaling and too round at every
    /// other one, which is what a fixed `10` was doing on notched displays.
    ///
    /// `panelHeight` is ``DisplayOption/panelBandHeight``, which **is** the
    /// cut-out's height on a notched display, so on the screens these radii
    /// have to agree with they are shares of the very shape they trace.
    static func surfaceShoulderRadius(panelHeight: CGFloat) -> CGFloat {
        max(0, panelHeight) * notchUpperRadiusRatio
    }

    /// The contour's lower corners, which are the ones the eye compares with
    /// the cut-out: the notch's own bottom corners sit under the panel, so this
    /// curve is the only place the shape is checkable against the hardware.
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
        // Rows on the monitored list. The collapsed leading wing is billed for
        // the numerals that counts them (`countsColumnWidth(sessionCount:)`),
        // and for nothing per product: one mark stands for every product at
        // once, so nothing on this form answers to how many are installed.
        sessionCount: Int = 0,
        // Whether the *collapsed notched* bar draws its mark at all. False in
        // exactly two states: a notched display resting with nothing connected,
        // and one that has given up its wings while nothing is waiting on a
        // person (`MonitorStore.drawsCompactMarks`).
        drawsMark: Bool = true,
        expandsToPillOnly: Bool = false,
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
                // Notched display with no measurable cut-out: nothing to wrap
                // around, so lay it out as an emulated notch instead.
                return CGSize(
                    width: fixedCompactWidth(for: status),
                    height: compactHeight
                )
            }
            // A notched panel wraps the cut-out, so its width is one fixed
            // obstacle with a wing on each side -- and each wing is exactly as
            // wide as what it is drawing. Nothing on this form is reserved:
            // both edges answer to their own wing's contents and to nothing
            // else.
            let width = notchedLeadingWidth(
                drawsMark: drawsMark,
                sessionCount: sessionCount
            )
                + centerOcclusionWidth
                + compactTrailingWingWidth(trailing: trailing)
            return CGSize(width: ceil(width), height: compactHeight)
        case .noNotch:
            return CGSize(
                width: fixedCompactWidth(for: status),
                height: compactHeight
            )
        }
    }

    /// What the collapsed reading draws at, ground and all.
    ///
    /// **One expression, because neither form holds a slot for it any more.**
    /// The notched bar hugs its reading (``drawnTrailingReadingWidth(_:)``) and
    /// so, now, does the notch-less pill
    /// (``fixedCompactWidth(for:matrixCount:trailing:)``), so this is what both
    /// are composed from and what the first-run drawing puts its pin under. The
    /// `00:00:00` template that used to stand beside it — `timerReservationWidth`,
    /// the Medium slot plus the ground, `65.91` — was the pill's alone and left
    /// with the reservation it existed for.
    ///
    /// **Ceiled, because the raster is.** `NotchTextRaster.textSize` rounds the
    /// glyph box up before drawing into it, so a composed width taking the bare
    /// metric is a fraction short of the ink — invisible while a reservation
    /// covered it, and the last digit against the panel edge once the wing
    /// hugs. The ground's own cost is already whole.
    static func drawnCompactReadingWidth(_ text: String) -> CGFloat {
        ceil(textWidth(text, font: timerFont)) + readingGroundWidthCost
    }

    /// Between two product matrices, when both are drawn.
    ///
    /// The expanded header alone: the collapsed forms draw one mark for every
    /// product at once and have no pair to space.
    static let compactMatrixSpacing: CGFloat = 6

    /// The notch-less pill: **one width in every connected state**.
    ///
    /// `230` whatever is running, whatever is waiting, however many rows are
    /// open and however long the reading is.
    ///
    /// **The two forms are inverses, and this is the half that cannot move its
    /// ends.** The notched bar has a fixed middle and moving ends: it is pinned
    /// to the cut-out, so a wing growing pushes an edge that nothing is
    /// measured from. The pill is centred on the display and pinned to nothing,
    /// so every point either end took would be taken from *both* edges at once
    /// and its whole contents would travel with them. So its ends are anchored
    /// — the leading group at `33.8`, the trailing reading at `12` from the
    /// trailing edge — and the middle gives way instead
    /// (``pillMiddleWidth(trailing:)``).
    ///
    /// **The reservation comes back, and this time the room is not empty.**
    /// `figma-design.md` §6.4 removed it on a finding that was correct when
    /// made — a reservation protects a neighbour, and nothing in the menu bar
    /// is laid out from this window — but both halves of that argument turned
    /// on the room standing empty. It now holds the only thing on this surface
    /// a person reads as a word, and what it protects is the pill's own
    /// contents: the mark, the counts and the reading stand in one place in
    /// every state, and the only thing that changes anywhere is how much of a
    /// name fits (`compact-view-v2.md` §6.1).
    ///
    /// `Disconnected` is the one state still sized to itself. Nothing can
    /// follow it and there is no product behind it, so neither `8` of clearance
    /// applies — each exists only where content stands on both sides of it.
    static func fixedCompactWidth(for status: MonitorStatus) -> CGFloat {
        status == .disconnected ? disconnectedPillWidth : pillBodyWidth
    }

    /// `230`, the width above.
    ///
    /// Stated rather than composed, because it is the *sum* that is the
    /// contract here and the middle is what absorbs everything else. See
    /// ``pillMiddleWidth(trailing:)``.
    static let pillBodyWidth: CGFloat = 230

    /// `41` — the mark, and a margin either side of it.
    static var disconnectedPillWidth: CGFloat {
        ceil(expandedHorizontalPadding + statusMatrixSize + expandedHorizontalPadding)
    }

    /// The middle, which is a subtraction and nothing else.
    ///
    /// No cap, no reservation, no constant of its own: it is whatever `250`
    /// has left once the two anchored ends and their clearances are taken out,
    /// so a reading gaining a digit narrows the name by exactly that digit and
    /// moves nothing else on the surface. `176.2` with nothing being timed,
    /// `140.2` at `1:23`, `112.2` at `10:00:00`.
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



    /// What either surface can say while an agent is connected.
    ///
    /// Both read the same aggregate (`MonitorStore.status`), so this is the
    /// collapsed pill's vocabulary and the expanded header's alike — the pill
    /// draws the short name and the header the long one. `Disconnected` is out
    /// of both: with nothing connected the collapsed form is the resting pill
    /// and the expanded form is that same pill widened
    /// (``MonitorStore/expandsToPillOnly``), and neither is sized from here.
    static let workingStatuses = MonitorStatus.collapsedReachable
        .subtracting([.disconnected])

    static func expandedHeight(compactHeight: CGFloat) -> CGFloat {
        compactHeight + expandedContentHeight
    }

    /// What the live list asks for, before its own viewport caps it.
    ///
    /// **With nothing live the list draws its own apology**, `48` in place of
    /// the rows: what has left is not what is running, and the one line that
    /// says nothing is running has to be sayable on its own — the Recent queue
    /// is a section of its own now and no longer what an empty live list falls
    /// back on.
    static func sessionListContentHeight(
        liveRowCount: Int,
        openRowHeight: CGFloat? = nil
    ) -> CGFloat {
        // One of the live rows may be open, and an open row is taller than the
        // `80` every row is billed at above. It is added as a difference rather
        // than counted separately so that a row opening cannot also change how
        // many rows there are.
        let opened = liveRowCount > 0 && openRowHeight != nil
            ? (openRowHeight ?? sessionRowHeight) - sessionRowHeight
            : 0
        return liveRowCount > 0
            ? sessionRowHeight * CGFloat(liveRowCount) + opened
            : thinExpandedBodyHeight
    }

    /// That content, capped at what the live viewport draws: at least one
    /// row's worth (the apology, with nothing live), at most three.
    static func sessionViewportHeight(
        liveRowCount: Int,
        openRowHeight: CGFloat? = nil
    ) -> CGFloat {
        min(
            sessionListContentHeight(
                liveRowCount: liveRowCount,
                openRowHeight: openRowHeight
            ),
            sessionViewportCap
        )
    }

    /// What the Recent queue's own list asks for, before its viewport caps it.
    /// Nothing while there are no retired rows — a seam is drawn only once
    /// there is something behind it.
    static func recentContentHeight(retiredRowCount: Int) -> CGFloat {
        retiredRowHeight * CGFloat(max(retiredRowCount, 0))
    }

    /// That content, capped at what the Recent viewport draws: past five
    /// retired rows, the queue scrolls on its own rather than growing the
    /// panel further.
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

    /// What an open row's body may weigh.
    ///
    /// **Bounded by the viewport, not by a line count** (`answer-in-notch.md`
    /// §4.1). The superseded draft capped the request at three lines and faded
    /// the rest, which is one number per form and a fade over a `--force` nobody
    /// read. This is one number for every form:
    ///
    /// ```text
    /// 140 = viewport 240 − (12.5 + caption 16 + 2 + title 17 + 2) − (10 + answer row 28 + 12.5)
    /// ```
    ///
    /// Below it the body hugs its content, so a one-line question makes a `117`
    /// pt row and the rows under it stay on the list.
    static let requestBodyMaximumHeight: CGFloat = 140

    /// One option on a question, numeral and label and description on one line.
    static let optionRowHeight: CGFloat = 24

    /// The row of answers at the foot of an open row.
    ///
    /// ~~The waiting mark's own `16` grown by ``PanelMotion``'s slot curve as
    /// the ground travels down the row~~ — the mark is `28` too now, so the
    /// ground travels without resizing at all. One object moving, which is why
    /// this is the same ground rather than a second one (`answer-in-notch.md`
    /// §3.1), and it is ``waitingMarkHeight`` that reads this rather than the
    /// other way round: the answer row is the control's size on this surface,
    /// and the mark is that control in its collapsed position.
    static let answerRowHeight: CGFloat = 28

    /// The corner every control on this surface takes, and the horizontal
    /// padding around the one word it holds.
    ///
    /// **One pair for the mark on a row and for the answers inside it**, which
    /// is the same argument ``answerRowHeight`` makes about the height: the
    /// ground the pointer presses on the caption line *is* the ground that
    /// travels down to the answer row, so a mark and an answer cut to different
    /// corners would be two objects rather than one moving. The padding was
    /// already `12` in both places and the corner was not — `8` on the mark and
    /// `4` on the answers, which read as a pill above a set of tiles.
    ///
    /// ~~The mark stays `4` taller than the answer it becomes
    /// (``waitingMarkHeight``); that difference is deliberate and is the one
    /// number here settled by how it feels under the pointer.~~
    ///
    /// **Superseded — the height went the same way, and so did the weight.**
    /// The mark is ``answerRowHeight`` and ``waitingMarkFont`` is the answers'
    /// Medium, so the four properties that make a control on this surface —
    /// height, corner, padding, weight — are now one set with one exception:
    /// the mark reserves ``waitingMarkWidth`` for its three verbs while an
    /// answer hugs its own word, because a mark appears once per row and must
    /// draw a straight column down a mixed queue.
    static let controlCornerRadius: CGFloat = 4
    static let controlHorizontalPadding: CGFloat = 12

    /// Everything an open row is besides its body.
    ///
    /// `12.5 + 16 + 2 + 17 + 2` above and `10 + 28 + 12.5` below — the caption,
    /// the title and the answer row, none of which changes with the request.
    static let openRowFixedHeight: CGFloat = 12.5 + sessionRowCaptionHeight
        + sessionRowLineSpacing + sessionRowTitleHeight + sessionRowLineSpacing
        + 10 + answerRowHeight + 12.5

    /// The width an open row's body is *wrapped* at.
    ///
    /// `610 − 2 × 12`, which is also `598 − 2 × 6`: the row block inside the
    /// list's own scroller, minus the row's own padding. It is a derived figure
    /// and has been one since V1 — the panel does not move at any agent or
    /// product count (`colour-v2.md` §3).
    ///
    /// **Less the rail's lane, unconditionally**, even though the rail is not
    /// always there. An open row is what pushes the live list past its cap, so
    /// the list's width would otherwise depend on a height measured at that
    /// width — the row is only narrow because it is tall, and only tall because
    /// it was measured wide. Wrapping at the narrower of the two settles it: the
    /// lines are laid out once, and the row draws exactly those lines whether or
    /// not the pass ended up with a rail. A list that does not scroll simply
    /// leaves ``scrollRailLane`` of slack past the last glyph, which is `7`
    /// points of empty ground nobody can see.
    static var requestBodyWidth: CGFloat {
        expandedBaselineWidth - expandedHorizontalPadding * 2 - scrollRailLane
    }

    /// §4.2's prose setting: sentences a person is meant to read.
    static let proseFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    /// And its machine text: strings a machine will execute.
    static let machineTextFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let machineTextHorizontalInset: CGFloat = 10
    static let machineTextVerticalInset: CGFloat = 8
    static let machineTextCornerRadius: CGFloat = 4
    /// Between the question and the options under it.
    static let optionListSpacing: CGFloat = 4

    /// How tall one line of a body is, which is a fact about its setting.
    ///
    /// `17` for prose and `18` for machine text — the second being SF Mono's own
    /// `12/18`, where the extra point is what keeps a wrapped command legible.
    static func requestLineHeight(for setting: AgentRequest.Setting) -> CGFloat {
        switch setting {
        case .prose: sessionRowTitleHeight
        case .machineText: 18
        }
    }

    /// How tall an open row is, holding a body of this height.
    ///
    /// **Not `openRowHeight(requestLines:)`**, which `expanded-panel-v2.md` §10
    /// still owes: that one counted lines, and §4.1 does not. The cap is the
    /// viewport itself, so the tallest an open row can be is the whole of what
    /// the list can show — and every height in §12 is this one arithmetic.
    static func openRowHeight(bodyHeight: CGFloat) -> CGFloat {
        openRowFixedHeight + min(max(bodyHeight, 0), requestBodyMaximumHeight)
    }

    /// The three sections stacked, none of them capping the others: the live
    /// viewport (at most three rows), the Recent section (nothing, a seam, or
    /// a seam and up to five rows of its own), and the footer (uncapped —
    /// however tall the quota table needs to be). There is no longer a ceiling
    /// over the sum of the three; each answers only to its own cap.
    static func expandedContentHeight(
        liveRowCount: Int,
        openRowHeight: CGFloat? = nil,
        retiredRowCount: Int = 0,
        isRecentExpanded: Bool = false,
        footerHeight: CGFloat = restingFooterHeight
    ) -> CGFloat {
        sessionViewportHeight(liveRowCount: liveRowCount, openRowHeight: openRowHeight)
            + recentSectionHeight(
                retiredRowCount: retiredRowCount,
                isRecentExpanded: isRecentExpanded
            )
            + footerHeight
    }

    /// The expanded panel's width, which answers to a **count of working
    /// agents** and to nothing that can be said in words.
    ///
    /// **The sentence is gone from both sides of this sum.** It used to reserve
    /// the longest status name the aggregate could reach — `Approval needed`,
    /// `102` at 13 pt Light — so a two-agent panel was `570` because of a
    /// sentence while a one-agent panel was `520` because of a baseline: the
    /// same object at two sizes depending on what happened to be open, changing
    /// size the first time a second agent connected. The band draws no word now
    /// (`expanded-header-v2.md` §3), and what is left on the leading side is
    /// the collapsed bar's own group and one column of numbers per working
    /// agent.
    ///
    /// **Doubled, because the panel is centred on the display** rather than
    /// pinned to the cut-out (``MonitorStore/currentPanelTrailingAnchor`` is
    /// nil while expanded), so the leading side can only be widened by widening
    /// both. The trailing side wants a gear and no more, and never binds here.
    ///
    /// The branch is `610` at every cut-out this product meets, and now at
    /// every agent count too: a side asks `53.8`, so the baseline is passed
    /// only where the cut-out is wider than `610 − 107.6 = 502.4`, well past
    /// the widest cut-out on any Mac. `expandedNotchClearance` therefore stays
    /// as the guard that this band clears the hardware and stops being the
    /// rule that decides a width.
    ///
    /// **It answers to nothing but the cut-out.** The working-agent count left
    /// with the decomposition (`colour-v2.md` §3), which was the only term on
    /// either side that read one — so the width series is one number.
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
        // Cleared as it publishes. Leaving it set kept ``nextPublishDeadline``
        // reporting an instant already past until the *next* refresh observed
        // the now-disconnected state and cleared it -- one wake-up spent
        // rediscovering something this call already knew.
        self.disconnectedSince = nil
        return true
    }

    /// When a suppressed disconnect becomes publishable.
    ///
    /// Suppressing without arranging to be asked again is the same mistake as
    /// dropping a refresh request: the grace period only bounds the wait if
    /// something actually looks again when it expires. Nothing did -- the store
    /// slept on the service's deadlines, which know nothing about this gate, so
    /// a real disconnect could sit unpublished until the next unrelated wake-up
    /// or the 60s heartbeat, rather than the 3s the latency budget documents.
    ///
    /// Always clearable: the refresh at this instant either publishes the
    /// disconnect or observes a recovery, and both clear `disconnectedSince`.
    var nextPublishDeadline: Date? {
        disconnectedSince?.addingTimeInterval(gracePeriod)
    }
}

@MainActor
final class MonitorStore: ObservableObject {
    /// Which product an integration call means when it does not say.
    ///
    /// Every switch in this store is per product (ADR 0016 gave Claude Code one
    /// too), and none of the state below is shared between them: installing or
    /// removing one product's hooks can never move the other product's switch.
    /// This default exists so the no-argument spelling still reads as Codex,
    /// which is what it has always meant.
    static let defaultIntegrationAgent = AgentKind.codex
    private static let liveService = LiveCodexMonitorService()
    private static let claudeCodeService = ClaudeCodeMonitorService()
    static let shared = makeShared()

    /// The store the product runs on, and nothing at all when this process is
    /// only hosting the test bundle.
    ///
    /// **The empty branch is the point.** A unit-test bundle is injected into a
    /// host application and this app is its own host, so `xcodebuild test`
    /// launches the product beside the copy the developer is already running --
    /// which then bound the same hook sockets and drew a second overlay in the
    /// same notch (see ``AppProcess``). The services are `static let`s and
    /// Swift builds those on first use, so a branch that never names them is a
    /// branch in which no watcher is attached, no socket is bound, no
    /// subprocess is started and no file of the user's is read.
    ///
    /// It costs the suite nothing: no test reaches for this store. Every one of
    /// them builds a ``MonitorStore`` of its own, over paths under `/tmp`.
    private static func makeShared() -> MonitorStore {
        guard !AppProcess.isHostingTests else {
            return MonitorStore(
                services: [],
                initialSnapshot: .connecting,
                preferences: .standard
            )
        }
        return MonitorStore(
            // Claude Code contributes nothing until its hooks are registered: an
            // unregistered product reports setupRequired, which loses to any
            // product that is ready and to any product that has a row. A user who
            // only runs Codex sees exactly what they saw before.
            services: [liveService, claudeCodeService],
            navigator: AgentNavigationRouter([
                .codex: CodexDesktopNavigator(targetChecker: liveService),
                // Raises the host rather than reopening the session, which is the
                // declared boundary rather than a fallback -- see ADR 0004 and
                // ``ClaudeCodeNavigator``.
                .claudeCode: ClaudeCodeNavigator(sessions: claudeCodeService)
            ]),
            initialSnapshot: .connecting,
            preferences: .standard,
            // Every provider's "ask me again" edges on one stream, so a late
            // answer from any of them wakes the loop.
            refreshEvents: DirectoryChangeWatcher.merged([
                liveService.stateChangeEvents,
                claudeCodeService.stateChangeEvents
            ])
        )
    }

    @Published private(set) var displays: [DisplayOption]
    @Published private(set) var selectedDisplayID: String
    @Published private(set) var status: MonitorStatus
    /// The products that are open *and* reachable, in display order.
    ///
    /// This is what the collapsed surface draws a matrix for, one each, and so
    /// it is also what sets the pill's width. Published because a second
    /// product connecting need not change the status — the first one may be
    /// mid-turn throughout — and a width that changed without a publish would
    /// leave the panel sized for the wrong number of marks.
    @Published private(set) var connectedAgents: [AgentKind] = []
    /// What the collapsed surface draws, left to right — never empty.
    ///
    /// Published for the same reason `connectedAgents` is: a second product
    /// opening, or one product's own turn starting, changes a mark without
    /// necessarily changing the aggregate status.
    @Published private(set) var presenceMarks: [PresenceMark] = [
        PresenceMark(agent: nil, status: .disconnected)
    ]
    /// What each product's monitoring has left on disk, for the products that
    /// leave anything. Shown in Settings; never acted on.
    ///
    /// Keyed only by the products that leave something: a product answering
    /// ``AgentDiskFootprintReport/leavesNothing`` is absent, and everything
    /// else — including a measurement still on its way — is present, because
    /// the presence of the key is what decides whether Settings draws the row
    /// and the row must not appear and disappear under the pointer (CC-020).
    @Published private(set) var diskFootprints: [AgentKind: AgentDiskFootprintReport] = [:]
    @Published private(set) var availability: MonitorAvailability
    @Published private(set) var quota: QuotaSnapshot
    @Published private(set) var sessions: [MonitoredSession] {
        didSet { updateElapsedTicking() }
    }
    /// Advances once a second while a turn is timed; see `updateElapsedTicking`.
    ///
    /// Deliberately **not** `@Published`. Every publish on this store re-evaluates
    /// the whole overlay — the `GeometryReader`, the custom panel `Shape` and both
    /// AppKit representables — which profiles at roughly 20ms, so a readout
    /// gaining a second used to cost about 4% of a core for as long as a turn ran
    /// or waited on the user. The readouts subscribe to this and redraw their own
    /// layer; nothing in the SwiftUI graph observes it.
    let elapsedTick: CurrentValueSubject<Date, Never>

    /// Bumped when a readout's *reserved width* changes, which is the only thing
    /// SwiftUI actually has to re-measure for.
    ///
    /// The readouts use tabular figures, so width follows the digit count: this
    /// moves when a turn crosses a minute or hour boundary, not every second.
    @Published private(set) var elapsedLayoutRevision = 0
    private var elapsedLayoutSignature: [Int] = []

    /// The instant the readouts are currently showing.
    var timerNow: Date { elapsedTick.value }
    /// How far along each product's registration is.
    ///
    /// Published because the settings rows read it, and written only when it
    /// actually changes -- one publish here re-evaluates the whole overlay
    /// (`AGENTS.md` §7), and a refresh re-states the same status every second.
    @Published private(set) var setupStatusByAgent: [AgentKind: HookSetupStatus] = [:]
    /// Where each product's switch is sitting.
    ///
    /// Held apart from ``setupStatusByAgent`` because the two disagree for as
    /// long as a convergence is in flight: the switch shows where the user put
    /// it, the status shows what the file says.
    @Published private(set) var integrationSwitchIsOnByAgent: [AgentKind: Bool] = [:]
    /// The products whose hooks are being written or removed right now.
    @Published private(set) var integrationBusyAgents: Set<AgentKind> = []
    @Published var isExpanded = false {
        didSet {
            // **Opening the panel is a read of the queue**, and eviction is a
            // read-time filter rather than a timer (§2.4 rule 11): a queue
            // nobody watched for six hours is empty by the time it could be
            // drawn, with no background work having run while the panel was
            // shut.
            guard isExpanded != oldValue else { return }
            if isExpanded { refreshRecentDepartures(at: clock.now()) }
            updateRecentTicking()
        }
    }
    /// Whether somebody has opened what the list has let go of.
    ///
    /// **Named for the open state rather than the folded one**, which is the
    /// spelling ``isQuotaExpanded`` arrived at for the same reason: folded is
    /// what this *is*, and opening it is the thing somebody asks for. The
    /// design calls the setting `recentFolded` (`expanded-panel-v2.md` §2.4
    /// rule 07); the default it names — folded — is what this stores, inverted.
    ///
    /// Remembered across openings, and **folding it never closes the panel**:
    /// the footer stands between this control and the bottom edge, so that edge
    /// cannot travel past a still pointer.
    @Published var isRecentExpanded: Bool {
        didSet {
            preferences?.set(
                isRecentExpanded,
                forKey: Self.recentExpandedDefaultsKey
            )
            guard isRecentExpanded != oldValue else { return }
            // The fold decides *which* instants matter, so a wake-up parked
            // before it moved is parked on the wrong one — see
            // ``nextRecentReadingChange(at:)``. Cancelled rather than left to
            // fire, because the tick is otherwise free to be wrong all the way
            // to the next boundary. The refresh re-plans it, and also reads the
            // ages, which are not kept up to date while nothing draws them.
            recentTickTask?.cancel()
            recentTickTask = nil
            refreshRecentDepartures(at: clock.now())
        }
    }
    /// What the queue holds right now, most recently departed first.
    ///
    /// A projection of ``departuresByThread`` past ``recentWindow``, republished
    /// wherever that can have changed. It is a stored value rather than a
    /// computed one because SwiftUI has to be told: a computed property reading
    /// the clock would go stale on screen with nothing to invalidate it.
    @Published private(set) var recentDepartures: [RecentDeparture] = []
    /// The instant the queue's ages are drawn against.
    ///
    /// **Not ``timerNow``**, which advances only while a Turn is being timed —
    /// on a panel with nothing running it is frozen at whatever the last turn
    /// left, and every age below the rule would be drawn against it. This moves
    /// whenever the queue is republished, which includes the panel being
    /// opened, so the ages are right at the moment somebody looks at them.
    ///
    /// It is published **only when a reading would actually move**, for the
    /// reason ``publishTick`` compares widths: one publish on this store
    /// re-evaluates the whole overlay (`AGENTS.md` §7), and the clock advances
    /// on every refresh whether or not anything down here changes because of
    /// it.
    @Published private(set) var recentReadAt: Date
    /// Whether somebody has opened the quota table.
    ///
    /// **A rename rather than a flipped boolean**, and the change is meant to
    /// be visible in review: it was `isQuotaFolded`, defaulting to `false`,
    /// because the footer *was* four quota rules and folding was the escape
    /// from them. Since `quota-footer-v2.md` §8.1 the small form is what the
    /// footer **is** — one number and a control, `22` at every product count,
    /// every window count and every share — and the table is a thing somebody
    /// asks for. So the default inverts with the name.
    ///
    /// One state for the whole footer, not one per product: the two share a
    /// footer, and opening one product's windows while the other's stayed shut
    /// would be a shape nothing describes. Remembered across openings, so a
    /// user who wants the table does not re-open it every time.
    @Published var isQuotaExpanded: Bool {
        didSet {
            preferences?.set(isQuotaExpanded, forKey: Self.quotaExpandedDefaultsKey)
        }
    }
    /// Whether the collapsed surface gives up its wings and leaves the cut-out
    /// to speak for itself.
    ///
    /// The resting form is not a new one: it is exactly what a notched display
    /// already draws while nothing is connected (``drawsCompactMarks``), asked
    /// for on purpose rather than arrived at. The cut-out is a shape the
    /// hardware puts on the screen whatever this app does, and this is the
    /// preference for people who want that shape and nothing beside it while
    /// nothing is being asked of them.
    ///
    /// **It is quiet, not blind.** A wing that never came back would make this
    /// a preference for turning the product off: the notch is the only thing
    /// this app has to say anything with, and a Turn stopped on an approval is
    /// exactly what it exists to say. So the leading wing comes out for a
    /// product holding a Turn to attend to and goes back when that Turn is
    /// dealt with (``compactDrawnMarks``), one matrix per product and neither
    /// while both are merely working. **The trailing wing never comes out at
    /// all**: the badges and the elapsed reading say how much and how long, not
    /// that anything is wanted, and the whole point of this preference is that
    /// a running turn is nobody's business but the agent's.
    ///
    /// **Collapsed only, and deliberately.** Hover still opens the panel, and
    /// the panel still carries the marks, the rows and the gear. The cut-out is
    /// the only entrance this product has -- an app with no menu bar item and
    /// no Dock icon (`PRD.md` §11) -- so a preference that closed it would be a
    /// preference for uninstalling.
    ///
    /// Remembered across launches, and kept even while the selected display
    /// cannot honour it: it is a fact about what the user wants, not about
    /// which screen happens to be plugged in this morning. See
    /// ``canHideCompactWings``.
    @Published var hidesCompactWings: Bool {
        didSet {
            preferences?.set(
                hidesCompactWings,
                forKey: Self.hidesCompactWingsDefaultsKey
            )
        }
    }
    /// Whether the surface draws a hairline around its own edge.
    ///
    /// The panel is black, and on a dark wallpaper that is a shape with no
    /// edge: the expanded panel reads as a hole rather than as an object, and
    /// on a display with no cut-out to inherit, so does the collapsed pill.
    /// The outline gives it one back.
    ///
    /// **The colour is derived, not picked**: three quarters of the grey a
    /// running turn's timer is drawn in (``NotchPalette/surfaceEdge``). An edge is not
    /// information -- it is there so the black has a shape against the
    /// wallpaper -- so it sits below every mark that does carry state rather
    /// than beside the dimmest of them.
    ///
    /// **The top line is not drawn.** The surface hangs from the very top of
    /// the display, so that edge belongs to the screen and not to this panel;
    /// a rule along it reads as a line across the menu bar. What is traced is
    /// the two shoulders, the sides and the lower corners.
    ///
    /// Collapsed and expanded alike, because the reason is the wallpaper
    /// behind it and that does not change on hover. The one form it is not
    /// drawn on is ``givesUpCompactWings`` with no mark out, where the user has
    /// asked for the cut-out and the surface is exactly that; see
    /// ``showsSurfaceOutline``.
    ///
    /// Off by default and remembered across launches. It is a fact about the
    /// wallpaper somebody chose, and nothing here can read that.
    @Published var drawsSurfaceOutline: Bool {
        didSet {
            preferences?.set(
                drawsSurfaceOutline,
                forKey: Self.drawsSurfaceOutlineDefaultsKey
            )
        }
    }
    /// Whether the notch-less pill names the work between its two ends.
    ///
    /// **Default on, and notch-less only.** The pill is the one form with a
    /// middle to give: the notched bar has a cut-out where a name would stand,
    /// and the only way to give it one is `102` pt of black beside the hardware
    /// for the whole of every turn — the reservation both wings spent V1 and V2
    /// getting rid of (`compact-view-v2.md` §5.2).
    ///
    /// Off, the middle draws nothing and **the pill holds its `250` rather than
    /// shrinking**: its two ends are anchored, so a width that answered to this
    /// preference would move the mark and the reading with it, which is the one
    /// thing this form is arranged not to do.
    @Published var namesWorkOnPill: Bool {
        didSet {
            preferences?.set(
                namesWorkOnPill,
                forKey: Self.namesWorkOnPillDefaultsKey
            )
        }
    }
    @Published private(set) var lastIntegrationMessage: String
    @Published private(set) var hasCompletedOnboarding: Bool

    private static let quotaExpandedDefaultsKey = "quotaExpanded"
    private static let recentExpandedDefaultsKey = "recentExpanded"
    private static let hidesCompactWingsDefaultsKey = "hidesCompactWings"
    private static let drawsSurfaceOutlineDefaultsKey = "drawsSurfaceOutline"
    private static let namesWorkOnPillDefaultsKey = "namesWorkOnPill"
    private static let onboardingDefaultsKey = "hasCompletedOnboarding"
    private static let selectedDisplayDefaultsKey = "selectedDisplayID"
    private let services: [any AgentMonitoring]
    /// Whether this store is watching anything at all.
    ///
    /// Read by one test, and it is the one worth being able to ask: the shared
    /// store is built with no services when this process is only hosting the
    /// test bundle, and "no services" is what stops a test run from binding the
    /// user's hook sockets and drawing a second overlay over their notch. It is
    /// a fact about the store rather than a hook for the suite -- `services` is
    /// private, and a decision this load-bearing should not rest on nobody
    /// being able to see it.
    var isWatching: Bool { !services.isEmpty }
    private let navigator: (any AgentNavigating)?
    private func integrationService(for agent: AgentKind) -> (any AgentMonitoring)? {
        services.first { $0.agent == agent }
    }
    /// Where every persisted preference is read and written. `nil` in tests,
    /// which is what keeps them off the running user's real defaults.
    private let preferences: UserDefaults?
    private let clock: any MonitorClock
    private let timing: MonitorTiming
    private var preferredDisplayID: String?
    private var pendingHoverTask: Task<Void, Never>?
    /// The armed wake-up for the next moment output could change, re-armed at
    /// the end of every refresh run. See ``scheduleNextWake()``.
    private var wakeTask: Task<Void, Never>?
    private var refreshEventTask: Task<Void, Never>?
    private var elapsedTickTask: Task<Void, Never>?
    private var recentTickTask: Task<Void, Never>?
    private let refreshEvents: AsyncStream<Void>?
    private var refreshGate = SingleFlightGate()
    private var refreshTask: Task<Void, Never>?
    /// Each switch's desired state, which that product's convergence task reads
    /// on every pass.
    private var desiredIntegrationEnabled: [AgentKind: Bool] = [:]
    /// One convergence task per product, so a slow write on one side cannot
    /// hold the other side's switch.
    private var integrationTasks: [AgentKind: Task<Void, Never>] = [:]
    private var isNavigationInFlight = false
    /// How long a row stays reachable after it leaves the list.
    ///
    /// **Five hours, and a constant rather than a setting** (§2.4 rule 01): a
    /// window the user can widen is the history browser this app is not. It is
    /// also what holds the age to two characters — nothing can ever read `5h`,
    /// because at five hours the row is gone (§2.3).
    ///
    /// Not in ``MonitorTiming``, deliberately. Every window there is a
    /// mechanism's — how stale an answer may get, how long a connection is
    /// given to come back — and they compose into user-visible latencies. This
    /// one composes into nothing and is answerable only from the product side.
    static let recentWindow: TimeInterval = 5 * 60 * 60
    /// A ceiling on the queue's size, behind the window rather than in front
    /// of it.
    ///
    /// **The rule anybody can see is still five hours** (§8.5 question 08).
    /// This exists only so an unbounded store cannot grow without limit: fifty
    /// is far past what the viewport can draw and far past a plausible five
    /// hours, and if it ever binds, the count on the seam said so long before.
    /// What it must never become is the visible rule — that is the "last N"
    /// this design has just finished banning.
    static let recentCeiling = 50
    /// Every row that has left the list, keyed by Thread.
    ///
    /// Keyed by Thread rather than by Turn for the reason on
    /// ``RecentDeparture/key(for:)``, and unbounded in count within its window:
    /// membership is the window, and ``recentCeiling`` stands behind it rather
    /// than beside it.
    private var departuresByThread: [String: RecentDeparture] = [:]
    /// The Turns the user has taken off the list, kept per product.
    ///
    /// Per product because forgetting one is decided against that product's own
    /// state: a dismissal may only be dropped on evidence from the product it
    /// came from, and the other product's health says nothing about it.
    private var dismissedSessionIDsByAgent: [AgentKind: Set<String>] = [:]
    /// The latest answer from each product, kept so the merge can be recomputed
    /// without asking anyone again. One product answering must never discard
    /// what another already said.
    private var latestByAgent: [AgentKind: AgentSnapshot] = [:]
    /// One gate per product. Sharing one made a Codex blip suppress a Claude
    /// Code publish, and made the grace period's wake-up a shared resource.
    private var stabilityGates: [AgentKind: ConnectionStabilityGate] = [:]
    private var diskFootprintTask: Task<Void, Never>?
    /// Deadlines a provider reported and then failed to clear. A provider that
    /// keeps naming the same overdue instant is not going to advance it, and
    /// letting it into the shared `min` would drag every other provider down to
    /// the refresh floor with it.
    private var stuckDeadlines: [AgentKind: Date] = [:]

    init(
        displays: [DisplayOption]? = nil,
        services: [any AgentMonitoring] = [],
        navigator: (any AgentNavigating)? = nil,
        initialSnapshot: AgentSnapshot? = nil,
        /// Every product's opening answer, where more than one is wanted.
        ///
        /// ``initialSnapshot`` seeds one product, which is all a live store
        /// ever needs -- the services publish the rest. A drawing that has to
        /// show both products at once has no services to wait for, so it hands
        /// the whole set in here and the merge runs over it exactly as it does
        /// on every refresh. See ``NotchSpecimen``.
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
        // Through the injected store, not `.standard`. These used to read
        // `.standard` directly while only the display preference was injected,
        // so a `MonitorStore` built in a test inherited whoever was running it:
        // an attribution test failed on any machine whose owner had chosen
        // `Badge` in the picker that used to be in Settings, and passed on
        // every other, which is a test reporting on the developer rather than
        // on the code.
        //
        // `object(forKey:)` rather than `bool(forKey:)` so an install that has
        // never opened the table is told apart from one that opened and shut
        // it — the two agree today, and would not if this default ever moved.
        self.isQuotaExpanded = preferences?.object(
            forKey: Self.quotaExpandedDefaultsKey
        ) as? Bool ?? false
        // `object(forKey:)` for the reason the quota's uses it: this defaults
        // to folded, and `bool` cannot tell an install that has never opened
        // the queue from one that opened and shut it.
        self.isRecentExpanded = preferences?.object(
            forKey: Self.recentExpandedDefaultsKey
        ) as? Bool ?? false
        self.hidesCompactWings = preferences?.bool(
            forKey: Self.hidesCompactWingsDefaultsKey
        ) ?? false
        self.drawsSurfaceOutline = preferences?.bool(
            forKey: Self.drawsSurfaceOutlineDefaultsKey
        ) ?? false
        // `object(forKey:)` rather than `bool(forKey:)`: this one defaults to
        // *on*, and `bool` cannot tell an install that has never seen the
        // switch from one that has turned it off.
        self.namesWorkOnPill = preferences?.object(
            forKey: Self.namesWorkOnPillDefaultsKey
        ) as? Bool ?? true
        self.hasCompletedOnboarding = preferences?.bool(
            forKey: Self.onboardingDefaultsKey
        ) ?? false
        self.lastIntegrationMessage = snapshots.first?.diagnostic
            ?? "Waiting for Codex data"

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
    /// The tick still lives here rather than in a view-local timer, because it is
    /// a timing decision and belongs on ``MonitorClock`` like every other window.
    /// What changed is how it leaves: a tick is sent on ``elapsedTick``, which no
    /// SwiftUI view observes, and only a change in the readouts' *reserved width*
    /// bumps ``elapsedLayoutRevision`` and asks SwiftUI to re-measure.
    private func updateElapsedTicking() {
        // Nothing being timed: stop entirely rather than wake once a second to
        // discover there is no work.
        guard longestRunningSessionStart != nil else {
            elapsedTickTask?.cancel()
            elapsedTickTask = nil
            return
        }
        guard elapsedTickTask == nil else { return }

        // The tick has been frozen since the last turn finished, so it is older
        // than the turn that just started. Left stale, the first second of that
        // turn reads as a negative duration -- which the formatter reports as
        // "not timed" -- and the row renders blank until the first tick.
        publishTick(clock.now())

        elapsedTickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard let start = self.longestRunningSessionStart else {
                    // The last timed turn finished between ticks. `sessions`
                    // will have cancelled this task already; clearing the handle
                    // keeps a later turn able to start a new one.
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

    /// Sends a tick to the readouts, and asks SwiftUI to re-measure only if one
    /// of them changed width.
    ///
    /// The formatter emits digits and colons in tabular figures, so a string's
    /// character count *is* its rendered width; comparing counts is comparing
    /// widths without measuring text once a second. The badge counts are
    /// included directly, rather than measured, for the same reason: a count
    /// changing is a width-affecting event whether or not its digit count
    /// happens to change too. Each badge's flip goes in beside its count
    /// because a badge that changes ground without changing width still has
    /// to redraw.
    private func publishTick(_ now: Date) {
        elapsedTick.send(now)

        // **The counts go in beside the reading.** A numeral gaining a digit
        // widens the leading wing exactly as a digit widens the trailing one,
        // and the collapsed bar is composed from both -- so a tick that finds
        // either changed is a tick the panel has to be re-measured for.
        var signature = [aggregateSessionCount, aggregateSubagentCount]
        signature.append(compactTimerText?.count ?? -1)
        signature.append(buriesAFinishedTurn ? 1 : 0)
        signature.append(contentsOf: sessions.map { elapsedText(for: $0)?.count ?? -1 })
        guard signature != elapsedLayoutSignature else { return }
        elapsedLayoutSignature = signature
        elapsedLayoutRevision &+= 1
    }

    /// Time until the timed turn's next whole second.
    ///
    /// Sleeping a flat second drifts, and a drifting tick eventually crosses two
    /// boundaries in one wake-up and visibly skips a digit. Landing on the turn's
    /// own boundary keeps the ticks a true second apart, so every row -- whatever
    /// its own sub-second phase -- advances exactly once per tick.
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

    /// The chosen display as AppKit's own object, for the windows that have to
    /// land on the screen the component is on.
    ///
    /// Matched by identifier, not by frame: a frame is not an identity — two
    /// displays swap origins the moment the user rearranges them in System
    /// Settings — and the identifier is the same string the preference is
    /// stored under. `nil` only while that display is gone and
    /// ``refreshDisplays()`` has not caught up with it yet.
    var selectedScreen: NSScreen? {
        guard let id = selectedDisplay?.id else { return nil }
        return NSScreen.screens.first { DisplayOption.identifier(for: $0) == id }
    }

    var geometry: DisplayGeometry {
        selectedDisplay?.geometry ?? .noNotch
    }

    /// The collapsed panel's height on the selected display, and the figure
    /// both corner radii and the wingless step are shares of.
    ///
    /// ``DisplayOption/panelBandHeight``: the cut-out on a notched display,
    /// the menu bar band on every other one.
    var compactHeight: CGFloat {
        selectedDisplay?.panelBandHeight ?? PanelMetrics.referenceCompactHeight
    }


    /// Whether this surface draws the name of the work between its two ends.
    ///
    /// **The notch-less pill, collapsed, with something to name.** The notched
    /// bar has no middle — the cut-out is where one would stand — and the
    /// expanded panel names every Project in the rows below.
    var drawsCompactMiddle: Bool {
        namesWorkOnPill
            && !isExpanded
            && geometry == .noNotch
            && !compactProjectNames.isEmpty
    }

    /// Whether ``namesWorkOnPill`` is something the selected display could
    /// honour — which is what the row's caption reports, and nothing else.
    ///
    /// **The mirror image of ``canHideCompactWings``.** That preference needs a
    /// cut-out to shrink onto; this one needs the absence of one, because the
    /// notched bar has no middle to name anything in. Both rows stay visible
    /// *and settable* on both kinds of display: a switch that appears only on
    /// one kind is one nobody finds, and one that is greyed on the other is one
    /// nobody can answer — the screen a preference cannot be honoured on is
    /// exactly the screen somebody is sitting at when they decide what they
    /// want. This gates the drawing, never the setting.
    var canNameWorkOnPill: Bool { geometry == .noNotch }

    /// Whether the collapsed surface draws its mark at all, which is the
    /// question the leading wing's existence turns on.
    ///
    /// **One mark for every product at once**, so this is a switch rather than
    /// a count: the wing is whole or it is absent. It is off in exactly two
    /// states, both of them notched and collapsed — nothing connected, and
    /// `Hide the wings` with nothing waiting on a person
    /// (`compact-view-v2.md` §9).
    var drawsCompactMarks: Bool {
        guard !isExpanded, geometry == .notched else { return true }
        guard !isRestingOnly else { return false }
        guard givesUpCompactWings else { return true }
        return presenceMarks.contains(where: \.hasATurnToAttendTo)
    }

    /// Whether ``hidesCompactWings`` is something the selected display could
    /// honour -- which is what the row's caption reports, and nothing else.
    ///
    /// **The condition is a measured cut-out, not a reported one.** Giving up
    /// the wings means shrinking the collapsed body onto the hardware's own
    /// shape, so this app has to know exactly where that shape is and how wide
    /// it is; there is nothing else left on screen to place. Two displays fail
    /// that, for the same reason stated twice:
    ///
    /// - A display without a notch has no such shape at all. Hiding the pill
    ///   would take its position in the menu bar with it and slide every icon
    ///   to its left across, and leave nothing to hover.
    /// - A display that reports a notch but no gap between its auxiliary areas
    ///   has a shape this app cannot locate. It is already laid out as an
    ///   *emulated* notch for exactly that reason (see `PanelMetrics.size`),
    ///   and shrinking onto a cut-out whose width reads as zero would leave a
    ///   zero-width panel: nothing drawn, and nothing to hover.
    ///
    /// The preference itself is untouched by either -- it survives unplugging
    /// the display that could not honour it, and can be set on one. The switch
    /// is not greyed here: this answers what the display can draw, not what the
    /// user is allowed to ask for.
    var canHideCompactWings: Bool {
        guard geometry == .notched else { return false }
        return (selectedDisplay?.centerOcclusionWidth ?? 0) >= 1
    }

    /// Whether the collapsed surface has given up its wings: the preference,
    /// on a display that can honour it.
    ///
    /// **Not "drawing nothing at all", which is what this used to say.** The
    /// trailing wing does go entirely, and so does the leading one for as long
    /// as neither product is waiting on the user — but a Turn stopped on an
    /// approval, a question or an unread answer brings its own matrix out
    /// (``compactDrawnMarks``), so this answers what the preference is doing
    /// rather than what is left on screen. ``drawsCompactMarks`` is the second
    /// question, and it is asked separately.
    ///
    /// Says nothing about hover: every reader of this is already collapsed-only
    /// (the drawn marks guard on it, and the trailing reading is drawn only
    /// while collapsed), and scoping it here as well would make the answer
    /// change under the pointer for no drawn difference.
    var givesUpCompactWings: Bool {
        hidesCompactWings && canHideCompactWings
    }

    /// Whether the outline is actually drawn, which is the preference minus the
    /// one form that has no edge of its own to trace.
    ///
    /// A collapsed surface that has given up its wings *and is drawing no mark*
    /// **is** the cut-out: its body is exactly the occlusion, and the only part
    /// of the contour still on lit pixels is the pair of shoulders curving back
    /// to the menu bar. Outlining those draws two grey hooks either side of the
    /// notch -- marks, on the one form whose whole point is that there are
    /// none. So the two preferences do not fight: the outline stands down while
    /// that form is on screen, and comes back the moment the panel drops.
    ///
    /// **A wing coming out gives it an edge back, and the outline returns with
    /// it.** Once a matrix is standing past the cut-out the body is no longer
    /// the occlusion, so the leading side and its lower corner are on lit pixels
    /// like any other collapsed bar's -- and this preference is about a black
    /// panel needing a boundary against a black wallpaper, which is as true of
    /// a one-matrix bar as of a full one. The added clause is an *or* rather
    /// than a replacement, which leaves the resting notched form exactly where
    /// it was: it draws no mark either, and it has always been outlined, hooks
    /// and all. The difference is that nobody asked for the cut-out there.
    ///
    /// Scoped to the collapsed state here rather than in ``givesUpCompactWings``
    /// for the reason given there: that property answers about the collapsed
    /// form and each reader says when it is asking.
    var showsSurfaceOutline: Bool {
        guard drawsSurfaceOutline else { return false }
        return isExpanded || !givesUpCompactWings || drawsCompactMarks
    }

    /// Nothing is connected, so the only mark is the grey one.
    var isRestingOnly: Bool {
        presenceMarks.allSatisfy(\.isResting)
    }

    /// Hovering grows the pill sideways instead of dropping the panel.
    ///
    /// True exactly when nothing is connected. The panel would have nothing in
    /// it, and the one thing the user might want — why nothing is connected —
    /// is in Settings, which the gear reaches in one action.
    var expandsToPillOnly: Bool {
        isRestingOnly
    }

    /// The name both collapsed forms and the panel read, since there is only
    /// one of them (``MonitorStatus/displayName``).
    var statusDisplayName: String {
        status.displayName
    }

    /// The turn the notch is timing.
    ///
    /// A single readout can only speak for one turn, so it follows the
    /// longest-running one — the oldest is the one worth surfacing. Every state
    /// but `completed` is eligible: a turn that has been parked on an approval
    /// for ten minutes is precisely the one the user needs to see, so filtering
    /// this to `running` would hide the timer exactly when it starts to matter.
    var longestRunningSessionStart: Date? {
        sessions
            .filter { $0.status.keepsTiming }
            .compactMap(\.startedAt)
            .min()
    }

    var compactTimerText: String? {
        // The drawn reading, measured. `Hide the wings` is answered by the span
        // below rather than here, so the width composed from this string and the
        // figure drawn from that span cannot disagree about whether there is a
        // reading at all. Every reader is the collapsed surface or its width:
        // the header, the two width compositions below, and the tick's own
        // re-measure signature.
        guard let span = compactReadingSpan else { return nil }
        return SessionElapsedFormatter.elapsed(
            since: span.start,
            now: span.end ?? Self.readableNow(timerNow, forStart: span.start)
        )
    }

    /// The two instants the collapsed reading is drawn between: a turn's start,
    /// and its end where it has one.
    ///
    /// **A stopped reading does not leave.** While something is unfinished this
    /// is the longest of those turns and the second stamp is absent, so the
    /// figure is advanced by the tick. When the last one ends the reading
    /// freezes on the turn it was timing rather than going away: the digits
    /// hold at that turn's own length, measured between its two stamps, and the
    /// panel's edge does not move at that instant
    /// (`compact-view-v2.md` §4.2).
    ///
    /// **Which finished turn**, when more than one has: the earliest-started of
    /// them, which is the same rule the live reading follows and therefore the
    /// same turn it was counting a moment ago. The doc leaves this open; it is
    /// decided here because "the last value the timer showed" has to name a
    /// row, and any other choice would let the figure jump when a row it was
    /// never drawing ages out.
    ///
    /// **Nil while the wings are given up**, which is where that preference is
    /// answered for the whole trailing slot. The collapsed body is composed from
    /// ``compactTimerText`` and drawn from this, and the gate used to stand on
    /// the string alone: the slot was then billed at zero while the view still
    /// had a span to draw into it, and a zero-width frame does not clip --
    /// ``ElapsedReadout`` paints its own raster from its leading edge whatever
    /// width it is offered. The figure ran out through the cut-out's trailing
    /// edge and was cut off by the window bound one shoulder past it, which is
    /// `12 + 4.75` pt of timer standing on a bar whose whole point is that there
    /// is nothing there. One answer, and it is this one, because everything the
    /// slot draws is derived from it.
    ///
    /// The dot beside it is untouched: it comes out from behind a hidden wing on
    /// its own account, billed for and drawn (`compact-view-v2.md` §9 -- the
    /// reading never comes out, the dot does).
    var compactReadingSpan: (start: Date, end: Date?)? {
        guard !givesUpCompactWings else { return nil }
        if let start = longestRunningSessionStart { return (start, nil) }
        let finished = sessions
            .filter { MonitorAggregation.effectiveStatus(of: $0) == .completed }
            .compactMap(finishedElapsed(for:))
            .min { $0.start < $1.start }
        return finished.map { ($0.start, $0.end) }
    }

    /// Whether the list holds a finished, unread turn that the aggregate mark
    /// is not drawing — the dot's own condition.
    ///
    /// **The aggregate's question, not each product's.** `PresenceMark`'s own
    /// flag answers it per product, and the case this surface now has to draw
    /// is one no product's flag can see: Codex holding nothing but a finished
    /// row while Claude Code runs is a buried finish for the *bar*, and false
    /// for both marks in it. So it is asked here, of the one list and the one
    /// mark that stand for all of them.
    var buriesAFinishedTurn: Bool {
        guard status != .completed else { return false }
        return sessions.contains {
            MonitorAggregation.effectiveStatus(of: $0) == .completed
        }
    }


    /// Every subagent still in flight across every listed row, both products
    /// together. Kept for VoiceOver's total and for callers that only need to
    /// know whether the collapsed surface has anything to say here.
    var compactRunningSubagentCount: Int {
        givesUpCompactWings ? 0 : aggregateSubagentCount
    }

    /// Everything the collapsed surface draws in the slot after the notch: a
    /// one subagent badge per product, the elapsed timer, or both sharing the slot.
    ///
    /// One value rather than two views, because it is one reading: the panel
    /// width is measured from it, and the elapsed half redraws itself once a
    /// second inside its own raster instead of laying out a stack every tick.
    var compactTrailingReading: CompactTrailingReading {
        CompactTrailingReading(
            timerText: compactTimerText,
            isFrozen: compactReadingSpan?.end != nil,
            // The reading still never comes out from behind a hidden wing; the
            // dot does, because a finished turn nobody has read is precisely a
            // thing that wants a person (`compact-view-v2.md` §9).
            buriesAFinishedTurn: buriesAFinishedTurn
        )
    }

    /// The large numeral: **rows on the monitored list**.
    ///
    /// Finished-but-not-yet-aged-out included, because it counts the same set
    /// the panel below it draws (`compact-view-v2.md` §3.3). It does not fall
    /// to zero the moment work stops; it falls when the row leaves, on the same
    /// clock that governs how long a stopped reading holds.
    ///
    /// **Ungated by `Hide the wings`.** That preference decides whether the
    /// leading wing is drawn; it never decides what the numerals count. A
    /// figure that meant the whole list under one display preference and the
    /// waiting subset under another would mean neither (§9).
    var aggregateSessionCount: Int { sessions.count }

    /// The small numeral: every subagent in flight, both products together.
    ///
    /// Summed off ``presenceMarks`` rather than re-derived, so the two ends of
    /// one bar cannot disagree about the same list. Ungated, for the reason
    /// above.
    var aggregateSubagentCount: Int {
        presenceMarks.reduce(0) { $0 + $1.subagents.count }
    }

    /// Every Project with an active row, in the panel's own order,
    /// deduplicated, first occurrence winning — the roster the pill's middle
    /// names in turn.
    ///
    /// **A Project name is the opposite of a product name.** The collapsed
    /// surface dropped hue and the matrix pair on the argument that a product
    /// name is a colour rather than a row, and that was right; this is the one
    /// fact the mark, the numerals and the clock all leave unanswered, and with
    /// several checkouts open it is the one that decides whether the user
    /// interrupts themselves (`compact-view-v2.md` §6.2).
    ///
    /// Ordered by ``sessions``, which is already the panel's own row order, so
    /// the roster and the list under it cannot disagree about what is first.
    var compactProjectNames: [String] {
        var seen: Set<String> = []
        return sessions.map(\.projectName).filter { seen.insert($0).inserted }
    }

    /// The aggregate mark's ink: ``NotchPalette/themeInk`` once a product is
    /// behind it, the resting grey until then.
    var aggregateMatrixInk: NotchPalette.MatrixInk {
        NotchPalette.matrixInk(isConnected: !isRestingOnly)
    }


    /// The leading group at the width it is drawing, for the view that has to
    /// draw it into exactly the room the panel was sized for.
    var compactDrawnLeadingGroupWidth: CGFloat {
        PanelMetrics.drawnLeadingGroupWidth(sessionCount: aggregateSessionCount)
    }

    /// The trailing reading at the width the collapsed surface bills it for,
    /// which since the pill stopped reserving is both collapsed forms.
    ///
    /// The view frames the reading to this and lets its glyphs sit at the
    /// leading edge of it, so the box and the panel edge open together and the
    /// figure's own leading edge stands still while a digit arrives at the far
    /// end. Zero on an empty reading, which is a slot that is not drawn at all.
    var compactDrawnTrailingReadingWidth: CGFloat {
        PanelMetrics.drawnTrailingReadingWidth(compactTrailingReading)
    }




    /// The counts column, in words.
    ///
    /// **What the numerals say, on the terms they say it.** Two figures with no
    /// product in either of them, so this names neither: hierarchy on that
    /// column is size and brightness, and the spoken form has neither channel —
    /// what it has instead is the two words the numerals cannot draw.
    ///
    /// **Ungated by `Hide the wings`**, like the numerals themselves: that
    /// preference decides whether the wing is drawn, never what it counts.
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

    /// What a breathing column is saying, in words.
    ///
    /// A movement cannot be spoken, and `figma-design.md` §10 forbids saying
    /// anything on this surface through one channel alone. It speaks on exactly
    /// the terms the column moves on (``PresenceMark/buriesAFinishedTurn``), so
    /// it stays quiet when every turn has finished — the status name already
    /// reads `Completed` there, and saying it again would be reading one fact
    /// twice.
    ///
    /// It does say **how many**, which the breath never does. That difference
    /// is kept rather than levelled: the number is already known, a reader who
    /// cannot see the column has no cheap way to ask for it, and nothing about
    /// the drawing has to change to hand it over.
    var spokenBuriedCompletionText: String? {
        // **On the aggregate, like the dot it speaks for.** It used to fold
        // each product's own flag, which cannot see a finished row on one
        // product buried under another product's running one -- the exact case
        // the one mark and the one dot now have to answer for.
        guard buriesAFinishedTurn else { return nil }
        let count = sessions.filter { session in
            MonitorAggregation.effectiveStatus(of: session) == .completed
        }.count
        guard count > 0 else { return nil }
        return count == 1
            ? "1 turn finished and unread"
            : "\(count) turns finished and unread"
    }

    /// The instant the compact readout counts from, or nil when there is nothing
    /// to draw. The readout advances itself from ``elapsedTick``, so it needs the
    /// start rather than a string that would go stale between re-renders.
    ///
    /// **Only while the figure is still moving.** A frozen reading is drawn
    /// between two stamps and ignores the tick, so it is
    /// ``compactReadingSpan`` that the view reads; this stays the question
    /// "is something being counted", which is what the tick itself answers to.
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

    /// What a finished row's slot draws: the length of the turn that ended.
    ///
    /// **A reading that has stopped, not one that is paused.** It is measured
    /// between the turn's own two stamps and never against the tick, so it is
    /// the same figure on every refresh for as long as the row is listed --
    /// which is the whole of what makes it read as a record rather than as a
    /// clock somebody forgot to restart.
    ///
    /// `nil` on a row that is still timing (its live reading is
    /// ``elapsedText(for:)``) and on one whose end was never observed, where a
    /// duration would have to be invented.
    func finishedElapsed(for session: MonitoredSession) -> (start: Date, end: Date)? {
        guard !session.status.keepsTiming,
              let startedAt = session.startedAt,
              let finishedAt = session.finishedAt,
              finishedAt >= startedAt
        else { return nil }
        return (startedAt, finishedAt)
    }

    /// ``finishedElapsed(for:)`` as the row draws it.
    func finishedElapsedText(for session: MonitoredSession) -> String? {
        guard let span = finishedElapsed(for: session) else { return nil }
        return SessionElapsedFormatter.elapsed(since: span.start, now: span.end)
    }

    /// ``finishedElapsed(for:)`` as VoiceOver has to hear it.
    func spokenFinishedElapsedText(for session: MonitoredSession) -> String? {
        guard let span = finishedElapsed(for: session) else { return nil }
        return SessionElapsedFormatter.spokenElapsed(since: span.start, now: span.end)
    }

    /// Whether a row's body line carries the searchlight.
    ///
    /// **The row's own turn is the only input.** A finished turn's body is the
    /// answer it produced, and it does not sweep even while subagents it
    /// started are still working: the text the band would cross is that turn's
    /// own final output, and the badge in the slot is what speaks for what is
    /// still in flight.
    ///
    /// Motion answers *live or finished*, which is the one thing here that can
    /// be read without looking straight at the panel. The reading's ground says
    /// the state on its own rather than lean on this.
    func sweepsBody(for session: MonitoredSession) -> Bool {
        session.status.keepsTiming
    }

    /// The instant a readout is drawn at, never earlier than the turn it draws.
    ///
    /// **A tick that has not caught up is not an untimed turn.** ``elapsedTick``
    /// only advances once a second, so between a turn starting and the next tick
    /// the shared instant is behind that turn's start by up to a second, and
    /// ``SessionElapsedFormatter`` answers `nil` — its contract, and the right
    /// one, because for it a start in the future is clock skew.
    ///
    /// Here it is not skew: both stamps come from ``MonitorClock``, so the only
    /// way the start can lead is that the tick has not arrived yet, and the
    /// honest reading at a turn's own start instant is `0:00`. Nothing is
    /// invented — the turn is running and its start is known.
    ///
    /// **What the `nil` cost was.** It does not just blank the readout for a
    /// beat; it takes the readout off screen and leaves it off. `nil` makes the
    /// row draw the untimed dot instead of ``ElapsedReadout``, and only a
    /// re-render puts the readout back — while the once-a-second re-measure is
    /// gated on the readouts' *width* (`AGENTS.md` §7), and `0:09` → nil →
    /// `0:00` is the same width throughout, so no re-render is ever asked for.
    /// Measured on a Release build 2026-08-24: a running row lost its timer for
    /// good, the collapsed pill went on counting because its own readout stayed
    /// mounted, and hovering the panel was what brought the row's back.
    nonisolated private static func readableNow(_ now: Date, forStart start: Date?) -> Date {
        guard let start else { return now }
        return max(now, start)
    }

    /// Whether rows say which product they belong to.
    ///
    /// Only while there are two products to tell apart — but that is a fact
    /// about what is **connected**, not about which product happens to have a
    /// row this second. Ordering is by urgency and not by product, so the list
    /// is interleaved and every row has to identify itself; with one product
    /// connected there is nothing to disambiguate and the mark would cost
    /// caption width for no reason.
    ///
    /// It used to read `Set(sessions.map(\.agent)).count > 1`, which made the
    /// mark come and go while both products stayed open: Claude Code finishing
    /// its last row silently un-marked every Codex row, and the mark returned
    /// on the next Claude Code turn. That is motion the user cannot account
    /// for, and it contradicts the surface's own presence rule — the collapsed
    /// matrices and the footer rules are already drawn per *connected* product
    /// (``footerRules``), so the rows were the one place answering a different
    /// question. Keyed to presence, the answer holds still for as long as both
    /// products are open, which is the span over which the user is actually
    /// telling rows apart.
    ///
    /// The second clause covers the reverse case: a product that closed while
    /// its rows are still listed. The list is visibly mixed, so it still has to
    /// identify itself, whatever presence now says.
    ///
    /// **The second clause reaches below the seam**, and for the reason it was
    /// written: a retired row names its product on the same presence rule
    /// (`expanded-panel-v2.md` §8.6), so a queue holding both products under
    /// one connected product is exactly the "visibly mixed list that still has
    /// to identify itself" the paragraph above describes.
    var showsProductAttribution: Bool {
        connectedAgents.count > 1 || attributedAgents.count > 1
    }

    /// Every product named anywhere on the list, above the rule and below it.
    private var attributedAgents: Set<AgentKind> {
        Set(sessions.map(\.agent))
            .union(recentDepartures.map(\.session.agent))
    }

    /// One group per connected product, in Settings' order, each holding its
    /// own windows in the order the product published them.
    ///
    /// Exactly as many groups as the notch has marks: the footer reports on the
    /// products that are there. **A product with no limits keeps its group**
    /// and draws no inner lines — its spend is attributed, and the absence says
    /// there is nothing to report. That is also how a connected product this
    /// app does not yet read quota for appears: present and counted, with
    /// nothing claimed about it (`quota-footer-v2.md` §5).
    ///
    /// **Nothing on this list is sorted, at either level.** Products keep
    /// Settings' order and windows keep the reader's — `Current session:` as
    /// `5 h` before `Current week (all models):` as `7 d` — so this accessor
    /// maps `snapshot.quota.windows` straight through. A sort by share was
    /// written and then overruled: the objection is not that an order indicates
    /// something, it is that it **moves**, and a share crossing another share
    /// would have re-ordered two rows for a reason nobody asked about. It also
    /// keeps one list to one order — `Quota.remainingPercent` reads
    /// `windows.first`, so a sort here would have made the table's first inner
    /// row a different window from the one every single-rule surface calls
    /// first.
    var footerRules: [FooterRule] {
        let now = clock.now()
        return quotaProducts.map { agent, quota in
            FooterRule(
                agent: agent,
                today: UsageSummaryFormatter.today(tokens: quota.todayTokens),
                windows: quota.windows.map { Self.footerWindow(for: $0, now: now) }
            )
        }
    }

    /// Every connected product this app has a reading for, in Settings' order.
    ///
    /// **The footer's shape without the footer's strings.** Building a
    /// `FooterRule` formats a countdown and a spoken date per window, and the
    /// panel asks the footer three questions on every render that only need the
    /// *shape*: is there a control, how tall is the box, and what has been spent
    /// today. Those read this instead, so the formatting is paid once, by the
    /// table, and only while somebody has it open (`AGENTS.md` §7 — a re-render
    /// costs what the whole overlay costs, so what a render does at rest is the
    /// number that matters).
    private var quotaProducts: [(agent: AgentKind, quota: QuotaSnapshot)] {
        connectedAgents.compactMap { agent in
            latestByAgent[agent].map { (agent, $0.quota) }
        }
    }

    /// One window's line: its name, its share, and the countdown to its reset.
    ///
    /// **`Resets in` came back.** It went out on the argument that the words
    /// were repeated once a window down a column of countdowns; what put them
    /// back is that the column beside this one now carries the window's own
    /// name, and a bare `4h` next to a `5h limit` reads as the same kind of
    /// thing. See ``UsageSummaryFormatter/resetText(resetsAt:remainingPercent:now:calendar:)``.
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

    /// The footer's one line at rest: every connected product's tokens for
    /// today, as a whole.
    ///
    /// **It is not broken into products here.** The word that says whose a
    /// number is costs width on this line and costs nothing in the table, where
    /// every figure sits beside its own product's name — so the parts that used
    /// to trail this line moved to the table's outer rows, and the collapsed
    /// footer names nobody (§3).
    ///
    /// Unreadable, it draws `-- today` in the place `518.7M today` would have
    /// had, and nothing else on the panel changes (§8.3).
    var footerToday: SpendReading {
        let totals = quotaProducts.compactMap(\.quota.todayTokens)
        guard !totals.isEmpty else {
            return UsageSummaryFormatter.today(tokens: nil)
        }
        return UsageSummaryFormatter.today(tokens: totals.reduce(0, +))
    }

    /// The control is drawn whenever there is at least one connected product.
    ///
    /// It does not wait for anything to be close: a control that appeared only
    /// in trouble would be one nobody had used at the moment they first needed
    /// it (§8.5 question 06). With nothing connected there is no footer at all.
    var showsQuotaFoldControl: Bool { !quotaProducts.isEmpty }

    /// Open the table, or shut it.
    ///
    /// **Shutting it cannot strand the pointer.** The control rides the spend
    /// line, which is the footer's first line and is always drawn, so the table
    /// opens *beneath* it and closing removes rows below a pointer sitting `6`
    /// to `22` above the folded bottom edge — inside it. The old footer folded
    /// the rules away *above* the line the chevron was on, which lifted the
    /// panel's bottom edge past the pointer that had just clicked.
    func toggleQuotaTable() { isQuotaExpanded.toggle() }

    var expandedFooterHeight: CGFloat {
        PanelMetrics.footerHeight(
            productCount: quotaProducts.count,
            windowCount: quotaProducts.reduce(0) { $0 + $1.quota.windows.count },
            isExpanded: isQuotaExpanded
        )
    }

    var emptyListMessage: String {
        availability.emptyListMessage
    }

    var expandedContentHeight: CGFloat {
        PanelMetrics.expandedContentHeight(
            liveRowCount: sessions.count,
            openRowHeight: openRowHeight,
            retiredRowCount: recentDepartures.count,
            isRecentExpanded: isRecentExpanded,
            footerHeight: expandedFooterHeight
        )
    }

    // MARK: - The open row

    /// The row whose request is open, if one is.
    ///
    /// **One at a time** (`answer-in-notch.md` §8.2): an open row is the
    /// subject, and two of them would be two subjects. Not persisted — §10 says
    /// text and part-answered sets stay with a row *for as long as that row
    /// lives*, and `artifacts.md` records that no hook payload ever reaches
    /// disk, which this is one of.
    @Published private(set) var openRowID: String?

    /// The session that row belongs to, if it is still on the list.
    ///
    /// Reading it through the list rather than holding the row is what makes
    /// §8's *settled elsewhere* free: when the request goes, the row goes with
    /// it and there is nothing to reconcile.
    var openSession: MonitoredSession? {
        guard let openRowID else { return nil }
        return sessions.first { $0.id == openRowID }
    }

    /// What the open row's body is, laid out at the width it draws in.
    ///
    /// One question of a set at a time (§5.3), which is why the count on the
    /// caption line is a drawn element rather than an ornament: an answer that
    /// appears to do nothing looks like a failure without it.
    var openRowBody: RequestBodyLayout? {
        guard let request = openSession?.request else { return nil }
        return RequestBodyLayout.laidOut(request, showing: openQuestionIndex)
    }

    /// Which question of a set the body is showing, from the top.
    var openQuestionIndex: Int {
        guard let openRowID else { return 0 }
        return answerProgress[openRowID]?.questionIndex ?? 0
    }

    /// How tall the open row is, or nil where no row is open.
    var openRowHeight: CGFloat? {
        guard openSession != nil else { return nil }
        return PanelMetrics.openRowHeight(
            bodyHeight: openRowBody?.contentHeight ?? 0
        )
    }

    /// Opens this row's request, or closes it if it is the one already open.
    ///
    /// **A row with nothing to show does not open.** The mark is a second target
    /// only where there is a second thing to reach; a row whose payload carried
    /// nothing readable stays what it has always been — one target, leading to
    /// the product (`answer-in-notch.md` §3).
    func toggleOpenRow(_ session: MonitoredSession) {
        guard session.request != nil else { return }
        if openRowID == session.id {
            closeOpenRow()
        } else {
            openRow(session.id)
        }
    }

    /// Whether the panel is holding the keyboard for a row.
    ///
    /// Hover browses and cannot latch, however long it lasts; only a click on a
    /// mark makes this panel key (§9.4).
    var isLatched: Bool { openRowID != nil }

    /// Collapses the open row, sending nothing and keeping the row where it was.
    ///
    /// The chevron's own action, and `⎋`'s. **What was typed is kept** — §10:
    /// text and any part-answered set stay with their row for as long as that
    /// row lives, so reopening resumes exactly where it stopped.
    func closeOpenRow() {
        guard openRowID != nil else { return }
        openRowID = nil
        armingTask?.cancel()
        armingTask = nil
        isAffirmativeArmed = false
        // ``isAnswerInFlight`` is deliberately left alone: it says an answer is
        // still on its way to a product, which is a fact about this app rather
        // than about the row it was typed into. Clearing it here would let the
        // same ticket be answered twice by closing the row and opening it again
        // mid-flight, and it is cleared where it becomes untrue — on landing.
    }

    // MARK: - Answering

    /// What has been typed into one row's field, and what part of its set has
    /// been answered.
    ///
    /// **Keyed by row and kept for the row's lifetime** (§10): closing sends
    /// nothing and keeps what was typed, so reopening resumes rather than
    /// starting again. It goes when the row goes, and it never reaches disk —
    /// a note about a request is the request's (ADR 0015).
    ///
    /// **Not published, and that is a rendering decision rather than an
    /// oversight.** The field is an AppKit text view drawing its own glyphs
    /// (§13.2), so a keystroke is not a layout change and must not invalidate a
    /// panel that measures text on every pass (`AGENTS.md` §7). What SwiftUI
    /// needs to know about typing is only ``answerGround``, which is published
    /// and changes at most once per row.
    private var answerProgress: [String: AnswerProgress] = [:]

    /// Which answer the white ground is on — and so what `⏎` will do.
    ///
    /// **Recomputed from what has been typed, never set from anywhere else.**
    /// §6: it begins on the affirmative, and exactly one force moves it in this
    /// version — the person's own typing, onto the answer that carries text,
    /// because a note cannot travel with a yes. Deriving it is what makes the
    /// drawing and the return key incapable of disagreeing: there is no second
    /// state to keep in step, which is §6.1's *the ground is the state* taken
    /// literally. The arrows are the second force (§9.3), and they are what will
    /// make this a value somebody sets.
    @Published private(set) var answerGround: AnswerGround = .affirmative

    /// What has changed about the open row that its identity cannot say.
    ///
    /// **A revision rather than the state itself.** The state is
    /// ``answerProgress``, which the field writes into on every keystroke —
    /// publishing it would re-render the whole panel per character, which is
    /// exactly the cost `AGENTS.md` §7 exists to keep off this surface. This is
    /// bumped only when something *drawn* moves: the question of a set on
    /// screen, which changes the row's height and so the window's, and a tick.
    @Published private(set) var answerRevision = 0

    /// How many times the store has replaced the field's text itself.
    ///
    /// **The field is an AppKit text view that owns its own string**, and it is
    /// refilled only when this or the row changes — refilling it on every pass
    /// would put the caret back to the start under somebody's hands. So the two
    /// places where the *store* decides what the field holds have to say so:
    /// an answer that landed clears it, and the next question of a set starts
    /// empty. Measured before this existed: a row answered and then re-opened
    /// by the advance came back holding the note that had already been sent.
    @Published private(set) var answerDraftGeneration = 0

    /// Whether an answer is on its way to the product (§8 state 01).
    ///
    /// The field and both controls drop to `45%` and stop taking keys while it
    /// is true. Nothing resizes and nothing new is drawn: the wait is a few
    /// hundred milliseconds, and anything drawn to fill it would outlive the
    /// thing it described.
    @Published private(set) var isAnswerInFlight = false

    /// Whether the affirmative has finished arriving, and may be taken (§6.3).
    ///
    /// **A ground that has not finished arriving is not a key and not a
    /// target.** Answering one request opens the next row (§8.2), which puts
    /// something the reader has never seen under a pointer that is already
    /// there — and the affirmative that arrives lands exactly where the
    /// affirmative just clicked was, so a pointer has to do nothing at all to
    /// answer twice. The ground is armed by the arrival it already animates
    /// rather than by a delay of its own: nothing is drawn that was not being
    /// drawn, and nothing is delayed that the eye was not already waiting for.
    ///
    /// It gates **every** answer rather than the affirmative alone, because the
    /// row that arrives is what the pointer is over: on a question the control
    /// under it is `Send`, and on an approval it may be either. Refusing is the
    /// cheap direction (§6.4) and costs nothing by waiting `200` ms for a row
    /// nobody has read yet.
    @Published private(set) var isAffirmativeArmed = false
    private var armingTask: Task<Void, Never>?

    /// What a row's preview line says instead of its own preview, once an
    /// answer has left it.
    ///
    /// **§8's states 02 and 03 are one mechanism.** Either way the row goes back
    /// to `80` and says one thing on the line it already draws: what was sent,
    /// or that it was not. In the preview's **own ink** — this app has no
    /// failure ink, and inventing one for a transport error would make it louder
    /// than a Turn that genuinely failed, which is drawn as ordinary preview
    /// text under an unchanged marker.
    ///
    /// It stands only until the product says something newer, which is what
    /// ``forgetNoticesTheProductHasOvertaken()`` is for.
    @Published private(set) var answerNotices: [String: AnswerNotice] = [:]

    /// What one row's preview line draws: the last thing this app said about
    /// it, or the product's own preview.
    func previewLine(for session: MonitoredSession) -> String? {
        answerNotices[session.id]?.text ?? session.preview
    }

    /// What is in the open row's field, for the view that draws it.
    var answerDraft: String {
        guard let openRowID else { return "" }
        return answerProgress[openRowID]?.draft ?? ""
    }

    /// The field reporting what it now holds.
    ///
    /// The text view owns the text; this owns what the text *means* for the
    /// ground. Called on every edit, and cheap by construction — the published
    /// value changes at most once per row, when the field stops or starts being
    /// empty.
    func answerDraftChanged(to text: String) {
        guard let openRowID else { return }
        answerProgress[openRowID, default: AnswerProgress()].draft = text
        refreshAnswerGround()
    }

    /// Takes one answer, which is what a click on it and what `⏎` both do.
    ///
    /// §6.6: **a click takes the answer it lands on**, whether or not the ground
    /// is there — there is no select-then-confirm on this surface, because the
    /// confirm would be a second control saying what the first already said.
    func takeAnswer(_ ground: AnswerGround) {
        guard !isAnswerInFlight, isAffirmativeArmed,
              let session = openSession,
              let request = session.request,
              let shape = request.answerRow,
              let ticket = request.replyTicket else { return }

        switch ground {
        case .affirmative where shape.refusal == nil:
            // A question's one control answers rather than grants: what it
            // sends is what the person put in — the field's words, or the
            // options they ticked.
            answerTheQuestion(
                choosing: nil,
                of: session,
                on: ticket,
                saying: shape.affirmativeNotice
            )
        case .affirmative:
            send(.grant, for: session, on: ticket, saying: shape.affirmativeNotice)
        case .refusal:
            let note = answerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            send(
                .refuse(note.isEmpty ? nil : note),
                for: session,
                on: ticket,
                saying: shape.refusalNotice
            )
        case let .option(index):
            if openRowBody?.allowsSeveralAnswers == true {
                // §5.5: with several allowed, a click on a box or its label
                // ticks it and nothing else happens — the ground stays on
                // `Send`, because the brightest object must not stop being what
                // `⏎` does on the one form where a person is most likely to
                // press it twice.
                tickOption(index)
            } else {
                answerTheQuestion(
                    choosing: index,
                    of: session,
                    on: ticket,
                    saying: shape.affirmativeNotice
                )
            }
        }
    }

    /// A digit takes the option it numbers — while the ground is still on one.
    ///
    /// **The one key the keyboard half left behind** (`answer-in-notch.md`
    /// §9.2). It is bound on §15 q08's condition and no other: *only while the
    /// ground is still on an option, which is to say before anything has been
    /// typed*. Reserving the digits permanently would silently eat the first
    /// character of an answer beginning with a number, and the ground being on
    /// an option is that condition already drawn — typing is what moves it off.
    ///
    /// Returns whether the panel took it, so the field types the digit when the
    /// panel did not. `takeAnswer` is what a click on that option does, so a
    /// numbered option and a clicked one cannot mean different things — on a
    /// `multiSelect` question both tick rather than send (§5.5).
    @discardableResult
    func takeNumberedOption(_ number: Int) -> Bool {
        guard case .option = answerGround, answerDraft.isEmpty else { return false }
        let options = openRowBody?.options ?? []
        guard number >= 1, number <= options.count else { return false }
        takeAnswer(.option(options[number - 1].id))
        return true
    }

    /// Whether one option of the question on screen is ticked (§5.5).
    func isOptionTicked(_ index: Int) -> Bool {
        guard let openRowID else { return false }
        return answerProgress[openRowID]?.ticked.contains(index) ?? false
    }

    private func tickOption(_ index: Int) {
        guard let openRowID else { return }
        var progress = answerProgress[openRowID] ?? AnswerProgress()
        if progress.ticked.contains(index) {
            progress.ticked.remove(index)
        } else {
            progress.ticked.insert(index)
        }
        answerProgress[openRowID] = progress
        answerRevision &+= 1
    }

    /// Answers the question on screen, and either draws the next or sends the
    /// set.
    ///
    /// **Answering one question of a set sends nothing** (§5.3): the set goes
    /// back as one `updatedInput`, so `⏎` on question two draws question three
    /// — the body alone changes, the head and the answer row stand still — and
    /// the count is what makes that legible.
    ///
    /// What is recorded depends on which answer was taken, and the rule is that
    /// **nothing a person typed is thrown away**: an option taken with text in
    /// the field carries that text as this question's note, which is the field
    /// the product's own component writes per-question notes into. Text with no
    /// option taken *is* the answer.
    private func answerTheQuestion(
        choosing index: Int?,
        of session: MonitoredSession,
        on ticket: HookReplyRegistry.Ticket,
        saying notice: String
    ) {
        guard let request = session.request else { return }
        let questions = request.askedQuestions
        guard !questions.isEmpty else { return }
        let position = min(max(openQuestionIndex, 0), questions.count - 1)
        let asked = questions[position]
        let typed = answerDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        let chosen: [String]
        if let index, index < asked.options.count {
            chosen = [asked.options[index].label]
        } else if asked.allowsSeveralAnswers {
            chosen = asked.options
                .filter { isOptionTicked($0.id) }
                .map(\.label)
        } else {
            chosen = []
        }

        let answered: AgentQuestionAnswer
        if chosen.isEmpty {
            // Nothing picked, so the field is the whole answer — and an empty
            // field is not an answer at all. `Send` with nothing to send does
            // nothing, which is the one honest thing it can do.
            guard !typed.isEmpty else { return }
            answered = AgentQuestionAnswer(question: asked.text, answer: typed)
        } else {
            answered = AgentQuestionAnswer(
                question: asked.text,
                answer: chosen.joined(separator: ", "),
                note: typed.isEmpty ? nil : typed
            )
        }

        guard let openRowID else { return }
        var progress = answerProgress[openRowID] ?? AnswerProgress()
        progress.answers[position] = answered
        if position + 1 < questions.count {
            progress.questionIndex = position + 1
            progress.draft = ""
            progress.ticked = []
            answerProgress[openRowID] = progress
            answerDraftGeneration &+= 1
            refreshAnswerGround()
            // The body is a question taller or shorter than the one it
            // replaces, and the window has to be remeasured for it.
            answerRevision &+= 1
            // The next question arrives on the same curve a row does, and its
            // affirmative is armed by that arrival rather than by a delay of its
            // own (§6.3).
            armTheAffirmativeOnArrival(of: openRowID)
            return
        }

        answerProgress[openRowID] = progress
        send(
            .answers(questions.indices.compactMap { progress.answers[$0] }),
            for: session,
            on: ticket,
            saying: notice
        )
    }

    /// Sends one answer, and turns what comes back into a row (§8).
    private func send(
        _ answer: AgentAnswer,
        for session: MonitoredSession,
        on ticket: HookReplyRegistry.Ticket,
        saying notice: String
    ) {
        isAnswerInFlight = true
        let agent = session.agent
        let rowID = session.id
        let previewWhenWritten = session.preview
        Task { [weak self] in
            let delivered = await self?.integrationService(for: agent)?
                .answer(answer, on: ticket) ?? false
            // The store is `@MainActor` and this task body is not: under
            // `SWIFT_APPROACHABLE_CONCURRENCY` the hop back is elided, and a
            // panel property written off the main actor is drawn one publish
            // stale (`AGENTS.md` §7).
            await MainActor.run { [weak self] in
                self?.answerLanded(
                    delivered: delivered,
                    rowID: rowID,
                    previewWhenWritten: previewWhenWritten,
                    notice: notice
                )
            }
        }
    }

    /// What the row becomes once the answer has either arrived or not (§8).
    ///
    /// **The panel does not close** (§8.3): closing on send would shut it in
    /// front of a second request nobody had seen. With nothing left waiting it
    /// unlatches instead — hands the keyboard back and starts answering the
    /// pointer again — and that release is how it says you are finished.
    private func answerLanded(
        delivered: Bool,
        rowID: String,
        previewWhenWritten: String?,
        notice: String
    ) {
        isAnswerInFlight = false
        if delivered {
            answerProgress[rowID] = nil
            answerDraftGeneration &+= 1
        }
        answerNotices[rowID] = AnswerNotice(
            text: delivered
                ? notice
                : "Not sent — the product stopped waiting for this answer",
            previewWhenWritten: previewWhenWritten
        )
        if openRowID == rowID { closeOpenRow() }
        // **The next request opens itself** (§8.2), with its affirmative
        // unarmed — which is what stops the click that answered this one from
        // answering that one. The advance is the whole notification: there is
        // another, and here it is, already open and already legible.
        //
        // Only on an answer that arrived. Advancing past a row that has just
        // said `Not sent` would hide the one line explaining why, and there is
        // nothing to advance *from*: nothing was answered.
        if delivered,
           let next = sessions.first(where: { $0.id != rowID && $0.request != nil }) {
            openRow(next.id)
        }
        // The ticket has been spent either way, so what the mark says about this
        // row is now out of date by one publish. Asking for the refresh is
        // cheaper than teaching the projection to notice a connection closing.
        requestRefresh()
    }

    /// Opens one row, and starts the arrival its affirmative is armed by.
    private func openRow(_ id: String) {
        openRowID = id
        refreshAnswerGround()
        armTheAffirmativeOnArrival(of: id)
    }

    /// Holds the affirmative unarmed for as long as it is still arriving (§6.3).
    private func armTheAffirmativeOnArrival(of id: String) {
        isAffirmativeArmed = false
        armingTask?.cancel()
        armingTask = Task { [weak self] in
            // ``PanelMotion/duration`` rather than the injected clock, and
            // `Task.sleep` rather than ``MonitorClock/sleep(seconds:)``: this
            // is the length of a drawing, not a monitoring window, and it has
            // to end when the animation the eye is following ends. A clock a
            // test never advanced would leave an affirmative armed by nothing.
            try? await Task.sleep(for: .seconds(PanelMotion.duration))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.openRowID == id else { return }
                self.isAffirmativeArmed = true
            }
        }
    }

    /// Puts the ground where what has been typed says it is.
    private func refreshAnswerGround() {
        let ground = AnswerGround.where(
            openSession?.request,
            showing: openRowBody,
            carriesText: !answerDraft.isEmpty
        )
        if answerGround != ground { answerGround = ground }
    }

    /// Closes a row whose request has been settled somewhere else (§8 state 04).
    ///
    /// Granted in the product, cancelled, or the Thread gone: the row closes
    /// **within one publish** and becomes whatever it now is. This is the one
    /// close the user did not ask for, which is why it is the row changing state
    /// rather than a message about a row — and what was typed goes with it,
    /// because there is nothing left to send it to.
    ///
    /// The row that stayed and stopped asking, **and the row that left the list
    /// altogether**.
    ///
    /// The second used to be skipped, on the reasoning that ``openSession``
    /// reads through the list so a departed row already draws nothing. That is
    /// true of the drawing and false of the latch: ``isLatched`` reads
    /// ``openRowID`` itself, and a row that left without being closed keeps the
    /// panel holding the keyboard over nothing at all -- measured on Release,
    /// with the pointer well off the panel and the row's Thread gone, the panel
    /// stayed expanded over an empty list; and with the product quit, it
    /// collapsed to the pill and *still* held the keyboard, so keystrokes went
    /// on reaching this app with nothing on screen to say why (§8 state 04).
    private func closeARowWhoseRequestHasGone() {
        guard let openRowID, !isAnswerInFlight else { return }
        guard sessions.first(where: { $0.id == openRowID })?.request == nil else { return }
        answerProgress[openRowID] = nil
        answerDraftGeneration &+= 1
        closeOpenRow()
    }

    /// Drops every notice the product has since spoken over, and every notice
    /// whose row has gone.
    ///
    /// A notice is the last thing *this app* said about a row; the product
    /// saying anything at all is newer than that, and a row that has left takes
    /// its notice with it.
    private func forgetNoticesTheProductHasOvertaken() {
        guard !answerNotices.isEmpty else { return }
        var previews: [String: String?] = [:]
        for session in sessions { previews[session.id] = session.preview }
        answerNotices = answerNotices.filter { id, notice in
            guard let preview = previews[id] else { return false }
            return preview == notice.previewWhenWritten
        }
        answerProgress = answerProgress.filter { previews[$0.key] != nil }
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
            // Every mark the surface *could* draw. The resting mark counts as
            // one, because it takes the single slot rather than adding one
            // beside it. What the collapsed notched bar is actually drawing is
            // `drawnMarkCount` below -- the two differ only where the wings
            // have been given up.
            matrixCount: presenceMarks.count,
            sessionCount: aggregateSessionCount,
            drawsMark: drawsCompactMarks,
            expandsToPillOnly: expandsToPillOnly,
            expandedContentHeight: expandedContentHeight
        )
    }

    /// Where the panel body's trailing edge has to land, in screen coordinates.
    ///
    /// Non-`nil` only for a notched compact panel, which is pinned to the
    /// cut-out. Everything else is centred on the display: an expanded panel is
    /// far wider than the cut-out and reads as a sheet under the menu bar, not
    /// as an extension of the notch.
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

    /// The contour's upper fillet on the selected display, which is also the
    /// shoulder the window has to leave outside the body on each side.
    var surfaceShoulderRadius: CGFloat {
        PanelMetrics.surfaceShoulderRadius(panelHeight: compactHeight)
    }

    /// The contour's lower corners on the selected display.
    var surfaceBottomCornerRadius: CGFloat {
        PanelMetrics.surfaceBottomCornerRadius(panelHeight: compactHeight)
    }

    var integrationSummary: String {
        switch availability {
        case .setupRequired:
            "Codex integration not set up"
        case .connecting:
            "Connecting to the Codex App Server"
        case .ready:
            "Codex live monitoring connected"
        case .updateAgent:
            "Codex needs updating"
        case .unsupportedVersion:
            "This version of Codex does not support the required protocol"
        case .disconnected:
            "Codex live monitoring not connected"
        }
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

    func pointerEnteredPanel() {
        scheduleHoverAction(after: timing.hoverExpandDelay) { store in
            store.isExpanded = true
        }
    }

    func pointerExitedPanel() {
        // **A row somebody is reading does not close because their pointer
        // drifted** (`answer-in-notch.md` §10). A body of `140` points is read
        // rather than glanced at, and moving to the keyboard is not a pointer
        // movement while any drift is one. This holds even where there is
        // nothing to type: a row that can only be read is the state a person
        // spends longest on.
        guard openRowID == nil else { return }
        scheduleHoverAction(after: timing.hoverCollapseDelay) { store in
            store.isExpanded = false
        }
    }

    /// Re-check the pointer against a panel that has just been resized.
    ///
    /// Hover reaches this store from an `NSTrackingArea`, and a tracking area
    /// only speaks when the pointer *moves*. Shrink the window away from a
    /// pointer that is standing still and no exit is ever delivered — and
    /// because the pointer is outside the window by then, moving it away
    /// afterwards delivers nothing either. The panel stays expanded until the
    /// pointer next enters and leaves, which is the same failure
    /// `OverlayPanelController.orderPanelToMatchConcealment` avoids by
    /// collapsing on the way out.
    ///
    /// **Shutting the quota table no longer reaches this**, and that is a
    /// property of the new footer rather than a case removed: the control rides
    /// the spend line, which is the footer's first line, so the table opens
    /// *beneath* the chevron and closing leaves the pointer `6` to `22` above
    /// the panel's new bottom edge — inside it (`quota-footer-v2.md` §5). The
    /// old footer folded the rules away *above* the line the chevron was on and
    /// took 56pt out from under a pointer that was still by definition, which
    /// is the trap this correction was written for.
    ///
    /// Only the leaving direction is corrected. A pointer that the panel has
    /// *grown* under has not asked for anything, and re-expanding on it would
    /// undo ``collapse()``, which is a decision taken for a reason the pointer
    /// knows nothing about: the concealment watcher closes the panel when the
    /// menu bar goes, and a pointer left resting on the notch by that must not
    /// reopen what was just closed over a full-screen window.
    func panelResized(to windowFrame: NSRect, pointerAt pointer: NSPoint) {
        guard isExpanded else { return }
        guard !OverlayPanelLayout.bodyContainsPointer(
            pointer,
            windowFrame: windowFrame,
            surfaceShoulder: surfaceShoulderRadius
        ) else { return }

        // The ordinary dwell, not an immediate collapse: a pointer that moves
        // back onto the panel while it is still animating cancels this the
        // same way it cancels an exit the tracking area reported.
        pointerExitedPanel()
    }

    func collapse() {
        cancelPendingHoverAction()
        // A panel that is closing cannot be holding a row open behind it, and
        // the keyboard goes back with it -- `⎋` twice, a click outside, a
        // navigation, the menu bar being concealed. The row keeps its place on
        // the list; only its openness ends.
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

    /// Takes one row off the list, at the user's asking.
    ///
    /// **Any status, and it used to be Completed only.** The argument for the
    /// restriction was that a running Turn has not told the user anything yet,
    /// so a row dismissed by accident is one they cannot get back until it
    /// ends — true, and the wrong thing to weigh it against. What it was
    /// actually weighed against turned out to be a row that could not be got
    /// rid of *at all*: a Turn stuck open by a defect is by definition never
    /// Completed, so the one gesture that removes a row was unavailable in
    /// exactly the state where a user most needs it, and the only way out was
    /// to quit the app (a nested agent taking a thread's Turn over,
    /// ``HookTurnState/heldTurnStart``). A control that works only when the app
    /// is behaving is not an escape hatch.
    ///
    /// So the cost is accepted rather than argued away: dismissing a running
    /// row does throw away a notice that has not arrived yet, and it is the
    /// user's to throw. It is one right-click on a row they are looking at,
    /// it names the Turn rather than the thread, and the thread's next Turn
    /// draws a new row — so what an accident costs is one Turn's notice, and
    /// the answer itself is still in the product, one click away on the same
    /// row's thread.
    ///
    /// **What it does not do.** Nothing is deleted, in either product: the
    /// thread, its Turn and its transcript are untouched. Nor is it a claim
    /// that the user read the answer — the read routes decide that from the products' own
    /// evidence, and this one is the user saying they are done with the row,
    /// which needs no evidence beyond their having asked.
    ///
    /// **It ends this Turn's row, not the session's.** The dismissed set is
    /// keyed by ``MonitoredSession/id``, which carries the Turn id, so the next
    /// Turn on the same thread arrives as a new row and lists normally. The
    /// entry is dropped once that product reports the Turn gone while we can
    /// still see the product — see ``forgetDismissalsProvenGone(in:)``.
    ///
    /// **The product is told.** Filtering here alone left the row listed by its
    /// provider, and a listed finished row is one the provider's terminal gate
    /// keeps asking about — a read-state sample a second, for a row that had
    /// stopped being drawn (CR-Fable-003). The record stays here, because only
    /// this layer can tell a removal from a Turn ending; what goes down with
    /// each snapshot request is which rows it covers.
    ///
    /// **It is not a stop button and must not be read as one.** Nothing is sent
    /// to either product, and the Turn behind a dismissed running row goes on
    /// exactly as it was — this removes the app's report of it, which is all
    /// this app has ever done to a Turn.
    ///
    /// This is the only way a user can take a terminal Claude Code row off the
    /// list: read state is not a question those rows can be asked (see
    /// [ADR 0012](../../docs/adr/0012-read-state-is-answered-per-product-or-not-at-all.md)),
    /// so what is left to them otherwise is the next prompt or the session
    /// ending. It used to have company — a `Clear the session list` button in
    /// Settings that dismissed every row at once — and that is gone: it acted
    /// on rows the user was not looking at, from a window they had to open
    /// first, to do in bulk what this does in place.
    @discardableResult
    func dismiss(_ session: MonitoredSession) -> Bool {
        guard !isDismissed(session) else { return false }

        dismissedSessionIDsByAgent[session.agent, default: []].insert(session.id)
        // Republished through the merge rather than by striking the row out of
        // `sessions` here. The list is not the only thing that has to change:
        // the summary status and the product marks are both derived from the
        // rows that are showing, and `apply` is where all three are kept in
        // agreement. Editing the array alone would leave a dismissed row still
        // lighting its product's mark.
        apply(AgentSnapshotMerge.merge(Array(latestByAgent.values)))
        // And the product it belongs to is told, by being asked again now. Its
        // terminal gate is still holding this row as something waiting to be
        // read, which books a re-check every second -- so until the next
        // refresh carries the removal down, the app goes on sampling read state
        // for a row nobody can see (CR-Fable-003). The row's own re-check would
        // deliver it within the second either way; a row that books nothing
        // would have waited for the heartbeat.
        requestRefresh()
        return true
    }

    @discardableResult
    func recheckIntegrationAndWait() async -> HookSetupStatus {
        await refreshAndWait()
        return hookSetupStatus
    }

    func installIntegrationHooks(for agent: AgentKind = MonitorStore.defaultIntegrationAgent) {
        Task { [weak self] in
            _ = await self?.installIntegrationHooksAndWait(for: agent)
        }
    }

    /// Records where the user wants one product's integration, and converges to
    /// it.
    ///
    /// The switch used to read its own guard flags before the task that sets
    /// them had started, so flipping it twice quickly could queue an install
    /// and a removal that then completed in whichever order they happened to
    /// finish in -- not the order the user asked for, and not necessarily
    /// ending where they left the switch (CR-017).
    ///
    /// Intent and execution are now separate. This records the desired state
    /// and returns; a single convergence task per product applies it, re-reading
    /// the desired state after each step so the last flip is the one that
    /// decides where things end up. Intermediate flips are collapsed rather than
    /// replayed -- nobody wants three installs because the switch was tapped
    /// three times.
    func setIntegrationEnabled(
        _ isEnabled: Bool,
        for agent: AgentKind = MonitorStore.defaultIntegrationAgent
    ) {
        guard isEnabled != desiredIntegrationEnabled[agent]
            ?? integrationSwitchIsOn(for: agent) else {
            return
        }

        desiredIntegrationEnabled[agent] = isEnabled
        setSwitch(isEnabled, for: agent)
        startIntegrationConvergenceIfNeeded(for: agent)
    }

    /// Applies the desired integration state, and waits for it to settle.
    @discardableResult
    func setIntegrationEnabledAndWait(
        _ isEnabled: Bool,
        for agent: AgentKind = MonitorStore.defaultIntegrationAgent
    ) async -> Bool {
        setIntegrationEnabled(isEnabled, for: agent)
        await integrationTasks[agent]?.value
        return integrationSwitchIsOn(for: agent) == isEnabled
    }

    /// Starts one product's convergence loop unless one is already running.
    ///
    /// No revision gate here on purpose. ``desiredIntegrationEnabled`` already
    /// records that work is outstanding -- the loop runs until that product's
    /// entry is gone -- so a gate alongside it would be a second, redundant copy
    /// of the same fact, and two sources of truth for "is more work pending" is
    /// worse than one.
    ///
    /// A plain task handle is safe because both the check and the clear happen
    /// on the main actor with no suspension between the loop's last read of
    /// the desired state and the handle being released.
    private func startIntegrationConvergenceIfNeeded(for agent: AgentKind) {
        guard integrationService(for: agent) != nil,
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

        // Someone flipped it again while this was running; that flip owns the
        // switch now, so this outcome must not write over it.
        guard desiredIntegrationEnabled[agent] == desired else { return }
        desiredIntegrationEnabled.removeValue(forKey: agent)

        if succeeded {
            // Re-read health rather than trusting the requested value: the
            // install may have landed in reviewRequired rather than active.
            if let service = integrationService(for: agent) {
                let status = await service.hookSetupStatus()
                setSetupStatus(status, for: agent)
                setSwitch(status.isIntegrationEnabled, for: agent)
            }
        } else {
            setSwitch(!desired, for: agent)
        }
    }

    @discardableResult
    func installIntegrationHooksAndWait(
        for agent: AgentKind = MonitorStore.defaultIntegrationAgent
    ) async -> Bool {
        guard let service = integrationService(for: agent),
              !integrationBusyAgents.contains(agent) else {
            return false
        }
        integrationBusyAgents.insert(agent)
        defer { integrationBusyAgents.remove(agent) }

        do {
            try await service.installHooks()
            let status = await service.hookSetupStatus()
            setSetupStatus(status, for: agent)
            setSwitch(status.isIntegrationEnabled, for: agent)
            lastIntegrationMessage = Self.installedMessage(for: agent)
            return true
        } catch {
            lastIntegrationMessage = "Could not install the hooks: \(error.localizedDescription)"
            return false
        }
    }

    func removeIntegration(for agent: AgentKind = MonitorStore.defaultIntegrationAgent) {
        Task { [weak self] in
            _ = await self?.removeIntegrationAndWait(for: agent)
        }
    }

    @discardableResult
    func removeIntegrationAndWait(
        for agent: AgentKind = MonitorStore.defaultIntegrationAgent
    ) async -> Bool {
        guard let service = integrationService(for: agent),
              !integrationBusyAgents.contains(agent) else {
            return false
        }
        integrationBusyAgents.insert(agent)
        defer { integrationBusyAgents.remove(agent) }

        do {
            try await service.removeHooks()
            // Only this product's half of the merge is dropped. It used to be
            // the whole of it -- sessions, quota and availability cleared
            // outright -- which was harmless while one product had a switch and
            // is not now that both do: turning Claude Code off would have taken
            // Codex's rows off the notch with it.
            //
            // Replaced rather than removed, and with exactly what that product
            // will report on its own next refresh: an unregistered product
            // answers `setupRequired` with no rows and nothing to say about
            // quota. Removing the key instead would let a store with one
            // product fall through to `disconnected`, which is not what
            // "you just switched this off" means.
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
            setSwitch(false, for: agent)
            lastIntegrationMessage = Self.removedMessage(for: agent)
            return true
        } catch {
            lastIntegrationMessage = "Could not remove the integration: \(error.localizedDescription)"
            return false
        }
    }

    /// What to say once a product's definitions are in its file.
    ///
    /// Per product because the next step is: Codex keys trust to each
    /// definition's place in the file and will not run one until the user says
    /// so, while Claude Code runs what is registered.
    ///
    /// Both products get the copy beside their file, and only Claude Code's
    /// message names it — not because the Codex one is not made, but because
    /// that message has a required action to carry and a second sentence would
    /// compete with it. The disclosure that has to land is the one *before* the
    /// switch is flipped, and both footnotes name both files.
    nonisolated private static func installedMessage(for agent: AgentKind) -> String {
        switch agent {
        case .codex:
            "Hooks installed; open /hooks in Codex and trust the new definitions."
        case .claudeCode:
            "Hooks written to ~/.claude/settings.json. Your file as it was is beside "
                + "it, as settings.json.notchline-backup."
        }
    }

    nonisolated private static func removedMessage(for agent: AgentKind) -> String {
        switch agent {
        case .codex:
            "The hooks managed by Notchline have been removed from ~/.codex/hooks.json."
        case .claudeCode:
            "The hooks managed by Notchline have been removed from ~/.claude/settings.json; "
                + "nothing else in it was touched."
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

    /// Runs one refresh cycle and waits for every product to answer.
    func refreshAndWaitForTesting() async {
        await refreshAndWait()
    }

    /// The instant the store would next wake for, or nil when only the
    /// heartbeat is left. Exposed so the deadline arithmetic is assertable
    /// without arming a real wake-up.
    func nextWakeUpForTesting() async -> Date? {
        (
            await providerDeadlines() + stabilityGates.values.map(\.nextPublishDeadline)
        ).compactMap { $0 }.min()
    }

    /// Feeds one product's answer through the same path a refresh uses, so a
    /// test exercises the merge rather than bypassing it.
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
            // `MainActor.run`, not a bare `action(self)`, and the reason is not
            // style. `action` is `@MainActor`, this store is `@MainActor`, and
            // the task was started from a `@MainActor` method -- and none of
            // that puts the resumption back on the main thread. Under
            // `SWIFT_APPROACHABLE_CONCURRENCY` the task body is
            // `nonisolated(nonsending)`, so its isolation is carried
            // dynamically rather than in its type, and the hop back after
            // `clock.sleep` is elided; measured in Release, `action` ran on a
            // cooperative-pool thread every time.
            //
            // What that costs is not a theoretical race. Writing `isExpanded`
            // off the main thread fires `objectWillChange` from that thread,
            // SwiftUI wakes the main thread to re-render, and the render can
            // read the property *before* the background thread has stored it --
            // between `willSet` and `didSet`. The body then draws the previous
            // expansion state and nothing invalidates it again, so the
            // collapsed notch keeps the expanded header's gear where its timer
            // belongs until some unrelated publish repairs it. Measured in
            // Release: three failures in ten hover bursts before this hop, none
            // in a hundred and twenty after it.
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
                    // A watcher signal only has to converge, so it does not
                    // wait -- but it must not be dropped either, which is what
                    // the gate guarantees.
                    self?.requestRefresh()
                }
            }
        }

        // Refreshes are driven by the watchers above. The only other trigger is
        // the wake-up ``scheduleNextWake`` arms whenever a refresh run finishes;
        // this first request is what starts that chain. Nothing samples on a
        // cadence.
        requestRefresh()
    }

    /// Arms the next wake-up from the state a refresh has just left behind.
    ///
    /// This has to hang off the *end of a refresh run*, not off an iteration of
    /// a loop of its own, and that distinction was the whole of the bug. A
    /// provider books its re-check during a refresh; most refreshes are driven
    /// by a watcher edge, not by the store. So a loop that computed the deadline
    /// only after its own `refreshAndWait` armed itself from state in which the
    /// row that now needs re-checking did not yet exist -- for the heartbeat --
    /// and then slept through the deadline the edge-driven refresh had just
    /// booked. A finished Turn waiting on the user asked to be looked at in a
    /// second and was looked at in up to a minute; the same missed re-arm
    /// delayed the disconnect grace re-examination and the usage retry.
    ///
    /// Every path into a refresh goes through ``startRefreshRunIfNeeded``, so
    /// arming here covers the watchers, Recheck, and the heartbeat alike. The
    /// wake-up is a task rather than an awaited sleep because the run that
    /// schedules it must be able to finish -- ``refreshAndWait`` is waiting on
    /// exactly that.
    private func scheduleNextWake() {
        wakeTask?.cancel()
        wakeTask = Task { [weak self] in
            guard let self else { return }
            let heartbeat = self.timing.heartbeatInterval
            // The gates' own deadlines count: a suppressed disconnect has to be
            // re-examined when its grace expires, not whenever some provider
            // happens to want attention next.
            let deadline = (
                await self.providerDeadlines()
                    + self.stabilityGates.values.map(\.nextPublishDeadline)
            ).compactMap { $0 }.min()
            guard !Task.isCancelled else { return }
            // An overdue deadline is clamped up to the floor, never down to
            // zero. Sleeping zero here re-runs a full snapshot -- a
            // LaunchServices round trip on the main thread and several stat
            // calls -- against a deadline the refresh cannot move, which is
            // a busy loop, not a catch-up.
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

    /// Re-stage a drawing's fixed answers, on a store that draws rather than
    /// watches.
    ///
    /// The first-run specimens are stores with no services (``NotchSpecimen``),
    /// so after `init` nothing will ever publish to them again -- and their
    /// reading is a clock, counting on from the moment the window opened. Handing
    /// the same rows back with a fresh start is what wraps it, and it goes
    /// through the ordinary merge, so a re-staged drawing is still only what a
    /// refresh could have produced.
    ///
    /// Refused on a watching store. Nothing outside a provider may put rows in
    /// front of the user; a caller that got this wrong would be publishing
    /// fiction to the notch.
    func restageSpecimen(_ snapshots: [AgentSnapshot]) {
        guard services.isEmpty else { return }
        for snapshot in snapshots {
            latestByAgent[snapshot.agent] = snapshot
        }
        apply(AgentSnapshotMerge.merge(Array(latestByAgent.values)))
    }

    private func apply(_ snapshot: MonitorSnapshot) {
        let now = clock.now()
        forgetDismissalsProvenGone(in: snapshot)
        let undismissedSessions = snapshot.sessions.filter { !isDismissed($0) }
        let visibleSessions = undismissedSessions
        // Before `sessions` moves, because what left is the difference between
        // the two. This is the one funnel every row leaves through -- a
        // dismissal republishes through here as well -- so it is the only place
        // the queue has to be fed from.
        recordDepartures(
            leaving: visibleSessions,
            connectedAgents: Set(snapshot.connectedAgents),
            at: now
        )
        // Re-aggregated rather than taken from the snapshot: a dismissed row
        // must stop counting towards the summary the moment it stops showing.
        let aggregateStatus = MonitorAggregation.status(
            agents: snapshot.agents,
            sessions: undismissedSessions
        )
        let integrationMessage = snapshot.diagnostic ?? "Codex data refreshed"

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
        // Rebuilt from the visible rows, not taken from the snapshot: a
        // dismissed row must stop lighting its product's mark the moment it
        // stops showing, exactly as it stops counting towards the summary.
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

    /// Archives what this app watched finish, and takes out what has come back.
    ///
    /// **The whole of this is Notchline's own lifecycle.** Nothing here asks a
    /// product what threads it has, or has had: the queue is a record of what
    /// *this list* drew and then let go of, which is what makes it memory
    /// rather than history (`PRD.md` §2 goal 9). The only two facts it reads
    /// are the row's last state as this app observed it and whether its product
    /// is present -- both already on the surface.
    ///
    /// ```text
    /// nothing → Running → Completed ─read→ archived ─┐
    ///                        ▲                       │
    ///                        └───────────────────────┘   submits again
    ///                                 archived ─expire/dismiss→ nothing
    /// ```
    ///
    /// **Leaving the list is the timing; finishing is the reason.** A row that
    /// disappears while this app last saw it working did not complete -- it
    /// vanished -- and vanishing is not archiving. That is what keeps the queue
    /// out of every ordinary way a product stops reporting rows that are very
    /// much alive (`tech-design.md` §15.1), and it is also the honest answer
    /// for a session killed under a connected product, which App Server
    /// membership correction retires with its Turn still open.
    ///
    /// A dismissal is the other way in, and it is the user's own gesture rather
    /// than a transition: the product goes on listing a dismissed Turn, so the
    /// dismissed set is what answers there and the row's state only decides
    /// which of the two dismissals it was.
    ///
    /// **The last loop is the return arrow**, and it doubles as the repair for
    /// the one case presence cannot refuse: Codex Desktop quitting empties its
    /// list *before* availability catches up, because presence is a kernel fact
    /// and precedes any message about Turns, so its finished rows are archived
    /// a moment early. Their Thread coming back takes them straight out again,
    /// because a Thread cannot be live and archived at once (§5).
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

        // The membrane, in both directions: a Thread that submits again leaves
        // the queue and reappears above the seam as the same row.
        for row in visibleSessions {
            departuresByThread.removeValue(forKey: RecentDeparture.key(for: row))
        }
    }

    /// Which arrow into the queue this row just took, or `nil` for a row that
    /// left the list without ending -- which is not an arrow at all.
    private func departureReason(
        for row: MonitoredSession,
        connectedAgents: Set<AgentKind>
    ) -> RecentDeparture.Reason? {
        if isDismissed(row) {
            // The reading below the rule is an age either way, so it stays
            // honest on a Turn that never finished (§2.4 rule 05).
            return row.status.keepsTiming ? .dismissedWhileRunning : .dismissed
        }
        // The lifecycle's own arrow, and this app's own observation of it: the
        // Turn was terminal when it was last drawn, and then the list stopped
        // reporting it -- which is the membership gate saying its product has
        // recorded the Thread as read (`tech-design.md` §12).
        guard !row.status.keepsTiming else { return nil }
        // And a product going dark takes its rows off the surface without
        // ending anything. Presence, not its list: what this asks is whether
        // the product was there to have read it.
        guard connectedAgents.contains(row.agent) else { return nil }
        return .read
    }

    /// Republishes the queue as of `now`, dropping whatever has aged out.
    ///
    /// **Eviction is a filter, not a timer** (§10). A queue nobody watched for
    /// six hours is empty the moment it is read, and nothing had to run while
    /// the panel was shut to make that true; a tick only makes the change
    /// visible to somebody already watching.
    private func refreshRecentDepartures(at now: Date) {
        var kept = departuresByThread.filter {
            $0.value.age(at: now) < Self.recentWindow
        }
        // Most recently departed first, with the key breaking a tie: several
        // rows can leave in one pass and share an instant exactly, and an order
        // that depends on dictionary iteration would flap between publishes.
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
        // **Only while the ages are on screen.** This is published, and one
        // publish re-renders the whole overlay (`AGENTS.md` §7) — so a queue
        // held across a boundary with the panel shut, or with the queue folded,
        // would buy a re-render a minute for a reading nobody is drawing. Both
        // states re-read on the way back in: opening either calls this.
        //
        // Ordered before the readings are compared, so a member added in this
        // pass is measured against its own arrival rather than against whenever
        // the clock was last consulted.
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

    /// Moves the queue's ages while somebody is looking at them.
    ///
    /// **This is the visible half only, and it is the smaller one.** Eviction
    /// and the readings are both correct without it, because
    /// ``refreshRecentDepartures(at:)`` is a filter as of `now` and opening the
    /// panel is a read -- so a queue nobody watched for six hours is empty
    /// before it is drawn, and every age is right at the instant somebody
    /// looks. What this adds is the one case that read cannot cover: a panel
    /// held open across a boundary, where `9m` has to become `10m` under a
    /// pointer that has not moved.
    ///
    /// **It runs only while the panel is open and the queue has members**, so
    /// on the overwhelming majority of this app's life it does not exist. The
    /// panel is a hover surface: it is open for seconds at a time, and most
    /// openings will not cross a boundary at all.
    ///
    /// It sleeps to the **next boundary any member actually crosses**, not to a
    /// flat minute. A flat minute would drift into crossing two boundaries in
    /// one wake-up and visibly skip a reading -- the fault
    /// ``secondsUntilNextTick(after:now:)`` exists to avoid one rule up -- and
    /// it would also wake up to change nothing at all for a queue whose members
    /// all departed within the same few seconds.
    private func updateRecentTicking() {
        // Nothing to move: stop entirely rather than wake to discover it.
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
                // `MainActor.run`, not a bare call, for the reason
                // ``scheduleHoverAction(after:action:)`` spells out: the task
                // body is `nonisolated(nonsending)` under
                // `SWIFT_APPROACHABLE_CONCURRENCY`, so resuming from a
                // suspension does not put this back on the main thread, and
                // every property the overlay renders from must be written there
                // (`AGENTS.md` §7).
                await MainActor.run {
                    self.refreshRecentDepartures(at: self.clock.now())
                }
            }
        }
    }

    /// When the first thing the panel is drawing changes, or `nil` if nothing
    /// can.
    ///
    /// **Which instants matter depends on the fold**, because that decides what
    /// is on screen. Open, every age is drawn, and a member reads in whole
    /// minutes below an hour and whole hours above one — so its next change is
    /// its own next such boundary measured from when it left. Folded, no age is
    /// drawn at all and the only thing that moves is the seam's own count, so
    /// the one instant worth waking for is the member's expiry. A folded queue
    /// therefore wakes at most once per member however long it is held open.
    ///
    /// **The eviction needs no term of its own in the open case.** A member can
    /// only reach five hours by passing four, so the hour boundary that would
    /// have drawn `5h` is exactly the instant the row is dropped instead.
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

    /// Takes one row out of the queue, at the user's asking (§2.4 rule 09).
    ///
    /// The live row's own secondary click, meaning the same thing one rule
    /// down, and the only way out that anybody performs -- the other is the
    /// window closing behind the row.
    ///
    /// **Nothing is remembered about the removal**, and it needs no equivalent
    /// of ``dismissedSessionIDsByAgent``. A row taken out here can only come
    /// back by its Thread departing again, which means it was on the live list
    /// in between -- so there is no re-entry to suppress and nothing to forget
    /// later.
    @discardableResult
    func removeFromRecent(_ departure: RecentDeparture) -> Bool {
        guard departuresByThread.removeValue(forKey: departure.id) != nil else {
            return false
        }
        refreshRecentDepartures(at: clock.now())
        return true
    }

    /// Opens or folds what the list has let go of.
    func toggleRecent() { isRecentExpanded.toggle() }

    private func isDismissed(_ session: MonitoredSession) -> Bool {
        dismissedSessionIDsByAgent[session.agent]?.contains(session.id) ?? false
    }

    /// Drops the dismissals whose Turn its own product has stopped listing
    /// *while we could see that product*.
    ///
    /// The set has to be bounded — a dismissal the app never forgets is a leak
    /// — but "absent from this snapshot" is not the same fact as "gone", and
    /// reading it that way put dismissed rows back on the notch (CR-Fable-004).
    /// A product stops listing its rows for ordinary reasons that leave the
    /// Turn very much alive and about to be republished: Codex Desktop quits,
    /// its App Server blips for longer than the grace period, Claude Code has
    /// no open window and so withholds its rows rather than discarding them
    /// (`tech-design.md` §15.1). Any of those used to erase that product's
    /// dismissals, and the next hook event brought the row the user had just
    /// waved away straight back.
    ///
    /// So the evidence required is the product itself being observable — open
    /// *and* answering — and the Turn not being in what it listed. A product we
    /// cannot see is not a witness to anything, and its dismissals are kept
    /// untouched until it can speak for them again. Each product answers only
    /// for its own: one being unreachable must not pin the other's set, and
    /// one being healthy must not clear the other's.
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

    /// Records one product's answer and republishes the merge.
    ///
    /// Each product is gated against its *own* previous availability, so a blip
    /// on one cannot suppress another's publish, and a product that is
    /// suppressed keeps its last trusted answer rather than dropping out of the
    /// merge entirely — its rows stay where they were.
    private func record(_ snapshot: AgentSnapshot, observedAt: Date) {
        let agent = snapshot.agent
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

    /// How far along a product's registration is.
    func setupStatus(for agent: AgentKind) -> HookSetupStatus {
        setupStatusByAgent[agent] ?? .notInstalled
    }

    /// The Codex registration, which is what the no-argument spelling has
    /// always meant.
    var hookSetupStatus: HookSetupStatus {
        setupStatus(for: Self.defaultIntegrationAgent)
    }

    /// Where one product's switch is sitting.
    func integrationSwitchIsOn(for agent: AgentKind) -> Bool {
        integrationSwitchIsOnByAgent[agent] ?? false
    }

    var integrationSwitchIsOn: Bool {
        integrationSwitchIsOn(for: Self.defaultIntegrationAgent)
    }

    /// Whether that product's hooks are being written or removed right now, and
    /// therefore whether its switch should refuse a second answer.
    func isIntegrationBusy(for agent: AgentKind) -> Bool {
        integrationBusyAgents.contains(agent)
    }

    /// Both writes go through here so the published dictionaries move only when
    /// the value in them actually changes. A refresh restates the same status
    /// every second, and one publish on this store re-evaluates the whole
    /// overlay (`AGENTS.md` §7).
    private func setSetupStatus(_ status: HookSetupStatus, for agent: AgentKind) {
        guard setupStatusByAgent[agent] != status else { return }
        setupStatusByAgent[agent] = status
    }

    private func setSwitch(_ isOn: Bool, for agent: AgentKind) {
        guard integrationSwitchIsOnByAgent[agent] != isOn else { return }
        integrationSwitchIsOnByAgent[agent] = isOn
    }

    /// What went wrong on this product's side, if anything did.
    ///
    /// Read off the same stored answer as ``agentAvailability(for:)`` rather
    /// than published on its own: the two are shown on the same line of the
    /// same card, and a second `@Published` would republish the whole store --
    /// the overlay included -- for a caption in a window that is usually shut
    /// (`AGENTS.md` §7). This is the reading end of the chain CR-029 found
    /// computed and never shown.
    func diagnostic(for agent: AgentKind) -> String? {
        latestByAgent[agent]?.diagnostic
    }

    /// Re-reads what a product has left on disk when it answers.
    ///
    /// Off the refresh for the same reason the instructions are: it lists a
    /// directory, and an open panel does not need that once a second. The
    /// measurement behind it keeps its own freshness window, so this asking
    /// often costs nothing.
    private func refreshDiskFootprintIfNeeded(for agent: AgentKind) {
        guard diskFootprintTask == nil,
              let service = services.first(where: { $0.agent == agent }) else {
            return
        }
        diskFootprintTask = Task { [weak self] in
            let report = await service.diskFootprint()
            guard let self else { return }
            self.diskFootprintTask = nil
            // Absence *is* `leavesNothing`, so it has to be folded into the
            // optional before the comparison. Compared the other way round,
            // every refresh of a product that leaves nothing would find `nil`
            // unequal to `.leavesNothing`, write the same absence back, and
            // publish -- and one publish on this store re-evaluates the whole
            // overlay (`AGENTS.md` §7).
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

    /// Keeps one product's switch in step with what its file actually says.
    ///
    /// Skipped while that product's own install or removal is in flight: the
    /// switch is showing where the user just put it, and a refresh landing
    /// mid-write would flick it back to the state the write is on its way to
    /// leaving. Another product being busy is none of this one's business,
    /// which is the whole reason the flag is a set rather than two booleans.
    private func applyIntegrationHealth(for agent: AgentKind) {
        guard let refreshed = setupStatusByAgent[agent],
              !integrationBusyAgents.contains(agent) else {
            return
        }
        setSwitch(refreshed.isIntegrationEnabled, for: agent)
    }

    /// Each provider's next deadline, with providers that cannot advance their
    /// own dropped.
    ///
    /// A provider that reports the same already-overdue instant twice has said
    /// everything it is going to say about it. Leaving it in the shared minimum
    /// would pin the loop to the refresh floor and drag every healthy provider
    /// into a full merged refresh every second alongside it.
    private func providerDeadlines() async -> [Date?] {
        var deadlines: [Date?] = []
        let now = clock.now()
        for service in services {
            let agent = service.agent
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

    /// Requests a refresh without waiting for it.
    ///
    /// For triggers that only need the state to converge -- the scheduled
    /// wake-up, the directory watchers. If one is already running, this raises
    /// the gate so another follows; it is never dropped.
    private func requestRefresh() {
        refreshGate.request()
        startRefreshRunIfNeeded()
    }

    /// Requests a refresh and waits for one that accounts for this request.
    ///
    /// For the user pressing Recheck. It used to call `performRefresh`, which
    /// returned immediately whenever an automatic refresh happened to be in
    /// flight -- so the button finished instantly and handed back the status it
    /// already had (CR-008). Waiting on the gate's own revision is what makes
    /// "I asked, so tell me what is true now" mean something.
    private func refreshAndWait() async {
        let revision = refreshGate.request()
        startRefreshRunIfNeeded()

        // At most two iterations: a run that begins after this request covers
        // it, and revisions only move forward.
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
            // The run is over and the gate is idle, so this is the first moment
            // the providers' deadlines describe the state the user is actually
            // looking at. Arming from here is what makes a re-check booked by a
            // watcher-driven refresh get slept on.
            guard !Task.isCancelled else { return }
            self.scheduleNextWake()
        }
    }

    /// Asks every product at once and publishes each answer as it lands.
    ///
    /// Publishing per answer rather than after the whole group is what keeps a
    /// slow provider from holding up a fast one: the fast product's rows are on
    /// screen while the slow one is still being asked. The group is still
    /// awaited, so a caller that wants "everyone has answered" — Recheck — gets
    /// exactly that.
    ///
    /// Nothing here cancels a slow fetch. Cancelling throws the work away and
    /// the next cycle starts it again, which is how "slow" turns into "never";
    /// each provider is responsible for bounding its own request instead.
    private func performRefresh() async {
        guard !services.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for service in services {
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    // What the user has already taken off this product's list
                    // travels with the request. The store keeps the record --
                    // it is the only layer that can tell a removal from a Turn
                    // ending -- but the product is the only one that can stop
                    // paying for it, so it is handed down on every ask rather
                    // than pushed once and remembered. Pushing it would have to
                    // survive everything that resets a provider's gate; this
                    // cannot go stale, because it is read a line before it is
                    // used (CR-Fable-003).
                    let snapshot = await service.fetchSnapshot(
                        dismissedRowIDs: self.dismissedSessionIDsByAgent[
                            service.agent
                        ] ?? []
                    )
                    guard !Task.isCancelled else { return }
                    // The snapshot already carries the health the same refresh
                    // observed; asking again would drain the store twice a
                    // cycle, and the second reading would take delivery of what
                    // the first was owed.
                    self.record(snapshot, observedAt: self.clock.now())
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
