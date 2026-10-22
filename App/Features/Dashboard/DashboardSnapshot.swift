import Foundation

/// Recorded spending only. No bank eligibility, rewards, or settlement simulation.
struct DashboardSnapshot: Sendable {
    let monthSpend: Int64
    let monthCount: Int
    let unvaluedCount: Int
    let originalTotals: String
    let categories: [CategoryTotal]
    let monthly: [DayTotal]
    let cardTotals: [CardSpendTotal]

    @MainActor init(cards: [BankCard], transactions: [SpendTransaction], now: Date = .now) {
        self.init(inputs: transactions.map(SpendInput.init), cardNames: Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.name) }), now: now)
    }

    init(inputs: [SpendInput], cardNames: [UUID: String] = [:], now: Date) {
        let month = inputs.filter { HKCalendar.isThisMonth($0.date, now: now) && $0.date <= now }
        let valued = month.filter(\.hasHKDValuation)
        monthSpend = valued.reduce(0) { $0 + $1.hkdCents }
        monthCount = month.count
        unvaluedCount = month.count - valued.count
        originalTotals = OriginalCurrencyTotals.text(month)
        categories = Dictionary(grouping: valued, by: \.category).map { name, values in
            CategoryTotal(name: name, cents: values.reduce(0) { $0 + $1.hkdCents })
        }.filter { $0.cents > 0 }.sorted { $0.cents > $1.cents }
        let start = HKCalendar.calendar.dateInterval(of: .month, for: now)?.start ?? now
        monthly = (-5...0).compactMap { offset in
            guard let date = HKCalendar.calendar.date(byAdding: .month, value: offset, to: start),
                  let period = HKCalendar.calendar.dateInterval(of: .month, for: date) else { return nil }
            let sum = inputs.filter { $0.date <= now && $0.date >= period.start && $0.date < period.end && $0.hasHKDValuation }
                .reduce(Int64(0)) { $0 + $1.hkdCents }
            return DayTotal(date: date, cents: sum)
        }
        cardTotals = Dictionary(grouping: month, by: \.cardID).map { id, values in
            CardSpendTotal(id: id, name: id.flatMap { cardNames[$0] } ?? "未关联卡片",
                           cents: values.filter(\.hasHKDValuation).reduce(0) { $0 + $1.hkdCents },
                           originalTotals: OriginalCurrencyTotals.text(values),
                           unvaluedCount: values.filter { !$0.hasHKDValuation }.count)
        }.sorted { $0.cents != $1.cents ? $0.cents > $1.cents : $0.name < $1.name }
    }
}
