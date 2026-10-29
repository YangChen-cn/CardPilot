import SwiftUI

struct TransactionAmountField: View {
    @Binding var amount: Decimal
    @Binding var currency: String
    let focusInitially: Bool
    @FocusState private var amountFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("消费金额").font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Picker("币种", selection: $currency) {
                    ForEach(Currency.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel("币种，当前\(currency)")
                .frame(minHeight: PilotTheme.minimumTouchTarget)
                TextField("0.00", value: $amount, format: .number.precision(.fractionLength(0...2)))
                    .font(.largeTitle.weight(.semibold)).monospacedDigit()
                    .accessibilityLabel("消费金额，\(currency)")
                    .focused($amountFocused)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { amountFocused = false }
            }
        }
        .task {
            if focusInitially { amountFocused = true }
        }
        #endif
    }
}
