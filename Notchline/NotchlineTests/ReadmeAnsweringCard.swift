// The README's second figure: the two shapes a request opens in, unlabelled, side by side.
import AppKit
import SwiftUI

@testable import Notchline

/// One open row on the panel's ground, inside the panel's gutter.
@MainActor
struct OpenRowPlate: View {
    let store: MonitorStore

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

@MainActor
struct ReadmeAnsweringCard: View {
    let staged: ApprovalSpecimens.Staged

    static let padding = ReadmeAnatomyCard.padding
    /// Two panel-wide plates plus this gap set ``ReadmeAnatomyCard/pageWidth``.
    static let plateGap: CGFloat = 32
    static let titleGap = ReadmeAnatomyCard.captionGap

    private var plates: [MonitorStore] { [staged.command, staged.series] }

    static func width(_ staged: ApprovalSpecimens.Staged) -> CGFloat {
        ReadmeAnatomyCard.pageWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.titleGap) {
            // The anatomy figure's caption sizes: the two figures are siblings.
            VStack(alignment: .leading, spacing: 3) {
                Text("Answering in the notch")
                    .font(AnatomyCardStyle.captionFont)
                    .foregroundStyle(AnatomyCardStyle.caption)
                Text("A request opens in the row that reported it, and is answered there.")
                    .font(AnatomyCardStyle.captionDetailFont)
                    .foregroundStyle(AnatomyCardStyle.captionDetail)
            }

            // Top-aligned: both plates are panels opened at the top of the screen.
            HStack(alignment: .top, spacing: Self.plateGap) {
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
