import SwiftUI

struct BillingStatementRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let statement: BillingStatement
    let finance: FinanceSnapshot
    var cardName: String?
    let edit: () -> Void
    let pay: () -> Void
    let remove: () -> Void
    let removePayment: (Repayment) -> Void
    @State private var undoing: Repayment?
    @State private var deleting = false

    var body: some View {
        let unpaid = finance.unpaid(statement)
        let payments = finance.payments.filter { $0.statementID == statement.id }.sorted { $0.date > $1.date }
        VStack(alignment: .leading, spacing: 12) {
            if let cardName { Text(cardName).font(.headline) }
            Label(BillingDates.status(due: statement.dueDate, paid: unpaid == 0), systemImage: unpaid == 0 ? "checkmark.circle" : "calendar")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(unpaid > 0 && HKCalendar.daysLeft(statement.dueDate) <= 3 ? Color.orange : .secondary)
            LabeledContent(unpaid == 0 ? "账单金额" : "待还金额", value: Money.text(unpaid == 0 ? statement.amountCents : unpaid, currency: statement.currency))
                .font(.headline).monospacedDigit()
            LabeledContent("还款截止", value: statement.dueDate.formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline)
            Text("账单截至 " + statement.periodEnd.formatted(date: .abbreviated, time: .omitted))
                .font(.caption).foregroundStyle(.secondary)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 16))
            layout {
                if unpaid > 0 { Button("记录还款", systemImage: "checkmark", action: pay).buttonStyle(.bordered).controlSize(.large) }
                Button(action: edit) { Text("编辑账单").frame(minHeight: PilotTheme.minimumTouchTarget).contentShape(.rect) }
                    .buttonStyle(.borderless)
            }
            if !payments.isEmpty {
                PilotDisclosureGroup("还款记录 · \(payments.count) 笔") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(payments) { payment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Money.text(payment.amountCents, currency: statement.currency)).font(.subheadline.weight(.medium))
                                HStack {
                                    Text(payment.date, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button(role: .destructive) { undoing = payment } label: {
                                        Text("撤销").frame(minHeight: PilotTheme.minimumTouchTarget).contentShape(.rect)
                                    }.buttonStyle(.borderless)
                                }
                            }
                        }
                    }.padding(.top, 12)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button("编辑账单", systemImage: "pencil", action: edit)
            Button("删除账单", systemImage: "trash", role: .destructive) { deleting = true }
        }
        .swipeActions(allowsFullSwipe: false) {
            Button("删除账单", systemImage: "trash", role: .destructive) { deleting = true }
        }
        .confirmationDialog("删除这期账单及其还款记录？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除账单", role: .destructive, action: remove)
        } message: { Text("不会删除消费记录，也不会向银行发起操作。") }
        .confirmationDialog("撤销这笔还款记录？", isPresented: undoConfirmation, titleVisibility: .visible) {
            Button("撤销还款记录", role: .destructive) {
                if let undoing { removePayment(undoing) }
                undoing = nil
            }
        } message: { Text("这只会修改本地记录，不会向银行发起操作。") }
    }

    private var undoConfirmation: Binding<Bool> {
        Binding(get: { undoing != nil }, set: { if !$0 { undoing = nil } })
    }
}
