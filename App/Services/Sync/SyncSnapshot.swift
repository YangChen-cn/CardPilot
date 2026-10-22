import Foundation

struct SyncSnapshot: Codable, Equatable, Sendable {
    var format = "cardpilot.sync"
    var version = 2
    var deviceID: UUID
    var updatedAt: Date
    var records: [SyncRecord]
}
