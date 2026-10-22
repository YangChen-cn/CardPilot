import Foundation
import SwiftData

@Model
final class SyncTombstone {
    @Attribute(.unique) var key: String
    var deletedAt: Date
    init(key: String, deletedAt: Date) { self.key = key; self.deletedAt = deletedAt }
}
