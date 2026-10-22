import Foundation

struct CardSpendTotal: Identifiable, Sendable {
    let id: UUID?
    let name: String
    let cents: Int64
    let originalTotals: String
    let unvaluedCount: Int
}
