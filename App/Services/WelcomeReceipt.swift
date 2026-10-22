import Foundation

struct WelcomeReceipt: Codable, Equatable, Sendable {
    var received: Bool
    var receivedOn: Date?
}
