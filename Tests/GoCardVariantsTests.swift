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
        #expect(diamond.id != platinum.id); #expect(diamond.imageResource != platinum.imageResource)
        let diamondImage = try #require(BankLibrary.imageData(resource: diamond.imageResource))
        let platinumImage = try #require(BankLibrary.imageData(resource: platinum.imageResource))
        #expect(diamondImage != platinumImage)
        #expect(diamondImage != BankLibrary.imageData(resource: "bochk-go.png"))
        #expect(platinumImage != BankLibrary.imageData(resource: "bochk-go.png"))
        #expect(diamond.welcomePlans.first?.id != platinum.welcomePlans.first?.id)
        #expect(diamond.welcomePlans.first?.ruleIDs != platinum.welcomePlans.first?.ruleIDs)

        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let a = try LibraryOnboarding.add(product: diamond, in: context)
        let b = try LibraryOnboarding.add(product: platinum, in: context)
        #expect(a.id != b.id); #expect(a.syncKey != b.syncKey)
        #expect(a.imageData == diamondImage); #expect(b.imageData == platinumImage)
        #expect(try OfferStore.offers(for: a, context: context).contains { $0.origin == .official })
        #expect(try OfferStore.offers(for: b, context: context).contains { $0.origin == .official })
        #expect(try LibraryOnboarding.add(product: diamond, in: context).id == a.id)
        #expect(try LibraryOnboarding.add(product: platinum, in: context).id == b.id)
        #expect(try context.fetchCount(FetchDescriptor<BankCard>()) == 2)
        #expect(a.rules.isEmpty); #expect(b.rules.isEmpty)
    }

    @Test(arguments: ["bochk-go.png", "bochk-go-cf.png"])
    func knownCompositeIsRepairedWithoutChangingPersonalDataOrRules(_ legacyResource: String) throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "BOCHK", name: "我的 GO", lastFour: "1234", statementDay: 17, paymentDay: 9, baseRateBps: 80)
        let legacyImage = try #require(BankLibrary.imageData(resource: legacyResource))
        card.catalogID = "bochk.go.diamond"; card.imageData = legacyImage
        context.insert(card)
        let rule = RewardRule(name: "自定义活动", card: card, rateBps: 777); rule.isEnabled = false; context.insert(rule)
        let transaction = SpendTransaction(merchant: "Shop", amountCents: 8888, card: card); context.insert(transaction)
        try context.save()
        let cardID = card.id, ruleID = rule.id, transactionID = transaction.id
        #expect(try LibraryArtworkUpdates.apply(in: context) == 1)
        #expect(card.imageData == BankLibrary.imageData(resource: "bochk-go-diamond.png"))
        #expect(card.id == cardID); #expect(card.name == "我的 GO"); #expect(card.lastFour == "1234")
        #expect(card.statementDay == 17); #expect(card.paymentDay == 9); #expect(card.baseRateBps == 80)
        #expect(rule.id == ruleID); #expect(rule.rateBps == 777); #expect(!rule.isEnabled)
        #expect(transaction.id == transactionID); #expect(transaction.amountCents == 8888)
        #expect(try LibraryArtworkUpdates.apply(in: context) == 0)
        let custom = try #require(BankLibrary.imageData(resource: "bea-hku-student.png"))
        card.imageData = custom
        #expect(try LibraryArtworkUpdates.apply(in: context) == 0); #expect(card.imageData == custom)
    }
}
