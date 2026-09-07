// Three first-run pages in one stable macOS window. See `figma-design.md` §7.
// The specimens use the product's own views with numbered keys. Settings
// reuses the scene after onboarding completes, at its own content height.
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

/// Three pages share one fixed content area and one bottom navigation row.
/// Only the current page is built, so opening the connection page does not
/// initialise the specimen stores. Long content scrolls above the controls.
enum OnboardingLayout {
    static let width: CGFloat = 580
    static let height: CGFloat = 840
    static let horizontalPadding: CGFloat = 24
    static let cardWidth = width - horizontalPadding * 2
}

struct OnboardingView: View {
    @EnvironmentObject private var store: MonitorStore
    @State private var page: Page = .connect

    enum Page: CaseIterable {
        case connect
        case read
        case answer
    }

    init(page: Page = .connect) {
        _page = State(initialValue: page)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 22) {
                    switch page {
                    case .connect:
                        hero
                        connectGroup
                    case .read:
                        notchGroup
                    case .answer:
                        answerGroup
                    }
                }
                .frame(width: OnboardingLayout.cardWidth, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity, alignment: .top)
            .id(page)

            navigation
        }
        .padding(.horizontal, OnboardingLayout.horizontalPadding)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .frame(width: OnboardingLayout.width, height: OnboardingLayout.height)
        .background(MacOSWindowColor.windowBackground)
        .background(SettingsWindowChrome(title: "Welcome to Notchline"))
    }

    private var navigation: some View {
        HStack(spacing: 16) {
            Spacer()

            if page != .connect {
                Button("Back") {
                    page = page == .answer ? .read : .connect
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }

            Button(page == .answer ? "Start" : "Continue") {
                switch page {
                case .connect: page = .read
                case .read: page = .answer
                case .answer: store.completeOnboarding()
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)

        }
    }

    /// The icon and the one sentence about what the app is for.
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

    /// Page three: the three things on this surface that open, and what is
    /// behind each of them.
    ///
    /// **One group of three blocks, which is page two's shape.** They belong
    /// together for a reason plainer than the page: a mark opens the request it
    /// is holding, and the seam opens the rows that have left — between them,
    /// every control on this surface that does anything is on this page.
    ///
    /// **Two request shapes, because the answer row is not one shape.** A
    /// permission has something to refuse, so it draws a field, `Deny` and
    /// `Approve`; a question has no refusal at all, because the text *is* the
    /// answer, so the field takes the space and one `Send` stands where two
    /// would (`answer-in-notch.md` §7). A user shown one of them and then
    /// handed the other would meet a row that had changed shape for no reason
    /// they had been told about.
    ///
    /// The specimens are rows on the panel's own ground rather than whole
    /// panels: everything named here is inside the row block, and the header
    /// and the footer around it are page two's (`OnboardingAnatomy.swift`).
    private var answerGroup: some View {
        SettingsGroup(header: "Answering and Recent Sessions") {
            OpenCommandAnatomy()
                .padding(.vertical, 14)

            SettingsSeparator()

            OpenQuestionAnatomy()
                .padding(.vertical, 14)

            SettingsSeparator()

            RecentQueueAnatomy()
                .padding(.vertical, 14)
        } footnote: {
            SettingsFootnote(
                "A row opens where the product sent something to show; where it "
                    + "did not, the mark says Read and takes you there instead. "
                    + "A finished turn leaves the list when its product records "
                    + "it as read, and stays under the seam for five hours."
            )
        }
        // The queue reads in ages, so it runs on page two's clock and is
        // re-staged on the same wrap. Cancelled with the view.
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
