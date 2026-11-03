import Foundation
import SwiftData
import Testing
@testable import CardPilot

@Suite @MainActor struct MailConnectionBackupTests {
    private let secret = "fictional-recovery-password"
    private var connection: MailCloudConnection {
        MailCloudConnection(url: "https://script.google.com/macros/s/fictional-deployment/exec", token: String(repeating: "fictional", count: 12))
    }

    @Test func authenticatedEncryptionRestoresExactlyAndRandomizesEachBackup() throws {
        let a = try MailConnectionBackup.encrypt(connection, password: secret)
        let b = try MailConnectionBackup.encrypt(connection, password: secret)
        #expect(a.isValid && b.isValid)
        #expect(a.salt != b.salt)
        #expect(a.ciphertext != b.ciphertext)
        let restored = try a.decrypt(password: secret)
        #expect(restored.url == connection.url && restored.token == connection.token)
        let serialized = String(decoding: try JSONEncoder().encode(a), as: UTF8.self)
        #expect(!serialized.contains(connection.url) && !serialized.contains(connection.token) && !serialized.contains(secret))
    }

    @Test func wrongPasswordTamperingAndInvalidParametersCannotRestore() throws {
        let value = try MailConnectionBackup.encrypt(connection, password: secret)
        #expect(throws: (any Error).self) { try value.decrypt(password: "different-recovery-password") }
        var damaged = value.ciphertext
        damaged[damaged.startIndex] ^= 1
        let tampered = MailConnectionBackup(version: 1, salt: value.salt, ciphertext: damaged)
        #expect(throws: (any Error).self) { try tampered.decrypt(password: secret) }
        #expect(throws: (any Error).self) { try MailConnectionBackup.encrypt(connection, password: "short") }
        #expect(!MailConnectionBackup(version: 2, salt: value.salt, ciphertext: value.ciphertext).isValid)
        #expect(!MailConnectionBackup(version: 1, salt: Data(), ciphertext: value.ciphertext).isValid)
    }

    @Test func encryptedDocumentSurvivesFolderSyncWithoutTouchingKeychainOrPreferences() throws {
        let a = try Persistence.makeContainer(inMemory: true), b = try Persistence.makeContainer(inMemory: true)
        let value = try MailConnectionBackup.encrypt(connection, password: secret)
        try DocumentStore.put(value, key: MailConnectionBackup.key, kind: "mailConnectionBackup", in: a.mainContext)
        try a.mainContext.save()
        let records = try SyncStore.records(a.mainContext)
        #expect(try SyncStore.apply(records, context: b.mainContext))
        let synced = try #require(try DocumentStore.load(MailConnectionBackup.self, key: MailConnectionBackup.key, in: b.mainContext))
        #expect(try synced.decrypt(password: secret).token == connection.token)
        #expect(try !SyncStore.apply(records, context: b.mainContext))
        let invalid = DocumentSyncData(key: "wrong-key", kind: "mailConnectionBackup", content: try SyncCodec.encoder().encode(value), isDeleted: false)
        #expect(throws: (any Error).self) { try DocumentValidator.validate(invalid) }
    }

    @Test func ephemeralControllerRejectsRestoringRealDeviceCredentials() throws {
        let controller = MailCloudController(allowsSync: false)
        #expect(throws: (any Error).self) { try controller.restoreConnection(connection) }
        #expect(!controller.isConnected)
    }
}
