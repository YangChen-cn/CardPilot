import Testing
import Foundation
import SwiftData
@testable import CardPilot

@Suite @MainActor
struct BankLibraryTests {
    private func product(_ id: String) throws -> CardProduct {
        try #require(BankLibrary.load().products.first { $0.id == id })
    }
    private func day(_ value: String) throws -> Date { try CatalogImporter.date(value) }

    @Test func libraryContainsFourBanksThirteenUniqueProductsAndOfflineArtwork() throws {
        let library = try BankLibrary.load()
        #expect(Set(library.banks.map(\.id)) == ["hsbc", "bochk", "bea", "cncbi"])
        #expect(library.products.count == 13); #expect(Set(library.products.map(\.id)).count == 13)
        for bank in library.banks { try CatalogImporter.validateImage(#require(BankLibrary.imageData(resource: bank.logoResource))) }
        for product in library.products { try CatalogImporter.validateImage(#require(BankLibrary.imageData(resource: product.imageResource))) }
        let ordinary = try product("bea.udc.diamond"), student = try product("bea.udc.diamond.student")
        #expect(ordinary.imageResource == student.imageResource)
        #expect(ordinary.welcomePlans.first?.id != student.welcomePlans.first?.id)
        #expect(try product("bochk.mastercard.debit").catalog.kind == "借记卡")
        #expect(try product("cncbi.multi-currency.debit").catalog.kind == "借记卡")
        #expect(try product("cncbi.gba.dual").catalog.kind != "借记卡")
    }

    @Test func everyProductIncludesDescriptiveWelcomesAndRepeatedAddPreservesPersonalData() throws {
        for product in try BankLibrary.load().products {
            let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
            let card = try LibraryOnboarding.add(product: product, in: context)
            card.lastFour = "1234"; card.statementDay = 17; card.paymentDay = 8; try context.save()
            let same = try LibraryOnboarding.add(product: product, in: context)
            #expect(try context.fetchCount(FetchDescriptor<BankCard>()) == 1)
            #expect(same.id == card.id); #expect(same.lastFour == "1234"); #expect(same.statementDay == 17)
            #expect(card.rules.isEmpty)
            #expect(card.catalogID == product.id)
            let offers = OfferStore.offers(for: card, context: context)
            #expect(Set(offers.filter { $0.origin == .official }.map(\.title))
                    == Set(product.displayCatalog.rules.map(\.name)))
            #expect(card.imageData != nil)
            if !product.baseRewardVerified { #expect(card.baseRateBps == 0) }
        }
    }

    @Test func personalSettingsSaveWithoutWelcomeEligibilityAndSync() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let product = try product("bea.udc.diamond.student"), card = try LibraryOnboarding.add(product: product, in: context)
        let draft = PersonalCardDraft(card: card, product: product)
        draft.lastFour = "6888"; draft.statementDay = 23; draft.paymentDay = 14; draft.creditLimit = 20000
        #expect(draft.save(in: context))
        #expect(try FinanceStore.snapshot(context: context).groups.first?.limitCents == 2_000_000)
        #expect(PersonalCardDraft(card: card, product: product).creditLimit == 20000)
        let other = try Persistence.makeContainer(inMemory: true), records = try SyncStore.records(context)
        #expect(try SyncStore.apply(records, context: other.mainContext))
        let remote = try #require(try other.mainContext.fetch(FetchDescriptor<BankCard>()).first)
        #expect(remote.lastFour == "6888"); #expect(remote.statementDay == 23)
        #expect(try !SyncStore.apply(records, context: other.mainContext))
    }

    @Test func editingPersonalFieldsPreservesOldApplicationAndRewardReceipt() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let product = try product("bochk.chill.platinum"), card = try LibraryOnboarding.add(product: product, in: context)
        let welcome = RewardRule(name: "Legacy welcome", kind: "welcome", card: card,
                                 startsOn: try day("2026-09-01"), endsOn: try day("2026-12-31"))
        welcome.externalID = try #require(product.welcomePlans.first?.ruleIDs.first)
        context.insert(welcome)
        let profile = PersonalCardProfile(cardKey: card.syncKey, productID: product.id, bankID: product.bankID,
            applicationDate: try day("2026-10-01"), applicationChannel: "网上申请", issueDate: try day("2026-10-05"),
            welcomePlanID: "legacy.plan", welcomeRuleIDs: [welcome.externalID], welcomeEnabled: true,
            welcomeStartsOn: try day("2026-10-05"), welcomeEndsOn: try day("2026-12-31"), confirmedEligibility: true)
        try DocumentStore.put(profile, key: "personalCard:" + card.syncKey, kind: "personalCardProfile", in: context)
        try DocumentStore.put(WelcomeReceipt(received: true, receivedOn: day("2026-10-20")), key: "welcome:" + welcome.syncKey, kind: "welcome", in: context)
        try context.save()
        let before = try #require(try DocumentStore.record("personalCard:" + card.syncKey, in: context)).content
        let receipt = try #require(try DocumentStore.record("welcome:" + welcome.syncKey, in: context)).content
        let draft = PersonalCardDraft(card: card, product: product); draft.lastFour = "4321"
        #expect(draft.save(in: context))
        #expect(try DocumentStore.record("personalCard:" + card.syncKey, in: context)?.content == before)
        #expect(try DocumentStore.record("welcome:" + welcome.syncKey, in: context)?.content == receipt)
    }

    @Test func catalogAndPersonalUpdatesPreserveCustomActivityAndArtwork() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let product = try product("hsbc.student.visa.gold"), card = try LibraryOnboarding.add(product: product, in: context)
        let welcome = RewardRule(name: "Legacy welcome", kind: "welcome", card: card,
                                 startsOn: try day("2026-09-01"), endsOn: try day("2026-12-31"))
        welcome.externalID = try #require(product.welcomePlans.first?.ruleIDs.first)
        context.insert(welcome)
        let edit = RuleDraft(rule: welcome); edit.notes = "My activity note"; edit.endsOn = try day("2026-11-20")
        #expect(edit.save(in: context, cards: [card]))
        let customArtwork = try #require(BankLibrary.imageData(resource: "bea-hku-student.png"))
        let custom = CardDraft(card: card); custom.name = "My student card"; custom.imageData = customArtwork
        custom.basePercent = 0.8; #expect(custom.save(in: context))
        try CatalogImporter.apply(CatalogPackage(schemaVersion: 1, cards: [product.displayCatalog]), context: context)
        #expect(card.name == "My student card"); #expect(card.imageData == customArtwork); #expect(card.baseRateBps == 80)
        let personal = PersonalCardDraft(card: card, product: product); personal.lastFour = "4321"
        #expect(personal.save(in: context)); #expect(welcome.notes == "My activity note")
        #expect(welcome.endsOn == (try day("2026-11-20")))
        #expect(try RulePolicyStore.state(welcome).pending != nil)
    }
}
