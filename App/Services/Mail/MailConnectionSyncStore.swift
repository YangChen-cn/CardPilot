import Foundation
import SwiftData

@MainActor enum MailConnectionSyncStore {
    static func save(_ connection: MailCloudConnection, in context: ModelContext) throws {
        let value = MailConnectionBackup(connection: connection)
        guard value.isValid else { throw PilotError.invalid("邮件连接资料无效。") }
        let old = try DocumentStore.load(MailConnectionBackup.self, key: MailConnectionBackup.key, in: context)
        guard old?.connection?.url != connection.url || old?.connection?.token != connection.token else { return }
        try Persistence.save(context) {
            try DocumentStore.put(value, key: MailConnectionBackup.key, kind: "mailConnectionBackup", in: context)
        }
    }

    /// Read remote settings first; an old device must not overwrite a newer connection.
    static func refresh(in context: ModelContext) {
        guard !RuntimeMode.isEphemeral, !MailCloudController.shared.ignoresSyncedConnection, !MailCloudController.shared.isSyncing else { return }
        do {
            try reconcile(in: context, load: MailCloudConnectionStore.load, apply: MailCloudController.shared.restoreConnection)
        } catch { MailCloudController.shared.connectionSyncFailed() }
    }

    static func reconcile(in context: ModelContext, load: () throws -> MailCloudConnection?,
                          apply: (MailCloudConnection) throws -> Void) throws {
            if let value = try DocumentStore.load(MailConnectionBackup.self, key: MailConnectionBackup.key, in: context),
               let connection = value.connection {
                let local = try load()
                if local?.url != connection.url || local?.token != connection.token {
                    try apply(connection)
                }
            } else if let local = try load() {
                try save(local, in: context)
            }
    }
}
