import Foundation

enum BillingDates {
    /// Fixed monthly dates are personal reminders, not an inferred bank statement cycle.
    static func date(day: Int, inMonth month: Date) -> Date? {
        guard (1...31).contains(day),
              let start = HKCalendar.calendar.dateInterval(of: .month, for: month)?.start,
              let days = HKCalendar.calendar.range(of: .day, in: .month, for: start)?.count else { return nil }
        return HKCalendar.calendar.date(byAdding: .day, value: min(day, days) - 1, to: start)
    }

    static func next(day: Int, now: Date = .now) -> Date? {
        guard (1...31).contains(day) else { return nil }
        return HKCalendar.nextDay(day, now: now)
    }

    static func dueDate(after closing: Date, day: Int) -> Date? {
        guard let sameMonth = date(day: day, inMonth: closing) else { return nil }
        if sameMonth > HKCalendar.start(closing) { return sameMonth }
        guard let nextMonth = HKCalendar.calendar.date(byAdding: .month, value: 1, to: closing) else { return nil }
        return date(day: day, inMonth: nextMonth)
    }

    static func status(due: Date, paid: Bool, now: Date = .now) -> String {
        if paid { return "已记录还清" }
        let days = HKCalendar.daysLeft(due, now: now)
        if days < 0 { return "已过期 \(-days) 天" }
        return days == 0 ? "今天到期" : "\(days) 天后到期"
    }
}
