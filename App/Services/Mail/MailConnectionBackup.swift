import Foundation

/// Personal connection settings travel with the user's chosen sync folder.
struct MailConnectionBackup: Codable, Sendable {
    static let key = "mailConnectionBackup"
    let version: Int
    let connection: MailCloudConnection?
    // Passive decoding of an already-saved obsolete backup; never asks for a password.
    let salt: Data?
    let ciphertext: Data?

    init(connection: MailCloudConnection) {
        version = 2; self.connection = connection; salt = nil; ciphertext = nil
    }

    var isValid: Bool {
        if version == 2, let connection {
            return connection.url.count <= 2048 && (try? connection.validatedURL()) != nil
        }
        return version == 1 && salt?.count == 16 && (29...16_384).contains(ciphertext?.count ?? 0)
    }
}
