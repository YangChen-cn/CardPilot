import Foundation

struct TransactionDayGroup: Identifiable {
    let date: Date
    let transactions: [SpendTransaction]
    var id: Date { date }
    var totalCents: Int64 { transactions.reduce(0) { $0 + $1.hkdCents } }

    var title: String {
        if HKCalendar.calendar.isDateInToday(date) { return "今天" }
        if HKCalendar.calendar.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }
}
