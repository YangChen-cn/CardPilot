import SwiftUI
import SwiftData

struct CardFinancialSummary: View {
    let card: BankCard
    @Query private var documents: [DomainRecord]

    var body: some View {
        let finance = (try? FinanceStore.snapshot(documents)) ?? FinanceSnapshot()
        let group = finance.groups.first { $0.cardKeys.contains(card.syncKey) }
        let statement = finance.statements.filter { $0.cardKey == card.syncKey && finance.unpaid($0) > 0 }
            .min { $0.dueDate < $1.dueDate }
        GroupBox("持卡与账单") {
            VStack(alignment: .leading, spacing: 14) {
                if let group {
                    LabeledContent("记录的信用额度", value: Money.text(group.limitCents))
                    if group.cardKeys.count > 1 { Text(group.name + " · 多卡共享").font(.caption).foregroundStyle(.secondary) }
                }
                LabeledContent("账单日", value: card.statementDay == 0 ? "未设置" : "每月 \(card.statementDay) 日")
                LabeledContent("还款日", value: card.paymentDay == 0 ? "未设置" : "每月 \(card.paymentDay) 日")
                if let statement {
                    LabeledContent("已记录待还账单", value: Money.text(finance.unpaid(statement), currency: statement.currency))
                    LabeledContent("到期日", value: statement.dueDate.formatted(date: .abbreviated, time: .omitted))
                }
                NavigationLink("管理账单与还款") { FinanceView() }.frame(minHeight: 44)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }
}
