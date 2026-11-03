import Foundation
import SwiftData
import Testing
@testable import CardPilot

@Suite @MainActor struct MailConnectionBackupTests {
    private var connection: MailCloudConnection {
        MailCloudConnection(url: "https://script.google.com/macros/s/fictional-deployment/exec", token: String(repeating: "fictional", count: 12))
    }

    @Test func connectionSyncNeedsNoPasswordAndRepeatedSaveKeepsRevision() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        try MailConnectionSyncStore.save(connection, in: context)
        let record = try #require(try DocumentStore.record(MailConnectionBackup.key, in: context))
        let revision = record.modifiedAt
        try MailConnectionSyncStore.save(connection, in: context)
        #expect(record.modifiedAt == revision)
        let value = try #require(try DocumentStore.load(MailConnectionBackup.self, key: MailConnectionBackup.key, in: context))
        #expect(value.version == 2 && value.isValid)
        #expect(value.connection?.url == connection.url && value.connection?.token == connection.token)
    }

    @Test func connectionSurvivesFolderSyncWithoutTouchingRealKeychains() throws {
        let a = try Persistence.makeContainer(inMemory: true), b = try Persistence.makeContainer(inMemory: true)
        try MailConnectionSyncStore.save(connection, in: a.mainContext)
        let records = try SyncStore.records(a.mainContext)
        #expect(try SyncStore.apply(records, context: b.mainContext))
        let value = try #require(try DocumentStore.load(MailConnectionBackup.self, key: MailConnectionBackup.key, in: b.mainContext))
        #expect(value.connection?.token == connection.token)
        #expect(try !SyncStore.apply(records, context: b.mainContext))
        let invalid = DocumentSyncData(key: "wrong-key", kind: "mailConnectionBackup", content: try SyncCodec.encoder().encode(value), isDeleted: false)
        #expect(throws: (any Error).self) { try DocumentValidator.validate(invalid) }
    }

    @Test func invalidConnectionRejectedAndEphemeralRunsNeverReadCredentials() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let invalid = MailCloudConnection(url: "http://example.test", token: "invalid")
        #expect(throws: (any Error).self) { try MailConnectionSyncStore.save(invalid, in: container.mainContext) }
        MailConnectionSyncStore.refresh(in: container.mainContext)
        let controller = MailCloudController(allowsSync: false)
        #expect(throws: (any Error).self) { try controller.restoreConnection(connection) }
    }

    @Test func remoteConnectionIsAdoptedWithoutBeingOverwrittenByAnOldDevice() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        try MailConnectionSyncStore.save(connection, in: context)
        let old = MailCloudConnection(url: connection.url, token: String(repeating: "outdated", count: 12))
        var restored: MailCloudConnection?
        try MailConnectionSyncStore.reconcile(in: context, load: { old }, apply: { restored = $0 })
        #expect(restored?.token == connection.token)
        #expect(try DocumentStore.load(MailConnectionBackup.self, key: MailConnectionBackup.key, in: context)?.connection?.token == connection.token)
        var writes = 0
        try MailConnectionSyncStore.reconcile(in: context, load: { connection }, apply: { _ in writes += 1 })
        #expect(writes == 0)
    }

    @Test func existingDeviceConnectionIsAutomaticallyAddedWhenDocumentIsMissing() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        try MailConnectionSyncStore.reconcile(in: context, load: { connection }, apply: { _ in Issue.record("Unexpected keychain replacement") })
        #expect(try DocumentStore.load(MailConnectionBackup.self, key: MailConnectionBackup.key, in: context)?.connection?.url == connection.url)
    }
}
