import Testing
import Foundation
@testable import CardPilot

@Suite
struct CardImageTests {
    @Test func officialPortraitIsPreservedAndSharedBetweenConsumers() async throws {
        let url = try #require(Bundle.main.url(forResource: "chill-platinum", withExtension: "png"))
        let data = try Data(contentsOf: url)
        let decoded = try await CardImageStore.shared.image(for: data)
        let cached = try await CardImageStore.shared.image(for: data)
        let original = try #require(decoded)
        let reused = try #require(cached)
        #expect(original.image.width == 355)
        #expect(original.image.height == 540)
        #expect(abs(Double(original.aspectRatio) - 355.0 / 540.0) < 0.000_001)
        #expect(original.image === reused.image)
    }

    @Test func malformedImageDataDoesNotCrashTheWallet() async throws {
        let image = try await CardImageStore.shared.image(for: Data("not an image".utf8))
        #expect(image == nil)
    }
}
