import Foundation

struct CatalogRule: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let kind: String
    var group: String?
    let startsOn: String?
    let endsOn: String?
    let sourceURL: String
    var ratePercent: Decimal?
    var capHKD: Decimal?
    var capPeriod: String?
    var sharedCapGroup: String?
    var thresholdHKD: Decimal?
    var bonusHKD: Decimal?
    var minimumHKD: Decimal?
    var monthlyPhysicalThresholdHKD: Decimal?
    var channelCondition: String?
    var category: String?
    var currency: String?
    var paymentMethod: String?
    var merchantKeywords: String?
    var requiresPersonalDates: Bool?
    var enabled: Bool?
    var notes: String?
    var calculation: RuleExtras?
}
