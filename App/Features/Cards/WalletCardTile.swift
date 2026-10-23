import SwiftUI
import SwiftData

struct WalletCardTile: View {
    let card: BankCard
    @Environment(\.modelContext) private var context
    @Environment(CatalogRepository.self) private var catalog
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var isHovered = false

    private var isCompact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        let _ = catalog.revision
        let benefits = OfferStore.offers(for: card, context: context).filter {
            !$0.isHidden && !$0.isArchived && !$0.isEnded && !$0.isHistorical
        }
        let pricing = PricingStore.current(card)
        let baseText = pricing.baseRateBps > 0 ? Money.percent(pricing.baseRateBps) + " 基础权益" : nil
        VStack(alignment: .leading, spacing: isCompact ? 14 : 18) {
            WalletCardFace(card: card)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(card.name).font(.headline).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: isCompact)
                    if !isCompact {
                        Text(card.kindLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(card.isDebitCard ? PilotTheme.accent : .secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                Text(card.bank + " · " + card.network + (card.lastFour.isEmpty ? "" : " · " + card.lastFour))
                    .font(.subheadline).foregroundStyle(.secondary)
                if isCompact {
                    Text(card.isArchived ? card.kindLabel + " · 已归档" :
                            [card.kindLabel, baseText, "\(benefits.count) 项权益"].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if card.isArchived {
                    Label("已归档", systemImage: "archivebox").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        if let baseText {
                            Text(baseText).foregroundStyle(.secondary)
                        }
                        Text("\(benefits.count) 项权益").foregroundStyle(.secondary)
                    }.font(.caption)
                }
            }
        }
        .padding(isCompact ? 0 : PilotTheme.spacing)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(isHovered ? PilotTheme.surface : .clear, in: .rect(cornerRadius: PilotTheme.radius + 4))
        .contentShape(.rect(cornerRadius: PilotTheme.radius + 4))
        .onHover { isHovered = $0 }
    }
}
