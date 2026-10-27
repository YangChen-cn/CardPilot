import Foundation
import SwiftData

/// Keeps offline official artwork for held cards. It never inspects or changes
/// personal image data; artwork ownership is an explicit saved choice.
@MainActor enum LibraryArtworkUpdates {
    static func retainHeldArtwork(in context: ModelContext) async {
        guard let cards = try? context.fetch(FetchDescriptor<BankCard>()),
              let library = try? BankLibrary.load() else { return }
        let assets = cards.compactMap { card -> (String, CatalogAsset)? in
            guard let product = library.product(id: card.catalogID), let artwork = product.artwork else { return nil }
            return (card.catalogID, artwork)
        }
        for (catalogID, artwork) in assets {
            await CatalogAssetStore.shared.retain(artwork, forCatalogID: catalogID)
        }
    }
}
