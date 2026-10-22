import Foundation
import SwiftData
import Testing
@testable import CardPilot

@Suite(.serialized) @MainActor
struct CardPricingStabilityTests {
    private func product(baseRate: Decimal) -> CardProduct {
        let catalog = CatalogCard(id: "rate.test", bank: "BOCHK", name: "Rate test", network: "Visa",
                                  sourceURL: "https://example.com/official", verifiedOn: "2026-10-23",
                                  baseRatePercent: baseRate, foreignFeePercent: 1,
                                  overseasHKDFeePercent: 0.5, excludesWallets: false,
                                  annualFeeNote: "年费说明", caveats: "官方注意", rules: [],
                                  calculation: nil)
        return CardProduct(bankID: "bochk", catalog: catalog,
                           artwork: CatalogAsset(path: "images/cards/bochk-chill-platinum.png",
                                                 sha256: String(repeating: "a", count: 64), contentType: "image/png"),
                           baseRewardVerified: true, welcomePlans: [], searchTerms: [])
    }

    @Test func currentOfficialRatesWinOverTheCardSnapshot() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "BOCHK", name: "Rate card")
        card.catalogID = "rate.test"
        card.baseRateBps = 40
        context.insert(card)
        let library = BankLibrary(banks: [], products: [product(baseRate: 0.8)])

        let value = PricingStore.current(card, library: library)
        #expect(value.baseRateBps == 80)
        #expect(value.foreignFeeBps == 100)
        #expect(PricingStore.details(card, library: library).annualFeeNote == "年费说明")
    }

    @Test func explicitFieldOverrideSurvivesOfficialBaseUpdate() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "BOCHK", name: "Rate card")
        card.catalogID = "rate.test"
        card.baseRateBps = 40
        context.insert(card)
        var override = CardPricing(card)
        override.foreignFeeBps = 250
        override.overriddenFields = ["foreign"]
        try DocumentStore.put(override, key: "cardOverride:" + card.syncKey, kind: "cardOverride", in: context)
        try context.save()

        let library = BankLibrary(banks: [], products: [product(baseRate: 0.8)])
        let value = PricingStore.current(card, library: library)
        #expect(value.baseRateBps == 80)
        #expect(value.foreignFeeBps == 250)
    }

    @Test func legacyOverrideWithoutFieldListStillAppliesToAllRates() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "BOCHK", name: "Legacy rate card")
        card.catalogID = "rate.test"
        context.insert(card)
        var override = CardPricing(card)
        override.baseRateBps = 33
        try DocumentStore.put(override, key: "cardOverride:" + card.syncKey, kind: "cardOverride", in: context)
        try context.save()

        let value = PricingStore.current(card, library: BankLibrary(banks: [], products: [product(baseRate: 0.8)]))
        #expect(value.baseRateBps == 33)
    }
}
