import Foundation
import SwiftData

@MainActor enum Persistence {
    static let schema = Schema(versionedSchema: LocalSchemaV3.self)
    static let live = Result { try makeContainer() }
    static let didChange = Notification.Name("CardPilotDataChanged")

    static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration("CardPilot", schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration("CardPilot", schema: schema,
                                               isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        if !inMemory { try StoreBackup.beforeFirstUpgrade(storeURL: configuration.url) }
        return try ModelContainer(for: schema, migrationPlan: PilotMigrationPlan.self, configurations: [configuration])
    }

    @MainActor static func save(_ context: ModelContext, mutation: () throws -> Void) throws {
        do { try mutation(); try context.save(); notifyChange() }
        catch { context.rollback(); throw error }
    }

    static func notifyChange() { NotificationCenter.default.post(name: didChange, object: nil) }

    static func setProfileRevision(cardKey: String, date: Date, context: ModelContext, advancing: Bool = false) throws {
        let key = "profile.modified." + cardKey
        let millis = Int64((date.timeIntervalSince1970 * 1000).rounded())
        if let metadata = try context.fetch(FetchDescriptor<AppMetadata>(predicate: #Predicate { $0.key == key })).first {
            metadata.value = String(advancing ? max(millis, (Int64(metadata.value) ?? 0) + 1) : millis)
        } else { context.insert(AppMetadata(key: key, value: String(millis))) }
    }

    static func markDeleted(key: String, context: ModelContext, now: Date = .now) {
        let existing = try? context.fetch(FetchDescriptor<SyncTombstone>(predicate: #Predicate { $0.key == key })).first
        if let existing { existing.deletedAt = now }
        else { context.insert(SyncTombstone(key: key, deletedAt: now)) }
    }

    static func remove(_ card: BankCard, context: ModelContext) {
        markDeleted(key: card.syncKey, context: context)
        for rule in card.rules { markDeleted(key: rule.syncKey, context: context) }
        for transaction in card.transactions { markDeleted(key: transaction.syncKey, context: context) }
        context.delete(card)
    }

    static func remove(_ rule: RewardRule, context: ModelContext) throws {
        try RulePolicyStore.archive(rule, context: context)
    }

    static func remove(_ transaction: SpendTransaction, context: ModelContext) {
        markDeleted(key: transaction.syncKey, context: context); context.delete(transaction)
    }
}
