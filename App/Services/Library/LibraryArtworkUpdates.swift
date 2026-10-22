import Foundation
import SwiftData

/// Replace only the exact bundled composite artwork used by older releases.
/// User photographs, custom artwork, identity and financial data stay unchanged.
@MainActor enum LibraryArtworkUpdates {
    @discardableResult static func apply(in context: ModelContext) throws -> Int {
        let productID = "bochk.go.diamond"
        let cards = try context.fetch(FetchDescriptor<BankCard>(predicate: #Predicate { $0.catalogID == productID }))
        let legacy = ["bochk-go.png", "bochk-go-cf.png"].compactMap { BankLibrary.imageData(resource: $0) }
        let affected = cards.filter { card in card.imageData.map { legacy.contains($0) } ?? false }
        guard !affected.isEmpty else { return 0 }
        guard let image = BankLibrary.imageData(resource: "bochk-go-diamond.png") else {
            throw PilotError.invalid("暂时无法更新银行卡面，请重新打开 App。")
        }
        try CatalogImporter.validateImage(image)
        try Persistence.save(context) {
            for card in affected {
                card.imageData = image
                card.imageURL = "https://www.bochk.com/creditcard/images/cardface/301_DD_0955_00012.png"
                card.modifiedAt = .now
            }
        }
        return affected.count
    }
}
