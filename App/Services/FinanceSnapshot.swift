import Foundation

struct FinanceSnapshot: Sendable {
    var groups: [CreditGroup] = []
    var statements: [BillingStatement] = []
    var payments: [Repayment] = []
    func unpaid(_ statement: BillingStatement, now: Date = .now) -> Int64 {
        max(0, statement.amountCents - payments.filter { $0.statementID == statement.id && $0.date <= now }.reduce(0) { $0 + $1.amountCents })
    }
    func available(_ group: CreditGroup, transactions: [SpendTransaction], now: Date = .now) -> Int64 {
        var keys: [UUID: String] = [:]
        for transaction in transactions { if let card = transaction.card { keys[card.id] = card.syncKey } }
        return available(group, inputs: transactions.map(SpendInput.init), cardKeys: keys, now: now)
    }
    func hasUnvaluedSpending(_ group: CreditGroup, inputs: [SpendInput], cardKeys: [UUID: String], now: Date) -> Bool {
        inputs.contains { input in
            input.date <= now && !input.hasHKDValuation && input.cardID.flatMap { cardKeys[$0] }.map { group.cardKeys.contains($0) } == true
        }
    }
    func available(_ group: CreditGroup, inputs: [SpendInput], cardKeys: [UUID: String], now: Date = .now) -> Int64 {
        let used = group.cardKeys.reduce(Int64(0)) { total, cardKey in
            let all = statements.filter { $0.cardKey == cardKey && $0.periodEnd <= now }
            let spending = inputs.filter { $0.cardID.flatMap { cardKeys[$0] } == cardKey && $0.date <= now }
            let currencies = Set(all.map(\.currency) + spending.map(\.currency))
            return total + currencies.reduce(Int64(0)) { currencyTotal, currency in
                let bills = all.filter { $0.currency == currency }
                let latest = bills.max { $0.periodEnd < $1.periodEnd }
                let cutoff = latest.map { HKCalendar.start($0.periodEnd).addingTimeInterval(86400) } ?? .distantPast
                let unbilled = spending.filter { $0.currency == currency && $0.date >= cutoff }.reduce(Int64(0)) { $0 + $1.hkdCents }
                let repayments = payments.filter { payment in
                    bills.contains { $0.id == payment.statementID } && payment.date <= now && payment.date >= cutoff
                }.reduce(Int64(0)) { total, payment in
                    guard let bill = bills.first(where: { $0.id == payment.statementID }) else { return total }
                    return total + Money.convert(payment.amountCents, rate: bill.currency == "HKD" ? "1" : bill.exchangeRate)
                }
                return currencyTotal + max(0, (latest?.hkdCents ?? 0) + unbilled - repayments)
            }
        }
        return group.limitCents - used
    }
}
