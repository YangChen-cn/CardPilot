import Foundation

struct MailKeychainReply: Codable, Sendable {
    var status: Int32
    var data: Data? = nil
    var codeHash: String? = nil
}
