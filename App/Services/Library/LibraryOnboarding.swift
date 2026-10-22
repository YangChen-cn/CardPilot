import Foundation
import SwiftData

@MainActor enum LibraryOnboarding {
    /// Adds a personal card instance. Official products and offers live only in
    /// the read-only catalog cache; no RewardRule is copied into SwiftData.
    static func add(product: CardProduct, in context: ModelContext, commit: Bool = true) throws -> BankCard {
        let id = product.id
        if let existing = try context.fetch(FetchDescriptor<BankCard>(predicate: #Predicate { $0.catalogID == id })).first { return existing }
        let catalog = product.catalog
        let card = BankCard(bank: catalog.bank, name: catalog.name, network: catalog.network,
                            kind: catalog.kind ?? "信用卡")
        card.catalogID = id
        card.sourceURL = catalog.sourceURL
        card.verifiedOn = catalog.verifiedOn
        card.baseRateBps = product.baseRewardVerified ? Int(Money.cents(catalog.baseRatePercent ?? 0)) : 0
        card.foreignFeeBps = Int(Money.cents(catalog.foreignFeePercent ?? 0))
        card.overseasHKDFeeBps = Int(Money.cents(catalog.overseasHKDFeePercent ?? 0))
        card.excludesWallets = catalog.excludesWallets ?? false
        card.annualFeeNote = catalog.annualFeeNote ?? ""
        card.caveats = catalog.caveats ?? ""
        card.imageData = nil
        Task { await CatalogAssetStore.shared.retain(product.artwork, forCatalogID: product.id) }
        if commit { try Persistence.save(context) { context.insert(card) } }
        else { context.insert(card) }
        return card
    }
}
