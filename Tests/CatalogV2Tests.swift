import Foundation
import SwiftData
import Testing
@testable import CardPilot

@Suite(.serialized) @MainActor
struct CatalogV2Tests {
    private let hex = String(repeating: "a", count: 64)
    private func asset(_ path: String, type: String = "image/png") -> CatalogAsset {
        CatalogAsset(path: path, sha256: hex, contentType: type)
    }
    private func bank(_ id: String = "futurebank") -> RemoteCatalogBank {
        RemoteCatalogBank(id: id, name: "Future Bank", shortName: "FUTURE",
                          logo: asset("images/banks/future.png"), searchTerms: ["未来银行"])
    }
    private func card(id: String = "future.card", bank: String = "Future Bank") -> CatalogCard {
        CatalogCard(id: id, bank: bank, name: "Future Card", network: "Visa",
                    sourceURL: "https://example.com/official", verifiedOn: "2026-10-23", rules: [])
    }
    private func document() -> RemoteCatalogDocument {
        RemoteCatalogDocument(schemaVersion: 2, contentVersion: 9, publishedAt: "2026-10-23",
                              banks: [bank()],
                              products: [RemoteCatalogProduct(id: "future.card", bankID: "futurebank",
                                                              artwork: asset("images/cards/future.png"),
                                                              baseRewardVerified: false, welcomePlans: [],
                                                              catalog: card(), searchTerms: ["未来卡"])])
    }

    @Test func arbitraryBanksAreAcceptedWithoutAnAppWhitelist() throws {
        let decoded = try RemoteCatalogDocument.decode(JSONEncoder().encode(document()))
        #expect(decoded.banks.map(\.id) == ["futurebank"])
        #expect(decoded.cardProducts.first?.bankID == "futurebank")
    }

    @Test func bankReferencesAndIdentifiersMustBeUnique() throws {
        var invalid = document()
        invalid = RemoteCatalogDocument(schemaVersion: 2, contentVersion: invalid.contentVersion,
                                        publishedAt: invalid.publishedAt, banks: invalid.banks,
                                        products: [RemoteCatalogProduct(id: "future.card", bankID: "missing",
                                                                        artwork: asset("images/cards/future.png"),
                                                                        baseRewardVerified: false, welcomePlans: [],
                                                                        catalog: card(), searchTerms: [])])
        #expect(throws: (any Error).self) { _ = try RemoteCatalogDocument.decode(JSONEncoder().encode(invalid)) }

        let duplicate = RemoteCatalogDocument(schemaVersion: 2, contentVersion: 9, publishedAt: "2026-10-23",
                                              banks: [bank(), bank()], products: document().products)
        #expect(throws: (any Error).self) { _ = try RemoteCatalogDocument.decode(JSONEncoder().encode(duplicate)) }
    }

    @Test func artworkPathsCannotEscapeOrUseAnotherDomain() throws {
        let base = URL(string: "https://catalog.example.test/")!
        #expect(throws: (any Error).self) {
            _ = try CatalogAsset(path: "../cards/a.png", sha256: hex, contentType: "image/png").validate()
        }
        #expect(throws: (any Error).self) {
            _ = try CatalogAsset(path: "https://evil.example/a.png", sha256: hex, contentType: "image/png").validate()
        }
        let valid = try CatalogAsset(path: "images/cards/a.png", sha256: hex, contentType: "image/png")
        #expect(try valid.remoteURL(baseURL: base).absoluteString == "https://catalog.example.test/images/cards/a.png")
    }

    @Test func bundledArtworkUsesContentHashAndRejectsMismatch() throws {
        let data = try #require(BankLibrary.load().product(id: "bochk.chill.platinum")?.artwork.bundledData())
        let hash = CatalogAssetStore.hash(data)
        let matching = CatalogAsset(path: "images/cards/bochk-chill-platinum.png", sha256: hash, contentType: "image/png")
        #expect(matching.bundledData() == data)
        let wrong = CatalogAsset(path: "images/cards/bochk-chill-platinum.png", sha256: hex, contentType: "image/png")
        #expect(wrong.bundledData() == nil)
    }

    @Test func officialCardsDoNotCopyArtworkAndCustomArtworkSurvivesMigration() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let product = try #require(BankLibrary.load().products.first { $0.id == "bochk.chill.platinum" })
        let card = try LibraryOnboarding.add(product: product, in: context)
        #expect(card.imageData == nil); #expect(card.artworkOrigin == "official")

        let custom = try #require(BankLibrary.load().product(id: "bea.udc.diamond")?.artwork.bundledData())
        card.imageData = custom
        #expect(try LibraryArtworkUpdates.apply(in: context) == 0)
        #expect(card.imageData == custom); #expect(card.artworkOrigin == "custom")
    }

    @Test func newOfficialCardCannotBeMarkedCustomByCatalogUpdate() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let product = try #require(BankLibrary.load().products.first { $0.id == "bochk.chill.platinum" })
        let card = try LibraryOnboarding.add(product: product, in: context)
        card.imageData = try #require(BankLibrary.load().product(id: "bea.udc.diamond")?.artwork.bundledData())
        try context.save()
        #expect(try LibraryArtworkUpdates.apply(in: context) == 0)
        #expect(card.artworkOrigin == "custom")
        #expect(card.imageData != nil)
    }
}
