import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case cards = "我的卡片"
    case dashboard = "总览"
    case offers = "权益与迎新"
    case transactions = "交易账本"
    case recommend = "选卡建议"
    case settings = "设置"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .cards: "creditcard"
        case .offers: "gift"
        case .transactions: "list.bullet.rectangle"
        case .recommend: "sparkles"
        case .settings: "gearshape"
        }
    }
}
