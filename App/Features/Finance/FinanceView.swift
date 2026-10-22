import SwiftUI
import SwiftData

struct FinanceView: View {
    @Environment(\.modelContext) private var context
    @Query private var documents: [DomainRecord]
    @Query private var transactions: [SpendTransaction]
    @Query private var cards: [BankCard]
    @State private var addingGroup = false
    @State private var addingStatement = false
    @State private var editingGroup: CreditGroup?
    @State private var editingStatement: BillingStatement?
    @State private var paying: BillingStatement?
    @State private var message: String?

    var body: some View {
        let snapshot = try? FinanceStore.snapshot(documents)
        List {
            Section("共享信用额度 · HKD") {
                Button("添加额度组", systemImage: "plus", action: { addingGroup = true }).disabled(cards.isEmpty)
                if snapshot?.groups.isEmpty == true { Text("将同一银行共用额度的卡片放进一个组。").foregroundStyle(.secondary) }
                ForEach(snapshot?.groups ?? []) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.name).font(.headline)
                        LabeledContent("总额度", value: Money.text(group.limitCents))
                        LabeledContent("预计可用", value: Money.text(snapshot?.available(group, transactions: transactions) ?? 0))
                        Text(cards.filter { group.cardKeys.contains($0.syncKey) }.map(\.name).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("编辑", action: { editingGroup = group })
                            Spacer()
                            Button("移除额度组", role: .destructive, action: { remove("creditGroup:" + group.id.uuidString) })
                        }
                    }.padding(.vertical, 4)
                }
            }
            Section("账单与还款") {
                Button("添加账单", systemImage: "doc.badge.plus", action: { addingStatement = true }).disabled(cards.isEmpty)
                ForEach((snapshot?.statements ?? []).sorted { $0.periodEnd > $1.periodEnd }) { statement in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(cards.first(where: { $0.syncKey == statement.cardKey })?.displayName ?? "已移除的银行卡").font(.headline)
                        LabeledContent("账单金额", value: Money.text(statement.amountCents, currency: statement.currency))
                        LabeledContent("已记录未还", value: Money.text(snapshot?.unpaid(statement) ?? statement.amountCents, currency: statement.currency))
                        LabeledContent("还款日期", value: statement.dueDate.formatted(date: .abbreviated, time: .omitted))
                        HStack {
                            Button("编辑账单", action: { editingStatement = statement })
                            Spacer()
                            Button("记录还款", action: { paying = statement }).disabled(snapshot?.unpaid(statement) == 0)
                        }
                        PilotDisclosureGroup("还款记录") {
                            ForEach((snapshot?.payments ?? []).filter { $0.statementID == statement.id }.sorted { $0.date > $1.date }) { payment in
                                HStack {
                                    Text(payment.date, format: .dateTime.year().month().day())
                                    Spacer(); Text(Money.text(payment.amountCents, currency: statement.currency))
                                    Button("撤销", role: .destructive, action: { remove("repayment:" + payment.id.uuidString) })
                                }
                            }
                        }
                    }.padding(.vertical, 5)
                }
            }
            Section {
                Text("可用额度按最新账单、账单后消费与还款估算。账单可包含上期欠款，旧账单不会重复累计；请及时补录账单及还款。").font(.caption).foregroundStyle(.secondary)
            }
            if snapshot == nil { Section { Text("暂时无法读取额度资料，请重新打开此页。") } }
            if let message { Section { Text(message).foregroundStyle(.red) } }
        }
        .navigationTitle("额度与还款")
        .sheet(isPresented: $addingGroup) { CreditGroupEditor() }
        .sheet(item: $editingGroup) { CreditGroupEditor(group: $0) }
        .sheet(isPresented: $addingStatement) { StatementEditor() }
        .sheet(item: $editingStatement) { StatementEditor(statement: $0) }
        .sheet(item: $paying) { RepaymentEditor(statement: $0) }
    }
    private func remove(_ key: String) {
        do { try Persistence.save(context) { try DocumentStore.remove(key, in: context) } }
        catch { message = "未能保存更改，请重试。" }
    }
}
