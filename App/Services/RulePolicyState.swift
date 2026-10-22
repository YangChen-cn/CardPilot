import Foundation

struct RulePolicyState: Codable, Equatable, Sendable {
    var currentSince = Date.distantPast
    var history: [RuleRevision] = []
    var extras = RuleExtras()
    var baseline: RuleSyncData?
    var customized = false
    var pending: RuleSyncData?
    var pendingExtras: RuleExtras?
    var archived = false
    var current: RuleSyncData?
    /// Version 2 records an explicit effective date, separate from the document edit timestamp.
    var timelineVersion: Int?
    /// Optional so older synchronized policy documents continue to decode.
    var retired: Bool?
    var enabledBeforeRetirement: Bool?

    var isRetired: Bool { retired ?? false }
}
