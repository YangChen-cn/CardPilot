import Foundation
import SwiftData
import Testing
@testable import CardPilot

@Suite @MainActor
struct GoCardVariantsTests {
    private func product(_ id: String) throws -> CardProduct {
        try #require(BankLibrary.load().products.first { $0.id == id })
    }
    private func day(_ text: String) throws -> Date { try CatalogImporter.date(text) }

    @Test func variantsHaveIndependentProductsArtworkAndRewards() throws {
        let diamond = try product("bochk.go.diamond"), platinum = try product("bochk.go.platinum")
        let diamondArtwork = try #require(diamond.artwork), platinumArtwork = try #require(platinum.artwork)
        #expect(diamond.id != platinum.id); #expect(diamondArtwork.path != platinumArtwork.path)
        let diamondImage = try #require(diamondArtwork.bundledData())
        let platinumImage = try #require(platinumArtwork.bundledData())
        #expect(diamondImage != platinumImage)
        #expect(diamond.welcomePlans.first?.id != platinum.welcomePlans.first?.id)
        #expect(diamond.welcomePlans.first?.ruleIDs != platinum.welcomePlans.first?.ruleIDs)

        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let a = try LibraryOnboarding.add(product: diamond, in: context)
        let b = try LibraryOnboarding.add(product: platinum, in: context)
        #expect(a.id != b.id); #expect(a.syncKey != b.syncKey)
        #expect(a.imageData == nil); #expect(b.imageData == nil)
        #expect(a.artworkSource == .catalog); #expect(b.artworkSource == .catalog)
        #expect(try OfferStore.offers(for: a, context: context).contains { $0.origin == .official })
        #expect(try OfferStore.offers(for: b, context: context).contains { $0.origin == .official })
        #expect(try LibraryOnboarding.add(product: diamond, in: context).id == a.id)
        #expect(try LibraryOnboarding.add(product: platinum, in: context).id == b.id)
        #expect(try context.fetchCount(FetchDescriptor<BankCard>()) == 2)
        #expect(a.rules.isEmpty); #expect(b.rules.isEmpty)
    }

}
