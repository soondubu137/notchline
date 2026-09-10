import AppKit
import Combine
import CoreImage
import SwiftUI

/// Colours the notch surface owns, mirroring the Figma variables of the same name.
enum NotchPalette {
    // The matrix draws through Core Animation, which needs CGColor, while the
    // rest of the surface is SwiftUI. Both come from these components so the two
    // representations cannot drift apart.
    private static let labelRGB = (red: 0.486, green: 0.486, blue: 0.502)

    /// One mark's two colours.
    ///
    /// **Hue says nothing at all**, and that is the decision rather than an
    /// omission (`colour-v2.md` §1): it used to say which product, and no
    /// product owns one now. What is left is brightness, which says whether
    /// something wants the user; presence is carried by the mark's *existence*
    /// rather than by any colour here.
    nonisolated struct MatrixInk: Equatable, Sendable {
        let offRed, offGreen, offBlue: Double
        let onRed, onGreen, onBlue: Double

        var off: Color { Color(red: offRed, green: offGreen, blue: offBlue) }
        var on: Color { Color(red: onRed, green: onGreen, blue: onBlue) }
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
        ///
        /// **Always lifted off black, never off a row's own fill.** A live
        /// row does wash a little under the pointer or while pressed
        /// (``RowEmphasis``), but the lift here is measured off the raw
        /// channel values regardless, so a tile sitting on the row never
        /// itself brightens with it -- it stays the one badge on the surface
        /// that does not answer to hover.
        var chipFill: Color {
            Color(
                red: min(1, offRed + Self.chipLift),
                green: min(1, offGreen + Self.chipLift),
                blue: min(1, offBlue + Self.chipLift)
            )
        }
        /// How far ``chipFill`` is lifted off the unlit colour towards white.
        ///
        /// `#151515` becomes `#242424` for the resting grey. Landed on by
        /// looking at it: below this the tile still sank into the panel,
        /// above it the fill started competing with the numeral it carries.
        private static let chipLift = 0.06
        /// The lit colour as AppKit draws it, at whatever weight is asked for.
        ///
        /// The answer field is a hosted `NSTextView` drawing its own ground
        /// (`answer-in-notch.md` §7), so it needs this ink in AppKit's own
        /// representation rather than SwiftUI's — from the same components, so
        /// the two cannot drift.
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

    /// The one ink this surface owns: the aggregate mark, every product badge,
    /// and now the row's own edge and halo under the pointer.
    ///
    /// **Hue stopped being identity when the marks folded into one.** With a
    /// matrix per product, hue was the only thing saying which product a mark
    /// belonged to; with one aggregate mark there is no product to name, so the
    /// channel was free for taste instead (`compact-view-v2.md` §2.2).
    ///
    /// Sage · hint, `#1B1F1C` → `#DEE8E0`: the hue furthest in OKLCH from both
    /// products at once (`150°`, `108°` from each, the maximum any hue can be),
    /// so the aggregate can never read as a dim Codex or a dim Claude Code.
    /// Both lightnesses are the greyscale's own — `#E5E5EA` lit and `#1E1E1E`
    /// unlit — because **brightness is this surface's attention channel**, and
    /// a value able to dim the mark asking for a person would be a value that
    /// changes what the mark means.
    ///
    /// **A single value rather than a preference.** This surface offered a
    /// twelve-way picker for it once; the choice cost a Settings row and a
    /// stored default for a difference nobody asked to see again, so the
    /// picker is gone and this is what every install draws. Changing the
    /// app's ink later is still exactly this one edit — every reader below
    /// reaches it through this name, never through a literal hex pair of its
    /// own.
    static let themeInk = MatrixInk(
        offRed: 0x1B / 255, offGreen: 0x1F / 255, offBlue: 0x1C / 255,
        onRed: 0xDE / 255, onGreen: 0xE8 / 255, onBlue: 0xE0 / 255
    )

    /// The aggregate mark's ink: ``themeInk`` once something is behind it, the
    /// resting grey until then.
    ///
    /// ``restingInk`` is not tinted and must not be: `#151515` means *nothing
    /// is connected*, and colouring it would say the theme applies to a state
    /// with no agent in it. The ink arrives with the first connection.
    nonisolated static func matrixInk(isConnected: Bool) -> MatrixInk {
        isConnected ? themeInk : restingInk
    }

    /// A step brighter than ``label``, for a caption the pointer has reached.
    ///
    /// `#9A9A9E` — enough to read as the row answering, not enough to compete
    /// with the reading ink or the title. Used wherever a plain SwiftUI `Text`
    /// carries ``label`` and the row it sits in is under the pointer or held
    /// down; the layer-backed title and preview lines do not read it; see
    /// ``RowEmphasis``.
    static let labelEmphasized = Color(
        red: 0x9A / 255, green: 0x9A / 255, blue: 0x9E / 255
    )

    /// What a row draws under the pointer, and it is not one answer: a row
    /// washes, a folding bar does not.
    ///
    /// **A session row fills in ``themeInk``'s lit colour.**
    /// It tried a border and a halo for a while — traced the edge instead of
    /// repainting the ground — and that read as a wire drawn around the row
    /// rather than as the row answering. A fill is back, but not the flat
    /// `#2B2B2E` it was before: this one is the app's own ink at a low
    /// opacity, so it is still black doing the answering, only lifted, never a
    /// grey invented for the occasion. Faintly was the first reading of *low*
    /// and it was too faint to see — the weights below say where it landed.
    ///
    /// **A retired row takes exactly that fill, at exactly those weights.**
    /// ~~It took a short mark of ``themeInk`` at its leading edge instead, on
    /// the grounds that a half-height bar has no room either side for a wash to
    /// read as a shape~~ — **superseded**: it does have the room, the wash
    /// reads as a shape there, and the two marks side by side said the rows
    /// under the rule were a different kind of thing to click. They are not.
    /// One click, one target, one answer to the pointer.
    ///
    /// **The two folding bars still never fill, and take no mark either.**
    /// Nothing stacks under them for a leading-edge flag to pick out and they
    /// are headings rather than rows, so a wash read as a bar growing in front
    /// of a heading. They answer the pointer with the brightened label and
    /// chevron alone.
    enum RowEmphasis {
        /// Every row on this panel that fills: a live session row, the row
        /// held open for an answer, and a retired row.
        ///
        /// **Two weights up from where the wash started**, because at `0.08`
        /// (`L 0.184`) it was so faint on a real bar that the row read as not
        /// answering at all — the point of a wash is that the pointer's row is
        /// obvious without anything moving, and this one had to be looked for.
        ///
        /// **`0.12`–`0.14` is not available, and the reason is on the row.**
        /// A product badge draws its own opaque ground at `L 0.234` and does
        /// not wash with the row it sits on (see ``MatrixInk/chipFill``), so a
        /// wash in that band erases the badge's boundary at exactly the moment
        /// the pointer is on it. `0.20` does the same to the subagent chip's
        /// `L 0.296`. `0.16` (`L 0.263`) is the nearest weight that is plainly
        /// brighter and still clears both by about `0.03` — the badge reads as
        /// an inset, the chip as a lift, which is what `colour-v2.md` §10
        /// question 02 asked for.
        ///
        /// The pressed weight moves with it, keeping the same step between
        /// the two states the eye was already reading (`ΔL ≈ 0.08`) rather
        /// than collapsing press into hover.
        static let sessionHoverFillOpacity: Double = 0.16
        static let sessionPressedFillOpacity: Double = 0.24

        /// Quiet request buttons need a visible tile on the open row's
        /// `0.16` theme wash. The former `0.08` rest and `0.04` hover almost
        /// disappeared into it, especially when hovering deepened the fill.
        /// Default theme: approximately #505451 at rest and #454846 on hover,
        /// against #242524. Resting text retains a 4.57:1 contrast ratio.
        /// Options remain list regions and keep their separate hover wash.
        static let controlRestFillOpacity: Double = 0.24
        static let controlHoverFillOpacity: Double = 0.18

        /// A dark charcoal fill with the theme hue, and nothing else — the
        /// tile is a shape made of ground, not a shape drawn with a line.
        ///
        /// ~~A fine edge separates the tile from black without lightening its
        /// entire surface.~~ **Superseded**: the edge at `0.40` was the
        /// brightest mark in the About panel, brighter than the text it
        /// framed, so the eye read the outline before the label. Without it
        /// the fill has to be the whole of the boundary, and `0.22` (`#313330`)
        /// was carrying a border rather than standing on its own — too pale
        /// for a control that promises nothing yet.
        ///
        /// `0.14` lands at about `#1F201F`, `L∗ 12` against the panel's black:
        /// plainly a tile, never a panel of its own. The hover step is `0.04`
        /// rather than the `0.06` a bordered tile could afford, because with
        /// the edge gone the fill is the only thing that moves and a larger
        /// step read as the button lighting up rather than answering.
        static let plainControlRestFillOpacity: Double = 0.14
        static let plainControlHoverFillOpacity: Double = 0.18

        /// Ease-in-out both ways -- the same gentle acceleration and
        /// deceleration whether the emphasis is arriving or leaving -- and
        /// still faster to leave than to arrive, the one asymmetry worth
        /// keeping.
        static let hoverEnterDuration: Double = 0.13
        static let hoverExitDuration: Double = 0.09
        static let pressEnterDuration: Double = 0.08
        static let pressExitDuration: Double = 0.10
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
    /// White glyph emphasis. Request controls keep their theme hue on hover.
    static let spotlight = Color.white

    /// The one bright ground this surface fills, and the ink drawn on it.
    ///
    /// ``themeInk``'s lit value — `#DEE8E0`, `L∗ 91` — which already draws the
    /// aggregate mark on the collapsed bar and the text of every product badge.
    /// A filled area in it is still by a wide margin the loudest thing in a list
    /// of `#7C7C80` readings, and unlike white it is *this app's*: the row's
    /// mark and the chip naming its product are then one ink, mirrored, rather
    /// than a house colour beside a borrowed one.
    ///
    /// It is deliberately one name for both meanings the bright ground carries
    /// — *this row wants a person* on the list, and *this is what `⏎` does*
    /// inside an open row — because it is one object: the ground the pointer
    /// pressed grows and travels down to the answer row (`answer-in-notch.md`
    /// §3.1), and a ground that changed colour on the way would be two.
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
    /// What is drawn on ``brightGround``: the same ink's unlit end, `#1B1F1C`,
    /// at `13.3 : 1`.
    ///
    /// Not black and not ``label``: the pair inverts within one ink, which is
    /// what makes a mark on the bright ground and a product badge on the dark
    /// one legibly the same family and legibly opposite.
    static var onBrightGround: Color { themeInk.off }
    /// What ``brightGround`` is drawn at while it is still growing out of the
    /// caption line and has not become a target yet (`answer-in-notch.md` §6.3).
    ///
    /// This opacity is set by text contrast, independently of the quiet
    /// buttons' rest and hover fills. It was
    /// `0.45`, where ``onBrightGround`` on it is `4.0 : 1` — under AA for the
    /// `13` pt light label it carries, for as long as the ground takes to
    /// travel. This is the first weight up the ladder that clears it, at
    /// `6.4 : 1`, and it still sits about `25` L∗ below the landed ground, so
    /// it says *not yet* exactly as plainly as the dimmer value did.
    ///
    /// A ground at this weight does not answer the pointer either — see
    /// ``requestHoverGround``, which is what the landed ground takes and this one must
    /// not, because it is not yet a thing a click can take.
    static let arrivingGroundOpacity: Double = 0.64
    /// Session title — the one element that stays bright.
    static let sessionTitle = Color.white.opacity(0.98)
    /// `#C7C7CC` — the step between the title's white and ``label``'s
    /// `#7C7C80`.
    ///
    /// The same value ``countsSessionDrawingColor`` draws the sessions numeral
    /// in, in SwiftUI's representation: on the footer it is the figure in every
    /// spend, which is the brightest thing in the table's three levels
    /// (`quota-footer-v2.md` §5).
    static let reading = Color(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xCC / 255)
    /// The ground a request's machine text is set on.
    ///
    /// `#242424`, and the same value the resting mark's own tile lands on — this
    /// surface has one recessed step and both readers take it. It exists to mark
    /// *machine text*: a string a machine will execute, as against sentences a
    /// person is meant to read, which take no ground at all
    /// (`answer-in-notch.md` §4.2). Putting prose on it would make the mark mean
    /// nothing, which is why the setting is decided by the payload a request came
    /// from and never by how long it is.
    static let recessedGround = Color(
        red: 0x24 / 255,
        green: 0x24 / 255,
        blue: 0x24 / 255
    )
    /// A reading on ``brightGround``: an option's numeral and its description
    /// while that option holds the ground.
    ///
    /// `#5A5A5E` (§5.1). The dark end of the same inversion the badge and the
    /// waiting mark already make — the label goes to ``onBrightGround`` and
    /// everything beside it goes here, so the option keeps its two levels on
    /// the bright ground exactly as it has them on black. It is `5.3 : 1` on
    /// `#DEE8E0`, so the step survived the ground ceasing to be white.
    static let readingOnLight = Color(
        red: 0x5A / 255,
        green: 0x5A / 255,
        blue: 0x5E / 255
    )

    /// An option's numeral, one step below its own description.
    ///
    /// `#6E6E73` (§5.1), which is dimmer than ``label`` — the numeral is a
    /// handle rather than a reading, and once the digits are bound it is what a
    /// person's eye goes to rather than what it dwells on.
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
    /// The sessions numeral, which is the brighter of the counts column's two
    /// steps (`compact-view-v2.md` §3.2 rule 01).
    ///
    /// **Hierarchy here is size and brightness, never hue.** Hue meant "which
    /// product" and there is no product left for a collapsed numeral to name;
    /// white stays reserved for attention, which this column never signals. The
    /// subagent numeral is ``labelDrawingColor`` — `#7C7C80`, the dim step this
    /// surface already draws every reading in — so the pair is one existing
    /// ramp rather than a new one.
    static let countsSessionDrawingColor = NSColor(
        srgbRed: 0xC7 / 255,
        green: 0xC7 / 255,
        blue: 0xCC / 255,
        alpha: 1
    )
    /// The dot that says a turn has finished, on the notch and on a row alike.
    ///
    /// **The sessions numeral's own ink, and that is the whole of the choice.**
    /// This mark used to be ``labelDrawingColor`` — `#7C7C80`, the dim step
    /// every reading takes — which put it a step *below* the figure it stands
    /// in front of, on a surface where brightness is the only thing that says
    /// a person is wanted. A finished turn nobody has read wants one. `#C7C7CC`
    /// is where this surface already puts that meaning, and it is the value the
    /// count beside the mark is drawn in, so the dot has a ceiling it is
    /// *equal* to rather than a new brightness of its own: on the notch the
    /// breath's crest is exactly the numeral and never past it.
    static var finishedDotDrawingColor: NSColor { countsSessionDrawingColor }
    /// Every rule this panel draws: the one under the band, a block heading's,
    /// and the seam's — `1` pt of white at `15%`.
    ///
    /// Declared because a fourth thing takes it now. The dot between a block's
    /// badge and its count is *chrome rather than caption*
    /// (`expanded-panel-v2.md` §4.2), which is a claim about being the same
    /// value as the rule it sits on rather than about being a faint grey — so
    /// the two are written once and cannot drift into being nearly the same.
    ///
    /// The scroll rail's track is not one of these. It reads the same value and
    /// means something else — how far there is to travel — so it keeps its own.
    static let hairline = Color.white.opacity(0.15)
    /// The same ink where SwiftUI draws the mark — a row's still dot.
    static var finishedDot: Color { reading }
    /// The searchlight that sweeps a row's text, which is the one white left on
    /// this surface that the pointer did not put there — and it brightens
    /// glyphs rather than filling an area. See ``spotlight``.
    static let spotlightDrawingColor = NSColor.white
    static let sessionTitleDrawingColor = NSColor.white.withAlphaComponent(0.98)
    /// ``onBrightGround`` for the layer-backed readings, which draw through
    /// AppKit rather than SwiftUI.
    static let onBrightGroundDrawingColor = NSColor(
        srgbRed: themeInk.offRed,
        green: themeInk.offGreen,
        blue: themeInk.offBlue,
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
            // Spoken by the row or the panel header, which say what the figure
            // counts and whose it is -- this mark alone is a bare number with
            // no label VoiceOver can read.
            .accessibilityHidden(true)
    }

    /// Dim while everything it counts is running, bright the moment one of them
    /// is stopped on a question.
    ///
    /// The bright end is ``NotchPalette/brightGround`` -- the app's own ink,
    /// not white, and it moves with the waiting row's mark rather than on its
    /// own account: the two are the same tile in the same slot, and one of
    /// them staying white would leave a single white mark in a column whose
    /// bright marks are all the ink. The dim end is
    /// ``NotchPalette/MatrixInk/chipFill`` lifted off black -- always black,
    /// now that a session row's own fill no longer brightens under the
    /// pointer or while held down.
    private var groundFill: Color {
        guard badge.wantsAttention else {
            return NotchPalette.restingInk.chipFill
        }
        return NotchPalette.brightGround
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

enum SessionDotBreath {
    /// Slower than every track in ``MatrixTrack``; pinned by
    /// `theBreathIsSlowerThanAnythingTheMatrixRuns`.
    static let period: TimeInterval = 2.8

    /// **Full, and the ceiling is somebody else's value.** ~~Steady, and a
    /// little under full: the column rests at `0.85` and the breath only ever
    /// leaves that value, so it never draws brighter than a resting column.~~
    /// ~~A version that went to `1.0` was tried and dropped — it made the
    /// column the brightest thing in the leading wing for part of every cycle,
    /// and bought that by breaking the one value this mark has always had.~~
    ///
    /// **Superseded, with the carrier.** There is no column: what breathes is
    /// one dot in the *trailing* wing, standing in front of a reading, and it
    /// has no resting appearance of its own to keep faith with. What holds it
    /// under the surface's own ceiling now is the ink rather than the opacity —
    /// ``NotchPalette/finishedDotDrawingColor`` is the sessions numeral's
    /// `#C7C7CC`, so the crest of every breath is *exactly* that numeral and
    /// never past it. `0.85` of it would have been a mark that only ever
    /// approached the value it was told to reach.
    static let restingOpacity: Double = 1.0

    /// The bottom of the swing.
    ///
    /// **`0.55` of amplitude, all of it below the crest.** The first version
    /// swung `0.35` and was too quiet to catch on a screen; this is wider than
    /// that. It is the same amplitude it has always been — the crest moved and
    /// the movement did not, because the movement is what was tuned against a
    /// screen and the crest is what the ink was chosen for.
    ///
    /// It goes this low because the dip is **momentary**. A mark held at the
    /// floor would stop being legible, which is exactly why "dim the marks that
    /// are not yours" was rejected when this page was drawn — but one that
    /// returns to its crest every `2.8 s` is legible for most of its cycle and
    /// never stops being a mark. What must hold at every instant is the weaker,
    /// checkable thing: it stays clearly brighter than the extinguished matrix
    /// across the bar, so a breathing dot never reads as a mark going out.
    /// Pinned by `theBreathsFloorStaysAboveTheMarkItStandsBeside`, which is
    /// asked of the dot's own ink now that the two differ.
    static let floorOpacity: Double = 0.45

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

/// How the middle hands one name to the next.
///
/// **One movement handed over, not two fades.** The name going out draws in
/// towards its own middle as it goes; the name coming in resumes at exactly
/// the size the last one reached and opens back out to full. The size is
/// continuous across the swap, so the pair reads as the slot being passed from
/// one word to the next rather than as one mark being swapped for another —
/// which is why ``scale`` is one constant read by both halves rather than a
/// figure each.
///
/// **It is not a cross-fade, and that is the whole of the design.**
/// ``MatrixDissolve`` crosses two patterns straight through their middle
/// because a matrix is an abstract figure and genuinely reads as half of each
/// there. Two words do not. They are drawn in one face from one leading edge,
/// so a frame holding both at half ink holds neither, and the glyphs of the
/// two collide exactly where the eye is. The halves are therefore offset in
/// time: the one leaving is short and starts at once, the one arriving is half
/// again as long and waits until the first is nearly spent. Sampled across the
/// whole handover, the most ink two names ever carry at one instant is about
/// `13%` each — `#1a1a1a` on this ground, under one legible word — and the
/// slot is never emptier than that either. Both halves of that are read off
/// the curves by
/// `neitherNameHoldsTheMiddleWhileTheOtherIsStillInIt`.
///
/// **What it does take from ``MatrixDissolve`` is the finding underneath it**:
/// a swap wants a middle, and ``PanelMotion``'s curve does not leave one.
enum ProjectNameHandover {
    /// How far in a name draws before it goes, and the size the next one
    /// resumes at.
    ///
    /// At `13` pt that is `0.9` pt off the cap height and, on `notchline`'s
    /// `55.10`, `2.8` pt off each end: a name receding, which is what the
    /// middle wants — the roster is a quiet channel and a Project name never
    /// signals attention. `0.80` is a zoom and puts the loudest movement on
    /// this surface under the one reading that means nothing urgent; `0.95`
    /// leaves a short name with nothing to move, since the width channel is
    /// the length of the word and the height channel is `0.5` pt.
    static let scale: CGFloat = 0.90

    /// The name going out. It starts the instant the name changes.
    static let leavingDuration: TimeInterval = 0.16

    /// How long the name coming in waits before it starts.
    ///
    /// **Past the leaving name's own midpoint**, so the middle is never held
    /// by two words at once — and short of its end, so the slot is never seen
    /// empty: the arriving name is already a fifth of the way up as the
    /// leaving one finishes. The `60 ms` those two bounds leave is the whole
    /// overlap, and both names spend it under `13%`.
    static let arrivingDelay: TimeInterval = 0.10

    /// The name coming in.
    ///
    /// Half again as long as the one going out, for the reason every reading
    /// on this surface fades in slower than it fades out
    /// (``PanelMotion/fade(isArriving:)``): something starting is worth
    /// catching and something ending is not.
    static let arrivingDuration: TimeInterval = 0.24

    /// End to end: `0.34 s`, against the `5 s` a name is held.
    static var duration: TimeInterval { arrivingDelay + arrivingDuration }

    /// **From rest, and too short to stall.** The name was standing still, so
    /// a curve carrying speed at its start reads as a snatch; symmetric gives
    /// it the still beginning, and over `0.16 s` the tail an `easeInEaseOut`
    /// parks in is too brief to be seen doing it.
    static let leavingTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

    /// **An arrival, and one of the few places on this surface where that is
    /// the right shape.**
    ///
    /// Deliberately not ``PanelMotion``'s `(0.22, 1, 0.36, 1)`, which is `96%`
    /// across at its own midpoint: over `0.24 s` it would have the name at
    /// full size inside `80 ms` and there would be no expansion left to see —
    /// the same failure ``MatrixDissolve`` was written to undo, arriving by
    /// the same route.
    static let arrivingTimingFunction = CAMediaTimingFunction(name: .easeOut)

    /// The name leaving: in towards its own middle, and out.
    ///
    /// It leaves from where the name has *actually* got to rather than from
    /// full — ``MatrixIndicatorView/crossFade(from:to:)``'s rule, for the same
    /// reason: a second change inside one handover would otherwise jump the
    /// name back to full ink at full size before starting away again.
    static func leaving(fromOpacity: Float, fromScale: CGFloat) -> CAAnimationGroup {
        let ink = CABasicAnimation(keyPath: "opacity")
        ink.fromValue = fromOpacity
        ink.toValue = 0
        let size = CABasicAnimation(keyPath: "transform.scale")
        size.fromValue = fromScale
        size.toValue = scale
        return group(of: [ink, size], over: leavingDuration, on: leavingTimingFunction)
    }

    /// The name arriving: out of the middle the last one drew into, and up.
    static func arriving(now: CFTimeInterval = CACurrentMediaTime()) -> CAAnimationGroup {
        let ink = CABasicAnimation(keyPath: "opacity")
        ink.fromValue = 0
        ink.toValue = 1
        let size = CABasicAnimation(keyPath: "transform.scale")
        size.fromValue = scale
        size.toValue = 1
        let arriving = group(of: [ink, size], over: arrivingDuration, on: arrivingTimingFunction)
        arriving.beginTime = now + arrivingDelay
        // Held at its start values through the wait rather than at the layer's
        // own, or the new name stands at full ink for the length of the delay
        // and the handover is a cut with a fade after it.
        arriving.fillMode = .backwards
        return arriving
    }

    /// The two channels of one half, as a single animation.
    ///
    /// The curve goes on each channel rather than on the group: a group's own
    /// timing function warps the clock its children run on, so declaring it in
    /// both places composes two curves rather than stating one twice.
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

/// The pill's middle: **the name of the work**.
///
/// Nothing on any collapsed form has ever named it. The mark says what is most
/// urgent, the numerals say how much, the clock says how long — and with five
/// checkouts open, the Project is the fact that decides whether you interrupt
/// yourself, which all three of them leave unanswered
/// (`compact-view-v2.md` §6.2).
///
/// **It cycles**, `5 s` each, because the middle belongs to no one row. The
/// clock does not follow it: the reading stays the longest unfinished turn
/// anywhere, so the bar stops claiming to be one row's report and becomes what
/// it is — two totals, a clock, and a rotating roster of the work behind them,
/// with no term pretending to describe another.
///
/// > The cost, stated plainly: for one frame in every *N*, the name beside an
/// > urgent mark is a Project that is not the one waiting. The rotation is what
/// > makes that legible over a few seconds; a static glance cannot distinguish
/// > it. This is the weakest point in the V2 collapsed surface and the thing to
/// > watch first on a real menu bar.
struct RotatingProjectName: View {
    /// Every Project with an active row, in the panel's own order,
    /// deduplicated, first occurrence winning.
    let names: [String]
    /// What `230` has left once the anchored ends are taken out.
    let width: CGFloat

    var body: some View {
        ProjectNameMarquee(names: names, width: width)
            .frame(width: width, height: PanelMetrics.readingGroundHeight)
            // Spoken by the panel's own label, which names the whole list
            // rather than whichever one the rotation is on.
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

/// The name, on a layer, with the rotation driven off a timer of its own.
///
/// **Nothing here re-renders the overlay.** A handover every five seconds
/// through SwiftUI would invalidate the whole panel twelve times a minute and
/// animate it for a third of a second each time — the same shape of cost as the
/// once-a-second readout that `AGENTS.md` §7 was written about. So the rotation
/// is two layers moving against each other under Core Animation, and the
/// SwiftUI graph never hears about it.
///
/// **Two layers, because the two halves move in opposite directions.** A
/// `CATransition` crosses one layer's old contents into its new ones, which is
/// what this was; but a transform on that layer scales the old and the new
/// together, so a name cannot draw in while the next one opens out. The name
/// on screen is therefore handed to a layer of its own and leaves from there
/// (``ProjectNameHandover``).
final class ProjectNameView: NSView {
    /// The name in the slot.
    private let ink = CALayer()
    /// The name leaving it: empty and unlit except during a handover.
    private let departing = CALayer()
    private let fade = CAGradientLayer()

    private var names: [String] = []
    private var width: CGFloat = 0
    private var index = 0
    private var timer: Timer?
    /// The glyph box last rasterised, which is what ``layout()`` centres. Held
    /// because placing the layer and drawing into it happen at different
    /// moments -- see ``layoutInk()``.
    private var renderedSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        // The arriving name in front of the departing one, though at the ink
        // the two ever share at once it is not a difference anyone can see.
        for glyphs in [departing, ink] {
            glyphs.contentsGravity = .bottomLeft
            // **Both turn about their own glyph box's middle.** It is the
            // default, and it is written out because the whole shape of the
            // handover rests on it: anchored at the leading edge a name would
            // draw sideways into the margin, and anchored on the slot it would
            // slide as it shrank. Anchored here it recedes into itself.
            glyphs.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.addSublayer(glyphs)
        }
        // At rest the departing layer is unlit, so the only thing that ever
        // shows it is the animation taking it away.
        departing.opacity = 0
        // The trailing fade, as a mask: opaque across everything but the last
        // `12`, where it runs out. Read as a mask, so only alpha matters.
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
        // **The cycle holds its place when the set changes.** A Project joining
        // or leaving does not restart it: the name that was on screen keeps the
        // slot it is in, and only a name that has actually gone moves anything.
        if let previous, let kept = names.firstIndex(of: previous) {
            index = kept
        } else if index >= names.count {
            index = 0
        }
        // One Project does not cycle; it is simply named. None draws nothing.
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
        // The overlay's run loop is in common modes while a menu is tracking,
        // and a name frozen mid-cycle behind a menu reads as a stall.
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
        // Before anything overwrites what is on screen, and including the case
        // where nothing follows it: the last Project leaving the list takes
        // its name out the way every other name goes, rather than blinking off.
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

    /// The name on screen moves to the departing layer and leaves from there,
    /// so the two halves of the swap can move against each other.
    ///
    /// A handover landing on top of one still running takes the departing
    /// name's start values from where it has *actually* got to, so a Project
    /// joining the list a fifth of a second after the rotation advanced does
    /// not snap the outgoing name back to full ink before dismissing it.
    /// Whatever was already departing is dropped at that instant: a third
    /// layer would carry it, and two names inside `0.34 s` is not a sight this
    /// surface can produce twice in a row.
    private func handOver() {
        guard ink.contents != nil else { return }
        let shown = ink.presentation()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        departing.contents = ink.contents
        departing.contentsScale = ink.contentsScale
        // Its own geometry rather than the new name's, which is a different
        // width: what leaves has to leave from where it stood.
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
    /// **Placed on every layout rather than only where they are drawn.**
    /// SwiftUI builds an `NSViewRepresentable` before it sizes it, so
    /// `makeNSView` and the update that follows both run against a zero
    /// `bounds` -- and a centring done only there reads `(0 - 16) / 2` and
    /// leaves the name half its own height below the slot, with the mask taking
    /// the top off it. That is what shipped: the pill's middle drew the lower
    /// half of a name sunk `8` pt, and it stayed that way until something
    /// happened to redraw it, which for a single Project is never, because one
    /// Project does not cycle.
    ///
    /// Splitting it costs nothing this view was avoiding. The raster is the
    /// expensive half and still runs only when the name changes; this is
    /// arithmetic against two sizes, and it has to run wherever either of them
    /// can move.
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

    /// The layer the name in the slot is drawn on, and the one a name leaves
    /// on. Exposed for the tests that read where each of them stands.
    var nameLayer: CALayer { ink }
    var departingNameLayer: CALayer { departing }
    /// Exposed for the test that the rotation is a Core Animation handover
    /// rather than a SwiftUI one.
    var arrivingAnimation: CAAnimation? { ink.animation(forKey: Self.arrivingKey) }
    var leavingAnimation: CAAnimation? { departing.animation(forKey: Self.leavingKey) }
    /// Exposed for the test that one Project does not cycle.
    var isCycling: Bool { timer != nil }
    var drawnName: String? { currentName }

    static let arrivingKey = "notch.projectName.arriving"
    static let leavingKey = "notch.projectName.leaving"
}

/// The collapsed surface's counts: sessions over subagents, stacked inside the
/// height of one matrix.
///
/// **It asks for no room the mark did not already have.** The two numerals are
/// anchored to the matrix's own edges rather than set on a line of their own —
/// the sessions cap-top on its top edge, the subagents baseline on its bottom —
/// so the whole column is exactly ``PanelMetrics/statusMatrixSize`` tall and
/// draws identically under a `46` pt menu bar and a `22` pt one. That is the
/// test the session-dot column was built to pass and the reason a numeral set
/// *beside* the matrix failed it (`compact-view-v2.md` §3.1).
///
/// **Nothing here is per product.** One numeral counts every row on the
/// monitored list and the other every subagent in flight across both, which is
/// what lets this replace a dot column and a badge per product at a fixed
/// width. Hierarchy is size and brightness and never hue, because there is no
/// product left for a colour to name (§3.2).
struct CountsColumn: View {
    /// Rows this column counts, which is the whole monitored list: the bar's
    /// totals and the band's are one figure, drawn once.
    let sessionCount: Int
    /// Subagents in flight, or `nil` for no lower row at all — the column is
    /// one numeral, centred on the mark.
    ///
    /// **Zero is never a value here.** It used to draw a dash, for an agent
    /// with sessions and no subagents standing beside an agent that had some;
    /// with the decomposition gone (`colour-v2.md` §3) there is one column and
    /// nothing to fill in beside, so a total of none is a row that is not
    /// drawn.
    let subagentCount: Int?
    let matrixSize: CGFloat
    /// Whether this form holds the column open at two digits rather than
    /// hugging the digits it draws.
    ///
    /// The pill alone (`compact-view-v2.md` §6.1): it is centred and fixed in
    /// width, so a tenth session must widen nothing and move nothing. The
    /// notched bar hugs and gives the width back, because it is pinned to the
    /// cut-out and its leading edge is free to travel.
    var reservesTwoDigits = false

    var body: some View {
        CountsNumerals(
            sessionCount: sessionCount,
            subagentCount: subagentCount,
            matrixSize: matrixSize
        )
        .frame(width: digitsWidth, height: matrixSize, alignment: .leading)
        // Drawn at its resting distance from the mark whatever the slot is
        // doing: `offset` moves the drawing and not the layout, so the room
        // below can open and close under numerals that never move. The same
        // arrangement, for the same reason, as ``SessionCountDots``.
        .offset(x: PanelMetrics.aggregateCountsGap)
        .frame(width: slotWidth, alignment: .leading)
        .animation(PanelMotion.slot(isOpening: sessionCount > 0), value: slotWidth)
        .accessibilityHidden(true)
    }

    /// The room the column takes out of the wing, gap included. Zero is never
    /// drawn, so no rows is no column at all (§3.2 rule 03) — except on the
    /// pill, which holds the room open whatever it draws.
    private var slotWidth: CGFloat {
        PanelMetrics.countsSlotWidth(
            sessionCount: sessionCount,
            reserved: reservesTwoDigits
        )
    }

    /// What the numerals themselves are given, which on the pill is two digits
    /// whether or not it is drawing two.
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
/// **Layer-backed for placement, not for cost.** A numeral has to land on the
/// matrix's own edges to a fraction of a point, and the one thing this surface
/// can measure exactly is a glyph raster drawn at a baseline it chose
/// (``NotchTextRaster/glyphImage(text:font:color:size:scale:)`` draws the line
/// box bottom at the origin, so the baseline is one descender above it). It
/// also gives the two movements somewhere to happen independently: a subagent
/// count arriving fades its own layer while the sessions layer rises under a
/// separate animation, and neither re-renders the overlay.
///
/// Both movements have a beginning and an end, which is what `AGENTS.md` §7
/// allows here — nothing on this view ticks.
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
        // The subagent numeral's baseline is the column's own bottom edge, so
        // its descenders — and the ceil the raster takes — fall outside these
        // bounds by design.
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
        // The lower row's *presence* is what moves the numeral above it; what
        // that row says once it is drawn does not.
        let rises = (self.subagentCount != nil) != (subagentCount != nil)
        self.sessionCount = sessionCount
        self.subagentCount = subagentCount
        self.matrixSize = matrixSize
        // The first application places the column rather than animating into
        // it: a panel opening on a turn already running has nothing to move
        // from.
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
            // A number, or no row at all -- and never a second numeral with no
            // sessions above it to belong to.
            text: sessionCount > 0 ? subagentCount.map(String.init) : nil,
            font: PanelMetrics.countsSubagentFont,
            colour: NotchPalette.labelDrawingColor,
            baseline: PanelMetrics.countsSubagentBaseline,
            scale: scale,
            animatingPosition: false,
            animatingFade: animatingFade
        )
    }

    /// One numeral, at the baseline the column gives it.
    ///
    /// The layer's own frame carries the glyphs' box; `baseline` is where the
    /// figures stand, measured up from the column's bottom edge, and the
    /// descender is what converts one into the other.
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

/// The mark that says a turn has finished: `4` points of `#C7C7CC`, in front of
/// the reading, on the notch and on a row alike.
///
/// **It began as the trailing wing's stand-in for a finished turn nobody had
/// read.** The mark draws the most urgent status anywhere and the reading
/// belongs to whatever is being timed, so a turn that finished while another
/// was still running had no representative at all
/// (`compact-view-v2.md` §4.3). That is still one of the two things this dot
/// says, and it is now the only one it says on both surfaces:
///
/// **A finished reading is a dot in front of the digits, not a ground behind
/// them.** ~~The turn ends, the figure freezes at the length it reached, and
/// the ground it was already standing on fills.~~ A filled ground was a
/// silhouette — a shape one row could answer with, where "no timer" and "a
/// dimmer timer" are both comparisons with a neighbour — and it worked, at the
/// price of two marks for one meaning: the notch drew a dot for a finished turn
/// it could not otherwise speak for, and a grey tile for a finished turn it
/// could. One meaning gets one mark. The digits simply stop, which is what they
/// do, and the dot in front of them is what says they have.
///
/// **It breathes on the notch and is still on a row**, and that difference is
/// the surfaces' own: a collapsed bar is glanced at and has one line to say
/// everything on, so movement is how it gets attention across a screen; an open
/// panel is being read, and a dot that pulsed once per row would be the list
/// moving while somebody scanned it (`AGENTS.md` §7).
///
/// **Its crest is the sessions numeral and never past it.** The breath swings
/// within ``NotchPalette/finishedDotDrawingColor``, whose full value is the
/// count beside the mark — see ``SessionDotBreath/restingOpacity``. Its slot is
/// a fixed `4`, so nothing on the wing changes width while it moves.
struct FinishedTurnDot: View {
    /// The notch's dot breathes; a row's holds still.
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
        // Spoken instead by the row's own status and by
        // `MonitorStore.spokenBuriedCompletionText`, which says how many —
        // something the movement never does.
        .accessibilityHidden(true)
    }
}

private struct BreathingDot: NSViewRepresentable {
    func makeNSView(context: Context) -> BreathingDotView { BreathingDotView() }
    func updateNSView(_ nsView: BreathingDotView, context: Context) {}
}

/// The dot, on a layer, so the loop is evaluated by the render server and the
/// overlay is not re-rendered for it (`AGENTS.md` §7).
final class BreathingDotView: NSView {
    private let ink = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        ink.backgroundColor = NotchPalette.finishedDotDrawingColor.cgColor
        ink.opacity = Float(SessionDotBreath.restingOpacity)
        layer?.addSublayer(ink)
        // Installed once, for the life of the view: this dot exists only while
        // it has something to say, so its presence is the condition and it has
        // no second state to settle back to.
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

    /// Exposed for the test that the breath reaches the layer at all.
    var breathAnimation: CAAnimation? { ink.animation(forKey: Self.breathKey) }

    static let breathKey = "notch.buriedFinish.breath"
}

/// The mark's own grid, in the units its design files are drawn in.
///
/// `27`-unit cells on a `32`-unit pitch with a `2`-unit corner radius — the
/// same three proportions the 3×3 and 4×4 matrices used, five to a side, so
/// the viewBox goes from `123` to `155`.
///
/// **The mark does not grow, so the cell pays for the row.**
/// ``PanelMetrics/statusMatrixSize`` is still `16.6`, and stretching the box
/// by a fifth without giving it more room takes the cell from `3.64` to
/// `2.89` and the gap from `0.68` to `0.54` — which on a Retina display is a
/// gap of about one device pixel. Holding today's cell size instead would mean
/// a `20.9` mark and a compact bar `4.3` wider, and the bar's width is a
/// number other things are measured against. The cell was the cheaper of the
/// two, and the patterns were chosen to survive it: they move whole rows,
/// whole columns or the whole grid, and none asks the eye to resolve a single
/// cell.
///
/// **The one pattern that argued for an exception did not survive it.** The
/// quincunx drew Completed as five isolated single cells for a day, on the
/// grounds that a die-five reads as one figure; at `2.89` it read as scattered
/// specks. The bloom that replaced it was a whole row crossing a whole column,
/// and the terrace drawing it now is a fifteen-cell connected mass. Neither
/// asks the eye to resolve a cell on its own. Take the rule as having no
/// exceptions.
enum MatrixGrid {
    static let side = 5
    static let cellCount = side * side
    static let cell: CGFloat = 27
    static let pitch: CGFloat = 32
    static let cornerRadius: CGFloat = 2
    /// `5` cells and the `4` gaps between them.
    static let viewBox = CGFloat(side) * pitch - (pitch - cell)
}

/// What the 5×5 indicator is doing, independent of which status drove it.
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
    /// the loom and the knock share `1.2`, so a bar showing one of each is
    /// showing two things on one grid rather than two clocks. Input and
    /// Completed each keep their own.
    ///
    /// **Two of the three moved when the wedge and the bars were replaced.**
    /// Input went `0.8` → `1`, which is `8` whole frames to a column rather
    /// than a front timed to cross in `0.8`; Completed went `2` → `2.4`. The
    /// treatments have changed again since — Input to the glide, and Completed
    /// to the bloom and then to the terrace — and both periods survived every
    /// one of those, which is some evidence they are the right two. Both are still ordered
    /// the way they have to be — the state that asks for nothing is much the
    /// slowest thing on the bar, and the state asking for the keyboard is
    /// faster than the two that share `1.2`. Completed's ceiling is the session
    /// column's `2.8` breath, which has to stay slower than every one of these;
    /// `theBreathIsSlowerThanAnythingTheMatrixRuns` is what holds that.
    var period: TimeInterval? {
        switch self {
        case .running, .approvalNeeded: 1.2
        case .inputNeeded: 1.0
        case .completed: 2.4
        case .inactive: nil
        }
    }
}

/// Per-cell opacity tracks, one per state.
///
/// Every one of the four draws **one** waveform and gives each cell that same
/// waveform at its own offset, so that is how they are held here: the curve
/// sampled once per state, plus the rule that says how far a given cell lags
/// it. Writing out twenty-five tracks per state would be the same numbers
/// twenty-five times over, and the rule — two rings turning against each other,
/// a column striking and the next taking it up, two diagonals trading about a
/// centre — is the half that has to survive being read.
///
/// The terrace is the one that needs more than a single curve: a cell's level
/// depends on which column it stands in, so it holds five, one per step of the
/// logo's ladder. It is still a curve and a rule for choosing it.
///
/// **The offsets are whole frames**, and a pattern is sampled at whatever rate
/// makes that true: the loom runs 48 frames at 40fps rather than 36 at 30
/// because `1.2s` over sixteen outer cells is otherwise `2.25` frames a step.
/// ~~One phase still does not land: the bars want their tiers `10.8` frames
/// apart.~~ Void with the bars — every offset in the file is now exact. The
/// glide takes `8` frames to a column, and the terrace needs no offsets at all
/// — its steps move together, so every cell in a given column draws the same
/// curve unshifted.
///
/// **Three of the four share one scale, and the knock does not.** Each pattern
/// was drawn against a floor and a ceiling that suited it alone; shipping four
/// of them means the same cell value has to mean the same thing whichever
/// state the mark is in, so loom, glide and terrace are each stretched linearly
/// until their dimmest cell sits at ``floor`` and their brightest at `1`. The
/// stretch is linear, so no pattern's *shape* moves — only the two ends it is
/// measured between.
///
/// **That is also why a pattern cannot be quietened at the ceiling**, which is
/// the first thing to say when one is called too loud: lowering a peak is
/// undone by the next stretch. What a treatment actually spends is lit area,
/// time held at white, and how fast it moves — the three readings quoted on
/// ``glide`` and ``terrace``, both of which were chosen against them.
///
/// The knock keeps its own `0.05`. Approval is the one state whose silence has
/// to stay darker than a resting mark: a mark asking for a person is twice as
/// dark as a bar with nothing connected, and that darkness is half of how it
/// asks (`dual-agent-design.md` §2). Lifting it to ``floor`` would have made
/// the two indistinguishable for the `900ms` after the second knock. It was
/// three times over until ``floor`` was lowered to `0.100`, and that narrowing
/// is why the floor did not go lower still.
///
/// **Nothing rests where a disconnected mark rests.** Three patterns now floor
/// at exactly ``inactiveLevel``, so the old argument — that the resting grey
/// threaded between the levels the patterns fell to — no longer holds and is
/// not what keeps them apart. What keeps them apart is that none of the three
/// is ever at its floor *everywhere at once*: the loom always has two ring
/// heads and a lit pivot, the glide always has a rule crossing, and the
/// terrace's tall step never falls below `0.465`. A live mark always
/// has a lit cell and a still one never does, which was the load-bearing half
/// of that argument all along.
private enum MatrixTrack {
    /// The level the three normalised patterns rest at, and the level a mark
    /// with nothing behind it holds.
    ///
    /// **Lowered from `0.150` to `0.100` on 2026-09-07**, which darkens every
    /// normalised pattern's resting level and the still with it. The stretch is
    /// linear and the ceiling did not move, so no pattern's *shape* changed —
    /// only the bottom of the range each is drawn against, and the marks sit
    /// quieter on the bar for it.
    ///
    /// **It could not go much further.** ``doubleKnock`` keeps its own `0.05`
    /// so that a mark waiting on a decision is darker in its silence than a
    /// mark with nothing behind it, and that ordering is half of how Approval
    /// asks. At `0.100` the still is twice the knock's silence; it was three
    /// times, and taking the floor to `0.05` would collapse the two entirely.
    static let floor = 0.100

    /// Stretch tracks so the dimmest sample across all of them sits at
    /// `floor` and the brightest at `1`.
    ///
    /// Taken over the whole set at once rather than track by track, because
    /// the rain's five rows are one pattern and scaling them separately would
    /// flatten the difference between a drop at the top of the grid and one at
    /// the bottom.
    private static func stretched(_ tracks: [[Double]], floor: Double) -> [[Double]] {
        let samples = tracks.flatMap { $0 }
        guard let low = samples.min(), let high = samples.max(), high - low > 1e-9
        else { return tracks }
        let scale = (1 - floor) / (high - low)
        return tracks.map { $0.map { floor + ($0 - low) * scale } }
    }

    // MARK: Running — loom

    /// **Loom**, 48 frames over `1.2s`.
    ///
    /// The outer sixteen cells turn clockwise and the inner eight anticlockwise,
    /// one lap each per loop, about a centre cell that holds still. Two gears
    /// meshing: plainly driven, plainly going nowhere, which is the pair of
    /// things Running has to say at once. The centre is 5×5's own affordance —
    /// an even grid has no cell for the two rings to turn about.
    ///
    /// **48 frames rather than 36.** A `1.2s` loop at 30fps is `2.25` frames to
    /// an outer step, and this file's offsets are whole frames. 40fps is the
    /// same `1.2s` and divides both rings exactly: `3` frames a step outside,
    /// `6` inside.
    ///
    /// A ring's cell is brightest as the head passes and falls away either side
    /// of it, so the lit arc is symmetric rather than a comet — a tooth on a
    /// gear rather than something thrown.
    static let loom: (outer: [Double], inner: [Double], centre: Double) = {
        let frames = 48
        func ring(_ n: Int) -> [Double] {
            let step = Double(frames) / Double(n)
            return (0 ..< frames).map { frame in
                let moved = Double(frame) / step            // steps the head has taken
                let gap = min(moved, Double(n) - moved)     // the nearer way round
                return 0.12 + 0.88 * exp(-gap / 1.5)
            }
        }
        // The pivot is stretched with the rings rather than after them, so it
        // keeps its place between the arc's floor and its crest.
        let all = stretched([ring(16), ring(8), [0.42]], floor: floor)
        return (all[0], all[1], all[2][0])
    }()

    /// The 16 perimeter cells, clockwise from the top-left corner.
    static let outerRing = [0, 1, 2, 3, 4, 9, 14, 19, 24, 23, 22, 21, 20, 15, 10, 5]
    /// The 8 cells around the centre, clockwise from the top-left of them.
    static let innerRing = [6, 7, 8, 13, 18, 17, 16, 11]

    /// One cell's loom track: which ring it is on, and how far behind that
    /// ring's head it sits. The inner offset is negative because that ring
    /// turns the other way.
    static func loomTrack(forCell index: Int) -> [Double] {
        if let i = outerRing.firstIndex(of: index) { return loom.outer.delayed(by: i * 3) }
        if let i = innerRing.firstIndex(of: index) { return loom.inner.delayed(by: -i * 6) }
        return [loom.centre]
    }

    // MARK: Input needed — glide

    /// **Glide**, 40 frames over `1s`.
    ///
    /// One upright rule crossing the grid, brightest where its centre is and
    /// falling away evenly to either side. The distance is taken **around** the
    /// grid rather than across it, so a column the rule has just left re-enters
    /// on the other side and nothing resets at the right-hand edge: the figure
    /// is always mid-crossing.
    ///
    /// **The profile is symmetric, and that is the whole of the change from the
    /// step it replaced.** The step's fault was never how bright it got — it
    /// held only `2.5%` of the grid at white, less than anything else on the
    /// surface. It was how fast it got there: each column arrived at full in a
    /// single frame, `34` units of opacity a second, five times a loop, and
    /// that instant arrival read as five hard strikes rather than as one thing
    /// moving. A rule that falls away on *both* sides has no leading edge to
    /// jump, so a column brightens as the rule approaches instead of switching
    /// on when it arrives. Same full `1`, reached at `8.9` instead of `34`.
    ///
    /// **What it costs is Input's distance from Running.** The step sat at `34`
    /// against the loom's `7.2` and could not be taken for it; the glide sits
    /// at `8.9`, and on mean level and lit area the two are now within a few
    /// points of each other. They read apart by shape — one crosses, one turns
    /// — rather than by urgency, which is a weaker separation than the one it
    /// had, and Input outranks Running. The lever if it ever needs one is the
    /// period: the same figure narrower and crossing in `0.8s` measures `12.5`,
    /// and costs nothing else.
    ///
    /// This is the curve for column `0`. Every other column is it, later.
    static let glide: [Double] = {
        let frames = 40, span = Double(MatrixGrid.side)
        let track = (0 ..< frames).map { frame -> Double in
            let behind = (Double(frame) / Double(frames) * span)
                .truncatingRemainder(dividingBy: span)
            let gap = min(behind, span - behind)       // the nearer way round
            return exp(-gap / 0.44)
        }
        return stretched([track], floor: floor)[0]
    }()

    /// The frame the rule's centre reaches this cell's column: `8` frames a
    /// column, a fifth of the loop each.
    ///
    /// Every offset is whole, so the glide needs no rounding — and it takes no
    /// row term at all, because a column brightens all the way down at once.
    /// That is what keeps it legible when the cell is `2.89`.
    static func glideOffset(column: Int) -> Int { column * 8 }

    // MARK: Approval needed — double knock

    /// **Double knock**, 36 frames over `1.2s`, every cell together.
    ///
    /// The whole grid to full twice, `300ms` apart, each knock falling away
    /// with a 3-frame time constant; then `900ms` at `0.05`, which is the
    /// darkest this surface ever goes. The pattern is the one thing on the
    /// bar that has no spatial reading at all — there is nothing to follow
    /// and nowhere to look, only two beats and a silence — and that is why
    /// it is the state that outranks the rest.
    ///
    /// Carried across from the 4×4 mark unchanged. It already ran the full
    /// `0.05` to `1`, so it is the one chosen track the stretch would not have
    /// moved even if it had been applied.
    static let doubleKnock: [Double] = [
        1.000, 1.000, 0.731, 0.538, 0.399, 0.300, 0.229, 0.179,
        0.142, 1.000, 1.000, 0.731, 0.538, 0.399, 0.300, 0.229,
        0.179, 0.142, 0.116, 0.097, 0.084, 0.074, 0.067, 0.062,
        0.059, 0.056, 0.055, 0.053, 0.052, 0.052, 0.051, 0.051,
        0.051, 0.050, 0.050, 0.050
    ]

    // MARK: Completed — terrace

    /// **Terrace**, 72 frames over `2.4s`. The app's own mark, breathing.
    ///
    /// **The logo is already drawn on this grid**, so there is nothing to
    /// translate. It is one connected mass hanging from the top edge with
    /// column heights `5 4 3 2 1` — exactly the cells where
    /// `row + column <= 4` — and a level stepping down
    /// `1.00 / .80 / .60 / .40 / .20` as the mass steps down. The crest frame
    /// *is* that mark, at `1.00 / .82 / .64 / .46 / .28` once the shared scale
    /// has lifted the ten cells off the mark up to ``floor``.
    ///
    /// One soft crest a loop with a long tail, the ladder holding its ratio the
    /// whole way, so the silhouette and the step gradient are the logo in every
    /// frame. Nothing travels and nothing turns — which is what Completed has
    /// to say, and the one thing it keeps from the bloom it replaced.
    ///
    /// **The tall step is a pilot light.** It falls back only to `0.40` of its
    /// own level between crests where the other four fall to `0.06`, so the
    /// dimmest frame still holds a cell at `0.465` and the whole mark reads
    /// `0.188` against the still's `0.10`. Same device as the bloom's centre at
    /// `0.595`, and the same job: stop a dim frame reading as a mark with
    /// nothing behind it.
    ///
    /// **The curve is the loom's, not a bump on a flat rest.** A crest built as
    /// a power of a cosine flattens so hard through the trough that neighbouring
    /// frames come out identical and the mark reads as held; the periodic
    /// `exp(-(gap / tau)^p)` the rings already turn on never stops moving.
    ///
    /// **Fifteen lit cells against the bloom's nine, and that is the trade.**
    /// On each pattern's own brightest frame, above the floor, the cross
    /// carries `5.87` cell-units of light and this ladder carries `9.90`. The
    /// one-scale rule pins both peaks at `1`, so the extra area cannot be paid
    /// for at the ceiling — it comes out of duty and slew, which is why the
    /// crest is brief and the tail long. Mean `0.279` against the bloom's
    /// `0.244`, but *less* time at white — `3.8%` against `5.7%` — on an edge
    /// of `1.23`/s that is still seven times slower than the glide's.
    ///
    /// **It witnesses the seam direction, where the bloom did not.** The bloom
    /// was symmetric about both axes; this mass hangs from the top edge, so a
    /// wrong `isFlipped` stands it on its head. That takes `figma-design.md`
    /// §4.1's witnesses back from one to two.
    static let terrace: (columns: [[Double]], dark: Double) = {
        let frames = 72
        func column(_ index: Int) -> [Double] {
            // The logo's ladder across, and how far this column falls back
            // between crests — the tall step much less far than the rest.
            let level = 1 - 0.2 * Double(index), rest = index == 0 ? 0.40 : 0.06
            return (0 ..< frames).map { frame in
                let gap = Double(min(frame, frames - frame))   // the nearer way round
                // `12` frames to fall to `1/e` -- a fifth of the loop, which is
                // what makes the crest brief and the tail long -- and an
                // exponent a little above `1` so the crest is rounded off
                // rather than coming to a point.
                return level * (rest + (1 - rest) * exp(-pow(gap / 12, 1.4)))
            }
        }
        // The ten cells off the mark are stretched *with* the figure rather
        // than set afterwards, which is what puts them at exactly `floor`
        // while leaving even the shortest step above them.
        let all = stretched((0 ..< MatrixGrid.side).map(column) + [[0]], floor: floor)
        return (Array(all[0 ..< MatrixGrid.side]), all[MatrixGrid.side][0])
    }()

    /// One cell's terrace track: the column it stands in, or the dark level if
    /// it is off the mark.
    ///
    /// A cell's level depends only on its column, so a whole column draws one
    /// curve unshifted and the pattern needs no offsets — as the bloom's arms
    /// needed none.
    static func terraceTrack(forCell index: Int) -> [Double] {
        let row = index / MatrixGrid.side, column = index % MatrixGrid.side
        guard row + column <= MatrixGrid.side - 1 else { return [terrace.dark] }
        return terrace.columns[column]
    }

    // MARK: Nothing running

    /// Connected and disconnected hold still.
    ///
    /// The same level the three live patterns floor at. That is no longer a
    /// distinction they are asked to carry — see the note above on why a live
    /// mark is still never mistakable for a still one — and holding it here
    /// keeps the resting mark from being brighter than any pattern's floor,
    /// which is the direction that would actually mislead.
    ///
    /// It stays above the knock's `0.05`, so a mark waiting on a decision is
    /// still twice as dark in its silence as a mark with nothing behind it.
    /// It was three times over, before ``floor`` was lowered to `0.100`.
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

/// The 5×5 status matrix that replaced the notch status dot.
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
    /// The pair this mark is drawn in.
    ///
    /// **Always passed, and never chosen from a product.** There is one mark on
    /// the surface, standing for every product at once, so there is no
    /// `AgentKind` that could pick an ink for it — and since `colour-v2.md` §1
    /// no product has one to pick.
    var ink: NotchPalette.MatrixInk = NotchPalette.restingInk
    /// Play the pattern from its first frame, rather than joining the phase
    /// the rest of the bar's marks share.
    ///
    /// **For a mark that is played rather than reported.** A mark on the bar
    /// starts when a turn starts, and it is anchored to a per-period grid so
    /// that two marks saying the same thing say it in step
    /// (``MatrixIndicatorView/phaseAnchor(for:now:)``). The Settings specimen
    /// has nothing beside it to be in step with, and it runs for exactly as
    /// long as it is asked to — so the grid would only drop the viewer into
    /// the middle of a loop, and the two turns of the sweep they were shown
    /// would begin and end mid-stride.
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
        startsAtItsFirstFrame: Bool = false
    ) {
        guard state != appliedState
            || size != appliedSize
            || isAnimated != appliedIsAnimated
            || ink != appliedInk
            || startsAtItsFirstFrame != appliedStartsAtItsFirstFrame else {
            return
        }
        // A dissolve crosses one pattern over another on the same mark. If the
        // mark itself is a different drawing — resized, or in a different ink
        // because the user changed the theme — there is nothing to cross: the
        // two are not two readings of one thing, and fading between them would
        // say they were.
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
        // radius, five to a side.
        let size = appliedSize
        let cell = size * MatrixGrid.cell / MatrixGrid.viewBox
        let radius = cell * MatrixGrid.cornerRadius / MatrixGrid.cell
        let pitch = size * MatrixGrid.pitch / MatrixGrid.viewBox
        // Three sigma is where a Gaussian is spent, so this is how far the
        // widest pass reaches. Each pass gets bounds that large or the filter
        // would clip its own halo.
        let bleed = cell * 10.5 / 27 * 3
        let scale = window?.backingScaleFactor ?? 2
        // One reading for every cell of this mark, so the twenty-five are on one
        // clock however long the layers take to build.
        let now = CACurrentMediaTime()
        // A specimen starts where the clock is; every other mark joins the
        // grid the rest of the bar's are already on.
        let anchorsPhase = !appliedStartsAtItsFirstFrame

        /// One cell of the mark.
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
    /// suddenly turning, or a finished turn the user has just read is
    /// suddenly gone.
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
    /// **The Settings specimen leans on both halves of this rule rather than
    /// opting out of it.** Its sweep arrives on a *hue change*, which is a
    /// different drawing and therefore a cut — the answer to a press should
    /// land on the press — and it leaves on a state change with the same ink,
    /// which dissolves, so two turns of the sweep sink back into the dark
    /// instead of snapping to the still.
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
    /// `1` and completed's `2.4` keep their own grids. Within one mark every
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
    /// step. It matters most to the knock, whose track ends far from where it
    /// begins.
    ///
    /// **`anchorsPhase` is what a specimen gives up.** There is nothing beside
    /// it to be in step with, and it runs for a counted number of loops, so the
    /// grid would only start it wherever the clock happened to be and end it
    /// the same distance short. It begins at `now` instead, which is the first
    /// frame of the pattern.
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
/// The AppKit window and opacity transitions use the same curve. SwiftUI
/// does not animate the window's geometry again; a reading finishes fading as
/// the width animating underneath it settles. `0.20` and `(0.22, 1, 0.36, 1)`
/// used to be written out separately in each of those three places, which is
/// how they were free to drift apart; this is the single declaration they read
/// from, in the forms the surface needs: SwiftUI transitions, AppKit's window
/// resize and the Core Animation labels.
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
    /// since neither collapsed form reserves a reading, the panel's own edges:
    /// the notched bar's trailing one, and both of the pill's, which is centred
    /// and takes half of every change on each.
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
    /// same instant — a collapsed surface is now exactly as wide as its
    /// contents, so its edge and the content inside it are two halves of one
    /// movement
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
    ///
    /// Shared with the retired row, which draws the same fade by a different
    /// means — see ``PanelMetrics/rowTrailingFadeWidth``.
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
