import Foundation

/// Artwork ownership is an explicit personal choice, independent of image contents.
enum CardArtworkSource: String, Codable, Equatable, Sendable {
    case catalog
    case custom
}
