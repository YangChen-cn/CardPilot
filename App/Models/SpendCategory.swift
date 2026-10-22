import Foundation

enum SpendCategory: String, Codable, CaseIterable, Identifiable {
    case dining = "餐饮"
    case groceries = "超市"
    case shopping = "购物"
    case transport = "交通"
    case travel = "旅行"
    case bills = "缴费"
    case entertainment = "娱乐"
    case other = "其他"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .dining: "fork.knife"
        case .groceries: "basket"
        case .shopping: "bag"
        case .transport: "tram"
        case .travel: "airplane"
        case .bills: "doc.text"
        case .entertainment: "play.tv"
        case .other: "square.grid.2x2"
        }
    }
}
