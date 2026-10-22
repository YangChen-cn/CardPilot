import Foundation

/// Value snapshot; contains no ModelContext or live SwiftData relationship.
struct TransactionSyncData: Codable, Equatable, Sendable {
    var merchant: String
    var amountCents: Int64
    var currency: String
    var exchangeRate: String
    var category: String
    var paymentMethod: String
    var date: Date
    var createdAt: Date
    var notes: String
    var source: String
    var externalID: String
    var channel: String
    var isOverseas: Bool
    var isRewardEligible: Bool
    var region: String?

    init(_ model: SpendTransaction) {
        merchant = model.merchant
        amountCents = model.amountCents
        currency = model.currency
        exchangeRate = model.exchangeRate
        category = model.category
        paymentMethod = model.paymentMethod
        date = model.date
        createdAt = model.createdAt
        notes = model.notes
        source = model.source
        externalID = model.externalID
        channel = model.channel
        isOverseas = model.isOverseas
        isRewardEligible = model.isRewardEligible
        region = model.region
    }

    func apply(to model: SpendTransaction) {
        model.merchant = merchant
        model.amountCents = amountCents
        model.currency = currency
        model.exchangeRate = exchangeRate
        model.category = category
        model.paymentMethod = paymentMethod
        model.date = date
        model.createdAt = createdAt
        model.notes = notes
        model.source = source
        model.externalID = externalID
        model.channel = channel
        model.isOverseas = isOverseas
        model.isRewardEligible = isRewardEligible
        model.region = region ?? ""
    }
}
