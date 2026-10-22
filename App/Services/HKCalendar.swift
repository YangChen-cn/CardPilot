import Foundation

enum HKCalendar {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        return value
    }
    static func start(_ date: Date) -> Date { calendar.startOfDay(for: date) }
    static func dayAfter(_ date: Date) -> Date { calendar.date(byAdding: .day, value: 1, to: start(date))! }
    static func contains(_ date: Date, from: Date, through: Date) -> Bool {
        date >= start(from) && date < dayAfter(through)
    }
    static func monthKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)"
    }
    static func isThisMonth(_ date: Date, now: Date = .now) -> Bool {
        monthKey(date) == monthKey(now)
    }
    static func statementKey(_ date: Date, closingDay: Int) -> String {
        let month = calendar.dateInterval(of: .month, for: date)!.start
        let days = calendar.range(of: .day, in: .month, for: date)!.count
        let closing = min(days, max(1, closingDay))
        let anchor = calendar.component(.day, from: date) <= closing ? month : calendar.date(byAdding: .month, value: 1, to: month)!
        return monthKey(anchor)
    }
    static func daysLeft(_ date: Date, now: Date = .now) -> Int {
        calendar.dateComponents([.day], from: start(now), to: start(date)).day ?? 0
    }
    static func nextDay(_ day: Int, now: Date = .now) -> Date {
        let startMonth = calendar.dateInterval(of: .month, for: now)!.start
        for offset in 0...1 {
            let month = calendar.date(byAdding: .month, value: offset, to: startMonth)!
            let maxDay = calendar.range(of: .day, in: .month, for: month)!.count
            let date = calendar.date(byAdding: .day, value: min(maxDay, max(1, day)) - 1, to: month)!
            if date >= start(now) { return date }
        }
        return now
    }
}
