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

    var menuBarHeight: CGFloat {
        let occupiedTopHeight = max(0, frame.maxY - visibleFrame.maxY)
        let measuredHeight = max(occupiedTopHeight, safeAreaInsets.top)
        return measuredHeight >= 1
            ? measuredHeight
            : max(1, fallbackMenuBarHeight)
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
        "\(geometry.title) · menu bar \(Int(menuBarHeight.rounded())) pt"
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

/// The collapsed surface's trailing wing: a subagent chip cluster sharing one
/// slot with the elapsed timer, exactly as the plain string this replaced
/// (`compactTrailingText`) used to share it.
///
/// One value rather than two views for the same reason the old string was
/// one: the panel's width is measured from it, so a chip cluster and a timer
/// that could independently disagree about what they drew would leave the
/// width composed from two readings instead of one.
struct CompactTrailingReading: Equatable {
    var chips: SubagentChipCounts = .empty
    var timerText: String?

    static let empty = CompactTrailingReading()

    var isEmpty: Bool { chips.isEmpty && timerText == nil }
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
    static let expandedBaselineWidth: CGFloat = 520
    static let sessionRowHeight: CGFloat = 80
    static let maximumVisibleSessionCount = 3
    static let expandedSessionViewportHeight = sessionRowHeight
        * CGFloat(maximumVisibleSessionCount)
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
    /// above it and the quota rules below it — whatever that value becomes.
    ///
    /// The `Colour bar` attribution is the one exception, and it moves the
    /// gutter rather than the padding — see ``sessionRowRailGutter``.
    static let sessionRowGutter: CGFloat = 6
    static let sessionRowPadding: CGFloat = expandedHorizontalPadding
        - sessionRowGutter
    /// The row block's margin while the `Colour bar` rail is drawn.
    ///
    /// The rail is flush with the block's leading edge, so the block's margin
    /// is where the rail lands — and at the shared `6` it landed half the
    /// panel's inset short of everything it is read against, the status matrix
    /// above and the quota rules below. Widening the margin to the full
    /// `expandedHorizontalPadding` puts the stroke on that same line. The two
    /// stop being one margin split in two: the padding behind the stroke is the
    /// rail's own (``sessionRowRailPadding``), and the row's text steps in
    /// behind the rail rather than sitting on top of it. This applies only
    /// while the rail is drawn — with one product connected there is no rail,
    /// and the row keeps the `6 + 6` that lands its text on the panel's own
    /// margin.
    static let sessionRowRailGutter: CGFloat = expandedHorizontalPadding
    /// The gap between the rail and the text it marks.
    ///
    /// Wider than the row's ordinary `6`, because this one is doing different
    /// work: the ordinary padding is the row's inset from a panel edge, and
    /// this is the clearance between a `2pt` stroke and the words beside it.
    /// At `6` the two read as one object.
    static let sessionRowRailPadding: CGFloat = 8
    /// The `Colour bar` attribution rail, flush with the row block's leading
    /// edge. It is narrower than the margin it sits on, so it marks the row
    /// without crowding the block's own corner.
    static let sessionRowRailWidth: CGFloat = 2
    static let sessionRowRailRadius: CGFloat = 1
    /// The row's three text lines, as the row lays them out.
    ///
    /// They live here rather than as literals in the view because the rail is
    /// measured against them: it spans the row's text exactly, so a line height
    /// that changed in the view and not here would leave the stroke running
    /// past the words or stopping short of them.
    static let sessionRowCaptionHeight: CGFloat = 14
    /// The `Badge` caption is a point taller than the text line it replaces.
    /// The rail never meets it — one style or the other — but the row does.
    static let sessionRowBadgeCaptionHeight: CGFloat = 16
    static let sessionRowTitleHeight: CGFloat = 17
    static let sessionRowPreviewHeight: CGFloat = 18
    static let sessionRowLineSpacing: CGFloat = 2

    /// The rail spans the row's text: the top of the Project caption to the
    /// bottom of the last line, and nothing beyond it.
    ///
    /// Half the row tall was a shape rather than a measurement — it marked the
    /// row's middle and stopped short of both the caption above and the preview
    /// below, so it read as a tick beside the row instead of as the row's own
    /// edge. It takes the row's actual content because a row without a preview
    /// is genuinely shorter: a fixed three-line stroke would overhang a
    /// two-line row by `10` at each end, which is the same not-quite-aligned
    /// mistake the gutter change just fixed.
    static func sessionRowRailHeight(hasPreview: Bool) -> CGFloat {
        let head = sessionRowCaptionHeight
            + sessionRowLineSpacing
            + sessionRowTitleHeight
        guard hasPreview else { return head }
        return head + sessionRowLineSpacing + sessionRowPreviewHeight
    }
    static let expandedReadoutSpacing: CGFloat = 12
    static let expandedNotchClearance: CGFloat = 8
    /// Single-Codex footer: one rule and one inline caption, as today.
    static let expandedFooterHeight: CGFloat = 40
    /// Claude Code alone: two windows fill the caption line, so today's usage
    /// needs a line of its own. This asymmetry between the two single-product
    /// forms is known and accepted — it follows from one product having two
    /// windows and the other having one.
    static let claudeCodeOnlyFooterHeight: CGFloat = 54
    /// Both products: two rule blocks and a shared usage line.
    static let dualFooterHeight: CGFloat = 84
    static let footerRuleHeight: CGFloat = 3
    /// A rule to its own caption.
    static let footerCaptionSpacing: CGFloat = 5
    /// One product's block to the next product's.
    static let footerRuleSpacing: CGFloat = 9
    /// Between two half-width rules of the same product.
    static let footerWindowSpacing: CGFloat = 8

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
    /// Composed from measured text like every other compact width rather than
    /// taken as a constant. `figma-design.md` §6.4 gives `400 × 46` notched and
    /// `208 × 46` no-notch, while its own checklist gives `400.6` and `224.6`;
    /// the two disagree, so the composition rule is authoritative here and the
    /// derived values are recorded in that doc.
    static func restingExpandedWidth(
        geometry: DisplayGeometry,
        centerOcclusionWidth: CGFloat,
        compactHeight: CGFloat
    ) -> CGFloat {
        let leading = expandedHorizontalPadding
            + statusMatrixSize
            + expandedReadoutSpacing
            + compactLabelWidth(.disconnected)
        let trailing = expandedReadoutSpacing
            + settingsButtonSize(compactHeight: compactHeight)
            + expandedHorizontalPadding
        guard geometry == .notched, centerOcclusionWidth >= 1 else {
            return ceil(leading + trailing)
        }
        return ceil(
            leading
                + expandedNotchClearance
                + centerOcclusionWidth
                + expandedNotchClearance
                + trailing
        )
    }

    /// Folded, the footer keeps today's line and nothing else.
    ///
    /// One height for every shape, which is the point: folded, the expanded
    /// panel is `314` whether one product is connected or both, and its height
    /// stops depending on what happens to be running. See §5.4.
    static let foldedFooterHeight: CGFloat = 28
    /// The disclosure at the trailing end of the footer's last line.
    static let quotaFoldControlSize: CGFloat = 16

    /// Footer height by shape. See `dual-agent-design.md` §5.1 and §5.4.
    static func footerHeight(rules: [FooterRule], isFolded: Bool = false) -> CGFloat {
        // With no rules there is nothing to fold, so folding cannot shrink it.
        if isFolded, !rules.isEmpty { return foldedFooterHeight }
        if rules.count > 1 { return dualFooterHeight }
        if rules.first?.windows.count ?? 0 > 1 { return claudeCodeOnlyFooterHeight }
        return expandedFooterHeight
    }
    static let thinExpandedBodyHeight: CGFloat = 48
    static let expandedContentHeight: CGFloat = expandedSessionViewportHeight
        + expandedFooterHeight
    static let thinExpandedContentHeight: CGFloat = thinExpandedBodyHeight
        + expandedFooterHeight
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

    /// Compact content leading the notch: padding, the matrix, and — where there
    /// is no physical notch to work around — the status label as well.
    ///
    /// Menu bar height no longer appears here. Neither the indicator nor the
    /// label scales with it, so it governs panel height and corner radius only.
    static func compactLeadingWidth(
        statusReadoutText: String,
        showsStatusText: Bool,
        markCount: Int = 1
    ) -> CGFloat {
        var width = expandedHorizontalPadding + marksWidth(markCount)
        if showsStatusText {
            width += expandedReadoutSpacing
                + textWidth(statusReadoutText, font: statusLabelFont)
        }
        return width
    }

    /// The marks themselves: one matrix each, with the pair spacing between.
    ///
    /// `6` because it lands on the matrix's own `5.84` cell pitch, so the gap
    /// reads as a missing column rather than an arbitrary space. `4` merges the
    /// pair into one 3×6 grid; `8` stops reading as a pair at all.
    static func marksWidth(_ markCount: Int) -> CGFloat {
        guard markCount > 0 else { return 0 }
        return CGFloat(markCount) * statusMatrixSize
            + CGFloat(markCount - 1) * compactMatrixSpacing
    }

    /// The subagent numeral chip: font, minimum size, and the padding that
    /// lets a two-digit count grow it rather than clip it.
    ///
    /// `dual-agent-design.md` §10 draws the chip at a fixed `15 × 15` for the
    /// single-digit counts every mockup shows; that figure is this type's
    /// floor rather than a hardcoded width -- `figma-design.md` §4.6's one
    /// lesson is that a slot must grow to fit what it actually draws, and a
    /// count of `10` or more is real once a thread has spawned enough
    /// subagents.
    static let subagentChipFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
    static let subagentChipMinSize: CGFloat = 15
    static let subagentChipCornerRadius: CGFloat = 4
    static let subagentChipHorizontalPadding: CGFloat = 4
    /// Between the two chips, when both are drawn.
    static let subagentChipSpacing: CGFloat = 4
    /// Between the chip cluster and the timer it shares the trailing slot
    /// with.
    static let subagentChipTimerSpacing: CGFloat = 8

    /// One chip's width, hugging its digits at the minimum size and growing
    /// only when a wider count needs it.
    static func subagentChipWidth(_ count: Int) -> CGFloat {
        let measured = textWidth("\(count)", font: subagentChipFont)
            + subagentChipHorizontalPadding * 2
        return max(subagentChipMinSize, ceil(measured))
    }

    /// The chip cluster's width -- zero, one or two chips, spaced apart when
    /// both are drawn. A chip whose count is zero contributes nothing: see
    /// ``SubagentChipCounts``.
    static func subagentChipsWidth(_ counts: SubagentChipCounts) -> CGFloat {
        var widths: [CGFloat] = []
        if counts.attention > 0 { widths.append(subagentChipWidth(counts.attention)) }
        if counts.running > 0 { widths.append(subagentChipWidth(counts.running)) }
        guard !widths.isEmpty else { return 0 }
        return widths.reduce(0, +) + CGFloat(widths.count - 1) * subagentChipSpacing
    }

    /// Everything the trailing slot actually draws: the chip cluster, the
    /// timer, and the gap between them when both are present.
    static func compactTrailingReadingWidth(_ trailing: CompactTrailingReading) -> CGFloat {
        let chipsWidth = subagentChipsWidth(trailing.chips)
        guard let timerText = trailing.timerText else { return chipsWidth }
        let timerWidth = textWidth(timerText, font: timerFont)
        guard chipsWidth > 0 else { return timerWidth }
        return chipsWidth + subagentChipTimerSpacing + timerWidth
    }

    /// Compact content trailing the notch, including its own trailing padding.
    ///
    /// Zero unless the collapsed surface has a reading to put there -- an
    /// elapsed value, a subagent chip cluster, or both. The usage ring used
    /// to sit here unconditionally, which meant an idle notched display
    /// rendered a blank wing that read as a second, fake notch.
    static func compactTrailingWidth(trailing: CompactTrailingReading) -> CGFloat {
        guard !trailing.isEmpty else { return 0 }
        return compactTrailingReadingWidth(trailing) + expandedHorizontalPadding
    }

    /// How far the compact body reaches past the cut-out's trailing edge.
    ///
    /// A notched panel is pinned to the notch, not the screen: its right edge
    /// sits on the cut-out's right edge, plus whatever trailing wing is drawn.
    /// Everything that rounds -- the ceiled width, a cut-out that is not
    /// perfectly centred -- is absorbed by the leading wing, which is padding
    /// and can take it, rather than by the edge that has to meet the hardware.
    static func compactTrailingWingWidth(trailing: CompactTrailingReading) -> CGFloat {
        let content = compactTrailingWidth(trailing: trailing)
        return content > 0 ? content + expandedNotchClearance : 0
    }

    /// Leading wing on a notched display: padding, the marks, and the clearance.
    ///
    /// Zero marks draws nothing at all. A notched display at rest hides the
    /// whole wing rather than parking a grey mark beside the cut-out — the
    /// cut-out is already a shape on the screen, and a second one next to it
    /// carries no information. A no-notch display keeps its mark instead,
    /// because a control that vanishes from the menu bar takes its position
    /// with it and everything to its left slides over.
    private static func notchedLeadingWidth(markCount: Int) -> CGFloat {
        guard markCount > 0 else { return 0 }
        return expandedHorizontalPadding
            + marksWidth(markCount)
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
    /// Both radii are shares of the menu bar height rather than constants,
    /// because that is how the hardware behaves. The cut-out is a fixed shape
    /// in millimetres; the menu bar on a notched display is exactly as tall as
    /// it, and both shrink together in points as the display scaling coarsens —
    /// `220 × 38` at *More Space* down to `127 × 22` at *Larger Text*. A pinned
    /// radius is therefore right at one scaling and too round at every other
    /// one, which is what a fixed `10` was doing on notched displays.
    static func surfaceShoulderRadius(menuBarHeight: CGFloat) -> CGFloat {
        max(0, menuBarHeight) * notchUpperRadiusRatio
    }

    /// The contour's lower corners, which are the ones the eye compares with
    /// the cut-out: the notch's own bottom corners sit under the panel, so this
    /// curve is the only place the shape is checkable against the hardware.
    static func surfaceBottomCornerRadius(menuBarHeight: CGFloat) -> CGFloat {
        max(0, menuBarHeight) * notchLowerRadiusRatio
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
        drawsCompactMarks: Bool = true,
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
                    width: fixedCompactWidth(
                        for: status,
                        matrixCount: matrixCount,
                        trailing: trailing
                    ),
                    height: compactHeight
                )
            }
            // A notched panel still wraps the cut-out, so its width is set by
            // the wings around a fixed obstacle rather than by its content.
            let width = notchedLeadingWidth(
                markCount: drawsCompactMarks ? matrixCount : 0
            )
                + centerOcclusionWidth
                + compactTrailingWingWidth(trailing: trailing)
            return CGSize(width: ceil(width), height: compactHeight)
        case .noNotch:
            return CGSize(
                width: fixedCompactWidth(
                    for: status,
                    matrixCount: matrixCount,
                    trailing: trailing
                ),
                height: compactHeight
            )
        }
    }

    /// The widest elapsed readout the slot has to hold.
    ///
    /// `00:00:00` rather than a real reading: with tabular figures every digit
    /// is the same width, so the widest form is simply the one with the most
    /// digits, and a turn crossing ten hours must not move the pill. Measured
    /// at Medium — the heaviest weight any surface draws it at — so the
    /// reservation is an upper bound however it is drawn.
    private static let timerSlotTemplate = "00:00:00"
    private static let timerSlotFont = NSFont.monospacedDigitSystemFont(
        ofSize: 13,
        weight: .medium
    )
    /// Between the status name and the right-aligned timer slot.
    ///
    /// Wider than the gap after the matrix, and not the same kind of thing: it
    /// is the distance at the moment the timer is at its longest, not a
    /// constant visual gap.
    static let compactTimerClearance: CGFloat = 32
    /// Between two product matrices, when both are drawn.
    static let compactMatrixSpacing: CGFloat = 6

    /// One width for the whole single-product working set.
    ///
    /// `Connected`, `Running`, `Input`, `Approval`, `Completed` and any elapsed
    /// reading up to `00:00:00` all render at the same width, so nothing in
    /// ordinary use moves the pill or the menu bar icons to its left. The timer
    /// is right-aligned inside its reserved slot, so a turn crossing an hour
    /// grows leftwards into space that was already empty.
    ///
    /// Two things changed here when presence arrived. The fold over
    /// `MonitorStatus.allCases` is gone: it reserved room for states the
    /// collapsed surface can no longer reach, and one of them —
    /// `Update Claude Code` — was setting the dual-product width for a state
    /// Claude Code cannot even be in (issue #29). And the fold over configured
    /// products is gone with it, because no label in the working set names a
    /// product any more; what widens the pill now is a second matrix, not a
    /// second product's vocabulary.
    ///
    /// `Disconnected` is the one state allowed to be narrower. Nothing follows
    /// it into the timer slot, so reserving one would leave a visibly empty
    /// pill beside a short word.
    ///
    /// - Parameter matrixCount: How many product matrices are drawn. Zero and
    ///   one are the same width — the grey resting mark occupies the single
    ///   slot rather than adding one.
    /// - Parameter trailing: What the trailing slot actually draws, when that
    ///   is more than an elapsed value. A subagent chip cluster sits in the
    ///   same slot and can be wider than the reservation, and a no-notch pill
    ///   is the one shape with no cut-out to hang a wing off -- what does not
    ///   fit inside its width is simply clipped. Defaults to empty, which is
    ///   every caller that is only ever going to draw a timer.
    static func fixedCompactWidth(
        for status: MonitorStatus,
        matrixCount: Int,
        trailing: CompactTrailingReading = .empty
    ) -> CGFloat {
        let extraMatrices = CGFloat(max(0, matrixCount - 1))
            * (statusMatrixSize + compactMatrixSpacing)
        guard status != .disconnected else {
            return ceil(
                compactChromeWidth
                    + compactLabelWidth(.disconnected)
                    + extraMatrices
            )
        }
        return ceil(
            compactChromeWidth
                + workingContentWidth(trailing: trailing)
                + extraMatrices
        )
    }

    /// One status name, at the weight the notch actually draws it.
    ///
    /// No product argument: nothing the collapsed surface can say names a
    /// product any more.
    static func compactLabelWidth(_ status: MonitorStatus) -> CGFloat {
        textWidth(status.compactDisplayName, font: statusLabelFont)
    }

    /// Everything in a compact panel that is not the label or the timer.
    static let compactChromeWidth: CGFloat = expandedHorizontalPadding
        + statusMatrixSize
        + expandedReadoutSpacing
        + expandedHorizontalPadding

    /// The widest the working set gets beside the chrome.
    ///
    /// Not "widest label plus a timer slot": only three of these states can be
    /// counting, and they are not the ones with the longest names. `Connected`
    /// and `Completed` are both longer words than `Approval`, and both lose to
    /// it anyway because `Approval` is the widest state that *also* reserves
    /// the timer. Adding the slot to the widest label instead of to the widest
    /// timed one over-reserves by about 13pt for a pill that sits in the menu
    /// bar.
    ///
    /// Computed rather than a stored `static let`: a lazily-initialised one runs
    /// its initialiser in a nonisolated context, and this measures text.
    static func workingContentWidth(trailing: CompactTrailingReading = .empty) -> CGFloat {
        workingStatuses
            .map { compactContentWidth($0, trailing: trailing) }
            .max() ?? 0
    }

    /// One status's own content: its label, plus the trailing slot when that
    /// state can be counting.
    static func compactContentWidth(
        _ status: MonitorStatus,
        trailing: CompactTrailingReading = .empty
    ) -> CGFloat {
        let label = compactLabelWidth(status)
        guard status.canShowElapsed else { return label }
        return label
            + compactTimerClearance
            + compactTrailingSlotWidth(trailing: trailing)
    }

    /// The trailing readout's slot: the elapsed reservation, or what is being
    /// drawn when that is wider.
    ///
    /// The reservation is what keeps the pill still while digits change, and it
    /// is an upper bound for an elapsed value alone. It is not one for the
    /// subagent chip cluster that shares the slot, and reserving room for it
    /// permanently would widen every pill for a reading almost no collapsed
    /// surface will ever show. So the slot grows to fit that reading and
    /// shrinks back when it goes -- a movement caused by something appearing,
    /// which is the one kind this surface already accepts.
    static func compactTrailingSlotWidth(trailing: CompactTrailingReading) -> CGFloat {
        let reservation = textWidth(timerSlotTemplate, font: timerSlotFont)
        guard !trailing.isEmpty else { return reservation }
        return max(reservation, compactTrailingReadingWidth(trailing))
    }

    /// What the collapsed surface can say while an agent is connected.
    static let workingStatuses = MonitorStatus.collapsedReachable
        .subtracting([.disconnected])

    static func expandedHeight(compactHeight: CGFloat) -> CGFloat {
        compactHeight + expandedContentHeight
    }

    static func sessionViewportHeight(forSessionCount sessionCount: Int) -> CGFloat {
        sessionRowHeight * CGFloat(min(max(sessionCount, 0), maximumVisibleSessionCount))
    }

    static func expandedContentHeight(
        forSessionCount sessionCount: Int,
        footerHeight: CGFloat = expandedFooterHeight
    ) -> CGFloat {
        guard sessionCount > 0 else {
            return thinExpandedBodyHeight + footerHeight
        }
        return sessionViewportHeight(forSessionCount: sessionCount) + footerHeight
    }

    /// No product argument. It used to fold over the configured products,
    /// because the widest sentence a panel could show named one of them; now
    /// that no status label names a product, every configured set folds to the
    /// same number and the widest name is `Version unsupported` for everybody.
    /// A Claude Code user's panel is ~79pt narrower for it.
    static func expandedWidth(centerOcclusionWidth: CGFloat) -> CGFloat {
        guard centerOcclusionWidth >= 1 else {
            return expandedBaselineWidth
        }

        // Only the status readout flanks the notch now — the usage readout that
        // used to claim the trailing side moved into the footer.
        let widestStatusReadout = MonitorStatus.allCases
            .map(expandedStatusReadoutWidth(status:))
            .max() ?? 0
        let requiredSideWidth = expandedHorizontalPadding
            + widestStatusReadout
            + expandedNotchClearance
        let notchSafeWidth = centerOcclusionWidth + requiredSideWidth * 2

        return ceil(max(expandedBaselineWidth, notchSafeWidth))
    }

    static func expandedStatusReadoutWidth(status: MonitorStatus) -> CGFloat {
        statusMatrixSize
            + expandedReadoutSpacing
            + textWidth(status.displayName, font: statusLabelFont)
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
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
    @Published var isExpanded = false
    /// Whether the user has asked the system to reduce motion.
    ///
    /// Seeded from the accessibility setting at construction and updated when
    /// it changes, because everything downstream -- the matrix keyframes, the
    /// searchlight sweep, the panel's spring -- reads this and nothing else.
    /// It was declared with a `false` literal and never written, which left
    /// every one of those paths dead in production while the tests that pass
    /// the flag straight into a view kept passing (figma-design §9.1, §10).
    @Published var reduceMotion: Bool
    /// How a row says which product it came from. Only drawn while both
    /// products are connected; see ``showsProductAttribution``.
    @Published var productAttribution: ProductAttributionStyle {
        didSet {
            preferences?.set(
                productAttribution.rawValue,
                forKey: Self.productAttributionDefaultsKey
            )
        }
    }
    /// Whether the footer is showing today's line alone.
    ///
    /// One state for the whole footer, not one per product: the two share a
    /// footer, and folding one product's rules while the other's stayed would
    /// be a shape nothing in §5.1 describes. Remembered across openings so a
    /// user who wants the quiet footer does not re-fold it every time, and it
    /// defaults to unfolded so the rules are what a first open shows.
    @Published var isQuotaFolded: Bool {
        didSet {
            preferences?.set(isQuotaFolded, forKey: Self.quotaFoldedDefaultsKey)
        }
    }
    /// Whether the collapsed surface gives up its wings and leaves the cut-out
    /// to speak for itself.
    ///
    /// The form is not a new one: it is exactly what a notched display already
    /// draws while nothing is connected (``drawsCompactMarks``), held for every
    /// state instead of only for that one. The cut-out is a shape the hardware
    /// puts on the screen whatever this app does, and this is the preference
    /// for people who want that shape and nothing beside it.
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
    @Published private(set) var lastIntegrationMessage: String
    @Published private(set) var hasCompletedOnboarding: Bool

    private static let productAttributionDefaultsKey = "productAttribution"
    private static let quotaFoldedDefaultsKey = "quotaFolded"
    private static let hidesCompactWingsDefaultsKey = "hidesCompactWings"
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
    private let accessibilityNotifications: NotificationCenter
    private var reduceMotionObserver: NSObjectProtocol?

    init(
        displays: [DisplayOption]? = nil,
        services: [any AgentMonitoring] = [],
        navigator: (any AgentNavigating)? = nil,
        initialSnapshot: AgentSnapshot? = nil,
        preferences: UserDefaults? = nil,
        refreshEvents: AsyncStream<Void>? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        timing: MonitorTiming = .standard,
        systemReduceMotion: @escaping @Sendable () -> Bool =
            { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
        accessibilityNotifications: NotificationCenter =
            NSWorkspace.shared.notificationCenter
    ) {
        let resolvedDisplays = displays ?? DisplayOption.currentDisplays()
        let snapshot = initialSnapshot ?? Self.previewSnapshot
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
        self.timing = timing
        self.stuckDeadlines = [:]
        self.accessibilityNotifications = accessibilityNotifications
        // Read once here for the same reason `DesktopReadingWatcher` reads the
        // front once: this is a state, not an event, and a user who already had
        // Reduce Motion on before launch never generates a change for it.
        self.reduceMotion = systemReduceMotion()
        self.preferredDisplayID = persistedDisplayID
            ?? (initialDisplayID.isEmpty ? nil : initialDisplayID)
        self.services = services
        self.navigator = navigator
        self.refreshEvents = refreshEvents
        self.latestByAgent = [snapshot.agent: snapshot]
        let merged = AgentSnapshotMerge.merge([snapshot])
        self.availability = merged.availability
        self.quota = merged.quota
        self.sessions = merged.sessions
        self.status = merged.status
        self.connectedAgents = merged.connectedAgents
        self.presenceMarks = merged.presenceMarks
        // Through the injected store, not `.standard`. These used to read
        // `.standard` directly while only the display preference was injected,
        // so a `MonitorStore` built in a test inherited whoever was running it:
        // `rowsAreAttributedForAsLongAsBothProductsAreConnected` failed on any
        // machine whose owner had chosen `Badge` in Settings, and passed on
        // every other, which is a test reporting on the developer rather than
        // on the code.
        self.productAttribution = preferences?.string(
            forKey: Self.productAttributionDefaultsKey
        ).flatMap(ProductAttributionStyle.init(rawValue:)) ?? .nameAndColour
        self.isQuotaFolded = preferences?.object(
            forKey: Self.quotaFoldedDefaultsKey
        ) as? Bool ?? false
        self.hidesCompactWings = preferences?.bool(
            forKey: Self.hidesCompactWingsDefaultsKey
        ) ?? false
        self.hasCompletedOnboarding = preferences?.bool(
            forKey: Self.onboardingDefaultsKey
        ) ?? false
        self.lastIntegrationMessage = snapshot.diagnostic ?? "Waiting for Codex data"

        // The workspace posts one notification for the whole accessibility
        // group, so the setting is re-read rather than carried in the payload.
        // Hopped to the main actor rather than trusting the delivery queue:
        // this store is main-actor state, and the publish it triggers is what
        // the panel controller and the matrix are subscribed to.
        reduceMotionObserver = accessibilityNotifications.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reduceMotion = systemReduceMotion()
            }
        }

        if !services.isEmpty {
            startMonitoring()
        }
        updateElapsedTicking()
    }

    deinit {
        if let reduceMotionObserver {
            accessibilityNotifications.removeObserver(reduceMotionObserver)
        }
        wakeTask?.cancel()
        refreshEventTask?.cancel()
        pendingHoverTask?.cancel()
        elapsedTickTask?.cancel()
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
    /// widths without measuring text once a second. The chip counts are
    /// included directly, rather than measured, for the same reason: a count
    /// changing is a width-affecting event whether or not its digit count
    /// happens to change too.
    private func publishTick(_ now: Date) {
        elapsedTick.send(now)

        let chips = compactSubagentChipCounts
        var signature = [chips.attention, chips.running, compactTimerText?.count ?? -1]
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

    var compactHeight: CGFloat {
        selectedDisplay?.menuBarHeight ?? PanelMetrics.referenceCompactHeight
    }

    var tokenRemainingPercent: Int? {
        quota.remainingPercent
    }

    /// Whether the collapsed surface draws any mark.
    ///
    /// False for a notched display resting with nothing connected, where the
    /// whole leading wing goes away and the panel is just the cut-out. This is
    /// the one place the two form factors differ in *what is visible* rather
    /// than in how it is drawn: a no-notch pill has no cut-out to hide behind,
    /// so it keeps the grey mark and holds its position in the menu bar.
    ///
    /// False for the whole of ``hidesCompactSurface`` as well, which is that
    /// same resting form asked for on purpose rather than arrived at.
    var drawsCompactMarks: Bool {
        guard !isExpanded, geometry == .notched else { return true }
        return !isRestingOnly && !hidesCompactSurface
    }

    /// Whether ``hidesCompactWings`` is something the selected display could
    /// honour -- which is what greys the switch that sets it.
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
    /// the display that could not honour it.
    var canHideCompactWings: Bool {
        guard geometry == .notched else { return false }
        return (selectedDisplay?.centerOcclusionWidth ?? 0) >= 1
    }

    /// Whether the collapsed surface is drawing nothing at all.
    ///
    /// Says nothing about hover: both readers of this are already collapsed-only
    /// (``drawsCompactMarks`` guards on it, and the compact timer is drawn only
    /// while collapsed), and scoping it here as well would make the answer
    /// change under the pointer for no drawn difference.
    var hidesCompactSurface: Bool {
        hidesCompactWings && canHideCompactWings
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

    var statusDisplayName: String {
        status.displayName
    }

    var compactStatusReadoutText: String {
        status.compactDisplayName
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
        // Nil rather than gated at the view, so the trailing wing this string
        // reserves goes away with the readout it was reserving for. Every
        // reader is the collapsed surface or its width: the header, the two
        // width compositions below, and the tick's own re-measure signature.
        guard !hidesCompactSurface else { return nil }
        return SessionElapsedFormatter.elapsed(
            since: longestRunningSessionStart,
            now: Self.readableNow(timerNow, forStart: longestRunningSessionStart)
        )
    }

    /// Subagents still in flight across every listed row, split into the
    /// figures the two chips draw (`dual-agent-design.md` §10).
    ///
    /// A total across every row, because the collapsed surface speaks for the
    /// whole list the way the summary status and the one timer already do —
    /// across both products, which both report subagent boundaries.
    var compactSubagentChipCounts: SubagentChipCounts {
        guard !hidesCompactSurface else { return .empty }
        let attention = sessions.reduce(0) { $0 + $1.subagentsAwaitingApprovalCount }
        let running = sessions.reduce(0) { $0 + $1.subagentsStillRunningCount }
        return SubagentChipCounts(attention: attention, running: running)
    }

    /// The collapsed pill's running chip colour -- rules 1–2 of
    /// `dual-agent-design.md` §10.
    ///
    /// Tinted only while the pill can honestly speak for one product: exactly
    /// one connected. Two connected, or none, and it goes neutral -- neither
    /// ink would be accurate, so neither is used.
    var compactSubagentRunningTint: SubagentChipTint {
        guard connectedAgents.count == 1, let only = connectedAgents.first else {
            return .neutral
        }
        return .product(only)
    }

    /// Every subagent still in flight across every listed row, counting both
    /// chips together. Kept for VoiceOver's total and for callers that only
    /// need to know whether the collapsed surface has anything to say here.
    var compactRunningSubagentCount: Int {
        let chips = compactSubagentChipCounts
        return chips.attention + chips.running
    }

    /// Everything the collapsed surface draws in the slot after the notch: a
    /// subagent chip cluster, the elapsed timer, or both sharing the slot.
    ///
    /// One value rather than two views, because it is one reading: the panel
    /// width is measured from it, and the elapsed half redraws itself once a
    /// second inside its own raster instead of laying out a stack every tick.
    var compactTrailingReading: CompactTrailingReading {
        CompactTrailingReading(chips: compactSubagentChipCounts, timerText: compactTimerText)
    }

    /// The spoken form of ``compactSubagentChipCounts``, since VoiceOver
    /// cannot read the white/grey split the chips draw with colour alone.
    var spokenRunningSubagentText: String? {
        let chips = compactSubagentChipCounts
        guard !chips.isEmpty else { return nil }
        var parts: [String] = []
        if chips.attention > 0 {
            parts.append(chips.attention == 1 ? "1 waiting for you" : "\(chips.attention) waiting for you")
        }
        if chips.running > 0 {
            parts.append(chips.running == 1 ? "1 subagent" : "\(chips.running) subagents")
        }
        return parts.joined(separator: ", ")
    }

    /// The instant the compact readout counts from, or nil when there is nothing
    /// to draw. The readout advances itself from ``elapsedTick``, so it needs the
    /// start rather than a string that would go stale between re-renders.
    var compactTimerStart: Date? {
        compactTimerText == nil ? nil : longestRunningSessionStart
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
    var showsProductAttribution: Bool {
        connectedAgents.count > 1 || Set(sessions.map(\.agent)).count > 1
    }

    /// Whether rows draw the leading attribution rail.
    ///
    /// The style is a preference, but the rail is only ever drawn on the same
    /// terms as every other attribution: while there are two products to tell
    /// apart. One product connected and the rows are unmarked whatever the
    /// picker says, which is why the geometry below is asked of the store
    /// rather than read off the style.
    var showsSessionRowRail: Bool {
        showsProductAttribution && productAttribution == .colourBar
    }

    /// The row block's leading and trailing margin, which the rail widens.
    ///
    /// Unmarked rows keep the `6` that puts their text on the panel's own
    /// margin; a marked row gives the rail that margin instead, so the stroke
    /// lines up with the matrix above and the quota rules below. See
    /// ``PanelMetrics/sessionRowRailGutter``.
    var sessionRowGutter: CGFloat {
        showsSessionRowRail
            ? PanelMetrics.sessionRowRailGutter
            : PanelMetrics.sessionRowGutter
    }

    /// The row's own horizontal padding, which the rail widens to clear itself.
    ///
    /// Unmarked, it is the other half of the panel's margin. Marked, it stops
    /// being a margin at all and becomes the gap between the stroke and the
    /// words — see ``PanelMetrics/sessionRowRailPadding``.
    var sessionRowPadding: CGFloat {
        showsSessionRowRail
            ? PanelMetrics.sessionRowRailPadding
            : PanelMetrics.sessionRowPadding
    }

    /// One rule block per connected product, in display order.
    ///
    /// Exactly as many rules as the notch has marks: the footer reports on the
    /// products that are there, and a product that is not connected has no rows
    /// and no quota worth drawing.
    var footerRules: [FooterRule] {
        let now = clock.now()
        return connectedAgents.compactMap { agent in
            guard let snapshot = latestByAgent[agent] else { return nil }
            let windows = snapshot.quota.windows.map { window in
                FooterWindow(
                    fill: window.remainingPercent.map { Double($0) / 100 },
                    caption: Self.caption(for: window, now: now)
                )
            }
            guard !windows.isEmpty else { return nil }
            return FooterRule(agent: agent, windows: windows)
        }
    }

    /// One window's caption: its label when it has one, then what is left and
    /// when it resets.
    private static func caption(for window: QuotaWindow, now: Date) -> String {
        let remaining = window.remainingPercent.map { "\($0)% left" } ?? "-- left"
        let reset = UsageSummaryFormatter.resetText(
            resetsAt: window.resetsAt,
            remainingPercent: window.remainingPercent,
            now: now
        )
        let body = "\(remaining) · \(reset)"
        return window.label.isEmpty ? body : "\(window.label) · \(body)"
    }

    /// The bottom line: every product's tokens for today, on one line.
    ///
    /// Nil for the single-Codex footer, which keeps today's inline form — one
    /// window leaves room in the caption, so a second line would be a line of
    /// whitespace with three words in it.
    var footerTodayText: String? {
        let rules = footerRules
        guard rules.count > 1 || (rules.first?.windows.count ?? 0) > 1 else {
            return nil
        }
        return Self.todayLine(for: rules, tokensBy: todayTokens)
    }

    /// Today's tokens as the folded footer prints them.
    ///
    /// Folded there is no rule caption left to ride, so every shape needs this
    /// line — including single-Codex, which does without one while its rule is
    /// showing because the tokens are inline in that caption.
    var foldedTodayText: String {
        Self.todayLine(for: footerRules, tokensBy: todayTokens)
    }

    /// Nothing to fold when quota is unavailable and no rule is drawn.
    var showsQuotaFoldControl: Bool { !footerRules.isEmpty }

    func toggleQuotaFold() { isQuotaFolded.toggle() }

    private func todayTokens(for agent: AgentKind) -> Int64? {
        latestByAgent[agent]?.quota.todayTokens
    }

    /// Every connected product's tokens for today, on one line.
    ///
    /// The product is named only when there are two of them. With one connected
    /// there is nothing to tell apart, so naming it is the same redundancy the
    /// rows already avoid — see ``showsProductAttribution``.
    private static func todayLine(
        for rules: [FooterRule],
        tokensBy tokens: (AgentKind) -> Int64?
    ) -> String {
        let names = rules.count > 1
        let parts = rules.compactMap { rule -> String? in
            guard let count = tokens(rule.agent) else { return nil }
            let compact = UsageSummaryFormatter.compactTokenCount(count)
            return names ? "\(rule.agent.displayName) \(compact)" : compact
        }
        guard !parts.isEmpty else { return "-- today" }
        return parts.joined(separator: " · ") + " today"
    }

    var expandedFooterHeight: CGFloat {
        PanelMetrics.footerHeight(rules: footerRules, isFolded: isQuotaFolded)
    }

    var expandedFooterText: String {
        UsageSummaryFormatter.summary(
            remainingPercent: quota.remainingPercent,
            todayTokens: quota.todayTokens,
            resetsAt: quota.resetsAt,
            now: clock.now()
        )
    }

    /// 0–1 fill for the footer meter, or nil when quota is unavailable.
    var usageMeterFill: Double? {
        quota.remainingPercent.map { Double($0) / 100 }
    }

    var emptyListMessage: String {
        availability.emptyListMessage
    }

    var expandedContentHeight: CGFloat {
        PanelMetrics.expandedContentHeight(
            forSessionCount: sessions.count,
            footerHeight: expandedFooterHeight
        )
    }

    var currentPanelSize: CGSize {
        PanelMetrics.size(
            geometry: geometry,
            isExpanded: isExpanded,
            statusReadoutText: compactStatusReadoutText,
            trailing: compactTrailingReading,
            centerOcclusionWidth: selectedDisplay?.centerOcclusionWidth ?? 0,
            compactHeight: compactHeight,
            status: status,
            // Exactly what the header draws. The resting mark counts as one,
            // because it takes the single slot rather than adding one beside it.
            matrixCount: presenceMarks.count,
            drawsCompactMarks: drawsCompactMarks,
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
        PanelMetrics.surfaceShoulderRadius(menuBarHeight: compactHeight)
    }

    /// The contour's lower corners on the selected display.
    var surfaceBottomCornerRadius: CGFloat {
        PanelMetrics.surfaceBottomCornerRadius(menuBarHeight: compactHeight)
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
        scheduleHoverAction(after: timing.hoverCollapseDelay) { store in
            store.isExpanded = false
        }
    }

    func collapse() {
        cancelPendingHoverAction()
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

    /// Takes one finished row off the list, at the user's asking.
    ///
    /// **Only a Completed row.** Every other status is a Turn that is still
    /// going — the user has not been told anything yet, and a row they dismiss
    /// by accident is one they cannot get back until the Turn ends. Dismissing
    /// a finished row throws away only the notice that it finished, which is
    /// the whole of what the row was still there to say.
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
        guard session.status == .completed else { return false }
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

    private func apply(_ snapshot: MonitorSnapshot) {
        forgetDismissalsProvenGone(in: snapshot)
        let undismissedSessions = snapshot.sessions.filter { !isDismissed($0) }
        let visibleSessions = undismissedSessions
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
    }

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
