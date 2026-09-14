import AppKit
import Combine
import SwiftUI

/// The width being drawn by the window, rather than the store's destination.
/// Nil lets standalone onboarding specimens retain their chosen store width.
private struct OverlayBodyWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var overlayBodyWidth: CGFloat? {
        get { self[OverlayBodyWidthKey.self] }
        set { self[OverlayBodyWidthKey.self] = newValue }
    }
}

/// Keep the same live layout through the fade instead of asking SwiftUI to
/// retain a removed subtree with its old geometry. No work remains when shut.
@MainActor
final class OverlayBodyPresentation: ObservableObject {
    @Published private(set) var isMounted = false
    private let clock: any MonitorClock
    private var removal: Task<Void, Never>?
    private var revision = 0

    init(clock: any MonitorClock = SystemMonitorClock()) { self.clock = clock }

    deinit { removal?.cancel() }

    func setExpanded(_ expanded: Bool) {
        revision += 1
        removal?.cancel()
        removal = nil
        if expanded {
            isMounted = true
            return
        }
        guard isMounted else { return }
        let expectedRevision = revision
        let clock = clock
        removal = Task { [weak self] in
            guard !Task.isCancelled else { return }
            do { try await clock.sleep(seconds: PanelMotion.duration) }
            catch { return }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.revision == expectedRevision else { return }
                self.isMounted = false
                self.removal = nil
            }
        }
    }

    func cancel() {
        revision += 1
        removal?.cancel()
        removal = nil
        isMounted = false
    }
}

struct NotchOverlayView: View {
    @EnvironmentObject private var store: MonitorStore
    @StateObject private var bodyPresentation = OverlayBodyPresentation()

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
                        // `Privacy Mode`'s gesture (`cover-the-words.md` §5): anywhere
                        // that is not a row. The primary press that opens a covered panel
                        // is taken by the window in ``OverlayPanel/sendEvent(_:)``, since
                        // `acceptsFirstMouse` hit-tests a primary press before this runs.
                        .overlay {
                            SecondaryClickCatcher { store.togglePrivacyMode() }
                        }
                        // Rides the window's bottom edge while the window is shorter than the
                        // band, so a pill tucking into the top edge slides up and out rather than
                        // being cut off; zero in every other state.
                        .offset(y: min(0, proxy.size.height - store.compactHeight))

                    if (store.isExpanded || bodyPresentation.isMounted),
                       !store.expandsToPillOnly {
                        // One body or the other, swapped without a cross-fade: two bodies
                        // during the window resize is a full overlay render per frame
                        // (`AGENTS.md` §7). Height is ``MonitorStore/expandedContentHeight``.
                        Group {
                            if store.isShowingAbout {
                                AboutPanelContent()
                            } else {
                                ExpandedPanelContent()
                            }
                        }
                        .transaction { transaction in
                            if !store.isExpanded { transaction.animation = nil }
                        }
                        .opacity(store.isExpanded ? 1 : 0)
                        .animation(PanelMotion.animation, value: store.isExpanded)
                        .allowsHitTesting(store.isExpanded)
                        .accessibilityHidden(!store.isExpanded)
                    }
                }
                // The window is one shoulder wider each side for `PanelContour`'s curve. Content and hit
                // region sit inside, so shoulders pass clicks through to the menu bar.
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
            }
            // AppKit already animates these bounds. Resolve surface and
            // content together without a second SwiftUI geometry animation;
            // only the body's opacity has its own transition.
            .geometryGroup()
            .environment(\.overlayBodyWidth,
                         max(0, proxy.size.width - store.surfaceShoulderRadius * 2))
        }
        .clipped()
        .onChange(of: store.isExpanded, initial: true) { _, expanded in
            bodyPresentation.setExpanded(expanded)
        }
        .onDisappear { bodyPresentation.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(panelAccessibilityLabel)
    }

    private var panelAccessibilityLabel: String {
        // Today's spend, not a share: no share is drawn at rest (`quota-footer-v2.md` §4).
        let usage = store.footerToday.spokenText.lowercased()
        // Spoken, not "12:34", which VoiceOver reads as a time of day.
        let elapsed = store.spokenLongestElapsedText.map { ", longest running for \($0)" }
            ?? ""
        // The counts column names neither figure, so the meaning is spoken.
        let counts = store.spokenCollapsedCountsText ?? "nothing running"
        // The breathing dot is motion-only, so it is said here too (§10).
        let finished = store.spokenBuriedCompletionText.map { ", \($0)" } ?? ""
        // The status name is no longer drawn but is still spoken (`compact-view-v2.md` §7, §10).
        return "Notchline, \(counts), status "
            + "\(store.statusDisplayName)\(elapsed)\(finished), \(usage)"
    }
}

private struct PanelSurface: View {
    let shoulderRadius: CGFloat
    let bottomRadius: CGFloat
    /// See ``MonitorStore/drawsSurfaceOutline``. Static: `AGENTS.md` §7 bans anything that ticks.
    let drawsOutline: Bool

    var body: some View {
        let contour = PanelContour(
            shoulderRadius: shoulderRadius,
            bottomRadius: bottomRadius
        )

        contour
            .fill(.black)
            // Every edge but the top, which is the screen's: an open path from top-right to top-left.
            // Stroked at double width and clipped to the closed shape so the line lies wholly inside;
            // a centred stroke would lose half along the bottom bounds.
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
/// Two radii like the notch: upper fillets are true quarter circles (`0.5523` handle); lower
/// corners are continuous corners (``PanelMetrics/smoothCornerReach(radius:)``): ease in,
/// circular arc, ease out. At smoothing `0` they reduce to a quarter-circle cubic.
struct PanelContour: Shape {
    let shoulderRadius: CGFloat
    let bottomRadius: CGFloat
    /// Whether the path spans the top edge. `true` for filling and clipping; `false` gives the
    /// open path from top-right to top-left that the outline is stroked from.
    var spansTopEdge = true
    /// Exposed so the reduction to a circular corner can be asserted; the product uses the default.
    var bottomSmoothing = PanelMetrics.notchLowerCornerSmoothing

    func path(in rect: CGRect) -> Path {
        // Each side spends one shoulder plus one lower corner's *reach* (not radius). Clamping the
        // pair together keeps their ratio.
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
        // Each call draws its own straight run in, so the corner decides where the edge ends.
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
    /// Runs the straight edge into `vertex` and turns the corner there with a continuous curve,
    /// leaving the current point on the outgoing edge.
    ///
    /// Built in the frame of the perpendicular unit vectors `entering` and `leaving`: an ease-in
    /// cubic on the incoming edge, an arc of `90° × (1 - smoothing)`, and the mirrored ease-out,
    /// consuming ``PanelMetrics/smoothCornerReach(radius:)`` along each edge.
    mutating func addSmoothCorner(
        vertex: CGPoint,
        entering: CGVector,
        leaving: CGVector,
        radius: CGFloat,
        smoothing: CGFloat
    ) {
        // Written as steps `along` (incoming) and `across` (outgoing), so any orientation reads alike.
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
        // The arc keeps what smoothing leaves; each easing segment turns `psi`.
        let arc = (.pi / 2) * (1 - s)
        let psi = (.pi / 4) * s
        // The arc's chord is at 45° to both edges, so the along and across steps are equal.
        let chord = sin(arc / 2) * r * (2 as CGFloat).squareRoot()
        // Where the easing segment hands over to the arc, from its start on the edge.
        let approach = r * tan(psi / 2) * cos(psi)
        let drop = approach * tan(psi)
        // The rest of the reach, split `2:1` over the control points so curvature rises evenly.
        let spread = (reach - chord - approach - drop) / 3
        let lead = 2 * spread
        // A cubic fits an arc of `theta` with `4/3 · tan(theta/4)` radii handles.
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
        // The arc's tangents run at `psi` to each edge, so its handles lie on those.
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
            // One leading group: the mark at `12` and the totals at `32.6` stay put whether open or shut
            // (`colour-v2.md` §3).
            CompactLeadingGroup()

            // Only the pill has a middle; the notched bar would need a `102` pt wing
            // (`compact-view-v2.md` §5.2).
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

            // The gear and About mark are one trailing group
            // (``PanelMetrics/expandedTrailingSideWidth``). The peek (`cover-the-words.md` §7) stands
            // outside it so ``PanelMetrics/restingExpandedWidth`` does not grow, mounted on
            // ``MonitorStore/keepsPeekRoom`` so toggling `Privacy Mode` moves nothing.
            if store.keepsPeekRoom {
                PeekButton()
            }

            if store.isExpanded {
                AboutButton()
                SettingsButton()
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }

    private var horizontalPadding: CGFloat {
        PanelMetrics.expandedHorizontalPadding
    }
}

/// The collapsed surface's leading wing: one aggregate mark, and the counts.
///
/// Nothing here is per product (`compact-view-v2.md` §1): the mark draws the most urgent status
/// in the user's ink and the numerals count every row and subagent.
private struct CompactLeadingGroup: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        // Absent on a notched bar with nothing to say; the other forms keep the mark so the control
        // keeps its position.
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
                    // The pill and band hold room for two digits; the notched bar hugs what it draws.
                    reservesTwoDigits: store.geometry == .noNotch || store.isExpanded
                )
            }
            .transition(Self.wingFade)
        }
    }

    /// Fades in and out so that, with `Hide Notchline` on, the mark is not drawn over the cut-out
    /// while the panel edge clears it.
    private static let wingFade = AnyTransition.asymmetric(
        insertion: .opacity.animation(PanelMotion.fade(isArriving: true)),
        removal: .opacity.animation(PanelMotion.fade(isArriving: false))
    )
}

/// The collapsed surface's trailing wing: the elapsed reading.
///
/// Absent when no turn is timed, so a notched display shows no empty second cut-out. Subagent
/// counts live in the leading wing (`compact-view-v2.md` §3).
struct CompactTrailingSlot: View {
    @EnvironmentObject private var store: MonitorStore

    /// The box the panel edge opens, held so the write that changes it knows which way it goes.
    ///
    /// Framed to `PanelMetrics.drawnTrailingReadingWidth`, which composes every collapsed width, so
    /// box and edge move on one curve. Nil until the first application, which places it.
    @State private var boxWidth: CGFloat?

    var body: some View {
        HStack(spacing: 0) {
            if drawsFinishedDot {
                FinishedTurnDot()
                    .padding(
                        .trailing,
                        store.compactTimerText == nil
                            ? 0
                            : PanelMetrics.buriedFinishDotSpacing
                    )
                    .transition(Self.markFade)
            }
            // Always running's bare figure, neutral: it belongs to no one product. The `.clear`
            // ``ReadingGround`` keeps the billed padding; a finished turn freezes the figure and draws
            // the dot (``CompactTrailingReading/drawsFinishedDot``).
            if let span = store.compactReadingSpan {
                ReadingGround(fill: .clear) {
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
        // Keyed on what is present, not the width: gaining a digit must not fade.
        .animation(PanelMotion.animation, value: presence)
        .onChange(of: targetWidth, initial: true) { previous, width in
            // The first application builds the slot: take the width, don't animate.
            guard boxWidth != nil, previous != width else {
                boxWidth = width
                return
            }
            withAnimation(PanelMotion.slot(isOpening: width > previous)) {
                boxWidth = width
            }
        }
    }

    private var targetWidth: CGFloat {
        store.compactDrawnTrailingReadingWidth
    }

    /// Read from the value the width is composed from, so drawing and billing agree.
    private var drawsFinishedDot: Bool {
        store.compactTrailingReading.drawsFinishedDot
    }

    private var presence: [Bool] {
        [store.compactReadingSpan == nil, drawsFinishedDot]
    }

    /// Fades so a reading is not drawn over the cut-out while the panel edge clears it.
    private static let markFade = AnyTransition.asymmetric(
        insertion: .opacity.animation(PanelMotion.fade(isArriving: true)),
        removal: .opacity.animation(PanelMotion.fade(isArriving: false))
    )
}

/// Hold to read your own list, and let go to put it back (`cover-the-words.md` §7).
///
/// - A hold cannot be left on; ``MonitorStore/isPeeking`` also clears when the panel closes.
/// - `DragGesture(minimumDistance: 0)`, not a `Button`, which fires on release and would flash
///   uncovered text. Accessibility activation latches (``MonitorStore/togglePeek()``).
/// - The box stays while ``MonitorStore/keepsPeekRoom``; the mode only draws the bars. Empty,
///   it takes no press, draws no hover fill, and is hidden from accessibility.
private struct PeekButton: View {
    @EnvironmentObject private var store: MonitorStore

    @State private var isHovered = false

    private var size: CGFloat {
        PanelMetrics.settingsButtonSize(compactHeight: store.compactHeight)
    }

    private var isDrawn: Bool { store.hasCoveredRows }

    var body: some View {
        PeekGlyph(
            ink: store.isPeeking ? Color.white : Color.white.opacity(0.55),
            isDrawn: isDrawn
        )
            .frame(width: size, height: size)
            // The fill needs hover and a drawn control, so it never outlives the bars.
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(isHovered && isDrawn ? 0.12 : 0))
            )
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(PanelMotion.fade(isArriving: isDrawn), value: isDrawn)
            .contentShape(Rectangle())
            // Tracked while empty too, so a mode switched on under a resting pointer is already lit.
            .onHover { isHovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in store.beginPeek() }
                    .onEnded { _ in store.endPeek() },
                // An empty box takes no press, so presses reach the band underneath.
                including: isDrawn ? .all : .none
            )
            .accessibilityElement()
            .accessibilityHidden(!isDrawn)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(
                store.isPeeking
                    ? "Cover the rows again"
                    : "Uncover the rows while you read them"
            )
            .accessibilityAction { store.togglePeek() }
            .help(
                "Hold to read the covered rows, and let go to cover them "
                    + "again. Privacy Mode stays on."
            )
    }
}

/// Three pills in the covers' own proportions, at glyph size.
///
/// Based on ``PanelMetrics/coverBarProjectLength`` and neighbours but spread apart: literal
/// `64 : 160 : 224` reads as a dot beside a line at `13` pt.
private struct PeekGlyph: View {
    let ink: Color
    /// Whether the covers are on; `false` is an empty box, not an absent one (``PeekButton``).
    let isDrawn: Bool

    private static let widths: [CGFloat] = [0.46, 0.77, 1]
    private static let barHeight: CGFloat = 1.8
    private static let gap: CGFloat = 2.7

    /// Delay between bars, going on and coming off; read as one sweep, shorter coming off.
    private static let stagger: TimeInterval = 0.05
    private static let unstagger: TimeInterval = 0.035

    var body: some View {
        let span = PanelMetrics.bandControlGlyphSize
        VStack(alignment: .leading, spacing: Self.gap) {
            ForEach(Array(Self.widths.enumerated()), id: \.offset) { index, fraction in
                RoundedRectangle(
                    cornerRadius: Self.barHeight / 2,
                    style: .continuous
                )
                .fill(ink)
                .frame(width: span * fraction, height: Self.barHeight)
                // Scaled from the leading edge, not resized, so nothing beside the glyph re-lays out
                // (as ``FoldSeamRule``).
                .scaleEffect(x: isDrawn ? 1 : 0, anchor: .leading)
                .opacity(isDrawn ? 1 : 0)
                .animation(Self.draw(isDrawn: isDrawn, index: index), value: isDrawn)
            }
        }
        .frame(width: span, alignment: .leading)
    }

    /// One bar going on or coming off: ``PanelMotion/fade(isArriving:)`` dealt a bar at a time,
    /// short to long on, reversed off so the long bar goes first. The rows uncover immediately;
    /// nothing waits for this.
    private static func draw(isDrawn: Bool, index: Int) -> Animation {
        let order = Double(isDrawn ? index : widths.count - 1 - index)
        return PanelMotion.fade(isArriving: isDrawn)
            .delay((isDrawn ? stagger : unstagger) * order)
    }
}

/// The mark, which puts the app itself on the panel in place of the work.
///
/// The brand package's menu bar template, tinted so its alpha ramp follows the control's ink.
/// Drawn at ``PanelMetrics/bandControlGlyphSize`` (the gear's), not the native `16`, from a
/// `13` resample in the catalogue so the `0.84` pt gap stays sharp.
private struct AboutButton: View {
    @EnvironmentObject private var store: MonitorStore

    @State private var isHovered = false

    private var size: CGFloat {
        PanelMetrics.settingsButtonSize(compactHeight: store.compactHeight)
    }

    /// A found version nobody has read yet; never while About is the panel (§2).
    private var dotVersion: UpdateVersion? {
        store.isShowingAbout ? nil : AppUpdater.shared.status.dot
    }

    var body: some View {
        Button(action: store.toggleAbout) {
            Image("NotchlineMark")
                .renderingMode(.template)
                .interpolation(.high)
                .resizable()
                .frame(
                    width: PanelMetrics.bandControlGlyphSize,
                    height: PanelMetrics.bandControlGlyphSize
                )
                // In the terrace's empty corner, in its own still ink: the pointer brightens the
                // mark, never the dot.
                .overlay(alignment: .topLeading) {
                    if dotVersion != nil {
                        Circle()
                            .fill(NotchPalette.finishedDot)
                            .frame(
                                width: PanelMetrics.aboutUpdateDotDiameter,
                                height: PanelMetrics.aboutUpdateDotDiameter
                            )
                            .offset(
                                x: PanelMetrics.aboutUpdateDotCentre - PanelMetrics.aboutUpdateDotDiameter / 2,
                                y: PanelMetrics.aboutUpdateDotCentre - PanelMetrics.aboutUpdateDotDiameter / 2
                            )
                    }
                }
                .frame(width: size, height: size)
                // Fill answers to hover; ink answers to hover and on-state. An on control takes no ground.
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.12 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            isHovered || store.isShowingAbout
                ? NotchPalette.sessionTitle
                : NotchPalette.label
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: store.isShowingAbout)
        .accessibilityLabel("About Notchline")
        .accessibilityValue(
            store.isShowingAbout
                ? "Shown"
                : dotVersion.map { "\($0.name) available" } ?? "Hidden"
        )
        .accessibilityAddTraits(store.isShowingAbout ? .isSelected : [])
        .help(
            store.isShowingAbout
                ? "Back to sessions"
                : dotVersion.map { "About Notchline — \($0.name) is waiting" } ?? "About Notchline"
        )
    }
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
            // Not `openSettings()` alone: the window would come up behind the active app and on the
            // display it last closed on. See ``SettingsWindowPresenter``.
            SettingsWindowPresenter.present { openSettings() }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(
                    size: PanelMetrics.bandControlGlyphSize,
                    weight: .regular
                ))
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

/// The panel below the band: the live list, the queue, the footer, and the band's closing rule.
///
/// The rule is drawn only while the list does not lead with a block heading, which brings its
/// own hairline `8` lower (`panel-v2.md` §3.4,
/// ``PanelMetrics/leadingProductGroupHeaderHeight``).
private struct ExpandedPanelContent: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        VStack(spacing: 0) {
            ActiveSessionList()
            RecentSessionSection()
            ExpandedPanelFooter()
        }
        .foregroundStyle(.white)
        .overlay(alignment: .top) {
            if !store.listLeadsWithABlockHeading {
                Rectangle()
                    .fill(NotchPalette.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, PanelMetrics.expandedHorizontalPadding)
            }
        }
    }
}

/// The panel with the app on it instead of the work: lockup, version, licence, one control.
///
/// Replaces the body, so its height is a constant (``PanelMetrics/aboutPanelHeight``).
/// Internal so its laid-out height can be tested against the metric.
struct AboutPanelContent: View {
    var body: some View {
        VStack(spacing: 0) {
            // The dark-ground file: its ramp is blended opaque ink (`#DEE8E0` to `#424743`); the
            // transparent file's thinned `#1B1F1C` is invisible on black. Its ground is `#000000`,
            // matching `PanelSurface`.
            Image("NotchlineLockup")
                .resizable()
                .interpolation(.high)
                .frame(
                    width: PanelMetrics.aboutLockupWidth,
                    height: PanelMetrics.aboutLockupHeight
                )
                .accessibilityLabel("Notchline")

            AboutVersionLine()
                .padding(.top, PanelMetrics.aboutLockupTextGap)

            if let notice = AppVersion.copyrightNotice {
                Text(notice)
                    .font(Font(PanelMetrics.captionFont))
                    .foregroundStyle(NotchPalette.label)
                    .padding(.top, PanelMetrics.aboutTextLineGap)
            }

            AboutRepositoryLink()
                .padding(.top, PanelMetrics.aboutTextLineGap)

            AboutUpdateControl()
                .padding(.top, PanelMetrics.aboutTextControlGap)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, PanelMetrics.aboutTopMargin)
        .padding(.bottom, PanelMetrics.aboutBottomMargin)
        .padding(.horizontal, PanelMetrics.expandedHorizontalPadding)
        .frame(height: PanelMetrics.aboutPanelHeight, alignment: .top)
        .overlay(alignment: .top) {
            // Unconditional here: this body has no block heading (``ExpandedPanelContent``).
            Rectangle()
                .fill(NotchPalette.hairline)
                .frame(height: 1)
                .padding(.horizontal, PanelMetrics.expandedHorizontalPadding)
        }
    }
}

/// The version line (`updates-on-the-notch.md` §3): this build, and while a version is waiting,
/// an arrow to it in the title's ink.
private struct AboutVersionLine: View {
    var body: some View {
        if let summary = AppVersion.summary {
            let target = AppUpdater.shared.status.version
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(summary)
                    .foregroundStyle(NotchPalette.reading)
                if let target {
                    Text("  →  \(target.name) (\(target.build))")
                        .foregroundStyle(NotchPalette.sessionTitle)
                }
            }
            .font(Font(PanelMetrics.captionFont))
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                (AppVersion.spokenSummary ?? summary)
                    + (target.map { ", updating to \($0.name), build \($0.build)" } ?? "")
            )
        }
    }
}

/// The About panel's control row: whatever the update needs next (§3). The one updater draws it
/// here and in Settings (rule 12); the panel's height never changes (rule 5).
private struct AboutUpdateControl: View {
    var body: some View {
        let row = AboutUpdateRow(AppUpdater.shared.status.flow)
        HStack(spacing: PanelMetrics.aboutUpdateRowSpacing) {
            if row.lead != nil || row.gloss != nil || row.meter != nil {
                AboutUpdateReading(row: row)
            }
            ForEach(row.controls, id: \.label) { spec in
                AboutUpdateButton(spec: spec)
            }
        }
        .frame(height: PanelMetrics.answerRowHeight)
    }
}

/// A reading in Light 13: the lead in `reading`, the gloss in `label`, and a still meter between
/// them while there is progress to show. Nothing on it spins (rule 6).
private struct AboutUpdateReading: View {
    let row: AboutUpdateRow

    var body: some View {
        HStack(alignment: .center, spacing: row.meter == nil ? 0 : PanelMetrics.aboutUpdateRowSpacing) {
            if let lead = row.lead {
                Text(lead)
                    .foregroundStyle(NotchPalette.reading)
            }
            if let meter = row.meter {
                UpdateMeter(fraction: meter)
            }
            if let gloss = row.gloss {
                Text(gloss)
                    .foregroundStyle(NotchPalette.label)
            }
        }
        .font(Font(PanelMetrics.requestControlFont))
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [row.lead, row.gloss]
                .compactMap { $0?.trimmingCharacters(in: CharacterSet(charactersIn: " ·")) }
                .joined(separator: ", ")
        )
    }
}

/// The download meter (`updates-on-the-notch.md` §3): a `120 × 3` capsule, track `hairline`, fill `themeInk.on`.
private struct UpdateMeter: View {
    let fraction: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(NotchPalette.hairline)
            Capsule()
                .fill(NotchPalette.themeInk.on)
                .frame(width: PanelMetrics.updateMeterFill(fraction))
        }
        .frame(width: PanelMetrics.updateMeterWidth, height: PanelMetrics.updateMeterHeight)
        .accessibilityHidden(true)
    }
}

/// One of §3's weights. A control with no action takes no press and dims its label (02).
private struct AboutUpdateButton: View {
    let spec: AboutUpdateControlSpec

    @State private var isHovered = false

    private var isLive: Bool { spec.action != nil }

    var body: some View {
        Button {
            if let action = spec.action {
                AppUpdater.shared.perform(action)
            }
        } label: {
            Text(spec.label)
                .font(Font(PanelMetrics.requestControlFont))
                .foregroundStyle(ink)
                .fixedSize()
                .frame(width: spec.widthOf.map(PanelMetrics.drawnAnswerControlWidth))
                .padding(.horizontal, spec.widthOf == nil ? PanelMetrics.controlHorizontalPadding : 0)
                .frame(height: PanelMetrics.answerRowHeight)
                .background(
                    RoundedRectangle(
                        cornerRadius: PanelMetrics.controlCornerRadius,
                        style: .continuous
                    )
                    .fill(ground)
                )
                .overlay { if isLive { PointingHandCursor() } }
                .contentShape(Rectangle())
                .onHover { isHovered = $0 && isLive }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isLive)
        .animation(
            .easeOut(duration: NotchPalette.RowEmphasis.controlHoverDuration),
            value: isHovered
        )
        .accessibilityLabel(spec.label.replacingOccurrences(of: " ↗", with: ""))
    }

    private var ink: Color {
        switch spec.weight {
        case .bare: isHovered ? NotchPalette.themeInk.on : NotchPalette.label
        case .quiet: isLive ? NotchPalette.themeInk.on : NotchPalette.label
        case .ground: NotchPalette.onBrightGround
        }
    }

    private var ground: Color {
        switch spec.weight {
        case .bare:
            isHovered
                ? NotchPalette.themeInk.on.opacity(NotchPalette.RowEmphasis.plainControlRestFillOpacity)
                : .clear
        case .quiet:
            NotchPalette.themeInk.on.opacity(
                isHovered
                    ? NotchPalette.RowEmphasis.plainControlHoverFillOpacity
                    : NotchPalette.RowEmphasis.plainControlRestFillOpacity
            )
        case .ground:
            isHovered ? Color.white : NotchPalette.brightGround
        }
    }
}

/// The complete address is both the label and the destination.
private struct AboutRepositoryLink: View {
    @State private var isHovered = false

    var body: some View {
        Link(destination: AppVersion.repositoryURL) {
            HStack(spacing: 6) {
                Image("GitHubMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                Text(AppVersion.repositoryURL.absoluteString)
                    .font(Font(PanelMetrics.captionFont))
            }
            .foregroundStyle(isHovered ? NotchPalette.themeInk.on : NotchPalette.reading)
            .frame(height: PanelMetrics.aboutLinkHeight)
            .contentShape(Rectangle())
            .overlay(PointingHandCursor())
            .onHover { isHovered = $0 }
        }
        .buttonStyle(.plain)
    }
}

/// Extra width for a scrolling list's `ScrollView`, so content still lands on the panel's
/// margin.
///
/// `ScrollView` shrinks its content's width for a scroller once content is taller than the
/// viewport (with "Show scroll bars" `Always`), even under `.scrollIndicators(.hidden)`. Gated on
/// `isScrolling`: a list that fits already gets the full width and would be pushed past the crop.
private func legacyScrollerGutter(isScrolling: Bool) -> CGFloat {
    guard isScrolling, NSScroller.preferredScrollerStyle == .legacy else {
        return 0
    }
    return NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
}

/// The live session list: at least one row's viewport, normally at most three, scrolling past
/// that; an open question taller than three rows enlarges it to keep its answer footer visible
/// (§4.1). Scrolls independently of ``RecentSessionSection``. Internal so its laid-out height
/// can be tested against the panel's.
struct ActiveSessionList: View {
    @EnvironmentObject private var store: MonitorStore
    @Environment(\.overlayBodyWidth) private var overlayBodyWidth

    @State private var scrollOffset: CGFloat = 0

    /// The full lane, rail included.
    private var laneWidth: CGFloat {
        PanelMetrics.sessionViewportWidth(panelWidth: overlayBodyWidth ?? store.currentPanelSize.width)
    }

    /// The rows' width once the rail has taken its lane.
    private var viewportWidth: CGFloat {
        PanelMetrics.sessionViewportWidth(
            panelWidth: overlayBodyWidth ?? store.currentPanelSize.width,
            isScrolling: isScrolling
        )
    }

    private var contentHeight: CGFloat { store.sessionListContentHeight }

    /// Taken from the store, the same arithmetic the panel was sized by.
    ///
    /// Not the bare ``PanelMetrics/sessionViewportCap``: an open question's row can reach `400`,
    /// past the `240` cap, and the window is sized from `max(cap, openRowHeight)`
    /// (`answer-in-notch.md` §4.1). Using the constant clipped the last option under the footer.
    private var viewportHeight: CGFloat { store.sessionViewportHeight }

    /// Against the viewport, not the cap: a lone open question fills its room and has no travel.
    private var isScrolling: Bool { contentHeight > viewportHeight }

    /// Whether the two badge lines are drawn: grouped and closed (an open row un-pins everything,
    /// §4.3 rule 06).
    private var showsTrails: Bool {
        store.openRowID == nil && store.groupsSessionsByProduct && !store.sessions.isEmpty
    }

    /// Where every heading stands for the current offset, from the heights the panel was sized by.
    private var trailLayout: ProductTrailLayout {
        let groups = store.sessionGroups
        return ProductTrailLayout.laidOut(
            groups: groups,
            badgeWidths: groups.map { PanelMetrics.productBadgeWidth($0.agent.displayName) },
            offset: scrollOffset,
            viewportHeight: viewportHeight,
            contentHeight: contentHeight
        )
    }

    var body: some View {
        ScrollViewReader { list in
            ScrollView(.vertical) {
                // Headings are drawn by ``ProductTrails`` over the list; the flow keeps a blank slot of each
                // one's height (`expanded-panel-v2.md` §4.6). While a row is open they go back into the flow:
                // a pinned header would cover the open row's ``OpenRowChevron``.
                LazyVStack(spacing: 0) {
                    // The apology scrolls with the list rather than pinning.
                    if store.sessions.isEmpty {
                        emptyListLabel
                    }

                    // `Group by product` off: the flat list, each row with its own chip.
                    let groups = store.sessionGroups
                    if groups.isEmpty {
                        rows(store.sessions)
                    } else {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            headingSlot(for: group, isLeading: index == 0)
                            rows(group.sessions)
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
            // The extra width is `ScrollView`'s (``legacyScrollerGutter``); clipping pins the visible
            // region to the panel's margin.
            .frame(width: viewportWidth, alignment: .leading)
            .clipped()
            .overlay(alignment: .topLeading) {
                if showsTrails {
                    ProductTrails(
                        groups: store.sessionGroups,
                        layout: trailLayout,
                        width: viewportWidth,
                        height: viewportHeight
                    ) { agent in
                        // A badge scrolls its block to the top; the slot's top is where the chip docks.
                        withAnimation(PanelMotion.slot(isOpening: true)) {
                            list.scrollTo(ProductHeadingSlotID(agent: agent), anchor: .top)
                        }
                    }
                }
            }
        }
        // The rail stops on the panel's inset; see ``PanelMetrics/scrollRailLane``.
        .frame(width: laneWidth, alignment: .leading)
        .overlay(alignment: .trailing) {
            ScrollRail(
                visibleHeight: viewportHeight,
                contentHeight: contentHeight,
                offset: scrollOffset
            )
            .padding(.trailing, PanelMetrics.sessionRowPadding)
        }
    }

    /// The scroll target for a heading's chip line. Its own type: the block's `AgentKind` already
    /// identifies the `ForEach` item, and a scroll target must name the line, not the item.
    private struct ProductHeadingSlotID: Hashable {
        let agent: AgentKind
    }

    /// A heading's slot in the flow. Closed, the overlay draws the heading and the slot keeps the
    /// slack plus the chip's line, which carries the block's scroll identity. Open, the bar stands here.
    @ViewBuilder
    private func headingSlot(
        for group: MonitorAggregation.SessionGroup,
        isLeading: Bool
    ) -> some View {
        if store.openRowID != nil {
            ProductGroupHeader(group: group, isLeading: isLeading)
        } else {
            // Two siblings with their own identity on the chip's line: wrapped in a `VStack` or
            // given the `ForEach` item's `id`, `scrollTo(_:anchor: .top)` lands on the slack and
            // the chip is `16` short.
            if !isLeading {
                Color.clear.frame(height: PanelMetrics.productGroupHeaderSlack)
            }
            Color.clear
                .frame(height: PanelMetrics.productTrailHeight)
                .id(ProductHeadingSlotID(agent: group.agent))
        }
    }

    @ViewBuilder
    private func rows(_ sessions: [MonitoredSession]) -> some View {
        ForEach(sessions) { session in
            if store.openRowID == session.id {
                // No `.id()` on either branch: the same id on both made SwiftUI treat closed and open as one
                // view, and the panel resized for a row that stayed shut.
                OpenRow(session: session)
            } else {
                // One open row is the subject (§8.2); every other row drops to `45%`.
                SessionRow(session: session)
                    .opacity(store.openRowID == nil ? 1 : 0.45)
            }
        }
    }

    private var emptyListLabel: some View {
        Text(store.emptyListMessage)
            .font(.system(size: 13, weight: .light))
            .foregroundStyle(NotchPalette.label)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: PanelMetrics.thinExpandedBodyHeight)
    }
}

/// The Recent queue: the seam, and the retired rows behind it while open.
///
/// Internal so the first-run window can draw one on its own (`OnboardingAnatomy.swift`).
struct RecentSessionSection: View {
    @EnvironmentObject private var store: MonitorStore
    @Environment(\.overlayBodyWidth) private var overlayBodyWidth

    @State private var scrollOffset: CGFloat = 0

    private var laneWidth: CGFloat {
        PanelMetrics.sessionViewportWidth(panelWidth: overlayBodyWidth ?? store.currentPanelSize.width)
    }

    private var viewportWidth: CGFloat {
        PanelMetrics.sessionViewportWidth(
            panelWidth: overlayBodyWidth ?? store.currentPanelSize.width,
            isScrolling: isScrolling
        )
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
                    .frame(width: laneWidth, alignment: .leading)
                    .overlay(alignment: .trailing) {
                        ScrollRail(
                            visibleHeight: viewportHeight,
                            contentHeight: contentHeight,
                            offset: scrollOffset
                        )
                        .padding(.trailing, PanelMetrics.sessionRowPadding)
                    }
                }
            }
        }
    }
}

/// The quota footer: one number, a control, and the table behind it.
///
/// Closed height is always `22` (`quota-footer-v2.md` §2). No low-value threshold (§4); only
/// opening the table or the Settings product choice (§13) changes its height.
private struct ExpandedPanelFooter: View {
    @EnvironmentObject private var store: MonitorStore
    @Environment(\.overlayBodyWidth) private var overlayBodyWidth

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: PanelMetrics.footerRuleSpacing) {
            if store.showsQuotaFooter {
                if store.showsQuotaFoldControl {
                    spendLine
                } else {
                    totalLine
                }

                if store.showsQuotaTable {
                    table
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PanelMetrics.expandedHorizontalPadding)
                }
            }
        }
        .padding(.bottom, store.showsQuotaTable
            ? PanelMetrics.footerCaptionBottomMargin
            : PanelMetrics.footerBottomMargin)
        .frame(maxWidth: .infinity)
        .frame(height: store.expandedFooterHeight, alignment: .top)
    }

    /// The spend line when every product is out of the table: not a button, and drawn where the
    /// spend line is so the total does not move.
    private var totalLine: some View {
        FooterSpendLineContent(isExpanded: false, isHovered: false, showsControl: false)
            .frame(width: PanelMetrics.sessionViewportWidth(panelWidth: overlayBodyWidth ?? store.currentPanelSize.width))
            .frame(height: PanelMetrics.recentSeamHeight)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Today, \(store.footerToday.spokenText)")
    }

    /// The footer's first line: the reading and the disclosure. Same `32` pt bar and hit target as
    /// the Recent seam; the whole line toggles the table.
    private var spendLine: some View {
        Button {
            store.toggleQuotaTable()
        } label: {
            FooterSpendLineContent(
                isExpanded: store.showsQuotaTable,
                isHovered: isHovered
            )
        }
        .buttonStyle(SessionRowButtonStyle())
        .frame(width: PanelMetrics.sessionViewportWidth(panelWidth: overlayBodyWidth ?? store.currentPanelSize.width))
        .frame(height: PanelMetrics.recentSeamHeight)
        // Claims the panel width so the line stays centred whether or not the table is shown.
        .frame(maxWidth: .infinity)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today, \(store.footerToday.spokenText)")
        .accessibilityValue(store.showsQuotaTable ? "Expanded" : "Collapsed")
        .accessibilityAddTraits(.isButton)
    }

    /// Two levels: the product and its spend today, then each window on a line. Indent carries the
    /// level; no box, rule or divider (§5).
    private var table: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.footerCaptionHeight) {
            ForEach(store.footerRules) { rule in
                FooterProductGroup(rule: rule)
            }
        }
    }
}

/// The spend line's drawing: the Recent seam's shape with a reading and a chevron.
private struct FooterSpendLineContent: View {
    @EnvironmentObject private var store: MonitorStore

    let isExpanded: Bool
    let isHovered: Bool
    var showsControl = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)

            HStack(spacing: 8) {
                FooterReading(store.footerToday)

                FoldSeamRule(isVisible: isExpanded)

                if showsControl {
                    QuotaFoldChevron(isExpanded: isExpanded, isHovered: isHovered)
                }
            }
            .padding(.horizontal, PanelMetrics.sessionRowPadding)
        }
        .contentShape(Rectangle())
        .frame(
            maxWidth: .infinity,
            minHeight: PanelMetrics.recentSeamHeight,
            maxHeight: PanelMetrics.recentSeamHeight
        )
    }
}

private struct FooterProductGroup: View {
    let rule: FooterRule

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.footerCaptionSpacing) {
            outerRow

            // Identity by index: windows with the same label, share and timer would collide otherwise.
            ForEach(rule.windows.indices, id: \.self) { index in
                FooterWindowRow(window: rule.windows[index])
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The product and its spend today, with nothing drawn between them.
    private var outerRow: some View {
        HStack(spacing: 0) {
            FooterCaption(
                rule.agent.displayName,
                ink: NotchPalette.reading,
                weight: .medium
            )

            Spacer(minLength: PanelMetrics.footerColumnGutter)

            FooterReading(rule.today)
        }
        .frame(height: PanelMetrics.footerCaptionHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rule.agent.displayName), \(rule.today.spokenText)")
    }
}

/// One window's line: name at `24`, share right-aligned at `184`, countdown right-aligned at
/// the spend's edge. The share's figure is the one bright thing; see ``ShareReading``.
private struct FooterWindowRow: View {
    let window: FooterWindow

    var body: some View {
        HStack(spacing: 0) {
            // Name and share are one box, so a long name eats the gutter rather than hitting the figure.
            HStack(spacing: 0) {
                // Capped and truncated: a model-named window can be any width; the figure must stay.
                FooterCaption(window.label)
                    .frame(
                        maxWidth: PanelMetrics.footerWindowColumnWidth,
                        alignment: .leading
                    )
                Spacer(minLength: PanelMetrics.footerColumnGutter)
                FooterReading(window.share)
            }
            .frame(
                width: PanelMetrics.footerShareTrailingEdge
                    - PanelMetrics.footerWindowIndent
            )

            Spacer(minLength: PanelMetrics.footerColumnGutter)
            FooterCaption(window.timer)
        }
        .padding(.leading, PanelMetrics.footerWindowIndent)
        .frame(height: PanelMetrics.footerCaptionHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLine)
    }

    /// Spoken line, including the absolute reset the column drops (§7).
    private var spokenLine: String {
        let head = window.label.isEmpty ? "" : "\(window.label), "
        return "\(head)\(window.share.text), \(window.spokenTimer)"
    }
}

/// The quota table's disclosure: one glyph rotated 180°, pointing down while shut.
///
/// A drawing only; the spend line is the hit target and hover source.
private struct QuotaFoldChevron: View {
    let isExpanded: Bool
    let isHovered: Bool

    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(isHovered ? NotchPalette.sessionTitle : NotchPalette.label)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .frame(
                width: PanelMetrics.quotaFoldControlSize,
                height: PanelMetrics.quotaFoldControlSize
            )
            .animation(.easeOut(duration: 0.16), value: isExpanded)
    }
}

/// The footer's 11pt caption. Hugs its text; each column's edge is placed by its line.
private struct FooterCaption: View {
    let text: String
    let ink: Color
    let weight: Font.Weight

    init(
        _ text: String,
        ink: Color = NotchPalette.label,
        weight: Font.Weight = .light
    ) {
        self.text = text
        self.ink = ink
        self.weight = weight
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: weight))
            .foregroundStyle(ink)
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A footer reading: figure in `#C7C7CC`, unit in `#7C7C80`. The footer's whole ink rule.
///
/// A `--` takes the figure's ink (`quota-footer-v2.md` §8.3).
private struct FooterReading: View {
    private let figure: String
    private let unit: String
    private let spokenText: String

    init(_ reading: SpendReading) {
        figure = reading.figure
        unit = reading.unit
        spokenText = reading.spokenText
    }

    init(_ reading: ShareReading) {
        figure = reading.figure
        unit = reading.unit
        spokenText = reading.spokenText
    }

    var body: some View {
        Text(runs)
            .font(.system(size: 11, weight: .light))
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(spokenText)
    }

    /// One string with two runs, so figure and unit are typeset as one line.
    private var runs: AttributedString {
        var figure = AttributedString(self.figure)
        figure.foregroundColor = NotchPalette.reading
        var unit = AttributedString(" " + self.unit)
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
        // On every row; the catcher claims only a secondary press. See ``MonitorStore/dismiss(_:)``.
        .overlay {
            SecondaryClickCatcher { store.dismiss(session) }
        }
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityText)
        // Secondary click has no keyboard or VoiceOver form, so offer it as an action.
        .accessibilityActions {
            Button("Remove this row") { store.dismiss(session) }
        }
    }

    private var accessibilityText: String {
        let preview = ", current content: \(store.previewLine(for: session))"
        // Spoken form: VoiceOver reads a drawn "12:34" as a clock time.
        let elapsed = store.spokenElapsedText(for: session).map { ", running for \($0)" }
            ?? ""
        // Drawn as one badge whose ground flips; spoken, it must say what it counts and that it waits.
        let subagents = session.spokenSubagentSummary.map { ", \($0)" } ?? ""
        // A finished row's duration, spoken as a length in the past tense.
        let took = store.spokenFinishedElapsedText(for: session)
            .map { ", took \($0)" } ?? ""
        // A timed row draws no badge, so a blocked subagent still needs a word.
        let blocked = session.status.keepsTiming && session.subagentsAwaitingApproval
            ? ", a subagent is waiting for approval"
            : ""
        // Product is named even where no chip is drawn: a row-by-row reader has no block header.
        // A covered run is spoken as covered, not read out (`cover-the-words.md` §9).
        guard !store.coversWords(of: session) else {
            return "\(session.agent.displayName), covered, "
                + "\(session.status.displayName)\(elapsed)\(took)\(subagents)\(blocked)"
        }
        return "\(session.agent.displayName), \(session.projectName), \(session.title), "
            + "\(session.status.displayName)\(elapsed)\(took)\(subagents)\(blocked)\(preview)"
    }
}

/// A row with its request open: the caption and title, the body, and the answers.
///
/// Internal like ``RecentSessionSection``, so the first-run window can draw one on its own
/// (`OnboardingAnatomy.swift`). Everything follows from the store's `openRowID`.
struct OpenRow: View {
    @EnvironmentObject private var store: MonitorStore
    let session: MonitoredSession

    @State private var isHovered = false
    /// The destination control's own hover; the row itself never answers the pointer.
    @State private var isDestinationHovered = false

    var body: some View {
        ZStack {
            // Permanently at the hover weight: an open row is always the thing being looked at.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            NotchPalette.themeInk.on.opacity(
                                NotchPalette.RowEmphasis.sessionHoverFillOpacity
                            )
                        )
                )
                // Inset from its frame (``PanelMetrics/sessionRowGroundInset``): an open row is washed
                // permanently, so a flush ground would sit against the chip above.
                .padding(.vertical, PanelMetrics.sessionRowGroundInset)

            VStack(alignment: .leading, spacing: PanelMetrics.sessionRowLineSpacing) {
                head
                if store.openRequestCount > 1 { requestNavigation }
                body(for: store.openRowBody)
                Spacer(minLength: 0)
                answerRow
            }
            .padding(.horizontal, PanelMetrics.sessionRowPadding)
            // Must match the closed row's centring so the head does not move when a row opens.
            .padding(.vertical, PanelMetrics.sessionRowVerticalPadding)
        }
        .frame(maxWidth: .infinity)
        .frame(height: store.openRowHeight ?? PanelMetrics.sessionRowHeight)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    private var requestNavigation: some View {
        HStack(spacing: 8) {
            requestStep("chevron.left", label: "Previous request", enabled: store.canGoBackARequest) {
                store.stepRequest(-1)
            }
            Text("Request \((store.openRequestIndex ?? 0) + 1) of \(store.openRequestCount)")
                .font(Font(PanelMetrics.requestControlFont).monospacedDigit())
                .foregroundStyle(NotchPalette.reading)
                .accessibilityLabel("Request \((store.openRequestIndex ?? 0) + 1) of \(store.openRequestCount)")
            requestStep("chevron.right", label: "Next request", enabled: store.canGoForwardARequest) {
                store.stepRequest(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: PanelMetrics.requestNavigationHeight)
    }

    private func requestStep(_ symbol: String, label: String, enabled: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Font(PanelMetrics.requestControlFont))
                .frame(width: PanelMetrics.requestNavigationHeight, height: PanelMetrics.requestNavigationHeight)
                .contentShape(Rectangle())
                .overlay(PointingHandCursor())
        }
        .buttonStyle(.plain)
        .foregroundStyle(NotchPalette.reading)
        .opacity(enabled ? 1 : 0.45)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .help(label)
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.sessionRowLineSpacing) {
            HStack(spacing: 8) {
                // The open row keeps its chip: opening un-pins headings (``ActiveSessionList``), so
                // the header has usually scrolled off, and the product decides what the answer
                // footer can do (`answer-in-notch.md` §14.2).
                // Never covered (`cover-the-words.md` §7).
                SessionRowCaption(
                    session: session,
                    showsAttribution: true,
                    isEmphasized: true,
                    isCovered: false
                )
                Spacer(minLength: 8)
                // Header and set position on the caption line's trailing side, empty on a closed row (§5.2).
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
            // The row's text still opens the Thread (§3, §6.6). The chevron keeps its own click: a
            // descendant's gesture wins over an ancestor's.
            .contentShape(Rectangle())
            .onTapGesture { store.open(session) }
        }
    }

    /// `Scope · 2/3`, or the count alone when there is no header (Codex). Always drawn, `1/1`
    /// included (§5.2).
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
                // Equal native IDs and bodies from another producer are still
                // another request: discard the previous body's scroll state.
                .id(store.openRequest?.identity)
        }
    }

    /// The three answers, or §11 rule 04's single control when the connection is not held
    /// (§11 rule 06). The single control never takes the white ground.
    @ViewBuilder
    private var answerRow: some View {
        if let shape = store.openAnswerRow {
            AnswerRow(session: session, shape: shape)
        } else {
            readingControl
        }
    }

    /// §11 rule 04: one control where three will stand. On the quiet answers' ladder, never the
    /// bright ground (`⏎` has nothing to do); not ``NotchPalette/recessedGround``, which marks
    /// machine text (§4.2).
    private var readingControl: some View {
        HStack(spacing: 8) {
            Button {
                store.open(session)
            } label: {
                Text(destination)
                    .font(Font(PanelMetrics.requestControlFont))
                    .foregroundStyle(
                        isDestinationHovered
                            ? NotchPalette.themeInk.on
                            : NotchPalette.reading
                    )
                    .padding(.horizontal, PanelMetrics.controlHorizontalPadding)
                    .frame(height: PanelMetrics.answerRowHeight)
                    .background(
                        RoundedRectangle(
                            cornerRadius: PanelMetrics.controlCornerRadius,
                            style: .continuous
                        )
                        .fill(
                            NotchPalette.themeInk.on.opacity(
                                isDestinationHovered
                                    ? NotchPalette.RowEmphasis.controlHoverFillOpacity
                                    : NotchPalette.RowEmphasis.controlRestFillOpacity
                            )
                        )
                    )
                    .overlay(PointingHandCursor())
                    .onHover { isDestinationHovered = $0 }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            if store.canGoBackAQuestion {
                AnswerControl(label: "Back", holdsGround: false, waitsForArrival: false,
                              spoken: "Read the previous question") { store.goBackAQuestion() }
            }
            if store.canGoForwardAQuestion {
                AnswerControl(label: "Next", holdsGround: false, waitsForArrival: false,
                              spoken: "Read the next question") { store.goForwardAQuestion() }
            }
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

/// The quota block's chevron, pointing up because what it folds is open
/// (`expanded-panel-v2.md` §2.2).
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
            // The row's own wash, not white; rests at nothing rather than
            // ``NotchPalette/RowEmphasis/controlRestFillOpacity`` so it does not read as a mark.
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        NotchPalette.themeInk.on.opacity(
                            isHovered
                                ? NotchPalette.RowEmphasis.sessionHoverFillOpacity
                                : 0
                        )
                    )
            )
            .overlay(PointingHandCursor())
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .accessibilityLabel("Collapse this request")
            .accessibilityAddTraits(.isButton)
    }
}

/// The field, the refusal and the affirmative (`answer-in-notch.md` §7).
///
/// The white ground marks what `⏎` does; only typing moves it, onto the text answer (§6).
/// Controls are text plus `12` a side either way. A one-answer form omits the refusal.
private struct AnswerRow: View {
    @EnvironmentObject private var store: MonitorStore
    let session: MonitoredSession
    let shape: AnswerRowShape

    var body: some View {
        HStack(spacing: 8) {
            if let placeholder = shape.placeholder {
                AnswerField(
                    identity: "\(session.id)#\(store.answerDraftGeneration)",
                    placeholder: placeholder,
                    initialText: store.answerDraft,
                    // §8 state 01: in flight, stop taking keys and drop the caret.
                    takesKeys: !store.isAnswerInFlight,
                    // §5.4 reversed: a ticked option overrules typed text.
                    superseded: store.questionHasASelection,
                    onEdit: { store.answerDraftChanged(to: $0) },
                    onReturn: { store.takeAnswer(store.answerGround) },
                    onEscape: { store.closeOpenRow() }
                )
                .frame(maxWidth: .infinity)
                .frame(height: PanelMetrics.answerRowHeight)
            } else {
                Spacer(minLength: 0)
            }

            // Previous question, in the slot a set's absent refusal leaves (§5.7, §7). Never holds ground.
            if store.canGoBackAQuestion {
                AnswerControl(
                    label: "Back",
                    holdsGround: false,
                    // A step is not an answer, so no arrival hold (§6.3).
                    waitsForArrival: false,
                    spoken: "Back to the previous question"
                ) {
                    store.goBackAQuestion()
                }
            }

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
            .opacity(store.canSubmitCurrentAnswer ? 1 : 0.45)
            .allowsHitTesting(store.canSubmitCurrentAnswer)
            .disabled(!store.canSubmitCurrentAnswer)
        }
        .frame(height: PanelMetrics.answerRowHeight)
        // §8 state 01: in flight, drop to `45%` and stop taking input. Nothing resizes, no spinner.
        .opacity(store.isAnswerInFlight ? 0.45 : 1)
        .allowsHitTesting(!store.isAnswerInFlight)
        .padding(.top, 10 - PanelMetrics.sessionRowLineSpacing)
    }
}

/// One answer: the ground when it holds it, its own text when not (§6.6). A click takes the
/// answer it lands on; hover never moves the ground; width is the same either way.
private struct AnswerControl: View {
    @EnvironmentObject private var store: MonitorStore

    let label: String
    let holdsGround: Bool
    /// Whether this control waits out §6.3's arrival before taking a click. False for controls that
    /// send nothing.
    var waitsForArrival: Bool = true
    /// Spoken label where the drawn word is shorter than the act (§13.3).
    var spoken: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Text(label)
            .font(Font(PanelMetrics.requestControlFont))
            .foregroundStyle(
                holdsGround
                    ? NotchPalette.onBrightGround
                    : (isHovered ? NotchPalette.themeInk.on : NotchPalette.reading)
            )
            .fixedSize()
            .frame(
                width: PanelMetrics.drawnAnswerControlWidth(label),
                height: PanelMetrics.answerRowHeight
            )
            .background(
                RoundedRectangle(
                    cornerRadius: PanelMetrics.controlCornerRadius,
                    style: .continuous
                )
                .fill(ground)
            )
            // Only while a click would be taken: the AppKit tracking area ignores
            // `allowsHitTesting(false)`, so a refusing control would still show the hand.
            .overlay { if isTarget { PointingHandCursor() } }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture(perform: action)
            .accessibilityElement()
            .accessibilityLabel(spoken ?? label)
            // §13.3: the ground is drawn only as brightness, so speak what `⏎` does.
            .accessibilityValue(holdsGround ? "Return takes this" : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    /// ``NotchPalette/brightGround`` while it is what `⏎` does; the deepened theme fill under the
    /// pointer; the quiet button wash otherwise.
    ///
    /// - Same ink as the mark that opened the row: the ground travels down here (§3.1).
    /// - A ground still arriving (§6.3) is dimmed, not hidden, and ignores the pointer.
    /// - Quiet answers wash stronger than the open row; see
    ///   ``NotchPalette/RowEmphasis/controlRestFillOpacity``.
    private var ground: Color {
        guard !holdsGround else {
            guard store.isAffirmativeArmed else {
                return NotchPalette.brightGround
                    .opacity(NotchPalette.arrivingGroundOpacity)
            }
            return isHovered ? NotchPalette.requestHoverGround : NotchPalette.brightGround
        }
        return NotchPalette.themeInk.on.opacity(
            isHovered
                ? NotchPalette.RowEmphasis.controlHoverFillOpacity
                : NotchPalette.RowEmphasis.controlRestFillOpacity
        )
    }

    /// Whether a click would be taken, i.e. what the pointing hand promises. Mirrors
    /// ``MonitorStore/takeAnswer(_:)``'s guard.
    private var isTarget: Bool {
        (store.isAffirmativeArmed || !waitsForArrival) && !store.isAnswerInFlight
    }
}

/// The answer field, hosted in AppKit.
///
/// - The caret must not be a SwiftUI animation (§13.2, `AGENTS.md` §7): it would invalidate the
///   whole panel twice a second. The text system draws it in its own layer.
/// - Text never reaches `@Published`; the store publishes only where the ground is.
/// - An ordinary focusable field (§6.6, corrected 2026-09-07): a click gives the caret, a click
///   elsewhere takes it (``OverlayPanel/sendEvent(_:)``); panel keys arrive only while nothing
///   holds it (``PanelKey``).
private struct AnswerField: NSViewRepresentable {
    /// Row plus ``MonitorStore/answerDraftGeneration``: the only things that refill the text view.
    /// Refilling on every pass would reset the caret under the person typing (§10).
    let identity: String
    let placeholder: String
    let initialText: String
    let takesKeys: Bool
    let superseded: Bool
    let onEdit: (String) -> Void
    let onReturn: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> AnswerFieldView {
        let view = AnswerFieldView()
        view.delegate = context.coordinator
        view.placeholder = placeholder
        view.string = initialText
        view.isEditable = takesKeys
        view.isSuperseded = superseded
        context.coordinator.identity = identity
        return view
    }

    func updateNSView(_ view: AnswerFieldView, context: Context) {
        context.coordinator.onEdit = onEdit
        context.coordinator.onReturn = onReturn
        context.coordinator.onEscape = onEscape
        view.placeholder = placeholder
        view.isEditable = takesKeys
        view.isSuperseded = superseded
        // §8 state 01: an answered row stops taking keys, so the caret leaves too.
        if !takesKeys, view.window?.firstResponder === view {
            view.window?.makeFirstResponder(nil)
        }
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

        /// The two keys the field handles itself; every other key is the text system's (§9.2).
        ///
        /// `⌘⏎`, `Space` and `⇥` are deliberately unbound: a second way to approve would make the white
        /// ground advisory. Digits and arrows go to the panel only when nothing holds the caret
        /// (``PanelKey``).
        func textView(
            _ view: NSTextView,
            doCommandBy selector: Selector
        ) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                onReturn()
                return true
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                // `⌥⏎`. `⇧⏎` arrives as `insertNewline:` in a plain text view (measured, Release), so it is
                // handled in ``AnswerFieldView/keyDown``.
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

/// The text view: one line of `13` pt, drawing its own ground.
///
/// Clicked into, not focused on open (§6.6, corrected 2026-09-07). With no caret at rest, the
/// ground marks hover and focus, and is nothing when neither holds.
final class AnswerFieldView: NSTextView {
    var placeholder: String = ""

    /// Whether a ticked option has taken the answer. Overruled text is dimmed, not removed (§5.4).
    var isSuperseded = false {
        didSet {
            guard isSuperseded != oldValue else { return }
            textColor = Self.ink(superseded: isSuperseded)
            needsDisplay = true
        }
    }

    private static func ink(superseded: Bool) -> NSColor {
        superseded
            ? NotchPalette.countsSessionDrawingColor.withAlphaComponent(0.45)
            : NotchPalette.countsSessionDrawingColor
    }

    private var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }

    /// `⇧⏎` inserts a new line; only `⏎` sends (§9.2).
    ///
    /// Read off the event: in a plain text view `⇧⏎` is `insertNewline:`, same as `⏎`.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.contains(.shift) {
            insertText("\n", replacementRange: selectedRange())
            return
        }
        super.keyDown(with: event)
    }

    /// The panel's recessed step: the one surface meant for input is drawn set into the row.
    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    /// Through `NSTextView`'s `init(frame:)`, never the designated initialiser with a `nil`
    /// container: that has no text system, and keystrokes fell through to the panel (measured,
    /// Release).
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
        textColor = Self.ink(superseded: false)
        insertionPointColor = .white
        textContainerInset = NSSize(width: 8, height: 5)
        textContainer?.lineFragmentPadding = 0
        // `13` pt line in a `28` pt box: a second line scrolls rather than growing the row (§12).
        textContainer?.widthTracksTextView = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: PanelMetrics.answerRowHeight)
    }

    /// Ground, text and placeholder all drawn here: a SwiftUI overlay would need every keystroke
    /// and focus change published.
    ///
    /// The ground is the quiet button wash (as on `Back`, `Deny`, `Submit`), not §4.2's recessed
    /// step, and is drawn only while hovered or focused (§7).
    override func draw(_ dirtyRect: NSRect) {
        drawGround()
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

    private func drawGround() {
        let isFocused = window?.firstResponder === self && isEditable
        let wash: Double = isFocused
            ? NotchPalette.RowEmphasis.controlHoverFillOpacity
            : (isHovered ? NotchPalette.RowEmphasis.controlRestFillOpacity : 0)
        let path = NSBezierPath(
            roundedRect: bounds,
            xRadius: PanelMetrics.controlCornerRadius,
            yRadius: PanelMetrics.controlCornerRadius
        )
        if wash > 0 {
            NotchPalette.themeInk.onDrawingColor(wash).setFill()
            path.fill()
        }
        // The focus mark matches the option card's selected stroke.
        guard isFocused else { return }
        NotchPalette.themeInk.onDrawingColor(Self.focusEdgeOpacity).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private static let focusEdgeOpacity = 0.5

    /// Tracking area so an empty field still reads as one under the pointer.
    ///
    /// - `.activeAlways`: the panel is hovered long before it holds the keyboard (ADR 0020).
    /// - Tagged, and only the tagged area is removed: `NSTextView` owns its own areas, which also
    ///   deliver `mouseEntered:` here.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where Self.isHoverArea(area) {
            removeTrackingArea(area)
        }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: [Self.hoverAreaKey: true]
            )
        )
    }

    private static let hoverAreaKey = "notchlineAnswerFieldHover"

    private static func isHoverArea(_ area: NSTrackingArea?) -> Bool {
        area?.userInfo?[hoverAreaKey] as? Bool == true
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if Self.isHoverArea(event.trackingArea) { isHovered = true }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if Self.isHoverArea(event.trackingArea) { isHovered = false }
    }

    /// Report caret arrival and departure; they never take it (``OverlayPanel/sendEvent(_:)``).
    override func becomeFirstResponder() -> Bool {
        let took = super.becomeFirstResponder()
        if took { needsDisplay = true }
        return took
    }

    override func resignFirstResponder() -> Bool {
        let gave = super.resignFirstResponder()
        if gave { needsDisplay = true }
        return gave
    }
}

/// A read-only scroll indicator: a `1.5` pt line over the range and a `3` pt capsule over the
/// visible slice. Always drawn while there is anything to scroll; not a grip.
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
                    .frame(width: PanelMetrics.scrollRailWidth, height: thumb)
                    .offset(y: (visibleHeight - thumb) * progress)
            }
            .frame(width: PanelMetrics.scrollRailWidth, height: visibleHeight)
            .accessibilityHidden(true)
        }
    }
}

/// A body taller than its space, with a count of the lines below the fold.
///
/// Only the wheel scrolls it (§6.2). Counted in lines, not bytes, because a hidden clause
/// (`&&`, `--force`) hides in lines (§15 q04).
private struct ScrollingRequestBody: View {
    let layout: RequestBodyLayout

    @State private var offset: CGFloat = 0

    private var travel: CGFloat {
        max(layout.contentHeight - layout.maximumHeight, 0)
    }

    private var overflows: Bool { travel > 0 }

    /// The slice ``RequestBodyView`` draws lines for (§4.7); arithmetic lives in
    /// ``RequestBodyLayout/drawnWindow(scrolledBy:)`` beside the fold count.
    private var window: ClosedRange<CGFloat>? {
        guard overflows else { return nil }
        return layout.drawnWindow(scrolledBy: offset)
    }

    var body: some View {
        RequestBodyView(layout: layout, window: window)
            .frame(
                maxWidth: .infinity,
                alignment: .topLeading
            )
            // Rasterised before the offset so the wheel is a layer transform: option cards re-rendered
            // every frame, `2.32` ms → `1.12` ms an event; sweep past an open row `40%` → `15%` of a core
            // (Release, 2026-09-07). Plain `Text` lines gain nothing (`system-architecture.md` §6).
            // Verified pixel-identical and same AX tree; `16 MB` on a `128 KB` body (`AGENTS.md` §7).
            .drawingGroup()
            .offset(y: -offset)
            .frame(height: layout.drawnHeight, alignment: .top)
            .clipped()
            // Fade at the fold; §4.4's count is drawn over it, since a fade alone cannot show a
            // `--force` below.
            .mask(alignment: .top) { fold }
            .overlay(alignment: .trailing) { rail }
            .overlay(alignment: .bottomTrailing) { count }
            // Wheel read directly and the body translated: a nested `ScrollView` chains against the
            // list's and loses. Keeps §4.4's count exact.
            // Over the body, never behind: behind the lines it never wins the hit test
            // (`system-architecture.md` §6).
            .overlay(
                WheelCatcher(claimsTheWheel: overflows) { delta in
                    offset = min(max(offset - delta, 0), travel)
                }
            )
            .onChange(of: layout) { old, new in
                if !new.optionLayouts.isEmpty && old.requestID == new.requestID && old.position == new.position {
                    offset = min(offset, travel)
                } else {
                    offset = 0
                }
            }
    }

    /// Solid to the last full line, then out; only when something is below.
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
            visibleHeight: layout.maximumHeight,
            contentHeight: layout.contentHeight,
            offset: offset
        )
    }

    /// `+2 lines`, over the fade. Spoken as well as drawn (§13.3).
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

/// Reads the wheel over one region and claims nothing else.
///
/// Like ``SecondaryClickCatcher``: drawn over the region, claiming one event type in
/// ``WheelCatcherView/hitTest(_:)``. As a `.background` it was never hit, since the body's
/// lines win the hit test (`system-architecture.md` §6).
struct WheelCatcher: NSViewRepresentable {
    /// A body that fits claims nothing, so the wheel still scrolls the list.
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
        // Trackpad reports pixels, a wheel lines; the precise flag says which.
        let delta = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : event.scrollingDeltaY * 12
        guard delta != 0 else { return }
        onScroll?(delta)
    }

    /// Split out from ``hitTest(_:)`` to be testable without an event loop, like
    /// ``SecondaryClickView/claims(_:)``. Wider breaks clicks underneath; narrower breaks scrolling.
    func claims(_ eventType: NSEvent.EventType?) -> Bool {
        claimsTheWheel && eventType == .scrollWheel
    }

    /// Claimed only for the wheel, only with travel. `nil` with no current event: that is AppKit
    /// asking about geometry.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard claims(NSApp.currentEvent?.type) else { return nil }
        return super.hitTest(point)
    }

    override var acceptsFirstResponder: Bool { false }
}

/// One request's body: the lines the layout counted, and the options under them.
///
/// Draws only lines the window reaches and holds the rest open by height (§4.7): a `128 KB`
/// payload as a `Text` per line took `0.80` s to open, `2.09` s for `240` wheel events and
/// `39` MB. Height always equals ``RequestBodyLayout/contentHeight``. `window` `nil` draws all.
struct RequestBodyView: View {
    let layout: RequestBodyLayout
    var window: ClosedRange<CGFloat>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if layout.fields.isEmpty {
                text
            } else {
                arguments
            }
            if !layout.options.isEmpty {
                Spacer().frame(height: PanelMetrics.optionListSpacing)
                VStack(spacing: PanelMetrics.optionSpacing) {
                    ForEach(layout.optionLayouts) { option in
                        OptionRow(layout: option, allowsSeveralAnswers: layout.allowsSeveralAnswers)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Every field is built and only its lines windowed: each field is one accessibility element
    /// with its whole label and value (§13.3).
    private var arguments: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.argumentSpacing) {
            ForEach(Array(zip(layout.fields, layout.fieldTops)), id: \.0.id) { field, top in
                VStack(alignment: .leading, spacing: PanelMetrics.argumentLabelSpacing) {
                    lineStack(
                        field.labelLines,
                        height: PanelMetrics.argumentLabelHeight,
                        top: top
                    ) { line in
                        Text(verbatim: line)
                            .font(Font(PanelMetrics.argumentLabelFont))
                            .foregroundStyle(NotchPalette.reading)
                            .frame(height: PanelMetrics.argumentLabelHeight, alignment: .leading)
                    }
                    .help(field.argument.id)
                    argumentValue(field, top: top + field.textTop)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(field.argument.label): \(field.argument.value)")
            }
        }
        .padding(.vertical, PanelMetrics.argumentBodyInset)
    }

    private func argumentValue(_ field: RequestBodyLayout.Field, top: CGFloat) -> some View {
        lineStack(field.lines, height: field.lineHeight, top: top) { line in
            Text(verbatim: line.isEmpty ? " " : line)
                .font(Font(field.isCode ? PanelMetrics.machineTextFont : PanelMetrics.proseFont))
                .foregroundStyle(NotchPalette.sessionTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: field.lineHeight, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, field.isCode ? PanelMetrics.machineTextHorizontalInset : 0)
        .padding(.vertical, field.isCode ? PanelMetrics.machineTextVerticalInset : 0)
        .background {
            if field.isCode {
                RoundedRectangle(cornerRadius: PanelMetrics.machineTextCornerRadius)
                    .fill(NotchPalette.recessedGround)
            }
        }
    }

    /// One run of equal-height lines, drawn where the window reaches it, held open otherwise.
    /// `top` comes from ``RequestBodyLayout/fieldTops`` and ``RequestBodyLayout/textTop`` so it
    /// agrees with ``RequestBodyLayout/linesBelowTheFold(scrolledBy:)``.
    private func lineStack(
        _ lines: [String],
        height: CGFloat,
        top: CGFloat,
        @ViewBuilder line draw: @escaping (String) -> some View
    ) -> some View {
        let drawn = RequestBodyLayout.visibleLines(
            of: lines.count, at: height, from: top, within: window
        )
        return VStack(alignment: .leading, spacing: 0) {
            if drawn.lowerBound > 0 {
                Spacer().frame(height: CGFloat(drawn.lowerBound) * height)
            }
            ForEach(drawn, id: \.self) { index in
                draw(lines[index])
            }
            if drawn.upperBound < lines.count {
                Spacer().frame(height: CGFloat(lines.count - drawn.upperBound) * height)
            }
        }
    }

    @ViewBuilder
    private var text: some View {
        let lines = lineStack(
            layout.lines,
            height: PanelMetrics.requestLineHeight(for: layout.setting),
            top: layout.textTop
        ) { line in
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
        .frame(maxWidth: .infinity, alignment: .leading)

        if layout.setting == .machineText {
            // The recessed ground marks machine text only (§4.2).
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

/// A selectable title and description with an independent reading disclosure.
/// Expanding text never selects or sends an answer. Read-only requests retain
/// the disclosure while disabling selection.
///
/// A ticked option stays ticked whatever is in the field; the field dims instead (§5.4,
/// reversed 2026-09-07).
struct OptionRow: View {
    @EnvironmentObject private var store: MonitorStore
    let layout: RequestBodyLayout.Option
    let allowsSeveralAnswers: Bool
    @State private var isHovered = false

    private var selected: Bool { store.isOptionTicked(layout.id) }
    private var isAnswerable: Bool { store.openRequest?.canBeAnswered == true }

    /// The whole card is the target (§6.6): padding sits inside the button's label, and the
    /// disclosure's line is held open by a clear band and drawn over it. As `VStack` siblings the
    /// gaps lit on hover but refused the click.
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Button {
                store.takeAnswer(.option(layout.id))
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        marker
                            .frame(width: PanelMetrics.optionHandleWidth, height: PanelMetrics.optionTitleLineHeight, alignment: .leading)
                        VStack(alignment: .leading, spacing: 0) {
                            lineStack(layout.titleLines, font: PanelMetrics.optionTitleFont, height: PanelMetrics.optionTitleLineHeight, ink: NotchPalette.sessionTitle)
                            if !layout.visibleDescription.isEmpty {
                                lineStack(layout.visibleDescription, font: PanelMetrics.optionDescriptionFont, height: PanelMetrics.optionDescriptionLineHeight, ink: NotchPalette.reading)
                                    .padding(.top, 3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if layout.canExpand {
                        Color.clear.frame(height: PanelMetrics.optionDisclosureHeight)
                    }
                }
                .padding(PanelMetrics.optionInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isAnswerable || store.isAnswerInFlight || !store.isAffirmativeArmed)
            .accessibilityLabel(layout.option.label)
            .accessibilityValue(selected ? "Selected" : "Not selected")
            .accessibilityHint(layout.option.description ?? "")

            if layout.canExpand {
                Button(layout.isExpanded ? "Show less" : "Show more") {
                    store.toggleOptionDescription(layout.id)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchPalette.reading)
                .buttonStyle(.plain)
                .frame(height: PanelMetrics.optionDisclosureHeight)
                .padding(.leading, PanelMetrics.optionInset + PanelMetrics.optionHandleWidth)
                .padding(.bottom, PanelMetrics.optionInset)
                .accessibilityLabel("\(layout.isExpanded ? "Show less about" : "Read full description for") \(layout.option.label)")
                .accessibilityValue(layout.isExpanded ? "Expanded" : "Collapsed")
                .disabled(store.isAnswerInFlight)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(NotchPalette.themeInk.on.opacity(selected ? 0.10 : (isHovered ? 0.07 : 0.025))))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(NotchPalette.themeInk.on.opacity(selected ? 0.5 : 0), lineWidth: 1))
        .onHover { isHovered = $0 }
    }

    @ViewBuilder private var marker: some View {
        if allowsSeveralAnswers {
            ZStack {
                RoundedRectangle(cornerRadius: 3).strokeBorder(NotchPalette.reading, lineWidth: 1)
                if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(NotchPalette.themeInk.on) }
            }
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
        } else {
            ZStack {
                Circle().strokeBorder(NotchPalette.reading, lineWidth: 1)
                if selected { Circle().fill(NotchPalette.themeInk.on).padding(4) }
            }
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
        }
    }

    private func lineStack(_ lines: [String], font: NSFont, height: CGFloat, ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line.isEmpty ? " " : line)
                    .font(Font(font))
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: height, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The bar at the head of one product's block on the live list.
///
/// - ``RecentSeam``'s bar with the badge where the label stands, minus the control: folding a
///   block is not offered, so no chevron, hover or click (`answer-in-notch.md` §11 rule 03).
/// - The rule runs the full width, since there is no control to stop short of.
/// - Square ground, not rounded: the bar pins, and a `12` pt corner would show rows beneath.
/// - All slack sits above the chip (``PanelMetrics/productGroupHeaderSlack``, `8`), so a
///   heading is nearer what it heads.
/// - The leading block drops the slack (``PanelMetrics/leadingProductGroupHeaderHeight``); the
///   band brings its own, so ``ExpandedPanelContent`` draws no hairline.
///
/// Internal like ``ActiveSessionList``, so its laid-out height can be checked.
struct ProductGroupHeader: View {
    let group: MonitorAggregation.SessionGroup
    /// The block the panel opens on, drawn without the slack.
    var isLeading: Bool = false

    private var height: CGFloat {
        isLeading
            ? PanelMetrics.leadingProductGroupHeaderHeight
            : PanelMetrics.productGroupHeaderHeight
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(Color.black)

            HStack(spacing: 8) {
                HStack(spacing: PanelMetrics.productBadgeCountSpacing) {
                    ProductBadge(name: group.agent.displayName)

                    // A drawn `2` pt dot like the seam's
                    // (``PanelMetrics/captionSeparatorDotSize``): a set `·` sits below the bar's
                    // centre line. Centred in ``PanelMetrics/productBadgeCountSpacing``.
                    Circle()
                        .fill(NotchPalette.label)
                        .frame(
                            width: PanelMetrics.captionSeparatorDotSize,
                            height: PanelMetrics.captionSeparatorDotSize
                        )
                        .accessibilityHidden(true)

                    // One step brighter while the block wants attention: grouped, the most urgent row may be
                    // below the fold (`panel-v2.md` §1.1).
                    Text(verbatim: "\(group.sessions.count)")
                        .font(Font(PanelMetrics.captionFont))
                        .foregroundStyle(
                            group.wantsAttention
                                ? NotchPalette.reading
                                : NotchPalette.label
                        )
                        .fixedSize()
                }

                Rectangle()
                    .fill(NotchPalette.hairline)
                    .frame(height: 1)
            }
            .padding(.horizontal, PanelMetrics.sessionRowPadding)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(.isHeader)
        .animation(.easeInOut(duration: 0.16), value: group.wantsAttention)
    }

    private var spokenLabel: String {
        let count = group.sessions.count
        let rows = "\(count) session\(count == 1 ? "" : "s")"
        return group.wantsAttention
            ? "\(group.agent.displayName), \(rows), one waiting for you"
            : "\(group.agent.displayName), \(rows)"
    }
}

/// The rule between the live list and the Recent queue (`expanded-panel-v2.md` §2.2).
///
/// The whole `32` pt line is the target, unlike the quota chevron (§2.4 rule 08). The count is
/// the only sign of an over-full queue: the viewport's spare `8` pt carries no ink.
private struct RecentSeam: View {
    @EnvironmentObject private var store: MonitorStore
    @Environment(\.overlayBodyWidth) private var overlayBodyWidth

    @State private var isHovered = false

    let count: Int

    var body: some View {
        Button {
            store.toggleRecent()
        } label: {
            SeamContent(count: count, isHovered: isHovered)
        }
        .buttonStyle(SessionRowButtonStyle())
        .frame(width: PanelMetrics.sessionViewportWidth(panelWidth: overlayBodyWidth ?? store.currentPanelSize.width))
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

            HStack(spacing: 8) {
                // The separator is the bar's own content, not a glyph in the label, sized by
                // ``PanelMetrics/captionSeparatorDotSize``.
                HStack(spacing: PanelMetrics.seamSeparatorSpacing) {
                    Text("Recent")

                    Circle()
                        .fill(ink)
                        .frame(
                            width: PanelMetrics.captionSeparatorDotSize,
                            height: PanelMetrics.captionSeparatorDotSize
                        )
                        .accessibilityHidden(true)

                    Text(verbatim: "\(count)")
                }
                .font(Font(PanelMetrics.captionFont))
                .foregroundStyle(ink)
                .fixedSize()

                FoldSeamRule(isVisible: store.isRecentExpanded)

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
            isPressed
                ? .easeInOut(duration: NotchPalette.RowEmphasis.pressEnterDuration)
                : .easeInOut(duration: NotchPalette.RowEmphasis.pressExitDuration),
            value: isPressed
        )
    }

    private var isEmphasized: Bool { isHovered || isPressed }

    private var ink: Color {
        isEmphasized ? NotchPalette.labelEmphasized : NotchPalette.label
    }
}

/// The rule between a folding bar's label and its chevron, drawn only while the section is open.
///
/// Keeps its width while hidden so nothing beside it moves; grows from the label's edge and stops
/// short of the chevron (a line through it reads as a strike).
private struct FoldSeamRule: View {
    let isVisible: Bool

    var body: some View {
        Rectangle()
            .fill(NotchPalette.hairline)
            .frame(height: 1)
            .scaleEffect(x: isVisible ? 1 : 0, anchor: .leading)
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isVisible)
    }
}

/// A row that has left the list: **product · project · subject** and an age, at half a live
/// row's height (`expanded-panel-v2.md` §2.3). Claims no status.
///
/// Click and secondary click are the live row's (§8.5 question 06, §2.4 rule 09).
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

    /// Spoken line with the age in words. Always names the product: a reader has no surface to
    /// disambiguate against.
    private var accessibilityText: String {
        let session = departure.session
        let age = departure.spokenAgeText(at: store.recentReadAt)
        // See ``SessionRow/accessibilityText``: the tree describes the drawing.
        guard !store.coversWords(of: session) else {
            return "\(session.agent.displayName), covered, \(age)"
        }
        return "\(session.agent.displayName), \(session.projectName), "
            + "\(session.title), \(age)"
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
                        .fill(NotchPalette.themeInk.on.opacity(fillOpacity))
                )
                // The live row's wash at the live row's inset.
                .padding(.vertical, PanelMetrics.sessionRowGroundInset)

            HStack(spacing: 12) {
                breadcrumb
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Bare, tabular, at most two characters (§2.3).
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
            isPressed
                ? .easeInOut(duration: NotchPalette.RowEmphasis.pressEnterDuration)
                : .easeInOut(duration: NotchPalette.RowEmphasis.pressExitDuration),
            value: isPressed
        )
    }

    /// **product · project · subject** in the panel's three inks; overflows and fades. The badge is
    /// always drawn (§8.6): nothing below the seam is grouped.
    private var breadcrumb: some View {
        HStack(spacing: 6) {
            ProductBadge(name: departure.session.agent.displayName)

            if store.coversWords(of: departure.session) {
                // One bar at the title's length; a retired row is a single run (`cover-the-words.md` §4.1).
                CoverBar(
                    length: PanelMetrics.coverBarBreadcrumbLength,
                    lineHeight: PanelMetrics.sessionRowCaptionHeight
                )
            } else {
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

    /// The live row's wash and weights (``NotchPalette/RowEmphasis``).
    private var fillOpacity: Double {
        if isPressed { return NotchPalette.RowEmphasis.sessionPressedFillOpacity }
        if isHovered { return NotchPalette.RowEmphasis.sessionHoverFillOpacity }
        return 0
    }
}

/// Internal so a figure can host it in a pointer state (see the geometry tests' hovered row).
struct SessionRowContent: View {
    @Environment(\.sessionRowIsPressed) private var isPressed

    @EnvironmentObject private var store: MonitorStore

    let session: MonitoredSession
    let isHovered: Bool

    var body: some View {
        ZStack {
            // The wash is inset (``PanelMetrics/sessionRowGroundInset``) so the air under a heading's
            // chip survives hover.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(NotchPalette.themeInk.on.opacity(fillOpacity))
                )
                .padding(.vertical, PanelMetrics.sessionRowGroundInset)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: PanelMetrics.sessionRowLineSpacing) {
                    SessionRowCaption(
                        session: session,
                        // Chip only on the flat list: grouped, the heading already names it
                        // (`panel-v2.md` §3.4). ``OpenRow`` keeps its own.
                        showsAttribution: !store.groupsSessionsByProduct,
                        isEmphasized: isEmphasized,
                        isCovered: isCovered
                    )

                    if isCovered {
                        CoverBar(
                            length: PanelMetrics.coverBarTitleLength,
                            lineHeight: PanelMetrics.sessionRowTitleHeight
                        )
                    } else {
                        SessionRowText(
                            text: session.title,
                            font: .systemFont(ofSize: 13, weight: .medium),
                            color: NotchPalette.sessionTitleDrawingColor,
                            lineHeight: PanelMetrics.sessionRowTitleHeight
                        )
                    }

                    // Always one line: the product's preview, this app's answer status (§8 states
                    // 02 and 03), or ``RowContentFallback/liveProgress``. See
                    // ``MonitorStore/previewLine(for:)``. Covered, the line is still laid out so
                    // the `72` pt row does not change height (`cover-the-words.md` §4.2).
                    if isCovered {
                        // The searchlight crosses the cover too: covering hides content, not live/finished.
                        CoverBar(
                            length: PanelMetrics.coverBarPreviewLength,
                            lineHeight: PanelMetrics.sessionRowPreviewHeight,
                            sweeps: sweepsBody
                        )
                    } else {
                        SessionRowText(
                            text: store.previewLine(for: session),
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
            isPressed
                ? .easeInOut(duration: NotchPalette.RowEmphasis.pressEnterDuration)
                : .easeInOut(duration: NotchPalette.RowEmphasis.pressExitDuration),
            value: isPressed
        )
    }

    private var sweepsBody: Bool { store.sweepsBody(for: session) }

    /// Whether the row's three runs are drawn as bars (`cover-the-words.md` §3).
    private var isCovered: Bool { store.coversWords(of: session) }

    private var isEmphasized: Bool { isHovered || isPressed }

    /// The row's wash in ``NotchPalette/themeInk``'s lit colour; see ``NotchPalette/RowEmphasis``.
    private var fillOpacity: Double {
        if isPressed { return NotchPalette.RowEmphasis.sessionPressedFillOpacity }
        if isHovered { return NotchPalette.RowEmphasis.sessionHoverFillOpacity }
        return 0
    }
}

private struct SessionStatusControl: View {
    @EnvironmentObject private var store: MonitorStore
    let session: MonitoredSession
    /// Pointer on this mark, not the row: the text is the Thread and the mark is the request
    /// (`answer-in-notch.md` §3).
    @State private var isMarkHovered = false

    // One mark per row, no hue; three silhouettes that one row answers alone
    // (`figma-design.md` page 14):
    // - Running: a bare reading.
    // - Wants a person: the word on the bright ground.
    // - Finished: a dot and the digits, like ``FinishedTurnDot``; a subagent still working keeps
    //   the ``SubagentBadgeView`` tile here.
    // A dim badge ground means work in flight; bright means something is stopped on a question,
    // possibly a subagent on a Completed row. The row's state is untouched; see
    // ``wantsAttention``.
    var body: some View {
        if session.status.wantsPerson {
            // The verb, not the duration (`panel-v2.md` §3.5). Reads the row's own turn, not its derived
            // status (`CONTEXT.md`: a row reports one turn, the ground its single exception).
            waitingWord
        } else if let startedAt = store.elapsedStart(for: session) {
            reading(startedAt: startedAt, stoppedAt: nil)
        } else if session.showsSubagentBadge {
            // Neutral badge (`dual-agent-design.md` §10; no product hue since `colour-v2.md` §1). One
            // badge for the whole count; the ground says whether any is stopped.
            SubagentBadgeView(badge: session.subagentBadge)
        } else if let span = store.finishedElapsed(for: session) {
            // What the turn took; nothing else on the surface reports it.
            reading(startedAt: span.start, stoppedAt: span.end)
        } else if session.status.keepsTiming {
            // Start never observed (unreachable with hook data); must not be left unmarked.
            Circle()
                .fill(NotchPalette.label)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
    }

    /// What this row wants, on the ground that says it wants something.
    ///
    /// A `Text` that does not tick (`AGENTS.md` §7). Built like ``AnswerControl`` (height, corner,
    /// padding, weight) on the app's ink; see ``NotchPalette/brightGround``.
    private var waitingWord: some View {
        Text(word)
            .font(Font(PanelMetrics.waitingMarkFont))
            .foregroundStyle(NotchPalette.onBrightGround)
            .lineLimit(1)
            .fixedSize()
            // One width for all three verbs (``PanelMetrics/waitingMarkWidth``), word centred: one
            // silhouette down the list.
            .frame(
                width: PanelMetrics.waitingMarkWidth,
                height: PanelMetrics.waitingMarkHeight
            )
            .background(
                RoundedRectangle(
                    cornerRadius: PanelMetrics.waitingMarkCornerRadius,
                    style: .continuous
                )
                .fill(ground)
            )
            // No curve, matching the row (``NotchPalette/RowEmphasis/controlHoverDuration``).
            // An overlay that declines every hit; the tap below is the target.
            .overlay(PointingHandCursor())
            .onHover { isMarkHovered = $0 }
            .contentShape(Rectangle())
        // The mark is the request, the text is the Thread (§3); a descendant's tap wins over the row.
        .onTapGesture { store.toggleOpenRow(session) }
        // Spoken as an action, not a second label (§13.3).
        .accessibilityElement()
        .accessibilityLabel(session.status.displayName)
        .accessibilityAddTraits(session.request == nil ? [] : .isButton)
        .accessibilityAction {
            store.toggleOpenRow(session)
        }
    }

    /// The verb inside the ground; hover never changes it, so nothing moves (§3.3,
    /// ``PanelMetrics/drawnWaitingMarkWidth(_:)``). Asked of the request, not the product; a
    /// request with no held connection says `Read` (`answer-in-notch.md` §11 rule 06).
    private var word: String {
        PanelMetrics.waitingMarkWord(
            for: session.status,
            canBeAnswered: session.request?.canBeAnswered == true
        )
    }

    private var ground: Color {
        isMarkHovered ? NotchPalette.requestHoverGround : NotchPalette.brightGround
    }

    /// The reading on its state's ground, behind a dot once stopped (``FinishedTurnDot``).
    ///
    /// No tile on a stopped reading, so running and finished digits end on the same column.
    @ViewBuilder
    private func reading(startedAt: Date, stoppedAt: Date?) -> some View {
        let readout = ElapsedReadout(
            startedAt: startedAt,
            stoppedAt: stoppedAt,
            tick: store.elapsedTick.eraseToAnyPublisher(),
            tint: tint,
            weight: weight
        )
        HStack(spacing: 0) {
            if stoppedAt != nil {
                // Still, unlike the notch's breathing dot: a pulse per row would move the list under a reader
                // (`AGENTS.md` §7).
                FinishedTurnDot(breathes: false)
                    .padding(.trailing, dotGap)
            }
            if let fill = groundFill {
                ReadingGround(fill: fill) { readout }
            } else {
                readout
            }
        }
    }

    /// Drawn gap from dot to digits. The collapsed wing adds ``ReadingGround`` padding to
    /// ``PanelMetrics/buriedFinishDotSpacing``; a row with no ground pays that `4` here so both
    /// surfaces match (`compact-view-v2.md` §4.3). Trailing-anchored, so only the dot moves.
    private var dotGap: CGFloat {
        groundFill == nil
            ? PanelMetrics.drawnFinishDotGap
            : PanelMetrics.buriedFinishDotSpacing
    }

    /// The bright ground when the row wants a person; nil otherwise. Running and finished readings
    /// are bare; the tile stays with ``SubagentBadgeView``.
    private var groundFill: Color? {
        wantsAttention ? NotchPalette.brightGround : nil
    }

    /// Whether the turn wants the person, or a subagent of this thread sits on a permission prompt.
    /// The latter changes only brightness: the row stays Completed, its clock stopped, its preview
    /// the final answer, and dismissable.
    private var wantsAttention: Bool {
        session.status == .inputNeeded
            || session.status == .approvalNeeded
            || session.subagentsAwaitingApproval
    }

    /// The reading takes whichever end of the pair its ground does not.
    private var tint: NSColor {
        wantsAttention
            ? NotchPalette.onBrightGroundDrawingColor
            : NotchPalette.labelDrawingColor
    }

    private var weight: NSFont.Weight {
        wantsAttention ? .medium : .light
    }
}

/// The row's leading `11 pt` line: the product badge (while more than one product is
/// connected), then the Project.
///
/// The chip is the only product presentation (`colour-v2.md` §5), in the user's ink. No
/// separator after the badge (`panel-v2.md` §3.4); the `6` is the badge's padding. The
/// attribution's width comes out of the Project, which fades.
private struct SessionRowCaption: View {
    let session: MonitoredSession
    let showsAttribution: Bool
    /// Row hovered or pressed, so the caption lifts a shade with it.
    var isEmphasized: Bool = false
    /// Whether the Project is covered (`cover-the-words.md` §3). The badge never is: it names the
    /// tool, not the work (§12 question 01).
    var isCovered: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if showsAttribution {
                ProductBadge(name: session.agent.displayName)
            }

            if isCovered {
                CoverBar(
                    length: PanelMetrics.coverBarProjectLength,
                    lineHeight: PanelMetrics.sessionRowCaptionHeight
                )
            } else {
                Text(session.projectName)
                    .foregroundStyle(
                        isEmphasized ? NotchPalette.labelEmphasized : NotchPalette.label
                    )
                    .font(.system(size: 11, weight: .light))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        // Badge height whether or not a badge is drawn, so a second product connecting moves nothing.
        .frame(height: PanelMetrics.sessionRowCaptionHeight)
    }
}

/// A product's name as a chip: ground from ``NotchPalette/themeInk``'s unlit value, text from
/// its lit one.
///
/// The hue lives in the text; the unlit ground reads near-black at badge size. Inverted
/// (``NotchPalette/brightGround`` / ``NotchPalette/onBrightGround``) means a row wants a person
/// (`colour-v2.md` §4); a trail badge flips for such a block (`expanded-panel-v2.md` §4.6).
private struct ProductBadge: View {
    let name: String
    var isInverted: Bool = false

    var body: some View {
        let ink = NotchPalette.themeInk
        Text(name)
            .font(Font(PanelMetrics.productBadgeFont))
            .foregroundStyle(isInverted ? ink.off : ink.on)
            .padding(.horizontal, PanelMetrics.productBadgePadding)
            .frame(height: PanelMetrics.productBadgeHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: PanelMetrics.productBadgeRadius,
                    style: .continuous
                )
                .fill(isInverted ? ink.on : ink.off)
            )
            .fixedSize()
    }
}

/// The two badge trails and every heading between them, drawn over the list at
/// ``ProductTrailLayout``'s positions (`expanded-panel-v2.md` §4.6).
///
/// - Every heading carries `16` of opaque black; rows scroll under the top strip and fade over
///   ``PanelMetrics/productTrailFadeHeight`` at the foot, which has no rule.
/// - Grounds are drawn even when the list fits: during a panel resize the scroller still
///   scrolls, and a conditional ground let rows slide through the chip.
/// - Grounds are laid before any chip, so an arriving heading never blacks out badges.
/// - Hit-tests only where it draws; everything else falls through to the rows.
private struct ProductTrails: View {
    let groups: [MonitorAggregation.SessionGroup]
    let layout: ProductTrailLayout
    let width: CGFloat
    let height: CGFloat
    let select: (AgentKind) -> Void

    var body: some View {
        let headings = Array(zip(groups, layout.headings))
        ZStack(alignment: .topLeading) {
            ForEach(headings, id: \.0.id) { _, heading in
                Rectangle()
                    .fill(Color.black)
                    .frame(width: width, height: PanelMetrics.productTrailHeight)
                    .offset(y: heading.y)
                    .accessibilityHidden(true)
            }

            if layout.drawsFootLine {
                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: width, height: PanelMetrics.productTrailFadeHeight)
                .offset(y: height - PanelMetrics.productTrailHeight - PanelMetrics.productTrailFadeHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                Rectangle()
                    .fill(Color.black)
                    .frame(width: width, height: PanelMetrics.productTrailHeight)
                    .offset(y: height - PanelMetrics.productTrailHeight)
                    .accessibilityHidden(true)
            }

            ForEach(headings, id: \.0.id) { group, heading in
                TrailHeading(group: group, heading: heading, select: select)
                    // Width past the chip, so the rule ends on the content box's trailing edge.
                    .frame(width: max(width - heading.x, 0), alignment: .leading)
                    .offset(x: heading.x, y: heading.y)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
}

/// One heading as the overlay draws it: ``ProductGroupHeader``'s chip line, the badge a control,
/// the rest faded by trail progress.
private struct TrailHeading: View {
    let group: MonitorAggregation.SessionGroup
    let heading: ProductTrailLayout.Heading
    let select: (AgentKind) -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: PanelMetrics.productBadgeCountSpacing) {
                TrailBadge(group: group, trailed: heading.trailed) {
                    select(group.agent)
                }

                HStack(spacing: PanelMetrics.productBadgeCountSpacing) {
                    Circle()
                        .fill(NotchPalette.label)
                        .frame(
                            width: PanelMetrics.captionSeparatorDotSize,
                            height: PanelMetrics.captionSeparatorDotSize
                        )
                        .accessibilityHidden(true)

                    Text(verbatim: "\(group.sessions.count)")
                        .font(Font(PanelMetrics.captionFont))
                        .foregroundStyle(
                            group.wantsAttention
                                ? NotchPalette.reading
                                : NotchPalette.label
                        )
                        .fixedSize()
                        .accessibilityHidden(true)
                }
                .opacity(heading.tail)
            }

            Rectangle()
                .fill(NotchPalette.hairline)
                .frame(height: 1)
                .opacity(heading.tail)
        }
        .padding(.trailing, PanelMetrics.sessionRowPadding)
        .frame(height: PanelMetrics.productTrailHeight)
    }
}

/// A block's badge as a control: click scrolls that block to the top.
///
/// On a trail it dims, or flips if its block wants a person (§4.5), crossfading with docking so
/// flip and lit count never show at once. Hover brightens a dimmed badge and shows the hand.
private struct TrailBadge: View {
    let group: MonitorAggregation.SessionGroup
    let trailed: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    private var name: String { group.agent.displayName }

    private var flip: Double {
        group.wantsAttention ? Double(trailed) : 0
    }

    private var weight: Double {
        if group.wantsAttention || isHovered { return 1 }
        return 1 - Double(trailed) * (1 - PanelMetrics.productTrailBadgeOpacity)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                ProductBadge(name: name)
                ProductBadge(name: name, isInverted: true)
                    .opacity(flip)
            }
        }
        .buttonStyle(.plain)
        .opacity(weight)
        .onHover { isHovered = $0 }
        .overlay(PointingHandCursor())
        .accessibilityLabel(spokenLabel)
        .accessibilityHint("Scrolls the list to this product's sessions.")
        .help("Scroll to \(name)")
    }

    private var spokenLabel: String {
        let count = group.sessions.count
        let rows = "\(count) session\(count == 1 ? "" : "s")"
        return group.wantsAttention
            ? "\(name), \(rows), one waiting for you"
            : "\(name), \(rows)"
    }
}

/// The pointing hand over every control on the panel.
///
/// - Not `addCursorRect(_:cursor:)`: AppKit services cursor rects for the key window only, and
///   this overlay usually is not one. An `.activeAlways` area delivers regardless;
///   ``BackgroundCursor`` lets the non-active app actually set it.
/// - A separate `.cursorUpdate` area (`.activeInKeyWindow`; AppKit rejects it with
///   `.activeAlways`): a latched panel is key, and the request body's scroll view reset the
///   hand to an arrow (measured 2026-09-06). `.mouseMoved` repairs it while in background.
/// - `set()`, not `push()`/`pop()`: the stack is process-global and a pop may never run on a
///   retired row or collapsed panel.
struct PointingHandCursor: NSViewRepresentable {
    func makeNSView(context: Context) -> PointingHandView { PointingHandView() }

    func updateNSView(_ nsView: PointingHandView, context: Context) {}
}

/// Lets this process set the cursor while another application is active, i.e. every hover
/// except on an open row.
///
/// - `NSCursor.set()` does nothing outside the active app; the gate is activation, not key
///   status (measured 2026-09-06, non-activating panel at level `25`, accessory app).
/// - Activating is not an option: §9.4 of `answer-in-notch.md` leaves the keyboard with the
///   app being typed in. This changes nothing about activation, key status or keyboard.
/// - The property is private, fetched via `dlsym`; absent means `false` and the arrow.
///   ``NotchlineTests`` pins the agreement to catch a release withdrawing it.
enum BackgroundCursor {
    /// Asked once per process; reading it asks. `true` if the window server agreed.
    static let isAllowed: Bool = requestFromWindowServer()

    private static func requestFromWindowServer() -> Bool {
        typealias MainConnectionID = @convention(c) () -> Int32
        typealias SetConnectionProperty =
            @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        // `RTLD_DEFAULT`: a vanished symbol is a `nil` here, not a launch failure.
        let loadedImages = UnsafeMutableRawPointer(bitPattern: -2)
        guard
            let connectionSymbol = dlsym(loadedImages, "CGSMainConnectionID"),
            let propertySymbol = dlsym(loadedImages, "CGSSetConnectionProperty")
        else { return false }
        let connection = unsafeBitCast(connectionSymbol, to: MainConnectionID.self)()
        let setProperty = unsafeBitCast(propertySymbol, to: SetConnectionProperty.self)
        let status = setProperty(
            connection,
            connection,
            "SetsCursorInBackground" as CFString,
            kCFBooleanTrue
        )
        return status == 0
    }
}

final class PointingHandView: NSView {
    private var tracking: NSTrackingArea?
    private var cursorTracking: NSTrackingArea?

    /// `.inVisibleRect` keeps the area in step with a scrolling row.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        if let cursorTracking { removeTrackingArea(cursorTracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area

        // AppKit explicitly excludes cursorUpdate from activeAlways. Keep its
        // key-window cursor pass separate from background pointer tracking.
        let cursorArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .cursorUpdate, .inVisibleRect],
            owner: self
        )
        addTrackingArea(cursorArea)
        cursorTracking = cursorArea
    }

    /// The key window's cursor pass, which the options' scroll view would otherwise win.
    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    /// Never takes a click; the tracking area is geometric and unaffected.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    /// Reassert the hand after entry while moving within a background panel,
    /// where the key-window cursor pass cannot repair a competing arrow.
    override func mouseMoved(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    /// Restores the arrow on leaving the window, since `mouseExited` never arrives if the row
    /// retires or the panel collapses. Also requests ``BackgroundCursor`` before any tracking
    /// area here can fire.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            NSCursor.arrow.set()
            return
        }
        _ = BackgroundCursor.isAllowed
    }
}

/// Turns a secondary click on the covered view into one call and leaves every other event alone.
///
/// AppKit because SwiftUI only offers `contextMenu`, a second click on a panel that hides on
/// exit. `hitTest` answers only for a secondary press, so primary clicks, hover and cursor
/// tracking reach the SwiftUI button beneath.
struct SecondaryClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> SecondaryClickView {
        let view = SecondaryClickView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: SecondaryClickView, context: Context) {
        // Re-assigned: SwiftUI reuses the view when the list reorders.
        nsView.action = action
    }
}

final class SecondaryClickView: NSView {
    var action: (() -> Void)?

    /// Split out from ``hitTest(_:)`` to be testable without an event loop. Widening it stops the
    /// row's primary click reaching the button.
    static func claims(_ eventType: NSEvent.EventType?) -> Bool {
        eventType == .rightMouseDown || eventType == .rightMouseUp
    }

    /// Claimed only for the secondary press. `nil` with no current event: AppKit asking about
    /// geometry.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard Self.claims(NSApp.currentEvent?.type) else { return nil }
        return super.hitTest(point)
    }

    /// The overlay never becomes key, so without this the first press would be spent on
    /// activation.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// On the press, as secondary clicks act everywhere else on the system.
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
