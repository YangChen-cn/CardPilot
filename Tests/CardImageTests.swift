import Testing
import Foundation
import ImageIO
@testable import CardPilot

@Suite
struct CardImageTests {
    @Test func normalizedStudentGoldArtworkUsesTheSharedCanvas() async throws {
        let url = try #require(Bundle.main.url(forResource: "hsbc-student-visa-gold", withExtension: "png", subdirectory: "Catalog/images/cards"))
        let data = try Data(contentsOf: url)
        let asset = try #require(try await CardImageStore.shared.image(for: data))
        #expect(asset.image.width == 1200)
        #expect(asset.image.height == 756)
        #expect(CatalogAssetStore.hash(data) == "4e52ff0c5b4572d3a5f18c67b074af6438f90a385a109c3de049fc04c17e61b9")
    }

    @Test @MainActor func bundledCardArtworkUsesTheSharedCanvas() throws {
        let library = try BankLibrary.load(remoteCache: nil)
        for product in library.products {
            let data = try #require(product.artwork.bundledData())
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 1200)
            #expect(image.height == 756)
        }
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
