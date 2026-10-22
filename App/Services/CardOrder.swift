import Foundation

/// Persisted display order for the card grid. Keys are cross-device stable
/// `BankCard.syncKey` values; cards not present in the order append at the end.
struct CardOrder: Codable, Equatable, Sendable {
    var keys: [String]
}
