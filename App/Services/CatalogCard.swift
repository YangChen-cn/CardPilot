import Foundation

struct CatalogCard: Codable, Identifiable, Sendable {
    let id: String
    let bank: String
    let name: String
    let network: String
    let sourceURL: String
    let verifiedOn: String
    var kind: String?
    var baseRatePercent: Decimal?
    var foreignFeePercent: Decimal?
    var overseasHKDFeePercent: Decimal?
    var excludesWallets: Bool?
    var annualFeeNote: String?
    var caveats: String?
    var imageURL: String?
    var imageBase64: String?
    var rules: [CatalogRule]
    var calculation: CardTerms?
}
