import Foundation

/// Value snapshot; contains no ModelContext or live SwiftData relationship.
struct RuleSyncData: Codable, Equatable, Sendable {
    var profileRevision: Date? = nil
    var name: String
    var kind: String
    var rateBps: Int
    var capCents: Int64
    var capPeriod: String
    var thresholdCents: Int64
    var bonusCents: Int64
    var minimumCents: Int64
    var category: String
    var currency: String
    var paymentMethod: String
    var merchantKeywords: String
    var startsOn: Date
    var endsOn: Date
    var isEnabled: Bool
    var notes: String
    var externalID: String
    var sourceURL: String
    var verifiedOn: String
    var sharedCapGroup: String
    var monthlyPhysicalThresholdCents: Int64
    var channelCondition: String

    init(_ model: RewardRule) {
        name = model.name
        kind = model.kind
        rateBps = model.rateBps
        capCents = model.capCents
        capPeriod = model.capPeriod
        thresholdCents = model.thresholdCents
        bonusCents = model.bonusCents
        minimumCents = model.minimumCents
        category = model.category
        currency = model.currency
        paymentMethod = model.paymentMethod
        merchantKeywords = model.merchantKeywords
        startsOn = model.startsOn
        endsOn = model.endsOn
        isEnabled = model.isEnabled
        notes = model.notes
        externalID = model.externalID
        sourceURL = model.sourceURL
        verifiedOn = model.verifiedOn
        sharedCapGroup = model.sharedCapGroup
        monthlyPhysicalThresholdCents = model.monthlyPhysicalThresholdCents
        channelCondition = model.channelCondition
    }

    func apply(to model: RewardRule) {
        model.name = name
        model.kind = kind
        model.rateBps = rateBps
        model.capCents = capCents
        model.capPeriod = capPeriod
        model.thresholdCents = thresholdCents
        model.bonusCents = bonusCents
        model.minimumCents = minimumCents
        model.category = category
        model.currency = currency
        model.paymentMethod = paymentMethod
        model.merchantKeywords = merchantKeywords
        model.startsOn = startsOn
        model.endsOn = endsOn
        model.isEnabled = isEnabled
        model.notes = notes
        model.externalID = externalID
        model.sourceURL = sourceURL
        model.verifiedOn = verifiedOn
        model.sharedCapGroup = sharedCapGroup
        model.monthlyPhysicalThresholdCents = monthlyPhysicalThresholdCents
        model.channelCondition = channelCondition
    }
}
