import Foundation

enum Currency: String, Codable, CaseIterable, Identifiable {
    case HKD, CNY, USD
    var id: String { rawValue }
}
