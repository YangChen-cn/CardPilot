import Foundation
import SwiftData

/// Typed domain documents evolve independently of the core card/transaction schema.
@Model
final class DomainRecord {
    @Attribute(.unique) var key: String
    var kind: String
    var content: Data
    var modifiedAt: Date
    var isDeleted: Bool
    init(key: String, kind: String, content: Data, modifiedAt: Date = .now, isDeleted: Bool = false) {
        self.key = key; self.kind = kind; self.content = content
        self.modifiedAt = modifiedAt; self.isDeleted = isDeleted
    }
}
