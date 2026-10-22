import Foundation
import SwiftData

@MainActor enum CardOrderStore {
    static let key = "cardOrder"

    static func load(context: ModelContext) -> [String] {
        (try? DocumentStore.load(CardOrder.self, key: key, in: context))?.keys ?? []
    }

    static func save(_ keys: [String], context: ModelContext) throws {
        var seen: Set<String> = []
        let unique = keys.filter { key in
            key.hasPrefix("card:") && key.count <= 600 && seen.insert(key).inserted
        }
        try Persistence.save(context) {
            try DocumentStore.put(CardOrder(keys: unique), key: key, kind: "cardOrder", in: context)
        }
    }

    static func ordered(_ cards: [BankCard], context: ModelContext) -> [BankCard] {
        ordered(cards, keys: load(context: context))
    }

    static func ordered(_ cards: [BankCard], keys: [String]) -> [BankCard] {
        let current = Set(cards.map(\.syncKey))
        var rank: [String: Int] = [:]
        for (index, key) in keys.enumerated() where current.contains(key) && rank[key] == nil {
            rank[key] = index
        }
        return cards.sorted { left, right in
            switch (rank[left.syncKey], rank[right.syncKey]) {
            case let (leftRank?, rightRank?):
                if leftRank != rightRank { return leftRank < rightRank }
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
            return left.syncKey < right.syncKey
        }
    }

    /// Returns the new order, or nil when the move is invalid/no-op.
    static func moved(_ keys: [String], source: String, target: String, after: Bool) -> [String]? {
        guard source != target,
              let sourceIndex = keys.firstIndex(of: source) else { return nil }
        var result = keys
        result.remove(at: sourceIndex)
        guard let targetIndex = result.firstIndex(of: target) else { return nil }
        result.insert(source, at: after ? targetIndex + 1 : targetIndex)
        return result == keys ? nil : result
    }
}
