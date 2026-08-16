import SwiftUI

struct NotchOverlayView: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                PanelSurface(
                    cornerRadius: PanelMetrics.surfaceCornerRadius(
                        geometry: store.geometry,
                        menuBarHeight: store.compactHeight
                    )
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
            : .timingCurve(0.22, 1, 0.36, 1, duration: 0.20)
    }

    private var panelAccessibilityLabel: String {
        let usage = store.tokenRemainingPercent.map { "剩余用量 \($0)%" }
            ?? "剩余用量不可用"
        // Spoken, not the "12:34" the notch draws: VoiceOver reads that as a
        // time of day. The label names it as the longest of the running turns,
        // because a bare duration beside a summary status is unattributable.
        let elapsed = store.spokenLongestElapsedText.map { "，最长已运行 \($0)" }
            ?? ""
        return "Codex，\(store.sessions.count) 个相关会话，状态 "
            + "\(store.status.displayName)\(elapsed)，\(usage)"
    }
}

private struct PanelSurface: View {
    let cornerRadius: CGFloat

    var body: some View {
        PanelContour(cornerRadius: cornerRadius)
            .fill(.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PanelContour: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(
            max(0, cornerRadius),
            min(rect.height / 2, rect.width / 4)
        )
        let controlOffset = radius * 0.552_284_749_8

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            control1: CGPoint(x: rect.maxX - controlOffset, y: rect.minY),
            control2: CGPoint(
                x: rect.maxX - radius,
                y: rect.minY + radius - controlOffset
            )
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius))
        path.addCurve(
            to: CGPoint(x: rect.maxX - 2 * radius, y: rect.maxY),
            control1: CGPoint(
                x: rect.maxX - radius,
                y: rect.maxY - radius + controlOffset
            ),
            control2: CGPoint(
                x: rect.maxX - 2 * radius + controlOffset,
                y: rect.maxY
            )
        )
        path.addLine(to: CGPoint(x: rect.minX + 2 * radius, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            control1: CGPoint(
                x: rect.minX + 2 * radius - controlOffset,
                y: rect.maxY
            ),
            control2: CGPoint(
                x: rect.minX + radius,
                y: rect.maxY - radius + controlOffset
            )
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY + radius))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(
                x: rect.minX + radius,
                y: rect.minY + radius - controlOffset
            ),
            control2: CGPoint(x: rect.minX + controlOffset, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct OverlayHeader: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        HStack(spacing: 0) {
            StatusReadout(
                status: store.status,
                text: statusText,
                showsText: showsStatusText,
                spacing: PanelMetrics.expandedReadoutSpacing,
                matrixSize: PanelMetrics.statusMatrixSize,
                reduceMotion: store.reduceMotion
            )

            Spacer(minLength: 0)

            // Trailing wing, compact only: present while a turn is timed, absent
            // otherwise so a notched display shows no empty second cut-out. The
            // expanded view times each row individually instead.
            if !store.isExpanded, let elapsed = store.compactTimerText {
                NotchTimerText(text: elapsed)
            }
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

    private var horizontalPadding: CGFloat {
        PanelMetrics.expandedHorizontalPadding
    }

    private var headerAnimation: Animation {
        store.reduceMotion
            ? .easeOut(duration: 0.08)
            : .timingCurve(0.22, 1, 0.36, 1, duration: 0.20)
    }
}

private struct StatusReadout: View {
    let status: MonitorStatus
    let text: String
    let showsText: Bool
    let spacing: CGFloat
    let matrixSize: CGFloat
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: spacing) {
            NotchStatusMatrix(
                state: state,
                size: matrixSize,
                isAnimated: !reduceMotion
            )

            if showsText {
                SearchlightLabel(
                    text: text,
                    isSweeping: state.isActive && !reduceMotion
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var state: NotchMatrixState {
        NotchMatrixState(status)
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
                        - PanelMetrics.expandedHorizontalPadding * 2,
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

private struct ExpandedPanelFooter: View {
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var store: MonitorStore

    @State private var isSettingsHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(store.expandedFooterText)
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(NotchPalette.label)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(isSettingsHovered ? 0.12 : 0))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                isSettingsHovered ? NotchPalette.sessionTitle : NotchPalette.label
            )
            .onHover { isSettingsHovered = $0 }
            .animation(
                store.reduceMotion ? nil : .easeOut(duration: 0.12),
                value: isSettingsHovered
            )
            .accessibilityLabel("Open Settings")
            .help("Open Settings")
        }
        .frame(maxWidth: .infinity)
        .frame(height: PanelMetrics.expandedFooterHeight)
        .overlay(alignment: .top) {
            // The separator *is* the quota meter — all usage lives down here now,
            // and the rule was already spanning this width doing nothing.
            UsageMeter(fill: store.usageMeterFill)
        }
        .padding(.horizontal, PanelMetrics.expandedHorizontalPadding)
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
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let preview = store.showsContentPreviews
            ? session.preview.map { "，当前内容：\($0)" } ?? ""
            : "，内容预览已隐藏"
        // Spoken form, not the drawn "12:34" — VoiceOver reads that as a clock
        // time. The row draws the elapsed value, so the label must carry it too.
        let elapsed = store.spokenElapsedText(for: session).map { "，已运行 \($0)" }
            ?? ""
        return "\(session.projectName)，\(session.title)，"
            + "\(session.status.controlTitle)\(elapsed)\(preview)"
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.projectName)
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(NotchPalette.label)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    UntruncatedSingleLineText(
                        text: session.title,
                        font: .system(size: 13, weight: .medium),
                        color: NotchPalette.sessionTitle,
                        lineHeight: 17
                    )
                    .mask(TrailingAlphaFade())

                    if store.showsContentPreviews, let preview = session.preview {
                        UntruncatedSingleLineText(
                            text: preview,
                            font: .system(size: 13, weight: .light),
                            color: NotchPalette.label,
                            lineHeight: 18,
                            sweeps: sweepsBody
                        )
                        .mask(TrailingAlphaFade())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SessionStatusControl(session: session)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 16)
        }
        .contentShape(Rectangle())
        .frame(
            maxWidth: .infinity,
            minHeight: PanelMetrics.sessionRowHeight,
            maxHeight: PanelMetrics.sessionRowHeight
        )
    }

    /// A session sweeps its body until it finishes. Hovering no longer changes
    /// anything about the indicator, so the row's own state is the only input.
    private var sweepsBody: Bool {
        session.status.keepsTiming && !store.reduceMotion
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
    @EnvironmentObject private var store: MonitorStore
    let session: MonitoredSession

    // One mark per row at most, and no hue — this surface says everything with
    // brightness and motion, and the amber and green dots were the only two
    // colours left on it. A row that wants the user counts in bright white; a
    // running row counts dim; a finished row shows nothing, because its still
    // body and absent timer already say so and the dot was a redundant third.
    var body: some View {
        if let elapsed = store.elapsedText(for: session) {
            NotchTimerText(text: elapsed, tint: tint, weight: weight)
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

    private var wantsAttention: Bool {
        session.status == .inputNeeded || session.status == .approvalNeeded
    }

    private var tint: Color {
        // Brightness is the attention channel, the same one the searchlight uses.
        wantsAttention ? NotchPalette.spotlight : NotchPalette.label
    }

    private var weight: Font.Weight {
        wantsAttention ? .medium : .light
    }
}

private struct UntruncatedSingleLineText: View {
    let text: String
    let font: Font
    let color: Color
    let lineHeight: CGFloat
    var sweeps = false

    var body: some View {
        GeometryReader { proxy in
            glyphs
                .overlay {
                    if sweeps {
                        SearchlightBand().mask(glyphs)
                    }
                }
                .frame(width: proxy.size.width, alignment: .leading)
                .clipped()
        }
        .frame(height: lineHeight)
    }

    private var glyphs: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .fixedSize(horizontal: true, vertical: false)
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
        .environmentObject(MonitorStore())
        .frame(
            width: PanelMetrics.expandedBaselineWidth,
            height: PanelMetrics.expandedHeight(
                compactHeight: PanelMetrics.referenceCompactHeight
            )
        )
        .background(Color.gray.opacity(0.2))
}
