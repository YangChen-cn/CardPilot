import Foundation

struct BankMailPackage: Codable, Sendable {
    var schemaVersion: Int
    var messages: [BankMailMessage]
}

/// Minimal Gmail envelope; only trusted header values belong in authenticationResults.
struct BankMailMessage: Codable, Sendable {
    var id: String
    var sender: String
    var subject: String
    var receivedAt: Date
    var body: String
    var authenticationResults: String
}

struct BankMailTransaction: Codable, Equatable, Sendable {
    var messageID: String
    var bankID: String
    var lastFour: String
    var merchant: String
    var amountCents: Int64
    var currency: String
    var date: Date
    var hasExactTime: Bool
    var receivedAt: Date
    var paymentMethod: String?
    var channel: String?
    var region: String?
    var bankReference: String?
    var cardKind: String? = nil
    var evidenceSource: String? = nil
    var source: String { evidenceSource ?? "email" }

    /// Older synced HSBC/BEA messages came exclusively from these same adapters.
    var requiredCardKind: String? {
        cardKind ?? (bankID == "hsbc" ? "借记卡" : bankID == "bea" ? "信用卡" : nil)
    }
}
