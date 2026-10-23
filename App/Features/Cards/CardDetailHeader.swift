import SwiftUI

struct CardDetailHeader: View {
    let card: BankCard
    @State private var wide = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if wide && !typeSize.isAccessibilitySize {
                HStack(alignment: .center, spacing: 32) {
                    WalletCardFace(card: card)
                        .frame(width: 380)
                    CardDetailOverview(card: card)
                }
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    WalletCardFace(card: card)
                        .frame(maxWidth: 460)
                        .frame(maxWidth: .infinity)
                    CardDetailOverview(card: card)
                }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 700 } action: { wide = $0 }
    }
}
