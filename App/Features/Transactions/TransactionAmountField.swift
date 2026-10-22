import SwiftUI

struct TransactionAmountField: View {
    @Binding var amount: Decimal
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("消费金额").font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(currency).font(.title3.weight(.medium)).foregroundStyle(.secondary)
                TextField("0.00", value: $amount, format: .number.precision(.fractionLength(0...2)))
                    .font(.largeTitle.weight(.semibold)).monospacedDigit()
                    .accessibilityLabel("消费金额，\(currency)")
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
        }
    }
}
