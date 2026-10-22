import Foundation

struct DayTotal: Identifiable, Sendable {
    let date: Date
    let cents: Int64
    var id: Date { date }
}
