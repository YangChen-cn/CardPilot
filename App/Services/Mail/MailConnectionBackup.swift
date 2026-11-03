import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Only this authenticated ciphertext enters folder sync. Passwords and plaintext never do.
struct MailConnectionBackup: Codable, Sendable {
    static let key = "mailConnectionBackup"
    let version: Int
    let salt: Data
    let ciphertext: Data
    var isValid: Bool { version == 1 && salt.count == 16 && (29...16_384).contains(ciphertext.count) }

    static func encrypt(_ connection: MailCloudConnection, password: String) throws -> Self {
        guard password.count >= 12, password.utf8.count <= 1024, connection.url.count <= 2048 else {
            throw PilotError.invalid("恢复密码至少12个字符，请使用独立的长密码并妥善保存。")
        }
        _ = try connection.validatedURL()
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw PilotError.invalid("暂时无法创建加密备份，请重试。") }
        let key = try derive(password: password, salt: salt)
        let sealed = try AES.GCM.seal(JSONEncoder().encode(connection), using: key)
        guard let data = sealed.combined else { throw PilotError.invalid("暂时无法加密连接。") }
        return Self(version: 1, salt: salt, ciphertext: data)
    }

    func decrypt(password: String) throws -> MailCloudConnection {
        guard isValid, password.count >= 12, password.utf8.count <= 1024 else { throw PilotError.invalid("请填写正确的恢复密码。") }
        do {
            let key = try Self.derive(password: password, salt: salt)
            let data = try AES.GCM.open(AES.GCM.SealedBox(combined: ciphertext), using: key)
            let connection = try JSONDecoder().decode(MailCloudConnection.self, from: data)
            _ = try connection.validatedURL()
            return connection
        } catch { throw PilotError.invalid("恢复密码不正确，或云端备份已损坏。本机连接未更改。") }
    }

    private static func derive(password: String, salt: Data) throws -> SymmetricKey {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = password.withCString { characters in
            salt.withUnsafeBytes { buffer in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), characters, password.utf8.count,
                    buffer.bindMemory(to: UInt8.self).baseAddress!, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 310_000, &bytes, 32)
            }
        }
        guard status == kCCSuccess else { throw PilotError.invalid("暂时无法解密连接，请重试。") }
        defer { _ = bytes.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        return SymmetricKey(data: bytes)
    }
}
