import Foundation

/// Local persistence for the source choice without changing the core SwiftData schema.
/// Sync carries this choice with the card's image/profile, not as a second LWW record.
struct CardArtworkState: Codable, Equatable, Sendable {
    var source: CardArtworkSource
}
