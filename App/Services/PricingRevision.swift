import Foundation

struct PricingRevision: Codable, Equatable, Sendable {
    var until: Date
    var value: CardPricing
}
