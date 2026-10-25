import Testing
import Foundation
import ImageIO
@testable import CardPilot

@Suite
struct CardImageTests {
    @Test func currentStudentGoldCanvasIsCroppedInTheSharedDecoder() async throws {
        let url = try #require(Bundle.main.url(forResource: "hsbc-student-visa-gold", withExtension: "jpg", subdirectory: "Catalog/images/cards"))
        let data = try Data(contentsOf: url)
        let asset = try #require(try await CardImageStore.shared.image(for: data))
        // The decoder scales 1600×900 to 1200×675 before applying the viewport.
        #expect(asset.image.width == 540)
        #expect(asset.image.height == 340)
        #expect(CatalogAssetStore.hash(data) == "49448f56b8136d8fef39656e5c0f5e8a4cba60f0c884bde249bca9b0c3c6c3b0")
    }

    @Test func unknownArtworkIsNeverCroppedByTheKnownCanvasCorrection() throws {
        let url = try #require(Bundle.main.url(forResource: "hsbc-student-visa-gold", withExtension: "jpg", subdirectory: "Catalog/images/cards"))
        let data = try Data(contentsOf: url)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(CardImageContentLayout.image(image, sourceDigest: "custom-artwork") === image)
        let legacy = CardImageContentLayout.image(image, sourceDigest: "0a5d027bbf93e8b0cca878d42e8f8a0c25153ebd19d39da24b2cd1b798a9ec64")
        #expect(legacy.width == 720)
        #expect(legacy.height == 453)
    }

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
