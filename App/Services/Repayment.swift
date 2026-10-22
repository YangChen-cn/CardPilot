import Foundation

struct Repayment: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var statementID: UUID
    var amountCents: Int64
    var date: Date
}
