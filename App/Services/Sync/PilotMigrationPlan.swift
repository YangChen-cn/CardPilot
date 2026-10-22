import SwiftData

enum PilotMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LegacySchemaV1.self, LocalSchemaV2.self, LocalSchemaV3.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: LegacySchemaV1.self, toVersion: LocalSchemaV2.self),
         .lightweight(fromVersion: LocalSchemaV2.self, toVersion: LocalSchemaV3.self)]
    }
}
