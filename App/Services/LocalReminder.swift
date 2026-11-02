import Foundation

struct LocalReminder: Equatable, Sendable {
    var id: String
    var title: String
    var body: String
    var date: Date
    var route = "billing"
}
