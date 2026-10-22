import Foundation

struct BillingStatement: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var cardKey: String
    var amountCents: Int64
    var currency: String
    var exchangeRate: String
    var periodEnd: Date
    var dueDate: Date
    var hkdCents: Int64 { Money.convert(amountCents, rate: currency == "HKD" ? "1" : exchangeRate) }
}
