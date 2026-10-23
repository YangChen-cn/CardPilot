import SwiftUI

/// The phone card wallet has its own preference, independent of the desktop grid.
enum PhoneCardPresentation: String, CaseIterable, Identifiable {
    case featured
    case compact

    var id: Self { self }
    var label: String { self == .featured ? "精选卡片" : "紧凑列表" }
    var symbol: String { self == .featured ? "rectangle.stack" : "list.bullet" }
}
