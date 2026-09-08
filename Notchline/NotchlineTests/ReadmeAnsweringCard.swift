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
    /// Between the two plates. They are the panel's own width, and the two of
    /// them plus this is what sets ``ReadmeAnatomyCard/pageWidth``.
    static let plateGap: CGFloat = 32
    static let titleGap = ReadmeAnatomyCard.captionGap

    private var plates: [MonitorStore] { [staged.command, staged.series] }

    /// The page both figures share, which this one is what sets.
    static func width(_ staged: ApprovalSpecimens.Staged) -> CGFloat {
        ReadmeAnatomyCard.pageWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.titleGap) {
            // The anatomy figure's own caption pair, at the same sizes: the two
            // figures are siblings on the README, and a heading a couple of
            // points larger here would have made this one look like the parent
            // of the other.
            VStack(alignment: .leading, spacing: 3) {
                Text("Answering in the notch")
                    .font(AnatomyCardStyle.captionFont)
                    .foregroundStyle(AnatomyCardStyle.caption)
                Text("A request opens in the row that reported it, and is answered there.")
                    .font(AnatomyCardStyle.captionDetailFont)
                    .foregroundStyle(AnatomyCardStyle.captionDetail)
            }

            // Hung from one line. Both plates are a panel opened at the top of
            // the screen, so their top edges are the edge they actually share;
            // centring them slid each one half of the height difference away
            // from that line and read as two panels at two heights. The
            // shorter plate's difference falls under it as empty page, which
            // is the honest shape of one row being taller than the other.
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
