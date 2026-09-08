// The README's second anatomy figure: the three shapes a request arrives in,
// open on the notch, with every part named.
//
// Each specimen is an `OpenRow` on the panel's own ground, at the width and the
// height the store composes for that request — the plate `OnboardingAnatomy`
// draws its own page-three figures on, and the same one, so the two cannot
// disagree about what an open row looks like.
import AppKit
import SwiftUI

@testable import Notchline

/// One open row on the panel's ground: the row at the width the viewport gives
/// it, with the panel's own gutter around it.
@MainActor
struct OpenRowPlate: View {
    let store: MonitorStore

    var height: CGFloat { store.openRowHeight ?? PanelMetrics.sessionRowHeight }

    var size: CGSize {
        CGSize(
            width: store.currentPanelSize.width,
            height: height + OpenedSpecimen.gutter * 2
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black)

            if let session = store.openSession {
                OpenRow(session: session)
                    .environmentObject(store)
                    .frame(
                        width: PanelMetrics.sessionViewportWidth(
                            panelWidth: store.currentPanelSize.width
                        )
                    )
                    .padding(OpenedSpecimen.gutter)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Where an open row's parts are

/// Every anchor the three figures need, in the plate's own coordinates.
///
/// The row stands one panel gutter in from the plate on every side, so a plate
/// coordinate is the row's own plus that gutter. Everything else is asked of
/// ``OpenRowGeometry``, ``OpenedSpecimen`` and the request's own layout — the
/// same figures `OnboardingAnatomy` pins its page-three drawings from.
@MainActor
struct OpenRowAnchors {
    let store: MonitorStore

    private var geometry: OpenRowGeometry { OpenRowGeometry(store: store) }
    private var gutter: CGFloat { OpenedSpecimen.gutter }

    var rowWidth: CGFloat {
        PanelMetrics.sessionViewportWidth(panelWidth: store.currentPanelSize.width)
    }

    var plateWidth: CGFloat { store.currentPanelSize.width }
    var plateHeight: CGFloat { geometry.height + gutter * 2 }

    /// The row's own text column, and the edge its controls end on.
    var textLeft: CGFloat { gutter + PanelMetrics.sessionRowPadding }
    var textRight: CGFloat { gutter + rowWidth - PanelMetrics.sessionRowPadding }

    /// The head, which does not move when a row opens.
    var captionY: CGFloat { gutter + 12.5 + PanelMetrics.sessionRowCaptionHeight / 2 }

    var titleY: CGFloat {
        gutter + 12.5
            + PanelMetrics.sessionRowCaptionHeight
            + PanelMetrics.sessionRowLineSpacing
            + PanelMetrics.sessionRowTitleHeight / 2
    }

    /// The chevron standing where the closed row's mark was.
    var chevronLeft: CGFloat { textRight - PanelMetrics.quotaFoldControlSize }

    /// `Rollout · 2/3` — the header and the position, on the caption line's
    /// trailing side, ending one gap before the chevron.
    var setCaptionRight: CGFloat { chevronLeft - 8 }

    // MARK: The body

    private var bodyTop: CGFloat { gutter + geometry.bodyTop }

    /// The middle of the question's own lines, before its options.
    var questionY: CGFloat { gutter + geometry.questionCentre }

    /// One argument's label, and the middle of the value under it.
    func argumentLabelY(_ index: Int) -> CGFloat? {
        guard let layout = store.openRowBody,
              layout.fieldTops.indices.contains(index) else { return nil }
        return bodyTop + layout.fieldTops[index] + PanelMetrics.argumentLabelHeight / 2
    }

    func argumentValueY(_ index: Int) -> CGFloat? {
        guard let layout = store.openRowBody,
              layout.fields.indices.contains(index),
              layout.fieldTops.indices.contains(index) else { return nil }
        let field = layout.fields[index]
        return bodyTop
            + layout.fieldTops[index]
            + field.textTop
            + CGFloat(field.lines.count) * field.lineHeight / 2
    }

    // MARK: The options

    /// Where the option list begins, under the question's own lines.
    private var optionsTop: CGFloat? {
        guard let body = store.openRowBody, !body.options.isEmpty else { return nil }
        let lines = CGFloat(body.lines.count)
            * PanelMetrics.requestLineHeight(for: body.setting)
        return bodyTop + lines + PanelMetrics.optionListSpacing
    }

    private func optionTop(_ index: Int) -> CGFloat? {
        guard let optionsTop, let body = store.openRowBody,
              body.optionLayouts.indices.contains(index) else { return nil }
        let above = body.optionLayouts.prefix(index).map(\.height).reduce(0, +)
        return optionsTop
            + above
            + CGFloat(index) * PanelMetrics.optionSpacing
    }

    /// The tick box or the ring: `14` wide, leading-aligned in its own `25` pt
    /// slot, one option inset from the card's edge.
    var markerLeft: CGFloat { textLeft + PanelMetrics.optionInset }

    func markerY(_ index: Int) -> CGFloat? {
        optionTop(index).map { $0 + PanelMetrics.optionInset + PanelMetrics.optionTitleLineHeight / 2 }
    }

    /// `Show more`, which an option draws only where its description ran past
    /// two lines. Its band is held open inside the card and the words are drawn
    /// over it, one marker column in.
    var disclosureLeft: CGFloat {
        textLeft + PanelMetrics.optionInset + PanelMetrics.optionHandleWidth
    }

    func disclosureY(_ index: Int) -> CGFloat? {
        guard let top = optionTop(index),
              let body = store.openRowBody,
              body.optionLayouts.indices.contains(index),
              body.optionLayouts[index].canExpand else { return nil }
        return top
            + body.optionLayouts[index].height
            - PanelMetrics.optionInset
            - PanelMetrics.optionDisclosureHeight / 2
    }

    // MARK: The answers

    /// The answer row's middle: it sits on the row's own bottom inset.
    var answerY: CGFloat {
        gutter + geometry.height - 12.5 - PanelMetrics.answerRowHeight / 2
    }

    private var centres: (field: CGFloat, back: CGFloat?, refusal: CGFloat?, affirmative: CGFloat)? {
        store.openAnswerRow.map {
            OpenedSpecimen.answerCentres(
                rowWidth: rowWidth,
                shape: $0,
                showsBack: store.canGoBackAQuestion
            )
        }
    }

    var fieldX: CGFloat? { centres.map { gutter + $0.field } }
    var backX: CGFloat? { centres?.back.map { gutter + $0 } }
    var refusalX: CGFloat? { centres?.refusal.map { gutter + $0 } }
    var affirmativeX: CGFloat? { centres.map { gutter + $0.affirmative } }
}

// MARK: - The card

/// The README's second anatomy: the three shapes a request arrives in, stacked,
/// with every part named.
@MainActor
struct ReadmeApprovalCard: View {
    let staged: ApprovalSpecimens.Staged

    static let padding = ReadmeAnatomyCard.padding
    static let leadingMargin = ReadmeAnatomyCard.leadingMargin
    static let trailingMargin = ReadmeAnatomyCard.trailingMargin
    static let captionGap = ReadmeAnatomyCard.captionGap
    static let sectionGap = ReadmeAnatomyCard.sectionGap
    /// A plate carries labels below it as well as beside it — the answers are
    /// three controls side by side at its foot, and three pins in one column
    /// would land on top of each other.
    static let stackMargin: CGFloat = 46
    /// The second row the middle answer drops to. The three controls are `50`
    /// to `70` pt apart and their labels are `120` to `195` wide, so one row
    /// cannot hold them: the field and the affirmative keep the near row at
    /// either end of it, and whatever stands between them takes the far one.
    static let stackedRowStep = ReadmeAnatomyCard.stackedRowStep

    static func width(_ staged: ApprovalSpecimens.Staged) -> CGFloat {
        let widest = [staged.command, staged.multipleChoice, staged.series]
            .map { OpenRowAnchors(store: $0).plateWidth }
            .max() ?? 0
        return widest + leadingMargin + trailingMargin + padding * 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.sectionGap) {
            figure(
                caption: "A permission request",
                detail: "Grant or refuse what the agent is asking to run.",
                store: staged.command,
                callouts: commandCallouts
            )
            figure(
                caption: "A question, several answers",
                detail: "Tick as many options as apply, then send them together.",
                store: staged.multipleChoice,
                callouts: multipleChoiceCallouts
            )
            figure(
                caption: "A series of questions, one answer each",
                detail: "Answered one at a time, walked with Back and Next, sent once.",
                store: staged.series,
                callouts: seriesCallouts
            )
        }
        .padding(Self.padding)
        .frame(width: Self.width(staged), alignment: .center)
        .background(AnatomyCardStyle.background)
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private func figure(
        caption: String,
        detail: String,
        store: MonitorStore,
        callouts: [AnatomyCallout]
    ) -> some View {
        let anchors = OpenRowAnchors(store: store)
        VStack(alignment: .leading, spacing: Self.captionGap) {
            VStack(alignment: .leading, spacing: 3) {
                Text(caption)
                    .font(AnatomyCardStyle.captionFont)
                    .foregroundStyle(AnatomyCardStyle.caption)
                Text(detail)
                    .font(AnatomyCardStyle.captionDetailFont)
                    .foregroundStyle(AnatomyCardStyle.captionDetail)
            }

            CalloutFigure(
                callouts: callouts,
                specimenSize: CGSize(width: anchors.plateWidth, height: anchors.plateHeight),
                margin: EdgeInsets(
                    top: 0,
                    leading: Self.leadingMargin,
                    bottom: Self.stackMargin + Self.stackedRowStep,
                    trailing: Self.trailingMargin
                )
            ) {
                OpenRowPlate(store: store)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Form 01

    private var commandCallouts: [AnatomyCallout] {
        let a = OpenRowAnchors(store: staged.command)
        var callouts: [AnatomyCallout] = [
            AnatomyCallout(
                id: 1,
                text: "Fold it away again",
                side: .trailing,
                target: CGPoint(x: a.textRight, y: a.captionY),
                stem: 26
            )
        ]
        if let label = a.argumentLabelY(0) {
            callouts.append(
                AnatomyCallout(
                    id: 2,
                    text: "Each argument, labelled",
                    side: .leading,
                    target: CGPoint(x: a.textLeft, y: label),
                    stem: 26
                )
            )
        }
        if let value = a.argumentValueY(0) {
            callouts.append(
                AnatomyCallout(
                    id: 3,
                    text: "What it wants to run",
                    side: .leading,
                    target: CGPoint(x: a.textLeft, y: value),
                    stem: 26
                )
            )
        }
        if let field = a.fieldX {
            callouts.append(
                AnatomyCallout(
                    id: 4,
                    text: "Say what to do instead",
                    side: .below,
                    target: CGPoint(x: field, y: a.answerY),
                    stem: 20
                )
            )
        }
        if let refusal = a.refusalX {
            callouts.append(
                AnatomyCallout(
                    id: 5,
                    text: "Turn it down",
                    side: .below,
                    target: CGPoint(x: refusal, y: a.answerY),
                    stem: 20,
                    drop: -60
                )
            )
        }
        if let affirmative = a.affirmativeX {
            callouts.append(
                AnatomyCallout(
                    id: 6,
                    text: "Approve — and what ⏎ does",
                    side: .below,
                    target: CGPoint(x: affirmative, y: a.answerY),
                    stem: 20 + Self.stackedRowStep
                )
            )
        }
        return callouts
    }

    // MARK: Form 03, one question

    private var multipleChoiceCallouts: [AnatomyCallout] {
        let a = OpenRowAnchors(store: staged.multipleChoice)
        var callouts: [AnatomyCallout] = [
            AnatomyCallout(
                id: 1,
                text: "Its header, and where it\nstands in the set",
                side: .trailing,
                target: CGPoint(x: a.textRight, y: a.captionY),
                stem: 26
            ),
            AnatomyCallout(
                id: 2,
                text: "What is being asked",
                side: .leading,
                target: CGPoint(x: a.textLeft, y: a.questionY),
                stem: 26
            )
        ]
        if let marker = a.markerY(0) {
            callouts.append(
                AnatomyCallout(
                    id: 3,
                    text: "Tick as many as apply",
                    side: .leading,
                    target: CGPoint(x: a.markerLeft, y: marker),
                    stem: 26
                )
            )
        }
        if let disclosure = a.disclosureY(0) {
            callouts.append(
                AnatomyCallout(
                    id: 4,
                    text: "A long description folds",
                    side: .leading,
                    // Its words start one marker column inside the card, so the
                    // stem has to carry the label back out past the plate.
                    target: CGPoint(x: a.disclosureLeft, y: disclosure),
                    stem: a.disclosureLeft + 14
                )
            )
        }
        if let marker = a.markerY(2) {
            callouts.append(
                AnatomyCallout(
                    id: 5,
                    text: "The whole card is the target",
                    side: .trailing,
                    target: CGPoint(x: a.textRight, y: marker),
                    stem: 26
                )
            )
        }
        if let field = a.fieldX {
            callouts.append(
                AnatomyCallout(
                    id: 6,
                    text: "Or answer in your own words",
                    side: .below,
                    target: CGPoint(x: field, y: a.answerY),
                    stem: 20
                )
            )
        }
        if let affirmative = a.affirmativeX {
            callouts.append(
                AnatomyCallout(
                    id: 7,
                    text: "Submit — the last of the set",
                    side: .below,
                    target: CGPoint(x: affirmative, y: a.answerY),
                    stem: 20
                )
            )
        }
        return callouts
    }

    // MARK: Form 03, a set

    private var seriesCallouts: [AnatomyCallout] {
        let a = OpenRowAnchors(store: staged.series)
        var callouts: [AnatomyCallout] = [
            AnatomyCallout(
                id: 1,
                text: "The second of three",
                side: .trailing,
                target: CGPoint(x: a.textRight, y: a.captionY),
                stem: 26
            ),
            AnatomyCallout(
                id: 2,
                text: "This question's own words",
                side: .leading,
                target: CGPoint(x: a.textLeft, y: a.questionY),
                stem: 26
            )
        ]
        if let marker = a.markerY(0) {
            callouts.append(
                AnatomyCallout(
                    id: 3,
                    text: "One answer, not several",
                    side: .leading,
                    target: CGPoint(x: a.markerLeft, y: marker),
                    stem: 26
                )
            )
        }
        if let field = a.fieldX {
            callouts.append(
                AnatomyCallout(
                    id: 4,
                    text: "Your own words instead",
                    side: .below,
                    target: CGPoint(x: field, y: a.answerY),
                    stem: 20
                )
            )
        }
        if let back = a.backX {
            callouts.append(
                AnatomyCallout(
                    id: 5,
                    text: "Back, keeping every answer",
                    side: .below,
                    target: CGPoint(x: back, y: a.answerY),
                    stem: 20,
                    drop: -62
                )
            )
        }
        if let affirmative = a.affirmativeX {
            callouts.append(
                AnatomyCallout(
                    id: 6,
                    text: "Next — Submit on the last one",
                    side: .below,
                    target: CGPoint(x: affirmative, y: a.answerY),
                    stem: 20 + Self.stackedRowStep
                )
            )
        }
        return callouts
    }
}
