import SwiftData

enum LocalSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [BankCard.self, RewardRule.self, SpendTransaction.self, AppMetadata.self, SyncTombstone.self, DomainRecord.self]
    }
}
