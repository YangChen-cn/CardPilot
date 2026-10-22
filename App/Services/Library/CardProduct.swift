import Foundation

/// Official product definitions are separate from a user's BankCard and personal application.
struct CardProduct: Identifiable, Sendable {
    let bankID: String
    let catalog: CatalogCard
    let imageResource: String
    let baseRewardVerified: Bool
    let welcomePlans: [WelcomePlan]
    var id: String { catalog.id }

    /// Extra names users commonly type that are not part of the formal title.
    var searchKeywords: [String] {
        switch id {
        case "hsbc.pulse.unionpay.diamond": ["Pulse", "Pluse", "双币", "钻石"]
        case "bochk.gba.youth": ["GBA", "大湾区", "双币", "青年"]
        case "cncbi.gba.dual": ["GBA", "大湾区", "双币", "信银", "中信"]
        case "bochk.mastercard.debit": ["Mastercard", "万事达", "扣账卡", "借记卡"]
        case "cncbi.multi-currency.debit": ["CITIC", "中信", "信银", "多币", "扣账卡", "借记卡"]
        default: []
        }
    }

    /// Some official welcomes cannot be expressed as a single numeric reward. Keep their
    /// published text as activities too, without manufacturing thresholds or payout values.
    var displayCatalog: CatalogCard {
        var value = catalog
        for plan in welcomePlans where plan.ruleIDs.isEmpty && !value.rules.contains(where: { $0.id == plan.id }) {
            let start = plan.applicationStartsOn ?? catalog.rules.compactMap(\.startsOn).max() ?? nil
            let end = plan.applicationEndsOn ?? catalog.rules.compactMap(\.endsOn).max() ?? nil
            var activity = CatalogRule(id: plan.id, name: plan.title, kind: "welcome", group: "welcome",
                                       startsOn: start, endsOn: end, sourceURL: plan.sourceURL)
            activity.enabled = false
            var metadata = RuleExtras()
            metadata.periodUnverified = plan.applicationStartsOn == nil || plan.applicationEndsOn == nil
            activity.calculation = metadata
            var notes = (plan.verified ? "" : "资料待核实。") + plan.details
            if !plan.applicationChannels.isEmpty { notes += "\n申请渠道：" + plan.applicationChannels.joined(separator: "、") }
            notes += metadata.periodUnverified ? "\n活动日期尚待核实，个人消费截止日请按官方条款记录。" : "\n所列日期为申请推广期，个人消费截止日请按官方条款记录。"
            activity.notes = notes
            value.rules.append(activity)
        }
        return value
    }
}
