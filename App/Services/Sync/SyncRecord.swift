import Foundation

struct SyncRecord: Codable, Equatable, Sendable {
    let key: String
    let kind: String
    var revision: Date
    var deleted: Bool
    var cardKey: String?
    var payload: Data?
    var revisionMillis: Int64 { Int64((revision.timeIntervalSince1970 * 1000).rounded()) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key && lhs.kind == rhs.kind && lhs.revisionMillis == rhs.revisionMillis &&
        lhs.deleted == rhs.deleted && lhs.cardKey == rhs.cardKey && lhs.payload == rhs.payload
    }
}
