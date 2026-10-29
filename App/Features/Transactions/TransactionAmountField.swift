import SwiftUI

struct TransactionAmountField: View {
    @Binding var amount: Decimal
    @Binding var currency: String
    let focusInitially: Bool
    var focus: FocusState<SpendInputFocus?>.Binding
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("消费金额").font(.subheadline).foregroundStyle(.secondary)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
            layout {
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
                    .focused(focus, equals: .amount)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focus.wrappedValue = nil }
            }
        }
        #endif
        .task { if focusInitially { focus.wrappedValue = .amount } }
    }
}
