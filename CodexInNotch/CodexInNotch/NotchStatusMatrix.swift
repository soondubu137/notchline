import SwiftUI

/// Colours the notch surface owns, mirroring the Figma variables of the same name.
enum NotchPalette {
    /// `text/notch-label` — the dim base every notch label sits at.
    static let label = Color(red: 0.486, green: 0.486, blue: 0.502)
    /// `text/notch-spotlight` — the searchlight highlight.
    static let spotlight = Color.white
    /// Unlit matrix cell.
    static let matrixOff = Color(red: 0.063, green: 0.106, blue: 0.149)
    /// Lit matrix cell.
    static let matrixOn = Color(red: 0.424, green: 0.706, blue: 1)
    /// Session title — the one element that stays bright.
    static let sessionTitle = Color.white.opacity(0.98)
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

    /// SMIL spreads N values across N-1 intervals; mirror that so the loop
    /// lands on the same frames the SVG does.
    static func sample(_ track: [Double], phase: Double) -> Double {
        guard track.count > 1 else { return track.first ?? 0 }
        let scaled = min(max(phase, 0), 1) * Double(track.count - 1)
        let index = Int(scaled)
        let fraction = scaled - Double(index)
        let lower = track[min(index, track.count - 1)]
        let upper = track[min(index + 1, track.count - 1)]
        return lower + (upper - lower) * fraction
    }
}

private extension NotchMatrixState {
    func opacity(forCell index: Int, phase: Double) -> Double {
        switch self {
        case .running:
            let isEven = ((index / 3) + (index % 3)).isMultiple(of: 2)
            return MatrixTrack.sample(
                isEven ? MatrixTrack.runningEven : MatrixTrack.runningOdd,
                phase: phase
            )
        case .needsAttention:
            return MatrixTrack.sample(
                index == 4 ? MatrixTrack.attentionCentre : MatrixTrack.attentionRing,
                phase: phase
            )
        case .completed:
            return MatrixTrack.sample(MatrixTrack.completed, phase: phase)
        case .inactive:
            return MatrixTrack.inactiveLevel
        }
    }
}

/// The 3×3 status matrix that replaced the notch status dot.
///
/// Sized by the caller to the fixed ``PanelMetrics/statusMatrixSize``.
struct NotchStatusMatrix: View {
    let state: NotchMatrixState
    let size: CGFloat
    var isAnimated = true

    // Proportions come straight from the SVG's 91-unit viewBox: 27-unit cells
    // on a 32-unit pitch, 2-unit corner radius.
    private var cell: CGFloat { size * 27 / 91 }
    private var gap: CGFloat { size * 5 / 91 }
    private var radius: CGFloat { cell * 2 / 27 }

    var body: some View {
        Group {
            if let period = state.period, isAnimated {
                TimelineView(.animation) { context in
                    grid(phase: phase(at: context.date, period: period))
                }
            } else {
                // The still the design file shows: every track's t=0 frame.
                grid(phase: 0)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func phase(at date: Date, period: TimeInterval) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period)
        return elapsed / period
    }

    private func grid(phase: Double) -> some View {
        let opacities = (0..<9).map { state.opacity(forCell: $0, phase: phase) }
        // One blurred copy per glow layer reproduces the SVG's three
        // feGaussianBlur + feMerge passes without stacking 27 shadows.
        return ZStack {
            cells(opacities: nil)
            cells(opacities: opacities)
                .blur(radius: cell * 10.5 / 27)
                .opacity(0.21)
            cells(opacities: opacities)
                .blur(radius: cell * 5.6 / 27)
                .opacity(0.35)
            cells(opacities: opacities)
                .blur(radius: cell * 2.1 / 27)
                .opacity(0.56)
            cells(opacities: opacities)
        }
    }

    /// `opacities == nil` draws the unlit bed; otherwise the lit cells.
    private func cells(opacities: [Double]?) -> some View {
        VStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { column in
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(opacities == nil ? NotchPalette.matrixOff : NotchPalette.matrixOn)
                            .frame(width: cell, height: cell)
                            .opacity(opacities?[row * 3 + column] ?? 1)
                    }
                }
            }
        }
    }
}

/// A highlight band travelling across the glyphs, over a dim base.
///
/// Mirrors the reference implementation: a 400%-wide gradient that is
/// transparent except for a peak at its centre, clipped to the text and slid
/// from one side to the other on a 2s linear loop.
struct SearchlightBand: View {
    var period: TimeInterval = 2

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
