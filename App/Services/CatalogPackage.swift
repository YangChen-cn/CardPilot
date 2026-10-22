import Foundation

struct CatalogPackage: Codable, Sendable {
    let schemaVersion: Int
    let cards: [CatalogCard]
}
