import SwiftUI

struct CardDetailHeader: View {
    let card: BankCard
    @State private var wide = false
    @Environment(\.dynamicTypeSize) private var typeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var phoneLayout: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if wide && !typeSize.isAccessibilitySize {
                HStack(alignment: .center, spacing: 32) {
                    WalletCardFace(card: card)
                        .frame(width: 380)
                    CardDetailOverview(card: card)
                }
            } else {
                VStack(alignment: .leading, spacing: phoneLayout ? 16 : 24) {
                    WalletCardFace(card: card)
                        .frame(maxWidth: phoneLayout ? 260 : 460)
                        .frame(maxWidth: .infinity)
                    CardDetailOverview(card: card, compact: phoneLayout)
                }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 700 } action: { wide = $0 }
    }
}
