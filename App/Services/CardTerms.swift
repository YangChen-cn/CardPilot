import Foundation

struct CardTerms: Codable, Equatable, Sendable {
    var cnyFeeBps: Int?
    var baseRewardBasis: String?
    var baseCapUsesCreditLimit: Bool?
    var baseCapPeriod: String?
    /// Nil keeps legacy all-region behavior. A regional waiver requires an explicit match.
    var cnyFeeRegions: [String]?
}
