import Foundation
import SwiftData

@Model
final class BankCard {
    @Attribute(.unique) var id: UUID
    var bank: String
    var name: String
    var network: String
    var kind: String
    var lastFour: String
    var statementDay: Int
    var paymentDay: Int
    var baseRateBps: Int
    var foreignFeeBps: Int
    var theme: String
    var isArchived: Bool
    var createdAt: Date
    var catalogID: String = ""
    var sourceURL: String = ""
    var verifiedOn: String = ""
    var imageURL: String = ""
    var annualFeeNote: String = ""
    var caveats: String = ""
    var overseasHKDFeeBps: Int = 0
    var excludesWallets: Bool = false
    @Attribute(.externalStorage) var imageData: Data?
    @Relationship(deleteRule: .cascade, inverse: \RewardRule.card) var rules: [RewardRule] = []
    @Relationship(deleteRule: .cascade, inverse: \SpendTransaction.card) var transactions: [SpendTransaction] = []

    var modifiedAt: Date = Date.distantPast

    init(bank: String, name: String, network: String = "Visa", kind: String = "信用卡",
         lastFour: String = "", statementDay: Int = 1, paymentDay: Int = 25,
         baseRateBps: Int = 0, foreignFeeBps: Int = 0, theme: String = "teal") {
        id = UUID(); self.bank = bank; self.name = name; self.network = network
        self.kind = kind; self.lastFour = lastFour; self.statementDay = statementDay
        self.paymentDay = paymentDay; self.baseRateBps = baseRateBps
        self.foreignFeeBps = foreignFeeBps; self.theme = theme
        isArchived = false; createdAt = .now
    }
    var displayName: String { "\(bank) · \(name)" }
}
