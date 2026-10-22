import Foundation
import SwiftData

// Frozen schema: never edit persisted fields in this version.
enum LocalSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [BankCard.self, RewardRule.self, SpendTransaction.self, AppMetadata.self, SyncTombstone.self] }

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

    @Model
    final class RewardRule {
        @Attribute(.unique) var id: UUID
        var name: String
        /// cashback: a total rate (not additive); welcome: one-time HKD reward.
        var kind: String
        var rateBps: Int
        var capCents: Int64
        var capPeriod: String
        var thresholdCents: Int64
        var bonusCents: Int64
        var minimumCents: Int64
        var category: String
        var currency: String
        var paymentMethod: String
        var merchantKeywords: String
        var startsOn: Date
        var endsOn: Date
        var isEnabled: Bool
        var notes: String
        var card: BankCard?
        var externalID: String = ""
        var sourceURL: String = ""
        var verifiedOn: String = ""
        var sharedCapGroup: String = ""
        var monthlyPhysicalThresholdCents: Int64 = 0
        /// any, online, overseasForeign, onlineOrOverseasForeign
        var channelCondition: String = "any"

        var modifiedAt: Date = Date.distantPast

        init(name: String, kind: String = "cashback", card: BankCard? = nil,
             rateBps: Int = 0, capCents: Int64 = 0, capPeriod: String = "monthly",
             thresholdCents: Int64 = 0, bonusCents: Int64 = 0,
             startsOn: Date = .now, endsOn: Date = .now) {
            id = UUID(); self.name = name; self.kind = kind; self.card = card
            self.rateBps = rateBps; self.capCents = capCents; self.capPeriod = capPeriod
            self.thresholdCents = thresholdCents; self.bonusCents = bonusCents
            self.startsOn = startsOn; self.endsOn = endsOn
            minimumCents = 0; category = ""; currency = ""; paymentMethod = ""
            merchantKeywords = ""; isEnabled = true; notes = ""
        }
        var isWelcome: Bool { kind == "welcome" }
    }

    @Model
    final class SpendTransaction {
        @Attribute(.unique) var id: UUID
        var merchant: String
        var amountCents: Int64
        var currency: String
        /// Decimal text, HKD per one unit of the original currency. Historical snapshot.
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

        var modifiedAt: Date = Date.distantPast

        init(merchant: String, amountCents: Int64, currency: String = "HKD",
             exchangeRate: String = "1", category: String = "其他",
             paymentMethod: String = "Apple Pay", date: Date = .now,
             notes: String = "", source: String = "manual", externalID: String = "", card: BankCard? = nil) {
            id = UUID(); self.merchant = merchant; self.amountCents = amountCents
            self.currency = currency; self.exchangeRate = currency == "HKD" ? "1" : exchangeRate
            self.category = category; self.paymentMethod = paymentMethod; self.date = date
            self.notes = notes; self.source = source; self.externalID = externalID
            self.card = card; createdAt = .now
        }
        var hkdCents: Int64 { Money.convert(amountCents, rate: exchangeRate) }
    }

    @Model
    final class AppMetadata {
        @Attribute(.unique) var key: String
        var value: String
        init(key: String, value: String) { self.key = key; self.value = value }
    }

    @Model
    final class SyncTombstone {
        @Attribute(.unique) var key: String
        var deletedAt: Date
        init(key: String, deletedAt: Date) { self.key = key; self.deletedAt = deletedAt }
    }
}
