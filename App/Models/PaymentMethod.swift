import Foundation

enum PaymentMethod: String, Codable, CaseIterable, Identifiable {
    case unknown = "待确认"
    case applePay = "Apple Pay"
    case physical = "实体卡"
    case online = "网上支付"
    case alipay = "支付宝"
    case wechat = "微信支付"
    case unionPay = "云闪付"
    case bocPay = "BoC Pay"
    case huaweiPay = "Huawei Pay"
    case payme = "PayMe"
    var id: String { rawValue }
}
