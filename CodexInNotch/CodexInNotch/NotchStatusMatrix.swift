import AppKit
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

    /// `text/notch-label` — the dim base every notch label sits at.
    static let label = Color(
        red: labelRGB.red,
        green: labelRGB.green,
        blue: labelRGB.blue
    )
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
struct NotchTimerText: View {
    let text: String
    var tint: Color = NotchPalette.label
    var weight: Font.Weight = .light

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: weight))
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
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

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(NotchPalette.matrixOff)

                if let fill {
                    Capsule()
                        .fill(NotchPalette.matrixOn)
                        .frame(width: proxy.size.width * min(max(fill, 0), 1))
                        .shadow(color: NotchPalette.matrixOn.opacity(0.35), radius: 2)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// What the 3×3 indicator is doing, independent of which status drove it.
///
/// Several statuses collapse onto one appearance: input and approval both read
/// as "needs attention", and every non-session state (idle, connecting, the
/// setup and version states) reads as "inactive".
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
        case .idle, .connecting, .disconnected,
             .setupRequired, .updateCodex, .unsupportedVersion:
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

/// Per-cell opacity tracks, transcribed verbatim from the `<animate values="…">`
/// lists in `running.svg`, `need-approval.svg` and `completed.svg`.
///
/// They are sampled rather than approximated with a sine so the code and the
/// design file keep describing the same motion — `needsAttention` in particular
/// is a hold-then-flash that no simple curve reproduces.
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
    static let attentionRing: [Double] = [
        0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
        0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
        1.000, 0.981, 0.963, 0.944, 0.925, 0.906, 0.887, 0.869
    ]
    static let attentionCentre: [Double] = [
        1.000, 0.981, 0.963, 0.944, 0.925, 0.906, 0.887, 0.869,
        0.850, 0.831, 0.813, 0.794, 0.775, 0.756, 0.738, 0.719,
        0.700, 0.681, 0.663, 0.644, 0.625, 0.606, 0.588, 0.569
    ]
    static let completed: [Double] = [
        0.600, 0.704, 0.800, 0.883, 0.946, 0.986, 1.000, 0.986,
        0.946, 0.883, 0.800, 0.704, 0.600, 0.496, 0.400, 0.317,
        0.254, 0.214, 0.200, 0.214, 0.254, 0.317, 0.400, 0.496
    ]
    /// Idle and disconnected hold the resting floor of the completed breath.
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

    var body: some View {
        MatrixIndicator(state: state, size: size, isAnimated: isAnimated)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct MatrixIndicator: NSViewRepresentable {
    let state: NotchMatrixState
    let size: CGFloat
    let isAnimated: Bool

    func makeNSView(context: Context) -> MatrixIndicatorView {
        MatrixIndicatorView()
    }

    func updateNSView(_ view: MatrixIndicatorView, context: Context) {
        view.apply(state: state, size: size, isAnimated: isAnimated)
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

    func apply(state: NotchMatrixState, size: CGFloat, isAnimated: Bool) {
        guard state != appliedState
            || size != appliedSize
            || isAnimated != appliedIsAnimated else {
            return
        }
        appliedState = state
        appliedSize = size
        appliedIsAnimated = isAnimated
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

        func pass(_ pass: GlowPass, color: CGColor, animated: Bool) -> CALayer {
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
                let cellLayer = CALayer()
                cellLayer.frame = CGRect(
                    x: bleed + CGFloat(index % 3) * pitch,
                    y: bleed + CGFloat(index / 3) * pitch,
                    width: cell,
                    height: cell
                )
                cellLayer.cornerRadius = radius
                cellLayer.cornerCurve = .continuous
                cellLayer.backgroundColor = color
                cellLayer.contentsScale = scale

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

        // The unlit bed never animates; only the lit copies above it do.
        root.addSublayer(
            pass(
                GlowPass(blur: nil, opacity: 1),
                color: NotchPalette.matrixOffLayerColor,
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
                    color: NotchPalette.matrixOnLayerColor,
                    animated: appliedIsAnimated
                )
            )
        }
    }

    /// Every cell's animation is added in one pass, so they share a `beginTime`
    /// and stay in phase with each other for as long as they run.
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
        return animation
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
        SweepingLabel(text: text, font: font, isSweeping: isSweeping)
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

    private let baseLayer = CALayer()
    private let highlightLayer = CALayer()
    private let sweepMask = NotchTextRaster.makeSweepMask()
    private var appliedText = ""
    private var appliedFont = NSFont.systemFont(ofSize: 13, weight: .light)
    private var appliedIsSweeping = false
    private var renderedScale: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        highlightLayer.mask = sweepMask
        layer?.addSublayer(baseLayer)
        layer?.addSublayer(highlightLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NotchTextRaster.textSize(appliedText, font: appliedFont)
    }

    func apply(text: String, font: NSFont, isSweeping: Bool) {
        let textChanged = text != appliedText || font != appliedFont
        guard textChanged || isSweeping != appliedIsSweeping else { return }

        appliedText = text
        appliedFont = font
        appliedIsSweeping = isSweeping

        if textChanged {
            invalidateIntrinsicContentSize()
            renderedScale = 0
            redrawGlyphs()
        }
        highlightLayer.isHidden = !isSweeping
        installSweep()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        redrawGlyphs()
        installSweep()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        redrawGlyphs()
    }

    override func layout() {
        super.layout()
        baseLayer.frame = bounds
        highlightLayer.frame = bounds
        installSweep()
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
            return
        }
        guard scale != renderedScale else { return }
        renderedScale = scale

        let size = intrinsicContentSize
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

    private func installSweep() {
        guard appliedIsSweeping else {
            sweepMask.removeAnimation(forKey: NotchTextRaster.sweepAnimationKey)
            return
        }
        NotchTextRaster.installSweep(
            on: sweepMask,
            across: bounds.width,
            height: bounds.height,
            period: Self.sweepPeriod
        )
    }
}

/// A session row's title or preview: one line, never truncated with an ellipsis,
/// fading out where it runs past the row instead.
///
/// Layer-backed for the same reason the notch readout is — a sweeping row cost
/// ~7% of a core, and the expanded panel shows up to three of them at once — but
/// it also owns the trailing fade its caller used to apply. A SwiftUI `.mask`
/// over an AppKit view is not dependable, and the fade is the row's own
/// behaviour rather than the caller's, so both masks live on the layer now: the
/// fade on the container, the sweep on the bright copy.
struct SessionRowText: View {
    let text: String
    let font: NSFont
    let color: NSColor
    let lineHeight: CGFloat
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
        highlightLayer.contentsScale = scale
        baseLayer.contents = NotchTextRaster.glyphImage(
            text: appliedText,
            font: appliedFont,
            color: appliedColor,
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
}
