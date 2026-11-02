import Foundation

/// Personal choices sync with the card; permission to notify stays on each device.
struct CardBillingPreferences: Codable, Equatable, Sendable {
    var cardKey: String
    var statementReminder = false
    var paymentReminder = false
    var advanceDays = 3
    var hour = 10
    var minute = 0

    var key: String { "billingPreferences:" + cardKey }
    var hasReminder: Bool { statementReminder || paymentReminder }
    var isValid: Bool {
        cardKey.hasPrefix("card:") && cardKey.count <= 600
            && [0, 1, 3, 7].contains(advanceDays) && (0...23).contains(hour) && (0...59).contains(minute)
    }
}
