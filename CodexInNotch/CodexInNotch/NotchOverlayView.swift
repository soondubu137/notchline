import SwiftUI

struct NotchOverlayView: View {
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                PanelSurface(
                    geometry: store.geometry,
                    isExpanded: store.isExpanded
                )

                VStack(spacing: 0) {
                    OverlayHeader()
                        .frame(height: store.compactHeight)

                    if store.isExpanded {
                        ExpandedPanelContent()
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: -6)),
                                    removal: .opacity
                                )
                            )
                    }
                }
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .top
                )
                .animation(contentAnimation, value: store.isExpanded)
            }
        }
        .contentShape(Rectangle())
        .clipped()
        .onHover { isInside in
            if isInside {
                store.pointerEnteredPanel()
            } else {
                store.pointerExitedPanel()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(panelAccessibilityLabel)
    }

    private var contentAnimation: Animation {
        store.reduceMotion
            ? .easeOut(duration: 0.08)
            : .timingCurve(0.22, 1, 0.36, 1, duration: 0.28)
    }

    private var panelAccessibilityLabel: String {
        let activity = store.longestRunningDurationText.map { "最长运行时间 \($0)" }
            ?? "剩余用量 \(store.tokenRemainingPercent)%"
        return "Codex，\(store.sessions.count) 个相关会话，状态 \(store.status.displayName)，\(activity)"
    }
}

private struct PanelSurface: View {
    let geometry: DisplayGeometry
    let isExpanded: Bool

    var body: some View {
        Image(assetName)
            .resizable(
                capInsets: EdgeInsets(
                    top: 12,
                    leading: 24,
                    bottom: 12,
                    trailing: 24
                ),
                resizingMode: .stretch
            )
            .interpolation(.high)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var assetName: String {
        if isExpanded {
            return "PanelNotchCompact"
        }

        switch geometry {
        case .notched:
            return "PanelNotchCompact"
        case .noNotch:
            return "PanelFallbackCompact"
        }
    }
}

private struct OverlayHeader: View {
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        HStack(spacing: 0) {
            StatusReadout(
                status: store.status,
                text: statusText,
                showsText: showsStatusText,
                spacing: store.isExpanded
                    ? PanelMetrics.expandedReadoutSpacing
                    : 8
            )

            Spacer(minLength: store.isExpanded ? 24 : compactGroupSpacing)

            UsageReadout(
                remainingPercent: store.tokenRemainingPercent,
                text: store.expandedUsageReadoutText,
                showsText: store.isExpanded
            )
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .animation(headerAnimation, value: store.isExpanded)
    }

    private var statusText: String {
        store.isExpanded ? store.status.displayName : store.compactStatusReadoutText
    }

    private var showsStatusText: Bool {
        store.isExpanded || store.geometry == .noNotch
    }

    private var compactGroupSpacing: CGFloat {
        store.geometry == .notched ? 0 : 32
    }

    private var horizontalPadding: CGFloat {
        PanelMetrics.expandedHorizontalPadding
    }

    private var headerAnimation: Animation {
        store.reduceMotion
            ? .easeOut(duration: 0.08)
            : .timingCurve(0.22, 1, 0.36, 1, duration: 0.28)
    }
}

private struct StatusReadout: View {
    let status: DemoStatus
    let text: String
    let showsText: Bool
    let spacing: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            StatusDot(status: status)

            if showsText {
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct UsageReadout: View {
    let remainingPercent: Int
    let text: String
    let showsText: Bool

    var body: some View {
        HStack(spacing: PanelMetrics.expandedReadoutSpacing) {
            if showsText {
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.remaining)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            UsageRing(remainingPercent: remainingPercent)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("剩余用量 \(remainingPercent)%")
    }

    private var palette: UsagePalette {
        UsagePalette(level: UsageLevel(remainingPercent: remainingPercent))
    }
}

private struct UsageRing: View {
    let remainingPercent: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.track, lineWidth: 2)

            if progress >= 0.999 {
                Circle()
                    .stroke(palette.remaining, lineWidth: 2)
            } else if progress > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        palette.remaining,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(x: -1, y: 1)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }

    private var progress: CGFloat {
        CGFloat(min(max(remainingPercent, 0), 100)) / 100
    }

    private var palette: UsagePalette {
        UsagePalette(level: UsageLevel(remainingPercent: remainingPercent))
    }
}

private struct UsagePalette {
    let remaining: Color
    let track: Color

    init(level: UsageLevel) {
        switch level {
        case .healthy:
            remaining = .white
            track = Color(red: 0.23, green: 0.23, blue: 0.24)
        case .warning:
            remaining = Color(red: 1, green: 0.62, blue: 0.04)
            track = Color(red: 0.34, green: 0.21, blue: 0.02)
        case .critical:
            remaining = Color(red: 1, green: 0.27, blue: 0.23)
            track = Color(red: 0.35, green: 0.09, blue: 0.08)
        }
    }
}

private struct ExpandedPanelContent: View {
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal, PanelMetrics.expandedHorizontalPadding)

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(store.sessions) { session in
                        SessionRow(session: session)
                    }
                }
            }
            .frame(
                width: store.currentPanelSize.width
                    - PanelMetrics.expandedHorizontalPadding * 2,
                height: PanelMetrics.expandedSessionViewportHeight
            )
            .scrollIndicators(.hidden)

            Color.clear
                .frame(height: 15)
        }
        .foregroundStyle(.white)
    }
}

private struct SessionRow: View {
    @EnvironmentObject private var store: DemoStore
    let session: DemoSession

    @State private var isHovered = false

    var body: some View {
        Button {
            store.simulateOpening(session)
        } label: {
            SessionRowContent(
                session: session,
                isHovered: isHovered
            )
        }
        .buttonStyle(SessionRowButtonStyle())
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .onHover { isHovered = $0 }
        .accessibilityLabel(
            "\(session.projectName)，\(session.title)，\(session.status.controlTitle)，当前内容：\(session.preview)"
        )
    }
}

private struct SessionRowContent: View {
    @Environment(\.sessionRowIsPressed) private var isPressed

    let session: DemoSession
    let isHovered: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.projectName)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.68))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    UntruncatedSingleLineText(
                        text: session.title,
                        font: .system(size: 13, weight: .medium),
                        color: Color.white.opacity(0.98),
                        lineHeight: 17
                    )
                    .mask(TrailingAlphaFade())

                    UntruncatedSingleLineText(
                        text: session.preview,
                        font: .system(size: 13, weight: .regular),
                        color: Color.white.opacity(0.68),
                        lineHeight: 18
                    )
                    .mask(TrailingAlphaFade())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SessionStatusControl(
                    session: session,
                    revealsStatusName: revealsStatusName
                )
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 16)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 80)
    }

    private var revealsStatusName: Bool {
        session.status.isRunning || isHovered || isPressed
    }

    private var backgroundColor: Color {
        if isPressed {
            return Color(red: 0.23, green: 0.23, blue: 0.24)
        }
        if isHovered {
            return Color(red: 0.17, green: 0.17, blue: 0.18)
        }
        return .black
    }
}

private struct SessionStatusControl: View {
    let session: DemoSession
    let revealsStatusName: Bool

    var body: some View {
        if revealsStatusName {
            HStack(spacing: 8) {
                StatusDot(status: session.status)
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(statusColor.opacity(0.16), in: Capsule())
        } else {
            StatusDot(status: session.status)
        }
    }

    private var label: String {
        if session.status.isRunning, let runtimeText = session.runtimeText {
            return runtimeText
        }
        return session.status.displayName
    }

    private var statusColor: Color {
        StatusPalette.color(for: session.status)
    }
}

private struct StatusDot: View {
    let status: DemoStatus

    var body: some View {
        Circle()
            .fill(StatusPalette.color(for: status))
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

private enum StatusPalette {
    static func color(for status: DemoStatus) -> Color {
        switch status {
        case .idle:
            Color(red: 0.39, green: 0.39, blue: 0.40)
        case .running:
            Color(red: 0.04, green: 0.52, blue: 1)
        case .inputNeeded, .approvalNeeded:
            Color(red: 1, green: 0.62, blue: 0.04)
        case .completed:
            Color(red: 0.19, green: 0.82, blue: 0.35)
        case .error:
            Color(red: 1, green: 0.27, blue: 0.23)
        case .cancelled:
            Color(red: 0.56, green: 0.56, blue: 0.58)
        case .disconnected:
            Color(red: 0.75, green: 0.35, blue: 0.95)
        }
    }
}

private struct UntruncatedSingleLineText: View {
    let text: String
    let font: Font
    let color: Color
    let lineHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: proxy.size.width, alignment: .leading)
                .clipped()
        }
        .frame(height: lineHeight)
    }
}

private struct TrailingAlphaFade: View {
    var body: some View {
        HStack(spacing: 0) {
            Rectangle()

            LinearGradient(
                colors: [.black, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 48)
        }
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
        .environmentObject(DemoStore())
        .frame(
            width: PanelMetrics.expandedBaselineWidth,
            height: PanelMetrics.expandedHeight(
                compactHeight: PanelMetrics.referenceCompactHeight
            )
        )
        .background(Color.gray.opacity(0.2))
}
