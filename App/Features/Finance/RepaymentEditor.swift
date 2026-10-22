import SwiftUI
import SwiftData

struct RepaymentEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let statement: BillingStatement
    @State private var amount = Decimal(0)
    @State private var date = Date.now
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("还款金额（\(statement.currency)）", value: $amount, format: .number)
                DatePicker("还款日期", selection: $date, in: ...Date.now, displayedComponents: .date)
                if let message { Text(message).foregroundStyle(.red) }
            }
            .formStyle(.grouped).navigationTitle("记录还款")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: { dismiss() }) }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
        }.editorSize()
        .task {
            do { amount = Decimal(try FinanceStore.snapshot(context: context).unpaid(statement)) / 100 }
            catch { message = "暂时无法读取账单。" }
        }
    }
    private func save() {
        guard !amount.isNaN, amount > 0, amount <= Money.maxAmount else { message = "请输入有效还款金额。"; return }
        do {
            try Persistence.save(context) { try FinanceStore.save(Repayment(statementID: statement.id, amountCents: Money.cents(amount), date: date), context: context) }
            dismiss()
        } catch { message = PilotError.message(error) }
    }
}
