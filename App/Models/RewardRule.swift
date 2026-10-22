import Foundation
import SwiftData

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
