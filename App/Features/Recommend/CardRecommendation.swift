import Foundation

struct CardRecommendation: Identifiable {
    let card: BankCard
    let offers: [SuggestedBenefit]
    let baseBenefit: String?
    let caveats: [String]

    var id: UUID { card.id }
    var knownMatches: Int { offers.reduce(0) { $0 + $1.matchedConditions.count } }
    var confirmationCount: Int { topOffer?.confirmationNeeded.count ?? 0 }
    var topOffer: SuggestedBenefit? { offers.first }
    var bestRateBps: Int { offers.map(\.rateBps).max() ?? 0 }
    var bestFixedRewardCents: Int64 { offers.map(\.fixedRewardCents).max() ?? 0 }
    var isConditional: Bool { !(topOffer?.keyMissingConditions.isEmpty ?? true) }
    var rankingLabel: String {
        guard topOffer != nil else { return "基础回赠参考" }
        return isConditional ? "需补充信息" : "可优先比较"
    }
    var rankingSummary: String {
        guard let topOffer else { return baseBenefit ?? "暂无公开活动参考。" }
        let value = topOffer.rateBps > 0 || topOffer.fixedRewardCents > 0
            ? "公开权益参考：" + topOffer.headline
            : "条件较匹配；请查看适用条款。"
        guard !topOffer.keyMissingConditions.isEmpty else { return value }
        return value + "；先确认" + topOffer.keyMissingConditions.joined(separator: "、") + "。"
    }
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
    /// Ranking facts are the published headline value, never a settlement estimate.
    let headline: String
    let rateBps: Int
    let fixedRewardCents: Int64
    let capCents: Int64
    /// User-supplied or availability facts that prevent calling this a confirmed match.
    let keyMissingConditions: [String]

    /// Legacy tests and personal rules. Official suggestions have no editable
    /// RewardRule and must use the projected fields above.
    var rule: RewardRule { legacyRule! }
}
