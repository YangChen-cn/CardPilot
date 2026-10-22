import Foundation

struct WelcomeAddonRecord: Codable, Sendable {
    var planID: String
    var ruleIDs: [String]
    var confirmedEligibility: Bool
    var received: Bool
    var receivedOn: Date?
    var applicationChannel: String
    var startsOn: Date
    var endsOn: Date
}
