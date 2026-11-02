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
    private let initial: BillingStatement
    private let isNew: Bool

    init(statement: BillingStatement? = nil, card: BankCard? = nil) {
        var value = statement ?? BillingStatement(cardKey: card?.syncKey ?? "", amountCents: 0, currency: "HKD", exchangeRate: "1", periodEnd: HKCalendar.start(.now), dueDate: HKCalendar.start(.now))
        if statement == nil, let card { Self.prepareDates(&value, card: card) }
        initial = value
        isNew = statement == nil
        _statement = State(initialValue: value); _amount = State(initialValue: Decimal(value.amountCents) / 100)
        _rate = State(initialValue: Decimal(string: value.exchangeRate) ?? 0)
    }

    private var selectableCards: [BankCard] {
        cards.filter { (!$0.isArchived && !$0.isDebitCard) || $0.syncKey == initial.cardKey }
    }

    private var hasChanges: Bool {
        statement != initial || amount != Decimal(initial.amountCents) / 100 || rate != (Decimal(string: initial.exchangeRate) ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("银行账单") {
                    Picker("银行卡", selection: $statement.cardKey) {
                    Text("请选择").tag("")
                        ForEach(selectableCards) { Text($0.displayName).tag($0.syncKey) }
                    }
                    TextField("账单总金额", value: $amount, format: .number)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Picker("账单币种", selection: $statement.currency) { ForEach(Currency.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                }
                Section {
                    DatePicker("账单截止日", selection: $statement.periodEnd, displayedComponents: .date)
                    DatePicker("还款截止日", selection: $statement.dueDate, displayedComponents: .date)
                } footer: { Text("请按银行账单填写实际日期；个人常用日期仅用于预填。") }
                if statement.currency != "HKD" {
                    Section {
                        TextField("1 \(statement.currency) = HKD", value: $rate, format: .number)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    } header: { Text("港币参考汇率（选填）") } footer: {
                        Text("填 0 表示未提供。账单和还款均按原币记录，不影响提醒。")
                    }
                }
                if let message { Section { Text(message).foregroundStyle(.red) } }
            }
            .formStyle(.grouped).navigationTitle("记录账单")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DiscardChangesButton(hasChanges: hasChanges, discard: { dismiss() }) }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
        }.editorSize()
        .interactiveDismissDisabled(hasChanges)
        .onChange(of: statement.currency) { _, new in rate = new == "HKD" ? 1 : 0 }
        .onChange(of: statement.cardKey) { _, key in
            if isNew, let card = cards.first(where: { $0.syncKey == key }) { Self.prepareDates(&statement, card: card) }
        }
    }
    private func save() {
        guard selectableCards.contains(where: { $0.syncKey == statement.cardKey }), !amount.isNaN, amount >= 0, amount <= Money.maxAmount,
              !rate.isNaN, rate >= 0, rate <= 1000 else { message = "请选择银行卡并填写有效金额。"; return }
        statement.amountCents = Money.cents(amount); statement.exchangeRate = statement.currency == "HKD" ? "1" : rate == 0 ? "" : rate.description
        do { try Persistence.save(context) { try FinanceStore.save(statement, context: context) }; dismiss() }
        catch { message = PilotError.message(error) }
    }

    private static func prepareDates(_ statement: inout BillingStatement, card: BankCard) {
        let calendar = HKCalendar.calendar
        if let date = BillingDates.date(day: card.statementDay, inMonth: .now) {
            if date <= HKCalendar.start(.now) { statement.periodEnd = date }
            else if let month = calendar.date(byAdding: .month, value: -1, to: .now),
                    let previous = BillingDates.date(day: card.statementDay, inMonth: month) { statement.periodEnd = previous }
        }
        statement.dueDate = BillingDates.dueDate(after: statement.periodEnd, day: card.paymentDay) ?? statement.periodEnd
    }
}
