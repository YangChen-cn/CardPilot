import Foundation

enum PaymentMethod: String, Codable, CaseIterable, Identifiable {
    case unknown = "待确认"
    case applePay = "Apple Pay"
    case physical = "实体卡"
    case online = "网上支付"
    case alipay = "支付宝"
    case wechat = "微信支付"
    case unionPay = "UnionPay"
    case bocPay = "BoC Pay"
    case huaweiPay = "Huawei Pay"
    case payme = "PayMe"
    var id: String { rawValue }

    /// `UnionPay`, `UnionPay App`, `云闪付` and `雲閃付` are the same payment
    /// method in official terms and user input. Store and compare one label.
    static func canonical(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.lowercased().replacingOccurrences(of: " ", with: "")
        if ["unionpay", "unionpayapp", "云闪付", "雲閃付", "云闪付app", "雲閃付app"].contains(key) {
            return unionPay.rawValue
        }
        return trimmed
    }

    static func isKnown(_ value: String) -> Bool {
        let canonical = canonical(value)
        return allCases.contains { $0.rawValue == canonical }
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        canonical(lhs) == canonical(rhs)
    }
}
