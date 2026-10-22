import CryptoKit
import Foundation
import Security

/// This executable has no UI or ledger dependency. Its code hash must stay unchanged
/// when the main app changes, because legacy macOS keychain partitions use that hash
/// for self-signed applications. Only the same-certificate CardPilot parent may call it.
@main enum MailKeychainMain {
    private static let service = "com.cardpilot.bank-mail-cloud"
    private static let account = "connection"
    private static let flags = SecCSFlags(rawValue: 0)

    static func main() {
        guard trustedParent() else { reply(MailKeychainReply(status: -70001)); return }
        do {
            var input = Data()
            while let chunk = try FileHandle.standardInput.read(upToCount: 4096), !chunk.isEmpty {
                input.append(chunk)
                guard input.count <= 16_384 else { reply(MailKeychainReply(status: errSecParam)); return }
            }
            let request = try JSONDecoder().decode(MailKeychainMessage.self, from: input)
            reply(perform(request))
        } catch { reply(MailKeychainReply(status: errSecParam)) }
    }

    private static func trustedParent() -> Bool {
        var parent: SecCode?
        guard getppid() > 1,
              let info = signingInfo(), info[kSecCodeInfoIdentifier as String] as? String == "com.cardpilot.mail-keychain",
              let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else { return false }
        let digest = Insecure.SHA1.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
        let text = "identifier \"com.cardpilot.app.mac\" and certificate leaf = H\"\(digest)\""
        var requirement: SecRequirement?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: getppid())]
        guard SecRequirementCreateWithString(text as CFString, flags, &requirement) == errSecSuccess,
              let requirement,
              SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, flags, &parent) == errSecSuccess,
              let parent else { return false }
        return SecCodeCheckValidity(parent, flags, requirement) == errSecSuccess
    }

    private static func signingInfo() -> [String: Any]? {
        var ownCode: SecCode?, ownStaticCode: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf(flags, &ownCode) == errSecSuccess, let ownCode,
              SecCodeCopyStaticCode(ownCode, flags, &ownStaticCode) == errSecSuccess, let ownStaticCode,
              SecCodeCopySigningInformation(ownStaticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess else { return nil }
        return info as? [String: Any]
    }

    private static func perform(_ request: MailKeychainMessage) -> MailKeychainReply {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: account]
        switch request.operation {
        case .probe:
            // Authenticated transport test only; never queries the keychain.
            let hash = (signingInfo()?[kSecCodeInfoUnique as String] as? Data)?.map { String(format: "%02x", $0) }.joined()
            return MailKeychainReply(status: errSecSuccess, codeHash: hash)
        case .load:
            var lookup = query
            lookup[kSecReturnData as String] = true
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(lookup as CFDictionary, &item)
            return MailKeychainReply(status: status, data: item as? Data)
        case .save:
            guard let data = request.data, data.count <= 8192 else { return MailKeychainReply(status: errSecParam) }
            var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var insert = query
                insert[kSecValueData as String] = data
                insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(insert as CFDictionary, nil)
            }
            return MailKeychainReply(status: status)
        case .remove:
            return MailKeychainReply(status: SecItemDelete(query as CFDictionary))
        }
    }

    private static func reply(_ value: MailKeychainReply) {
        // The only secret output is an anonymous pipe to the verified app parent.
        if let data = try? JSONEncoder().encode(value) { try? FileHandle.standardOutput.write(contentsOf: data) }
    }
}
