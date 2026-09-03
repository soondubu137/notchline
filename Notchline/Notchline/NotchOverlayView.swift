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
        let usage = store.tokenRemainingPercent.map { "\($0)% usage remaining" }
            ?? "usage remaining unavailable"
        // Spoken, not the "12:34" the notch draws: VoiceOver reads that as a
        // time of day. The label names it as the longest of the running turns,
        // because a bare duration beside a summary status is unattributable.
        let elapsed = store.spokenLongestElapsedText.map { ", longest running for \($0)" }
            ?? ""
        // The collapsed slot draws one bare badge per product, told apart by
        // ink alone; spoken, each has to name its product and say what it
        // counts -- and together they are the only thing on the surface saying
        // work is still in flight once every turn has finished.
        let subagents = store.spokenRunningSubagentText.map { ", \($0)" } ?? ""
        // The breathing column, which VoiceOver cannot see move. It is the one
        // thing on this surface said by motion alone, so it has to be said here
        // too -- §10's rule about colour, applied to the channel that replaced
        // it.
        let finished = store.spokenBuriedCompletionText.map { ", \($0)" } ?? ""
        return "Codex, \(store.sessions.count) related sessions, status "
            + "\(store.statusDisplayName)\(elapsed)\(subagents)\(finished), \(usage)"
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
            StatusReadout(
                marks: store.compactDrawnMarks,
                text: statusText,
                showsText: showsStatusText,
                reservesColumnRoom: reservesRoom,
                spacing: PanelMetrics.expandedReadoutSpacing,
                matrixSize: PanelMetrics.statusMatrixSize,
                markSpacing: PanelMetrics.compactMatrixSpacing,
                breathesBuriedCompletions: !store.isExpanded
            )

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

    private var statusText: String {
        // One name in every form. The resting pill used to keep a shorter word
        // when it widened, because its width was composed from an abbreviated
        // label and the panel's longer sentence would have overflowed a pill
        // sized for the short one; with a single name
        // (``MonitorStatus/displayName``) the width the pill reserves and the
        // word it draws are the same in both states, expanded or not.
        store.statusDisplayName
    }

    private var showsStatusText: Bool {
        store.drawsCompactStatusName
    }

    /// Whether this form holds room it is not drawing into, which is now the
    /// expanded header's session columns and nothing else.
    ///
    /// ``MonitorStore/reservesCompactRoom``, which is also what the panel's own
    /// width is composed under, so the room reserved and the room drawn into
    /// cannot come apart. It is **not** the question `showsStatusText` asks any
    /// more: the collapsed pill draws a word and hugs its marks, and for as
    /// long as the two shared one spelling the pill held column room whose only
    /// effect was `35` pt of padding against its trailing edge.
    private var reservesRoom: Bool {
        store.reservesCompactRoom
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

/// The collapsed surface's trailing wing: the subagent badges, the elapsed
/// reading, or both sharing the slot.
///
/// Present while a turn is timed or a subagent is still working, absent
/// otherwise so a notched display shows no empty second cut-out. The expanded
/// view times each row individually instead.
///
/// The badges and the reading are two views sharing one slot, not one raster
/// the way the count used to be baked into the timer's own prefix: a badge is a
/// static reading that only changes when a subagent starts, stops or is stopped
/// on a question, and drawing it apart from the reading's once-a-second layer
/// keeps that layer from re-rastering on every badge change and vice versa.
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
        HStack(spacing: PanelMetrics.subagentBadgeTimerSpacing) {
            let badges = store.compactSubagentBadges
            if !badges.isEmpty {
                SubagentBadgeRow(badges: badges)
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
            if let startedAt = store.compactTimerStart {
                ReadingGround(fill: .clear) {
                    ElapsedReadout(
                        startedAt: startedAt,
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
        [store.compactSubagentBadges.isEmpty, store.compactTimerStart == nil]
    }

    /// Fading rather than appearing, because the wing they stand in is a width
    /// that opens for them: a reading arriving at full ink would be drawn over
    /// the cut-out for as long as the panel edge took to clear it.
    private static let markFade = AnyTransition.asymmetric(
        insertion: .opacity.animation(PanelMotion.fade(isArriving: true)),
        removal: .opacity.animation(PanelMotion.fade(isArriving: false))
    )
}

private struct StatusReadout: View {
    /// What this surface draws, which on a collapsed notched bar is not
    /// necessarily every mark: ``MonitorStore/compactDrawnMarks``.
    let marks: [PresenceMark]
    let text: String
    let showsText: Bool
    /// Whether the panel this readout is drawn in has held room for every
    /// mark's session column, drawn or not.
    ///
    /// ``MonitorStore/reservesCompactRoom``: true in the expanded header alone,
    /// where the marks are packed into a fixed reservation and the status name
    /// is drawn back over what no column is using. False on both collapsed
    /// forms, where the surface is exactly as wide as the marks it draws and
    /// the panel's own edges move instead — the notched bar's leading one, and
    /// both of the pill's, since it is centred.
    ///
    /// **The pill draws a status name under that and needs no slide.** Its
    /// mark stack hugs, so a column opening genuinely widens the stack and the
    /// word after it is carried by the layout, on the curve
    /// ``SessionCountDots`` animates its own width with. The slide exists for
    /// the one form whose stack cannot change width.
    let reservesColumnRoom: Bool
    let spacing: CGFloat
    let matrixSize: CGFloat
    let markSpacing: CGFloat
    /// Whether a column may breathe here at all.
    ///
    /// The breath exists to compensate for a summary, and only the collapsed
    /// form summarises: expanded, the list naming every row is directly beneath
    /// this readout, so a moving column would be saying what the rows are about
    /// to spell out. The same reason the top bar takes the dot columns but not
    /// the subagent badges ([`dual-agent-design.md`](dual-agent-design.md) §11).
    let breathesBuriedCompletions: Bool

    /// How far the label is drawn back over its own slot, animated on the
    /// column's curve. Held rather than computed so the write that moves it can
    /// say which way the room went.
    @State private var slide: CGFloat = 0

    var body: some View {
        HStack(spacing: spacing) {
            if !marks.isEmpty {
                HStack(spacing: markSpacing) {
                    // Order is `AgentKind`'s and never urgency's, so a mark
                    // never moves out from under the eye reading it.
                    ForEach(marks, id: \.agent) { mark in
                        // A product's mark is the matrix and the column of
                        // session dots beside it; the resting grey is the
                        // matrix alone, because nothing is connected behind it
                        // to have rows. Spacing is zero here because the column
                        // owns the gap it stands off by, so the two collapse
                        // together at no rows -- see ``SessionCountDots``.
                        HStack(spacing: 0) {
                            NotchStatusMatrix(
                                state: NotchMatrixState(mark.status),
                                size: matrixSize,
                                agent: mark.agent
                            )
                            if let agent = mark.agent {
                                SessionCountDots(
                                    count: mark.sessionCount,
                                    agent: agent,
                                    matrixSize: matrixSize,
                                    breathes: breathesBuriedCompletions
                                        && mark.buriesAFinishedTurn
                                )
                            }
                        }
                        .transition(Self.markFade)
                    }
                }
                // **The anchor, on the two forms that hold a position.** The
                // marks are given the room every column would take and packed
                // into it from the leading edge, so the first matrix stands in
                // one place whatever the counts do: a column opening pushes
                // only the marks after it, and the last mark's column pushes
                // nothing.
                //
                // This is `PanelMetrics.marksWidth`, the same expression those
                // panels are measured from (``MonitorStore/currentPanelSize``),
                // so the room reserved and the room drawn into cannot drift.
                //
                // **The notched bar takes `nil` and hugs.** Its wing is
                // `PanelMetrics.drawnMarksWidth` — the marks and nothing else —
                // so a frame here would be holding open room the panel has
                // already given back, and the last mark would stand a column
                // short of the cut-out it is supposed to meet. The column
                // widths inside still animate on their own
                // (``SessionCountDots``), which is what carries this stack's
                // width, and the panel's leading edge travels the same curve to
                // meet it.
                .frame(width: reservedMarksWidth, alignment: .leading)
            }

            if showsText {
                // **The label rides with the marks, by its drawing and not by
                // its layout.** Its slot stays where the reservation put it and
                // the glyphs are drawn back over the room no column is using,
                // which is the same trick the dot itself is placed with (see
                // ``SessionCountDots``) -- and the reason the readout is still
                // exactly ``PanelMetrics/marksWidth`` plus a gap plus a word,
                // whatever the counts are doing.
                //
                // Everything inside the label is framed to its own glyph raster
                // rather than to its bounds, and its sweep is installed against
                // that raster too, so a translation costs it nothing: no
                // re-rasterising, no sweep rebuilt, no hand-over disturbed.
                SearchlightLabel(text: text, isSweeping: isActive)
                .offset(x: slide)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        // The transaction the mark transitions above run in. Each carries its
        // own curve, so what this supplies is only the fact that a mark
        // arriving or leaving is animated at all -- on the same curve the
        // panel's own edge travels, since the two are one movement.
        .animation(PanelMotion.animation, value: drawnProducts)
        // Moved by an explicit write on the column's own curve rather than by
        // inheriting one. A packed mark's width change animates inside the mark
        // that owns it; two stacks out, at the label, that arrived as a jump --
        // the marks glided and the name snapped. What the eye is on here is the
        // name, so it is the one thing on this surface that cannot be left to
        // inherit.
        //
        // On the readout and not on the label, which is drawn only where there
        // is room for a word (``showsStatusText``): tracked from inside that
        // branch, a collapsed notched surface would stop following the counts
        // and hand the panel a stale offset to open with.
        .onChange(of: unpackedColumnRoom, initial: true) { previous, room in
            // The first application is the readout being built, not a column
            // moving: take the position rather than animating to it.
            guard previous != room else {
                slide = -room
                return
            }
            // Less room going unused means a column opened ahead of the label
            // and is pushing it along.
            withAnimation(PanelMotion.slot(isOpening: room < previous)) {
                slide = -room
            }
        }
    }

    /// The reserved column room no mark is standing in, which is how far back
    /// over its own slot the label is drawn -- see
    /// ``PanelMetrics/unpackedColumnRoom(_:matrixSize:)``.
    ///
    /// Zero where nothing is reserved: there is no unused room to draw back
    /// over, and the notched bar draws no label to do it with.
    private var unpackedColumnRoom: CGFloat {
        guard reservesColumnRoom else { return 0 }
        return PanelMetrics.unpackedColumnRoom(marks, matrixSize: matrixSize)
    }

    /// The room the panel has already reserved for the marks, or `nil` where it
    /// has reserved none and this stack simply hugs what it draws.
    private var reservedMarksWidth: CGFloat? {
        guard reservesColumnRoom else { return nil }
        return PanelMetrics.marksWidth(
            marks.count,
            areProductMarks: marks.contains { $0.agent != nil }
        )
    }

    /// The label sweeps if *any* mark is in flight. There is one label for both
    /// products and it takes the most urgent status, so it has to follow the
    /// most urgent mark rather than a single product's.
    private var isActive: Bool {
        marks.contains { NotchMatrixState($0.status).isActive }
    }

    /// What the readout is drawing, as against what those marks are saying.
    ///
    /// A mark changing status is redrawn where it stands; a mark *arriving* or
    /// *leaving* is a wing opening or closing around it, and that is the only
    /// change this animation is for. Keyed on the products drawn rather than on
    /// the marks themselves so a matrix falling from `Working...` to
    /// `Completed` starts no transition.
    private var drawnProducts: [AgentKind?] {
        marks.map(\.agent)
    }

    /// A mark arriving into the wing that opened for it, or leaving before it
    /// shuts -- the same fade, and the same reasoning, as the badges and the
    /// reading in the trailing slot (``PanelMotion/fade(isArriving:)``).
    ///
    /// It earns its keep on the collapsed notched bar with `Hide the wings` on,
    /// where a matrix comes out from behind the cut-out on its own account: at
    /// full ink from the first frame it would be drawn *over* the cut-out for
    /// as long as the panel's edge took to clear it.
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
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        VStack(spacing: 0) {
            sessionRegion
            ExpandedPanelFooter()
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var sessionRegion: some View {
        Group {
            if store.sessions.isEmpty {
                Text(store.emptyListMessage)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(NotchPalette.label)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(height: PanelMetrics.thinExpandedBodyHeight)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(store.sessions) { session in
                            SessionRow(session: session)
                        }
                    }
                }
                .frame(
                    width: store.currentPanelSize.width
                        - store.sessionRowGutter * 2,
                    height: PanelMetrics.sessionViewportHeight(
                        forSessionCount: store.sessions.count
                    )
                )
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal, PanelMetrics.expandedHorizontalPadding)
        }
    }
}

/// The quota footer: one rule per product, and a shared usage line.
///
/// One product draws a single full-width rule, exactly as before. Two draw
/// Codex's full-width rule above a split row of Claude Code's two windows —
/// the halving is not to make them fit but because that product genuinely has
/// two windows to report, a 5-hour session one and a 7-day one.
private struct ExpandedPanelFooter: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.footerRuleSpacing) {
            if isFolded {
                // Today's line rises to where a caption always starts, at the
                // top of the footer box, and the rules are simply not drawn.
                QuotaFoldLine { FooterCaption(store.foldedTodayText) }
            } else {
                ForEach(store.footerRules) { rule in
                    FooterRuleRow(rule: rule, inlineTodayText: inlineTodayText)
                }

                if let today = store.footerTodayText {
                    QuotaFoldLine { FooterCaption(today) }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: store.expandedFooterHeight, alignment: .top)
        .padding(.horizontal, PanelMetrics.expandedHorizontalPadding)
    }

    private var isFolded: Bool {
        store.isQuotaFolded && store.showsQuotaFoldControl
    }

    /// The single-Codex footer keeps today's tokens in the one caption it has,
    /// rather than spending a second line on three words.
    private var inlineTodayText: String? {
        store.footerTodayText == nil ? store.expandedFooterText : nil
    }
}

/// The footer's last line, and the disclosure that folds the rules away.
///
/// The chevron is the whole hit target. The rest of the line is a reading —
/// today's tokens — and a number that resizes the panel when clicked is a trap
/// for anyone reaching in to select or simply read it; the affordance and the
/// target are the same `16pt` square instead.
private struct QuotaFoldLine<Content: View>: View {
    @EnvironmentObject private var store: MonitorStore

    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: PanelMetrics.footerWindowSpacing) {
            content()

            if store.showsQuotaFoldControl {
                QuotaFoldChevron(isFolded: store.isQuotaFolded)
            }
        }
        // The control is a point taller than the caption it rides. The footer's
        // own height does not move: the trailing `Spacer` absorbs it.
        .frame(height: PanelMetrics.quotaFoldControlSize)
    }
}

/// One glyph, turned 180° between the two states rather than swapped for a
/// second drawing.
///
/// It points down while folded because the panel hangs from the notch and can
/// only grow downward — the chevron points the way the panel will move, which is
/// also the "show more" every list uses. Being the only hit target, it carries
/// the gear's whole hover treatment — the wash behind it and the brighter
/// glyph — so the square it answers to is visible before the click, not
/// guessed at.
private struct QuotaFoldChevron: View {
    @EnvironmentObject private var store: MonitorStore

    @State private var isHovered = false

    let isFolded: Bool

    var body: some View {
        Button {
            store.toggleQuotaFold()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isHovered ? NotchPalette.sessionTitle : NotchPalette.label)
                .rotationEffect(.degrees(isFolded ? 0 : 180))
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
        .animation(.easeOut(duration: 0.16), value: isFolded)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(isFolded ? "Show quota rules" : "Hide quota rules")
    }
}

/// One product's rules, and the captions under them.
private struct FooterRuleRow: View {
    let rule: FooterRule
    let inlineTodayText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.footerCaptionSpacing) {
            HStack(spacing: PanelMetrics.footerWindowSpacing) {
                ForEach(rule.windows.indices, id: \.self) { index in
                    UsageMeter(
                        fill: rule.windows[index].fill,
                        ink: NotchPalette.ink(for: rule.agent)
                    )
                }
            }
            .frame(height: PanelMetrics.footerRuleHeight)

            if let inlineTodayText {
                // Today's tokens are already on this caption, so there is no
                // totals line below to carry the disclosure — and adding one
                // would spend exactly the height folding is meant to save. It
                // rides this line instead.
                QuotaFoldLine { FooterCaption(inlineTodayText) }
            } else {
                HStack(spacing: PanelMetrics.footerWindowSpacing) {
                    ForEach(rule.windows.indices, id: \.self) { index in
                        FooterCaption(rule.windows[index].caption)
                    }
                }
            }
        }
    }
}

/// The footer's 11pt caption, which every line down here uses.
private struct FooterCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .light))
            .foregroundStyle(NotchPalette.label)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
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

private struct SessionRowContent: View {
    @Environment(\.sessionRowIsPressed) private var isPressed

    @EnvironmentObject private var store: MonitorStore

    let session: MonitoredSession
    let isHovered: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: PanelMetrics.sessionRowLineSpacing) {
                    SessionRowCaption(
                        session: session,
                        style: store.productAttribution,
                        showsAttribution: store.showsProductAttribution
                    )

                    SessionRowText(
                        text: session.title,
                        font: .systemFont(ofSize: 13, weight: .medium),
                        color: NotchPalette.sessionTitleDrawingColor,
                        lineHeight: PanelMetrics.sessionRowTitleHeight
                    )

                    if let preview = session.preview {
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

                SessionStatusControl(session: session, ground: ground)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, store.sessionRowPadding)
        }
        // Flush with the block's leading edge, so it reads as a mark beside the
        // row rather than as a fifth thing inside it. The block's margin widens
        // to `12` while the rail is drawn (`MonitorStore.sessionRowGutter`), so
        // the stroke lands on the same line as the matrix and the quota rules;
        // the row's text steps in behind it rather than moving with it. It runs
        // the height of that text — caption to last line — so it reads as the
        // row's own edge rather than as a tick beside its middle.
        .overlay(alignment: .leading) {
            if drawsRail {
                RoundedRectangle(
                    cornerRadius: PanelMetrics.sessionRowRailRadius,
                    style: .continuous
                )
                .fill(NotchPalette.ink(for: session.agent).on)
                .frame(
                    width: PanelMetrics.sessionRowRailWidth,
                    height: PanelMetrics.sessionRowRailHeight(
                        hasPreview: session.preview != nil
                    )
                )
            }
        }
        .contentShape(Rectangle())
        .frame(
            maxWidth: .infinity,
            minHeight: PanelMetrics.sessionRowHeight,
            maxHeight: PanelMetrics.sessionRowHeight
        )
    }

    /// The rail is drawn on the same terms as every other attribution: only
    /// while two products are connected and there is something to tell apart.
    private var drawsRail: Bool { store.showsSessionRowRail }

    private var sweepsBody: Bool { store.sweepsBody(for: session) }

    /// What the row is drawing behind its marks, so a tile can stay above it.
    private var ground: NotchPalette.SurfaceGround {
        if isPressed { return .rowPressed }
        if isHovered { return .rowHovered }
        return .black
    }

    private var backgroundColor: Color { ground.color }
}

private struct SessionStatusControl: View {
    @EnvironmentObject private var store: MonitorStore
    let session: MonitoredSession
    /// What the row is drawing behind this mark.
    var ground: NotchPalette.SurfaceGround = .black

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
        if let startedAt = store.elapsedStart(for: session) {
            reading(startedAt: startedAt, stoppedAt: nil)
        } else if session.showsSubagentBadge {
            // `dual-agent-design.md` §10: an expanded row's badge is always
            // neutral, whatever else is connected -- the row already names its
            // product on the caption above. One badge carrying the whole
            // count, with the ground saying whether any of them is stopped.
            SubagentBadgeView(badge: session.subagentBadge, tint: .neutral, ground: ground)
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
        return NotchPalette.restingInk.chipFill(over: ground)
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

/// The row's leading 11pt line: the Project, and — while two products are
/// connected — which product this one is.
///
/// The attribution costs horizontal space and what it costs comes out of the
/// Project text: `Claude Code ·` takes about 73 of the caption's 394. That is
/// accepted rather than overlooked. The caption is the least important line in
/// the row and it ends in a fade rather than an ellipsis, so losing its tail is
/// the cheapest thing on this surface to lose.
private struct SessionRowCaption: View {
    let session: MonitoredSession
    let style: ProductAttributionStyle
    let showsAttribution: Bool

    var body: some View {
        HStack(spacing: 6) {
            if showsAttribution, style == .badge {
                Text(session.agent.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchPalette.ink(for: session.agent).on)
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(NotchPalette.ink(for: session.agent).off)
                    )
                    .fixedSize()
            }

            caption
                .font(.system(size: 11, weight: .light))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        // The badge is a point taller than the text line, so the caption's own
        // height moves 14 -> 16 with it. The row height does not: the content
        // block absorbs it.
        .frame(
            height: showsAttribution && style == .badge
                ? PanelMetrics.sessionRowBadgeCaptionHeight
                : PanelMetrics.sessionRowCaptionHeight
        )
    }

    /// One `Text`, two runs: the product prefix and the Project.
    ///
    /// Concatenated rather than laid out side by side so the line still
    /// truncates as one string — the tail that goes is the Project's, which is
    /// what the attribution was always spending.
    private var caption: Text {
        let project = Text(session.projectName)
            .foregroundStyle(NotchPalette.label)
        guard showsAttribution, style.namesProductInCaption else {
            return project
        }
        return Text("\(session.agent.displayName) · ")
            .foregroundStyle(prefixColor) + project
    }

    /// Only `nameAndColour` tints, and it tints the product name alone.
    ///
    /// The prefix is the whole of what the colour is about: it says which
    /// product, and the Project beside it is the row's own subject rather than
    /// a second statement of that. Tinting the line entire made the Project
    /// read as part of the mark and cost the caption its ordinary grey.
    private var prefixColor: Color {
        style.tintsProductName
            ? NotchPalette.ink(for: session.agent).on
            : NotchPalette.label
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
