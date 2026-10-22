import Foundation

enum OriginalCurrencyTotals {
    static func text(_ inputs: [SpendInput]) -> String {
        Dictionary(grouping: inputs.filter { $0.currency != "HKD" }, by: \.currency).sorted { $0.key < $1.key }.map { currency, values in
            Money.text(values.reduce(Int64(0)) { $0 + $1.amountCents }, currency: currency)
        }.joined(separator: " · ")
    }
}
