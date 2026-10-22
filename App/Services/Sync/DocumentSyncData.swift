import Foundation

struct DocumentSyncData: Codable, Equatable, Sendable {
    var key: String
    var kind: String
    var content: Data
    var isDeleted: Bool
}
