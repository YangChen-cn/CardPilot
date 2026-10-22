import Foundation

struct MailKeychainMessage: Codable, Sendable {
    enum Operation: String, Codable, Sendable { case load, save, remove, probe }
    var operation: Operation
    var data: Data? = nil
}

