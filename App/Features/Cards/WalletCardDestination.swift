import SwiftUI

struct WalletCardDestination: View {
    let card: BankCard
    let transition: Namespace.ID

    var body: some View {
        CardDetailView(card: card)
            .pilotZoomTransition(sourceID: card.id, in: transition)
    }
}
