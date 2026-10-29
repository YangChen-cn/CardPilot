import SwiftUI

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
