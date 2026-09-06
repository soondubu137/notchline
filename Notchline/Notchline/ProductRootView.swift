// First run, as redesigned for macOS 26. See `figma-design.md` §7.
//
// One pane, not three. V1 spent a window each on value, consent and
// confirmation, but the consent is the switch and the confirmation is the row
// turning green — the other two windows were narration around two controls.
// Collapsing them leaves room for the thing the flow never explained: what the
// notch actually draws.
//
// It teaches that the way the README figures do, and for the same reason those
// figures exist: the parts have names, and a still of the real surface with
// its parts numbered says more than any amount of prose. What does not carry
// over is their layout — those figures are four thousand pixels wide with a
// column of callouts either side, and a `532` pt content area would draw that
// text at four points. So the callouts become pins and a key, and the drawings
// stay at the size the user will meet them (`OnboardingAnatomy.swift`).
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

/// Two pages: the connections, then the notch.
///
/// **The teaching outgrew the page it was on.** One window carrying the hero,
/// both switches, the bar, the five states and the whole panel came to `1026`
/// pt — past what a 14-inch built-in display leaves under its menu bar, which
/// put `Start` behind the Dock on the smallest Mac this ships to. Cutting the
/// drawings back to fit was the wrong economy: what would have gone is the
/// panel's quota footer and its second row, which are two of the four things
/// the panel exists to show.
///
/// So the flow is two pages of about `380` and `850`, and they divide on the
/// seam the content already had: **page one asks for something, page two
/// explains something.** Nothing on the first page needs the second to make
/// sense — a user who presses `Continue` without reading has connected both
/// products correctly — and nothing on the second asks for anything, which is
/// why it can carry a `Back` and be re-read.
///
/// The second page is also where every specimen lives, and they are built on
/// first use (``NotchSpecimen``), so a launch that stops at page one never
/// composes a panel, a store or a mark.
private struct OnboardingView: View {
    @EnvironmentObject private var store: MonitorStore
    @State private var page: Page = .connect

    private enum Page {
        case connect
        case read
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            switch page {
            case .connect:
                hero
                connectGroup
                connectClosing
            case .read:
                notchGroup
                readClosing
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .frame(width: 580, alignment: .leading)
        .background(MacOSWindowColor.windowBackground)
        .background(SettingsWindowChrome(title: "Welcome to Notchline"))
    }

    /// Page one's closing line: the standing statement, the version, and the
    /// way on.
    ///
    /// Same shape as the Settings window's closing row — an explanation with
    /// the action it is about on the end. The read-only promise belongs here
    /// rather than on page two, because this is the page with the switches on
    /// it and it is the switches the promise is about.
    ///
    /// The version rides under that statement, in the same place and the same
    /// view Settings uses (`AppVersionLine`), so the window says it in one form
    /// before and after onboarding. Page one and not page two: this is the page
    /// the window opens on, and a build number is a fact about the app rather
    /// than part of the teaching.
    private var connectClosing: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notchline only reads. Nothing here changes Codex or Claude Code.")
                    .settingsFootnote(MacOSWindowColor.tertiaryText)

                AppVersionLine()
            }

            Button("Continue") {
                page = .read
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
    }

    /// Page two's closing line: where all of this lives afterwards, `Back`, and
    /// the one action that ends onboarding.
    private var readClosing: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("All of this is in Settings afterwards, behind the gear.")
                .settingsFootnote(MacOSWindowColor.tertiaryText)

            Button("Back") {
                page = .connect
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)

            Button("Start") {
                store.completeOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
    }

    /// The icon, and the one sentence about what the app is for.
    ///
    /// No second title: the window's own title bar already says the name, and
    /// repeating it in the content area is the mistake the Settings redesign
    /// removed. No second promise either — the closing line carries the
    /// read-only statement, and saying it twice on one page made the page read
    /// as though it were arguing with somebody.
    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)

            Text(
                "Every Codex and Claude Code session at the top of your screen "
                    + "— running, waiting on you, or finished but unseen."
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
    /// `Recheck` sits in the footnote rather than beside the switches because
    /// turning the Codex one on is not the end of it: Codex keys hook trust to
    /// each definition's place in the file and asks before it will run one, so
    /// that row only says Connected once a trusted event has actually arrived.
    /// Claude Code has no such step — its row answers as soon as the file is
    /// written.
    private var connectGroup: some View {
        SettingsGroup(header: "Connect your agents") {
            ProductConnectionRows()
        } footnote: {
            SettingsFootnote(
                "Each switch writes Notchline’s hooks into ~/.codex/hooks.json "
                    + "or ~/.claude/settings.json and takes them out again when "
                    + "off. Both files are backed up first."
            ) {
                Button("Recheck") {
                    store.refreshNow()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
    }

    /// The whole of what the notch draws: shut, the five states, hovered.
    ///
    /// Three blocks rather than one row of swatches. The swatches said what the
    /// marks mean and nothing about where they sit, which left the first thing
    /// a user actually sees — a bar in the menu bar with six parts in it —
    /// unexplained. The bar and the panel are the product's own views at their
    /// own size (`OnboardingAnatomy.swift`), so this group cannot fall out of
    /// step with the surface it describes.
    private var notchGroup: some View {
        SettingsGroup(header: "Reading the notch") {
            CollapsedBarAnatomy()
                .padding(14)

            SettingsSeparator()

            MatrixLegend()

            SettingsSeparator()

            ExpandedPanelAnatomy()
                .padding(.vertical, 14)
        } footnote: {
            SettingsFootnote(
                "Hovering opens one list — both products, most urgent first. "
                    + "With nothing connected the mark is grey, or absent on a "
                    + "notched display."
            )
        }
        // Both specimens read from one clock, and it is a real one: the
        // readings are the product's own, counting on from the moment this
        // window opened. Restarted every ten minutes so a window left open all
        // afternoon is still teaching from a turn-shaped figure rather than
        // from `4:17:33`. Cancelled with the view, which is the whole of its
        // lifetime.
        .task { await NotchSpecimen.cycle() }
    }
}

/// The five appearances, live, in the surface's one ink.
///
/// They animate here for the same reason they animate in the notch: the
/// pattern *is* the motion, and a still grid says far less than a moving one.
/// It costs nothing to run — the tracks are layer animations on the render
/// server, and `Connected` holds by itself because its state has no period at
/// all.
///
/// **One mark per specimen, which is how many the notch draws.** It taught two
/// for as long as hue said which product: first as a single matrix cut on its
/// own diagonal, then as a stacked pair in the two brand colours. Both are
/// gone with the colours (`colour-v2.md` §1) — the surface has one aggregate
/// mark standing for every product at once, in ``NotchPalette/themeInk``, and
/// a legend showing anything else would be teaching a drawing the product
/// never makes.
private struct MatrixLegend: View {
    private static let states: [(NotchMatrixState, String)] = [
        (.running, "Working..."),
        (.approvalNeeded, "Approval"),
        (.inputNeeded, "Input"),
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
                            size: MarkSpecimenMetrics.matrixSize,
                            ink: NotchPalette.themeInk
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "The five marks, one for every product at once: running, "
                + "approval, input, completed, and connected with nothing running."
        )
    }
}

/// A scrap of the notch to stand a specimen on.
///
/// The matrix is drawn for one surface only — a black one — and its unlit bed
/// is nearly black by design. Dropped straight onto a light card it would read
/// as a smudge, so a specimen brings the ground it belongs to with it. The chip
/// is also what contains the glow: the lit passes bleed `cell × 10.5/27 × 3`
/// past the matrix's own bounds, which at this size is less than the padding
/// here.
///
/// A mark shown off the notch should look the same wherever it is shown.
struct NotchChip<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding((MarkSpecimenMetrics.chipSize - MarkSpecimenMetrics.matrixSize) / 2)
            .background(
                Color.black,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }
}

enum MarkSpecimenMetrics {
    /// The size the notch itself draws a matrix at, so a specimen is one
    /// rather than an illustration of one.
    static let matrixSize = PanelMetrics.statusMatrixSize
    static let chipSize: CGFloat = 30
}

#Preview("Onboarding") {
    ProductRootView()
        .environmentObject(MonitorStore())
}
