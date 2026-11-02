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
        let creditCards = cards.filter { !$0.isArchived && !$0.isDebitCard }.sorted {
            let first = nextPayment(for: $0, finance: snapshot)
            let second = nextPayment(for: $1, finance: snapshot)
            return first == second ? $0.displayName < $1.displayName : first < second
        }
        let pending = (snapshot?.statements ?? []).filter { (snapshot?.unpaid($0) ?? $0.amountCents) > 0 }.sorted { $0.dueDate < $1.dueDate }
        let paid = (snapshot?.statements ?? []).filter { snapshot?.unpaid($0) == 0 }.sorted { $0.periodEnd > $1.periodEnd }
        List {
            Section {
                NavigationLink { BillingReminderSettingsView() } label: {
                    Label("账单与还款提醒", systemImage: "bell")
                }
                if creditCards.isEmpty { Text("添加信用卡后，可在这里集中管理日期与账单。").foregroundStyle(.secondary) }
                ForEach(creditCards) { card in
                    NavigationLink { CardBillingView(card: card) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(card.name).font(.headline)
                            Text(card.bank + (card.lastFour.isEmpty ? "" : " · 尾号 " + card.lastFour))
                                .font(.caption).foregroundStyle(.secondary)
                            let date = nextPayment(for: card, finance: snapshot)
                            if date != .distantFuture {
                                Text("还款日 " + date.formatted(date: .abbreviated, time: .omitted)).font(.subheadline)
                            } else { Text("日期待设置").font(.subheadline).foregroundStyle(.secondary) }
                            if snapshot?.billingPreferences[card.syncKey]?.hasReminder == true {
                                Label("已选提醒", systemImage: "bell").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 5)
                    }
                }
            } header: { Text("我的信用卡") } footer: {
                Text("有账单时显示实际还款日；未记录账单时，显示个人设置的常用日期。")
            }
            if let snapshot {
                if !pending.isEmpty {
                    Section("待还账单 · \(pending.count) 期") {
                        ForEach(pending) { statement in statementRow(statement, finance: snapshot) }
                    }
                } else if !snapshot.statements.isEmpty {
                    Section { Label("已记录账单均已还清", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("还没有账单记录").font(.headline)
                            Text("记录各卡账单，集中查看到期日和还款情况。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("记录账单", systemImage: "doc.badge.plus", action: { addingStatement = true })
                                .buttonStyle(.borderedProminent).disabled(creditCards.isEmpty)
                        }.padding(.vertical, 12)
                    }
                }
                if !paid.isEmpty {
                    Section {
                        DisclosureGroup("已还账单 · \(paid.count) 期") {
                            ForEach(paid) { statement in statementRow(statement, finance: snapshot) }
                        }
                    }
                }
            }
            Section("共享信用额度 · HKD") {
                Button("添加额度组", systemImage: "plus", action: { addingGroup = true }).disabled(cards.isEmpty)
                if snapshot?.groups.isEmpty == true { Text("将同一银行共用额度的卡片放进一个组。").foregroundStyle(.secondary) }
                ForEach(snapshot?.groups ?? []) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.name).font(.headline)
                        LabeledContent("总额度", value: Money.text(group.limitCents))
                        if hasUnvaluedAmounts(group, finance: snapshot) {
                            Text("部分原币金额未折算，暂不估算可用额度。").font(.caption).foregroundStyle(.secondary)
                        } else {
                            LabeledContent("预计可用", value: Money.text(snapshot?.available(group, transactions: transactions) ?? 0))
                        }
                        Text(cards.filter { group.cardKeys.contains($0.syncKey) }.map(\.name).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        ViewThatFits(in: .horizontal) {
                            HStack {
                            Button("编辑", action: { editingGroup = group })
                            Spacer()
                            Button("移除额度组", role: .destructive, action: { remove("creditGroup:" + group.id.uuidString) })
                            }
                            VStack(alignment: .leading) {
                                Button("编辑", action: { editingGroup = group })
                                Button("移除额度组", role: .destructive, action: { remove("creditGroup:" + group.id.uuidString) })
                            }
                        }
                        .buttonStyle(.borderless)
                    }.padding(.vertical, 4)
                }
            }
            Section {
                Text("可用额度按最新账单、账单后消费与还款估算。账单可包含上期欠款，旧账单不会重复累计；请及时补录账单及还款。").font(.caption).foregroundStyle(.secondary)
            }
            if snapshot == nil { Section { Text("暂时无法读取额度资料，请重新打开此页。") } }
            if let message { Section { Text(message).foregroundStyle(.red) } }
        }
        .groupedListStyle()
        .navigationTitle("账单与还款")
        .toolbar {
            if snapshot?.statements.isEmpty == false {
                ToolbarItem(placement: .primaryAction) {
                    Button("记录账单", systemImage: "plus", action: { addingStatement = true }).disabled(creditCards.isEmpty)
                }
            }
        }
        .sheet(isPresented: $addingGroup) { CreditGroupEditor() }
        .sheet(item: $editingGroup) { CreditGroupEditor(group: $0) }
        .sheet(isPresented: $addingStatement) { StatementEditor() }
        .sheet(item: $editingStatement) { StatementEditor(statement: $0) }
        .sheet(item: $paying) { RepaymentEditor(statement: $0) }
    }

    private func nextPayment(for card: BankCard, finance: FinanceSnapshot?) -> Date {
        finance?.statements.filter { $0.cardKey == card.syncKey && (finance?.unpaid($0) ?? 0) > 0 }.map(\.dueDate).min()
            ?? BillingDates.next(day: card.paymentDay) ?? .distantFuture
    }

    private func statementRow(_ statement: BillingStatement, finance: FinanceSnapshot) -> some View {
        BillingStatementRow(statement: statement, finance: finance,
            cardName: cards.first(where: { $0.syncKey == statement.cardKey })?.displayName ?? "已移除的银行卡",
            edit: { editingStatement = statement }, pay: { paying = statement }, remove: {
                do { try Persistence.save(context) { try FinanceStore.removeStatement(statement, context: context) } }
                catch { message = "未能删除账单，请重试。" }
            }) { payment in
                remove("repayment:" + payment.id.uuidString)
            }
    }

    private func hasUnvaluedAmounts(_ group: CreditGroup, finance: FinanceSnapshot?) -> Bool {
        let keys = Set(group.cardKeys)
        return finance?.statements.contains { keys.contains($0.cardKey) && $0.currency != "HKD" && $0.exchangeRate.isEmpty } == true
            || transactions.contains { $0.card.map { keys.contains($0.syncKey) } == true && !$0.hasHKDValuation }
    }
    private func remove(_ key: String) {
        do { try Persistence.save(context) { try DocumentStore.remove(key, in: context) } }
        catch { message = "未能保存更改，请重试。" }
    }
}
