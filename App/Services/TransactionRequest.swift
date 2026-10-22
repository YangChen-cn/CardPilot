import Foundation

struct TransactionRequest: Codable, Equatable, Sendable {
    var cardID: String
    var merchant: String
    var amountCents: Int64
    var currency = "HKD"
    var exchangeRate = ""
    var date: Date
    var hasStableDate = true
    var paymentMethod = "待确认"
    var category = "其他"
    var channel = "unknown"
    var isOverseas = false
    var externalID = ""
    var source = "shortcuts"
    var region = ""
    var isRewardEligible: Bool?
    var notes: String?
}
