import Foundation
import SwiftData

/// One-time cleanup for cards that stored a copy of an official card face.
/// It only clears the copy when the bytes match the current official asset (or
/// a known legacy GO face). Anything uncertain stays as personal artwork.
@MainActor enum LibraryArtworkUpdates {
    @discardableResult static func apply(in context: ModelContext) throws -> Int {
        let cards = try context.fetch(FetchDescriptor<BankCard>())
        let library = try? BankLibrary.load()
        let legacyGo = ["bochk-go.png", "bochk-go-cf.png"].compactMap { BankLibrary.imageData(resource: $0) }
        var changed: [BankCard] = []

        for card in cards where card.imageData != nil {
            guard !card.catalogID.isEmpty else { continue }
            let matchesCurrent = library?.product(id: card.catalogID)
                .flatMap { $0.artwork.bundledData() }
                .map { $0 == card.imageData } ?? false
            let isLegacyGO = card.catalogID == "bochk.go.diamond"
                && legacyGo.contains(card.imageData ?? Data())
            if matchesCurrent || isLegacyGO {
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
