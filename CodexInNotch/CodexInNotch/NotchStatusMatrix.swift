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

    /// `text/notch-label` — the dim base every notch label sits at.
    static let label = Color(red: 0.486, green: 0.486, blue: 0.502)
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

/// A highlight band travelling across the glyphs, over a dim base.
///
/// Mirrors the reference implementation: a 400%-wide gradient that is
/// transparent except for a peak at its centre, clipped to the text and slid
/// from one side to the other on a 2s linear loop.
struct SearchlightBand: View {
    var period: TimeInterval = 2

    // NOTE: this sweep costs ~7% of a core for as long as it runs, and capping
    // the schedule does not help -- 30 Hz measured the same as the display's
    // 120. The redraw is not driven by this view's tick but by the panel being
    // marked for display every frame, so the whole overlay is re-rendered
    // either way. Only moving the motion to Core Animation removes it, the way
    // NotchStatusMatrix now does; that needs the mask to move into AppKit too.
    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { proxy in
                let elapsed = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period)
                let progress = elapsed / period
                let band = max(proxy.size.width * 4, 1)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.40),
                        .init(color: NotchPalette.spotlight, location: 0.50),
                        .init(color: .clear, location: 0.60),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: band)
                .offset(x: -band + progress * (band + proxy.size.width))
            }
        }
        .allowsHitTesting(false)
    }
}

/// A single-line notch label: thin and dim, sweeping while work is in flight.
struct SearchlightLabel: View {
    let text: String
    var font: Font = .system(size: 13, weight: .light)
    var isSweeping: Bool

    var body: some View {
        base
            .overlay {
                if isSweeping {
                    SearchlightBand().mask(base)
                }
            }
    }

    private var base: some View {
        Text(text)
            .font(font)
            .foregroundStyle(NotchPalette.label)
            .lineLimit(1)
    }
}
