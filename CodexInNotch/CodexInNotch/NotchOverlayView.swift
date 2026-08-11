import SwiftUI

struct NotchOverlayView: View {
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        ZStack(alignment: .top) {
            PanelSurface(
                geometry: store.geometry,
                isExpanded: store.isExpanded
            )

            if store.isExpanded {
                ExpandedPanelContent()
                    .transition(.opacity.animation(contentAnimation))
            } else {
                CompactHeader()
                    .transition(.opacity.animation(contentAnimation))
            }
        }
        .frame(
            width: store.currentPanelSize.width,
            height: store.currentPanelSize.height,
            alignment: .top
        )
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
            : .easeInOut(duration: 0.20)
    }

    private var panelAccessibilityLabel: String {
        "Codex，\(store.sessions.count) 个相关会话，状态 \(store.status.fallbackTitle)，token 余额百分之 \(store.tokenRemainingPercent)"
    }
}

private struct PanelSurface: View {
    let geometry: DisplayGeometry
    let isExpanded: Bool

    var body: some View {
        Image(assetName)
            .resizable(
                capInsets: isExpanded
                    ? EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
                    : EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24),
                resizingMode: .stretch
            )
            .interpolation(.high)
    }

    private var assetName: String {
        switch (geometry, isExpanded) {
        case (.notched, false):
            "PanelNotchCompact"
        case (.noNotch, false):
            "PanelFallbackCompact"
        case (.notched, true):
            "PanelNotchExpanded"
        case (.noNotch, true):
            "PanelFallbackExpanded"
        }
    }
}

private struct CompactHeader: View {
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        Group {
            if store.geometry == .notched {
                HStack(spacing: 0) {
                    StatusIndicatorView(status: store.status)
                    Spacer(minLength: 0)
                    tokenBalance
                }
                .padding(.horizontal, 35)
            } else {
                HStack(spacing: 0) {
                    StatusIndicatorView(status: store.status)
                    Text(store.status.fallbackTitle)
                        .padding(.leading, 8)
                    tokenBalance
                        .padding(.leading, 16)
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(height: store.compactHeight)
        .contentShape(Rectangle())
    }

    private var tokenBalance: some View {
        Text(store.tokenText)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .fixedSize()
    }
}

private struct ExpandedPanelContent: View {
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        VStack(spacing: 0) {
            expandedHeader
                .frame(height: store.compactHeight)

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

    @ViewBuilder
    private var expandedHeader: some View {
        if store.geometry == .notched {
            HStack(spacing: 0) {
                StatusIndicatorView(status: store.status)
                Spacer(minLength: 0)
                tokenBalance
            }
            .padding(.horizontal, 28)
        } else {
            HStack(spacing: 0) {
                StatusIndicatorView(status: store.status)
                Text(store.status.fallbackTitle)
                    .font(.system(size: 13, weight: .bold))
                    .padding(.leading, 8)
                Spacer(minLength: 16)
                tokenBalance
            }
            .padding(.horizontal, 28)
        }
    }

    private var tokenBalance: some View {
        Text(store.tokenText)
            .font(.system(size: 13, weight: .bold))
            .fixedSize()
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
