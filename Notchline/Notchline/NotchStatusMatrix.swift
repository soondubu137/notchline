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
        /// A subagent badge's dim ground, which is the one it has while
        /// everything it counts is running.
        ///
        /// The badge is a flat tile with a numeral on it, not a dot, and at
        /// the unlit colour that tile read as a hole in the panel rather than
        /// as a mark sitting on it. So it is lifted a little towards white --
        /// every channel by the same amount, which leaves each product's hue
        /// and the resting grey's neutrality where they were and gives all
        /// three the same distance from the black behind them. Still plainly
        /// the dim end of the pair the flipped ground leads.
        ///
        /// The bright end does *not* come from here: it is the ink's own lit
        /// colour, unlifted, because there brightness is the signal itself.
        var chipFill: Color {
            chipFill(over: .black)
        }
        /// The same ground on a surface that is not black.
        ///
        /// **A tile has to stay above whatever it is drawn on.** A session row
        /// lights to `#2B2B2E` under the pointer and `#3A3A3D` while pressed,
        /// both of which are brighter than the resting `#242424` this returns
        /// on black -- so a fixed value turns into a hole at the exact moment
        /// the pointer is on it. Lifting off the brighter of the two keeps the
        /// value it has always had at rest and lets it rise with the row.
        func chipFill(over ground: NotchPalette.SurfaceGround) -> Color {
            Color(
                red: min(1, max(offRed, ground.red) + Self.chipLift),
                green: min(1, max(offGreen, ground.green) + Self.chipLift),
                blue: min(1, max(offBlue, ground.blue) + Self.chipLift)
            )
        }
        /// How far ``chipFill`` is lifted off the unlit colour towards white.
        ///
        /// `#151515` becomes `#242424` for the resting grey. Landed on by
        /// looking at it: below this the tile still sank into the panel,
        /// above it the fill started competing with the numeral it carries.
        private static let chipLift = 0.06
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

    /// A surface a tile can be drawn on, so the tile can be told what it has
    /// to stay above.
    ///
    /// Only the session row is ever anything but black, and only while the
    /// pointer is on it — but that is the one moment a mark must not vanish,
    /// so the grounds live here rather than as literals at the two views that
    /// draw them.
    nonisolated struct SurfaceGround: Equatable, Sendable {
        let red, green, blue: Double

        var color: Color { Color(red: red, green: green, blue: blue) }

        /// The notch's own surface, and a session row at rest.
        static let black = SurfaceGround(red: 0, green: 0, blue: 0)
        /// A session row under the pointer, and one being pressed.
        static let rowHovered = SurfaceGround(red: 0.17, green: 0.17, blue: 0.18)
        static let rowPressed = SurfaceGround(red: 0.23, green: 0.23, blue: 0.24)
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
    /// A neutral subagent badge's numeral once its ground has flipped, drawn
    /// on ``spotlight`` white.
    ///
    /// `dual-agent-design.md` §10. Not ``label`` or pure black: the badge
    /// inverts the same way the row's own attention state already does
    /// elsewhere on this surface, and this is that inversion's dark end. A
    /// product-tinted badge inverts within its own ink instead and never
    /// reaches this value.
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
    /// ``chipOnLight`` for the layer-backed readings, which draw through
    /// AppKit rather than SwiftUI.
    static let chipOnLightDrawingColor = NSColor(
        srgbRed: 0.05,
        green: 0.05,
        blue: 0.06,
        alpha: 1
    )
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
    /// The instant the turn ended, on the rows where it has.
    ///
    /// A finished row draws how long its turn took, and that figure must not
    /// move: with an end the reading is measured between the turn's own two
    /// stamps and the tick is ignored, so every refresh draws the same value
    /// for as long as the row is listed. Nil while a turn is running, where
    /// the tick is what advances it.
    var stoppedAt: Date?
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
            stoppedAt: stoppedAt,
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
    /// Set on a reading that has stopped, which is then measured against this
    /// rather than against the tick.
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
        // SwiftUI may measure before the first tick has been rendered. A
        // shortest-form reading is the right placeholder: every readout starts
        // at 0:00 and only ever grows from there.
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

        // A stopped reading takes no tick: it is measured between the turn's
        // own two stamps, so a subscription would wake this view once a second
        // to redraw a figure that cannot have changed. One that had a tick and
        // has stopped drops it here, which is the turn ending under the row.
        guard stoppedAt == nil else {
            subscription = nil
            render(at: lastTick)
            return
        }

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

/// Which ink a subagent badge draws in.
///
/// `dual-agent-design.md` §10: hue on this badge only ever answers "whose is
/// this" — never "what state is this". State is the ground's brightness, and
/// it flips within whichever ink the badge already has.
enum SubagentBadgeTint: Equatable {
    /// A session row's badge, always. The row names its product on the caption
    /// line above, so hue here would spend a channel saying the same thing
    /// twice.
    case neutral
    /// The collapsed surface's badge, one per product. A bar has no caption
    /// line, so ink is the only thing on it that can say whose.
    case product(AgentKind)

    private var ink: NotchPalette.MatrixInk {
        switch self {
        case .neutral: NotchPalette.restingInk
        case .product(let agent): NotchPalette.ink(for: agent)
        }
    }

    /// The ground. Dim while everything is running, bright the moment one of
    /// them is stopped on a question.
    ///
    /// The bright end is the ink's own lit colour for a product badge and the
    /// surface's white for a neutral one — the resting grey has no lit colour
    /// of its own (it cannot light, because nothing is connected to light it),
    /// so brightness there is the same white every other attention signal on
    /// this surface uses.
    ///
    /// `over` is the surface the badge is drawn on, which is black everywhere
    /// but a session row under the pointer. Only the dim end reads it: the
    /// bright end is a signal and has to be the same white, or the same lit
    /// hue, wherever it appears.
    func fill(wantsAttention: Bool, over ground: NotchPalette.SurfaceGround = .black) -> Color {
        guard wantsAttention else { return ink.chipFill(over: ground) }
        switch self {
        case .neutral: return NotchPalette.spotlight
        case .product: return ink.on
        }
    }

    /// The numeral, which is always whichever end of the pair the ground is
    /// not.
    func text(wantsAttention: Bool) -> Color {
        guard wantsAttention else {
            switch self {
            case .neutral: return NotchPalette.label
            case .product: return ink.on
            }
        }
        switch self {
        case .neutral: return NotchPalette.chipOnLight
        case .product: return ink.off
        }
    }
}

/// One subagent badge: a filled, rounded tile holding a bare count.
///
/// `dual-agent-design.md` §10. Sized to `PanelMetrics.subagentBadgeWidth`
/// explicitly rather than left to hug its own text: the collapsed pill's
/// width is composed from that same measurement, and a view free to size
/// itself independently could drift from it by a point SwiftUI's own text
/// layout and `NSString`'s measurement disagree on.
///
/// **The count is every subagent, and the ground is the only other thing this
/// says.** There is no second badge for the waiting ones: a badge is drawn on
/// exactly the rows and bars that already need a person's attention, and two
/// numerals there would be two things to read at the worst moment to be
/// reading.
struct SubagentBadgeView: View {
    let badge: SubagentBadge
    let tint: SubagentBadgeTint
    /// What the badge is drawn on, so its dim ground can stay above it.
    var ground: NotchPalette.SurfaceGround = .black

    var body: some View {
        Text("\(badge.count)")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint.text(wantsAttention: badge.wantsAttention))
            .frame(
                width: PanelMetrics.subagentBadgeWidth(badge.count),
                height: PanelMetrics.subagentBadgeMinSize
            )
            .background(
                RoundedRectangle(
                    cornerRadius: PanelMetrics.subagentBadgeCornerRadius,
                    style: .continuous
                )
                .fill(tint.fill(wantsAttention: badge.wantsAttention, over: ground))
            )
            // Spoken by the row or the panel header, which say what the figure
            // counts and whose it is -- this mark alone is a bare number with
            // colour as its only label, which VoiceOver cannot read.
            .accessibilityHidden(true)
    }
}

/// The ground an elapsed reading sits on, which is how the surface tells the
/// four session states apart (`figma-design.md` page 14).
///
/// **One slot, one mark, three silhouettes.** A reading with no ground is a
/// turn still running; on white it is a turn stopped on something only a
/// person can answer; on the dim ground it is a turn that has finished, and
/// the figure inside it is how long that took. Presence and brightness alone
/// could not say this: both are comparisons, and a row read on its own — or a
/// list where every row happens to be in the same state — answered neither.
///
/// **The three are the expanded rows'.** The collapsed bar's single reading
/// draws the running silhouette always: it is one figure for every turn at
/// once, with no second reading beside it to be read against, and the white
/// slab there was the brightest thing on the bar for a state the matrix
/// already announces. It keeps this ground at `.clear` for the room alone.
///
/// It is deliberately the ``SubagentBadgeView`` tile at reading width, down to
/// the radius and the padding. That badge already draws a figure on a ground
/// that flips when a person is wanted; this is the same mark answering for the
/// turn as well as for the subagents it spawned, which is also why the two
/// compose without a rule of their own on the row that draws both.
struct ReadingGround<Content: View>: View {
    /// The ground itself. `.clear` is a drawn state and not an absence: the
    /// collapsed bar wraps its reading in one of these permanently, for the
    /// padding, and the width it composes is billed for that padding.
    let fill: Color
    /// Fixed on the surfaces whose width is composed rather than hugged.
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

/// The collapsed surface's badges: one per product, tinted, Codex leading.
///
/// `dual-agent-design.md` §10. Spaced at the matrices' own `6`, because this
/// pair is that pair read at the other end of the bar.
struct SubagentBadgeRow: View {
    let badges: [AgentSubagentBadge]

    var body: some View {
        HStack(spacing: PanelMetrics.subagentBadgeSpacing) {
            ForEach(badges, id: \.agent) { mark in
                SubagentBadgeView(badge: mark.badge, tint: .product(mark.agent))
            }
        }
    }
}

/// The session-count dots that stand beside one status matrix.
///
/// `dual-agent-design.md` §11. One dot per row, packed from the top edge and
/// centred on the matrix's own three rows; past three the third stretches into
/// a dash a full cell long, which finishes flush with the matrix's lower edge
/// and means "more than three".
///
/// **A column exactly as tall as the mark it belongs to.** Two row pitches and
/// a cell is the matrix's own height, so this asks for no vertical room the
/// mark did not already have and draws identically on a `46` pt menu bar and a
/// `22` pt one. Under the matrix — where this was drawn first — it needed
/// `5.66` of clearance below the mark, which the short bars have not got.
///
/// **The column owns the gap that separates it from its matrix, and collapses
/// with it.** A product with no rows takes no width here at all. Together the
/// gap and the dot are `PanelMetrics.sessionDotColumnWidth`, which is why they
/// open and close as one value rather than as a spacing plus a view — half a
/// column is a dot standing at the wrong distance from its own mark.
///
/// **What an opening column moves depends on which form is drawing it.** On
/// the notch-less pill and the expanded header the room was reserved, so the
/// panel does not resize and the column pushes only the marks and the status
/// name after it. On the notched bar nothing is reserved: the leading wing is
/// as wide as its contents and the panel is pinned to the cut-out, so the
/// column pushes the panel's leading edge and every matrix *before* it
/// leftwards instead, while the marks between it and the cut-out stand still.
/// Both readings are the same rule — a column displaces whatever the anchored
/// edge does not hold in place — and both run on this view's own curve.
///
/// **Dots only fade; matrices only move.** The dot is drawn at a fixed `2.92`
/// from the matrix that owns it — offset rather than laid out, so the column's
/// width can grow underneath it without carrying it along. That matrix is
/// already standing still by the time the dot appears, so the dot appears in
/// the place it will keep. Nothing in this view translates.
///
/// The offset overhangs the column while it is opening, and is allowed to: a
/// dot reaches `5.66` from its matrix and the next mark is never nearer than
/// the pair's own `6`, so the overhang has nothing to collide with and needs no
/// clip. Clipping instead would wipe the dot in from its leading edge, which is
/// the one motion this view is arranged to avoid.
struct SessionCountDots: View {
    let count: Int
    /// Which product's rows these are, for the ink. The resting grey has no
    /// product and never draws this view at all.
    let agent: AgentKind
    let matrixSize: CGFloat
    /// Whether a finished, unread turn is sitting under a mark drawing
    /// something else — ``PresenceMark/buriesAFinishedTurn``, which is the only
    /// thing that turns the breath on.
    var breathes: Bool = false

    private var hasRows: Bool { count > 0 }
    private var columnWidth: CGFloat {
        hasRows ? PanelMetrics.sessionDotColumnWidth(matrixSize: matrixSize) : 0
    }
    private var gap: CGFloat { PanelMetrics.sessionDotGap(matrixSize: matrixSize) }
    private var diameter: CGFloat { PanelMetrics.sessionDotDiameter(matrixSize: matrixSize) }
    private var isPastCap: Bool { count > PanelMetrics.sessionDotCap }
    private var drawnCount: Int { min(count, PanelMetrics.sessionDotCap) }

    var body: some View {
        dots
            // Rendered at its resting distance from the matrix, and rendered
            // there whatever the slot is currently doing: `offset` moves the
            // drawing and not the layout, so the width below can open and close
            // under a dot that never moves.
            .offset(x: gap)
            .frame(width: columnWidth, alignment: .leading)
            .animation(slotAnimation, value: columnWidth)
            .accessibilityHidden(true)
    }

    /// **The marks themselves are drawn by Core Animation, and the slot around
    /// them is not.** The breath is a loop with no end, and `AGENTS.md` §7 and
    /// `system-architecture.md` §6 allow exactly one home for that: a `CALayer`
    /// evaluated by the render server, never a SwiftUI animation ticking the
    /// whole overlay. What stays here is everything with a beginning and an end
    /// — the slot opening, the dot fading in and out — which that rule does not
    /// reach and which SwiftUI already drives correctly.
    ///
    /// The two opacities compose rather than compete: this fade is on the
    /// hosted view, and the breath is on a layer inside it.
    private var dots: some View {
        SessionDotColumn(
            drawnCount: drawnCount,
            isPastCap: isPastCap,
            agent: agent,
            matrixSize: matrixSize,
            breathes: breathes
        )
        .frame(width: diameter, height: matrixSize, alignment: .topLeading)
        .opacity(hasRows ? 1 : 0)
        .animation(fadeAnimation, value: hasRows)
    }

    /// The slot opening and closing, shared with everything that stands after
    /// it and with the panel edge itself — see
    /// ``PanelMotion/slot(isOpening:)``.
    private var slotAnimation: Animation {
        PanelMotion.slot(isOpening: hasRows)
    }

    /// The dot arriving and leaving. Fading only — see the type's note.
    ///
    /// ``PanelMotion/fade(isArriving:)``, shared with every other mark that
    /// arrives into a slot on this surface: the reasoning that set these
    /// durations is the dot's, and the collapsed reading and the subagent
    /// badges inherit it rather than restating it.
    private var fadeAnimation: Animation {
        PanelMotion.fade(isArriving: hasRows)
    }
}

/// The column's one movement, and the only one it will ever have.
///
/// **What it says.** The collapsed surface draws the most urgent status and
/// nothing else, so every state under the maximum has no representative on the
/// bar. Three survive that: approval outranks everything, input loses only to
/// approval and the mark still says a person is wanted, and a running turn that
/// loses asks for nobody. `.completed` both loses and waits, and it is the only
/// one that does. So the column moves exactly when the mark beside it is
/// telling part of the truth — ``PresenceMark/buriesAFinishedTurn`` — and rests
/// the rest of the time, which is nearly all of it.
///
/// **Why the column and not the mark.** The matrix already has four movements
/// and each one means a status; a fifth would have to mean "running, and also
/// something finished", which is a pair of statuses rather than one, and it
/// would be drawn in a product's hue, so the same fact would look different
/// depending on whose it was. The column had no movement at all, which is what
/// makes giving it one unambiguous. This supersedes the "steady always" half of
/// the dot ink's rule ([`dual-agent-design.md`](dual-agent-design.md) §11) and
/// no other part of it: the column still takes no part in the matrix's own
/// patterns, which is what `figma-design.md` §4.8 actually says.
///
/// **Why the whole column, and opacity only.** One `2.74` dot is below the size
/// at which movement registers away from the centre of vision, which is the
/// only kind of looking a menu bar gets; every dot moving together makes the
/// target the column, `5.66` by `16.6`. Nothing translates and nothing resizes,
/// because the column's geometry is load-bearing — it is exactly as tall as the
/// matrix and ends flush with it.
///
/// **The numbers.** `2.8 s` sits below lull's `2 s`, the slowest thing the mark
/// runs, so the breath reads as a different order of movement rather than a
/// fifth pattern on a mark `2.92` away. The swing is the column's own `0.85`
/// down to `0.30` and back — `0.55` of amplitude, all of it below rest, so the
/// column never draws brighter than a resting one. It went that deep because
/// `0.35` was measured on a screen and was too quiet to catch, and it may go
/// that deep because the dip is momentary: what has to hold at every instant is
/// only that the run stays clearly brighter than the extinguished matrix, which
/// at `0.30` it does by about a factor of two.
enum SessionDotBreath {
    /// Slower than every track in ``MatrixTrack``; pinned by
    /// `theBreathIsSlowerThanAnythingTheMatrixRuns`.
    static let period: TimeInterval = 2.8

    /// **Steady, and a little under full.** Unchanged, and it is also the top
    /// of the swing: the breath only ever leaves this value and comes back to
    /// it, so the column never draws brighter than a resting one and §11's
    /// reason for holding the dots under full still stands untouched.
    ///
    /// A version that went to `1.0` was tried and dropped. It read, but it made
    /// the column the brightest thing in the leading wing for part of every
    /// cycle, and it bought that by breaking the one value this mark has always
    /// had. Taking the same amplitude out of the floor instead costs nothing
    /// that was already there.
    static let restingOpacity: Double = 0.85

    /// The bottom of the swing.
    ///
    /// **`0.55` of amplitude, all of it below rest.** The first version swung
    /// `0.35` and was too quiet to catch on a screen; this is wider than that
    /// and wider than the `1.0`-crested version it replaces, without the column
    /// ever exceeding where it rests.
    ///
    /// It goes this low because the dip is **momentary**. A column held at
    /// `0.30` would stop being countable, which is exactly why "dim the marks
    /// that are not yours" was rejected when this page was drawn — but a column
    /// that returns to full rest every `2.8 s` is legible for most of its cycle
    /// and never stops being a count. What must hold at every instant is the
    /// weaker, checkable thing: the run of dots stays clearly brighter than the
    /// extinguished matrix beside it, so a breathing column never reads as a
    /// mark going out. At `0.30` it keeps about twice that value in every
    /// channel of both inks — pinned by
    /// `theBreathsFloorStaysAboveTheMarkItStandsBeside`.
    static let floorOpacity: Double = 0.30

    /// **The turns slow down; they do not stop.**
    ///
    /// `easeInEaseOut` was the obvious curve and the wrong one. Its rate is
    /// zero at both ends, so an autoreversed cycle parks at the crest and again
    /// at the trough and spends most of its length barely moving — and what
    /// peripheral vision answers to is rate of change, not value. This is the
    /// same shape with the ends unparked: symmetric, still slowest at the
    /// turns, but never slower there than **a third** of its average rate, so
    /// the column is moving at every moment of the cycle.
    ///
    /// `y1 / x1` and `(1 - y2) / (1 - x2)` are that third, and their being
    /// equal is what keeps the fall and the rise the same shape. Pinned by
    /// `theBreathNeverParksAtEitherTurn`.
    static let timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.1, 0.7, 0.9)

    /// The loop, phased off the layer clock.
    ///
    /// **It begins on the next whole beat rather than immediately**, which buys
    /// two things at once. It puts two products' columns on one grid, so a pair
    /// breathing together reads as one signal rather than two — the reason
    /// ``MatrixIndicatorView/phaseAnchor(for:now:)`` is shared rather than
    /// copied, and the same rule the searchlight follows
    /// (``NotchTextRaster/installSweep(on:across:height:period:)``). And since
    /// the cycle's first value is ``restingOpacity``, exactly where the column
    /// already stood, the movement starts from where the mark was instead of
    /// stepping to a phase. Waiting costs at most one period, in a state that
    /// lasts until somebody reads something.
    static func animation(now: CFTimeInterval = CACurrentMediaTime()) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = restingOpacity
        animation.toValue = floorOpacity
        // Autoreversed, so one period is crest to trough and back, and the fall
        // and the rise are one curve rather than two that have to be kept
        // matching.
        animation.duration = period / 2
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = timingFunction
        animation.beginTime = beginTime(now: now)
        animation.isRemovedOnCompletion = false
        return animation
    }

    /// The next whole-period boundary on the layer clock.
    static func beginTime(now: CFTimeInterval = CACurrentMediaTime()) -> CFTimeInterval {
        MatrixIndicatorView.phaseAnchor(for: period, now: now) + period
    }
}

private struct SessionDotColumn: NSViewRepresentable {
    let drawnCount: Int
    let isPastCap: Bool
    let agent: AgentKind
    let matrixSize: CGFloat
    let breathes: Bool

    func makeNSView(context: Context) -> SessionDotColumnView {
        let view = SessionDotColumnView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: SessionDotColumnView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: SessionDotColumnView) {
        view.apply(
            drawnCount: drawnCount,
            isPastCap: isPastCap,
            agent: agent,
            matrixSize: matrixSize,
            breathes: breathes
        )
    }
}

/// The dots themselves, on layers, so the breath is evaluated by the render
/// server and the overlay is not re-rendered for it.
///
/// Two opacities, on two layers, because they answer different questions and
/// must be able to hold different values at the same instant: the hosted view's
/// own opacity is the dot arriving and leaving (SwiftUI, in
/// ``SessionCountDots``), and ``ink``'s is the breath. They compose.
final class SessionDotColumnView: NSView {
    /// Carries the breath. The capsules are its sublayers and are opaque.
    private let ink = CALayer()
    private var dots: [CALayer] = []

    private var drawnCount = 0
    private var isPastCap = false
    private var agent: AgentKind = .codex
    private var matrixSize: CGFloat = 0
    private var breathes = false
    private var isBreathing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        ink.opacity = Float(SessionDotBreath.restingOpacity)
        layer?.addSublayer(ink)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(
        drawnCount: Int,
        isPastCap: Bool,
        agent: AgentKind,
        matrixSize: CGFloat,
        breathes: Bool
    ) {
        // The dash is the only geometry change worth animating, and only when
        // it is genuinely a change: everything else here is a fresh layout.
        let dashChanged = self.isPastCap != isPastCap && self.drawnCount == drawnCount
        let inkChanged = self.agent != agent
        self.drawnCount = drawnCount
        self.isPastCap = isPastCap
        self.agent = agent
        self.matrixSize = matrixSize
        self.breathes = breathes

        rebuildDots(recolouring: inkChanged)
        layoutDots(animatingDash: dashChanged)
        updateBreath()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ink.frame = bounds
        CATransaction.commit()
        layoutDots(animatingDash: false)
    }

    private func rebuildDots(recolouring: Bool) {
        guard dots.count != drawnCount || recolouring else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        while dots.count > drawnCount {
            dots.removeLast().removeFromSuperlayer()
        }
        while dots.count < drawnCount {
            let dot = CALayer()
            ink.addSublayer(dot)
            dots.append(dot)
        }
        let colour = NotchPalette.ink(for: agent).onLayerColor
        for dot in dots { dot.backgroundColor = colour }
        CATransaction.commit()
    }

    /// Where the marks sit, in the layer's own bottom-up space.
    ///
    /// **Written as the arithmetic rather than as a flipped coordinate system.**
    /// The design states this column downwards — "one dot per row from the top
    /// edge at `5.84` pitch" — and a layer's space runs the other way, so the
    /// conversion has to happen somewhere. Doing it here, in one subtraction
    /// with the column's own height, is a thing that can be read and pinned;
    /// `isGeometryFlipped` is a thing that has to be trusted, and it would put
    /// the run at the wrong end of the mark if it were ever misread.
    ///
    /// The height is ``PanelMetrics/statusMatrixSize``'s column rather than the
    /// view's `bounds`, so the frames do not depend on when layout happens to
    /// run — and because that identity is the column's whole placement argument
    /// (`dual-agent-design.md` §11): it is exactly as tall as the matrix.
    ///
    /// Pinned by `theDashEndsOnTheMatrixsLowerEdge`.
    static func markFrames(
        drawnCount: Int,
        isPastCap: Bool,
        matrixSize: CGFloat
    ) -> [CGRect] {
        let diameter = PanelMetrics.sessionDotDiameter(matrixSize: matrixSize)
        let pitch = PanelMetrics.sessionDotPitch(matrixSize: matrixSize)
        let dashLength = PanelMetrics.sessionDotDashLength(matrixSize: matrixSize)
        return (0 ..< max(0, drawnCount)).map { index in
            let isDash = isPastCap && index == PanelMetrics.sessionDotCap - 1
            let height = isDash ? dashLength : diameter
            // The top edge of one mark, centred in its matrix row. The dash
            // takes the whole row instead of being centred in it, so the run
            // ends on the matrix's own lower edge rather than short of it.
            let row = CGFloat(index) * pitch
            let top = isDash ? row : row + (dashLength - diameter) / 2
            return CGRect(
                x: 0,
                y: matrixSize - top - height,
                width: diameter,
                height: height
            )
        }
    }

    private func layoutDots(animatingDash: Bool) {
        guard !dots.isEmpty else { return }
        let diameter = PanelMetrics.sessionDotDiameter(matrixSize: matrixSize)
        let frames = Self.markFrames(
            drawnCount: dots.count,
            isPastCap: isPastCap,
            matrixSize: matrixSize
        )

        CATransaction.begin()
        if animatingDash {
            // The third dot becoming the dash is one capsule growing, not a
            // swap: the height and the offset that keeps its run ending on the
            // matrix's lower edge move together, on the panel's own curve.
            CATransaction.setAnimationDuration(PanelMotion.duration)
            CATransaction.setAnimationTimingFunction(PanelMotion.timingFunction)
        } else {
            CATransaction.setDisableActions(true)
        }
        for (dot, frame) in zip(dots, frames) {
            dot.frame = frame
            dot.cornerRadius = diameter / 2
        }
        CATransaction.commit()
    }

    private func updateBreath() {
        guard breathes else {
            guard isBreathing else { return }
            isBreathing = false
            settleBreath()
            return
        }
        guard !isBreathing else { return }
        isBreathing = true
        ink.removeAnimation(forKey: Self.settleKey)
        ink.add(SessionDotBreath.animation(), forKey: Self.breathKey)
    }

    /// Coming to rest rather than stopping where it happened to be.
    ///
    /// The loop is removed the instant the condition clears, so without this
    /// the column would cut from wherever the cycle had reached back to full —
    /// a step of up to `0.35` on a mark that has just been read, which is the
    /// one moment nothing should be drawing attention.
    private func settleBreath() {
        let resting = Float(SessionDotBreath.restingOpacity)
        let current = ink.presentation()?.opacity ?? resting
        ink.removeAnimation(forKey: Self.breathKey)
        guard abs(current - resting) > 0.001 else { return }
        let settle = CABasicAnimation(keyPath: "opacity")
        settle.fromValue = current
        settle.toValue = resting
        settle.duration = PanelMotion.duration
        settle.timingFunction = PanelMotion.timingFunction
        ink.add(settle, forKey: Self.settleKey)
    }

    /// The loop actually attached to the layer.
    ///
    /// Exposed for `theBreathReachesTheLayerAndLeavesWithTheCondition`, because
    /// the failure this change is most exposed to is silent: every value right,
    /// every rule right, and nothing ever handed to Core Animation.
    var installedBreath: CAAnimation? { ink.animation(forKey: Self.breathKey) }

    private static let breathKey = "sessionDotBreath"
    private static let settleKey = "sessionDotBreathSettle"
}

/// The mark's own grid, in the units its design files are drawn in.
///
/// `27`-unit cells on a `32`-unit pitch with a `2`-unit corner radius — the
/// same three proportions the 3×3 matrix used, four to a side instead of
/// three, so the viewBox goes from `91` to `123`. The mark itself does not
/// grow: ``PanelMetrics/statusMatrixSize`` is still `16.6`, and the cell it
/// buys shrinks from `4.92` to `3.64`.
enum MatrixGrid {
    static let side = 4
    static let cellCount = side * side
    static let cell: CGFloat = 27
    static let pitch: CGFloat = 32
    static let cornerRadius: CGFloat = 2
    /// `4` cells and the `3` gaps between them.
    static let viewBox = CGFloat(side) * pitch - (pitch - cell)
}

/// What the 4×4 indicator is doing, independent of which status drove it.
///
/// One collapse is left, and it is the one that costs nothing: every
/// non-session state (connected, disconnected, and the retired thin states
/// the expanded panel still says) reads as "inactive". Input and approval
/// used to collapse too — one `needsAttention` flash stood for both — and no
/// longer do. The design file draws them as two patterns, so the mark now
/// says *which* question is waiting rather than only that one is, which is
/// the difference between a turn the user can answer from the keyboard and
/// one that wants a decision.
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

    /// Whether anything is in flight. Drives both the matrix animation and
    /// whether the accompanying label sweeps.
    var isActive: Bool {
        switch self {
        case .running, .inputNeeded, .approvalNeeded: true
        case .completed, .inactive: false
        }
    }

    /// Loop length, or `nil` when the state is a still.
    ///
    /// Three lengths for four patterns, and the pairing is the design's:
    /// the radar and the knock share `1.2`, so a bar showing one of each is
    /// showing two things on one grid rather than two clocks.
    var period: TimeInterval? {
        switch self {
        case .running, .approvalNeeded: 1.2
        case .inputNeeded: 0.8
        case .completed: 2.0
        case .inactive: nil
        }
    }
}

/// Per-cell opacity tracks, taken from the four animated SVGs in
/// `design/assets/matrix-states/`.
///
/// Every one of those files draws **one** waveform and gives each of its
/// sixteen cells that same waveform at its own offset, so that is how they
/// are held here: the curve sampled once per state, plus the rule that says
/// how far a given cell lags it. Writing out sixteen tracks per state would
/// be the same numbers sixteen times over, and the rule — a beam going
/// round, a column stepping across, a wave crossing the diagonal — is the
/// half that has to survive being read.
///
/// **The offsets are whole frames.** The files' own phases are not: a
/// bearing lands where it lands, and the lull's diagonals are `48.7/6`
/// frames apart. But each file is sampled at 30fps and so lights a cell on a
/// frame boundary anyway, and taking the frame the file itself lights
/// reproduces what the file draws. Measured against all sixteen tracks of
/// all four files, that costs at most `0.85` of a frame of phase and `0.065`
/// of opacity, both of them on the radar, whose beam crosses a cell up to
/// that far before the frame that first shows it lit.
///
/// Nothing here deviates from the design file. The old tracks did, in two
/// places, because that file rested every dim cell at one level and left a
/// mark waiting on the user as dark as a mark with nothing running. These
/// four sit at three floors of their own — `0.05` under the knock and
/// between the advance's columns, `0.139` behind the radar, `0.182` at the
/// bottom of the lull — so a mark asking something of the user is legible
/// from the darkness alone and there is nothing left to correct. What moves
/// to keep that true is the resting level, which threads between them; see
/// ``MatrixTrack/inactiveLevel``.
private enum MatrixTrack {
    /// **Radar**, 36 frames over `1.2s`.
    ///
    /// A beam sweeps clockwise about the mark's centre. A cell goes to full
    /// as the beam crosses its bearing and then decays towards a `0.139`
    /// floor with a time constant of 10.2 frames — `341ms`, so a cell is
    /// still visibly warm a third of a turn later and the sweep reads as one
    /// moving thing rather than as sixteen cells taking turns.
    static let radar: [Double] = [
        1.000, 0.930, 0.853, 0.784, 0.721, 0.664, 0.613, 0.566,
        0.523, 0.485, 0.450, 0.418, 0.389, 0.363, 0.340, 0.318,
        0.299, 0.281, 0.265, 0.251, 0.238, 0.226, 0.215, 0.205,
        0.196, 0.188, 0.181, 0.174, 0.168, 0.163, 0.158, 0.153,
        0.149, 0.146, 0.142, 0.139
    ]
    /// **Advance**, 24 frames over `0.8s`, for the top three rows.
    ///
    /// One column at a time, `200ms` each, left to right. Unlike the other
    /// three patterns nothing here decays: a column is on or it is off,
    /// which is what makes the advance read as a position rather than as a
    /// pulse — the thing being asked for is the next step, not attention.
    static let advance: [Double] = [
        1.000, 1.000, 1.000, 1.000, 1.000, 1.000,
        0.050, 0.050, 0.050, 0.050, 0.050, 0.050,
        0.050, 0.050, 0.050, 0.050, 0.050, 0.050,
        0.050, 0.050, 0.050, 0.050, 0.050, 0.050
    ]
    /// The advance's bottom row, which never moves.
    ///
    /// A floor under the three rows that do, held at a level no other
    /// pattern rests at. It is what stops a single column crossing an
    /// otherwise black mark from reading as a mark that has gone out.
    static let advanceBaseline = 0.300
    /// **Double knock**, 36 frames over `1.2s`, every cell together.
    ///
    /// The whole grid to full twice, `300ms` apart, each knock falling away
    /// with a 3-frame time constant; then `900ms` at `0.05`, which is the
    /// darkest this surface ever goes. The pattern is the one thing on the
    /// bar that has no spatial reading at all — there is nothing to follow
    /// and nowhere to look, only two beats and a silence — and that is why
    /// it is the state that outranks the rest.
    static let doubleKnock: [Double] = [
        1.000, 1.000, 0.731, 0.538, 0.399, 0.300, 0.229, 0.179,
        0.142, 1.000, 1.000, 0.731, 0.538, 0.399, 0.300, 0.229,
        0.179, 0.142, 0.116, 0.097, 0.084, 0.074, 0.067, 0.062,
        0.059, 0.056, 0.055, 0.053, 0.052, 0.052, 0.051, 0.051,
        0.051, 0.050, 0.050, 0.050
    ]
    /// **Lull**, 60 frames over `2s`.
    ///
    /// A crest crosses the mark along its anti-diagonal — the mark's own
    /// seam — and a cell the crest has left sinks to `0.182` and stays down
    /// there about three quarters of a second before the next one reaches
    /// it. The trough is the point: a finished turn is not asking for
    /// anything, so a cell spends a good part of the loop saying nothing.
    /// The mark as a whole never does, because the diagonals are staggered
    /// across four fifths of the loop and one of them always holds the crest.
    static let lull: [Double] = [
        0.359, 0.407, 0.454, 0.505, 0.561, 0.616, 0.673, 0.730, 0.784, 0.834,
        0.884, 0.918, 0.952, 0.975, 0.988, 1.000, 0.988, 0.975, 0.952, 0.918,
        0.884, 0.834, 0.784, 0.730, 0.673, 0.616, 0.561, 0.505, 0.454, 0.407,
        0.359, 0.325, 0.291, 0.263, 0.242, 0.220, 0.210, 0.199, 0.192, 0.188,
        0.183, 0.183, 0.182, 0.182, 0.182, 0.182, 0.182, 0.182, 0.182, 0.183,
        0.183, 0.188, 0.192, 0.199, 0.210, 0.220, 0.242, 0.263, 0.291, 0.325
    ]
    /// Connected and disconnected hold still at a level no live pattern
    /// rests at.
    ///
    /// It threads between the floors the four patterns fall to: above the
    /// `0.05` the knock and the advance drop to, below the `0.182` the
    /// lull's trough holds, and just above the radar's `0.139`. Only the
    /// first of those three gaps is a difference the eye reads as darkness,
    /// and it is the one that has to be — a mark waiting on the user is
    /// three times darker than a resting one, and "the agent wants you"
    /// against "nothing is happening" is the pair it would be worst to
    /// confuse. The other two are ordering rather than contrast, and they do
    /// not have to carry weight on their own: the radar and the lull are
    /// never at their floors everywhere at once, so a live mark always has a
    /// lit cell somewhere and a still one never does.
    ///
    /// It was `0.180` while the lull rested at `0.343`. The design file
    /// brought that trough down to `0.182`, which would have left the two
    /// indistinguishable, so the level came down with it rather than the
    /// ordering being given up.
    static let inactiveLevel = 0.150

    /// The frame the beam reaches this cell on.
    ///
    /// The bearing of the cell's centre from the mark's centre, in a space
    /// where y grows downwards, so the sweep turns clockwise on screen.
    /// Rounded **up**, because a discretely sampled beam lights a cell on
    /// the first frame at or after it crosses; that is the frame the design
    /// file lights, on all sixteen of the cells it draws.
    static func radarOffset(row: Int, column: Int) -> Int {
        let centre = Double(MatrixGrid.side - 1) / 2
        let bearing = atan2(Double(row) - centre, Double(column) - centre)
        let turns = (bearing < 0 ? bearing + 2 * .pi : bearing) / (2 * .pi)
        return Int((turns * Double(radar.count)).rounded(.up)) % radar.count
    }

    /// The frame this cell's column lights on: `200ms` per column.
    static func advanceOffset(column: Int) -> Int {
        column * advance.count / MatrixGrid.side
    }

    /// The frame this cell's anti-diagonal takes the crest.
    ///
    /// The crest crosses the six steps from the first cell to the last in
    /// 48.7 of the loop's 60 frames — a little over four fifths of it — so a
    /// mark is never entirely at rest and never entirely lit.
    static func lullOffset(row: Int, column: Int) -> Int {
        Int((Double(row + column) * 48.7 / 6).rounded())
    }

}

private extension [Double] {
    /// The same loop, started `offset` frames later.
    func delayed(by offset: Int) -> [Double] {
        guard count > 1, offset % count != 0 else { return self }
        return indices.map { self[(($0 - offset) % count + count) % count] }
    }
}

extension NotchMatrixState {
    /// One cell's whole opacity track: the state's curve, delayed by the
    /// number of frames this cell's place in the grid asks for.
    ///
    /// The track is handed to Core Animation as keyframes rather than sampled
    /// per frame. `CAKeyframeAnimation` with linear calculation spreads N
    /// values across N-1 intervals, so ``MatrixIndicatorView/trackAnimation``
    /// closes the loop with a repeat of the first frame before handing it
    /// over — N+1 values across N intervals is the cadence the design file's
    /// N frames are drawn at.
    func track(forCell index: Int) -> [Double] {
        let row = index / MatrixGrid.side
        let column = index % MatrixGrid.side
        switch self {
        case .running:
            return MatrixTrack.radar
                .delayed(by: MatrixTrack.radarOffset(row: row, column: column))
        case .inputNeeded:
            // The bottom row is the baseline the advance crosses above.
            return row == MatrixGrid.side - 1
                ? [MatrixTrack.advanceBaseline]
                : MatrixTrack.advance
                    .delayed(by: MatrixTrack.advanceOffset(column: column))
        case .approvalNeeded:
            return MatrixTrack.doubleKnock
        case .completed:
            return MatrixTrack.lull
                .delayed(by: MatrixTrack.lullOffset(row: row, column: column))
        case .inactive:
            return [MatrixTrack.inactiveLevel]
        }
    }
}

/// The 4×4 status matrix that replaced the notch status dot.
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
    /// row 0 at the top the sum of a cell's row and column is below `side - 1`
    /// above the seam, above it below the seam, and exactly `side - 1` on the
    /// four cells the seam itself passes through.
    enum DiagonalSide: Equatable {
        case above, below, onSeam

        static func of(cell index: Int) -> DiagonalSide {
            switch index / MatrixGrid.side + index % MatrixGrid.side {
            case ..<(MatrixGrid.side - 1): .above
            case MatrixGrid.side - 1: .onSeam
            default: .below
            }
        }
    }

    private var appliedState: NotchMatrixState?
    private var appliedSize: CGFloat = 0
    private var appliedIsAnimated = true
    private var appliedInk = NotchPalette.codexInk
    private var appliedSplit: NotchPalette.MatrixSplit?
    /// What the mark is currently drawing, which the next `apply` compares
    /// against to decide whether the change is one to fade across.
    private var appliedDrawing: NotchMatrixState?
    /// The lit copies of the current pattern, kept because a dissolve needs
    /// them to go on drawing while the next pattern comes up under the pointer.
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
        split: NotchPalette.MatrixSplit? = nil
    ) {
        guard state != appliedState
            || size != appliedSize
            || isAnimated != appliedIsAnimated
            || ink != appliedInk
            || split != appliedSplit else {
            return
        }
        // A dissolve crosses one pattern over another on the same mark. If the
        // mark itself is a different drawing — resized, a different product's
        // ink, the legend's split — there is nothing to cross: the two are not
        // two readings of one thing, and fading between them would say they
        // were.
        let sameMark = size == appliedSize
            && ink == appliedInk
            && split == appliedSplit
        let wasDrawing = appliedDrawing

        appliedState = state
        appliedSize = size
        appliedIsAnimated = isAnimated
        appliedInk = ink
        appliedSplit = split
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

    /// Rebuild the layers, optionally fading out of what was there before.
    ///
    /// `previous` is what the mark was drawing, and is `nil` whenever the
    /// rebuild is for a reason the eye should not see — a window change, a
    /// backing-scale change — or for a mark whose drawing changed underneath
    /// the pattern.
    private func rebuild(dissolvingFrom previous: NotchMatrixState? = nil) {
        guard let state = appliedState, appliedSize > 0, let root = layer else {
            return
        }

        // The copies that stay behind to be faded out, before anything else is
        // torn down.
        let outgoing = Self.dissolves(from: previous, to: state) ? litPasses : []
        appliedDrawing = state

        for sublayer in root.sublayers ?? []
        where !outgoing.contains(where: { $0 === sublayer }) {
            sublayer.removeFromSuperlayer()
        }

        // Proportions come straight from the design file's viewBox, by way of
        // ``MatrixGrid``: 27-unit cells on a 32-unit pitch, 2-unit corner
        // radius, four to a side.
        let size = appliedSize
        let cell = size * MatrixGrid.cell / MatrixGrid.viewBox
        let radius = cell * MatrixGrid.cornerRadius / MatrixGrid.cell
        let pitch = size * MatrixGrid.pitch / MatrixGrid.viewBox
        // Three sigma is where a Gaussian is spent, so this is how far the
        // widest pass reaches. Each pass gets bounds that large or the filter
        // would clip its own halo.
        let bleed = cell * 10.5 / 27 * 3
        let scale = window?.backingScaleFactor ?? 2
        // One reading for every cell of this mark, so the sixteen are on one
        // clock however long the layers take to build.
        let now = CACurrentMediaTime()

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

            for index in 0 ..< MatrixGrid.cellCount {
                let cellLayer = makeCell(
                    ink,
                    side: DiagonalSide.of(cell: index),
                    edge: cell
                )
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
                            now: now
                        ),
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

        // The unlit bed never animates; only the lit copies above it do. It
        // goes in underneath whatever is on its way out, which is drawing the
        // same bed's worth of cells and must stay on top of it.
        root.insertSublayer(
            pass(
                GlowPass(blur: nil, opacity: 1),
                ink: unlit,
                animated: false
            ),
            at: 0
        )

        // Three blurred copies reproduce the SVG's feGaussianBlur + feMerge
        // passes, then the sharp copy sits on top.
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

    /// Whether a change of pattern is crossed over rather than swapped.
    ///
    /// **Only the changes with the still on one side of them.** Those are the
    /// ones where the mark starts or stops having something to say, and cut
    /// they read as a light being thrown: a mark that was a dark square is
    /// suddenly a radar, or a lull the user has just read is suddenly gone.
    /// Neither is a lie about the product, but both are louder than the news
    /// they carry — a turn beginning and a turn being read are quiet events,
    /// and the mark arrives out of the dark and sinks back into it.
    ///
    /// **A change between two live patterns is not faded.** Running to
    /// Completed, Input to Approval: those are the product saying a different
    /// thing, and the cut is the point — there is no moment where the mark is
    /// half of each, because it is never half in one state and half in
    /// another. Fading them would also be the fade the eye reads *least*, both
    /// sides being lit and moving.
    static func dissolves(from previous: NotchMatrixState?, to next: NotchMatrixState) -> Bool {
        guard let previous, previous != next else { return false }
        return (previous == .inactive) != (next == .inactive)
    }

    /// Cross one lit stack over another, and drop the old one when it is spent.
    ///
    /// Both stacks go on drawing for the length of the fade, so a pattern
    /// leaving is still running while it dissolves — a completed mark's crest
    /// keeps crossing as it goes out, rather than freezing on a frame and then
    /// vanishing. The unlit bed under both never moves, because it is the same
    /// bed either way; what fades is only the product's colour over it.
    ///
    /// The two stacks are composited rather than mixed, so a cell midway
    /// through reads a shade above the straight average of the two. At these
    /// opacities that is a fraction of a percent, and it errs towards keeping
    /// the mark lit through the middle of the fade, which is the direction a
    /// dissolve should err in.
    ///
    /// The length and the curve are ``MatrixDissolve``'s and not the panel's,
    /// for the reason written there: the panel's curve is an arrival, and read
    /// as a fade it is a cut with a tail.
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
            // Where a fade is already running, take over from where it has
            // actually got to rather than from the value it was heading for.
            // Two changes inside one dissolve would otherwise jump back up to
            // full before starting down again.
            fade(copy, from: copy.presentation()?.opacity ?? copy.opacity, to: 0)
        }

        // Nothing else is waiting on these, so they are dropped a beat after
        // they stop being visible rather than on a completion the render
        // server has to call back for.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            for copy in outgoing {
                copy.removeFromSuperlayer()
            }
        }
    }

    static let dissolveAnimationKey = "notch.matrix.dissolve"

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
    /// The grid is per-period, so the states that share a period -- running
    /// and approval, both `1.2` -- also sync with each other, while input's
    /// `0.8` and completed's `2` keep their own grids. Within one mark every
    /// cell's animation is added in the same pass with the same anchor, so the
    /// cells stay in phase with each other; the phase each cell then shows is
    /// baked into its own track by ``NotchMatrixState/track(forCell:)``.
    ///
    /// **The loop is closed before it is handed over.** Linear keyframes
    /// spread N values across N-1 intervals, so a 36-frame track drawn at
    /// 30fps would be played back at 34.3ms a frame and the last frame would
    /// cut straight to the first. Repeating the opening frame at the end makes
    /// it N+1 values across N intervals -- the cadence the design file's
    /// frames are drawn at, and a wrap that interpolates like every other
    /// step. It matters most to the radar and the knock, whose tracks end far
    /// from where they begin.
    private static func trackAnimation(
        track: [Double],
        period: TimeInterval,
        now: CFTimeInterval
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = (track + [track[0]]).map { NSNumber(value: $0) }
        animation.duration = period
        animation.calculationMode = .linear
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.beginTime = phaseAnchor(for: period, now: now)
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

/// How a mark crosses between the still and a pattern.
///
/// **Not ``PanelMotion``'s curve, which is what this was and why it could not
/// be seen.** That curve is `(0.22, 1, 0.36, 1)` over `0.20 s`, and it is
/// right for what it was written for: a panel arriving at a size wants to get
/// there and settle, so it spends `83%` of its travel in the first `60 ms` and
/// eases out for the rest. Read as a fade that is a cut with a tail — the mark
/// was fully across before the eye had a chance to catch it mid-way, and the
/// dissolve landed as the hard swap it had replaced.
///
/// A cross-fade is the opposite shape of event: nothing about it is an
/// arrival, and the part worth seeing is the middle, where the mark is
/// genuinely half of each. So it is symmetric — as long coming out of the
/// still as going into it — and long enough to have a middle at all.
enum MatrixDissolve {
    static let duration: TimeInterval = 0.32

    static let timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
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

    static let animation = Animation.timingCurve(0.22, 1, 0.36, 1, duration: duration)

    static let timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)

    /// How long a closing slot waits before it starts shutting.
    ///
    /// Long enough for the mark inside it to be most of the way out — see
    /// ``slot(isOpening:)``.
    static let closingDelay: TimeInterval = 0.05

    /// **Every horizontal movement the collapsed surface makes.** A session
    /// column's room opening and closing, the trailing reading's box growing a
    /// digit or taking a badge, whatever stands after either of those — and,
    /// since the notched bar stopped reserving, the panel's own two edges.
    ///
    /// Opening, it leads: the room is made and the mark arrives into it.
    /// Closing, it waits for the mark to go first — a slot seen shutting on
    /// something still lit reads as that thing being crushed rather than
    /// dismissed, which is the wrong thing to say about a session that ended or
    /// a turn that finished.
    ///
    /// **One declaration, read by the room, by everything the room pushes, and
    /// by the window.** `SessionCountDots` opens and closes the column,
    /// `StatusReadout` and `OverlayHeader` carry what stands after it, and
    /// `OverlayPanelController` moves the panel edge that has to arrive at the
    /// same instant — a notched wing is now exactly as wide as its contents, so
    /// the black edge and the content inside it are two halves of one movement
    /// and cannot be allowed to keep separate time. A pushed thing that keeps
    /// its own timing stops reading as pushed; an edge that keeps its own
    /// timing clips what it is supposed to be revealing.
    ///
    /// AppKit cannot take an `Animation`, so the window reads ``closingDelay``
    /// and ``timingFunction`` directly and this method's asymmetry is spelled
    /// out there rather than duplicated as a second rule.
    static func slot(isOpening: Bool) -> Animation {
        isOpening ? animation : animation.delay(closingDelay)
    }

    /// The same asymmetry as a plain number of seconds, for the window frame.
    static func slotDelay(isOpening: Bool) -> TimeInterval {
        isOpening ? 0 : closingDelay
    }

    /// A mark arriving into a slot, or leaving one: the session dot, a subagent
    /// badge, the collapsed elapsed reading.
    ///
    /// **It trails the room rather than matching it.** ``slot(isOpening:)`` is
    /// a hard ease-out that is most of the way open early; run the two together
    /// and the mark is at full ink inside a slot that has not finished making
    /// space for it — and on the notched bar, where the slot is now the panel's
    /// own edge, at full ink over the cut-out. Leaving is quicker than
    /// arriving, for the reason every reading on this surface fades out quicker
    /// than it fades in: something starting is worth catching and something
    /// ending is not. It is also what lets ``closingDelay`` be as short as it
    /// is — by the time the room begins to shut, the mark is most of the way
    /// gone.
    static func fade(isArriving: Bool) -> Animation {
        isArriving
            ? .easeOut(duration: fadeInDuration).delay(fadeInDelay)
            : .easeOut(duration: fadeOutDuration)
    }

    static let fadeInDelay: TimeInterval = 0.06
    static let fadeInDuration: TimeInterval = 0.12
    static let fadeOutDuration: TimeInterval = 0.08
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

    var body: some View {
        SweepingLabel(
            text: text,
            font: font,
            isSweeping: isSweeping
        )
        .accessibilityHidden(true)
    }
}

private struct SweepingLabel: NSViewRepresentable {
    let text: String
    let font: NSFont
    let isSweeping: Bool

    func makeNSView(context: Context) -> SweepingLabelView {
        SweepingLabelView()
    }

    func updateNSView(_ view: SweepingLabelView, context: Context) {
        view.apply(text: text, font: font, isSweeping: isSweeping)
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

    func apply(text: String, font: NSFont, isSweeping: Bool) {
        let textChanged = text != appliedText || font != appliedFont
        guard textChanged || isSweeping != appliedIsSweeping else { return }

        let previousText = appliedText
        let previousGlyphs = baseLayer.contents
        let previousGlyphSize = glyphSize
        let previousScale = baseLayer.contentsScale

        appliedText = text
        appliedFont = font
        appliedIsSweeping = isSweeping

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

        let duration = PanelMotion.duration
        let timing = PanelMotion.timingFunction

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
/// Layer-backed for the same reason the notch readout is — a sweeping row cost
/// ~7% of a core as a `TimelineView`, a running turn replaces its body text
/// constantly, and the expanded panel shows up to three rows at once — but it
/// also owns the trailing fade its caller used to apply. A SwiftUI `.mask` over
/// an AppKit view is not dependable, and the fade is the row's own behaviour
/// rather than the caller's, so both masks live on the layer: the fade on the
/// container, the sweep on the bright copy.
struct SessionRowText: View {
    let text: String
    let font: NSFont
    let color: NSColor
    let lineHeight: CGFloat
    /// Whether a highlight crosses these glyphs.
    ///
    /// The row's body line only, and only while its turn is unfinished. It is
    /// the channel that answers *live or finished* — the one thing here that
    /// can be read without looking straight at the panel, which is how a
    /// menu-bar surface is actually watched. A finished row's body is the
    /// answer its turn produced, and a highlight moving across a finished
    /// answer says work is happening where none is.
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
        // Takes the width it is offered, like the GeometryReader it replaced,
        // and lets the glyphs overflow and fade rather than shrinking the row.
        CGSize(
            width: proposal.width ?? nsView.intrinsicContentSize.width,
            height: lineHeight
        )
    }
}

final class SessionRowTextView: NSView {
    /// Loop length of one traverse, the notch label's own.
    static let sweepPeriod: TimeInterval = 2
    /// Distance over which the last glyphs fade out, matching the gradient the
    /// caller used to apply as a separate SwiftUI mask.
    private static let trailingFadeWidth: CGFloat = 48

    private let baseLayer = CALayer()
    private let highlightLayer = CALayer()
    private let sweepMask = NotchTextRaster.makeSweepMask()
    private let fadeMask = CAGradientLayer()
    private var appliedText = ""
    private var appliedFont = NSFont.systemFont(ofSize: 13, weight: .light)
    private var appliedColor = NSColor.white
    private var appliedSweeps = false
    private var renderedScale: CGFloat = 0
    /// The glyph size actually drawn, which is the natural text size clipped to
    /// the row. Only this much is ever visible, and every byte beyond it is a
    /// texture upload per update that nothing can see.
    private var renderedGlyphSize: CGSize = .zero
    /// Geometry the running sweep was built for, so an unchanged one is left
    /// alone rather than torn down and rebuilt on every text update.
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
            // No `invalidateIntrinsicContentSize` here on purpose. This view is
            // always given the width it is offered, so its intrinsic size never
            // decides the layout -- invalidating it only makes SwiftUI re-measure
            // and re-lay-out the subtree, once per row for every update, and a
            // running turn's body text updates constantly.
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
        highlightLayer.frame = glyphFrame

        fadeMask.frame = bounds
        let width = max(bounds.width, 1)
        let fadeStart = max(0, width - Self.trailingFadeWidth) / width
        fadeMask.locations = [0, NSNumber(value: fadeStart), 1]

        if appliedSweeps {
            // The sweep crosses what is *visible*, not the whole string. A
            // 240-character body line is three times the row, so a band scaled
            // to the glyphs spends most of its loop off-screen -- the highlight
            // degrades to a 0.13s flicker once every two seconds. Bounding it to
            // the row keeps one full, even pass however long the text is.
            //
            // It also makes the sweep's geometry independent of the text, which
            // is what lets the reinstall below be skipped: a running turn
            // replaces this text constantly, and re-adding the animation each
            // time is a CATransaction commit per row per update.
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
        // Replacing `contents` is an animatable change on a plain sublayer, so
        // Core Animation would cross-fade it. Body text is replaced as a turn
        // makes progress, and fades that outlive the gap between updates pile
        // up into a smear; the text it replaced swapped instantly.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard !appliedText.isEmpty else {
            baseLayer.contents = nil
            highlightLayer.contents = nil
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
        // The bright copy, which the band uncovers a slice of at a time. Drawn
        // even on a row that is not sweeping: `highlightLayer` is hidden there,
        // and rasterising on the transition instead would cost a texture upload
        // at the moment a turn changes state.
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
