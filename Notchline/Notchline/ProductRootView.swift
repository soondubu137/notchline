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

enum AnswerLesson: String, CaseIterable {
    case permission = "Permissions"
    case question = "Questions"
}

enum QuestionLesson: String, CaseIterable {
    case singleChoice = "Single choice"
    case multipleChoice = "Multiple choice"
    case typedAnswer = "Your own answer"

    var explanation: String {
        switch self {
        case .singleChoice:
            "Choose one option, then click Submit. Selecting an option does not submit it."
        case .multipleChoice:
            "Tick the options you want, then click Submit. Click a ticked option again to remove it."
        case .typedAnswer:
            "Type in the field beside Submit when none of the options fit. Your words are the answer while nothing is ticked."
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: MonitorStore
    @State private var page: Page = .connect
    @State private var answerLesson: AnswerLesson
    @State private var questionLesson: QuestionLesson

    enum Page: CaseIterable {
        case connect
        case read
        case answer
    }

    init(page: Page = .connect, answerLesson: AnswerLesson = .permission, questionLesson: QuestionLesson = .singleChoice) {
        _page = State(initialValue: page)
        _answerLesson = State(initialValue: answerLesson)
        _questionLesson = State(initialValue: questionLesson)
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
                        recentGroup
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
                "Every \(ProductRegistry.spokenNames) session at the top of your screen "
                    + "— running, waiting on you, or finished but unseen."
            )
            .font(.system(size: 13))
            .foregroundStyle(MacOSWindowColor.secondaryText)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The connections, in the rows Settings uses for the same job.
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
                "Trae installs a companion extension; reopen its windows afterwards. "
                    + "The other switches write Notchline’s hooks into "
                    + "\(ProductRegistry.spokenConfigurationFiles) and take them out "
                    + "again when off. Each file is backed up first."
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
                "Hovering opens one list — every product, most urgent first. "
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

    /// Recent follows the expanded panel whose seam opens it.
    private var recentGroup: some View {
        SettingsGroup(header: "Recent: find a Thread after it leaves the list") {
            RecentQueueAnatomy().padding(.vertical, 18)
        } footnote: {
            SettingsFootnote(
                "Open Recent to revisit Threads that have left the live list. "
                    + "Each row shows when it left and opens the Thread in its product. "
                    + "A finished Turn leaves the live list when its product records it as read; "
                    + "the Recent queue keeps a route back for five hours."
            )
        }
    }

    /// One lesson at a time keeps each example and its explanation together.
    /// These controls browse drawings; they never send an answer to a product.
    private var answerGroup: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Answering on the notch")
                .font(.system(size: 20, weight: .semibold))
            Text("Open a request from its mark. Read it here, then decide what to send.")
                .font(.system(size: 13))
                .foregroundStyle(MacOSWindowColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Tutorial topic", selection: $answerLesson) {
                ForEach(AnswerLesson.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch answerLesson {
            case .permission:
                SettingsGroup(header: "Read the request before approving") {
                    OpenCommandAnatomy().padding(.vertical, 18)
                } footnote: {
                    SettingsFootnote("Commands keep their monospaced text box. Other arguments appear as labelled fields. Scroll longer requests to read every detail.")
                }
                lessonNote("Approve or suggest a change", "Click Approve to allow the request. To refuse with instructions, type beside Deny and then click Deny or press Return.")
            case .question:
                Picker("Question example", selection: $questionLesson) {
                    ForEach(QuestionLesson.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                SettingsGroup(header: questionLesson.rawValue) {
                    OpenQuestionAnatomy(lesson: questionLesson).padding(.vertical, 18)
                } footnote: {
                    SettingsFootnote(questionLesson.explanation)
                }
                if questionLesson == .typedAnswer {
                    lessonNote("A ticked option wins", "Tick an option and it becomes the answer, whatever the field holds — your words dim and stay where they are, and are the answer again the moment you untick it.")
                } else {
                    lessonNote("Read more without choosing", "Show more expands a long description. It does not select the option or send an answer. Scroll the question to keep reading; the answer field stays at the bottom.")
                }
            }

            Text("These are examples. If a request cannot be answered here, the row offers a way to answer in its product.")
                .font(.system(size: 12))
                .foregroundStyle(MacOSWindowColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { await NotchSpecimen.cycle() }
    }

    private func lessonNote(_ title: String, _ explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(explanation)
                .font(.system(size: 13))
                .foregroundStyle(MacOSWindowColor.secondaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
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
