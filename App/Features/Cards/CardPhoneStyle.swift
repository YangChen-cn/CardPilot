import Foundation

/// iPhone-only presentation choices. Card faces remain the default; the
/// compact list and deck are opt-in so desktop layouts are untouched.
enum CardPhoneStyle: String, CaseIterable, Identifiable, Sendable {
    case faces
    case compact
    case deck

    var id: String { rawValue }

    var label: String {
        switch self {
        case .faces: "卡面展示"
        case .compact: "紧凑列表"
        case .deck: "叠放卡包"
        }
    }

    var symbol: String {
        switch self {
        case .faces: "creditcard"
        case .compact: "list.bullet"
        case .deck: "rectangle.stack"
        }
    }
}
