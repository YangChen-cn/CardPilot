import Foundation

/// Stored `BankCard.kind` values stay stable for existing data and sync.
enum CardKind: String, CaseIterable, Identifiable, Sendable {
    case credit = "信用卡"
    case debit = "借记卡"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .credit: "信用卡"
        case .debit: "扣账卡"
        }
    }

    static func normalized(_ value: String) -> CardKind {
        value == CardKind.debit.rawValue ? .debit : .credit
    }
}

enum CardDisplayMode: String, CaseIterable, Identifiable {
    case together
    case grouped

    var id: String { rawValue }

    var label: String {
        switch self {
        case .together: "一起显示"
        case .grouped: "按类型分类"
        }
    }
}

extension BankCard {
    var cardKind: CardKind { CardKind.normalized(kind) }
    var kindLabel: String { cardKind.label }
    var isDebitCard: Bool { cardKind == .debit }
}
