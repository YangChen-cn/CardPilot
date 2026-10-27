import Foundation

/// Parse the complete Wallet value, without guessing a currency or rounding malformed input.
enum WalletAmountParser {
    struct Parsed: Equatable {
        let amountCents: Int64
        let currency: String
    }

    enum Failure: Error, LocalizedError, Equatable {
        case missingAmount
        case ambiguousCurrency
        case unsupportedCurrency
        case invalidAmount

        var errorDescription: String? {
            switch self {
            case .missingAmount: "钱包没有传入金额，请检查「数量」变量。"
            case .ambiguousCurrency: "钱包金额没有明确币种，请核对原文；单币种自动化可指定备用币种。"
            case .unsupportedCurrency: "钱包交易使用了 CardPilot 尚未支持的币种或金额格式。"
            case .invalidAmount: "无法识别钱包消费金额，请检查「数量」变量。退款或负数请手动核对。"
            }
        }
    }

    static func parse(_ raw: String, fallbackCurrency: String = "自动") throws -> Parsed {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.missingAmount }
        guard text.count <= 256,
              let range = text.range(of: #"[0-9](?:[0-9.,\s]*[0-9])?"#, options: .regularExpression) else {
            throw Failure.invalidAmount
        }
        let markers = [String(text[..<range.lowerBound]), String(text[range.upperBound...])]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        let explicit: [String: String] = [
            "HKD": "HKD", "HK$": "HKD", "HK＄": "HKD", "港币": "HKD", "港幣": "HKD",
            "CNY": "CNY", "RMB": "CNY", "CN¥": "CNY", "CN￥": "CNY", "人民币": "CNY", "人民幣": "CNY",
            "USD": "USD", "US$": "USD", "US＄": "USD"
        ]
        var currencies = Set<String>()
        for marker in markers where !marker.isEmpty {
            if let currency = explicit[marker] {
                currencies.insert(currency)
            } else if !["$", "＄", "¥", "￥"].contains(marker) {
                // Never discard a sign, extra number, unknown currency, or trailing text.
                throw Failure.unsupportedCurrency
            }
        }
        let preference = fallbackCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let fallback = ["", "自动", "AUTO"].contains(preference) ? nil : preference
        if let fallback, Currency(rawValue: fallback) == nil { throw Failure.unsupportedCurrency }
        guard currencies.count <= 1, let currency = currencies.first ?? fallback else {
            throw Failure.ambiguousCurrency
        }
        // Both yen signs and dollar signs are ambiguous without an explicit code or user choice.
        if markers.contains(where: { ["¥", "￥"].contains($0) }), currency != "CNY" {
            throw Failure.ambiguousCurrency
        }
        if markers.contains(where: { ["$", "＄"].contains($0) }), !["HKD", "USD"].contains(currency) {
            throw Failure.ambiguousCurrency
        }

        let number = String(text[range]).replacing("\u{00a0}", with: " ").replacing("\u{202f}", with: " ")
        let normalized: String
        if matches(number, #"(?:[1-9][0-9]{0,2}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]{1,2})?"#) {
            normalized = number.replacing(",", with: "")
        } else if matches(number, #"(?:[1-9][0-9]{0,2}(?:\.[0-9]{3})+|[0-9]+)(?:,[0-9]{1,2})?"#) {
            normalized = number.replacing(".", with: "").replacing(",", with: ".")
        } else if matches(number, #"[1-9][0-9]{0,2}(?: [0-9]{3})+(?:[.,][0-9]{1,2})?"#) {
            normalized = number.replacing(" ", with: "").replacing(",", with: ".")
        } else {
            throw Failure.invalidAmount
        }
        guard let amount = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              amount > 0, amount <= Money.maxAmount else { throw Failure.invalidAmount }
        return Parsed(amountCents: Money.cents(amount), currency: currency)
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: "\\A(?:" + pattern + ")\\z", options: .regularExpression) != nil
    }
}
