import Foundation
import Observation

/// A few user-supplied shopping conditions, independent of ledger and bank settlement.
@MainActor @Observable
final class RecommendationDraft {
    var category = SpendCategory.dining.rawValue
    var amount: Decimal? = nil
    var currency = "HKD"
    var region = ""
    var paymentMethod = ""
    var merchant = ""

    var validationError: String? {
        if let amount, amount.isNaN || amount < 0.01 || amount > Money.maxAmount {
            return "预计金额可留空；填写时须为0.01–100,000,000。"
        }
        if region.isEmpty { return "选择消费地区，查看可能适用的银行卡权益。" }
        return nil
    }
}
