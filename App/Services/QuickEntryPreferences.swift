import Foundation

struct QuickEntryPreferences: Codable, Equatable {
    var cardKey: String
    var category: String
    var paymentMethod: String
}
