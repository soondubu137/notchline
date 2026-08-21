// First run, as redesigned for macOS 26. See `figma-design.md` §7.
//
// One pane, not three. V1 spent a window each on value, consent and
// confirmation, but the consent is the switch and the confirmation is the row
// turning green — the other two windows were narration around two controls.
// Collapsing them leaves room for the thing the flow never explained: what the
// notch actually draws.
//
// It is the Settings window's shapes throughout, because it becomes the
// Settings window: the same scene shows this view until onboarding completes
// and `AppSettingsView` afterwards, so the second time it opens nothing has
// moved.
import AppKit
import SwiftUI

struct ProductRootView: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        Group {
            if store.hasCompletedOnboarding {
                AppSettingsView()
            } else {
                OnboardingView()
            }
        }
    }
}

private struct OnboardingView: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            hero
            connectGroup
            notchGroup

            // Same shape as the Settings window's closing line: the standing
            // statement about what this app does, and the action it is about.
            HStack(alignment: .center, spacing: 16) {
                Text(
                    "Notchline only reads. Nothing here changes state in "
                        + "Codex or Claude Code."
                )
                .settingsFootnote(MacOSWindowColor.tertiaryText)

                Button("Start") {
                    store.completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .frame(width: 580, alignment: .leading)
        .background(MacOSWindowColor.windowBackground)
        .background(SettingsWindowChrome(title: "Welcome to Notchline"))
    }

    /// The icon, and the one sentence about what the app is for.
    ///
    /// No second title: the window's own title bar already says the name, and
    /// repeating it in the content area is the mistake the Settings redesign
    /// removed.
    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)

            Text(
                "Notchline keeps every Codex and Claude Code session that is "
                    + "running, waiting on you, or finished but unseen at the "
                    + "top of your screen. It only ever reads."
            )
            .font(.system(size: 13))
            .foregroundStyle(MacOSWindowColor.secondaryText)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The two connections, in the rows Settings uses for the same job.
    ///
    /// `Recheck` sits in the footnote rather than beside the switch because
    /// turning the switch on is not the end of it: Codex keys hook trust to
    /// each definition's place in the file and asks before it will run one, so
    /// the row only says Connected once a trusted event has actually arrived.
    private var connectGroup: some View {
        SettingsGroup(header: "Connect your agents") {
            ProductConnectionRows()
        } footnote: {
            SettingsFootnote(
                "The switch installs five lifecycle definitions in "
                    + "~/.codex/hooks.json and removes them again when it is "
                    + "off; your own hooks are untouched. Claude Code is "
                    + "registered by hand — Notchline never writes that file."
            ) {
                Button("Recheck") {
                    store.refreshNow()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
    }

    /// The whole of what the notch draws, in four specimens and two words.
    ///
    /// A state called `Running` does not need a sentence saying that a turn is
    /// running. The specimens carry the pattern, the labels carry the names,
    /// and the only thing left to say is which colour belongs to which product.
    private var notchGroup: some View {
        SettingsGroup(header: "Reading the notch") {
            MatrixLegend()
            SettingsSeparator()
            ProductColourKey()
        } footnote: {
            SettingsFootnote(
                "With nothing connected the matrix is grey — or on a notched "
                    + "display, absent."
            )
        }
    }
}

/// The four appearances, live.
///
/// They animate here for the same reason they animate in the notch: the
/// pattern *is* the motion, and a still checkerboard says far less than a
/// moving one. It costs nothing to run — the tracks are layer animations on
/// the render server, and `Connected` holds by itself because its state has no
/// period at all.
private struct MatrixLegend: View {
    @EnvironmentObject private var store: MonitorStore

    private static let states: [(NotchMatrixState, String)] = [
        (.running, "Running"),
        (.needsAttention, "Input · Approval"),
        (.completed, "Completed"),
        (.inactive, "Connected")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.states.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 8) {
                    NotchChip {
                        NotchStatusMatrix(
                            state: entry.0,
                            size: OnboardingMetrics.matrixSize,
                            isAnimated: !store.reduceMotion,
                            split: .products
                        )
                    }

                    Text(entry.1)
                        .font(.system(size: 12))
                        .foregroundStyle(MacOSWindowColor.primaryText)
                }
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
    }
}

/// Which hue belongs to which product, in the fewest words that can say it.
///
/// The specimens above carry both colours at once, which shows that there are
/// two but not which is which. This row answers only that, and it sits on the
/// same four columns as the legend so the two chips line up under specimens
/// rather than floating between them.
private struct ProductColourKey: View {
    private static let products: [AgentKind?] = [.codex, nil, .claudeCode, nil]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.products.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 8) {
                    if let agent = entry {
                        NotchChip {
                            NotchStatusMatrix(
                                state: .running,
                                size: OnboardingMetrics.matrixSize,
                                isAnimated: false,
                                agent: agent
                            )
                        }

                        Text(agent.displayName)
                            .font(.system(size: 12))
                            .foregroundStyle(MacOSWindowColor.primaryText)
                    }
                }
                .padding(.trailing, 12)
                .frame(
                    maxWidth: .infinity,
                    minHeight: OnboardingMetrics.chipSize,
                    alignment: .leading
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// A scrap of the notch to stand a specimen on.
///
/// The matrix is drawn for one surface only — a black one — and its unlit bed
/// is nearly black by design. Dropped straight onto a light card it would read
/// as a smudge, so the legend brings the ground it belongs to with it. The chip
/// is also what contains the glow: the lit passes bleed `cell × 10.5/27 × 3`
/// past the matrix's own bounds, which at this size is less than the padding
/// here.
private struct NotchChip<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding((OnboardingMetrics.chipSize - OnboardingMetrics.matrixSize) / 2)
            .background(
                Color.black,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }
}

private enum OnboardingMetrics {
    /// The size the notch itself draws a matrix at, so the legend is a
    /// specimen rather than an illustration of one.
    static let matrixSize = PanelMetrics.statusMatrixSize
    static let chipSize: CGFloat = 30
}

#Preview("Onboarding") {
    ProductRootView()
        .environmentObject(MonitorStore())
}
