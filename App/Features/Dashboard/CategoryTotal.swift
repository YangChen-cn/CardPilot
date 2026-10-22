import Foundation

struct CategoryTotal: Identifiable, Sendable {
    let name: String
    let cents: Int64
    var id: String { name }
}
