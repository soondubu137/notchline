import AppKit
import Combine
import SwiftUI

struct NotchOverlayView: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                PanelSurface(
                    shoulderRadius: store.surfaceShoulderRadius,
                    bottomRadius: store.surfaceBottomCornerRadius,
                    drawsOutline: store.showsSurfaceOutline
                )

                VStack(spacing: 0) {
                    OverlayHeader()
                        .frame(height: store.compactHeight)

                    if store.isExpanded, !store.expandsToPillOnly {
                        ExpandedPanelContent()
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: -6)),
                                    removal: .opacity
                                )
                            )
                    }
                }
                // The window is one shoulder wider than the panel on each side,
                // because that is where `PanelContour` draws the curve back up
                // to the menu bar. Content is laid out in the body inside them,
                // so its padding is measured from the black edge and not from
                // an invisible window bound — and so is the region that answers
                // to the pointer, which leaves the shoulders passing clicks
                // through to the menu bar items they overhang.
                .frame(
                    width: max(0, proxy.size.width - store.surfaceShoulderRadius * 2),
                    height: proxy.size.height,
                    alignment: .top
                )
                .contentShape(Rectangle())
                .onHover { isInside in
                    if isInside {
                        store.pointerEnteredPanel()
                    } else {
                        store.pointerExitedPanel()
                    }
                }
                .animation(contentAnimation, value: store.isExpanded)
            }
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(panelAccessibilityLabel)
    }

    private var contentAnimation: Animation {
        PanelMotion.animation
    }

    private var panelAccessibilityLabel: String {
        // **Today's spend, not a share.** It used to end `72% usage remaining`,
        // read off `windows.first` — which is one window selected over the
        // others, on a surface where no share is drawn at all until somebody
        // opens the table (`quota-footer-v2.md` §4). Speaking one here handed a
        // screen-reader user a figure nobody else could see, and picked which
        // window it was. What the footer draws at rest is this.
        let usage = store.footerToday.spokenText.lowercased()
        // Spoken, not the "12:34" the notch draws: VoiceOver reads that as a
        // time of day. The label names it as the longest of the running turns,
        // because a bare duration beside a summary status is unattributable.
        let elapsed = store.spokenLongestElapsedText.map { ", longest running for \($0)" }
            ?? ""
        // The counts column, which draws two figures and names neither: there
        // is no product left for a collapsed numeral to belong to, so what is
        // spoken is what the numerals mean rather than whose they are.
        let counts = store.spokenCollapsedCountsText ?? "nothing running"
        // The breathing dot, which VoiceOver cannot see move. It is the one
        // thing on this surface said by motion alone, so it has to be said here
        // too -- §10's rule about colour, applied to the channel that replaced
        // the column's own breath.
        let finished = store.spokenBuriedCompletionText.map { ", \($0)" } ?? ""
        // **The status name stops being drawn and does not stop being said.**
        // Neither collapsed form has a word on it any more; this is where that
        // word went (`compact-view-v2.md` §7, §10).
        return "Notchline, \(counts), status "
            + "\(store.statusDisplayName)\(elapsed)\(finished), \(usage)"
    }
}

private struct PanelSurface: View {
    let shoulderRadius: CGFloat
    let bottomRadius: CGFloat
    /// See ``MonitorStore/drawsSurfaceOutline``. Static, and it has to stay
    /// that way: §7 of `AGENTS.md` bans anything on this surface that ticks.
    let drawsOutline: Bool

    var body: some View {
        let contour = PanelContour(
            shoulderRadius: shoulderRadius,
            bottomRadius: bottomRadius
        )

        contour
            .fill(.black)
            // Everything but the top line, which is not this panel's edge but
            // the screen's: the surface hangs from the very top of the display,
            // so a rule drawn there reads as a line across the menu bar rather
            // than as the boundary of the thing under it. The stroke therefore
            // comes off an open path, from the top-right corner round to the
            // top-left one, and ends flush with the top on both sides.
            //
            // Stroked at twice the width and clipped back to the closed shape,
            // so the line lands wholly *inside* it. A centred stroke would lose
            // its outer half along the bottom, which lies on the panel's own
            // bounds and is clipped to them — leaving that edge half the
            // thickness of the two sides.
            .overlay {
                if drawsOutline {
                    PanelContour(
                        shoulderRadius: shoulderRadius,
                        bottomRadius: bottomRadius,
                        spansTopEdge: false
                    )
                    .stroke(
                        NotchPalette.surfaceEdge,
                        lineWidth: PanelMetrics.surfaceOutlineWidth * 2
                    )
                    .clipShape(contour)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The cut-out's outline, stretched to whatever rect the panel occupies.
///
/// Two radii, not one, because the notch has two: a small concave fillet where
/// its sides meet the top of the display, and lower corners twice as round.
///
/// The upper fillets are true circular arcs — a quarter circle each, hence the
/// `0.5523` handle — which is what the hardware edge is up there and what makes
/// the panel read as the same object as the cut-out it grows out of rather than
/// as a rounded rectangle pinned beneath it.
///
/// **The lower corners are not.** They are continuous corners: the curve begins
/// ``PanelMetrics/smoothCornerReach(radius:)`` back along each straight edge
/// and eases curvature up from zero before it reaches the arc, so the vertical
/// side does not stop being straight at a findable point. That constant carries
/// the reasoning; the shape of it is three segments per corner — ease in,
/// circular arc, ease out — and at a smoothing of `0` it collapses back into
/// the single quarter-circle cubic that used to be written here.
struct PanelContour: Shape {
    let shoulderRadius: CGFloat
    let bottomRadius: CGFloat
    /// Whether the path spans the top of its rect, which is the one edge the
    /// panel does not own.
    ///
    /// `true` for the black body and for anything clipping to it — the shape
    /// has to be closed to be filled. `false` produces the same outline as an
    /// open path running from the top-right corner round to the top-left one,
    /// which is what the optional edge is stroked from: that top line lies on
    /// the screen's own edge, and a line drawn along it is not this panel's
    /// boundary but a rule across the top of the display.
    var spansTopEdge = true
    /// Exposed so the reduction to a circular corner can be asserted rather
    /// than argued; nothing in the product passes anything but the default.
    var bottomSmoothing = PanelMetrics.notchLowerCornerSmoothing

    func path(in rect: CGRect) -> Path {
        // Each side of the shape spends one shoulder plus one lower corner, so
        // that sum is what has to fit — down the side, and twice across the
        // width. It is the corner's *reach* that is spent, not its radius: a
        // smoothed corner starts further back along both edges than a circular
        // one of the same radius. Clamping the pair together keeps their
        // ratio, which is the part of the shape that carries the resemblance.
        let smoothing = min(max(0, bottomSmoothing), 1)
        let requestedShoulder = max(0, shoulderRadius)
        let requestedBottom = max(0, bottomRadius)
        let requested = requestedShoulder
            + requestedBottom * (1 + smoothing)
        let available = min(rect.height, rect.width / 2)
        let fit = requested > available && requested > 0
            ? available / requested
            : 1
        let shoulder = requestedShoulder * fit
        let bottom = requestedBottom * fit
        let shoulderControl = shoulder * 0.552_284_749_8

        var path = Path()
        if spansTopEdge {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.addCurve(
            to: CGPoint(x: rect.maxX - shoulder, y: rect.minY + shoulder),
            control1: CGPoint(x: rect.maxX - shoulderControl, y: rect.minY),
            control2: CGPoint(
                x: rect.maxX - shoulder,
                y: rect.minY + shoulder - shoulderControl
            )
        )
        // Down the trailing side and round the bottom-right corner, then
        // along the bottom and round the bottom-left one. Each call draws its
        // own straight run in, so the corner decides where the straight edge
        // ends rather than the two having to agree separately.
        path.addSmoothCorner(
            vertex: CGPoint(x: rect.maxX - shoulder, y: rect.maxY),
            entering: CGVector(dx: 0, dy: 1),
            leaving: CGVector(dx: -1, dy: 0),
            radius: bottom,
            smoothing: smoothing
        )
        path.addSmoothCorner(
            vertex: CGPoint(x: rect.minX + shoulder, y: rect.maxY),
            entering: CGVector(dx: -1, dy: 0),
            leaving: CGVector(dx: 0, dy: -1),
            radius: bottom,
            smoothing: smoothing
        )
        path.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.minY + shoulder))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(
                x: rect.minX + shoulder,
                y: rect.minY + shoulder - shoulderControl
            ),
            control2: CGPoint(x: rect.minX + shoulderControl, y: rect.minY)
        )
        if spansTopEdge {
            path.closeSubpath()
        }
        return path
    }
}

private extension Path {
    /// Runs the straight edge into `vertex` and turns the corner there with a
    /// continuous curve, leaving the current point on the outgoing edge.
    ///
    /// `entering` and `leaving` are unit vectors: the direction the path is
    /// already travelling, and the direction it travels after the turn. They
    /// are perpendicular here — every corner this shape has is a right angle —
    /// and the whole corner is written in the frame they make, which is what
    /// lets one construction serve corners facing four different ways.
    ///
    /// Three segments, in the order they are drawn:
    ///
    /// 1. **Ease in.** A cubic whose two control points both lie *on* the
    ///    incoming edge. Collinear control points mean zero curvature at the
    ///    start, so the curve leaves the straight run the way the straight run
    ///    arrives — no step, and nothing for the eye to find.
    /// 2. **The arc.** A true circular arc of `radius`, but spanning only
    ///    `90° × (1 - smoothing)` instead of the whole quarter turn, drawn as
    ///    the single cubic that fits an arc of that angle (`4/3 · tan(θ/4)`).
    /// 3. **Ease out.** The mirror of the first, landing on the outgoing edge
    ///    with its curvature back at zero.
    ///
    /// The three together consume exactly `(1 + smoothing) · radius` along each
    /// edge, which is why the caller sizes the straight runs from
    /// ``PanelMetrics/smoothCornerReach(radius:)`` and not from the radius.
    /// At `smoothing == 0` the first and third segments have zero length and
    /// the second is the plain quarter-circle cubic.
    mutating func addSmoothCorner(
        vertex: CGPoint,
        entering: CGVector,
        leaving: CGVector,
        radius: CGFloat,
        smoothing: CGFloat
    ) {
        // Everything below is written as a step of `along` (the incoming
        // direction) and a step of `across` (the outgoing one) from a point,
        // so the arithmetic reads the same whichever way the corner faces.
        func step(
            from origin: CGPoint,
            along: CGFloat,
            across: CGFloat
        ) -> CGPoint {
            CGPoint(
                x: origin.x + entering.dx * along + leaving.dx * across,
                y: origin.y + entering.dy * along + leaving.dy * across
            )
        }

        let r = max(0, radius)
        let s = min(max(0, smoothing), 1)
        guard r > 0 else {
            addLine(to: vertex)
            return
        }

        let reach = r * (1 + s)
        // The circular arc keeps only what smoothing has not taken from it,
        // and the easing segments turn the rest: `psi` each, so the three
        // sweeps still add up to the right angle.
        let arc = (.pi / 2) * (1 - s)
        let psi = (.pi / 4) * s
        // The arc's endpoints, as a step along and a step across from where it
        // starts: it is a chord at 45° to both edges, so the two are equal.
        let chord = sin(arc / 2) * r * (2 as CGFloat).squareRoot()
        // Where the easing segment hands over to the arc, measured from the
        // point it started at on the straight edge.
        let approach = r * tan(psi / 2) * cos(psi)
        let drop = approach * tan(psi)
        // What is left of the reach after the arc and the handover, spread
        // over the easing segment's two control points. `2:1` is the ratio
        // that keeps the segment's own curvature rising evenly.
        let spread = (reach - chord - approach - drop) / 3
        let lead = 2 * spread
        // A cubic fits an arc of `theta` with handles of `4/3 · tan(theta/4)`
        // radii; at a right angle that is the familiar `0.5523`.
        let handle = (4.0 / 3.0) * tan(arc / 4) * r

        let start = step(from: vertex, along: -reach, across: 0)
        let arcStart = step(
            from: start,
            along: lead + spread + approach,
            across: drop
        )
        let arcEnd = step(from: arcStart, along: chord, across: chord)

        addLine(to: start)
        addCurve(
            to: arcStart,
            control1: step(from: start, along: lead, across: 0),
            control2: step(from: start, along: lead + spread, across: 0)
        )
        // The arc's tangents run at `psi` to each edge — the angle the easing
        // segments turned through — so its handles are laid on those, not on
        // the edges themselves.
        addCurve(
            to: arcEnd,
            control1: step(
                from: arcStart,
                along: handle * cos(psi),
                across: handle * sin(psi)
            ),
            control2: step(
                from: arcEnd,
                along: -handle * sin(psi),
                across: -handle * cos(psi)
            )
        )
        addCurve(
            to: step(from: arcEnd, along: drop, across: lead + spread + approach),
            control1: step(from: arcEnd, along: drop, across: approach),
            control2: step(from: arcEnd, along: drop, across: spread + approach)
        )
    }
}

private struct OverlayHeader: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        HStack(spacing: 0) {
            // **One leading group, and it is the whole of the band's leading
            // side.** The mark stands at `12` and the totals at `32.6` whether
            // the panel is open or shut, so expanding neither replaces nor adds
            // anything here: the figure the eye was on when it hovered does not
            // move, change colour or go away. The columns that used to fade in
            // beside it — one per working agent, in that agent's own inks —
            // went with the product hues that were the only thing on them
            // saying whose a number was (`colour-v2.md` §3).
            CompactLeadingGroup()

            // **The pill's middle, and only the pill's.** The notched bar has
            // no middle to give: the cut-out is where one would stand, and the
            // only way to give it one is a wing — `102` pt of black beside the
            // hardware for the whole of every turn, which is the reservation
            // both wings spent V1 and V2 getting rid of. That is permanent
            // rather than deferred (`compact-view-v2.md` §5.2).
            if store.drawsCompactMiddle {
                RotatingProjectName(
                    names: store.compactProjectNames,
                    width: PanelMetrics.pillMiddleWidth(
                        trailing: store.compactTrailingReading
                    )
                )
                .padding(.horizontal, PanelMetrics.expandedNotchClearance)
            }

            Spacer(minLength: 0)

            if !store.isExpanded {
                CompactTrailingSlot()
            }

            // The gear lives up here now rather than in the footer, for one and
            // two products alike. The footer became three quota rules and had no
            // room left; the top bar's trailing side is empty whenever the panel
            // is open, because the compact timer only draws while collapsed.
            if store.isExpanded {
                SettingsButton()
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .animation(headerAnimation, value: store.isExpanded)
    }

    private var horizontalPadding: CGFloat {
        PanelMetrics.expandedHorizontalPadding
    }

    private var headerAnimation: Animation {
        // The same curve the window resizes on and the same one the status
        // label hands its reading over on: the three are one movement.
        PanelMotion.animation
    }
}

/// The collapsed surface's leading wing: one aggregate mark, and the counts.
///
/// **Nothing here is per product.** The mark draws the most urgent status any
/// product is holding, in the ink the user has chosen rather than in one that
/// says whose it is; the numerals count every row and every subagent on the
/// list. So the wing moves when the *work* changes and never because something
/// was installed — which is the whole of `compact-view-v2.md` §1, and worth
/// `167` pt at five products against V1's per-product bar.
private struct CompactLeadingGroup: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        // Absent rather than empty on a notched bar with nothing to say: the
        // cut-out is already a shape on the screen, and a grey mark beside it
        // carries no information. Both other forms keep the mark, because a
        // control that vanishes from the menu bar takes its position with it.
        if store.drawsCompactMarks {
            HStack(spacing: 0) {
                NotchStatusMatrix(
                    state: NotchMatrixState(store.status),
                    size: PanelMetrics.statusMatrixSize,
                    ink: store.aggregateMatrixInk
                )
                CountsColumn(
                    sessionCount: store.aggregateSessionCount,
                    subagentCount: store.aggregateSubagentCount > 0
                        ? store.aggregateSubagentCount
                        : nil,
                    matrixSize: PanelMetrics.statusMatrixSize,
                    // The pill is centred and fixed in width and the band is
                    // sized from a baseline, so both hold the room open; the
                    // notched bar is pinned to the cut-out and hugs what it
                    // draws, because its leading edge is free to travel.
                    reservesTwoDigits: store.geometry == .noNotch || store.isExpanded
                )
            }
            .transition(Self.wingFade)
        }
    }

    /// The mark arriving into a wing that opened for it, or leaving before it
    /// shuts — the same fade, and the same reasoning, as everything else that
    /// stands in a slot on this surface.
    ///
    /// It earns its keep with `Hide the wings` on, where the whole group comes
    /// out from behind the cut-out on its own account: at full ink from the
    /// first frame it would be drawn *over* the cut-out for as long as the
    /// panel's edge took to clear it.
    private static let wingFade = AnyTransition.asymmetric(
        insertion: .opacity.animation(PanelMotion.fade(isArriving: true)),
        removal: .opacity.animation(PanelMotion.fade(isArriving: false))
    )
}

/// The collapsed surface's trailing wing: the elapsed reading.
///
/// Present while a turn is timed, absent otherwise so a notched display shows
/// no empty second cut-out. The expanded view times each row individually
/// instead.
///
/// **The subagent badges have left it.** They were one tinted tile per product
/// saying how many were in flight, and that count is now the leading wing's
/// second numeral — aggregate, untinted, and inside the room the mark already
/// had (`compact-view-v2.md` §3).
private struct CompactTrailingSlot: View {
    @EnvironmentObject private var store: MonitorStore

    /// The box the panel edge opens, held rather than computed so the write
    /// that changes it can say which way the wing is going.
    ///
    /// **It is the panel's own trailing slot, drawn.** Every collapsed width is
    /// composed from exactly this number
    /// (`PanelMetrics.drawnTrailingReadingWidth`), so framing the reading to it
    /// and drawing the glyphs from its leading edge makes the box and the
    /// panel's edge two halves of one movement: both travel on the same curve,
    /// and their difference — which is everything ahead of the reading — does
    /// not change while they do. A digit therefore arrives at the far end with
    /// the edge opening ahead of it, rather than the whole figure sliding
    /// sideways to stay flush with an edge that moved first. On the notched bar
    /// that leaves the reading standing ``PanelMetrics/expandedNotchClearance``
    /// past the cut-out at every length it can draw; on the pill, which is
    /// centred, the panel takes half the width on each edge and the reading
    /// rides with it.
    ///
    /// Optional only until the first application, which places the box rather
    /// than animating to it.
    @State private var boxWidth: CGFloat?

    var body: some View {
        HStack(spacing: 0) {
            if store.buriesAFinishedTurn {
                BuriedFinishDot()
                    .padding(
                        .trailing,
                        store.compactTimerText == nil
                            ? 0
                            : PanelMetrics.buriedFinishDotSpacing
                    )
                    .transition(Self.markFade)
            }
            // The reading is drawn the one way, whatever the aggregate is:
            // running's bare figure, neutral rather than tinted — it is the
            // longest unfinished turn anywhere and belongs to no one product,
            // so a hue would claim an owner it has not got. The waiting flip
            // that used to put it on white lived here alone; the expanded rows
            // keep their own three silhouettes (``ReadingGround``), where a
            // row's ground is read against the rows beside it and says which of
            // them wants the person. Up here there is nothing to read it
            // against — one reading for every turn at once — and the white slab
            // was the brightest thing on the bar for a state the matrix beside
            // it already announces.
            //
            // The ground stays a `.clear` ``ReadingGround`` rather than no
            // ground at all: it carries the padding both trailing widths bill
            // for, so the composed bar width is unchanged.
            //
            // **Except when it has stopped**, which is the one thing the digits
            // cannot say alone: the turn ends, the figure freezes at the length
            // it reached, and the ground it was already standing on fills. That
            // is a property of the figure rather than a comparison with a
            // neighbour, which is why a ground is allowed here where the white
            // flip is not (`compact-view-v2.md` §4.2).
            if let span = store.compactReadingSpan {
                ReadingGround(fill: span.end == nil ? .clear : Self.stoppedGround) {
                    ElapsedReadout(
                        startedAt: span.start,
                        stoppedAt: span.end,
                        tick: store.elapsedTick.eraseToAnyPublisher(),
                        tint: NotchPalette.labelDrawingColor,
                        weight: .light
                    )
                }
                .transition(Self.markFade)
            }
        }
        .frame(width: boxWidth, alignment: .leading)
        // The transaction the two transitions above run in. They each carry
        // their own curve, so what this supplies is only the fact that the
        // change is animated at all -- and it is keyed on *what is present*
        // rather than on the width, because a reading merely gaining a digit
        // inserts and removes nothing and must not be faded.
        .animation(PanelMotion.animation, value: presence)
        .onChange(of: targetWidth, initial: true) { previous, width in
            // The first application is the slot being built rather than a
            // reading arriving: take the width rather than animating to it.
            guard boxWidth != nil, previous != width else {
                boxWidth = width
                return
            }
            withAnimation(PanelMotion.slot(isOpening: width > previous)) {
                boxWidth = width
            }
        }
    }

    /// The width this slot has to be, on either form: exactly its contents,
    /// zero when it has none.
    private var targetWidth: CGFloat {
        store.compactDrawnTrailingReadingWidth
    }

    /// What the slot is currently drawing, as against how wide it is.
    private var presence: [Bool] {
        [store.compactReadingSpan == nil, store.buriesAFinishedTurn]
    }

    /// The ground a stopped reading fills with: the dim end of the row's own
    /// pair, unchanged, so a frozen figure up here and a finished row below it
    /// are the same mark.
    private static let stoppedGround = NotchPalette.restingInk.chipFill

    /// Fading rather than appearing, because the wing they stand in is a width
    /// that opens for them: a reading arriving at full ink would be drawn over
    /// the cut-out for as long as the panel edge took to clear it.
    private static let markFade = AnyTransition.asymmetric(
        insertion: .opacity.animation(PanelMotion.fade(isArriving: true)),
        removal: .opacity.animation(PanelMotion.fade(isArriving: false))
    )
}

/// The gear, shared by the expanded top bar and the resting pill.
private struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var store: MonitorStore

    @State private var isHovered = false

    private var size: CGFloat {
        PanelMetrics.settingsButtonSize(compactHeight: store.compactHeight)
    }

    var body: some View {
        Button {
            // Not `openSettings()` on its own: the click arrives while another
            // app is active, so the window it orders comes up behind that app,
            // and on the display it was last closed on rather than on the one
            // this gear is drawn on. See ``SettingsWindowPresenter``.
            SettingsWindowPresenter.present { openSettings() }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .regular))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.12 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? NotchPalette.sessionTitle : NotchPalette.label)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel("Open Settings")
        .help("Open Settings")
    }
}

private struct ExpandedPanelContent: View {
    var body: some View {
        VStack(spacing: 0) {
            ActiveSessionList()
            RecentSessionSection()
            ExpandedPanelFooter()
        }
        .foregroundStyle(.white)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal, PanelMetrics.expandedHorizontalPadding)
        }
    }
}

/// How much width to hand a scrolling list's `ScrollView` beyond the row
/// block's own, so its content still lands on the panel's margin once
/// `ScrollView` reserves room for a scroller.
///
/// **`ScrollView` shrinks the width it hands its content the instant that
/// content is actually taller than the viewport**, to leave room for a
/// scroller — matching System Settings' "Show scroll bars" set to `Always` —
/// even though `.scrollIndicators(.hidden)` means nothing is ever drawn into
/// that room. A list that fits needs no scroller and is handed the full width
/// already; one that scrolls is not, which is why the row block's right edge
/// sits on the panel's own margin collapsed and steps in the moment the list
/// crosses its own cap.
///
/// Gated on `isScrolling` because the reservation itself is: adding it
/// unconditionally would hand a list that already fits more width than the
/// panel's margin allows, pushing its own trailing content past the crop
/// below and cutting it off instead of leaving it be.
private func legacyScrollerGutter(isScrolling: Bool) -> CGFloat {
    guard isScrolling, NSScroller.preferredScrollerStyle == .legacy else {
        return 0
    }
    return NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
}

/// The live session list: at least one row's worth of viewport — the apology
/// when nothing is running — at most three, and its own scroller past that.
///
/// **No longer shares a viewport, a cap or a scroller with the Recent
/// queue** — each folds and scrolls entirely on its own now
/// (``RecentSessionSection``).
private struct ActiveSessionList: View {
    @EnvironmentObject private var store: MonitorStore

    @State private var scrollOffset: CGFloat = 0

    private var viewportWidth: CGFloat {
        PanelMetrics.sessionViewportWidth(panelWidth: store.currentPanelSize.width)
    }

    private var contentHeight: CGFloat {
        PanelMetrics.sessionListContentHeight(
            liveRowCount: store.sessions.count,
            openRowHeight: store.openRowHeight
        )
    }

    private var viewportHeight: CGFloat {
        min(contentHeight, PanelMetrics.sessionViewportCap)
    }

    private var isScrolling: Bool { contentHeight > PanelMetrics.sessionViewportCap }

    var body: some View {
        ScrollViewReader { list in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    // The apology is one of the list's own lines, so it
                    // scrolls with what is under it rather than pinning a
                    // sentence over rows somebody is reading.
                    if store.sessions.isEmpty {
                        emptyListLabel
                    }

                    ForEach(store.sessions) { session in
                        if store.openRowID == session.id {
                            // **No `.id()` on either branch.** `ForEach`
                            // already gives each row the identity `scrollTo`
                            // needs, and tagging both branches with the same
                            // one made SwiftUI treat the closed row and the
                            // open row as the same view: the panel resized
                            // for a row that went on drawing itself shut.
                            OpenRow(session: session)
                        } else {
                            // **One row is open at a time, and it is the
                            // subject** (§8.2): everything else on the list
                            // drops to `45%` for as long as it is, which is
                            // the same value an answer in flight takes and
                            // the same statement — this is not the thing you
                            // are looking at.
                            SessionRow(session: session)
                                .opacity(store.openRowID == nil ? 1 : 0.45)
                        }
                    }
                }
            }
            .frame(
                width: viewportWidth + legacyScrollerGutter(isScrolling: isScrolling),
                height: viewportHeight
            )
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offset in
                scrollOffset = offset
            }
            .onChange(of: store.openRowID) { _, opened in
                guard let opened else { return }
                withAnimation(PanelMotion.slot(isOpening: true)) {
                    list.scrollTo(opened, anchor: .top)
                }
            }
            .onChange(of: store.sessions.map(\.id)) { _, _ in
                guard let opened = store.openRowID else { return }
                list.scrollTo(opened, anchor: .top)
            }
        }
        // The extra width above is `ScrollView`'s own, not the row block's —
        // see ``legacyScrollerGutter``. It never belongs on screen, which is
        // what pins the visible region back to the panel's own margin
        // regardless of whether this pass actually needed the room.
        .frame(width: viewportWidth, alignment: .leading)
        .clipped()
        .overlay(alignment: .trailing) {
            ScrollRail(
                visibleHeight: viewportHeight,
                contentHeight: contentHeight,
                offset: scrollOffset
            )
        }
    }

    /// The one line an empty live list draws, at the height it has always
    /// been drawn at — `48`.
    private var emptyListLabel: some View {
        Text(store.emptyListMessage)
            .font(.system(size: 13, weight: .light))
            .foregroundStyle(NotchPalette.label)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: PanelMetrics.thinExpandedBodyHeight)
    }
}

/// The Recent queue: nothing while it is empty, its seam alone while folded,
/// and its own five-row viewport — scrolling on its own past that — while
/// open.
private struct RecentSessionSection: View {
    @EnvironmentObject private var store: MonitorStore

    @State private var scrollOffset: CGFloat = 0

    private var viewportWidth: CGFloat {
        PanelMetrics.sessionViewportWidth(panelWidth: store.currentPanelSize.width)
    }

    private var contentHeight: CGFloat {
        PanelMetrics.recentContentHeight(retiredRowCount: store.recentDepartures.count)
    }

    private var viewportHeight: CGFloat {
        PanelMetrics.recentViewportHeight(retiredRowCount: store.recentDepartures.count)
    }

    private var isScrolling: Bool { contentHeight > PanelMetrics.recentViewportCap }

    var body: some View {
        if !store.recentDepartures.isEmpty {
            VStack(spacing: 0) {
                RecentSeam(count: store.recentDepartures.count)

                if store.isRecentExpanded {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(store.recentDepartures) { departure in
                                RetiredRow(departure: departure)
                            }
                        }
                    }
                    .frame(
                        width: viewportWidth + legacyScrollerGutter(isScrolling: isScrolling),
                        height: viewportHeight
                    )
                    .scrollIndicators(.hidden)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y
                    } action: { _, offset in
                        scrollOffset = offset
                    }
                    .frame(width: viewportWidth, alignment: .leading)
                    .clipped()
                    .overlay(alignment: .trailing) {
                        ScrollRail(
                            visibleHeight: viewportHeight,
                            contentHeight: contentHeight,
                            offset: scrollOffset
                        )
                    }
                }
            }
        }
    }
}

/// The quota footer: one number, a control, and the table behind it.
///
/// **At rest it is `22`, and that is the only closed height it has**
/// (`quota-footer-v2.md` §2). It used to be a `496 × 3` rule per quota window
/// with a caption under each — four numbers drawn every time the panel opened,
/// on nearly all of which not one of them needed anything, spending between a
/// fifth and a third of the panel's height saying so. The rule went first: it
/// drew as a length exactly what its own caption printed as a figure two points
/// to its right (§1.1). What is left is today's spend and the disclosure.
///
/// **Nothing here is drawn differently for being low.** There is no threshold,
/// no window speaks, and no share reaches this line at any value (§4). The one
/// thing that can change the footer's height is somebody opening the table.
private struct ExpandedPanelFooter: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.footerRuleSpacing) {
            if store.showsQuotaFoldControl {
                spendLine

                if store.isQuotaExpanded {
                    table
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: store.expandedFooterHeight, alignment: .top)
        .padding(.horizontal, PanelMetrics.expandedHorizontalPadding)
    }

    /// The footer's first line, always drawn, carrying the control.
    private var spendLine: some View {
        HStack(spacing: 0) {
            FooterSpend(store.footerToday)

            Spacer(minLength: 0)

            QuotaFoldChevron(isExpanded: store.isQuotaExpanded)
        }
        // The control is a point taller than the caption it rides. The footer's
        // own height does not move: the trailing `Spacer` absorbs it.
        .frame(height: PanelMetrics.quotaFoldControlSize)
    }

    /// Two levels, because the windows belong to products.
    ///
    /// Outside, the product and its own spend today. Inside, each of its
    /// windows on a line. **Indentation and the leader carry the level between
    /// them** — no box, rule or divider is drawn (§5).
    private var table: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.footerCaptionHeight) {
            ForEach(store.footerRules) { rule in
                FooterProductGroup(rule: rule)
            }
        }
    }
}

/// One product's group: its badge and spend, then a line per window.
private struct FooterProductGroup: View {
    let rule: FooterRule

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.footerCaptionSpacing) {
            outerRow

            // By position, not by content. Nothing on this table sorts, so a
            // window's index *is* its identity: two windows a product happened
            // to publish with the same label, share and timer would collide
            // under any identity derived from what they say.
            ForEach(rule.windows.indices, id: \.self) { index in
                FooterWindowRow(window: rule.windows[index])
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The product, a faint leader, and what it has spent today.
    ///
    /// **The leader is what makes the spend attributable without colour.** On
    /// the collapsed line those parts had to be coloured numerals; here each
    /// one sits beside its product's own name, joined to it by `1` pt of white
    /// at `10%` — one step below the white-at-`15%` the panel's structural
    /// hairlines use, because it is joining two things rather than dividing
    /// anything. It is drawn on outer rows only, so **having a leader is itself
    /// part of what says which level a line is on**.
    private var outerRow: some View {
        HStack(spacing: PanelMetrics.footerLeaderClearance) {
            ProductBadge(name: rule.agent.displayName)

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)
                .accessibilityHidden(true)

            FooterSpend(rule.today)
        }
        .frame(height: PanelMetrics.productBadgeHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rule.agent.displayName), \(rule.today.spokenText)")
    }
}

/// One window's line: the label, the share, and the countdown.
///
/// Three columns and one trailing edge shared with the outer row above: the
/// window at `24` — one step in from the panel's own `12` — the share
/// right-aligned at `300`, and the timer right-aligned at `508`, which is where
/// the product's spend is right-aligned too.
///
/// **Every one of them is `#7C7C80`, whatever the share.** Brightness on this
/// footer separates the table's three levels and separates nothing by value
/// (§5).
private struct FooterWindowRow: View {
    let window: FooterWindow

    var body: some View {
        HStack(spacing: 0) {
            // The label at `24` and the share ending at `300`, which is one
            // box: what is between them is whitespace either way, and giving
            // it a boundary of its own would be a column nothing is in.
            HStack(spacing: 0) {
                FooterCaption(window.label)
                Spacer(minLength: 0)
                FooterCaption(window.share)
            }
            .frame(
                width: PanelMetrics.footerShareTrailingEdge
                    - PanelMetrics.footerWindowIndent
            )

            // The timer, right-aligned on the footer's own trailing edge,
            // which is where the spend above it is right-aligned too.
            Spacer(minLength: 0)
            FooterCaption(window.timer)
        }
        .padding(.leading, PanelMetrics.footerWindowIndent)
        .frame(height: PanelMetrics.footerCaptionHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLine)
    }

    /// What the line says out loud, with the absolute reset the column trades
    /// away for a duration (§7).
    private var spokenLine: String {
        let head = window.label.isEmpty ? "" : "\(window.label), "
        return "\(head)\(window.share), \(window.spokenTimer)"
    }
}

/// The disclosure that opens the quota table.
///
/// One glyph, turned 180° between the two states rather than swapped for a
/// second drawing. It points down while the table is shut because the panel
/// hangs from the notch and can only grow downward — the chevron points the way
/// the panel will move, which is also the "show more" every list uses.
///
/// The chevron is the whole hit target. The rest of the line is a reading —
/// today's tokens — and a number that resizes the panel when clicked is a trap
/// for anyone reaching in to select or simply read it; the affordance and the
/// target are the same `16pt` square instead. Being the only hit target, it
/// carries the gear's whole hover treatment — the wash behind it and the
/// brighter glyph — so the square it answers to is visible before the click,
/// not guessed at.
private struct QuotaFoldChevron: View {
    @EnvironmentObject private var store: MonitorStore

    @State private var isHovered = false

    let isExpanded: Bool

    var body: some View {
        Button {
            store.toggleQuotaTable()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isHovered ? NotchPalette.sessionTitle : NotchPalette.label)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .frame(
                    width: PanelMetrics.quotaFoldControlSize,
                    height: PanelMetrics.quotaFoldControlSize
                )
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.12 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isExpanded)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(isExpanded ? "Hide limits" : "Show limits")
    }
}

/// The footer's 11pt caption, which every line down here uses.
///
/// It hugs its text rather than filling: this footer is a table, and every
/// column's edge is placed by the line that holds it.
private struct FooterCaption: View {
    let text: String
    let ink: Color

    init(_ text: String, ink: Color = NotchPalette.label) {
        self.text = text
        self.ink = ink
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .light))
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
    }
}

/// A day's spend, in the two brightnesses it is drawn in.
///
/// The figure in `#C7C7CC` and `today` in `#7C7C80` — one reading, with the
/// part that is a number set apart from the part that is a unit. It is the same
/// on the resting line and on a product's outer row, because they are the same
/// reading at two scopes.
private struct FooterSpend: View {
    let reading: SpendReading

    init(_ reading: SpendReading) { self.reading = reading }

    var body: some View {
        Text(runs)
            .font(.system(size: 11, weight: .light))
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(reading.spokenText)
    }

    /// One string, two runs — rather than two `Text`s side by side, so the
    /// figure and its unit are still typeset as one line.
    private var runs: AttributedString {
        var figure = AttributedString(reading.figure)
        figure.foregroundColor = NotchPalette.reading
        var unit = AttributedString(" " + reading.unit)
        unit.foregroundColor = NotchPalette.label
        return figure + unit
    }
}

private struct SessionRow: View {
    @EnvironmentObject private var store: MonitorStore
    let session: MonitoredSession

    @State private var isHovered = false

    var body: some View {
        Button {
            store.open(session)
        } label: {
            SessionRowContent(
                session: session,
                isHovered: isHovered
            )
        }
        .buttonStyle(SessionRowButtonStyle())
        .frame(maxWidth: .infinity)
        .frame(height: PanelMetrics.sessionRowHeight)
        // Every row, and it used to be finished ones only -- see
        // ``MonitorStore/dismiss(_:)`` for what that cost. The catcher claims
        // nothing but a secondary press, so the primary click's behaviour is
        // identical either way.
        .overlay {
            SecondaryClickCatcher { store.dismiss(session) }
        }
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityText)
        // A secondary click is not something a keyboard or VoiceOver can
        // produce, so the same intent is offered as an action rather than left
        // reachable only by mouse.
        .accessibilityActions {
            Button("Remove this row") { store.dismiss(session) }
        }
    }

    private var accessibilityText: String {
        let preview = session.preview.map { ", current content: \($0)" } ?? ""
        // Spoken form, not the drawn "12:34" — VoiceOver reads that as a clock
        // time. The row draws the elapsed value, so the label must carry it too.
        let elapsed = store.spokenElapsedText(for: session).map { ", running for \($0)" }
            ?? ""
        // The drawn form is one bare badge in the slot the timer had, with a
        // ground that flips rather than a second figure; spoken, it has to say
        // what it counts and, when the ground has flipped, that it is waiting.
        let subagents = session.spokenSubagentSummary.map { ", \($0)" } ?? ""
        // A finished row draws how long its turn took, and a ground cannot be
        // heard any more than a flip can. Said as a length rather than as a
        // reading, and in the past tense, because that is what it is.
        let took = store.spokenFinishedElapsedText(for: session)
            .map { ", took \($0)" } ?? ""
        // Brightness cannot be read out on its own, so a blocked subagent
        // still needs a word even while the row is timed and its own mark is
        // the bright clock rather than a badge -- a running row draws its
        // timer bright and would otherwise say nothing about why.
        let blocked = session.status.keepsTiming && session.subagentsAwaitingApproval
            ? ", a subagent is waiting for approval"
            : ""
        return "\(session.projectName), \(session.title), "
            + "\(session.status.displayName)\(elapsed)\(took)\(subagents)\(blocked)\(preview)"
    }
}

/// A row whose request is open, read rather than answered.
///
/// **The reading form** (`answer-in-notch.md` §11), which is what ships before a
/// product offers a way in. The head does not move: the caption and the title
/// are where they were on the closed row, so opening grows the row downward and
/// nothing the eye was already on shifts. Where the mark was, the quota block's
/// own chevron stands — pointing up, because the thing it folds is open.
///
/// **No white ground is drawn anywhere on it.** The affirmative ground is the
/// return key made visible, and drawing it where there is nothing for a return
/// key to do is a promise made quietly — which is why a greyed-out `Approve` is
/// worse than none at all (§11 rule 03). One control stands where three will,
/// and it is the click that has always worked, moved to a place a reader
/// arrives at *after* reading.
private struct OpenRow: View {
    @EnvironmentObject private var store: MonitorStore
    let session: MonitoredSession

    @State private var isHovered = false

    var body: some View {
        ZStack {
            // Permanently at the hover weight, never at rest -- an open row
            // reads as a live session's own row would the instant the
            // pointer arrived, because it is always the one thing on this
            // surface being looked at. (Adjacent, not done here: this is a
            // committed, sunken state rather than a transient one under the
            // pointer, and the pressed pair -- see ``NotchPalette/RowEmphasis``
            // -- would say that more precisely than reusing hover's.)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            NotchPalette.themeInk.on.opacity(
                                NotchPalette.RowEmphasis.hoverBorderOpacity
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: NotchPalette.themeInk.on.opacity(
                        NotchPalette.RowEmphasis.hoverGlowOpacity
                    ),
                    radius: NotchPalette.RowEmphasis.hoverGlowRadius
                )

            VStack(alignment: .leading, spacing: PanelMetrics.sessionRowLineSpacing) {
                head
                body(for: store.openRowBody)
                Spacer(minLength: 0)
                answerRow
            }
            .padding(.horizontal, PanelMetrics.sessionRowPadding)
            .padding(.vertical, 12.5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: store.openRowHeight ?? PanelMetrics.sessionRowHeight)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    /// The caption and the title, unmoved, with the chevron where the mark was.
    private var head: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.sessionRowLineSpacing) {
            HStack(spacing: 8) {
                SessionRowCaption(
                    session: session,
                    showsAttribution: store.showsProductAttribution,
                    isEmphasized: true
                )
                Spacer(minLength: 8)
                // The header and the position in the set, on the caption line's
                // trailing side — which carries nothing at all on a closed row,
                // so this costs the badge and the Project nothing (§5.2).
                if let position = store.openRowBody?.position {
                    Text(setCaption(position))
                        .font(.system(size: 11, weight: .regular).monospacedDigit())
                        .foregroundStyle(NotchPalette.label)
                        .fixedSize()
                }
                OpenRowChevron()
                    .onTapGesture { store.closeOpenRow() }
            }
            .frame(height: PanelMetrics.sessionRowCaptionHeight)

            SessionRowText(
                text: session.title,
                font: .systemFont(ofSize: 13, weight: .medium),
                color: NotchPalette.sessionTitleDrawingColor,
                lineHeight: PanelMetrics.sessionRowTitleHeight
            )
            // **The row's text is still the Thread** (§3, §6.6). Opening a row
            // takes nothing away from it: the two targets are the two answers to
            // *what do I want with this row*, and an open row still has both.
            // The chevron sits inside this and keeps its own click, because a
            // descendant's gesture takes precedence over an ancestor's.
            .contentShape(Rectangle())
            .onTapGesture { store.open(session) }
        }
    }

    /// `Scope · 2/3`, or the count alone where the product sends no header.
    ///
    /// Codex sends none, so that side carries the chevron and the count and
    /// nothing else — and **every** question draws the count, `1/1` included,
    /// because a count that appears only sometimes is a count nobody learns to
    /// read (§5.2).
    private func setCaption(_ position: RequestBodyLayout.Position) -> String {
        guard let header = store.openRowBody?.header, !header.isEmpty else {
            return position.drawn
        }
        return "\(header) · \(position.drawn)"
    }

    @ViewBuilder
    private func body(for layout: RequestBodyLayout?) -> some View {
        if let layout {
            ScrollingRequestBody(layout: layout)
        }
    }

    /// The three answers, or §11 rule 04's one control where three would stand.
    ///
    /// **Which of the two is drawn is a fact about this request** rather than
    /// about its product or its status: a row whose connection is still held
    /// can be answered here, and one whose cannot says where to answer it
    /// instead (§11 rule 06). No white ground is drawn anywhere on the second —
    /// the affirmative ground is the return key made visible, and drawing it
    /// where there is nothing for the return key to do is a promise made
    /// quietly, which is why a greyed-out `Approve` is worse than none at all.
    @ViewBuilder
    private var answerRow: some View {
        if let shape = session.request?.answerRow {
            AnswerRow(session: session, shape: shape)
        } else {
            readingControl
        }
    }

    /// §11 rule 04: one control where three will stand.
    private var readingControl: some View {
        HStack(spacing: 0) {
            Button {
                store.open(session)
            } label: {
                Text(destination)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NotchPalette.reading)
                    .padding(.horizontal, 12)
                    .frame(height: PanelMetrics.answerRowHeight)
                    .background(
                        RoundedRectangle(
                            cornerRadius: PanelMetrics.machineTextCornerRadius,
                            style: .continuous
                        )
                        .fill(NotchPalette.recessedGround)
                    )
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .frame(height: PanelMetrics.answerRowHeight)
        .padding(.top, 10 - PanelMetrics.sessionRowLineSpacing)
    }

    private var destination: String { "Answer in \(session.agent.displayName)" }

    private var accessibilityText: String {
        let asked = store.openRowBody.map { layout in
            ", " + layout.lines.joined(separator: " ")
        } ?? ""
        let position = store.openRowBody?.position.map {
            ", question \($0.index) of \($0.count)"
        } ?? ""
        return "\(session.projectName), \(session.title), "
            + "\(session.status.displayName)\(position)\(asked)"
    }
}

/// The quota block's own control, unchanged, standing where the mark was.
///
/// `16 × 16`, a `9 × 4.5` glyph at `1.4` stroke with round caps, pointing up
/// because the thing it folds is open (`expanded-panel-v2.md` §2.2). Deliberately
/// the same object rather than one that looks like it: this surface has one
/// chevron and it means one thing.
private struct OpenRowChevron: View {
    @State private var isHovered = false

    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(NotchPalette.label)
            .rotationEffect(.degrees(180))
            .frame(
                width: PanelMetrics.quotaFoldControlSize,
                height: PanelMetrics.quotaFoldControlSize
            )
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.12 : 0))
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .accessibilityLabel("Collapse this request")
            .accessibilityAddTraits(.isButton)
    }
}

/// The three objects at the foot of an open row: the field, the refusal and
/// the affirmative (`answer-in-notch.md` §7).
///
/// **The white ground is the return key made visible.** Whichever of the two
/// controls holds it is what `⏎` will do, and exactly one force moves it —
/// typing, onto the answer that carries text, because a note cannot travel with
/// a yes (§6). Neither control moves as the ground crosses between them: both
/// are their own text plus `12` a side, whether they are holding it or not.
///
/// A form with one answer omits the refusal and the field takes the space.
private struct AnswerRow: View {
    @EnvironmentObject private var store: MonitorStore
    let session: MonitoredSession
    let shape: AnswerRowShape

    var body: some View {
        HStack(spacing: 8) {
            AnswerField(
                identity: "\(session.id)#\(store.answerDraftGeneration)",
                placeholder: shape.placeholder,
                initialText: store.answerDraft,
                // §8 state 01: an answer in flight stops taking keys as well as
                // clicks. The caret goes with it, so nothing is typed into a
                // row that has already been answered.
                takesKeys: !store.isAnswerInFlight,
                onEdit: { store.answerDraftChanged(to: $0) },
                onReturn: { store.takeAnswer(store.answerGround) },
                onEscape: { store.closeOpenRow() },
                onDigit: { store.takeNumberedOption($0) }
            )
            .frame(maxWidth: .infinity)
            .frame(height: PanelMetrics.answerRowHeight)

            if let refusal = shape.refusal {
                AnswerControl(
                    label: refusal,
                    holdsGround: store.answerGround == .refusal
                ) {
                    store.takeAnswer(.refusal)
                }
            }

            AnswerControl(
                label: shape.affirmative,
                holdsGround: store.answerGround == .affirmative
            ) {
                store.takeAnswer(.affirmative)
            }
        }
        .frame(height: PanelMetrics.answerRowHeight)
        // §8 state 01: in flight, the field and both controls drop to `45%` and
        // stop taking anything. **Nothing resizes** — no spinner, no progress,
        // no new mark: the wait is a few hundred milliseconds, and anything
        // drawn to fill it would outlive the thing it described.
        .opacity(store.isAnswerInFlight ? 0.45 : 1)
        .allowsHitTesting(!store.isAnswerInFlight)
        .padding(.top, 10 - PanelMetrics.sessionRowLineSpacing)
    }
}

/// One answer: the ground when it holds it, its own text when it does not.
///
/// §6.6, in three clauses. **A click takes the answer it lands on**, whether or
/// not the ground is there — there is no select-then-confirm here, because the
/// confirm would be a second control saying what the first already said.
/// **Hover moves nothing**: an answer under the pointer takes the list's own
/// hover fill and the ground stays where the typing left it, because the ground
/// is a statement about `⏎` and a pointer crossing an answer is not an act.
/// And the width is the same either way, so nothing moves as the ground
/// crosses.
private struct AnswerControl: View {
    @EnvironmentObject private var store: MonitorStore

    let label: String
    let holdsGround: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(
                holdsGround
                    ? Color(NotchPalette.chipOnLightDrawingColor)
                    : NotchPalette.reading
            )
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: PanelMetrics.answerRowHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: PanelMetrics.machineTextCornerRadius,
                    style: .continuous
                )
                .fill(ground)
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture(perform: action)
            .accessibilityElement()
            .accessibilityLabel(label)
            // §13.3: what the ground says in ink, spoken. It is the one piece
            // of state on this row that is drawn only as brightness, so a
            // reader who cannot see it would otherwise not know what `⏎` does.
            .accessibilityValue(holdsGround ? "Return takes this" : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    /// White while it is what `⏎` does; the list's own hover fill under the
    /// pointer; nothing otherwise.
    ///
    /// A ground that has not finished arriving is drawn but is not yet a target
    /// (§6.3) — it is dimmed rather than hidden, because the eye is already
    /// following it down the row and something that appears late reads as a
    /// second object.
    private var ground: Color {
        guard !holdsGround else {
            return NotchPalette.spotlight.opacity(store.isAffirmativeArmed ? 1 : 0.45)
        }
        return Color.white.opacity(isHovered ? 0.12 : 0)
    }
}

/// The field, which is an AppKit text view and has to be.
///
/// **The caret is the one thing on this surface that ticks, and it must not be
/// ours** (§13.2). A blinking caret drawn from SwiftUI is precisely the
/// continuously running animation the overlay forbids (`AGENTS.md` §7): it
/// would invalidate the whole panel — `PanelContour` and every text measurement
/// — twice a second for as long as a row is open. Hosted here, the text system
/// draws it into its own layer, which is the same division that already sends
/// persistent motion to Core Animation.
///
/// **The text never reaches `@Published` either**, for the same reason: a
/// keystroke is not a layout change. What the store publishes is where the
/// ground is, which changes at most once per row.
private struct AnswerField: NSViewRepresentable {
    /// Which row this field belongs to, and which text the store has put in
    /// it — the only two things that refill it.
    ///
    /// §10: what was typed stays with its row for as long as that row lives, so
    /// the text view is refilled when the row changes and left alone otherwise
    /// — refilling it on every pass would put the caret back to the start under
    /// somebody's hands. The second half of the identity is
    /// ``MonitorStore/answerDraftGeneration``, which moves when the store itself
    /// replaces the text: an answer that landed, or the next question of a set.
    let identity: String
    let placeholder: String
    let initialText: String
    let takesKeys: Bool
    let onEdit: (String) -> Void
    let onReturn: () -> Void
    let onEscape: () -> Void
    /// A digit while the ground is still on an option, and whether it was taken.
    let onDigit: (Int) -> Bool

    func makeNSView(context: Context) -> AnswerFieldView {
        let view = AnswerFieldView()
        view.delegate = context.coordinator
        view.placeholder = placeholder
        view.string = initialText
        view.isEditable = takesKeys
        view.onDigit = onDigit
        context.coordinator.identity = identity
        return view
    }

    func updateNSView(_ view: AnswerFieldView, context: Context) {
        context.coordinator.onEdit = onEdit
        context.coordinator.onReturn = onReturn
        context.coordinator.onEscape = onEscape
        view.placeholder = placeholder
        view.isEditable = takesKeys
        view.onDigit = onDigit
        guard context.coordinator.identity != identity else { return }
        context.coordinator.identity = identity
        view.string = initialText
        view.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onEdit: onEdit, onReturn: onReturn, onEscape: onEscape)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var identity: String?
        var onEdit: (String) -> Void
        var onReturn: () -> Void
        var onEscape: () -> Void

        init(
            onEdit: @escaping (String) -> Void,
            onReturn: @escaping () -> Void,
            onEscape: @escaping () -> Void
        ) {
            self.onEdit = onEdit
            self.onReturn = onReturn
            self.onEscape = onEscape
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            view.needsDisplay = true
            onEdit(view.string)
        }

        /// The three keys the panel answers to here, and they are the field's
        /// own (§9.2).
        ///
        /// `⌘⏎`, the arrows, `Space` and `⇥` are deliberately unbound: a second
        /// way to approve would make the white ground advisory rather than
        /// definitive, and the whole safety of this surface rests on the ground
        /// being the literal truth about `⏎`. The digits are the one exception
        /// and are read off the event in ``AnswerFieldView/keyDown(with:)``,
        /// because what a digit means depends on whether anything has been
        /// typed and this table cannot see that.
        func textView(
            _ view: NSTextView,
            doCommandBy selector: Selector
        ) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                onReturn()
                return true
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                // `⌥⏎`, which AppKit binds here as well. `⇧⏎` does **not**
                // arrive as this and is handled in ``AnswerFieldView/keyDown``
                // — measured on Release, it arrived as `insertNewline:` and
                // sent the answer, because the standard binding only separates
                // the two inside a field editor and this is a plain text view.
                view.insertText("\n", replacementRange: view.selectedRange())
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onEscape()
                return true
            default:
                return false
            }
        }
    }
}

/// The text view itself: one line of `13` pt on the panel's recessed step.
///
/// It takes the caret when the row opens (§6.6), so a refusal costs a sentence
/// and a return and no travel at all — which is the whole of why denial is the
/// cheap direction (§6.4).
final class AnswerFieldView: NSTextView {
    var placeholder: String = ""
    /// A digit that may be an option's number rather than a character.
    var onDigit: ((Int) -> Bool)?

    /// `⇧⏎` puts a new line in the field, and only `⏎` sends (§9.2). Then the
    /// digits, which are the field's too the moment anything has been typed.
    ///
    /// **Read off the event rather than left to the binding table.** In a field
    /// editor `⇧⏎` is `insertNewlineIgnoringFieldEditor:`; in a plain text view
    /// it is `insertNewline:`, which is what `⏎` is — so the one key that must
    /// not send was sending. A refusal that explains itself is often two
    /// sentences and an alternative command is often two lines, and this is the
    /// only way to get one, which is what lets `⏎` be unambiguous.
    ///
    /// A digit is offered to the panel **bare only** — `⌥1` types a character of
    /// its own and is nobody's option number — and the panel refuses it unless
    /// the white ground is still on an option, which is §15 q08's rule and the
    /// reason this cannot be a binding: it depends on what the field holds.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.contains(.shift) {
            insertText("\n", replacementRange: selectedRange())
            return
        }
        if isBare(event),
           let digit = event.characters.flatMap({ Int($0) }),
           digit >= 1, digit <= 4,
           onDigit?(digit) == true {
            return
        }
        super.keyDown(with: event)
    }

    /// Whether this key arrived with nothing held down.
    private func isBare(_ event: NSEvent) -> Bool {
        event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad])
            .isEmpty
    }

    /// The panel's own recessed step, which is where a field belongs on it: the
    /// one surface a person is meant to put something into, drawn as the one
    /// surface that is set into the row.
    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    /// **Through `NSTextView`'s own `init(frame:)`, never the designated
    /// initialiser with a `nil` container.** A text view built with no
    /// container has no text system behind it: measured on Release, every
    /// keystroke reached `keyDown` and then fell straight through to the
    /// panel's, because there was nothing there to insert into — a field that
    /// took the caret and swallowed everything typed into it.
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        drawsBackground = false
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isVerticallyResizable = false
        isHorizontallyResizable = false
        font = NSFont.systemFont(ofSize: 13, weight: .regular)
        textColor = NotchPalette.countsSessionDrawingColor
        insertionPointColor = .white
        textContainerInset = NSSize(width: 8, height: 5)
        textContainer?.lineFragmentPadding = 0
        // A `13` pt line in a `28` pt box, so a second line scrolls rather than
        // growing the row: every height in §12 is fixed before the first
        // keystroke.
        textContainer?.widthTracksTextView = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: PanelMetrics.answerRowHeight)
    }

    /// The placeholder, drawn here rather than by a view above.
    ///
    /// A SwiftUI overlay would have to be told when the field stopped being
    /// empty, which means publishing every keystroke — the one thing this view
    /// exists to avoid.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: NotchPalette.labelDrawingColor
        ]
        (placeholder as NSString).draw(
            at: NSPoint(x: textContainerInset.width, y: textContainerInset.height),
            withAttributes: attributes
        )
    }

    /// Takes the caret as soon as it has a window to take it in.
    ///
    /// The panel becomes key in the same publish that opens the row, so this and
    /// ``OverlayPanel/latches`` are two halves of one movement — and if the
    /// window is not key yet, ``windowDidBecomeKey`` finishes the job.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    @objc private func windowDidBecomeKey() {
        window?.makeFirstResponder(self)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

/// A read-only report of where a scroller stands, drawn in place of the
/// system's own indicator: a thin line over the whole range, and a thicker,
/// capsule-ended line over the slice currently visible.
///
/// **Always drawn while there is anything to scroll**, not just while
/// scrolling or hovered — the same standard as the request body's own rail
/// this generalises. `1.5` points for the range and `3` for the position: it
/// reports where the reader is and is deliberately not a grip, because it is
/// never the only way to move.
private struct ScrollRail: View {
    let visibleHeight: CGFloat
    let contentHeight: CGFloat
    let offset: CGFloat

    private var travel: CGFloat { max(contentHeight - visibleHeight, 0) }

    var body: some View {
        if travel > 0 {
            let thumb = max(24, visibleHeight * visibleHeight / contentHeight)
            let progress = min(max(offset / travel, 0), 1)
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1.5)
                Capsule()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 3, height: thumb)
                    .offset(y: (visibleHeight - thumb) * progress)
            }
            .frame(width: 3, height: visibleHeight)
            .accessibilityHidden(true)
        }
    }
}

/// A body taller than the space it has, and how much of it is missing.
///
/// **The wheel is the only thing that scrolls it**, and nothing else on this
/// surface scrolls (§6.2). The count is what makes that honest: a fade is right
/// for a title, where what is lost is more of the same sentence, and wrong for a
/// command, where what is lost may be a second command after `&&`, a `--force`,
/// or a path outside the project. So the body says how many lines are under the
/// fold — **lines rather than bytes**, which is the unit a hidden clause hides
/// in (§15 q04) — and says nothing once nothing is.
///
/// A count that names something unreachable is an apology, which is why the two
/// arrived together: the rail reports where the reader is, at `1.5` points it is
/// not a grip, and it is never the only way to move.
private struct ScrollingRequestBody: View {
    let layout: RequestBodyLayout

    @State private var offset: CGFloat = 0

    private var travel: CGFloat {
        max(layout.contentHeight - PanelMetrics.requestBodyMaximumHeight, 0)
    }

    private var overflows: Bool { travel > 0 }

    var body: some View {
        RequestBodyView(layout: layout)
            .frame(
                maxWidth: .infinity,
                alignment: .topLeading
            )
            .offset(y: -offset)
            .frame(height: layout.drawnHeight, alignment: .top)
            .clipped()
            // The fade the count sits over. Without it the line at the fold is
            // cut through its own glyphs, which reads as damage rather than as
            // more -- and §4.4's count is drawn *over* this rather than instead
            // of it, because a fade alone cannot say a `--force` is under there.
            .mask(alignment: .top) { fold }
            .overlay(alignment: .trailing) { rail }
            .overlay(alignment: .bottomTrailing) { count }
            // **Driven rather than nested.** A second `ScrollView` inside the
            // list's own chains against it and loses -- the same finding that
            // left the Recent queue without a scroller of its own -- so the
            // wheel is read directly and the body is translated. It also makes
            // §4.4's count exact, because the offset it counts from is the
            // offset that was applied.
            //
            // **Over the body, never behind it** (`system-architecture.md` §6):
            // the catcher only ever sees a wheel event if it wins the hit test,
            // and behind the lines it never does.
            .overlay(
                WheelCatcher(claimsTheWheel: overflows) { delta in
                    offset = min(max(offset - delta, 0), travel)
                }
            )
            .onChange(of: layout) { _, _ in offset = 0 }
    }

    /// Solid to the last full line, then out.
    ///
    /// Only where there is something below: a body that fits is drawn whole, and
    /// fading its foot would say there was more when there is not.
    @ViewBuilder
    private var fold: some View {
        if layout.linesBelowTheFold(scrolledBy: offset) > 0 {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.86),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Color.black
        }
    }

    private var rail: some View {
        ScrollRail(
            visibleHeight: PanelMetrics.requestBodyMaximumHeight,
            contentHeight: layout.contentHeight,
            offset: offset
        )
    }

    /// `+2 lines`, over the fade the body's last line already has.
    ///
    /// **Spoken as well as drawn** (§13.3): a reader who cannot see the count
    /// must not be the only one who does not know something is missing.
    @ViewBuilder
    private var count: some View {
        let hidden = layout.linesBelowTheFold(scrolledBy: offset)
        if hidden > 0 {
            Text("+\(hidden) line\(hidden == 1 ? "" : "s")")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(NotchPalette.label)
                .padding(.trailing, 8)
                .accessibilityLabel(
                    "\(hidden) more line\(hidden == 1 ? "" : "s") below"
                )
        }
    }
}

/// Reads the wheel over one region, and claims nothing else.
///
/// The same shape as ``SecondaryClickCatcher``, down to the placement: an
/// `NSView` drawn **over** the region, claiming exactly one kind of event in
/// ``WheelCatcherView/hitTest(_:)`` and transparent to every other, so the
/// row's clicks and the panel's hover are untouched.
///
/// It was written as a `.background` instead, which reads as the safer half of
/// that shape and is the one thing the shape cannot do: AppKit dispatches
/// `scrollWheel` to whatever `hitTest` answers with, SwiftUI answers with the
/// frontmost hit-testable thing it finds, and the body's own lines are
/// hit-testable -- so behind them this view was never hit at all, and every
/// wheel event over an open request went to the list's `ScrollView` instead
/// (`system-architecture.md` §6).
struct WheelCatcher: NSViewRepresentable {
    /// Whether there is anything under this region for the wheel to move.
    ///
    /// A body that fits claims nothing, so the wheel falls through to the list
    /// it is drawn in: swallowing it would make the pointer resting on a short
    /// request the one place on the panel where the list cannot be scrolled.
    let claimsTheWheel: Bool
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> WheelCatcherView {
        let view = WheelCatcherView()
        view.onScroll = onScroll
        view.claimsTheWheel = claimsTheWheel
        return view
    }

    func updateNSView(_ view: WheelCatcherView, context: Context) {
        view.onScroll = onScroll
        view.claimsTheWheel = claimsTheWheel
    }
}

final class WheelCatcherView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    var claimsTheWheel = false

    override func scrollWheel(with event: NSEvent) {
        // A trackpad reports pixels and a wheel reports lines; both arrive as
        // `scrollingDeltaY`, and the precise flag is what says which.
        let delta = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : event.scrollingDeltaY * 12
        guard delta != 0 else { return }
        onScroll?(delta)
    }

    /// Whether an event of this type is one this view is entitled to take.
    ///
    /// Split out from ``hitTest(_:)`` for the reason
    /// ``SecondaryClickView/claims(_:)`` is: it is the one thing here that can
    /// be asserted without a running event loop, and the one thing that must not
    /// drift. Widen it and the lines and options underneath stop taking clicks;
    /// narrow it and the body stops scrolling.
    func claims(_ eventType: NSEvent.EventType?) -> Bool {
        claimsTheWheel && eventType == .scrollWheel
    }

    /// Claimed only for the wheel, and only where there is travel.
    ///
    /// `nil` is also the answer when there is no current event at all, which is
    /// how AppKit asks about geometry rather than about a gesture.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard claims(NSApp.currentEvent?.type) else { return nil }
        return super.hitTest(point)
    }

    /// It reads one gesture and owns no state; the field on an open row is the
    /// only thing on this panel that wants the keyboard.
    override var acceptsFirstResponder: Bool { false }
}

/// One request's body: the lines it wrapped to, and the options under them.
///
/// **The lines are the ones the layout counted**, character for character, which
/// is what makes §4.4's count of what is below the fold true rather than
/// approximately true.
private struct RequestBodyView: View {
    let layout: RequestBodyLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            text
            if !layout.options.isEmpty {
                Spacer().frame(height: PanelMetrics.optionListSpacing)
                ForEach(layout.options) { option in
                    OptionRow(
                        option: option,
                        allowsSeveralAnswers: layout.allowsSeveralAnswers
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var text: some View {
        let lines = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(layout.lines.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .font(Font(font))
                    .foregroundStyle(NotchPalette.reading)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: PanelMetrics.requestLineHeight(for: layout.setting),
                        maxHeight: PanelMetrics.requestLineHeight(for: layout.setting),
                        alignment: .leading
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if layout.setting == .machineText {
            // The recessed ground exists to mark machine text, and putting
            // prose on it would make the mark mean nothing (§4.2).
            lines
                .padding(.horizontal, PanelMetrics.machineTextHorizontalInset)
                .padding(.vertical, PanelMetrics.machineTextVerticalInset)
                .background(
                    RoundedRectangle(
                        cornerRadius: PanelMetrics.machineTextCornerRadius,
                        style: .continuous
                    )
                    .fill(NotchPalette.recessedGround)
                )
        } else {
            lines
        }
    }

    private var font: NSFont {
        layout.setting == .machineText
            ? PanelMetrics.machineTextFont
            : PanelMetrics.proseFont
    }
}

/// One option a question offers.
///
/// The numeral, the label and the description on one `24` pt line (§5.1). **The
/// option the ground is on carries the white ground** across the full content
/// width; one under the pointer takes the list's own hover fill instead, and
/// the ground does not move to meet it (§6.6) — hover is not an act.
///
/// On a row that can only be read it takes no click: with no way to send an
/// answer, an option that looked selectable would be the same quiet promise a
/// white ground would be (§11 rule 03).
private struct OptionRow: View {
    @EnvironmentObject private var store: MonitorStore

    let option: AgentQuestionOption
    let allowsSeveralAnswers: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            handle
            Text(option.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(
                    holdsGround
                        ? Color(NotchPalette.chipOnLightDrawingColor)
                        : NotchPalette.sessionTitle
                )
                .fixedSize()
            if let description = option.description {
                Text(description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(
                        holdsGround ? NotchPalette.readingOnLight : NotchPalette.label
                    )
                    .padding(.leading, 12)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 9)
        .frame(height: PanelMetrics.optionRowHeight)
        .background(
            RoundedRectangle(
                cornerRadius: PanelMetrics.machineTextCornerRadius,
                style: .continuous
            )
            .fill(ground)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { if isAnswerable { store.takeAnswer(.option(option.id)) } }
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            allowsSeveralAnswers
                ? (isTicked ? "Ticked" : "Not ticked")
                : (holdsGround ? "Return takes this" : "")
        )
        .accessibilityAddTraits(isAnswerable ? .isButton : [])
        .accessibilityAction { if isAnswerable { store.takeAnswer(.option(option.id)) } }
    }

    /// The numeral, or the box that replaces it where several may be taken.
    ///
    /// §5.5: with `multiSelect` the numerals become `12 × 12` boxes — the
    /// recessed step empty, ``NotchPalette/themeInk``'s lit value filled. It is
    /// a box rather than a digit because a digit would promise a key that does
    /// not tick.
    @ViewBuilder
    private var handle: some View {
        if allowsSeveralAnswers {
            RoundedRectangle(
                cornerRadius: PanelMetrics.machineTextCornerRadius,
                style: .continuous
            )
            .fill(
                isTicked
                    ? NotchPalette.themeInk.on
                    : NotchPalette.recessedGround
            )
            .frame(width: 12, height: 12)
            .frame(width: 19, alignment: .leading)
        } else {
            Text("\(option.id + 1)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(
                    holdsGround ? NotchPalette.readingOnLight : NotchPalette.optionNumeral
                )
                .frame(width: 19, alignment: .leading)
        }
    }

    /// Whether this row's request can be answered here at all.
    ///
    /// Asked of the request rather than passed down: these views are drawn for
    /// the one open row and for nothing else, so the store's own answer is the
    /// exact one (§11 rule 06).
    private var isAnswerable: Bool {
        store.openSession?.request?.canBeAnswered == true
    }

    private var isTicked: Bool {
        isAnswerable && store.isOptionTicked(option.id)
    }

    private var holdsGround: Bool {
        isAnswerable && store.answerGround == .option(option.id)
    }

    private var ground: Color {
        guard !holdsGround else {
            return NotchPalette.spotlight.opacity(store.isAffirmativeArmed ? 1 : 0.45)
        }
        return Color.white.opacity(isHovered && isAnswerable ? 0.12 : 0)
    }
}

/// The rule between the list and what it has let go of.
///
/// A label, a hairline and a chevron on one `32` pt line at the foot of the
/// live list (`expanded-panel-v2.md` §2.2). **The whole line is the target**,
/// and that is a departure from the quota's control: §5.4 gave that chevron a
/// `16 × 16` hit area because the rest of its line is a reading somebody might
/// want to select, and this line carries only its own name — so it takes the
/// row's own hover fill and the row's own click (§2.4 rule 08).
///
/// The count is live and is the one thing here that says there is more below
/// than is drawn: the eight points the viewport has left over at six or more
/// fall inside the sixth row's top padding and carry no ink at all, so an
/// over-full queue is drawn exactly like a full one.
private struct RecentSeam: View {
    @EnvironmentObject private var store: MonitorStore

    @State private var isHovered = false

    let count: Int

    var body: some View {
        Button {
            store.toggleRecent()
        } label: {
            SeamContent(count: count, isHovered: isHovered)
        }
        .buttonStyle(SessionRowButtonStyle())
        .frame(maxWidth: .infinity)
        .frame(height: PanelMetrics.recentSeamHeight)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Recent, \(count) session\(count == 1 ? "" : "s")")
        .accessibilityValue(store.isRecentExpanded ? "Expanded" : "Collapsed")
        .accessibilityAddTraits(.isButton)
    }
}

private struct SeamContent: View {
    @Environment(\.sessionRowIsPressed) private var isPressed

    @EnvironmentObject private var store: MonitorStore

    let count: Int
    let isHovered: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            NotchPalette.themeInk.on.opacity(borderOpacity),
                            lineWidth: 1
                        )
                )

            HStack(spacing: 8) {
                // The caption idiom exactly, separator included.
                Text("Recent · \(count)")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(isEmphasized ? NotchPalette.labelEmphasized : NotchPalette.label)
                    .fixedSize()

                // **The list's own top rule drawn again**, and it stops short
                // of the control rather than running under it: a 1 pt line
                // through a chevron reads as a strike, not as a rule.
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(
                        isHovered ? NotchPalette.sessionTitle : NotchPalette.label
                    )
                    .rotationEffect(.degrees(store.isRecentExpanded ? 180 : 0))
                    .frame(
                        width: PanelMetrics.quotaFoldControlSize,
                        height: PanelMetrics.quotaFoldControlSize
                    )
            }
            .padding(.horizontal, PanelMetrics.sessionRowPadding)
        }
        .contentShape(Rectangle())
        .frame(
            maxWidth: .infinity,
            minHeight: PanelMetrics.recentSeamHeight,
            maxHeight: PanelMetrics.recentSeamHeight
        )
        .animation(.easeOut(duration: 0.16), value: store.isRecentExpanded)
        .animation(
            isHovered
                ? .easeInOut(duration: NotchPalette.RowEmphasis.hoverEnterDuration)
                : .easeInOut(duration: NotchPalette.RowEmphasis.hoverExitDuration),
            value: isHovered
        )
        .animation(
            isPressed
                ? .easeInOut(duration: NotchPalette.RowEmphasis.pressEnterDuration)
                : .easeInOut(duration: NotchPalette.RowEmphasis.pressExitDuration),
            value: isPressed
        )
    }

    private var isEmphasized: Bool { isHovered || isPressed }

    /// The Recent seam and a retired row take the dimmer of the two border
    /// weights, and no halo at all — see ``NotchPalette/RowEmphasis``.
    private var borderOpacity: Double {
        if isPressed { return NotchPalette.RowEmphasis.utilityPressedBorderOpacity }
        if isHovered { return NotchPalette.RowEmphasis.utilityHoverBorderOpacity }
        return 0
    }
}

/// A row that has left the list, under the rule.
///
/// One line — **product · project · subject** — and an age, at half a live
/// row's height (`expanded-panel-v2.md` §2.3). **Nothing here claims a
/// status**, because the rule's meaning is that the list stops there: the
/// ground family does not travel below it, and a bare age counts the other way
/// from a bare Running reading besides.
///
/// Its click is the live row's click, unchanged, which is also the answer to
/// §8.5 question 06: a product that has gone dark is re-asked at the moment
/// somebody wants it, and `openAndWait` already reports what it could not do.
/// Its secondary click is the live row's too, meaning the same thing one rule
/// down — take this away (§2.4 rule 09).
private struct RetiredRow: View {
    @EnvironmentObject private var store: MonitorStore

    @State private var isHovered = false

    let departure: RecentDeparture

    var body: some View {
        Button {
            store.open(departure.session)
        } label: {
            RetiredRowContent(departure: departure, isHovered: isHovered)
        }
        .buttonStyle(SessionRowButtonStyle())
        .frame(maxWidth: .infinity)
        .frame(height: PanelMetrics.retiredRowHeight)
        .overlay {
            SecondaryClickCatcher { store.removeFromRecent(departure) }
        }
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityText)
        .accessibilityActions {
            Button("Remove this row") { store.removeFromRecent(departure) }
        }
    }

    /// The line spelled out, with the age as words.
    ///
    /// **The product is named here whether or not a badge is drawn**, and that
    /// is not the live row's rule. A badge is dropped when there is nothing to
    /// disambiguate *on the surface*; a reader arriving at a line under a rule
    /// has no surface to compare it against, and the product is the first thing
    /// that says where clicking would go.
    private var accessibilityText: String {
        let session = departure.session
        return "\(session.agent.displayName), \(session.projectName), "
            + "\(session.title), \(departure.spokenAgeText(at: store.recentReadAt))"
    }
}

private struct RetiredRowContent: View {
    @Environment(\.sessionRowIsPressed) private var isPressed

    @EnvironmentObject private var store: MonitorStore

    let departure: RecentDeparture
    let isHovered: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            NotchPalette.themeInk.on.opacity(borderOpacity),
                            lineWidth: 1
                        )
                )

            HStack(spacing: 12) {
                breadcrumb
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Bare, tabular, and never wider than two characters — the
                // window and the reading agree (§2.3).
                Text(departure.ageText(at: store.recentReadAt))
                    .font(.system(size: 13, weight: .light).monospacedDigit())
                    .foregroundStyle(isEmphasized ? NotchPalette.labelEmphasized : NotchPalette.label)
                    .fixedSize()
            }
            .padding(.horizontal, PanelMetrics.sessionRowPadding)
        }
        .contentShape(Rectangle())
        .frame(
            maxWidth: .infinity,
            minHeight: PanelMetrics.retiredRowHeight,
            maxHeight: PanelMetrics.retiredRowHeight
        )
        .animation(
            isHovered
                ? .easeInOut(duration: NotchPalette.RowEmphasis.hoverEnterDuration)
                : .easeInOut(duration: NotchPalette.RowEmphasis.hoverExitDuration),
            value: isHovered
        )
        .animation(
            isPressed
                ? .easeInOut(duration: NotchPalette.RowEmphasis.pressEnterDuration)
                : .easeInOut(duration: NotchPalette.RowEmphasis.pressExitDuration),
            value: isPressed
        )
    }

    /// **product · project · subject**, in the three inks the panel already has.
    ///
    /// It overflows and fades rather than truncating, like every other line
    /// here. The badge follows the live row's presence rule exactly (§8.6): the
    /// surface names products while more than one is on it, and stops when
    /// there is nothing to tell apart.
    private var breadcrumb: some View {
        HStack(spacing: 6) {
            if store.showsProductAttribution {
                ProductBadge(name: departure.session.agent.displayName)
            }

            (
                Text("\(departure.session.projectName) · ")
                    .foregroundStyle(isEmphasized ? NotchPalette.labelEmphasized : NotchPalette.label)
                    + Text(departure.session.title)
                    .foregroundStyle(NotchPalette.reading)
            )
            .font(.system(size: 13))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .mask(
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(
                    colors: [.black, .black.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: PanelMetrics.rowTrailingFadeWidth)
            }
        )
    }

    private var isEmphasized: Bool { isHovered || isPressed }

    /// The Recent seam and a retired row take the dimmer of the two border
    /// weights, and no halo at all — see ``NotchPalette/RowEmphasis``.
    private var borderOpacity: Double {
        if isPressed { return NotchPalette.RowEmphasis.utilityPressedBorderOpacity }
        if isHovered { return NotchPalette.RowEmphasis.utilityHoverBorderOpacity }
        return 0
    }
}

private struct SessionRowContent: View {
    @Environment(\.sessionRowIsPressed) private var isPressed

    @EnvironmentObject private var store: MonitorStore

    let session: MonitoredSession
    let isHovered: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            NotchPalette.themeInk.on.opacity(borderOpacity),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: NotchPalette.themeInk.on.opacity(glowOpacity),
                    radius: glowRadius
                )

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: PanelMetrics.sessionRowLineSpacing) {
                    SessionRowCaption(
                        session: session,
                        showsAttribution: store.showsProductAttribution,
                        isEmphasized: isEmphasized
                    )

                    SessionRowText(
                        text: session.title,
                        font: .systemFont(ofSize: 13, weight: .medium),
                        color: NotchPalette.sessionTitleDrawingColor,
                        lineHeight: PanelMetrics.sessionRowTitleHeight
                    )

                    // **The last thing said about this row**, which is the
                    // product's own preview until an answer leaves from here
                    // and this app has something newer to say (§8 states 02
                    // and 03). One line, in one ink, either way.
                    if let preview = store.previewLine(for: session) {
                        SessionRowText(
                            text: preview,
                            font: .systemFont(ofSize: 13, weight: .light),
                            color: NotchPalette.labelDrawingColor,
                            lineHeight: PanelMetrics.sessionRowPreviewHeight,
                            sweeps: sweepsBody
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SessionStatusControl(session: session)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, PanelMetrics.sessionRowPadding)
        }
        .contentShape(Rectangle())
        .frame(
            maxWidth: .infinity,
            minHeight: PanelMetrics.sessionRowHeight,
            maxHeight: PanelMetrics.sessionRowHeight
        )
        .animation(
            isHovered
                ? .easeInOut(duration: NotchPalette.RowEmphasis.hoverEnterDuration)
                : .easeInOut(duration: NotchPalette.RowEmphasis.hoverExitDuration),
            value: isHovered
        )
        .animation(
            isPressed
                ? .easeInOut(duration: NotchPalette.RowEmphasis.pressEnterDuration)
                : .easeInOut(duration: NotchPalette.RowEmphasis.pressExitDuration),
            value: isPressed
        )
    }

    private var sweepsBody: Bool { store.sweepsBody(for: session) }

    private var isEmphasized: Bool { isHovered || isPressed }

    /// The row's edge, in ``NotchPalette/themeInk``'s lit colour — see
    /// ``NotchPalette/RowEmphasis``. No longer a change to the row's own
    /// fill, which stays black at every state so a tile drawn on it never has
    /// to lift for anything but the panel's own black.
    private var borderOpacity: Double {
        if isPressed { return NotchPalette.RowEmphasis.pressedBorderOpacity }
        if isHovered { return NotchPalette.RowEmphasis.hoverBorderOpacity }
        return 0
    }
    private var glowOpacity: Double {
        if isPressed { return NotchPalette.RowEmphasis.pressedGlowOpacity }
        if isHovered { return NotchPalette.RowEmphasis.hoverGlowOpacity }
        return 0
    }
    private var glowRadius: CGFloat {
        isPressed
            ? NotchPalette.RowEmphasis.pressedGlowRadius
            : NotchPalette.RowEmphasis.hoverGlowRadius
    }
}

private struct SessionStatusControl: View {
    @EnvironmentObject private var store: MonitorStore
    let session: MonitoredSession
    /// Whether the pointer is on **this mark**, rather than anywhere on the row.
    ///
    /// The distinction is the whole of `answer-in-notch.md` §3: the row's text
    /// is the Thread and the mark is the request, so a pointer resting on the
    /// title must not offer a word describing what the mark would do. It is
    /// held here rather than passed down for the same reason — the row's own
    /// hover answers a different question.
    @State private var isMarkHovered = false

    // One mark per row at most, and no hue — this surface says everything with
    // brightness and shape, and the amber and green dots were the only two
    // colours left on it. What changed in `figma-design.md` page 14 is that the
    // mark now has three silhouettes rather than one drawn three ways: a bare
    // reading while the turn runs, the same reading on white while it wants a
    // person, and on a dim ground once it has finished.
    //
    // **Presence and brightness were both comparisons, and that was the bug.**
    // "No timer" only reads as finished beside a row that has one, and a white
    // timer only reads as waiting beside a dimmer one — so a row read on its
    // own, or a list where every row happens to be in the same state, answered
    // neither question. A ground is a silhouette, which one row can answer
    // alone. It is the ``SubagentBadgeView`` tile at reading width, which is
    // also why the two compose here without a case of their own.
    //
    // A finished row with a subagent still working keeps the badge in this
    // slot, as before: the turn's own clock has stopped — it really did end —
    // but the thread has not, and the badge is already this tile, so the
    // silhouette is unchanged and only what sits inside it differs.
    //
    // **The ground has both states, and which one it gets is the whole
    // difference between two very different situations.** Dim, work is in
    // flight and nobody is needed. Bright, something here is stopped on a
    // question — the turn itself, or a subagent of it, which is reachable on a
    // Completed row because a subagent's dialog can open after the parent
    // turn's terminal. The row's own state is untouched either way; see
    // ``wantsAttention``.
    var body: some View {
        if session.status.wantsPerson {
            // **The name, not the duration** (`panel-v2.md` §3.5). A row that
            // wants a person says what it wants them for, and the ground is
            // sized once for the longest word it can hold so that nothing moves
            // when a passing pointer changes that word to `Answer` or `Read`
            // (`answer-in-notch.md` §3.3). A ground sized for `0:42` could not
            // hold either without moving, which is why the two could not both
            // live here and why the duration went to the finished row's dark
            // ground.
            //
            // It reads the row's **own** turn and never its derived status, so
            // a Running row whose subagent is waiting keeps its timer and says
            // so in brightness alone -- which is `CONTEXT.md`'s rule that a row
            // reports one turn, with the ground as its single exception.
            waitingWord
        } else if let startedAt = store.elapsedStart(for: session) {
            reading(startedAt: startedAt, stoppedAt: nil)
        } else if session.showsSubagentBadge {
            // `dual-agent-design.md` §10: an expanded row's badge is neutral,
            // whatever else is connected -- the row already names its product
            // on the caption above, and since `colour-v2.md` §1 there is no
            // product hue for it to be neutral *against*. One badge carrying
            // the whole count, with the ground saying whether any of them is
            // stopped.
            SubagentBadgeView(badge: session.subagentBadge)
        } else if let span = store.finishedElapsed(for: session) {
            // What the turn took, which the slot used to throw away. No other
            // part of this surface reports it, and it is what turns the mark
            // from an absence into a record.
            reading(startedAt: span.start, stoppedAt: span.end)
        } else if session.status.keepsTiming {
            // Unfinished but its start was never observed — unreachable with
            // hook-sourced data, and it must not be left unmarked when previews
            // are hidden and there is no swept body either.
            Circle()
                .fill(NotchPalette.label)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
    }

    /// What this row wants, on the ground that says it wants something.
    ///
    /// A `Text` rather than the layer-backed readout it replaces, and that is
    /// an improvement rather than a compromise: the readout redrew this cell
    /// once a second for as long as a row sat waiting, and a name does not tick
    /// at all. `AGENTS.md` §7's rule is about continuous motion, and this
    /// removes some.
    private var waitingWord: some View {
        ReadingGround(
            fill: NotchPalette.spotlight,
            width: PanelMetrics.waitingMarkWidth
        ) {
            Text(word)
                .font(Font(PanelMetrics.waitingMarkFont))
                .foregroundStyle(Color(NotchPalette.chipOnLightDrawingColor))
                .lineLimit(1)
                .fixedSize()
        }
        .onHover { isMarkHovered = $0 }
        .contentShape(Rectangle())
        // **The mark is the request; the text is the Thread** (§3). A tap on a
        // descendant takes precedence over the row's own button, so this is the
        // second target without the row becoming two views — and no other row
        // gains one, because a row with no mark has nothing to open.
        .onTapGesture { store.toggleOpenRow(session) }
        // Spoken as an action rather than a second label: assistive technology
        // reaches it by its own means, which are not a pointer (§13.3).
        .accessibilityElement()
        .accessibilityLabel(session.status.displayName)
        .accessibilityAddTraits(session.request == nil ? [] : .isButton)
        .accessibilityAction {
            store.toggleOpenRow(session)
        }
    }

    /// The word inside the ground: the status at rest, and what a click would
    /// do under the pointer.
    ///
    /// `Read` where the request cannot be answered from here and `Answer` where
    /// it can — which is a fact about **this row's request** rather than about
    /// its product, because the two products differ per shape rather than
    /// wholesale (`answer-in-notch.md` §11 rule 06).
    private var word: String {
        guard isMarkHovered else { return session.status.displayName }
        // `Read` until this request can genuinely be answered from here. The
        // word is a promise about what a click does, and with no write path
        // built there is nothing behind `Answer` -- which is the same rule that
        // keeps the white ground off the open row until there is (§11 rule 03).
        return session.request?.canBeAnswered == true
            ? PanelMetrics.waitingMarkAnswerWord
            : PanelMetrics.waitingMarkReadWord
    }

    /// The reading, on the ground its state gives it.
    ///
    /// Running is the one state drawn bare: a set of silhouettes needs one
    /// member that is nothing, and it should be the state that fills most of
    /// the list.
    @ViewBuilder
    private func reading(startedAt: Date, stoppedAt: Date?) -> some View {
        let readout = ElapsedReadout(
            startedAt: startedAt,
            stoppedAt: stoppedAt,
            tick: store.elapsedTick.eraseToAnyPublisher(),
            tint: tint,
            weight: weight
        )
        if let fill = groundFill {
            ReadingGround(fill: fill) { readout }
        } else {
            readout
        }
    }

    /// The ground under the reading, or nil on the one state that has none.
    private var groundFill: Color? {
        if wantsAttention { return NotchPalette.spotlight }
        guard !session.status.keepsTiming else { return nil }
        return NotchPalette.restingInk.chipFill
    }

    /// Whether this row wants the person, from either of the two places that
    /// can want them.
    ///
    /// The turn's own state is the first. The second is a subagent of this
    /// thread sitting on a permission prompt, which is not the turn's state and
    /// must not be turned into one: the row stays Completed, its clock stays
    /// stopped, its preview stays the final answer, and it stays dismissable.
    /// Only the brightness changes — which is what this surface says everything
    /// with, and it is exactly the difference between `1 subagent` meaning
    /// "still working" and meaning "stopped, waiting for you".
    private var wantsAttention: Bool {
        session.status == .inputNeeded
            || session.status == .approvalNeeded
            || session.subagentsAwaitingApproval
    }

    /// The reading is always whichever end of the pair its ground is not.
    ///
    /// Brightness is still the attention channel; it has moved from the four
    /// glyph strokes onto the filled area behind them, which is the whole of
    /// what makes it legible at a glance instead of only in comparison.
    private var tint: NSColor {
        wantsAttention
            ? NotchPalette.chipOnLightDrawingColor
            : NotchPalette.labelDrawingColor
    }

    private var weight: NSFont.Weight {
        wantsAttention ? .medium : .light
    }
}

/// The row's leading `11 pt` line: the Project, and — while more than one
/// product is connected — a badge naming which product this one is.
///
/// **One presentation, and it is the only one** (`colour-v2.md` §5). The four
/// the picker used to offer all answered *which product* in a channel other
/// than the name: two tinted the name, one struck a rail down the block's
/// leading edge, and the fourth was this chip. Three of them are gone with the
/// product hues, so the chip is what is left — drawn in the ink the user chose
/// rather than in one that says whose it is, which is the whole of the
/// decision.
///
/// **The badge, then the Project, with no separator between them**
/// (`panel-v2.md` §3.4). The `Codex ·` prefix the chip replaces had a dot
/// dividing two words inside one grey run; beside a chip that dot is a boundary
/// after a boundary. The `6` between them is the badge's own padding, so
/// nothing is measured here that was not measured before.
///
/// The attribution costs horizontal space and what it costs comes out of the
/// Project text. That is accepted rather than overlooked: the caption is the
/// least important line in the row and it ends in a fade rather than an
/// ellipsis, so losing its tail is the cheapest thing on this surface to lose.
private struct SessionRowCaption: View {
    let session: MonitoredSession
    let showsAttribution: Bool
    /// Whether the row this caption sits in is under the pointer or held
    /// down, so its own text can lift a shade the way the row's border does.
    var isEmphasized: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if showsAttribution {
                ProductBadge(name: session.agent.displayName)
            }

            Text(session.projectName)
                .foregroundStyle(
                    isEmphasized ? NotchPalette.labelEmphasized : NotchPalette.label
                )
                .font(.system(size: 11, weight: .light))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        // The line is the badge's own height whether or not a badge is in it,
        // so nothing on a row moves at the moment a second product connects.
        .frame(height: PanelMetrics.sessionRowCaptionHeight)
    }
}

/// A product's name, in the one presentation this surface has for it.
///
/// Ground from ``NotchPalette/themeInk``'s unlit value and text from its lit
/// one, so the chip and the mark on the bar can never drift.
///
/// **The hue lives in the text, not in the ground, and that is by
/// construction.** The unlit value runs at `0.55 ×` the lit chroma at
/// `L 0.235` — what makes a `5 × 5` dark grid carry any hue at all — and at
/// badge size that reads as near-black. The ground's job is to be a boundary
/// and the text's is to be the colour.
private struct ProductBadge: View {
    let name: String

    var body: some View {
        let ink = NotchPalette.themeInk
        Text(name)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(ink.on)
            .padding(.horizontal, PanelMetrics.productBadgePadding)
            .frame(height: PanelMetrics.productBadgeHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: PanelMetrics.productBadgeRadius,
                    style: .continuous
                )
                .fill(ink.off)
            )
            .fixedSize()
    }
}

/// Turns a secondary click on the view it covers into one call, and leaves
/// every other event alone.
///
/// **Why AppKit.** SwiftUI has no secondary-click gesture. What it has is
/// `contextMenu`, which is a menu -- a second click to make a one-item choice,
/// on a panel that hides itself as soon as the pointer leaves it. The press
/// itself is the whole interaction here, so the press is what this reads.
///
/// **How it stays out of the way.** The view sits above the row and would
/// otherwise swallow the primary click the row is built around. `hitTest`
/// answers only while the event being dispatched is a secondary press;
/// everything else -- the primary click, the hover that expands the panel,
/// cursor tracking -- gets `nil` and finds the SwiftUI button underneath, as if
/// this were not here.
struct SecondaryClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> SecondaryClickView {
        let view = SecondaryClickView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: SecondaryClickView, context: Context) {
        // Re-assigned rather than captured once: the closure holds the row this
        // view was made for, and SwiftUI reuses the view when the list reorders.
        nsView.action = action
    }
}

final class SecondaryClickView: NSView {
    var action: (() -> Void)?

    /// Whether an event of this type is one this view is entitled to take.
    ///
    /// Split out from ``hitTest(_:)`` because it is the one thing here that can
    /// be asserted without a running event loop, and the one thing that must
    /// not drift: widen it and the row underneath stops opening, because its
    /// primary click never reaches the button.
    static func claims(_ eventType: NSEvent.EventType?) -> Bool {
        eventType == .rightMouseDown || eventType == .rightMouseUp
    }

    /// Claimed only for the secondary press. See ``SecondaryClickCatcher``.
    ///
    /// `nil` is also the answer when there is no current event at all, which is
    /// how AppKit asks about geometry rather than about a click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard Self.claims(NSApp.currentEvent?.type) else { return nil }
        return super.hitTest(point)
    }

    /// The overlay is not activating and never becomes key, so the panel is
    /// clicked while another application holds the front every time. Without
    /// this the first press on it would be spent bringing this app forward,
    /// which it does not even do.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// On the press, not the release, which is when a secondary click acts
    /// everywhere else on this system -- a menu opens under the pointer the
    /// moment the button goes down.
    override func rightMouseDown(with event: NSEvent) {
        action?()
    }
}

private struct SessionRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.sessionRowIsPressed, configuration.isPressed)
    }
}

private struct SessionRowPressedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var sessionRowIsPressed: Bool {
        get { self[SessionRowPressedKey.self] }
        set { self[SessionRowPressedKey.self] = newValue }
    }
}

#Preview("Notch Expanded") {
    NotchOverlayView()
        .environmentObject(MonitorStore())
        .frame(
            width: PanelMetrics.expandedBaselineWidth,
            height: PanelMetrics.expandedHeight(
                compactHeight: PanelMetrics.referenceCompactHeight
            )
        )
        .background(Color.gray.opacity(0.2))
}
