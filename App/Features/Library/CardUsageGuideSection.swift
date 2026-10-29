import SwiftUI

/// One entry per card, shown both in the library and directly in the wallet.
/// The preview opens the complete card-level guide without first navigating
/// through the detail page or an individual promotion.
struct CardUsageGuideSection: View {
    let guide: CardUsageGuide
    let productName: String
    var compact = false
    var showsProductName = false
    @State private var showingGuide = false

    var body: some View {
        Button { showingGuide = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("推荐用法", systemImage: "lightbulb")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PilotTheme.accent)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                if showsProductName {
                    Text(productName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Text(guide.summary)
                    .font(compact ? .subheadline : .body)
                    .foregroundStyle(.primary)
                    .lineLimit(compact ? 2 : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: PilotTheme.minimumTouchTarget, alignment: .leading)
            .contentShape(.rect)
            .pilotPanel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(productName + "的推荐用法：" + guide.summary)
        .accessibilityHint("直接打开这张卡的完整用卡指南")
        .sheet(isPresented: $showingGuide) {
            CardUsageGuideView(guide: guide, productName: productName)
        }
    }
}

/// Resolve the current catalog's guide for a card already added to the wallet.
/// The catalog revision dependency makes an updated remote guide visible
/// without baking the original editorial content into personal SwiftData.
struct CardUsageGuideForCard: View {
    let card: BankCard
    var compact = false
    var showsProductName = false
    @Environment(CatalogRepository.self) private var catalog

    var body: some View {
        let _ = catalog.revision
        if !card.catalogID.isEmpty,
           let product = (try? BankLibrary.load())?.product(id: card.catalogID),
           let guide = product.usageGuide {
            CardUsageGuideSection(guide: guide, productName: product.catalog.name,
                                  compact: compact, showsProductName: showsProductName)
        }
    }
}
