import Foundation

/// Currency describes settlement, not the merchant's location.
enum SpendLocationPolicy {
    static func implicitRegion(for currency: String) -> String { currency == "HKD" ? "HK" : "" }
    static func region(afterCurrencyChange currency: String, current: String, wasChosen: Bool) -> String {
        wasChosen ? current : implicitRegion(for: currency)
    }
    static func title(_ region: String) -> String {
        switch region {
        case "HK": "香港"
        case "CN": "中国内地"
        case "MO": "澳门"
        case "other": "其他地区"
        default: "选择地区"
        }
    }
}
