import SwiftUI

struct NotchOverlayView: View {
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                PanelSurface(geometry: store.geometry)

                VStack(spacing: 0) {
                    OverlayHeader()
                        .frame(height: store.compactHeight)

                    ExpandedPanelContent()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(store.isExpanded ? 1 : 0)
                        .offset(y: store.isExpanded ? 0 : -8)
                        .allowsHitTesting(store.isExpanded)
                        .animation(contentAnimation, value: store.isExpanded)
                }
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .top
                )
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
        "Codex，\(store.sessions.count) 个相关会话，状态 \(store.status.fallbackTitle)，token 余额百分之 \(store.tokenRemainingPercent)"
    }
}

private struct PanelSurface: View {
    let geometry: DisplayGeometry

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
        switch geometry {
        case .notched:
            "PanelNotchCompact"
        case .noNotch:
            "PanelFallbackCompact"
        }
    }
}

private struct OverlayHeader: View {
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                StatusIndicatorView(status: store.status)

                if store.geometry == .noNotch {
                    Text(store.status.fallbackTitle)
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: store.geometry == .notched ? 0 : 16)

            tokenBalance
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .animation(headerAnimation, value: store.isExpanded)
    }

    private var tokenBalance: some View {
        Text(store.tokenText)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .fixedSize()
    }

    private var horizontalPadding: CGFloat {
        switch store.geometry {
        case .notched:
            store.isExpanded ? 28 : 35
        case .noNotch:
            store.isExpanded ? 28 : 20
        }
    }

    private var headerAnimation: Animation {
        store.reduceMotion
            ? .easeOut(duration: 0.08)
            : .timingCurve(0.22, 1, 0.36, 1, duration: 0.28)
    }
}

private struct ExpandedPanelContent: View {
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 0.5)
                .padding(.horizontal, 24)

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(store.sessions.enumerated()), id: \.element.id) { index, session in
                        SessionRow(session: session)

                        if index < store.sessions.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.10))
                                .frame(height: 0.5)
                                .padding(.horizontal, 36)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(.white)
    }
}

private struct SessionRow: View {
    @EnvironmentObject private var store: DemoStore
    let session: DemoSession

    @State private var isHovered = false

    var body: some View {
        ZStack {
            if session.isHighlighted || isHovered {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.10 : 0.075))
                    .frame(height: 72)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.title)
                        .foregroundStyle(Color.white.opacity(0.97))
                    Text(session.preview)
                        .foregroundStyle(Color.white.opacity(0.62))
                }
                .font(.system(size: 13, weight: .regular))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                StatusIndicatorView(status: session.status)
            }
            .padding(.horizontal, 36)
        }
        .frame(height: 80)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            store.simulateOpening(session)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.title)，\(session.status.controlTitle)，当前内容：\(session.preview)")
        .accessibilityAddTraits(.isButton)
    }
}

private struct StatusIndicatorView: View {
    @EnvironmentObject private var store: DemoStore
    let status: DemoStatus

    @State private var isPulsing = false

    var body: some View {
        Group {
            switch status {
            case .running:
                Image("StatusRunning")
                    .resizable()
            case .waitingApproval:
                Image("StatusWaiting")
                    .resizable()
            case .completed:
                ZStack {
                    Image("StatusCompletedRing")
                        .resizable()
                    Image("StatusCompletedCheck")
                        .resizable()
                        .frame(width: 10.7, height: 8.2)
                }
            case .failed:
                ZStack {
                    Image("StatusFailedRing")
                        .resizable()
                    Image("StatusFailedX")
                        .resizable()
                        .frame(width: 9, height: 9)
                }
            }
        }
        .frame(width: 18, height: 18)
        .opacity(status == .running && isPulsing ? 0.68 : 1)
        .onAppear {
            updatePulseAnimation()
        }
        .onChange(of: store.reduceMotion) {
            updatePulseAnimation()
        }
        .accessibilityHidden(true)
    }

    private func updatePulseAnimation() {
        guard status == .running, !store.reduceMotion else {
            withAnimation(nil) {
                isPulsing = false
            }
            return
        }

        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}

#Preview("Notch Expanded") {
    NotchOverlayView()
        .environmentObject(DemoStore())
        .frame(width: PanelMetrics.expandedWidth, height: PanelMetrics.expandedHeight)
        .background(Color.gray.opacity(0.2))
}
