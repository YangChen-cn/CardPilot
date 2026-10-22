import Foundation
import SwiftData

/// Official, published card details. When a product has a verified base rate we
/// use the current catalog value; otherwise the rate is intentionally unknown.
struct CardOfficialDetails: Equatable, Sendable {
    var baseRateVerified = true
    var annualFeeNote = ""
    var caveats = ""
    var sourceURL = ""
    var verifiedOn = ""
}

@MainActor enum PricingStore {
    /// Resolves "current official product + explicit personal override".
    /// BankCard's own rate fields are only a compatibility snapshot and are not
    /// authoritative for a card that belongs to the public catalog.
    static func current(_ card: BankCard, applyingOverride: Bool = true, library: BankLibrary? = nil) -> CardPricing {
        var value = CardPricing(card)
        value.statementDay = card.statementDay
        let library = library ?? (try? BankLibrary.load())
        if let library, let product = library.product(id: card.catalogID) {
            let catalog = product.catalog
            value.baseRateBps = product.baseRewardVerified ? Int(Money.cents(catalog.baseRatePercent ?? 0)) : 0
            value.foreignFeeBps = Int(Money.cents(catalog.foreignFeePercent ?? 0))
            value.overseasHKDFeeBps = Int(Money.cents(catalog.overseasHKDFeePercent ?? 0))
            value.excludesWallets = catalog.excludesWallets ?? false
        }
        if let context = card.modelContext {
            value.terms = try? DocumentStore.load(CardTerms.self, key: "cardTerms:" + card.syncKey, in: context)
            value.creditLimitCents = try? FinanceStore.snapshot(context: context).groups.first(where: { $0.cardKeys.contains(card.syncKey) })?.limitCents
            if applyingOverride, let override = try? DocumentStore.load(CardPricing.self, key: "cardOverride:" + card.syncKey, in: context) {
                let fields = override.overriddenFields
                if fields == nil || fields?.contains("base") == true { value.baseRateBps = override.baseRateBps }
                if fields == nil || fields?.contains("foreign") == true { value.foreignFeeBps = override.foreignFeeBps }
                if fields == nil || fields?.contains("overseas") == true { value.overseasHKDFeeBps = override.overseasHKDFeeBps }
                if fields == nil || fields?.contains("wallets") == true { value.excludesWallets = override.excludesWallets }
                value.terms = override.terms ?? value.terms
            }
        }
        return value
    }

    static func details(_ card: BankCard, library: BankLibrary? = nil) -> CardOfficialDetails {
        let library = library ?? (try? BankLibrary.load())
        guard let library, let product = library.product(id: card.catalogID) else {
            return CardOfficialDetails(annualFeeNote: card.annualFeeNote, caveats: card.caveats,
                                       sourceURL: card.sourceURL, verifiedOn: card.verifiedOn)
        }
        return CardOfficialDetails(baseRateVerified: product.baseRewardVerified,
                                   annualFeeNote: product.catalog.annualFeeNote ?? "",
                                   caveats: product.catalog.caveats ?? "",
                                   sourceURL: product.catalog.sourceURL,
                                   verifiedOn: product.catalog.verifiedOn)
    }
}
