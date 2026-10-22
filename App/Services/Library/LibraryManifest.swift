import Foundation

struct LibraryManifest: Decodable {
    let products: [LibraryProductDefinition]
}
