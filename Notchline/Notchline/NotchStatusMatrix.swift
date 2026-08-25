import AppKit
import Combine
import CoreImage
import SwiftUI

/// Colours the notch surface owns, mirroring the Figma variables of the same name.
enum NotchPalette {
    // The matrix draws through Core Animation, which needs CGColor, while the
    // rest of the surface is SwiftUI. Both come from these components so the two
    // representations cannot drift apart.
    private static let matrixOffRGB = (red: 0.063, green: 0.106, blue: 0.149)
    private static let matrixOnRGB = (red: 0.424, green: 0.706, blue: 1.0)
    private static let labelRGB = (red: 0.486, green: 0.486, blue: 0.502)

    /// One matrix's two colours.
    ///
    /// Hue says which product, brightness says whether it wants the user, and
    /// the two channels never swap jobs. Presence is the third channel and it
    /// is carried by the mark's *existence* rather than by any colour here.
    nonisolated struct MatrixInk: Equatable, Sendable {
        let offRed, offGreen, offBlue: Double
        let onRed, onGreen, onBlue: Double

        var off: Color { Color(red: offRed, green: offGreen, blue: offBlue) }
        var on: Color { Color(red: onRed, green: onGreen, blue: onBlue) }
        /// The spent end of a quota rule.
        ///
        /// A rule is 3pt tall where a matrix cell is a whole dot, and at that
        /// thickness the unlit colour all but vanishes against the panel --
        /// the spent share stops being readable as a share at all. So it sits
        /// one step up the same ramp, a quarter of the lit colour rather than
        /// the matrix's 15%: still plainly the dim end, still the product's
        /// hue, but visible. Nothing else on the surface uses it, so the
        /// matrix keeps the darkness it wants.
        var spent: Color {
            Color(
                red: offRed + Self.spentLift * (onRed - offRed),
                green: offGreen + Self.spentLift * (onGreen - offGreen),
                blue: offBlue + Self.spentLift * (onBlue - offBlue)
            )
        }
        /// How far ``spent`` travels from unlit towards lit.
        private static let spentLift = 0.12
        var offLayerColor: CGColor {
            CGColor(srgbRed: offRed, green: offGreen, blue: offBlue, alpha: 1)
        }
        var onLayerColor: CGColor {
            CGColor(srgbRed: onRed, green: onGreen, blue: onBlue, alpha: 1)
        }
    }

    /// Codex blue. `#101B26` unlit, `#6CB4FF` lit.
    static let codexInk = MatrixInk(
        offRed: matrixOffRGB.red,
        offGreen: matrixOffRGB.green,
        offBlue: matrixOffRGB.blue,
        onRed: matrixOnRGB.red,
        onGreen: matrixOnRGB.green,
        onBlue: matrixOnRGB.blue
    )

    /// Claude Code terracotta. `#21120D` unlit, `#D97757` lit.
    ///
    /// The unlit colour keeps the same 15% relationship to the lit one that
    /// Codex's pair has, so "dim" reads identically across products and only
    /// the hue tells them apart.
    static let claudeCodeInk = MatrixInk(
        offRed: 0x21 / 255, offGreen: 0x12 / 255, offBlue: 0x0D / 255,
        onRed: 0xD9 / 255, onGreen: 0x77 / 255, onBlue: 0x57 / 255
    )

    /// The resting mark, for when no product is there to own one.
    ///
    /// Grey is not a fourth product colour, and it is the darkest thing on the
    /// surface: `#151515` is the brightest neutral still at or below both
    /// products' unlit luminance (`0.0075` against `#21120D`'s `0.0079` and
    /// `#101B26`'s `0.0104`). That ordering is the point — "an agent is
    /// connected" must never look dimmer than "nothing is connected".
    ///
    /// Lit and unlit are the same colour because this mark cannot light: with
    /// nothing connected there is nothing that could be running.
    static let restingInk = MatrixInk(
        offRed: 0x15 / 255, offGreen: 0x15 / 255, offBlue: 0x15 / 255,
        onRed: 0x15 / 255, onGreen: 0x15 / 255, onBlue: 0x15 / 255
    )

    /// Two inks in one matrix, cut on the mark's diagonal.
    ///
    /// The surface never draws this. Every mark on the notch belongs to exactly
    /// one product, because hue is how the user tells two marks apart, and a
    /// mark carrying both hues would answer that question with "both". It
    /// exists for the first-run legend, where one specimen per state has to
    /// stand for both products at once and drawing eight specimens would say
    /// that the pattern differs by product, which it does not.
    ///
    /// The cut runs from the lower-left corner to the upper-right one, Codex
    /// above and Claude Code below — the same seam the app's own mark has, so
    /// the legend reads as the icon rather than as a fifth state.
    nonisolated struct MatrixSplit: Equatable, Sendable {
        let above: MatrixInk
        let below: MatrixInk

        /// The pairing the icon uses: Codex leading, Claude Code trailing.
        static let products = MatrixSplit(above: codexInk, below: claudeCodeInk)
    }

    /// The ink for one product, or the resting grey when no product owns the mark.
    nonisolated static func ink(for agent: AgentKind?) -> MatrixInk {
        switch agent {
        case .codex: codexInk
        case .claudeCode: claudeCodeInk
        case nil: restingInk
        }
    }

    /// `text/notch-label` — the dim base every notch label sits at.
    static let label = Color(
        red: labelRGB.red,
        green: labelRGB.green,
        blue: labelRGB.blue
    )
    /// The optional edge around the whole surface (`figma-design.md` §8.4).
    ///
    /// Three quarters of ``label`` in every channel — `#5D5D60` against the
    /// running timer's `#7C7C80`. Derived rather than picked, so the edge
    /// cannot drift into a hue of its own: it is the same neutral the dimmest
    /// text on this surface uses, turned down until it stops being a mark and
    /// starts being a boundary. An edge is not information — it is there so
    /// the black has a shape on a dark wallpaper — and anything bright enough
    /// to read as a mark would be a third brightness on a surface that says
    /// everything with two.
    static let surfaceEdge = Color(
        red: labelRGB.red * edgeDimming,
        green: labelRGB.green * edgeDimming,
        blue: labelRGB.blue * edgeDimming
    )
    /// How far ``surfaceEdge`` is turned down from ``label``.
    ///
    /// Landed on by looking at it: `0.5` (`#3E3E40`) all but vanished on a
    /// wallpaper that was merely dim rather than black, and undimmed it read
    /// as a mark. This is the midpoint of those two.
    private static let edgeDimming = 0.75
    /// `text/notch-spotlight` — the searchlight highlight.
    static let spotlight = Color.white
    /// Unlit matrix cell.
    static let matrixOff = Color(
        red: matrixOffRGB.red,
        green: matrixOffRGB.green,
        blue: matrixOffRGB.blue
    )
    /// Lit matrix cell.
    static let matrixOn = Color(
        red: matrixOnRGB.red,
        green: matrixOnRGB.green,
        blue: matrixOnRGB.blue
    )
    /// Session title — the one element that stays bright.
    static let sessionTitle = Color.white.opacity(0.98)
    /// The subagent attention chip's numeral, drawn on ``spotlight`` white.
    ///
    /// `dual-agent-design.md` §10. Not ``label`` or pure black: the chip
    /// inverts the same way the row's own attention state already does
    /// elsewhere on this surface, and this is that inversion's dark end.
    static let chipOnLight = Color(red: 0.05, green: 0.05, blue: 0.06)

    static let matrixOffLayerColor = CGColor(
        srgbRed: matrixOffRGB.red,
        green: matrixOffRGB.green,
        blue: matrixOffRGB.blue,
        alpha: 1
    )
    static let matrixOnLayerColor = CGColor(
        srgbRed: matrixOnRGB.red,
        green: matrixOnRGB.green,
        blue: matrixOnRGB.blue,
        alpha: 1
    )

    /// Drawing colours for the layer-backed notch label.
    static let labelDrawingColor = NSColor(
        srgbRed: labelRGB.red,
        green: labelRGB.green,
        blue: labelRGB.blue,
        alpha: 1
    )
    static let spotlightDrawingColor = NSColor.white
    static let sessionTitleDrawingColor = NSColor.white.withAlphaComponent(0.98)
}

/// Elapsed time for a turn.
///
/// This is the *whole* indicator for an unfinished row — the state rides in the
/// colour and weight rather than a separate dot, so a row never shows two marks.
///
/// It advances itself from the store's tick and draws into a layer, rather than
/// reading a string the store republishes. A republish re-evaluates the entire
/// overlay for about 20ms, which for a readout that changes once a second came
/// to roughly 4% of a core for as long as a turn ran — or sat waiting on an
/// approval, where nothing else was happening at all.
struct ElapsedReadout: View {
    let startedAt: Date
    let tick: AnyPublisher<Date, Never>
    var tint: NSColor = NotchPalette.labelDrawingColor
    var weight: NSFont.Weight = .light
    /// Drawn immediately before the elapsed value, in the same raster.
    ///
    /// The collapsed surface puts the subagent count and the elapsed value in
    /// one slot, and they are one reading rather than two views: laid out as a
    /// stack, every tick would re-measure a `Text` beside this, and the width
    /// the panel is sized from would have to be composed from two measurements
    /// that could disagree. Empty everywhere else.
    var prefix: String = ""

    var body: some View {
        ElapsedReadoutRepresentable(
            startedAt: startedAt,
            tick: tick,
            tint: tint,
            weight: weight,
            prefix: prefix
        )
        // The panel and each row already speak their own elapsed value in a
        // spoken form; VoiceOver reads "12:34" as a time of day.
        .accessibilityHidden(true)
    }
}

private struct ElapsedReadoutRepresentable: NSViewRepresentable {
    let startedAt: Date
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
        // SwiftUI may measure before the first tick has been rendered. A
        // shortest-form reading is the right placeholder: every readout starts
        // at 0:00 and only ever grows from there.
        let placeholder = NotchTextRaster.textSize(prefix + "0:00", font: font)
        return NSSize(width: placeholder.width, height: placeholder.height)
    }

    func configure(
        startedAt: Date,
        tint: NSColor,
        weight: NSFont.Weight,
        prefix: String = "",
        tick: AnyPublisher<Date, Never>
    ) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: weight)
        let changed = startedAt != self.startedAt
            || tint != self.tint
            || font != self.font
            || prefix != self.prefix
        self.startedAt = startedAt
        self.tint = tint
        self.font = font
        self.prefix = prefix

        guard subscription == nil else {
            if changed { render(at: lastTick) }
            return
        }
        // The tick is a CurrentValueSubject, so subscribing delivers the current
        // instant straight away and the readout is never blank for a second.
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
        // Clamped for the same reason ``MonitorStore.readableNow`` clamps: the
        // shared tick advances once a second, so a readout configured for a turn
        // that started since the last one would draw an empty raster until the
        // next tick. `0:00` is what this readout's own placeholder width already
        // assumes every reading starts at.
        let elapsed = SessionElapsedFormatter.elapsed(
            since: startedAt,
            now: max(now, startedAt)
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
        // Width only moves when the digit count does, which is also when the
        // store bumps its layout revision, so SwiftUI re-measures in the same
        // turn rather than being asked to on every tick.
        renderedSize = size
        invalidateIntrinsicContentSize()
    }
}

/// The footer's separator, doubling as the quota meter.
///
/// It reuses the matrix palette so the two readouts on this surface read as one
/// system, and costs no vertical space — the rule was already there.
struct UsageMeter: View {
    /// 0–1 remaining, or nil when quota is unavailable.
    let fill: Double?
    var height: CGFloat = 3
    /// Whose rule this is. The footer carries one rule per product, so the rule
    /// takes the same hue as that product's matrix — the two readouts on this
    /// surface stay one system, and a rule is attributable at a glance.
    var ink: NotchPalette.MatrixInk = NotchPalette.codexInk

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(ink.spent)

                if let fill {
                    Capsule()
                        .fill(ink.on)
                        .frame(width: proxy.size.width * min(max(fill, 0), 1))
                        .shadow(color: ink.on.opacity(0.35), radius: 2)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Which colour a subagent numeral chip draws in.
///
/// `dual-agent-design.md` §10: hue on this chip only ever answers "can this
/// mark honestly speak for one product right now" — never "which state is
/// this". State is ``attention`` versus everything else, and it is answered
/// by which chip a count is drawn on, not by tint.
enum SubagentChipTint: Equatable {
    /// The attention chip's colour, always -- never product-tinted (rule 4).
    case attention
    /// The running chip's colour when it cannot honestly speak for one
    /// product: two products connected in the collapsed pill (rule 2), or an
    /// expanded row regardless of how many products are connected (rule 3) --
    /// the row already names its product elsewhere.
    case neutral
    /// The running chip's colour when exactly one product is connected in the
    /// collapsed pill (rule 1).
    case product(AgentKind)

    var fill: Color {
        switch self {
        case .attention: NotchPalette.spotlight
        case .neutral: NotchPalette.restingInk.off
        case .product(let agent): NotchPalette.ink(for: agent).off
        }
    }

    var text: Color {
        switch self {
        case .attention: NotchPalette.chipOnLight
        case .neutral: NotchPalette.label
        case .product(let agent): NotchPalette.ink(for: agent).on
        }
    }
}

/// One subagent numeral chip: a filled, rounded tile holding a bare count.
///
/// `dual-agent-design.md` §10. Sized to `PanelMetrics.subagentChipWidth`
/// explicitly rather than left to hug its own text: the collapsed pill's
/// width is composed from that same measurement, and a view free to size
/// itself independently could drift from it by a point SwiftUI's own text
/// layout and `NSString`'s measurement disagree on.
struct SubagentChip: View {
    let count: Int
    let tint: SubagentChipTint

    var body: some View {
        Text("\(count)")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint.text)
            .frame(
                width: PanelMetrics.subagentChipWidth(count),
                height: PanelMetrics.subagentChipMinSize
            )
            .background(
                RoundedRectangle(
                    cornerRadius: PanelMetrics.subagentChipCornerRadius,
                    style: .continuous
                )
                .fill(tint.fill)
            )
            // Spoken by the row or the panel header, which say what each
            // figure counts -- this mark alone is a bare number with colour
            // as its only label, which VoiceOver cannot read.
            .accessibilityHidden(true)
    }
}

/// The white-then-grey/tinted chip pair, wherever it is drawn.
///
/// `dual-agent-design.md` §10, rules 5–6. A chip whose count is zero is not
/// drawn at all -- see ``SubagentChipCounts`` -- and the attention chip always
/// leads when both are present.
struct SubagentChipCluster: View {
    let counts: SubagentChipCounts
    /// ``.neutral`` for a row always, and for the collapsed pill while two
    /// products are connected; ``.product(_:)`` only for the collapsed pill
    /// with exactly one product connected. Never ``.attention`` -- that tint
    /// belongs to the other chip alone.
    let runningTint: SubagentChipTint

    var body: some View {
        HStack(spacing: PanelMetrics.subagentChipSpacing) {
            if counts.attention > 0 {
                SubagentChip(count: counts.attention, tint: .attention)
            }
            if counts.running > 0 {
                SubagentChip(count: counts.running, tint: runningTint)
            }
        }
    }
}

/// What the 3×3 indicator is doing, independent of which status drove it.
///
/// Several statuses collapse onto one appearance: input and approval both read
/// as "needs attention", and every non-session state (connected, disconnected,
/// and the retired thin states the expanded panel still says) reads as
/// "inactive".
enum NotchMatrixState: Equatable {
    case running
    case needsAttention
    case completed
    case inactive

    init(_ status: MonitorStatus) {
        switch status {
        case .running:
            self = .running
        case .inputNeeded, .approvalNeeded:
            self = .needsAttention
        case .completed:
            self = .completed
        case .connected, .connecting, .disconnected,
             .setupRequired, .updateAgent, .unsupportedVersion:
            self = .inactive
        }
    }

    /// Whether anything is in flight. Drives both the matrix animation and
    /// whether the accompanying label sweeps.
    var isActive: Bool {
        self == .running || self == .needsAttention
    }

    /// Loop length, or `nil` when the state is a still.
    var period: TimeInterval? {
        switch self {
        case .running: 1.0
        case .needsAttention, .completed: 1.2
        case .inactive: nil
        }
    }
}

/// Per-cell opacity tracks, taken from the `<animate values="…">` lists in
/// `running.svg`, `need-approval.svg` and `completed.svg`.
///
/// They are sampled rather than approximated with a sine so the code and the
/// design file keep describing the same motion — `needsAttention` in particular
/// is a hold-then-flash that no simple curve reproduces.
///
/// Two tracks deviate from the file on purpose, and both deviate in the same
/// direction: ``attentionRing`` and ``completed`` reach `0.100` where the SVG
/// stops at `0.200`. The SVG had every dim cell resting at one level, which
/// left a mark waiting on the user and a mark with nothing running equally
/// dark. Those two are the states the eye has to catch, so they now go darker
/// than rest rather than level with it; the design file owes an update.
private enum MatrixTrack {
    static let runningEven: [Double] = [
        0.500, 0.371, 0.250, 0.146, 0.067, 0.017, 0.000, 0.017,
        0.067, 0.146, 0.250, 0.371, 0.500, 0.629, 0.750, 0.854,
        0.933, 0.983, 1.000, 0.983, 0.933, 0.854, 0.750, 0.629
    ]
    static let runningOdd: [Double] = [
        0.757, 0.859, 0.937, 0.985, 1.000, 0.981, 0.929, 0.848,
        0.743, 0.622, 0.492, 0.363, 0.243, 0.141, 0.063, 0.015,
        0.000, 0.019, 0.071, 0.152, 0.257, 0.378, 0.508, 0.637
    ]
    /// The ring holds at half ``inactiveLevel``. It used to hold at exactly
    /// that level, which made a mark waiting on the user as dark between
    /// flashes as a mark with nothing running at all; sitting below it says
    /// the darkness itself belongs to a live session, and it lengthens the
    /// climb the flash makes, so the flash reads from further away.
    static let attentionRing: [Double] = [
        0.100, 0.100, 0.100, 0.100, 0.100, 0.100, 0.100, 0.100,
        0.100, 0.100, 0.100, 0.100, 0.100, 0.100, 0.100, 0.100,
        1.000, 0.981, 0.963, 0.944, 0.925, 0.906, 0.887, 0.869
    ]
    static let attentionCentre: [Double] = [
        1.000, 0.981, 0.963, 0.944, 0.925, 0.906, 0.887, 0.869,
        0.850, 0.831, 0.813, 0.794, 0.775, 0.756, 0.738, 0.719,
        0.700, 0.681, 0.663, 0.644, 0.625, 0.606, 0.588, 0.569
    ]
    /// The same raised cosine the SVG draws, rescaled about its peak so the
    /// breath bottoms out at `0.100` instead of at ``inactiveLevel``: a
    /// finished turn is darker at its dimmest than a mark at rest, which is
    /// what makes the breath read as motion rather than as a lit mark.
    static let completed: [Double] = [
        0.550, 0.667, 0.775, 0.868, 0.939, 0.984, 1.000, 0.984,
        0.939, 0.868, 0.775, 0.667, 0.550, 0.433, 0.325, 0.232,
        0.161, 0.116, 0.100, 0.116, 0.161, 0.232, 0.325, 0.433
    ]
    /// Connected and disconnected hold the brightest dim level on the surface.
    ///
    /// It is a floor for the states that are *not* doing anything: the two
    /// that are — the attention ring between flashes, the completed breath at
    /// its trough — dip below it, so "dark" alone tells a live mark from a
    /// resting one.
    static let inactiveLevel = 0.200
}

private extension NotchMatrixState {
    /// One cell's whole opacity track, verbatim from the SVG's `values` list.
    ///
    /// The track is handed to Core Animation as keyframes rather than sampled
    /// per frame. `CAKeyframeAnimation` with linear calculation spreads N values
    /// across N-1 intervals, which is exactly SMIL's rule, so the motion is the
    /// same curve the design file describes — evaluated on the render server
    /// instead of by re-rendering the view tree.
    func track(forCell index: Int) -> [Double] {
        switch self {
        case .running:
            let isEven = ((index / 3) + (index % 3)).isMultiple(of: 2)
            return isEven ? MatrixTrack.runningEven : MatrixTrack.runningOdd
        case .needsAttention:
            return index == 4
                ? MatrixTrack.attentionCentre
                : MatrixTrack.attentionRing
        case .completed:
            return MatrixTrack.completed
        case .inactive:
            return [MatrixTrack.inactiveLevel]
        }
    }
}

/// The 3×3 status matrix that replaced the notch status dot.
///
/// Sized by the caller to the fixed ``PanelMetrics/statusMatrixSize``.
///
/// The indicator animates continuously for every state but `inactive` —
/// including `completed`, which lingers until the user reads the turn — so its
/// steady-state cost is what the app costs at rest. It is therefore drawn by
/// Core Animation rather than SwiftUI: a `TimelineView` tick re-renders the
/// whole overlay, custom panel `Shape` included, and measured at 8% of a core
/// no matter how little the tick actually changed. Layer animations run on the
/// render server and leave the view graph alone entirely.
struct NotchStatusMatrix: View {
    let state: NotchMatrixState
    let size: CGFloat
    var isAnimated = true
    /// Which product this mark belongs to, or nil for the resting grey.
    var agent: AgentKind?
    /// Draw one specimen for both products instead, cut on the mark's diagonal.
    ///
    /// Only the first-run legend passes this; on the surface a mark always
    /// belongs to one product. When set it replaces `agent`'s ink entirely.
    var split: NotchPalette.MatrixSplit?

    var body: some View {
        MatrixIndicator(
            state: state,
            size: size,
            isAnimated: isAnimated,
            ink: NotchPalette.ink(for: agent),
            split: split
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
    let split: NotchPalette.MatrixSplit?

    func makeNSView(context: Context) -> MatrixIndicatorView {
        MatrixIndicatorView()
    }

    func updateNSView(_ view: MatrixIndicatorView, context: Context) {
        view.apply(
            state: state,
            size: size,
            isAnimated: isAnimated,
            ink: ink,
            split: split
        )
    }
}

final class MatrixIndicatorView: NSView {
    /// One blur pass of the lit cells, or the sharp copy when `blur` is nil.
    private struct GlowPass {
        let blur: CGFloat?
        let opacity: Float
    }

    /// One cell's colours: the product's, or both where the seam crosses it.
    private enum CellInk {
        case single(CGColor)
        case split(above: CGColor, below: CGColor)
    }

    /// Which side of the mark's diagonal a cell falls on.
    ///
    /// The seam runs from the lower-left corner to the upper-right one, so with
    /// row 0 at the top the sum of a cell's row and column is below 2 above the
    /// seam, above 2 below it, and exactly 2 on the three cells the seam itself
    /// passes through.
    enum DiagonalSide: Equatable {
        case above, below, onSeam

        static func of(cell index: Int) -> DiagonalSide {
            switch index / 3 + index % 3 {
            case ..<2: .above
            case 2: .onSeam
            default: .below
            }
        }
    }

    private var appliedState: NotchMatrixState?
    private var appliedSize: CGFloat = 0
    private var appliedIsAnimated = true
    private var appliedInk = NotchPalette.codexInk
    private var appliedSplit: NotchPalette.MatrixSplit?

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
        split: NotchPalette.MatrixSplit? = nil
    ) {
        guard state != appliedState
            || size != appliedSize
            || isAnimated != appliedIsAnimated
            || ink != appliedInk
            || split != appliedSplit else {
            return
        }
        appliedState = state
        appliedSize = size
        appliedIsAnimated = isAnimated
        appliedInk = ink
        appliedSplit = split
        rebuild()
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

    private func rebuild() {
        guard let state = appliedState, appliedSize > 0, let root = layer else {
            return
        }

        root.sublayers?.forEach { $0.removeFromSuperlayer() }

        // Proportions come straight from the SVG's 91-unit viewBox: 27-unit
        // cells on a 32-unit pitch, 2-unit corner radius.
        let size = appliedSize
        let cell = size * 27 / 91
        let gap = size * 5 / 91
        let radius = cell * 2 / 27
        let pitch = cell + gap
        // Three sigma is where a Gaussian is spent, so this is how far the
        // widest pass reaches. Each pass gets bounds that large or the filter
        // would clip its own halo.
        let bleed = cell * 10.5 / 27 * 3
        let scale = window?.backingScaleFactor ?? 2

        /// One cell, in one colour or cut into two on the mark's diagonal.
        ///
        /// The split cell is a full rounded rect in the leading colour with the
        /// trailing colour laid over its lower-right half. The mask is a plain
        /// triangle rather than a gradient stop: it is drawn in the same
        /// flipped space the cell frames are laid out in, so the seam cannot
        /// come out mirrored the way a unit-space gradient can.
        func makeCell(_ ink: CellInk, side: DiagonalSide, edge: CGFloat) -> CALayer {
            let layer = CALayer()
            layer.cornerRadius = radius
            layer.cornerCurve = .continuous
            layer.contentsScale = scale

            switch (ink, side) {
            case let (.single(color), _):
                layer.backgroundColor = color
            case let (.split(above, _), .above):
                layer.backgroundColor = above
            case let (.split(_, below), .below):
                layer.backgroundColor = below
            case let (.split(above, below), .onSeam):
                layer.backgroundColor = above
                let trailing = CAShapeLayer()
                trailing.frame = CGRect(x: 0, y: 0, width: edge, height: edge)
                trailing.path = Self.trailingHalf(edge: edge, radius: radius)
                trailing.fillColor = below
                trailing.contentsScale = scale
                layer.addSublayer(trailing)
            }
            return layer
        }

        func pass(_ pass: GlowPass, ink: CellInk, animated: Bool) -> CALayer {
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

            for index in 0 ..< 9 {
                let cellLayer = makeCell(
                    ink,
                    side: DiagonalSide.of(cell: index),
                    edge: cell
                )
                cellLayer.frame = CGRect(
                    x: bleed + CGFloat(index % 3) * pitch,
                    y: bleed + CGFloat(index / 3) * pitch,
                    width: cell,
                    height: cell
                )

                let track = state.track(forCell: index)
                // The still the design file shows: every track's t=0 frame.
                cellLayer.opacity = Float(track.first ?? 1)
                if animated, let period = state.period, track.count > 1 {
                    cellLayer.add(
                        Self.trackAnimation(track: track, period: period),
                        forKey: "notch.matrix.opacity"
                    )
                }
                container.addSublayer(cellLayer)
            }
            return container
        }

        let unlit: CellInk = appliedSplit.map {
            .split(above: $0.above.offLayerColor, below: $0.below.offLayerColor)
        } ?? .single(appliedInk.offLayerColor)
        let lit: CellInk = appliedSplit.map {
            .split(above: $0.above.onLayerColor, below: $0.below.onLayerColor)
        } ?? .single(appliedInk.onLayerColor)

        // The unlit bed never animates; only the lit copies above it do.
        root.addSublayer(
            pass(
                GlowPass(blur: nil, opacity: 1),
                ink: unlit,
                animated: false
            )
        )

        // Three blurred copies reproduce the SVG's feGaussianBlur + feMerge
        // passes, then the sharp copy sits on top.
        let glowPasses = [
            GlowPass(blur: cell * 10.5 / 27, opacity: 0.21),
            GlowPass(blur: cell * 5.6 / 27, opacity: 0.35),
            GlowPass(blur: cell * 2.1 / 27, opacity: 0.56),
            GlowPass(blur: nil, opacity: 1)
        ]
        for glowPass in glowPasses {
            root.addSublayer(
                pass(
                    glowPass,
                    ink: lit,
                    animated: appliedIsAnimated
                )
            )
        }
    }

    /// The part of one cell that lies past the seam, corners and all.
    ///
    /// The seam runs from the cell's lower-left corner to its upper-right one,
    /// so the half beyond it is the triangle through the top-right, bottom-right
    /// and bottom-left corners — in this view's flipped space, where y grows
    /// downwards. Intersecting with the cell's own rounded rect rather than
    /// masking it keeps the two halves inside the same rounded outline and
    /// leaves the result a plain path, which is a thing a test can ask about.
    static func trailingHalf(edge: CGFloat, radius: CGFloat) -> CGPath {
        let triangle = CGMutablePath()
        triangle.move(to: CGPoint(x: edge, y: 0))
        triangle.addLine(to: CGPoint(x: edge, y: edge))
        triangle.addLine(to: CGPoint(x: 0, y: edge))
        triangle.closeSubpath()

        let cell = CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: edge, height: edge),
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
        return triangle.intersection(cell)
    }

    /// Phase comes from the clock, not from the moment of installation.
    ///
    /// Left at the default `beginTime` of 0, Core Animation starts the loop
    /// when the animation is added, so a mark's phase records when its layers
    /// were last built. Two products reaching the same state at different
    /// moments -- a Codex turn starting, then a Claude Code one a few seconds
    /// later -- then breathe against each other, and two marks side by side
    /// running the same curve out of step read as noise rather than as one
    /// state said twice. A rebuild for a reason the eye should not see (a
    /// window change, a backing-scale change) restarted the loop too.
    ///
    /// Anchoring `beginTime` to the last whole multiple of the period fixes
    /// both: every mark in a given state lands on the same grid, so marks
    /// showing the same pattern show it in sync no matter when each started,
    /// and a rebuild resumes the phase the mark already had. Same trick, same
    /// reason, as ``NotchTextRaster/installSweep(on:width:period:)``.
    ///
    /// The grid is per-period, so the states that share a period -- attention
    /// and completed, both `1.2` -- also sync with each other, while running's
    /// `1.0` keeps its own grid. Within one mark every cell's animation is
    /// added in the same pass with the same anchor, so the cells stay in phase
    /// with each other as they always did.
    private static func trackAnimation(
        track: [Double],
        period: TimeInterval
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = track.map { NSNumber(value: $0) }
        animation.duration = period
        animation.calculationMode = .linear
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.beginTime = phaseAnchor(for: period)
        return animation
    }

    /// The most recent whole-period boundary on the layer clock.
    ///
    /// A cell layer is built fresh with default timing under a superlayer with
    /// default timing, so its local time is `CACurrentMediaTime()` and the
    /// anchor can be expressed in that clock directly.
    static func phaseAnchor(
        for period: TimeInterval,
        now: CFTimeInterval = CACurrentMediaTime()
    ) -> CFTimeInterval {
        now - now.truncatingRemainder(dividingBy: period)
    }
}

/// Shared drawing for the surface's layer-backed labels.
///
/// Both the notch readout and the session rows animate a highlight across their
/// glyphs, so both draw the glyphs into a layer rather than letting SwiftUI
/// re-render them every frame. They rasterise through ordinary AppKit text
/// drawing, so a layer-backed label matches a SwiftUI one beside it.
enum NotchTextRaster {
    /// A highlight band: transparent except for a peak at its centre, four
    /// times as wide as what it crosses. Read as a mask, so only alpha matters.
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
        // Phase comes from the clock, not from the moment of installation.
        //
        // A running turn's body text is its live progress, so it is replaced
        // every few seconds, and every replacement re-rasterises the glyphs and
        // lands back here. Left at the default `beginTime` of 0, Core Animation
        // starts the loop when the animation is added, so each update would
        // restart the sweep. The band is four times the width of what it
        // crosses with its bright peak at the centre, so the peak does not
        // reach the glyphs until 40% into the loop -- restarting more often
        // than that would mean the highlight is never drawn at all.
        //
        // Anchoring to a whole-period grid also keeps every row in phase with
        // every other, which is what the absolute-time SwiftUI schedule did
        // before this moved to Core Animation.
        let now = CACurrentMediaTime()
        animation.beginTime = now - now.truncatingRemainder(dividingBy: period)
        mask.add(animation, forKey: sweepAnimationKey)
    }

    static let sweepAnimationKey = "notch.searchlight"

    static func textSize(_ text: String, font: NSFont) -> CGSize {
        let size = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    /// The glyphs, drawn the way every other label on this surface is drawn.
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

/// The one curve this overlay opens, closes and hands text over on.
///
/// The window, the header and the labels inside it all move together, and a
/// label that dissolves one reading into another has to be finished exactly as
/// the width animating underneath it settles. `0.20` and `(0.22, 1, 0.36, 1)`
/// used to be written out separately in each of those three places, which is
/// how they were free to drift apart; this is the single declaration they read
/// from, in the two forms the surface needs — SwiftUI lays out the header, and
/// Core Animation drives the window and the layer-backed labels.
enum PanelMotion {
    static let duration: TimeInterval = 0.20
    /// Reduce Motion shortens the hand-over rather than removing it. What that
    /// setting asks to be spared is movement, and a dissolve is the thing you
    /// replace movement *with* — a label that swaps instantly under a panel
    /// that is still closing is not the calmer option.
    static let reducedDuration: TimeInterval = 0.08

    static func duration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedDuration : duration
    }

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: reducedDuration)
            : .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }

    static func timingFunction(reduceMotion: Bool) -> CAMediaTimingFunction {
        reduceMotion
            ? CAMediaTimingFunction(name: .easeOut)
            : CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
    }
}

/// A single-line notch label: thin and dim, sweeping while work is in flight.
///
/// This is the notch's own status readout, so it is on screen for as long as
/// the panel is, and its sweep is the one that runs indefinitely — a turn can
/// sit on `Approval needed` all afternoon. It is therefore layer-backed, for
/// the reason ``NotchStatusMatrix`` documents: a SwiftUI-driven animation here
/// re-renders the whole overlay every frame, measured at ~7% of a core, and
/// throttling its schedule does not help because the redraw follows the panel
/// being marked for display rather than this view's tick.
///
/// The glyphs are rasterised through ordinary AppKit text drawing rather than a
/// `CATextLayer` so they match the rest of the surface exactly; only the tint
/// differs between the two copies. Measurement uses the same `NSFont` metrics
/// ``PanelMetrics`` sizes the panel with, so the label and the panel width now
/// agree by construction instead of by coincidence.
struct SearchlightLabel: View {
    let text: String
    var font: NSFont = .systemFont(ofSize: 13, weight: .light)
    var isSweeping: Bool
    /// Only the length of the hand-over between two readings. Whether the label
    /// sweeps at all is the caller's decision and rides in `isSweeping`.
    var reduceMotion = false

    var body: some View {
        SweepingLabel(
            text: text,
            font: font,
            isSweeping: isSweeping,
            reduceMotion: reduceMotion
        )
        .accessibilityHidden(true)
    }
}

private struct SweepingLabel: NSViewRepresentable {
    let text: String
    let font: NSFont
    let isSweeping: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> SweepingLabelView {
        SweepingLabelView()
    }

    func updateNSView(_ view: SweepingLabelView, context: Context) {
        view.apply(
            text: text,
            font: font,
            isSweeping: isSweeping,
            reduceMotion: reduceMotion
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: SweepingLabelView,
        context: Context
    ) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

final class SweepingLabelView: NSView {
    /// Loop length of one traverse.
    private static let sweepPeriod: TimeInterval = 2
    static let dissolveAnimationKey = "notch.label.dissolve"
    static let baseLayerName = "notch.label.base"
    static let highlightLayerName = "notch.label.highlight"
    static let outgoingLayerName = "notch.label.outgoing"

    private let baseLayer = CALayer()
    private let highlightLayer = CALayer()
    /// The reading being replaced, held above the new one until it has
    /// dissolved. It shows the raster that was already drawn — nothing is
    /// re-rasterised to leave the screen.
    private let outgoingLayer = CALayer()
    private let sweepMask = NotchTextRaster.makeSweepMask()
    private var appliedText = ""
    private var appliedFont = NSFont.systemFont(ofSize: 13, weight: .light)
    private var appliedIsSweeping = false
    private var appliedReduceMotion = false
    private var renderedScale: CGFloat = 0
    /// The size the current glyphs were rasterised at, which is what every
    /// glyph layer is framed to. Never `bounds`: the layout animates `bounds`
    /// across an expand or a collapse, and a layer framed to it stretches its
    /// raster to fit every width on the way.
    private var glyphSize: CGSize = .zero
    private var outgoingGlyphSize: CGSize = .zero
    /// Geometry the running sweep was built for, so an unchanged one is left
    /// alone rather than torn down and rebuilt — this view is laid out on every
    /// frame of a transition, and re-adding the animation there is a
    /// `CATransaction` commit per frame for a band that would not have moved.
    private var installedSweepSize: CGSize?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // The outgoing reading is wider than this view for the length of a
        // collapse, and the panel edge closing over it is half of what makes
        // the hand-over read as one movement. Unclipped, those glyphs would be
        // drawn outside the black surface and over the desktop.
        layer?.masksToBounds = true

        baseLayer.name = Self.baseLayerName
        highlightLayer.name = Self.highlightLayerName
        outgoingLayer.name = Self.outgoingLayerName
        // Resting state of a layer that is only ever seen mid-dissolve.
        outgoingLayer.opacity = 0

        highlightLayer.mask = sweepMask
        layer?.addSublayer(baseLayer)
        layer?.addSublayer(highlightLayer)
        // Above both copies: it is the reading being taken away.
        layer?.addSublayer(outgoingLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NotchTextRaster.textSize(appliedText, font: appliedFont)
    }

    func apply(text: String, font: NSFont, isSweeping: Bool, reduceMotion: Bool) {
        let textChanged = text != appliedText || font != appliedFont
        guard textChanged
            || isSweeping != appliedIsSweeping
            || reduceMotion != appliedReduceMotion
        else { return }

        let previousText = appliedText
        let previousGlyphs = baseLayer.contents
        let previousGlyphSize = glyphSize
        let previousScale = baseLayer.contentsScale

        appliedText = text
        appliedFont = font
        appliedIsSweeping = isSweeping
        appliedReduceMotion = reduceMotion

        if textChanged {
            invalidateIntrinsicContentSize()
            renderedScale = 0
            redrawGlyphs()
            dissolve(
                from: previousGlyphs,
                text: previousText,
                size: previousGlyphSize,
                scale: previousScale
            )
            layoutGlyphLayers()
        }
        highlightLayer.isHidden = !isSweeping
        installSweep()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        redrawGlyphs()
        layoutGlyphLayers()
        installSweep()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        redrawGlyphs()
    }

    override func layout() {
        super.layout()
        layoutGlyphLayers()
        installSweep()
    }

    /// Hand one reading over to the next without either of them jumping.
    ///
    /// Two things change at once when the panel opens or closes: the words, and
    /// the width the layout gives them. The width is animated, so the words
    /// have to be handed over on the same curve. Swapped outright at the start
    /// of it — which is what this used to do, with the glyph layer framed to
    /// `bounds` — the short raster was stretched across the long frame for the
    /// whole transition: `Approval` arrived as wide as `Approval needed` and
    /// then squeezed down into itself.
    ///
    /// The two readings are almost never unrelated. A compact form is the
    /// expanded form with a word taken off it, so where one is the beginning of
    /// the other the shared glyphs are the same pixels in the same place:
    /// fading the new copy in over them would only dim a word that never moved,
    /// once through 75% and back. The new copy is shown at full strength there
    /// and the old one dissolves off it, which leaves exactly the dropped word
    /// fading out under the closing edge. Only a genuinely different reading —
    /// `Running` becoming `Approval` — is cross-faded both ways.
    private func dissolve(
        from previousGlyphs: Any?,
        text previousText: String,
        size previousGlyphSize: CGSize,
        scale previousScale: CGFloat
    ) {
        guard let previousGlyphs,
              !previousText.isEmpty,
              !appliedText.isEmpty
        else {
            endDissolve()
            return
        }

        let duration = PanelMotion.duration(reduceMotion: appliedReduceMotion)
        let timing = PanelMotion.timingFunction(reduceMotion: appliedReduceMotion)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outgoingLayer.contents = previousGlyphs
        outgoingLayer.contentsScale = previousScale
        outgoingGlyphSize = previousGlyphSize
        outgoingLayer.frame = glyphFrame(for: previousGlyphSize)
        CATransaction.commit()

        outgoingLayer.add(
            Self.fade(from: 1, to: 0, duration: duration, timing: timing),
            forKey: Self.dissolveAnimationKey
        )

        // One reading is the beginning of the other: the shared glyphs are
        // already on screen and stay exactly where they are.
        guard !previousText.hasPrefix(appliedText),
              !appliedText.hasPrefix(previousText)
        else {
            baseLayer.removeAnimation(forKey: Self.dissolveAnimationKey)
            highlightLayer.removeAnimation(forKey: Self.dissolveAnimationKey)
            return
        }

        let fadeIn = Self.fade(from: 0, to: 1, duration: duration, timing: timing)
        baseLayer.add(fadeIn, forKey: Self.dissolveAnimationKey)
        highlightLayer.add(fadeIn, forKey: Self.dissolveAnimationKey)
    }

    /// Drop whatever is mid-dissolve.
    ///
    /// The outgoing copy rests at zero opacity, so there is nothing to tear
    /// down on a timer and nothing left drawn if the label is emptied halfway
    /// through a hand-over.
    private func endDissolve() {
        outgoingLayer.removeAnimation(forKey: Self.dissolveAnimationKey)
        baseLayer.removeAnimation(forKey: Self.dissolveAnimationKey)
        highlightLayer.removeAnimation(forKey: Self.dissolveAnimationKey)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outgoingLayer.contents = nil
        outgoingGlyphSize = .zero
        CATransaction.commit()
    }

    private static func fade(
        from: Float,
        to: Float,
        duration: TimeInterval,
        timing: CAMediaTimingFunction
    ) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = timing
        return animation
    }

    private func redrawGlyphs() {
        let scale = window?.backingScaleFactor ?? 2
        // Replacing `contents` is an animatable change on a plain sublayer, so
        // Core Animation would cross-fade it — on its own schedule, not the
        // panel's, and with no say in which of the two readings is on top. The
        // hand-over above is that cross-fade, done deliberately.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard !appliedText.isEmpty else {
            baseLayer.contents = nil
            highlightLayer.contents = nil
            glyphSize = .zero
            return
        }
        let size = intrinsicContentSize
        glyphSize = size
        guard scale != renderedScale else { return }
        renderedScale = scale

        baseLayer.contentsScale = scale
        highlightLayer.contentsScale = scale
        baseLayer.contents = NotchTextRaster.glyphImage(
            text: appliedText,
            font: appliedFont,
            color: NotchPalette.labelDrawingColor,
            size: size,
            scale: scale
        )
        highlightLayer.contents = NotchTextRaster.glyphImage(
            text: appliedText,
            font: appliedFont,
            color: NotchPalette.spotlightDrawingColor,
            size: size,
            scale: scale
        )
    }

    /// The glyphs keep their own size and their own place; only the view around
    /// them is animated.
    private func layoutGlyphLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let frame = glyphFrame(for: glyphSize)
        baseLayer.frame = frame
        highlightLayer.frame = frame
        outgoingLayer.frame = glyphFrame(for: outgoingGlyphSize)
        CATransaction.commit()
    }

    /// Leading edge, vertically centred: the matrix sits to this label's left
    /// and the reading grows away from it, so the first glyph is the one that
    /// must not move when the reading changes length.
    private func glyphFrame(for size: CGSize) -> CGRect {
        CGRect(
            x: 0,
            y: ((bounds.height - size.height) / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }

    private func installSweep() {
        guard appliedIsSweeping else {
            installedSweepSize = nil
            sweepMask.removeAnimation(forKey: NotchTextRaster.sweepAnimationKey)
            return
        }
        // Across the glyphs, not across the frame the layout is animating — a
        // band scaled to a width that is still closing would sweep at a
        // different speed on every frame of the collapse.
        guard glyphSize != installedSweepSize
            || sweepMask.animation(
                forKey: NotchTextRaster.sweepAnimationKey
            ) == nil
        else { return }
        installedSweepSize = glyphSize
        NotchTextRaster.installSweep(
            on: sweepMask,
            across: glyphSize.width,
            height: glyphSize.height,
            period: Self.sweepPeriod
        )
    }
}

/// A session row's title or preview: one line, never truncated with an ellipsis,
/// fading out where it runs past the row instead.
///
/// Layer-backed for the same reason the notch readout is — a running turn
/// replaces its body text constantly, and the expanded panel shows up to three
/// rows at once — but it also owns the trailing fade its caller used to apply.
/// A SwiftUI `.mask` over an AppKit view is not dependable, and the fade is the
/// row's own behaviour rather than the caller's, so it lives on the layer now.
struct SessionRowText: View {
    let text: String
    let font: NSFont
    let color: NSColor
    let lineHeight: CGFloat

    var body: some View {
        SessionRowTextRepresentable(
            text: text,
            font: font,
            color: color,
            lineHeight: lineHeight
        )
        .frame(height: lineHeight)
    }
}

private struct SessionRowTextRepresentable: NSViewRepresentable {
    let text: String
    let font: NSFont
    let color: NSColor
    let lineHeight: CGFloat

    func makeNSView(context: Context) -> SessionRowTextView {
        SessionRowTextView()
    }

    func updateNSView(_ view: SessionRowTextView, context: Context) {
        view.apply(text: text, font: font, color: color)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: SessionRowTextView,
        context: Context
    ) -> CGSize? {
        // Takes the width it is offered, like the GeometryReader it replaced,
        // and lets the glyphs overflow and fade rather than shrinking the row.
        CGSize(
            width: proposal.width ?? nsView.intrinsicContentSize.width,
            height: lineHeight
        )
    }
}

final class SessionRowTextView: NSView {
    /// Distance over which the last glyphs fade out, matching the gradient the
    /// caller used to apply as a separate SwiftUI mask.
    private static let trailingFadeWidth: CGFloat = 48

    private let baseLayer = CALayer()
    private let fadeMask = CAGradientLayer()
    private var appliedText = ""
    private var appliedFont = NSFont.systemFont(ofSize: 13, weight: .light)
    private var appliedColor = NSColor.white
    private var renderedScale: CGFloat = 0
    /// The glyph size actually drawn, which is the natural text size clipped to
    /// the row. Only this much is ever visible, and every byte beyond it is a
    /// texture upload per update that nothing can see.
    private var renderedGlyphSize: CGSize = .zero

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

        layer?.addSublayer(baseLayer)
        // Sized to the row, so it clips the overflow as well as fading it.
        layer?.mask = fadeMask
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NotchTextRaster.textSize(appliedText, font: appliedFont)
    }

    func apply(text: String, font: NSFont, color: NSColor) {
        guard text != appliedText
            || font != appliedFont
            || color != appliedColor
        else { return }

        appliedText = text
        appliedFont = font
        appliedColor = color

        // No `invalidateIntrinsicContentSize` here on purpose. This view is
        // always given the width it is offered, so its intrinsic size never
        // decides the layout -- invalidating it only makes SwiftUI re-measure
        // and re-lay-out the subtree, once per row for every update, and a
        // running turn's body text updates constantly.
        renderedScale = 0
        renderedGlyphSize = .zero
        redrawGlyphs()
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
        // Geometry changes must not animate: the row is inside a panel that
        // resizes, and an implicit CA animation would drag the glyphs after it.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // The clip depends on the row's width, so a resize has to re-draw.
        redrawGlyphs()
        let glyphs = renderedGlyphSize
        // Left-aligned at the top of the line box, where the GeometryReader
        // this replaced placed its content.
        let glyphFrame = CGRect(
            x: 0,
            y: 0,
            width: glyphs.width,
            height: glyphs.height
        )
        baseLayer.frame = glyphFrame

        fadeMask.frame = bounds
        let width = max(bounds.width, 1)
        let fadeStart = max(0, width - Self.trailingFadeWidth) / width
        fadeMask.locations = [0, NSNumber(value: fadeStart), 1]

        CATransaction.commit()
    }

    private func redrawGlyphs() {
        let scale = window?.backingScaleFactor ?? 2
        // Replacing `contents` is an animatable change on a plain sublayer, so
        // Core Animation would cross-fade it. Body text is replaced as a turn
        // makes progress, and fades that outlive the gap between updates pile
        // up into a smear; the text it replaced swapped instantly.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard !appliedText.isEmpty else {
            baseLayer.contents = nil
            renderedGlyphSize = .zero
            return
        }

        // Only what the row can show. A body line is capped at 240 characters,
        // three times the width of the row it sits in, and the remainder is
        // behind the fade -- drawing it would upload a texture per update for
        // pixels that are never composited.
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
    }
}
