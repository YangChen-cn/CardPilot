import SwiftUI

struct WalletCardDestination: View {
    let card: BankCard
    let transition: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        #if os(iOS)
        if reduceMotion {
            CardDetailView(card: card)
        } else {
            CardDetailView(card: card).navigationTransition(.zoom(sourceID: card.id, in: transition))
        }
        #else
        CardDetailView(card: card)
        #endif
    }
}
