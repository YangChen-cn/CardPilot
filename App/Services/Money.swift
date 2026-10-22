import Foundation

enum Money {
    static let maxAmount: Decimal = 100_000_000

    static func cents(_ value: Decimal) -> Int64 {
        rounded(value * 100)
    }

    static func rounded(_ value: Decimal) -> Int64 {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .plain)
        return NSDecimalNumber(decimal: result).int64Value
    }

    static func convert(_ cents: Int64, rate: String) -> Int64 {
        guard let value = Decimal(string: rate, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN, value > 0 else { return 0 }
        return rounded(Decimal(cents) * value)
    }

    static func reward(_ cents: Int64, bps: Int) -> Int64 {
        rounded(Decimal(cents) * Decimal(bps) / 10_000)
    }

    static func text(_ cents: Int64, currency: String = "HKD") -> String {
        (Decimal(cents) / 100).formatted(.currency(code: currency).locale(Locale(identifier: "en_HK")))
    }

    static func percent(_ bps: Int) -> String {
        (Decimal(bps) / 100).formatted(.number.precision(.fractionLength(0...2))) + "%"
    }
}
