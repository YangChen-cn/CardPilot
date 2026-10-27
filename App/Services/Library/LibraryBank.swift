import Foundation

struct LibraryBank: Identifiable, Sendable {
    let id: String
    let name: String
    let shortName: String
    let logo: CatalogAsset?
    let searchTerms: [String]
}
