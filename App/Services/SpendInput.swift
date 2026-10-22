import Foundation

/// Plain recorded spending facts for currency totals and consumption charts.
struct SpendInput: Sendable {
    var id = UUID()
    var cardID: UUID?
    var merchant: String
    var amountCents: Int64
    var currency: String
    var exchangeRate: String
    var category: String
    var paymentMethod: String
    var date: Date
    var createdAt: Date = .now
    var channel: String = "unknown"
    var isOverseas: Bool = false
    var isRewardEligible: Bool = true
    var region: String = ""
    var hasHKDValuation: Bool { currency == "HKD" || (!exchangeRate.isEmpty && (Decimal(string: exchangeRate) ?? 0) > 0) }
    var hkdCents: Int64 { Money.convert(amountCents, rate: currency == "HKD" ? "1" : exchangeRate) }

    init(cardID: UUID?, merchant: String, amountCents: Int64, currency: String = "HKD",
         exchangeRate: String = "", category: String = "其他", paymentMethod: String = "待确认", date: Date = .now) {
        self.cardID = cardID; self.merchant = merchant; self.amountCents = amountCents
        self.currency = currency; self.exchangeRate = exchangeRate; self.category = category
        self.paymentMethod = paymentMethod; self.date = date
    }

    init(_ transaction: SpendTransaction) {
        id = transaction.id; cardID = transaction.card?.id; merchant = transaction.merchant
        amountCents = transaction.amountCents; currency = transaction.currency
        exchangeRate = transaction.exchangeRate; category = transaction.category
        paymentMethod = transaction.paymentMethod; date = transaction.date; createdAt = transaction.createdAt
        channel = transaction.channel; isOverseas = transaction.isOverseas
        isRewardEligible = transaction.isRewardEligible
        region = transaction.region
    }
}
