import Foundation

struct CreditGroup: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var limitCents: Int64
    var cardKeys: [String]
}
