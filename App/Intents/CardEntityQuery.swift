import AppIntents
import SwiftData

struct CardEntityQuery: EntityQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [CardEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    @MainActor func suggestedEntities() async throws -> [CardEntity] {
        let context = try Persistence.live.get().mainContext
        return try context.fetch(FetchDescriptor<BankCard>()).filter { !$0.isArchived }
            .map { CardEntity(id: $0.syncKey, name: $0.displayName + ($0.lastFour.isEmpty ? "" : " · " + $0.lastFour)) }
    }
}
