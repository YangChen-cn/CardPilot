import SwiftUI
import SwiftData

struct StatementEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var cards: [BankCard]
    @State private var statement: BillingStatement
    @State private var amount: Decimal
    @State private var rate: Decimal
    @State private var message: String?
    init(statement: BillingStatement? = nil) {
        let value = statement ?? BillingStatement(cardKey: "", amountCents: 0, currency: "HKD", exchangeRate: "1", periodEnd: .now, dueDate: .now.addingTimeInterval(20 * 86400))
        _statement = State(initialValue: value); _amount = State(initialValue: Decimal(value.amountCents) / 100)
        _rate = State(initialValue: Decimal(string: value.exchangeRate) ?? 1)
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("银行卡", selection: $statement.cardKey) {
                    Text("请选择").tag("")
                    ForEach(cards) { Text($0.displayName).tag($0.syncKey) }
                }
                TextField("账单总金额", value: $amount, format: .number)
                Picker("账单币种", selection: $statement.currency) { ForEach(Currency.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                if statement.currency != "HKD" { TextField("1 \(statement.currency) = HKD", value: $rate, format: .number) }
                DatePicker("账单截止日", selection: $statement.periodEnd, displayedComponents: .date)
                DatePicker("还款截止日", selection: $statement.dueDate, displayedComponents: .date)
                if let message { Text(message).foregroundStyle(.red) }
            }
            .formStyle(.grouped).navigationTitle("记录账单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: { dismiss() }) }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
        }.editorSize()
        .onChange(of: statement.currency) { _, new in rate = new == "HKD" ? 1 : 0 }
    }
    private func save() {
        guard !statement.cardKey.isEmpty, !amount.isNaN, amount >= 0, amount <= Money.maxAmount, !rate.isNaN else { message = "请选择银行卡并填写有效金额。"; return }
        statement.amountCents = Money.cents(amount); statement.exchangeRate = statement.currency == "HKD" ? "1" : rate.description
        do { try Persistence.save(context) { try FinanceStore.save(statement, context: context) }; dismiss() }
        catch { message = PilotError.message(error) }
    }
}
