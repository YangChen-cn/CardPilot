import Foundation

struct CardRecommendation: Identifiable {
    let card: BankCard
    let offers: [SuggestedBenefit]
    let baseBenefit: String?
    let caveats: [String]
    var id: UUID { card.id }
    var knownMatches: Int { offers.reduce(0) { $0 + $1.matchedConditions.count } }
}

struct SuggestedBenefit: Identifiable {
    let id: UUID
    let title: String
    let note: String
    let sourceURL: String
    let endsOn: Date
    let hasKnownPeriod: Bool
    let hasKnownStart: Bool
    let hasKnownEnd: Bool
    let legacyRule: RewardRule?
    let matchedConditions: [String]
    let confirmationNeeded: [String]

    /// Legacy tests and personal rules. Official suggestions have no editable
    /// RewardRule and must use the projected fields above.
    var rule: RewardRule { legacyRule! }
}
