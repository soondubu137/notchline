import AppKit
import Combine
import CoreImage
import SwiftUI

/// Colours the notch surface owns, mirroring the Figma variables of the same name.
enum NotchPalette {
    // Core Animation needs CGColor and SwiftUI needs Color; both come from these components.
    private static let labelRGB = (red: 0.486, green: 0.486, blue: 0.502)

    /// One mark's two colours. Hue carries nothing (`colour-v2.md` §1); brightness says whether
    /// something wants the user.
    nonisolated struct MatrixInk: Equatable, Sendable {
        let offRed, offGreen, offBlue: Double
        let onRed, onGreen, onBlue: Double

        var off: Color { Color(red: offRed, green: offGreen, blue: offBlue) }
        var on: Color { Color(red: onRed, green: onGreen, blue: onBlue) }
        /// A subagent badge's dim ground, used while everything it counts is running.
        ///
        /// Lifted evenly towards white so the tile does not read as a hole; the bright end is the
        /// unlifted lit colour. Measured off raw channels, never a row's fill, so it does not answer
        /// to hover (``RowEmphasis``).
        var chipFill: Color {
            Color(
                red: min(1, offRed + Self.chipLift),
                green: min(1, offGreen + Self.chipLift),
                blue: min(1, offBlue + Self.chipLift)
            )
        }
        /// Lift of ``chipFill`` towards white: `#151515` → `#242424` for resting grey. Tuned by eye.
        private static let chipLift = 0.06
        /// The lit colour as `NSColor`, for the hosted answer field (`answer-in-notch.md` §7).
        func onDrawingColor(_ alpha: Double = 1) -> NSColor {
            NSColor(srgbRed: onRed, green: onGreen, blue: onBlue, alpha: alpha)
        }
        var offLayerColor: CGColor {
            CGColor(srgbRed: offRed, green: offGreen, blue: offBlue, alpha: 1)
        }
        var onLayerColor: CGColor {
            CGColor(srgbRed: onRed, green: onGreen, blue: onBlue, alpha: 1)
        }
    }

    /// The resting mark, when no product is connected.
    ///
    /// `#151515` is the brightest neutral at or below both products' unlit luminance (`0.0075`
    /// vs `#21120D`'s `0.0079` and `#101B26`'s `0.0104`), so connected never looks dimmer than
    /// not. Lit equals unlit: nothing can be running.
    static let restingInk = MatrixInk(
        offRed: 0x15 / 255, offGreen: 0x15 / 255, offBlue: 0x15 / 255,
        onRed: 0x15 / 255, onGreen: 0x15 / 255, onBlue: 0x15 / 255
    )

    /// The one ink this surface owns: the aggregate mark, every product badge, and the row wash.
    ///
    /// Sage · hint, `#1B1F1C` → `#DEE8E0`: hue `150°`, the furthest in OKLCH from both products
    /// (`108°` each), so it never reads as a dim Codex or Claude Code (`compact-view-v2.md` §2.2).
    /// Lightnesses match the greyscale (`#E5E5EA` / `#1E1E1E`): brightness is the attention
    /// channel. A constant, not a preference; every reader goes through this name.
    static let themeInk = MatrixInk(
        offRed: 0x1B / 255, offGreen: 0x1F / 255, offBlue: 0x1C / 255,
        onRed: 0xDE / 255, onGreen: 0xE8 / 255, onBlue: 0xE0 / 255
    )

    /// ``themeInk`` once something is connected, ``restingInk`` until then. The resting grey must
    /// not be tinted: it means nothing is connected.
    nonisolated static func matrixInk(isConnected: Bool) -> MatrixInk {
        isConnected ? themeInk : restingInk
    }

    /// `#9A9A9E`, a step above ``label`` for a caption in a hovered or pressed row. Layer-backed
    /// title and preview lines do not use it; see ``RowEmphasis``.
    static let labelEmphasized = Color(
        red: 0x9A / 255, green: 0x9A / 255, blue: 0x9E / 255
    )

    /// Pointer response: session, open and retired rows fill with ``themeInk``'s lit colour at
    /// low opacity; the two folding bars never fill and answer with label and chevron brightness.
    enum RowEmphasis {
        /// Fill for every washing row: live, open for an answer, and retired.
        ///
        /// `0.08` was too faint to see. `0.12`–`0.14` erases a product badge's `L 0.234` ground and
        /// `0.20` the subagent chip's `L 0.296`; `0.16` (`L 0.263`) clears both by about `0.03`
        /// (`colour-v2.md` §10 question 02). Pressed keeps the `ΔL ≈ 0.08` step.
        static let sessionHoverFillOpacity: Double = 0.16
        static let sessionPressedFillOpacity: Double = 0.24

        /// Quiet request buttons must stay visible on the open row's `0.16` wash (`0.08`/`0.04` did
        /// not). Default theme: about #505451 rest, #454846 hover, on #242524; resting text 4.57:1.
        /// Options keep their separate hover wash.
        static let controlRestFillOpacity: Double = 0.24
        static let controlHoverFillOpacity: Double = 0.18

        /// A borderless theme-hue charcoal tile. `0.14` ≈ `#1F201F`, `L∗ 12` on black. An edge at
        /// `0.40` outshone its label; hover steps `0.04` because the fill is the only thing that moves.
        static let plainControlRestFillOpacity: Double = 0.14
        static let plainControlHoverFillOpacity: Double = 0.18

        /// Rows, folding bars and a row's waiting mark do not animate their hover wash: a fast sweep
        /// (`40` ms per row) left rows half-lit and trailing. A lone aimed control keeps a short fade
        /// in (``AboutUpdateControl``).
        static let controlHoverDuration: Double = 0.13
        static let pressEnterDuration: Double = 0.08
        static let pressExitDuration: Double = 0.10
    }

    /// `text/notch-label` — the dim base every notch label sits at.
    static let label = Color(
        red: labelRGB.red,
        green: labelRGB.green,
        blue: labelRGB.blue
    )
    /// The bar a covered run is drawn as (`cover-the-words.md` §4): ``label`` at `45%` for every
    /// bar, so a covered panel's bars never take the attention channel.
    static let coverBar = label.opacity(coverBarOpacity)
    /// ``coverBar`` for AppKit drawing, where a searchlight crosses it (``CoverBarView``).
    static let coverBarDrawingColor = labelDrawingColor
        .withAlphaComponent(coverBarOpacity)
    private static let coverBarOpacity: Double = 0.45
    /// The optional edge around the whole surface (`figma-design.md` §8.4): ``label`` × `0.75`
    /// per channel (`#5D5D60`), derived so it cannot drift into a hue.
    static let surfaceEdge = Color(
        red: labelRGB.red * edgeDimming,
        green: labelRGB.green * edgeDimming,
        blue: labelRGB.blue * edgeDimming
    )
    /// Tuned by eye: `0.5` (`#3E3E40`) vanished on a dim wallpaper; `1.0` read as a mark.
    private static let edgeDimming = 0.75
    /// White glyph emphasis. Request controls keep their theme hue on hover.
    static let spotlight = Color.white

    /// The one bright ground and the ink on it: ``themeInk``'s lit value, `#DEE8E0`, `L∗ 91`.
    ///
    /// One name for both meanings (a row wants a person; what `⏎` does) because the ground
    /// travels from the row to the answer row (`answer-in-notch.md` §3.1).
    static var brightGround: Color { themeInk.on }
    /// Opaque, so hovering a row cannot change the button's deepened colour.
    /// Scaling all channels equally preserves the theme hue.
    static var requestHoverGround: Color {
        Color(
            red: themeInk.onRed * 0.85,
            green: themeInk.onGreen * 0.85,
            blue: themeInk.onBlue * 0.85
        )
    }
    /// Ink on ``brightGround``: the same ink's unlit end, `#1B1F1C`, at `13.3 : 1`.
    static var onBrightGround: Color { themeInk.off }
    /// ``brightGround``'s opacity while still arriving and not yet a target
    /// (`answer-in-notch.md` §6.3). Set by text contrast: `0.45` gave ``onBrightGround`` only
    /// `4.0 : 1` on a `13` pt light label; `0.64` gives `6.4 : 1`, still ~`25` L∗ below landed.
    /// Does not take ``requestHoverGround``.
    static let arrivingGroundOpacity: Double = 0.64
    /// Session title — the one element that stays bright.
    static let sessionTitle = Color.white.opacity(0.98)
    /// `#C7C7CC`, between the title's white and ``label``. Same value as
    /// ``countsSessionDrawingColor``; the spend figure on the footer (`quota-footer-v2.md` §5).
    static let reading = Color(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xCC / 255)
    /// Ground for a request's machine text, `#242424` (`answer-in-notch.md` §4.2). Chosen by the
    /// payload's kind, never by length.
    static let recessedGround = Color(
        red: 0x24 / 255,
        green: 0x24 / 255,
        blue: 0x24 / 255
    )
    /// `#5A5A5E` (§5.1): an option's numeral and description while it holds ``brightGround``.
    /// `5.3 : 1` on `#DEE8E0`.
    static let readingOnLight = Color(
        red: 0x5A / 255,
        green: 0x5A / 255,
        blue: 0x5E / 255
    )

    /// `#6E6E73` (§5.1), dimmer than ``label``: the numeral is a handle, not a reading.
    static let optionNumeral = Color(
        red: 0x6E / 255,
        green: 0x6E / 255,
        blue: 0x73 / 255
    )

    /// Drawing colours for the layer-backed notch label.
    static let labelDrawingColor = NSColor(
        srgbRed: labelRGB.red,
        green: labelRGB.green,
        blue: labelRGB.blue,
        alpha: 1
    )
    /// The sessions numeral, the brighter counts step (`compact-view-v2.md` §3.2 rule 01). The
    /// subagent numeral is ``labelDrawingColor``; hierarchy is size and brightness, never hue.
    static let countsSessionDrawingColor = NSColor(
        srgbRed: 0xC7 / 255,
        green: 0xC7 / 255,
        blue: 0xCC / 255,
        alpha: 1
    )
    /// The finished-turn dot, on the notch and a row: the sessions numeral's ink, so the breath's
    /// crest equals the numeral and never exceeds it.
    static var finishedDotDrawingColor: NSColor { countsSessionDrawingColor }
    /// Every panel rule, the block badge/count dot (`expanded-panel-v2.md` §4.2) included:
    /// `1` pt white at `15%`. The scroll rail's track keeps its own value.
    static let hairline = Color.white.opacity(0.15)
    /// The same ink in SwiftUI, for a row's still dot.
    static var finishedDot: Color { reading }
    /// The searchlight sweeping a row's text; brightens glyphs, never fills. See ``spotlight``.
    static let spotlightDrawingColor = NSColor.white
    static let sessionTitleDrawingColor = NSColor.white.withAlphaComponent(0.98)
    static let onBrightGroundDrawingColor = NSColor(
        srgbRed: themeInk.offRed,
        green: themeInk.offGreen,
        blue: themeInk.offBlue,
        alpha: 1
    )
}

/// Elapsed time for a turn; the whole indicator for an unfinished row.
///
/// Draws into a layer off the store's tick: a store republish costs ~20ms of overlay
/// re-evaluation, about 4% of a core per running turn.
struct ElapsedReadout: View {
    let startedAt: Date
    /// When the turn ended. With an end, the reading is fixed between the two stamps and the tick
    /// is ignored; nil while running.
    var stoppedAt: Date?
    let tick: AnyPublisher<Date, Never>
    var tint: NSColor = NotchPalette.labelDrawingColor
    var weight: NSFont.Weight = .light
    /// Drawn before the elapsed value in the same raster, so the collapsed slot's subagent count and
    /// elapsed are one measurement. Empty elsewhere.
    var prefix: String = ""

    var body: some View {
        ElapsedReadoutRepresentable(
            startedAt: startedAt,
            stoppedAt: stoppedAt,
            tick: tick,
            tint: tint,
            weight: weight,
            prefix: prefix
        )
        // Rows and panel speak their own elapsed; VoiceOver reads "12:34" as a time of day.
        .accessibilityHidden(true)
    }
}

private struct ElapsedReadoutRepresentable: NSViewRepresentable {
    let startedAt: Date
    let stoppedAt: Date?
    let tick: AnyPublisher<Date, Never>
    let tint: NSColor
    let weight: NSFont.Weight
    let prefix: String

    func makeNSView(context: Context) -> ElapsedReadoutView {
        ElapsedReadoutView()
    }

    func updateNSView(_ view: ElapsedReadoutView, context: Context) {
        view.configure(
            startedAt: startedAt,
            stoppedAt: stoppedAt,
            tint: tint,
            weight: weight,
            prefix: prefix,
            tick: tick
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: ElapsedReadoutView,
        context: Context
    ) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

final class ElapsedReadoutView: NSView {
    private let glyphLayer = CALayer()
    private var subscription: AnyCancellable?
    private var startedAt: Date?
    private var stoppedAt: Date?
    private var font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .light)
    private var tint = NotchPalette.labelDrawingColor
    private var prefix = ""
    private var lastTick = Date.distantPast
    private var renderedText = ""
    private var renderedScale: CGFloat = 0
    private var renderedSize: CGSize = .zero

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(glyphLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        guard renderedSize == .zero else {
            return NSSize(width: renderedSize.width, height: renderedSize.height)
        }
        // SwiftUI may measure before the first tick; every readout starts at 0:00.
        let placeholder = NotchTextRaster.textSize(prefix + "0:00", font: font)
        return NSSize(width: placeholder.width, height: placeholder.height)
    }

    func configure(
        startedAt: Date,
        stoppedAt: Date? = nil,
        tint: NSColor,
        weight: NSFont.Weight,
        prefix: String = "",
        tick: AnyPublisher<Date, Never>
    ) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: weight)
        let changed = startedAt != self.startedAt
            || stoppedAt != self.stoppedAt
            || tint != self.tint
            || font != self.font
            || prefix != self.prefix
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
        self.tint = tint
        self.font = font
        self.prefix = prefix

        // A stopped reading needs no tick; drop any subscription.
        guard stoppedAt == nil else {
            subscription = nil
            render(at: lastTick)
            return
        }

        guard subscription == nil else {
            if changed { render(at: lastTick) }
            return
        }
        // CurrentValueSubject delivers the current instant on subscribe, so it is never blank.
        subscription = tick.sink { [weak self] now in
            self?.render(at: now)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        render(at: lastTick)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glyphLayer.frame = CGRect(origin: .zero, size: renderedSize)
        CATransaction.commit()
    }

    private func render(at now: Date) {
        lastTick = now
        guard let startedAt else { return }
        // Clamped like ``MonitorStore.readableNow``: the once-a-second tick may predate a new turn's
        // start, which would draw an empty raster.
        let elapsed = SessionElapsedFormatter.elapsed(
            since: startedAt,
            now: stoppedAt ?? max(now, startedAt)
        )
        let text = elapsed.map { prefix + $0 } ?? ""
        let scale = window?.backingScaleFactor ?? 2
        guard text != renderedText || scale != renderedScale else { return }
        renderedText = text
        renderedScale = scale

        let size = NotchTextRaster.textSize(text, font: font)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glyphLayer.contentsScale = scale
        glyphLayer.contents = NotchTextRaster.glyphImage(
            text: text,
            font: font,
            color: tint,
            size: size,
            scale: scale
        )
        glyphLayer.frame = CGRect(origin: .zero, size: size)
        CATransaction.commit()

        guard size != renderedSize else { return }
        // Width changes only with digit count, when the store also bumps its layout revision.
        renderedSize = size
        invalidateIntrinsicContentSize()
    }
}

/// One subagent badge: a filled rounded tile holding the count of every subagent
/// (`dual-agent-design.md` §10).
///
/// Fixed at `PanelMetrics.subagentBadgeWidth` so the collapsed pill's composed width cannot
/// disagree with SwiftUI's text layout. No second badge for waiting ones; the ground says it.
struct SubagentBadgeView: View {
    let badge: SubagentBadge

    var body: some View {
        Text("\(badge.count)")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(
                badge.wantsAttention
                    ? NotchPalette.onBrightGround
                    : NotchPalette.label
            )
            .frame(
                width: PanelMetrics.subagentBadgeWidth(badge.count),
                height: PanelMetrics.subagentBadgeMinSize
            )
            .background(
                RoundedRectangle(
                    cornerRadius: PanelMetrics.subagentBadgeCornerRadius,
                    style: .continuous
                )
                .fill(groundFill)
            )
            // Spoken by the row or panel header; alone it is a bare number.
            .accessibilityHidden(true)
    }

    /// Dim while all are running, ``NotchPalette/brightGround`` once one is stopped on a question,
    /// matching the waiting row's mark. The dim end is ``NotchPalette/MatrixInk/chipFill``, always
    /// lifted off black.
    private var groundFill: Color {
        guard badge.wantsAttention else {
            return NotchPalette.restingInk.chipFill
        }
        return NotchPalette.brightGround
    }
}

/// The ground an elapsed reading sits on (`figma-design.md` page 14): the
/// ``SubagentBadgeView`` tile at reading width. The collapsed bar keeps it `.clear` for the
/// room alone.
struct ReadingGround<Content: View>: View {
    /// `.clear` is a drawn state: the collapsed bar bills its width for the padding.
    let fill: Color
    var width: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, PanelMetrics.readingGroundPadding)
            .frame(width: width, height: PanelMetrics.readingGroundHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: PanelMetrics.readingGroundCornerRadius,
                    style: .continuous
                )
                .fill(fill)
            )
    }
}

enum SessionDotBreath {
    /// Slower than every track in ``MatrixTrack``; pinned by
    /// `theBreathIsSlowerThanAnythingTheMatrixRuns`.
    static let period: TimeInterval = 2.8

    /// Full: the ceiling comes from the ink, ``NotchPalette/finishedDotDrawingColor``
    /// (`#C7C7CC`), so each crest equals the sessions numeral.
    static let restingOpacity: Double = 1.0

    /// The bottom of the swing: `0.55` of amplitude (`0.35` was too quiet). Momentary, so legible;
    /// must stay brighter than the extinguished matrix. Pinned by
    /// `theBreathsFloorStaysAboveTheMarkItStandsBeside`.
    static let floorOpacity: Double = 0.45

    /// Not `easeInEaseOut`, which parks at both turns: never slower than a third of the average
    /// rate, and `y1 / x1` = `(1 - y2) / (1 - x2)` keeps fall and rise symmetric. Pinned by
    /// `theBreathNeverParksAtEitherTurn`.
    static let timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.1, 0.7, 0.9)

    /// The loop, starting on the next whole beat of the layer clock: shared phase with
    /// ``MatrixIndicatorView/phaseAnchor(for:now:)`` and the searchlight
    /// (``NotchTextRaster/installSweep(on:across:height:period:)``), and it starts at
    /// ``restingOpacity``, where the mark already is.
    static func animation(now: CFTimeInterval = CACurrentMediaTime()) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = restingOpacity
        animation.toValue = floorOpacity
        // Autoreversed: one curve for fall and rise.
        animation.duration = period / 2
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = timingFunction
        animation.beginTime = beginTime(now: now)
        animation.isRemovedOnCompletion = false
        return animation
    }

    static func beginTime(now: CFTimeInterval = CACurrentMediaTime()) -> CFTimeInterval {
        MatrixIndicatorView.phaseAnchor(for: period, now: now) + period
    }
}

/// How the middle hands one Project name to the next: the leaving name shrinks to ``scale``
/// and the arriving one opens out from it.
///
/// Not a cross-fade like ``MatrixDissolve``: two words at half ink collide. The halves are
/// offset so the most ink both carry at once is about `13%` each (`#1a1a1a`). Pinned by
/// `neitherNameHoldsTheMiddleWhileTheOtherIsStillInIt`.
enum ProjectNameHandover {
    /// Shrink before leaving and size to resume at. `0.80` read as a zoom; `0.95` left a short name
    /// nothing to move.
    static let scale: CGFloat = 0.90

    static let leavingDuration: TimeInterval = 0.16

    /// Past the leaving name's midpoint and before its end: a `60 ms` overlap, both under `13%`.
    static let arrivingDelay: TimeInterval = 0.10

    /// Slower than the leave, like every arrival on this surface (``PanelMotion/fade(isArriving:)``).
    static let arrivingDuration: TimeInterval = 0.24

    /// End to end `0.34 s`, against the `5 s` a name is held.
    static var duration: TimeInterval { arrivingDelay + arrivingDuration }

    /// Symmetric: the name starts from rest, and over `0.16 s` the slow tail is too brief to see.
    static let leavingTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

    /// Not ``PanelMotion``'s `(0.22, 1, 0.36, 1)`: `96%` across at its midpoint, it would reach full
    /// size inside `80 ms` and leave no visible expansion.
    static let arrivingTimingFunction = CAMediaTimingFunction(name: .easeOut)

    /// The name leaving: in towards its own middle, and out.
    ///
    /// Starts from the name's current opacity and scale, not full, so a second change inside one
    /// handover does not jump it back (as ``MatrixIndicatorView/crossFade(from:to:)``).
    static func leaving(fromOpacity: Float, fromScale: CGFloat) -> CAAnimationGroup {
        let ink = CABasicAnimation(keyPath: "opacity")
        ink.fromValue = fromOpacity
        ink.toValue = 0
        let size = CABasicAnimation(keyPath: "transform.scale")
        size.fromValue = fromScale
        size.toValue = scale
        return group(of: [ink, size], over: leavingDuration, on: leavingTimingFunction)
    }

    static func arriving(now: CFTimeInterval = CACurrentMediaTime()) -> CAAnimationGroup {
        let ink = CABasicAnimation(keyPath: "opacity")
        ink.fromValue = 0
        ink.toValue = 1
        let size = CABasicAnimation(keyPath: "transform.scale")
        size.fromValue = scale
        size.toValue = 1
        let arriving = group(of: [ink, size], over: arrivingDuration, on: arrivingTimingFunction)
        arriving.beginTime = now + arrivingDelay
        // Held at start values through the delay, or the new name shows at full ink first.
        arriving.fillMode = .backwards
        return arriving
    }

    /// The curve goes on each channel, not the group: a group's timing function warps its
    /// children's clock, so both would compose two curves.
    private static func group(
        of animations: [CABasicAnimation],
        over duration: TimeInterval,
        on timing: CAMediaTimingFunction
    ) -> CAAnimationGroup {
        for animation in animations {
            animation.duration = duration
            animation.timingFunction = timing
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        return group
    }
}

/// The pill's middle: the name of the work, the Project (`compact-view-v2.md` §6.2).
///
/// Cycles `5 s` each; the clock does not follow it and stays the longest unfinished turn.
/// Known weakness: the name beside an urgent mark may be a Project that is not the one waiting.
struct RotatingProjectName: View {
    /// Every Project with an active row, in panel order, deduplicated, first occurrence winning.
    let names: [String]
    /// What `230` has left once the anchored ends are taken out.
    let width: CGFloat

    var body: some View {
        ProjectNameMarquee(names: names, width: width)
            .frame(width: width, height: PanelMetrics.readingGroundHeight)
            // The panel's own label speaks the whole list.
            .accessibilityHidden(true)
    }
}

private struct ProjectNameMarquee: NSViewRepresentable {
    let names: [String]
    let width: CGFloat

    func makeNSView(context: Context) -> ProjectNameView {
        let view = ProjectNameView()
        view.apply(names: names, width: width)
        return view
    }

    func updateNSView(_ nsView: ProjectNameView, context: Context) {
        nsView.apply(names: names, width: width)
    }

    static func dismantleNSView(_ nsView: ProjectNameView, coordinator: ()) {
        nsView.stop()
    }
}

/// The name on a layer, rotated off its own timer so the overlay never re-renders for it
/// (`AGENTS.md` §7).
///
/// Two layers because the halves move in opposite directions: a transform on one layer would
/// scale old and new together (``ProjectNameHandover``).
final class ProjectNameView: NSView {
    private let ink = CALayer()
    /// Empty and unlit except during a handover.
    private let departing = CALayer()
    private let fade = CAGradientLayer()

    private var names: [String] = []
    private var width: CGFloat = 0
    private var index = 0
    private var timer: Timer?
    /// The glyph box last rasterised, which ``layoutInk()`` centres.
    private var renderedSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        for glyphs in [departing, ink] {
            glyphs.contentsGravity = .bottomLeft
            // Anchored mid-glyph-box so the name recedes into itself; the handover depends on it.
            glyphs.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.addSublayer(glyphs)
        }
        departing.opacity = 0
        // Trailing fade mask: opaque except the last `12`.
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 0)]
        layer?.mask = fade
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit { timer?.invalidate() }

    func apply(names: [String], width: CGFloat) {
        let previous = currentName
        self.names = names
        self.width = width
        // A change in the set keeps the current name's slot; only a removed name moves anything.
        if let previous, let kept = names.firstIndex(of: previous) {
            index = kept
        } else if index >= names.count {
            index = 0
        }
        // One Project does not cycle. None draws nothing.
        if names.count > 1 { start() } else { stop() }
        redraw(handingOver: currentName != previous)
        layoutFade()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    override func layout() {
        super.layout()
        layoutInk()
        layoutFade()
    }

    private var currentName: String? {
        names.indices.contains(index) ? names[index] : nil
    }

    private func start() {
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(
            withTimeInterval: PanelMetrics.projectNameInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        // Common modes, or the name freezes behind a tracking menu.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func advance() {
        guard names.count > 1 else { return }
        index = (index + 1) % names.count
        redraw(handingOver: true)
    }

    private func redraw(handingOver: Bool) {
        let scale = window?.backingScaleFactor ?? 2
        // Hand over first, even with no next name, so the last Project fades out rather than blinking off.
        if handingOver { handOver() }
        guard let name = currentName else {
            ink.contents = nil
            renderedSize = .zero
            layoutInk()
            return
        }
        let font = PanelMetrics.projectNameFont
        let size = NotchTextRaster.textSize(name, font: font)
        let image = NotchTextRaster.glyphImage(
            text: name,
            font: font,
            color: NotchPalette.countsSessionDrawingColor,
            size: size,
            scale: scale
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ink.contentsScale = scale
        ink.contents = image
        CATransaction.commit()
        renderedSize = size
        layoutInk()
        if handingOver {
            ink.add(ProjectNameHandover.arriving(), forKey: Self.arrivingKey)
        }
    }

    /// Moves the on-screen name to the departing layer so the two halves can move against each other.
    ///
    /// Starts from the departing name's current values; anything already departing is dropped.
    private func handOver() {
        guard ink.contents != nil else { return }
        let shown = ink.presentation()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        departing.contents = ink.contents
        departing.contentsScale = ink.contentsScale
        // Its own geometry, not the new name's width: it leaves from where it stood.
        departing.bounds = ink.bounds
        departing.position = ink.position
        CATransaction.commit()
        departing.add(
            ProjectNameHandover.leaving(
                fromOpacity: shown?.opacity ?? ink.opacity,
                fromScale: shown.map { $0.transform.m11 } ?? 1
            ),
            forKey: Self.leavingKey
        )
    }

    /// The glyphs, centred in the slot.
    ///
    /// Runs on every layout: `makeNSView` and its first update see zero `bounds`, and centring only
    /// there sank a single Project's name `8` pt under the mask. The raster still runs only on change.
    private func layoutInk() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ink.frame = CGRect(
            x: 0,
            y: (bounds.height - renderedSize.height) / 2,
            width: renderedSize.width,
            height: renderedSize.height
        )
        CATransaction.commit()
    }

    private func layoutFade() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        let fadeWidth = PanelMetrics.projectNameFadeWidth
        let start = bounds.width > fadeWidth ? (bounds.width - fadeWidth) / bounds.width : 0
        fade.locations = [0, NSNumber(value: Double(start)), 1]
        CATransaction.commit()
    }

    /// Exposed for tests.
    var nameLayer: CALayer { ink }
    var departingNameLayer: CALayer { departing }
    var arrivingAnimation: CAAnimation? { ink.animation(forKey: Self.arrivingKey) }
    var leavingAnimation: CAAnimation? { departing.animation(forKey: Self.leavingKey) }
    var isCycling: Bool { timer != nil }
    var drawnName: String? { currentName }

    static let arrivingKey = "notch.projectName.arriving"
    static let leavingKey = "notch.projectName.leaving"
}

/// The collapsed surface's counts: sessions over subagents, inside one matrix's height.
///
/// Anchored to the matrix's edges (sessions cap-top on top, subagents baseline on bottom), so the
/// column is ``PanelMetrics/statusMatrixSize`` tall under any menu bar height
/// (`compact-view-v2.md` §3.1). Not per product; hierarchy is size and brightness, never hue
/// (§3.2).
struct CountsColumn: View {
    /// The whole monitored list: the bar's and the band's totals are one figure.
    let sessionCount: Int
    /// Subagents in flight, or `nil` for no lower row (one numeral, centred). Never zero.
    let subagentCount: Int?
    let matrixSize: CGFloat
    /// Holds the column at two digits. The pill only (`compact-view-v2.md` §6.1): it is centred and
    /// fixed-width; the notched bar hugs.
    var reservesTwoDigits = false

    var body: some View {
        CountsNumerals(
            sessionCount: sessionCount,
            subagentCount: subagentCount,
            matrixSize: matrixSize
        )
        .frame(width: digitsWidth, height: matrixSize, alignment: .leading)
        // `offset` moves the drawing, not the layout, so the slot can open under still numerals
        // (as ``SessionCountDots``).
        .offset(x: PanelMetrics.aggregateCountsGap)
        .frame(width: slotWidth, alignment: .leading)
        .animation(PanelMotion.slot(isOpening: sessionCount > 0), value: slotWidth)
        .accessibilityHidden(true)
    }

    /// The room taken out of the wing, gap included. No rows is no column (§3.2 rule 03), except on
    /// the pill.
    private var slotWidth: CGFloat {
        PanelMetrics.countsSlotWidth(
            sessionCount: sessionCount,
            reserved: reservesTwoDigits
        )
    }

    private var digitsWidth: CGFloat {
        reservesTwoDigits
            ? PanelMetrics.reservedCountsColumnWidth
            : PanelMetrics.countsColumnWidth(sessionCount: sessionCount)
    }
}

private struct CountsNumerals: NSViewRepresentable {
    let sessionCount: Int
    let subagentCount: Int?
    let matrixSize: CGFloat

    func makeNSView(context: Context) -> CountsNumeralsView {
        let view = CountsNumeralsView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: CountsNumeralsView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: CountsNumeralsView) {
        view.apply(
            sessionCount: sessionCount,
            subagentCount: subagentCount,
            matrixSize: matrixSize
        )
    }
}

/// The two numerals, on two layers.
///
/// Layer-backed for exact baseline placement on the matrix's edges
/// (``NotchTextRaster/glyphImage(text:font:color:size:scale:)`` draws the line box bottom at the
/// origin) and so each numeral animates independently without re-rendering the overlay. Both
/// movements end; nothing ticks (`AGENTS.md` §7).
final class CountsNumeralsView: NSView {
    private let sessions = CALayer()
    private let subagents = CALayer()

    private var sessionCount = 0
    private var subagentCount: Int?
    private var matrixSize: CGFloat = 0
    private var hasApplied = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // The subagent baseline is the bottom edge, so descenders fall outside bounds by design.
        layer?.masksToBounds = false
        for numeral in [sessions, subagents] {
            numeral.contentsGravity = .bottomLeft
            numeral.opacity = 0
            layer?.addSublayer(numeral)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(
        sessionCount: Int,
        subagentCount: Int?,
        matrixSize: CGFloat
    ) {
        // Only the lower row's presence moves the numeral above it.
        let rises = (self.subagentCount != nil) != (subagentCount != nil)
        self.sessionCount = sessionCount
        self.subagentCount = subagentCount
        self.matrixSize = matrixSize
        // The first application places without animating.
        let animates = hasApplied
        hasApplied = true
        redraw(animatingRise: rises && animates, animatingFade: animates)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        redraw(animatingRise: false, animatingFade: false)
    }

    private func redraw(animatingRise: Bool, animatingFade: Bool) {
        let scale = window?.backingScaleFactor ?? 2
        place(
            sessions,
            text: sessionCount > 0 ? "\(sessionCount)" : nil,
            font: PanelMetrics.countsSessionFont,
            colour: NotchPalette.countsSessionDrawingColor,
            baseline: PanelMetrics.countsSessionBaseline(
                hasSubagents: subagentCount != nil,
                matrixSize: matrixSize
            ),
            scale: scale,
            animatingPosition: animatingRise,
            animatingFade: animatingFade
        )
        place(
            subagents,
            // Never a subagent numeral with no sessions above it.
            text: sessionCount > 0 ? subagentCount.map(String.init) : nil,
            font: PanelMetrics.countsSubagentFont,
            colour: NotchPalette.labelDrawingColor,
            baseline: PanelMetrics.countsSubagentBaseline,
            scale: scale,
            animatingPosition: false,
            animatingFade: animatingFade
        )
    }

    /// `baseline` is measured up from the column's bottom edge; the descender converts it to the
    /// layer's glyph-box frame.
    private func place(
        _ numeral: CALayer,
        text: String?,
        font: NSFont,
        colour: NSColor,
        baseline: CGFloat,
        scale: CGFloat,
        animatingPosition: Bool,
        animatingFade: Bool
    ) {
        guard let text else {
            fade(numeral, to: 0, animated: animatingFade)
            return
        }
        let size = NotchTextRaster.textSize(text, font: font)
        let frame = CGRect(
            x: 0,
            y: baseline + font.descender,
            width: size.width,
            height: size.height
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        numeral.contentsScale = scale
        numeral.contents = NotchTextRaster.glyphImage(
            text: text,
            font: font,
            color: colour,
            size: size,
            scale: scale
        )
        if !animatingPosition || numeral.opacity == 0 {
            numeral.frame = frame
        }
        CATransaction.commit()

        if animatingPosition, numeral.opacity != 0, numeral.frame != frame {
            CATransaction.begin()
            CATransaction.setAnimationDuration(PanelMotion.duration)
            CATransaction.setAnimationTimingFunction(PanelMotion.timingFunction)
            numeral.frame = frame
            CATransaction.commit()
        }
        fade(numeral, to: 1, animated: animatingFade)
    }

    private func fade(_ numeral: CALayer, to opacity: Float, animated: Bool) {
        guard numeral.opacity != opacity else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated {
            CATransaction.setAnimationDuration(PanelMotion.duration)
            CATransaction.setAnimationTimingFunction(PanelMotion.timingFunction)
        }
        numeral.opacity = opacity
        CATransaction.commit()
    }
}

/// The finished-turn mark: `4` points of `#C7C7CC` in front of the reading, on the notch and on a
/// row (`compact-view-v2.md` §4.3).
///
/// - Replaces a filled ground behind the digits: one meaning, one mark.
/// - Breathes on the notch, still on a row, where a pulse per row would move the list
///   (`AGENTS.md` §7).
/// - Crest never exceeds the sessions numeral (``SessionDotBreath/restingOpacity``); fixed `4`
///   slot, so the wing's width never changes.
struct FinishedTurnDot: View {
    var breathes = true

    var body: some View {
        Group {
            if breathes {
                BreathingDot()
            } else {
                Circle().fill(NotchPalette.finishedDot)
            }
        }
        .frame(
            width: PanelMetrics.buriedFinishDotSize,
            height: PanelMetrics.buriedFinishDotSize
        )
        // Spoken by the row's status and `MonitorStore.spokenBuriedCompletionText`.
        .accessibilityHidden(true)
    }
}

private struct BreathingDot: NSViewRepresentable {
    func makeNSView(context: Context) -> BreathingDotView { BreathingDotView() }
    func updateNSView(_ nsView: BreathingDotView, context: Context) {}
}

/// On a layer, so the render server runs the loop and the overlay is not re-rendered
/// (`AGENTS.md` §7).
final class BreathingDotView: NSView {
    private let ink = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        ink.backgroundColor = NotchPalette.finishedDotDrawingColor.cgColor
        ink.opacity = Float(SessionDotBreath.restingOpacity)
        layer?.addSublayer(ink)
        // Installed once: the view exists only while the dot is shown.
        ink.add(SessionDotBreath.animation(), forKey: Self.breathKey)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ink.frame = bounds
        ink.cornerRadius = min(bounds.width, bounds.height) / 2
        CATransaction.commit()
    }

    var breathAnimation: CAAnimation? { ink.animation(forKey: Self.breathKey) }

    static let breathKey = "notch.buriedFinish.breath"
}

/// The mark's grid in design-file units: `27`-unit cells on a `32` pitch, `2` corner radius.
///
/// ``PanelMetrics/statusMatrixSize`` stays `16.6`, so at 5×5 the cell is `2.89` and the gap `0.54`
/// (about one device pixel). Patterns move whole rows, columns or the grid; none may rely on
/// resolving a single cell (isolated cells read as specks at `2.89`).
enum MatrixGrid {
    static let side = 5
    static let cellCount = side * side
    static let cell: CGFloat = 27
    static let pitch: CGFloat = 32
    static let cornerRadius: CGFloat = 2
    static let viewBox = CGFloat(side) * pitch - (pitch - cell)
}

/// What the 5×5 indicator is doing, independent of which status drove it.
///
/// Every non-session state reads as "inactive". Input and approval are separate patterns.
enum NotchMatrixState: Equatable {
    case running
    case inputNeeded
    case approvalNeeded
    case completed
    case inactive

    init(_ status: MonitorStatus) {
        switch status {
        case .running:
            self = .running
        case .inputNeeded:
            self = .inputNeeded
        case .approvalNeeded:
            self = .approvalNeeded
        case .completed:
            self = .completed
        case .connected, .connecting, .disconnected,
             .setupRequired, .updateAgent, .unsupportedVersion:
            self = .inactive
        }
    }

    /// Drives both the matrix animation and whether the label sweeps.
    var isActive: Bool {
        switch self {
        case .running, .inputNeeded, .approvalNeeded: true
        case .completed, .inactive: false
        }
    }

    /// Loop length, or `nil` for a still.
    ///
    /// The loom and the knock share `1.2`; Input is faster (`1`), Completed slowest (`2.4`). All must
    /// stay below the session column's `2.8` breath (`theBreathIsSlowerThanAnythingTheMatrixRuns`).
    var period: TimeInterval? {
        switch self {
        case .running, .approvalNeeded: 1.2
        case .inputNeeded: 1.0
        case .completed: 2.4
        case .inactive: nil
        }
    }
}

/// Per-cell opacity tracks, one per state: one waveform sampled per state plus a rule for how far
/// each cell lags it (the terrace holds five, one per column).
///
/// - Offsets are whole frames; each pattern's sample rate is chosen to make that exact.
/// - Loom, glide and terrace are stretched linearly to ``floor``…`1`, so a pattern cannot be
///   quietened at the ceiling; loudness is lit area, time at white and slew.
/// - The knock keeps its own `0.05` so Approval's silence stays darker than a resting mark
///   (`dual-agent-design.md` §2).
/// - A live mark always has a lit cell (the terrace's tall step never falls below `0.465`); a
///   still one never does. That, not the floor level, separates them from ``inactiveLevel``.
private enum MatrixTrack {
    /// The level the three normalised patterns rest at, and a mark with nothing behind it holds.
    /// `0.100` since 2026-09-07; at ``doubleKnock``'s `0.05` the still and Approval's silence would
    /// be indistinguishable.
    static let floor = 0.100

    /// Stretches tracks so the dimmest sample across all of them sits at `floor` and the brightest
    /// at `1`. Over the whole set at once, so rows of one pattern keep their relative levels.
    private static func stretched(_ tracks: [[Double]], floor: Double) -> [[Double]] {
        let samples = tracks.flatMap { $0 }
        guard let low = samples.min(), let high = samples.max(), high - low > 1e-9
        else { return tracks }
        let scale = (1 - floor) / (high - low)
        return tracks.map { $0.map { floor + ($0 - low) * scale } }
    }

    // MARK: Running — loom

    /// **Loom**, 48 frames over `1.2s`: the outer sixteen cells turn clockwise, the inner eight
    /// anticlockwise, about a still centre. 40fps so steps are whole frames (`3` outside, `6`
    /// inside). The lit arc is symmetric about the head.
    static let loom: (outer: [Double], inner: [Double], centre: Double) = {
        let frames = 48
        func ring(_ n: Int) -> [Double] {
            let step = Double(frames) / Double(n)
            return (0 ..< frames).map { frame in
                let moved = Double(frame) / step
                let gap = min(moved, Double(n) - moved)
                return 0.12 + 0.88 * exp(-gap / 1.5)
            }
        }
        // The pivot is stretched with the rings so it stays between the arc's floor and crest.
        let all = stretched([ring(16), ring(8), [0.42]], floor: floor)
        return (all[0], all[1], all[2][0])
    }()

    /// The 16 perimeter cells, clockwise from the top-left corner.
    static let outerRing = [0, 1, 2, 3, 4, 9, 14, 19, 24, 23, 22, 21, 20, 15, 10, 5]
    /// The 8 cells around the centre, clockwise from the top-left of them.
    static let innerRing = [6, 7, 8, 13, 18, 17, 16, 11]

    /// The inner offset is negative because that ring turns the other way.
    static func loomTrack(forCell index: Int) -> [Double] {
        if let i = outerRing.firstIndex(of: index) { return loom.outer.delayed(by: i * 3) }
        if let i = innerRing.firstIndex(of: index) { return loom.inner.delayed(by: -i * 6) }
        return [loom.centre]
    }

    // MARK: Input needed — glide

    /// **Glide**, 40 frames over `1s`: one upright rule crossing the grid, symmetric falloff, distance
    /// taken around the grid so nothing resets at the edge. This is column `0`'s curve.
    ///
    /// Symmetric so columns brighten gradually: a hard step (`34`/s) read as five strikes; this
    /// peaks at `8.9`/s. Cost: close to Running's loom (`7.2`) on level and area. If Input needs more
    /// separation, crossing in `0.8s` measures `12.5`.
    static let glide: [Double] = {
        let frames = 40, span = Double(MatrixGrid.side)
        let track = (0 ..< frames).map { frame -> Double in
            let behind = (Double(frame) / Double(frames) * span)
                .truncatingRemainder(dividingBy: span)
            let gap = min(behind, span - behind)
            return exp(-gap / 0.44)
        }
        return stretched([track], floor: floor)[0]
    }()

    /// `8` frames a column. No row term: a whole column brightens at once, legible at a `2.89` cell.
    static func glideOffset(column: Int) -> Int { column * 8 }

    // MARK: Approval needed — double knock

    /// **Double knock**, 36 frames over `1.2s`, every cell together: full twice `300ms` apart (3-frame
    /// time constant), then `900ms` at `0.05`, the darkest this surface goes. Already spans
    /// `0.05`…`1`, so it is not stretched.
    static let doubleKnock: [Double] = [
        1.000, 1.000, 0.731, 0.538, 0.399, 0.300, 0.229, 0.179,
        0.142, 1.000, 1.000, 0.731, 0.538, 0.399, 0.300, 0.229,
        0.179, 0.142, 0.116, 0.097, 0.084, 0.074, 0.067, 0.062,
        0.059, 0.056, 0.055, 0.053, 0.052, 0.052, 0.051, 0.051,
        0.051, 0.050, 0.050, 0.050
    ]

    // MARK: Completed — terrace

    /// **Terrace**, 72 frames over `2.4s`: the app's logo breathing. Column heights `5 4 3 2 1`
    /// (`row + column <= 4`) at levels `1.00 / .80 / .60 / .40 / .20`, `1.00 / .82 / .64 / .46 / .28`
    /// after the stretch.
    ///
    /// - The tall step falls only to `0.40` of its level (others `0.06`), so the dimmest frame holds a
    ///   cell at `0.465` and never reads as a still.
    /// - Uses the loom's periodic `exp(-(gap / tau)^p)`; a power-of-cosine crest flattened into
    ///   identical frames.
    /// - `9.90` cell-units of light at peak, so the crest is brief and the tail long: `3.8%` time at
    ///   white, edge `1.23`/s.
    /// - Hangs from the top edge, so a wrong `isFlipped` inverts it (`figma-design.md` §4.1).
    static let terrace: (columns: [[Double]], dark: Double) = {
        let frames = 72
        func column(_ index: Int) -> [Double] {
            // The logo's ladder across, and how far each column falls back between crests.
            let level = 1 - 0.2 * Double(index), rest = index == 0 ? 0.40 : 0.06
            return (0 ..< frames).map { frame in
                let gap = Double(min(frame, frames - frame))
                // `12` frames to `1/e` makes the crest brief; the exponent above `1` rounds it.
                return level * (rest + (1 - rest) * exp(-pow(gap / 12, 1.4)))
            }
        }
        // Off-mark cells are stretched with the figure, putting them at exactly `floor`.
        let all = stretched((0 ..< MatrixGrid.side).map(column) + [[0]], floor: floor)
        return (Array(all[0 ..< MatrixGrid.side]), all[MatrixGrid.side][0])
    }()

    /// One cell's terrace track: its column's curve unshifted, or the dark level off the mark.
    static func terraceTrack(forCell index: Int) -> [Double] {
        let row = index / MatrixGrid.side, column = index % MatrixGrid.side
        guard row + column <= MatrixGrid.side - 1 else { return [terrace.dark] }
        return terrace.columns[column]
    }

    // MARK: Nothing running

    /// Connected and disconnected hold still, at the live patterns' floor (never brighter), and still
    /// twice the knock's `0.05` silence.
    static let inactiveLevel = floor
}

private extension [Double] {
    /// The same loop, started `offset` frames later.
    func delayed(by offset: Int) -> [Double] {
        guard count > 1, offset % count != 0 else { return self }
        return indices.map { self[(($0 - offset) % count + count) % count] }
    }
}

extension NotchMatrixState {
    /// One cell's whole opacity track: the state's curve, delayed by the cell's grid offset.
    ///
    /// Handed to Core Animation as keyframes; ``MatrixIndicatorView/trackAnimation`` repeats the first
    /// frame so N+1 linear values span N intervals, matching the design file's cadence.
    func track(forCell index: Int) -> [Double] {
        switch self {
        case .running:
            return MatrixTrack.loomTrack(forCell: index)
        case .inputNeeded:
            return MatrixTrack.glide
                .delayed(by: MatrixTrack.glideOffset(column: index % MatrixGrid.side))
        case .approvalNeeded:
            return MatrixTrack.doubleKnock
        case .completed:
            return MatrixTrack.terraceTrack(forCell: index)
        case .inactive:
            return [MatrixTrack.inactiveLevel]
        }
    }
}

/// The 5×5 status matrix, sized by the caller to ``PanelMetrics/statusMatrixSize``.
///
/// Animates for every state but `inactive`, so it is drawn by Core Animation: a `TimelineView`
/// tick re-renders the whole overlay and measured 8% of a core.
struct NotchStatusMatrix: View {
    let state: NotchMatrixState
    let size: CGFloat
    var isAnimated = true
    /// Always passed, never chosen from a product: one mark stands for every product
    /// (`colour-v2.md` §1).
    var ink: NotchPalette.MatrixInk = NotchPalette.restingInk
    /// Plays from the first frame instead of joining the bar's shared phase
    /// (``MatrixIndicatorView/phaseAnchor(for:now:)``). For the Settings specimen, which has nothing
    /// to be in step with.
    var startsAtItsFirstFrame = false

    var body: some View {
        MatrixIndicator(
            state: state,
            size: size,
            isAnimated: isAnimated,
            ink: ink,
            startsAtItsFirstFrame: startsAtItsFirstFrame
        )
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct MatrixIndicator: NSViewRepresentable {
    let state: NotchMatrixState
    let size: CGFloat
    let isAnimated: Bool
    let ink: NotchPalette.MatrixInk
    let startsAtItsFirstFrame: Bool

    func makeNSView(context: Context) -> MatrixIndicatorView {
        MatrixIndicatorView()
    }

    func updateNSView(_ view: MatrixIndicatorView, context: Context) {
        view.apply(
            state: state,
            size: size,
            isAnimated: isAnimated,
            ink: ink,
            startsAtItsFirstFrame: startsAtItsFirstFrame
        )
    }
}

final class MatrixIndicatorView: NSView {
    /// One blur pass of the lit cells, or the sharp copy when `blur` is nil.
    private struct GlowPass {
        let blur: CGFloat?
        let opacity: Float
    }

    private var appliedState: NotchMatrixState?
    private var appliedSize: CGFloat = 0
    private var appliedIsAnimated = true
    private var appliedInk = NotchPalette.restingInk
    private var appliedStartsAtItsFirstFrame = false
    /// Compared by the next `apply` to decide whether to fade across.
    private var appliedDrawing: NotchMatrixState?
    /// Kept so a dissolve can keep drawing them while the next pattern comes up.
    private var litPasses: [CALayer] = []

    // Row 0 is the top row, as in the SVG.
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // The glow deliberately spills past the indicator's own bounds.
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(
        state: NotchMatrixState,
        size: CGFloat,
        isAnimated: Bool,
        ink: NotchPalette.MatrixInk,
        startsAtItsFirstFrame: Bool = false
    ) {
        guard state != appliedState
            || size != appliedSize
            || isAnimated != appliedIsAnimated
            || ink != appliedInk
            || startsAtItsFirstFrame != appliedStartsAtItsFirstFrame else {
            return
        }
        // A different drawing (size or ink) is a cut, not a dissolve.
        let sameMark = size == appliedSize && ink == appliedInk
        let wasDrawing = appliedDrawing

        appliedState = state
        appliedSize = size
        appliedIsAnimated = isAnimated
        appliedInk = ink
        appliedStartsAtItsFirstFrame = startsAtItsFirstFrame
        rebuild(dissolvingFrom: sameMark ? wasDrawing : nil)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // `contentsScale` is only knowable once there is a window to ask.
        rebuild()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        rebuild()
    }

    /// `previous` is `nil` when the rebuild should not be seen (window or backing-scale change) or the
    /// mark's drawing changed.
    private func rebuild(dissolvingFrom previous: NotchMatrixState? = nil) {
        guard let state = appliedState, appliedSize > 0, let root = layer else {
            return
        }

        // Capture the copies to fade out before anything is torn down.
        let outgoing = Self.dissolves(from: previous, to: state) ? litPasses : []
        appliedDrawing = state

        for sublayer in root.sublayers ?? []
        where !outgoing.contains(where: { $0 === sublayer }) {
            sublayer.removeFromSuperlayer()
        }

        // Proportions from the design file's viewBox via ``MatrixGrid``.
        let size = appliedSize
        let cell = size * MatrixGrid.cell / MatrixGrid.viewBox
        let radius = cell * MatrixGrid.cornerRadius / MatrixGrid.cell
        let pitch = size * MatrixGrid.pitch / MatrixGrid.viewBox
        // Three sigma of the widest pass; smaller bounds would clip the halo.
        let bleed = cell * 10.5 / 27 * 3
        let scale = window?.backingScaleFactor ?? 2
        // One clock reading so all twenty-five cells stay in phase.
        let now = CACurrentMediaTime()
        // A specimen starts at the clock; other marks join the bar's shared phase grid.
        let anchorsPhase = !appliedStartsAtItsFirstFrame

        func makeCell(_ colour: CGColor) -> CALayer {
            let layer = CALayer()
            layer.cornerRadius = radius
            layer.cornerCurve = .continuous
            layer.contentsScale = scale
            layer.backgroundColor = colour
            return layer
        }

        func pass(_ pass: GlowPass, ink: CGColor, animated: Bool) -> CALayer {
            let container = CALayer()
            container.frame = CGRect(
                x: -bleed,
                y: -bleed,
                width: size + bleed * 2,
                height: size + bleed * 2
            )
            container.masksToBounds = false
            container.contentsScale = scale
            container.opacity = pass.opacity
            if let blur = pass.blur,
               let filter = CIFilter(
                   name: "CIGaussianBlur",
                   parameters: [kCIInputRadiusKey: blur]
               ) {
                container.filters = [filter]
            }

            for index in 0 ..< MatrixGrid.cellCount {
                let cellLayer = makeCell(ink)
                cellLayer.frame = CGRect(
                    x: bleed + CGFloat(index % MatrixGrid.side) * pitch,
                    y: bleed + CGFloat(index / MatrixGrid.side) * pitch,
                    width: cell,
                    height: cell
                )

                let track = state.track(forCell: index)
                // The still the design file shows: every track's t=0 frame.
                cellLayer.opacity = Float(track.first ?? 1)
                if animated, let period = state.period, track.count > 1 {
                    cellLayer.add(
                        Self.trackAnimation(
                            track: track,
                            period: period,
                            now: now,
                            anchorsPhase: anchorsPhase
                        ),
                        forKey: "notch.matrix.opacity"
                    )
                }
                container.addSublayer(cellLayer)
            }
            return container
        }

        let unlit = appliedInk.offLayerColor
        let lit = appliedInk.onLayerColor

        // The unlit bed never animates, and goes beneath any outgoing lit copies.
        root.insertSublayer(
            pass(
                GlowPass(blur: nil, opacity: 1),
                ink: unlit,
                animated: false
            ),
            at: 0
        )

        // Three blurred copies reproduce the SVG's feGaussianBlur + feMerge passes; sharp copy on top.
        let glowPasses = [
            GlowPass(blur: cell * 10.5 / 27, opacity: 0.21),
            GlowPass(blur: cell * 5.6 / 27, opacity: 0.35),
            GlowPass(blur: cell * 2.1 / 27, opacity: 0.56),
            GlowPass(blur: nil, opacity: 1)
        ]
        litPasses = glowPasses.map { glowPass in
            let copy = pass(glowPass, ink: lit, animated: appliedIsAnimated)
            root.addSublayer(copy)
            return copy
        }

        guard !outgoing.isEmpty else { return }
        crossFade(from: outgoing, to: litPasses)
    }

    /// Whether a pattern change is crossed over rather than cut.
    ///
    /// Only changes to or from the still dissolve; a change between two live patterns cuts. The
    /// Settings specimen relies on both: a hue change is a different drawing and cuts, and its
    /// same-ink return to the still dissolves.
    static func dissolves(from previous: NotchMatrixState?, to next: NotchMatrixState) -> Bool {
        guard let previous, previous != next else { return false }
        return (previous == .inactive) != (next == .inactive)
    }

    /// Crosses one lit stack over another, then drops the old one.
    ///
    /// Both stacks keep running through the fade; the unlit bed never moves. Compositing reads a
    /// fraction of a percent above the average mid-fade. Length and curve are ``MatrixDissolve``'s,
    /// not the panel's.
    private func crossFade(from outgoing: [CALayer], to incoming: [CALayer]) {
        let duration = MatrixDissolve.duration
        let timing = MatrixDissolve.timingFunction

        func fade(_ layer: CALayer, from: Float, to: Float) {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = from
            animation.toValue = to
            animation.duration = duration
            animation.timingFunction = timing
            layer.opacity = to
            layer.add(animation, forKey: Self.dissolveAnimationKey)
        }

        for copy in incoming {
            fade(copy, from: 0, to: copy.opacity)
        }
        for copy in outgoing {
            // Fade from the presentation value, so two changes inside one dissolve do not jump back to full.
            fade(copy, from: copy.presentation()?.opacity ?? copy.opacity, to: 0)
        }

        // Dropped after the fade by a timer rather than a render-server completion callback.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            for copy in outgoing {
                copy.removeFromSuperlayer()
            }
        }
    }

    static let dissolveAnimationKey = "notch.matrix.dissolve"

    /// Phase comes from the clock, not the moment of installation.
    ///
    /// - `beginTime` anchors to the last whole multiple of the period, so marks in the same state
    ///   (or sharing a period: running and approval at `1.2`) stay in sync and a rebuild resumes
    ///   its phase. Same as ``NotchTextRaster/installSweep(on:width:period:)``.
    /// - The first frame is repeated at the end: linear keyframes spread N values over N-1
    ///   intervals, which would play too fast and cut from last to first (worst for the knock).
    /// - `anchorsPhase` false (a specimen) begins at `now`, the pattern's first frame.
    private static func trackAnimation(
        track: [Double],
        period: TimeInterval,
        now: CFTimeInterval,
        anchorsPhase: Bool = true
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = (track + [track[0]]).map { NSNumber(value: $0) }
        animation.duration = period
        animation.calculationMode = .linear
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.beginTime = anchorsPhase ? phaseAnchor(for: period, now: now) : now
        return animation
    }

    /// The most recent whole-period boundary. Cell layers use default timing, so their local time
    /// is `CACurrentMediaTime()`.
    static func phaseAnchor(
        for period: TimeInterval,
        now: CFTimeInterval = CACurrentMediaTime()
    ) -> CFTimeInterval {
        now - now.truncatingRemainder(dividingBy: period)
    }
}

/// Shared drawing for the surface's layer-backed labels, rasterised through AppKit text drawing
/// so they match SwiftUI labels beside them.
enum NotchTextRaster {
    /// A highlight band four times as wide as what it crosses, peaking at its centre. Alpha-only mask.
    static func makeSweepMask() -> CAGradientLayer {
        let mask = CAGradientLayer()
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        mask.colors = [
            CGColor(gray: 0, alpha: 0),
            CGColor(gray: 0, alpha: 0),
            CGColor(gray: 0, alpha: 1),
            CGColor(gray: 0, alpha: 0),
            CGColor(gray: 0, alpha: 0)
        ]
        mask.locations = [0, 0.40, 0.50, 0.60, 1]
        return mask
    }

    /// Slides `mask` across `width` on a linear loop, on the render server.
    static func installSweep(
        on mask: CAGradientLayer,
        across width: CGFloat,
        height: CGFloat,
        period: TimeInterval
    ) {
        mask.removeAnimation(forKey: sweepAnimationKey)
        guard width > 0 else { return }

        let band = max(width * 4, 1)
        mask.frame = CGRect(x: 0, y: 0, width: band, height: max(height, 1))

        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = -band
        animation.toValue = width
        animation.duration = period
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = false
        // Anchored to a whole-period grid: body text is replaced every few seconds, and restarting the
        // loop each time would never reach the peak (40% into the loop). Also keeps rows in phase.
        let now = CACurrentMediaTime()
        animation.beginTime = now - now.truncatingRemainder(dividingBy: period)
        mask.add(animation, forKey: sweepAnimationKey)
    }

    static let sweepAnimationKey = "notch.searchlight"

    static func textSize(_ text: String, font: NSFont) -> CGSize {
        let size = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    static func glyphImage(
        text: String,
        font: NSFont,
        color: NSColor,
        size: CGSize,
        scale: CGFloat
    ) -> CGImage? {
        let pixelWidth = Int((size.width * scale).rounded(.up))
        let pixelHeight = Int((size.height * scale).rounded(.up))
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(
            cgContext: context,
            flipped: false
        )
        (text as NSString).draw(
            at: .zero,
            withAttributes: [.font: font, .foregroundColor: color]
        )
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}

/// How a mark crosses between the still and a pattern.
///
/// Symmetric and long enough to have a visible middle. Not ``PanelMotion``'s curve: it covers
/// `83%` in the first `60 ms`, which reads as a cut.
enum MatrixDissolve {
    static let duration: TimeInterval = 0.32

    static let timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
}

/// The one curve this overlay opens, closes and hands text over on, in SwiftUI, AppKit window
/// resize and Core Animation forms. SwiftUI does not animate the window's geometry.
enum PanelMotion {
    static let duration: TimeInterval = 0.20

    static let animation = Animation.timingCurve(0.22, 1, 0.36, 1, duration: duration)

    static let timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)

    /// How long a closing slot waits, so its mark is mostly gone first (``slot(isOpening:)``).
    static let closingDelay: TimeInterval = 0.05

    /// Every horizontal movement the collapsed surface makes, including the panel's own edges.
    ///
    /// Opening leads; closing waits for the mark to go first. `SessionCountDots`, `StatusReadout`,
    /// `OverlayHeader` and `OverlayPanelController` must share this timing, or pushed content
    /// stops reading as pushed and the edge clips it. AppKit reads ``closingDelay`` and
    /// ``timingFunction`` directly.
    static func slot(isOpening: Bool) -> Animation {
        isOpening ? animation : animation.delay(closingDelay)
    }

    /// The same asymmetry in seconds, for the window frame.
    static func slotDelay(isOpening: Bool) -> TimeInterval {
        isOpening ? 0 : closingDelay
    }

    /// A mark arriving into a slot or leaving one: the session dot, a subagent badge, the collapsed
    /// elapsed reading.
    ///
    /// Trails ``slot(isOpening:)``, or the mark is at full ink before the slot (or the notched bar's
    /// edge) has made room. Leaving is quicker than arriving, which lets ``closingDelay`` be short.
    static func fade(isArriving: Bool) -> Animation {
        isArriving
            ? .easeOut(duration: fadeInDuration).delay(fadeInDelay)
            : .easeOut(duration: fadeOutDuration)
    }

    static let fadeInDelay: TimeInterval = 0.06
    static let fadeInDuration: TimeInterval = 0.12
    static let fadeOutDuration: TimeInterval = 0.08
}

/// A session row's title or preview: one line, faded where it runs past the row, never ellipsised.
///
/// Layer-backed: a `TimelineView` sweep cost ~7% of a core per row. Both masks live on the layer
/// (fade on the container, sweep on the bright copy); a SwiftUI `.mask` over an AppKit view is
/// not dependable.
struct SessionRowText: View {
    let text: String
    let font: NSFont
    let color: NSColor
    let lineHeight: CGFloat
    /// The row's body line only, while its turn is unfinished: the sweep says *live*, so it must not
    /// cross a finished answer.
    var sweeps = false

    var body: some View {
        SessionRowTextRepresentable(
            text: text,
            font: font,
            color: color,
            lineHeight: lineHeight,
            sweeps: sweeps
        )
        .frame(height: lineHeight)
    }
}

private struct SessionRowTextRepresentable: NSViewRepresentable {
    let text: String
    let font: NSFont
    let color: NSColor
    let lineHeight: CGFloat
    let sweeps: Bool

    func makeNSView(context: Context) -> SessionRowTextView {
        SessionRowTextView()
    }

    func updateNSView(_ view: SessionRowTextView, context: Context) {
        view.apply(text: text, font: font, color: color, sweeps: sweeps)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: SessionRowTextView,
        context: Context
    ) -> CGSize? {
        // Takes the offered width; glyphs overflow and fade rather than shrinking the row.
        CGSize(
            width: proposal.width ?? nsView.intrinsicContentSize.width,
            height: lineHeight
        )
    }
}

/// The bar a covered run is drawn as (`cover-the-words.md` §4), with the run's searchlight.
///
/// Layer-backed like ``SessionRowText``, even when not sweeping: no continuously running SwiftUI
/// animation in this overlay (`AGENTS.md` §7), and phase comes from
/// ``NotchTextRaster/installSweep(on:across:height:period:)``.
struct CoverBar: View {
    let length: CGFloat
    let lineHeight: CGFloat
    /// Body line only, as on the uncovered words: covering hides content, not the *live* reading.
    var sweeps = false

    var body: some View {
        CoverBarRepresentable(length: length, sweeps: sweeps)
            .frame(width: length, height: PanelMetrics.coverBarHeight)
            .frame(height: lineHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CoverBarRepresentable: NSViewRepresentable {
    let length: CGFloat
    let sweeps: Bool

    func makeNSView(context: Context) -> CoverBarView { CoverBarView() }

    func updateNSView(_ nsView: CoverBarView, context: Context) {
        nsView.apply(length: length, sweeps: sweeps)
    }
}

final class CoverBarView: NSView {
    private let baseLayer = CALayer()
    private let highlightLayer = CALayer()
    private let sweepMask = NotchTextRaster.makeSweepMask()
    private var appliedLength: CGFloat = 0
    private var appliedSweeps = false
    private var installedSweepWidth: CGFloat?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let radius = PanelMetrics.coverBarHeight / 2
        for bar in [baseLayer, highlightLayer] {
            bar.cornerRadius = radius
            bar.cornerCurve = .continuous
        }
        baseLayer.backgroundColor = NotchPalette.coverBarDrawingColor.cgColor
        // The crest is the bar's ink at full strength, the breathing dot's ceiling
        // (`compact-view-v2.md` §4.3).
        highlightLayer.backgroundColor = NotchPalette.label.opacity(1).cgColor
        highlightLayer.mask = sweepMask
        layer?.addSublayer(baseLayer)
        layer?.addSublayer(highlightLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Assertable without a running overlay; a cover that stopped sweeping would look exactly like a
    /// bar.
    var isSweeping: Bool {
        sweepMask.animation(forKey: NotchTextRaster.sweepAnimationKey) != nil
    }

    func apply(length: CGFloat, sweeps: Bool) {
        guard length != appliedLength || sweeps != appliedSweeps else { return }
        appliedLength = length
        appliedSweeps = sweeps
        highlightLayer.isHidden = !sweeps
        needsLayout = true
        layout()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let frame = CGRect(
            x: 0,
            y: 0,
            width: appliedLength,
            height: PanelMetrics.coverBarHeight
        )
        baseLayer.frame = frame
        highlightLayer.frame = frame

        if appliedSweeps {
            // Bounded to the bar, so it reinstalls only when the length changes.
            if appliedLength != installedSweepWidth {
                installedSweepWidth = appliedLength
                NotchTextRaster.installSweep(
                    on: sweepMask,
                    across: appliedLength,
                    height: PanelMetrics.coverBarHeight,
                    period: SessionRowTextView.sweepPeriod
                )
            }
        } else {
            installedSweepWidth = nil
            sweepMask.removeAnimation(forKey: NotchTextRaster.sweepAnimationKey)
        }

        CATransaction.commit()
    }
}

final class SessionRowTextView: NSView {
    /// One traverse, the notch label's own.
    static let sweepPeriod: TimeInterval = 2
    /// Shared with the retired row, which draws the same fade differently
    /// (``PanelMetrics/rowTrailingFadeWidth``).
    private static let trailingFadeWidth: CGFloat = PanelMetrics.rowTrailingFadeWidth

    private let baseLayer = CALayer()
    private let highlightLayer = CALayer()
    private let sweepMask = NotchTextRaster.makeSweepMask()
    private let fadeMask = CAGradientLayer()
    private var appliedText = ""
    private var appliedFont = NSFont.systemFont(ofSize: 13, weight: .light)
    private var appliedColor = NSColor.white
    private var appliedSweeps = false
    private var renderedScale: CGFloat = 0
    /// The natural text size clipped to the row; anything beyond is an invisible texture upload.
    private var renderedGlyphSize: CGSize = .zero
    /// Kept so an unchanged sweep is not rebuilt on every text update.
    private var installedSweepWidth: CGFloat?
    private var installedSweepHeight: CGFloat?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        fadeMask.colors = [
            CGColor(gray: 0, alpha: 1),
            CGColor(gray: 0, alpha: 1),
            CGColor(gray: 0, alpha: 0)
        ]

        highlightLayer.mask = sweepMask
        layer?.addSublayer(baseLayer)
        layer?.addSublayer(highlightLayer)
        // Sized to the row, so it clips the overflow as well as fading it.
        layer?.mask = fadeMask
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NotchTextRaster.textSize(appliedText, font: appliedFont)
    }

    func apply(text: String, font: NSFont, color: NSColor, sweeps: Bool) {
        let textChanged = text != appliedText
            || font != appliedFont
            || color != appliedColor
        guard textChanged || sweeps != appliedSweeps else { return }

        appliedText = text
        appliedFont = font
        appliedColor = color
        appliedSweeps = sweeps

        if textChanged {
            // No `invalidateIntrinsicContentSize`: the view always takes the offered width, and invalidating
            // re-lays-out the subtree per row on every body-text update.
            renderedScale = 0
            renderedGlyphSize = .zero
            redrawGlyphs()
        }
        highlightLayer.isHidden = !sweeps
        layout()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        redrawGlyphs()
        layout()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        redrawGlyphs()
    }

    override func layout() {
        super.layout()
        // No implicit animation: the panel resizes, and CA would drag the glyphs after it.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // The clip depends on the row's width, so a resize has to re-draw.
        redrawGlyphs()
        let glyphs = renderedGlyphSize
        // Left-aligned at the top of the line box.
        let glyphFrame = CGRect(
            x: 0,
            y: 0,
            width: glyphs.width,
            height: glyphs.height
        )
        baseLayer.frame = glyphFrame
        highlightLayer.frame = glyphFrame

        fadeMask.frame = bounds
        let width = max(bounds.width, 1)
        let fadeStart = max(0, width - Self.trailingFadeWidth) / width
        fadeMask.locations = [0, NSNumber(value: fadeStart), 1]

        if appliedSweeps {
            // Bounded to the visible width: a 240-character line spans three rows' width, and a band scaled
            // to the glyphs flickers for 0.13s every two seconds. Also lets the reinstall be skipped.
            let sweepWidth = min(glyphs.width, bounds.width)
            let sweepHeight = glyphs.height
            if sweepWidth != installedSweepWidth
                || sweepHeight != installedSweepHeight
                || sweepMask.animation(
                    forKey: NotchTextRaster.sweepAnimationKey
                ) == nil {
                installedSweepWidth = sweepWidth
                installedSweepHeight = sweepHeight
                NotchTextRaster.installSweep(
                    on: sweepMask,
                    across: sweepWidth,
                    height: sweepHeight,
                    period: Self.sweepPeriod
                )
            }
        } else {
            installedSweepWidth = nil
            installedSweepHeight = nil
            sweepMask.removeAnimation(forKey: NotchTextRaster.sweepAnimationKey)
        }

        CATransaction.commit()
    }

    private func redrawGlyphs() {
        let scale = window?.backingScaleFactor ?? 2
        // Disable the implicit `contents` cross-fade; fades outliving frequent updates smear.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard !appliedText.isEmpty else {
            baseLayer.contents = nil
            highlightLayer.contents = nil
            renderedGlyphSize = .zero
            return
        }

        // Only what the row can show: the rest is behind the fade and would be a wasted texture upload.
        let natural = NotchTextRaster.textSize(appliedText, font: appliedFont)
        let size = bounds.width > 0
            ? CGSize(width: min(natural.width, bounds.width), height: natural.height)
            : natural
        guard scale != renderedScale || size != renderedGlyphSize else { return }
        renderedScale = scale
        renderedGlyphSize = size

        baseLayer.contentsScale = scale
        baseLayer.contents = NotchTextRaster.glyphImage(
            text: appliedText,
            font: appliedFont,
            color: appliedColor,
            size: size,
            scale: scale
        )
        // Drawn even when not sweeping, so a state change costs no texture upload.
        highlightLayer.contentsScale = scale
        highlightLayer.contents = NotchTextRaster.glyphImage(
            text: appliedText,
            font: appliedFont,
            color: NotchPalette.spotlightDrawingColor,
            size: size,
            scale: scale
        )
    }
}
