import SwiftUI
import SwiftData

struct CardBillingView: View {
    @Environment(\.modelContext) private var context
    @Query private var documents: [DomainRecord]
    let card: BankCard
    @State private var editingDates = false
    @State private var adding = false
    @State private var editing: BillingStatement?
    @State private var paying: BillingStatement?
    @State private var message: String?

    var body: some View {
        let finance = try? FinanceStore.snapshot(documents)
        let bills = (finance?.statements ?? []).filter { $0.cardKey == card.syncKey }
        let unpaid = bills.filter { (finance?.unpaid($0) ?? $0.amountCents) > 0 }.sorted { $0.dueDate < $1.dueDate }
        let paid = bills.filter { finance?.unpaid($0) == 0 }.sorted { $0.periodEnd > $1.periodEnd }
        List {
            Section {
                Text(card.name).font(.headline)
                LabeledContent("账单日", value: card.statementDay == 0 ? "未设置" : "每月 \(card.statementDay) 日")
                LabeledContent("常用还款日", value: card.paymentDay == 0 ? "未设置" : "每月 \(card.paymentDay) 日")
                if !card.isArchived && !card.isDebitCard {
                    Button("日期与提醒", systemImage: "bell", action: { editingDates = true })
                }
            }
            if bills.isEmpty, finance != nil {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("记录第一期账单").font(.headline)
                        Text("填入银行账单金额与还款日，还款后更新记录。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("记录账单", systemImage: "doc.badge.plus", action: { adding = true }).buttonStyle(.borderedProminent)
                    }.padding(.vertical, 12)
                }
            }
            if let finance {
                if !unpaid.isEmpty {
                    Section("待还账单") { ForEach(unpaid) { row($0, finance: finance) } }
                } else if !bills.isEmpty {
                    Section { Label("已记录账单均已还清", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                }
                if !paid.isEmpty {
                    Section("已还账单") { ForEach(paid) { row($0, finance: finance) } }
                }
            } else { Section { Text("暂时无法读取账单，请重新打开。原有记录会保留。").foregroundStyle(.secondary) } }
            if let message { Section { Text(message).foregroundStyle(.red) } }
        }
        .groupedListStyle()
        .navigationTitle("账单与还款")
        .inlineNavigationTitle()
        .toolbar {
            if !bills.isEmpty {
                ToolbarItem(placement: .primaryAction) { Button("记录账单", systemImage: "plus", action: { adding = true }) }
            }
        }
        .sheet(isPresented: $editingDates) { BillingScheduleEditor(card: card) }
        .sheet(isPresented: $adding) { StatementEditor(card: card) }
        .sheet(item: $editing) { StatementEditor(statement: $0) }
        .sheet(item: $paying) { RepaymentEditor(statement: $0) }
    }

    private func row(_ statement: BillingStatement, finance: FinanceSnapshot) -> some View {
        BillingStatementRow(statement: statement, finance: finance, edit: { editing = statement }, pay: { paying = statement }, remove: {
            do { try Persistence.save(context) { try FinanceStore.removeStatement(statement, context: context) } }
            catch { message = "未能删除账单，请重试。" }
        }) { payment in
            do { try Persistence.save(context) { try DocumentStore.remove("repayment:" + payment.id.uuidString, in: context) } }
            catch { message = "未能撤销还款记录，请重试。" }
        }
    }
}
