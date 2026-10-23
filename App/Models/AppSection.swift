import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case cards = "我的卡片"
    case dashboard = "总览"
    case offers = "权益与迎新"
    case transactions = "交易账本"
    case recommend = "选卡建议"
    case settings = "设置"
    var id: String { rawValue }

    /// Short titles used by the iPhone tab bar and navigation bars. The longer
    /// `rawValue` remains the descriptive label in the macOS sidebar.
    var navigationTitle: String {
        switch self {
        case .cards: "卡片"
        case .dashboard: "总览"
        case .offers: "优惠"
        case .transactions: "账本"
        case .recommend: "推荐"
        case .settings: "设置"
        }
    }

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
