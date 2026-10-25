import Foundation
import SwiftData

/// One-time cleanup for cards that stored a copy of an official card face.
/// It clears the copy only when the bytes match the current official asset, a
/// historical official asset for the same catalog product, or a known legacy GO
/// face. Anything uncertain stays as personal artwork.
@MainActor enum LibraryArtworkUpdates {
    @discardableResult static func apply(
        in context: ModelContext,
        legacyFingerprints: [String: Set<String>] = LegacyArtworkFingerprints.byCatalogID
    ) throws -> Int {
        let cards = try context.fetch(FetchDescriptor<BankCard>())
        let library = try? BankLibrary.load()
        let legacyGo = ["bochk-go.png", "bochk-go-cf.png"].compactMap { BankLibrary.imageData(resource: $0) }
        var changed: [BankCard] = []

        let retained = cards.compactMap { card -> (String, CatalogAsset)? in
            guard !card.catalogID.isEmpty, let product = library?.product(id: card.catalogID) else { return nil }
            return (card.catalogID, product.artwork)
        }
        if !retained.isEmpty {
            Task {
                for (catalogID, artwork) in retained {
                    await CatalogAssetStore.shared.retain(artwork, forCatalogID: catalogID)
                }
            }
        }

        for card in cards where card.imageData != nil {
            guard !card.catalogID.isEmpty else { continue }
            let imageFingerprint = card.imageData.flatMap(ArtworkFingerprint.of)
            let currentFingerprint = library?.product(id: card.catalogID)
                .flatMap { $0.artwork.bundledData() }
                .flatMap(ArtworkFingerprint.of)
            let matchesCurrent = imageFingerprint != nil && imageFingerprint == currentFingerprint
            let isLegacyGO = card.catalogID == "bochk.go.diamond"
                && legacyGo.contains(card.imageData ?? Data())
            let isLegacyOfficial = imageFingerprint.map {
                legacyFingerprints[card.catalogID]?.contains($0) ?? false
            } ?? false
            if matchesCurrent || isLegacyGO || isLegacyOfficial {
                card.imageData = nil
                changed.append(card)
            }
        }

        guard !changed.isEmpty else { return 0 }
        try Persistence.save(context) {
            for card in changed { card.modifiedAt = .now }
        }
        return changed.count
    }
}
