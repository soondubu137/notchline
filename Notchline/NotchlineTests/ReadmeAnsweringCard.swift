// The README's second figure: the two shapes a request opens in, side by side.
//
// **A picture rather than a diagram.** Nothing on it is labelled: the first
// figure names the parts of the surface, and this one only has to show that a
// request opens in place and is answered there. So it is two `OpenRow`s on the
// panel's own ground, at the width and the height the store composes for each,
// and a title.
import AppKit
import SwiftUI

@testable import Notchline

/// One open row on the panel's ground: the row at the width the viewport gives
/// it, with the panel's own gutter around it.
@MainActor
struct OpenRowPlate: View {
    let store: MonitorStore

    /// The panel's own inset around a row block.
    static var gutter: CGFloat { PanelMetrics.sessionRowGutter }

    var height: CGFloat { store.openRowHeight ?? PanelMetrics.sessionRowHeight }

    var size: CGSize {
        CGSize(
            width: store.currentPanelSize.width,
            height: height + Self.gutter * 2
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
                    .padding(Self.gutter)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The two shapes, on one white page, under one title.
@MainActor
struct ReadmeAnsweringCard: View {
    let staged: ApprovalSpecimens.Staged

    static let padding = ReadmeAnatomyCard.padding
    /// Between the two plates. They are the panel's own width, so the page is
    /// wide and the gutter between them does not need to be.
    static let plateGap: CGFloat = 32
    static let titleGap: CGFloat = 28

    static let titleFont = Font.system(size: 17, weight: .semibold)

    private var plates: [MonitorStore] { [staged.command, staged.series] }

    static func width(_ staged: ApprovalSpecimens.Staged) -> CGFloat {
        let card = ReadmeAnsweringCard(staged: staged)
        let widths = card.plates.map { OpenRowPlate(store: $0).size.width }
        return widths.reduce(0, +)
            + plateGap * CGFloat(max(widths.count - 1, 0))
            + padding * 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.titleGap) {
            Text("Answering in the notch")
                .font(Self.titleFont)
                .foregroundStyle(AnatomyCardStyle.caption)

            // Centred against each other rather than hung from one line. Two
            // requests are never this size at once anyway — a panel draws one
            // open row — so the shared edge is a composition rather than a
            // claim, and top-aligning left the whole of the shorter plate's
            // difference as one empty block under it.
            HStack(alignment: .center, spacing: Self.plateGap) {
                ForEach(Array(plates.enumerated()), id: \.offset) { _, store in
                    OpenRowPlate(store: store)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(Self.padding)
        .frame(width: Self.width(staged), alignment: .center)
        .background(AnatomyCardStyle.background)
        .environment(\.colorScheme, .light)
    }
}
