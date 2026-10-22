import Foundation
import SwiftData

@MainActor enum WelcomeTrackingStore {
    static func key(_ rule: RewardRule) -> String { "welcomeTracking:" + rule.syncKey }

    static func load(rule: RewardRule, context: ModelContext) throws -> WelcomeTracking {
        if let saved = try DocumentStore.load(WelcomeTracking.self, key: key(rule), in: context) { return saved }
        let receipt = try DocumentStore.load(WelcomeReceipt.self, key: "welcome:" + rule.syncKey, in: context)
        let profile: PersonalCardProfile? = if let card = rule.card {
            try DocumentStore.load(PersonalCardProfile.self, key: "personalCard:" + card.syncKey, in: context)
        } else { nil }
        let addon = profile?.addons?.first { $0.ruleIDs.contains(rule.externalID) || $0.planID == rule.externalID }
        let info = BenefitInfo(rule: rule)
        var result = WelcomeTracking(status: rule.isEnabled ? .active : .unconfirmed,
                                     applicationDate: profile?.applicationDate, issueDate: profile?.issueDate,
                                     deadline: rule.endsOn, thresholdCents: rule.thresholdCents,
                                     rewardContent: info.headline)
        // A published promotion period is not automatically this user's personal spending period.
        result.deadlineConfirmed = rule.isEnabled && info.hasKnownPeriod
        if let addon { result.deadline = addon.endsOn; result.deadlineConfirmed = true }
        else if let profile, profile.welcomePlanID == rule.externalID {
            result.deadline = profile.welcomeEndsOn; result.deadlineConfirmed = true
        } else if profile?.welcomeRuleIDs.contains(rule.externalID) == true {
            result.deadlineConfirmed = true
        }
        if receipt?.received == true || addon?.received == true {
            result.status = .received; result.receivedOn = receipt?.receivedOn ?? addon?.receivedOn
        } else if (try? RulePolicyStore.state(rule).archived) == true { result.status = .ended }
        return result
    }

    static func save(_ value: WelcomeTracking, rule: RewardRule, context: ModelContext) throws {
        guard rule.isWelcome, (0...10_000_000_000).contains(value.thresholdCents),
              value.rewardContent.count <= 2000, value.notes.count <= 10_000 else {
            throw PilotError.invalid("请检查迎新目标和备注。")
        }
        try Persistence.save(context) {
            try DocumentStore.put(value, key: key(rule), kind: "welcomeTracking", in: context)
        }
    }
}
