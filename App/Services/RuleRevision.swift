import Foundation

struct RuleRevision: Codable, Equatable, Sendable {
    var since: Date
    var until: Date
    var value: RuleSyncData
    var extras: RuleExtras
}
