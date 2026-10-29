import SwiftUI

struct SpendFields: View {
    @Bindable var draft: TransactionDraft
    let cards: [BankCard]
    @State private var showingDetails = false
    @FocusState private var focusedInput: SpendInputFocus?

    var body: some View {
        Section {
            TransactionAmountField(amount: $draft.amount, currency: $draft.currency,
                                   focusInitially: draft.existing == nil, focus: $focusedInput)
                .padding(.vertical, 12)
        }
        Section {
            TextField("商户名称", text: $draft.merchant)
                .textContentType(.organizationName)
                .focused($focusedInput, equals: .merchant)
                .submitLabel(.done)
                .onSubmit { focusedInput = nil }
            Picker("银行卡", selection: $draft.cardID) {
                Text("选择银行卡").tag(nil as UUID?)
                ForEach(cards) { Text($0.displayName).tag(Optional($0.id)) }
            }
            Picker("分类", selection: $draft.category) {
                ForEach(SpendCategory.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0.rawValue) }
            }
            DatePicker("交易日期", selection: $draft.date, in: ...Date.now, displayedComponents: .date)
        }
        Section {
            PilotDisclosureGroup("更多选项", isExpanded: $showingDetails) {
                if draft.currency != "HKD" {
                    TextField("1 \(draft.currency) 折合 HKD", value: $draft.exchangeRate, format: .number.precision(.fractionLength(0...6)))
                        .focused($focusedInput, equals: .exchangeRate)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                if draft.currency != "HKD" {
                    Text("原币金额直接保存。汇率可不填；港币合计仅包含有可信汇率的记录。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DatePicker("具体时间", selection: $draft.date, in: ...Date.now, displayedComponents: .hourAndMinute)
                Picker("支付方式", selection: $draft.paymentMethod) {
                    ForEach(PaymentMethod.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Picker("消费渠道", selection: $draft.channel) {
                    Text("未记录").tag("unknown")
                    Text("实体商户").tag("physical")
                    Text("网上商户").tag("online")
                }
                RegionPicker(region: $draft.region)
                if draft.region == "" || draft.region == "HK" {
                    Toggle("境外商户", isOn: $draft.isOverseas)
                }
                TextField("备注", text: $draft.notes, axis: .vertical).lineLimit(2...4)
                    .focused($focusedInput, equals: .notes)
            }
        }
    }
}
