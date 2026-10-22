import Foundation

struct WelcomePlan: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let details: String
    let sourceURL: String
    let ruleIDs: [String]
    let applicationChannels: [String]
    let verified: Bool
    var calculable: Bool = true
    var applicationStartsOn: String?
    var applicationEndsOn: String?
    var periodType: String?
    var periodCount: Int?
    var kind = "main"
    var exclusionGroup: String?
    var isAddon: Bool { kind == "addon" }

    private enum CodingKeys: String, CodingKey {
        case id, title, details, sourceURL, ruleIDs, applicationChannels, verified, calculable
        case applicationStartsOn, applicationEndsOn, periodType, periodCount
        case kind, exclusionGroup
    }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); title = try c.decode(String.self, forKey: .title)
        details = try c.decode(String.self, forKey: .details); sourceURL = try c.decode(String.self, forKey: .sourceURL)
        ruleIDs = try c.decodeIfPresent([String].self, forKey: .ruleIDs) ?? []
        applicationChannels = try c.decodeIfPresent([String].self, forKey: .applicationChannels) ?? []
        verified = try c.decode(Bool.self, forKey: .verified)
        calculable = try c.decodeIfPresent(Bool.self, forKey: .calculable) ?? true
        applicationStartsOn = try c.decodeIfPresent(String.self, forKey: .applicationStartsOn)
        applicationEndsOn = try c.decodeIfPresent(String.self, forKey: .applicationEndsOn)
        periodType = try c.decodeIfPresent(String.self, forKey: .periodType)
        periodCount = try c.decodeIfPresent(Int.self, forKey: .periodCount)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "main"
        exclusionGroup = try c.decodeIfPresent(String.self, forKey: .exclusionGroup)
    }
}
