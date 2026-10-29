import SwiftUI

/// The compact list changes presentation only; navigation and ordering stay in the card item.
struct CompactWalletCardRow: View {
    let card: BankCard
    var transition: Namespace.ID?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 14) {
            if !typeSize.isAccessibilitySize {
                CardFaceFrame {
                    CardArtwork(card: card, compact: true)
                }
                .frame(width: 76)
                .cardTransitionSource(id: card.id, in: transition)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(card.name).font(.body).bold().foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text([card.bank, card.network, card.lastFour.isEmpty ? nil : card.lastFour,
                      card.isArchived ? "已归档" : card.kindLabel]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .contentShape(.rect)
    }
}
