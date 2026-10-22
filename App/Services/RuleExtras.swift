import Foundation

struct RuleExtras: Codable, Equatable, Sendable {
    var perTransactionCapCents: Int64 = 0
    var minimumOriginalCents: Int64 = 0
    var monthlyLocalThresholdCents: Int64 = 0
    var stackingGroup = ""
    var rateMode = "total"
    var capScope = ""
    var currencyCondition = "any"
    var excludedCategories: [String] = []
    var excludedPaymentMethods: [String] = []
    var paymentMethods: [String] = []
    var regions: [String] = []
    var rewardBasis = "hkd"
    var capIncludesBase = false
    var welcomeMode = "fixed"
    /// Explicit published activity group. Nil on legacy records.
    var benefitGroup: String?
    /// Published activity dates are incomplete; stored fallback dates are not presented as verified terms.
    var periodUnverified = false

    enum CodingKeys: String, CodingKey {
        case perTransactionCapCents, minimumOriginalCents, monthlyLocalThresholdCents, stackingGroup, rateMode, capScope
        case currencyCondition, excludedCategories, excludedPaymentMethods, paymentMethods, regions, rewardBasis, capIncludesBase, welcomeMode, periodUnverified, benefitGroup
    }
    init() {}
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        perTransactionCapCents = try c.decodeIfPresent(Int64.self, forKey: .perTransactionCapCents) ?? 0
        minimumOriginalCents = try c.decodeIfPresent(Int64.self, forKey: .minimumOriginalCents) ?? 0
        monthlyLocalThresholdCents = try c.decodeIfPresent(Int64.self, forKey: .monthlyLocalThresholdCents) ?? 0
        stackingGroup = try c.decodeIfPresent(String.self, forKey: .stackingGroup) ?? ""
        rateMode = try c.decodeIfPresent(String.self, forKey: .rateMode) ?? "total"
        capScope = try c.decodeIfPresent(String.self, forKey: .capScope) ?? ""
        currencyCondition = try c.decodeIfPresent(String.self, forKey: .currencyCondition) ?? "any"
        excludedCategories = try c.decodeIfPresent([String].self, forKey: .excludedCategories) ?? []
        excludedPaymentMethods = try c.decodeIfPresent([String].self, forKey: .excludedPaymentMethods) ?? []
        paymentMethods = try c.decodeIfPresent([String].self, forKey: .paymentMethods) ?? []
        regions = try c.decodeIfPresent([String].self, forKey: .regions) ?? []
        rewardBasis = try c.decodeIfPresent(String.self, forKey: .rewardBasis) ?? "hkd"
        capIncludesBase = try c.decodeIfPresent(Bool.self, forKey: .capIncludesBase) ?? false
        welcomeMode = try c.decodeIfPresent(String.self, forKey: .welcomeMode) ?? "fixed"
        benefitGroup = try c.decodeIfPresent(String.self, forKey: .benefitGroup)
        periodUnverified = try c.decodeIfPresent(Bool.self, forKey: .periodUnverified) ?? false
    }
}
