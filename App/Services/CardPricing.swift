import Foundation

struct CardPricing: Codable, Equatable, Sendable {
    var baseRateBps: Int
    var foreignFeeBps: Int
    var overseasHKDFeeBps: Int
    var excludesWallets: Bool
    var terms: CardTerms?
    var statementDay: Int?
    var creditLimitCents: Int64?
    /// Nil means an old-style override that applies to every rate field.
    var overriddenFields: Set<String>?
    init(_ card: BankCard) {
        baseRateBps = card.baseRateBps; foreignFeeBps = card.foreignFeeBps
        overseasHKDFeeBps = card.overseasHKDFeeBps; excludesWallets = card.excludesWallets
    }

    func overrideFields(comparedTo official: CardPricing) -> Set<String> {
        var fields = Set<String>()
        if baseRateBps != official.baseRateBps { fields.insert("base") }
        if foreignFeeBps != official.foreignFeeBps { fields.insert("foreign") }
        if overseasHKDFeeBps != official.overseasHKDFeeBps { fields.insert("overseas") }
        if excludesWallets != official.excludesWallets { fields.insert("wallets") }
        return fields
    }

    func sameRates(as other: CardPricing) -> Bool {
        baseRateBps == other.baseRateBps && foreignFeeBps == other.foreignFeeBps
            && overseasHKDFeeBps == other.overseasHKDFeeBps && excludesWallets == other.excludesWallets
    }
}
