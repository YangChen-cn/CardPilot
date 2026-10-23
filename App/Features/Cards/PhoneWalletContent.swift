import SwiftUI

#if os(iOS)
/// Only presentation is phone-specific. Ordering, destinations and mutations
/// continue to use the same card identities and existing services.
struct PhoneWalletContent: View {
    let cards: [BankCard]
    let presentation: PhoneCardPresentation
    @Binding var selectedKey: String?
    let transition: Namespace.ID
    let benefits: [BenefitInfo]
    let onSelect: (BankCard) -> Void
    let onRecord: (BankCard) -> Void
    let onDrop: (String, String, Bool) -> Bool
    let onMoveToStart: (BankCard) -> Bool
    let onMoveToEnd: (BankCard) -> Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedCard: BankCard? {
        cards.first { $0.syncKey == selectedKey } ?? cards.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PilotTheme.phoneSectionSpacing) {
            if presentation == .featured, let card = selectedCard {
                PhoneWalletCarousel(cards: cards, selectedKey: $selectedKey, transition: transition)
                PhoneWalletSelection(card: card, benefits: benefits, transition: transition,
                                     onRecord: { onRecord(card) })
            }
            VStack(alignment: .leading, spacing: 12) {
                if presentation == .featured {
                    Text("全部卡片").font(.headline)
                }
                LazyVStack(spacing: 0) {
                    ForEach(cards) { card in
                        if card.syncKey != cards.first?.syncKey {
                            Divider().padding(.leading, 100)
                        }
                        CompactWalletCardItem(card: card,
                                              isSelected: presentation == .featured && card.syncKey == selectedCard?.syncKey,
                                              onSelect: presentation == .featured ? { onSelect(card) } : nil,
                                              onDrop: { source, after in onDrop(source, card.syncKey, after) },
                                              onMoveToStart: { onMoveToStart(card) },
                                              onMoveToEnd: { onMoveToEnd(card) })
                    }
                }
                .background(PilotTheme.surface, in: .rect(cornerRadius: PilotTheme.radius))
                .animation(reduceMotion ? nil : .snappy, value: cards.map(\.syncKey))
            }
        }
        .onChange(of: cards.map(\.syncKey), initial: true) { _, keys in
            if selectedKey == nil || !keys.contains(selectedKey ?? "") {
                selectedKey = keys.first
            }
        }
    }
}
#endif
