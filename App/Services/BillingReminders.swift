import Foundation

@MainActor enum BillingReminders {
    /// A small rolling calendar. Real statements replace the monthly fallback in their due month.
    static func plan(cards: [BankCard], finance: FinanceSnapshot, now: Date = .now) -> [LocalReminder] {
        let calendar = HKCalendar.calendar
        guard let start = calendar.dateInterval(of: .month, for: now)?.start else { return [] }
        var result: [LocalReminder] = []
        for card in cards where !card.isArchived && !card.isDebitCard {
            guard let preferences = finance.billingPreferences[card.syncKey], preferences.isValid else { continue }
            let bills = finance.statements.filter { $0.cardKey == card.syncKey }
            for offset in 0..<6 {
                guard let month = calendar.date(byAdding: .month, value: offset, to: start) else { continue }
                if preferences.statementReminder, let date = BillingDates.date(day: card.statementDay, inMonth: month) {
                    append(date, kind: "statement", title: "查看本月账单", body: "\(card.name)：已到你设置的账单日，可记录账单金额与实际还款日。")
                }
                guard preferences.paymentReminder else { continue }
                let known = bills.filter { HKCalendar.isThisMonth($0.dueDate, now: month) }
                if known.isEmpty {
                    if let date = BillingDates.date(day: card.paymentDay, inMonth: month) {
                        payment(date, actual: false)
                    }
                } else {
                    let dates = Set(known.filter { finance.unpaid($0, now: now) > 0 }.map { HKCalendar.start($0.dueDate) })
                    for date in dates.sorted() { payment(date, actual: true) }
                }
            }

            func payment(_ date: Date, actual: Bool) {
                let body = actual ? "\(card.name)：有已记录账单待还，请核对银行账单并在还款后更新记录。"
                    : "\(card.name)：临近你设置的还款日，请查看银行账单。本提醒不代表已有欠款。"
                append(date, kind: "payment", title: actual ? "账单今天到期" : "查看本月还款", body: body)
                if preferences.advanceDays > 0,
                   let early = calendar.date(byAdding: .day, value: -preferences.advanceDays, to: date) {
                    append(early, kind: "payment-early", title: "还款日前 \(preferences.advanceDays) 天", body: body)
                }
            }

            func append(_ day: Date, kind: String, title: String, body: String) {
                guard let date = calendar.date(bySettingHour: preferences.hour, minute: preferences.minute, second: 0, of: day), date > now else { return }
                let dayID = Int(HKCalendar.start(day).timeIntervalSince1970)
                result.append(LocalReminder(id: "cardpilot.billing.\(card.syncKey).\(kind).\(dayID)", title: title, body: body, date: date))
            }
        }
        return result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}
