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

    static func historyStart(now: Date) -> Date {
        let calendar = HKCalendar.calendar
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return calendar.date(byAdding: .month, value: -5, to: month) ?? month
    }

    @MainActor init(cards: [BankCard], transactions: [SpendTransaction], now: Date = .now) {
        self.init(inputs: transactions.map(SpendInput.init), cardNames: Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.name) }), now: now)
    }

    init(inputs: [SpendInput], cardNames: [UUID: String] = [:], now: Date) {
        let calendar = HKCalendar.calendar
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let firstMonth = Self.historyStart(now: now)
        let months = (-5...0).compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
        var month: [SpendInput] = []
        var spend: Int64 = 0
        var unvalued = 0
        var byMonth: [Date: Int64] = [:]
        var byCategory: [String: Int64] = [:]
        var byCard: [UUID?: Int64] = [:]
        var unvaluedByCard: [UUID?: Int] = [:]
        var cardInputs: [UUID?: [SpendInput]] = [:]

        // One pass across the bounded history, converting each valued amount once.
        for input in inputs where input.date >= firstMonth && input.date <= now {
            let hasValue = input.hasHKDValuation
            let cents = hasValue ? input.hkdCents : 0
            if hasValue, let monthStart = calendar.dateInterval(of: .month, for: input.date)?.start {
                byMonth[monthStart, default: 0] += cents
            }
            guard input.date >= start else { continue }
            month.append(input)
            cardInputs[input.cardID, default: []].append(input)
            if hasValue {
                spend += cents
                byCategory[input.category, default: 0] += cents
                byCard[input.cardID, default: 0] += cents
            } else {
                unvalued += 1
                unvaluedByCard[input.cardID, default: 0] += 1
            }
        }
        monthSpend = spend
        monthCount = month.count
        unvaluedCount = unvalued
        originalTotals = OriginalCurrencyTotals.text(month)
        categories = byCategory.map { CategoryTotal(name: $0.key, cents: $0.value) }
            .filter { $0.cents > 0 }.sorted { $0.cents > $1.cents }
        monthly = months.map { DayTotal(date: $0, cents: byMonth[$0, default: 0]) }
        cardTotals = cardInputs.map { id, values in
            CardSpendTotal(id: id, name: id.flatMap { cardNames[$0] } ?? "未关联卡片",
                           cents: byCard[id, default: 0],
                           originalTotals: OriginalCurrencyTotals.text(values),
                           unvaluedCount: unvaluedByCard[id, default: 0])
        }.sorted { $0.cents != $1.cents ? $0.cents > $1.cents : $0.name < $1.name }
    }
}
