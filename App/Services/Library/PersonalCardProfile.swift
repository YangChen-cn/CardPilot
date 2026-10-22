import Foundation

/// A user's application and chosen welcome plan, independent of official product data.
struct PersonalCardProfile: Codable, Sendable {
    var cardKey: String
    var productID: String
    var bankID: String
    var applicationDate: Date
    var applicationChannel: String
    var issueDate: Date
    var welcomePlanID: String
    var welcomeRuleIDs: [String]
    var welcomeEnabled: Bool
    var welcomeStartsOn: Date
    var welcomeEndsOn: Date
    var confirmedEligibility: Bool
    var managedWelcomeRuleIDs: [String]? = nil
    var managedMainRuleIDs: [String]? = nil
    var mainExclusionGroup: String? = nil
    var mainEligibilityClaimed: Bool? = nil
    var addons: [WelcomeAddonRecord]? = nil
    var managedIDs: Set<String> { Set(managedWelcomeRuleIDs ?? welcomeRuleIDs) }
    var mainManagedIDs: Set<String> { Set(managedMainRuleIDs ?? managedWelcomeRuleIDs ?? welcomeRuleIDs) }
}
