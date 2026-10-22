import Foundation
import SwiftData

@Model
final class SpendTransaction {
    @Attribute(.unique) var id: UUID
    var merchant: String
    var amountCents: Int64
    var currency: String
    /// HKD per original unit; empty for a saved original-currency purchase without HKD valuation.
    var exchangeRate: String
    var category: String
    var paymentMethod: String
    var date: Date
    var createdAt: Date
    var notes: String
    var source: String
    var externalID: String
    var card: BankCard?
    var channel: String = "physical"
    var isOverseas: Bool = false
    var isRewardEligible: Bool = true
    var region: String = ""

    var modifiedAt: Date = Date.distantPast

    init(merchant: String, amountCents: Int64, currency: String = "HKD",
         exchangeRate: String = "", category: String = "其他",
         paymentMethod: String = "待确认", date: Date = .now,
         notes: String = "", source: String = "manual", externalID: String = "", card: BankCard? = nil) {
        id = UUID(); self.merchant = merchant; self.amountCents = amountCents
        self.currency = currency; self.exchangeRate = currency == "HKD" ? "1" : exchangeRate
        self.category = category; self.paymentMethod = paymentMethod; self.date = date
        self.notes = notes; self.source = source; self.externalID = externalID
        self.card = card; createdAt = .now; channel = "unknown"
    }
    var hasHKDValuation: Bool { currency == "HKD" || (!exchangeRate.isEmpty && (Decimal(string: exchangeRate) ?? 0) > 0) }
    var hkdCents: Int64 { Money.convert(amountCents, rate: exchangeRate) }
}
