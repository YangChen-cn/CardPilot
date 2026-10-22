import SwiftUI
import SwiftData

struct CreditGroupEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BankCard.createdAt) private var cards: [BankCard]
    @State private var group: CreditGroup
    @State private var amount: Decimal
    @State private var message: String?
    init(group: CreditGroup? = nil) {
        let value = group ?? CreditGroup(name: "", limitCents: 0, cardKeys: [])
        _group = State(initialValue: value); _amount = State(initialValue: Decimal(value.limitCents) / 100)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("额度资料") {
                    TextField("名称，例如中银共享额度", text: $group.name)
                    TextField("信用额度（HKD）", value: $amount, format: .number)
                }
                Section("共用此额度的银行卡") {
                    ForEach(cards) { card in
                        Button(action: { toggle(card.syncKey) }) {
                            Label(card.displayName, systemImage: group.cardKeys.contains(card.syncKey) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }
                if let message { Text(message).foregroundStyle(.red) }
            }
            .formStyle(.grouped).navigationTitle("共享信用额度")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: { dismiss() }) }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
        }.editorSize()
    }
    private func toggle(_ key: String) {
        if group.cardKeys.contains(key) { group.cardKeys.removeAll { $0 == key } } else { group.cardKeys.append(key) }
    }
    private func save() {
        guard !amount.isNaN, amount > 0, amount <= Money.maxAmount else { message = "请输入有效信用额度。"; return }
        do { group.limitCents = Money.cents(amount); try Persistence.save(context) { try FinanceStore.save(group, context: context) }; dismiss() }
        catch { message = PilotError.message(error) }
    }
}
