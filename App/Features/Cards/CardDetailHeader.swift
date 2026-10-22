import SwiftUI

struct CardDetailHeader: View {
    let card: BankCard
    @State private var wide = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if wide && !typeSize.isAccessibilitySize {
                HStack(alignment: .center, spacing: 32) {
                    CardArtwork(card: card).frame(width: 340, height: 270)
                    CardDetailOverview(card: card)
                }
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    CardArtwork(card: card)
                        .frame(maxWidth: 400)
                        .frame(height: typeSize.isAccessibilitySize && card.imageData == nil ? nil : 260)
                        .frame(maxWidth: .infinity)
                    CardDetailOverview(card: card)
                }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 700 } action: { wide = $0 }
    }
}
