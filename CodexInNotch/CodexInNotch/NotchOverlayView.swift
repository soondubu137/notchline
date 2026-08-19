import Combine
import SwiftUI

struct NotchOverlayView: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                PanelSurface(cornerRadius: store.surfaceCornerRadius)

                VStack(spacing: 0) {
                    OverlayHeader()
                        .frame(height: store.compactHeight)

                    if store.isExpanded, !store.expandsToPillOnly {
                        ExpandedPanelContent()
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: -6)),
                                    removal: .opacity
                                )
                            )
                    }
                }
                // The window is one shoulder wider than the panel on each side,
                // because that is where `PanelContour` draws the curve back up
                // to the menu bar. Content is laid out in the body inside them,
                // so its padding is measured from the black edge and not from
                // an invisible window bound — and so is the region that answers
                // to the pointer, which leaves the shoulders passing clicks
                // through to the menu bar items they overhang.
                .frame(
                    width: max(0, proxy.size.width - store.surfaceCornerRadius * 2),
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
                .animation(contentAnimation, value: store.isExpanded)
            }
        }
        .clipped()
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
            + "\(store.statusDisplayName)\(elapsed)，\(usage)"
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
                marks: store.presenceMarks,
                drawsMarks: store.drawsCompactMarks,
                text: statusText,
                showsText: showsStatusText,
                spacing: PanelMetrics.expandedReadoutSpacing,
                matrixSize: PanelMetrics.statusMatrixSize,
                markSpacing: PanelMetrics.compactMatrixSpacing,
                reduceMotion: store.reduceMotion
            )

            Spacer(minLength: 0)

            // Trailing wing, compact only: present while a turn is timed, absent
            // otherwise so a notched display shows no empty second cut-out. The
            // expanded view times each row individually instead.
            if !store.isExpanded, let startedAt = store.compactTimerStart {
                ElapsedReadout(
                    startedAt: startedAt,
                    tick: store.elapsedTick.eraseToAnyPublisher()
                )
            }

            // The gear lives up here now rather than in the footer, for one and
            // two products alike. The footer became three quota rules and had no
            // room left; the top bar's trailing side is empty whenever the panel
            // is open, because the compact timer only draws while collapsed.
            if store.isExpanded {
                SettingsButton()
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .animation(headerAnimation, value: store.isExpanded)
    }

    private var statusText: String {
        // The resting pill keeps the short, unattributed word even when it is
        // widened. Nothing is connected, so naming one product ("Codex
        // disconnected") would single out a product for a state that is about
        // all of them — and it would overflow a pill sized for the short form.
        if store.expandsToPillOnly {
            return store.status.compactDisplayName(for: nil)
        }
        return store.isExpanded ? store.statusDisplayName : store.compactStatusReadoutText
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
    let marks: [PresenceMark]
    let drawsMarks: Bool
    let text: String
    let showsText: Bool
    let spacing: CGFloat
    let matrixSize: CGFloat
    let markSpacing: CGFloat
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: spacing) {
            if drawsMarks {
                HStack(spacing: markSpacing) {
                    // Order is `AgentKind`'s and never urgency's, so a mark
                    // never moves out from under the eye reading it.
                    ForEach(marks, id: \.agent) { mark in
                        NotchStatusMatrix(
                            state: NotchMatrixState(mark.status),
                            size: matrixSize,
                            isAnimated: !reduceMotion,
                            agent: mark.agent
                        )
                    }
                }
            }

            if showsText {
                SearchlightLabel(
                    text: text,
                    isSweeping: isActive && !reduceMotion
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// The label sweeps if *any* mark is in flight. There is one label for both
    /// products and it takes the most urgent status, so it has to follow the
    /// most urgent mark rather than a single product's.
    private var isActive: Bool {
        marks.contains { NotchMatrixState($0.status).isActive }
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
            openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .regular))
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
        .animation(
            store.reduceMotion ? nil : .easeOut(duration: 0.12),
            value: isHovered
        )
        .accessibilityLabel("Open Settings")
        .help("Open Settings")
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
                        - PanelMetrics.sessionRowGutter * 2,
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

/// The quota footer: one rule per product, and a shared usage line.
///
/// One product draws a single full-width rule, exactly as before. Two draw
/// Codex's full-width rule above a split row of Claude Code's two windows —
/// the halving is not to make them fit but because that product genuinely has
/// two windows to report, a 5-hour session one and a 7-day one.
private struct ExpandedPanelFooter: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.footerRuleSpacing) {
            if isFolded {
                // Today's line rises to where a caption always starts, at the
                // top of the footer box, and the rules are simply not drawn.
                QuotaFoldLine { FooterCaption(store.foldedTodayText) }
            } else {
                ForEach(store.footerRules) { rule in
                    FooterRuleRow(rule: rule, inlineTodayText: inlineTodayText)
                }

                if let today = store.footerTodayText {
                    QuotaFoldLine { FooterCaption(today) }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: store.expandedFooterHeight, alignment: .top)
        .padding(.horizontal, PanelMetrics.expandedHorizontalPadding)
    }

    private var isFolded: Bool {
        store.isQuotaFolded && store.showsQuotaFoldControl
    }

    /// The single-Codex footer keeps today's tokens in the one caption it has,
    /// rather than spending a second line on three words.
    private var inlineTodayText: String? {
        store.footerTodayText == nil ? store.expandedFooterText : nil
    }
}

/// The footer's last line, and the disclosure that folds the rules away.
///
/// The whole line is the hit target — the chevron is the affordance, not the
/// target — so clicking the quota caption itself folds the block, which is what
/// a user tries first.
private struct QuotaFoldLine<Content: View>: View {
    @EnvironmentObject private var store: MonitorStore

    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if store.showsQuotaFoldControl {
                Button {
                    store.toggleQuotaFold()
                } label: {
                    HStack(spacing: PanelMetrics.footerWindowSpacing) {
                        content()
                        QuotaFoldChevron(isFolded: store.isQuotaFolded)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    store.isQuotaFolded ? "Show quota rules" : "Hide quota rules"
                )
            } else {
                content()
            }
        }
        // The control is a point taller than the caption it rides. The footer's
        // own height does not move: the trailing `Spacer` absorbs it.
        .frame(height: PanelMetrics.quotaFoldControlSize)
    }
}

/// One glyph, turned 180° between the two states rather than swapped for a
/// second drawing.
///
/// It points down while folded because the panel hangs from the notch and can
/// only grow downward — the chevron points the way the panel will move, which is
/// also the "show more" every list uses.
private struct QuotaFoldChevron: View {
    @EnvironmentObject private var store: MonitorStore

    let isFolded: Bool

    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(NotchPalette.label)
            .frame(
                width: PanelMetrics.quotaFoldControlSize,
                height: PanelMetrics.quotaFoldControlSize
            )
            .rotationEffect(.degrees(isFolded ? 0 : 180))
            .animation(
                store.reduceMotion ? nil : .easeOut(duration: 0.16),
                value: isFolded
            )
    }
}

/// One product's rules, and the captions under them.
private struct FooterRuleRow: View {
    let rule: FooterRule
    let inlineTodayText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.footerCaptionSpacing) {
            HStack(spacing: PanelMetrics.footerWindowSpacing) {
                ForEach(rule.windows.indices, id: \.self) { index in
                    UsageMeter(
                        fill: rule.windows[index].fill,
                        ink: NotchPalette.ink(for: rule.agent)
                    )
                }
            }
            .frame(height: PanelMetrics.footerRuleHeight)

            if let inlineTodayText {
                // Today's tokens are already on this caption, so there is no
                // totals line below to carry the disclosure — and adding one
                // would spend exactly the height folding is meant to save. It
                // rides this line instead.
                QuotaFoldLine { FooterCaption(inlineTodayText) }
            } else {
                HStack(spacing: PanelMetrics.footerWindowSpacing) {
                    ForEach(rule.windows.indices, id: \.self) { index in
                        FooterCaption(rule.windows[index].caption)
                    }
                }
            }
        }
    }
}

/// The footer's 11pt caption, which every line down here uses.
private struct FooterCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .light))
            .foregroundStyle(NotchPalette.label)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    SessionRowCaption(
                        session: session,
                        style: store.productAttribution,
                        showsAttribution: store.showsProductAttribution
                    )

                    SessionRowText(
                        text: session.title,
                        font: .systemFont(ofSize: 13, weight: .medium),
                        color: NotchPalette.sessionTitleDrawingColor,
                        lineHeight: 17
                    )

                    if store.showsContentPreviews, let preview = session.preview {
                        SessionRowText(
                            text: preview,
                            font: .systemFont(ofSize: 13, weight: .light),
                            color: NotchPalette.labelDrawingColor,
                            lineHeight: 18,
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
        // Flush with the block's leading edge, so it reads as a mark beside the
        // row rather than as a fifth thing inside it. Half the row tall, which
        // keeps it clear of the block's own 12 pt corners.
        .overlay(alignment: .leading) {
            if drawsRail {
                RoundedRectangle(
                    cornerRadius: PanelMetrics.sessionRowRailRadius,
                    style: .continuous
                )
                .fill(NotchPalette.ink(for: session.agent).on)
                .frame(
                    width: PanelMetrics.sessionRowRailWidth,
                    height: PanelMetrics.sessionRowRailHeight
                )
            }
        }
        .contentShape(Rectangle())
        .frame(
            maxWidth: .infinity,
            minHeight: PanelMetrics.sessionRowHeight,
            maxHeight: PanelMetrics.sessionRowHeight
        )
    }

    /// The rail is drawn on the same terms as every other attribution: only
    /// while two products are connected and there is something to tell apart.
    private var drawsRail: Bool {
        store.showsProductAttribution && store.productAttribution == .colourBar
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
        if let startedAt = store.elapsedStart(for: session) {
            ElapsedReadout(
                startedAt: startedAt,
                tick: store.elapsedTick.eraseToAnyPublisher(),
                tint: tint,
                weight: weight
            )
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

    private var tint: NSColor {
        // Brightness is the attention channel, the same one the searchlight uses.
        wantsAttention
            ? NotchPalette.spotlightDrawingColor
            : NotchPalette.labelDrawingColor
    }

    private var weight: NSFont.Weight {
        wantsAttention ? .medium : .light
    }
}

/// The row's leading 11pt line: the Project, and — while two products are
/// connected — which product this one is.
///
/// The attribution costs horizontal space and what it costs comes out of the
/// Project text: `Claude Code ·` takes about 73 of the caption's 394. That is
/// accepted rather than overlooked. The caption is the least important line in
/// the row and it ends in a fade rather than an ellipsis, so losing its tail is
/// the cheapest thing on this surface to lose.
private struct SessionRowCaption: View {
    let session: MonitoredSession
    let style: ProductAttributionStyle
    let showsAttribution: Bool

    var body: some View {
        HStack(spacing: 6) {
            if showsAttribution, style == .badge {
                Text(session.agent.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchPalette.ink(for: session.agent).on)
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(NotchPalette.ink(for: session.agent).off)
                    )
                    .fixedSize()
            }

            Text(captionText)
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(captionColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        // The badge is a point taller than the text line, so the caption's own
        // height moves 14 -> 16 with it. The row height does not: the content
        // block absorbs it.
        .frame(height: showsAttribution && style == .badge ? 16 : 14)
    }

    private var captionText: String {
        guard showsAttribution, style.namesProductInCaption else {
            return session.projectName
        }
        return "\(session.agent.displayName) · \(session.projectName)"
    }

    /// Only `nameAndColour` tints, and it tints the whole line rather than the
    /// prefix alone — the Project belongs to that product too, and a two-colour
    /// caption would be a third encoding of the same fact.
    private var captionColor: Color {
        guard showsAttribution, style == .nameAndColour else {
            return NotchPalette.label
        }
        return NotchPalette.ink(for: session.agent).on
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
