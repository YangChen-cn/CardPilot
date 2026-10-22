import Foundation
import OSLog
import Security

struct MailCloudConnection: Codable, Sendable {
    let url: String
    let token: String

    func validatedURL() throws -> URL {
        guard let value = URLComponents(string: url), value.scheme == "https",
              value.host == "script.google.com", value.user == nil, value.password == nil,
              value.query == nil, value.fragment == nil, value.path.hasPrefix("/macros/s/"),
              value.path.hasSuffix("/exec"), let url = value.url, (64...512).contains(token.count) else {
            throw PilotError.invalid("请填写已部署的 Google 云端服务网址和连接码。")
        }
        return url
    }
}

@MainActor enum MailCloudConnectionStore {
    private static let logger = Logger(subsystem: "com.cardpilot.app", category: "MailKeychain")
    private static let service = "com.cardpilot.bank-mail-cloud"
    private static let account = "connection"
    private static var cachedConnection: MailCloudConnection?
    private static var didLoad = false
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func load() throws -> MailCloudConnection? {
        if didLoad { return cachedConnection }
        #if os(macOS)
        let reply = try MacMailKeychain.perform(MailKeychainMessage(operation: .load))
        let status = reply.status
        let data = reply.data
        #else
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        let data = item as? Data
        #endif
        if status == errSecItemNotFound { didLoad = true; return nil }
        guard status == errSecSuccess, let data else {
            logger.error("Connection read failed: \(status, privacy: .public)")
            #if os(macOS)
            var processCode: SecCode?
            if SecCodeCopySelf(SecCSFlags(rawValue: 0), &processCode) == errSecSuccess,
               let processCode, SecCodeCheckValidity(processCode, SecCSFlags(rawValue: 0), nil) != errSecSuccess {
                throw PilotError.invalid("CardPilot 已更新，请退出并重新打开 App 后重试。")
            }
            throw PilotError.invalid("暂时无法读取邮箱连接。请退出并重新打开 App；若系统询问钥匙串访问，请允许 CardPilot 读取。")
            #else
            if status == errSecInteractionNotAllowed {
                throw PilotError.invalid("暂时无法读取邮箱连接，请解锁设备后重试。")
            }
            throw PilotError.invalid("暂时无法读取邮箱连接，请重新打开 App 后重试。")
            #endif
        }
        let connection = try JSONDecoder().decode(MailCloudConnection.self, from: data)
        cachedConnection = connection; didLoad = true
        return connection
    }

    static func save(_ connection: MailCloudConnection) throws {
        _ = try connection.validatedURL()
        let data = try JSONEncoder().encode(connection)
        #if os(macOS)
        guard try MacMailKeychain.perform(MailKeychainMessage(operation: .save, data: data)).status == errSecSuccess else {
            throw PilotError.invalid("未能安全保存邮箱连接，请稍后重试。")
        }
        #else
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw PilotError.invalid("未能安全保存邮箱连接，请稍后重试。")
            }
        } else if status != errSecSuccess {
            throw PilotError.invalid("未能安全更新邮箱连接，请稍后重试。")
        }
        #endif
        cachedConnection = connection; didLoad = true
    }

    static func remove() throws {
        #if os(macOS)
        let status = try MacMailKeychain.perform(MailKeychainMessage(operation: .remove)).status
        #else
        let status = SecItemDelete(query as CFDictionary)
        #endif
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PilotError.invalid("未能移除邮箱连接，请稍后重试。")
        }
        cachedConnection = nil; didLoad = true
    }
}
