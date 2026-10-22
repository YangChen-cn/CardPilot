import Testing
import Foundation
import SwiftData
@testable import CardPilot

@Suite @MainActor
struct HardeningTests {
    private func day(_ date: String) throws -> Date { try CatalogImporter.date(date) }
    private func card(_ context: ModelContext) -> BankCard {
        let card = BankCard(bank: "Bank", name: "Card", baseRateBps: 40)
        card.catalogID = "bank.card"; context.insert(card); return card
    }
    private func rule(_ context: ModelContext, card: BankCard) throws -> RewardRule {
        let value = RewardRule(name: "Offer", card: card, rateBps: 400, capCents: 15_000,
                               startsOn: try day("2026-10-01"), endsOn: try day("2026-12-31"))
        context.insert(value); value.externalID = "offer"
        try RulePolicyStore.imported(RuleSyncData(value), extras: RuleExtras(), into: value, isNew: true, context: context)
        return value
    }
    private func tx(_ context: ModelContext, card: BankCard, date: String, amount: Int64 = 100_000) throws -> SpendTransaction {
        let value = SpendTransaction(merchant: "Shop", amountCents: amount, date: try day(date), card: card)
        context.insert(value); return value
    }

    @Test func automaticEntryUsesStableCardIdentityTimePaymentAndExactDedupe() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext, card = card(context)
        var request = TransactionRequest(cardID: card.syncKey, merchant: " Cafe ", amountCents: 1250, date: try day("2026-10-10"))
        request.paymentMethod = "云闪付"; request.region = "HK"
        _ = try TransactionRecorder.record(request, in: context); try context.save()
        card.name = "Renamed"
        guard case .duplicate = try TransactionRecorder.record(request, in: context) else { Issue.record("Repeated stable transaction was saved twice"); return }
        let records = try context.fetch(FetchDescriptor<SpendTransaction>())
        #expect(records.count == 1); #expect(records.first?.date == request.date)
        #expect(records.first?.paymentMethod == "云闪付"); #expect(records.first?.region == "HK")
    }

    @Test func explicitReferencesDeduplicatePerCardAndAllowDistinctTransactions() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext, card = card(context)
        var request = TransactionRequest(cardID: card.syncKey, merchant: "Cafe", amountCents: 1250, date: try day("2026-10-10"))
        request.externalID = "bank-123"; request.hasStableDate = false
        _ = try TransactionRecorder.record(request, in: context)
        request.externalID = "bank-124"; _ = try TransactionRecorder.record(request, in: context)
        guard case .duplicate = try TransactionRecorder.record(request, in: context) else { Issue.record("Reference duplicate was accepted"); return }
        let other = BankCard(bank: "B", name: "Other"); context.insert(other); request.cardID = other.syncKey
        _ = try TransactionRecorder.record(request, in: context)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 3)
    }

    @Test func weakDuplicatesGoToReviewAndAnExplicitApprovalPreservesLegitimateRepeats() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext, card = card(context)
        var request = TransactionRequest(cardID: card.syncKey, merchant: "Cafe", amountCents: 1000, date: try day("2026-10-10"))
        request.hasStableDate = false
        _ = try TransactionRecorder.record(request, in: context)
        request.date.addTimeInterval(15)
        guard case .needsReview(let key) = try TransactionRecorder.record(request, in: context) else { Issue.record("Ambiguous repeat was not held for review"); return }
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        #expect(try DocumentStore.load(TransactionRequest.self, key: key, in: context) == request)
        _ = try TransactionRecorder.record(request, in: context, allowPossibleDuplicate: true)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 2)
    }

    @Test func reimportPreservesEditedRatesCapsDisabledStateAndPersonalWelcomeDates() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let url = try #require(Bundle.main.url(forResource: "bochk-chill", withExtension: "json"))
        let package = try CatalogImporter.decode(Data(contentsOf: url))
        try CatalogImporter.apply(package, context: context)
        let card = try #require(context.fetch(FetchDescriptor<BankCard>()).first)
        let cashback = try #require(card.rules.first(where: { !$0.isWelcome }))
        cashback.isEnabled = false; cashback.minimumCents = 25000
        let draft = RuleDraft(rule: cashback); draft.rate = 7
        #expect(draft.save(in: context, cards: [card]))
        let welcome = try #require(card.rules.first(where: { $0.isWelcome }))
        let personal = RuleDraft(rule: welcome); personal.startsOn = try day("2026-09-10"); personal.endsOn = try day("2026-11-30"); welcome.isEnabled = true
        #expect(personal.save(in: context, cards: [card]))
        try CatalogImporter.apply(package, context: context)
        #expect(cashback.rateBps == 700); #expect(cashback.minimumCents == 25_000); #expect(!cashback.isEnabled)
        #expect(welcome.startsOn == (try day("2026-09-10"))); #expect(welcome.isEnabled)
        #expect(try RulePolicyStore.state(cashback).pending != nil)
        try RulePolicyStore.acceptPending(cashback, context: context)
        #expect(!cashback.isEnabled); #expect(cashback.rateBps != 700)
    }

    @Test func csvQuotesDatesDuplicateIdsAndAtomicFailureAreHandled() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext, card = card(context)
        let csv = "id,merchant,date,amount,currency,payment,reward_eligible,notes\r\nref1,\"Cafe, Central\",2026-10-10T01:02:03.123Z,12.50,HKD,Apple Pay,true,lunch\r\nref2,\"Shop \"\"A\"\"\",2026-10-10T01:03:03Z,20,HKD,实体卡,false,bill\r\n"
        let requests = try CanonicalCSVAdapter().parse(Data(csv.utf8), cardID: card.syncKey)
        #expect(Int64((requests[0].date.timeIntervalSince1970 * 1000).rounded()) % 1000 == 123)
        #expect(requests.count == 2); #expect(requests[0].merchant == "Cafe, Central"); #expect(requests[1].merchant == "Shop \"A\"")
        try Persistence.save(context) { for request in requests { _ = try TransactionRecorder.record(request, in: context) } }
        try Persistence.save(context) { for request in requests { _ = try TransactionRecorder.record(request, in: context) } }
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 2)
        let imported = try #require(context.fetch(FetchDescriptor<SpendTransaction>()).first(where: { $0.externalID == "ref2" }))
        #expect(!imported.isRewardEligible); #expect(imported.notes == "bill")
        var invalid = requests[0]; invalid.externalID = "invalid"; invalid.paymentMethod = "unsupported"
        var valid = requests[0]; valid.externalID = "third"
        do { try Persistence.save(context) { _ = try TransactionRecorder.record(valid, in: context); _ = try TransactionRecorder.record(invalid, in: context) }; Issue.record("Invalid batch was saved") }
        catch { }
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 2)
    }

    @Test func schemaV2MigratesToV3AndDomainDocumentsSurviveReopening() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "CardPilot.store")
        do {
            let schema = Schema(versionedSchema: LocalSchemaV2.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration("CardPilot", schema: schema, url: url, cloudKitDatabase: .none))
            let card = LocalSchemaV2.BankCard(bank: "Original", name: "V2")
            container.mainContext.insert(card)
            container.mainContext.insert(LocalSchemaV2.SpendTransaction(merchant: "Original", amountCents: 1234, card: card))
            try container.mainContext.save()
        }
        do {
            let container = try Persistence.makeContainer(url: url), context = container.mainContext
            #expect(try context.fetch(FetchDescriptor<SpendTransaction>()).first?.region == "")
            try DocumentStore.put(WelcomeReceipt(received: true, receivedOn: try day("2026-10-20")), key: "welcome:test", kind: "welcome", in: context)
            try context.save()
        }
        let reopened = try Persistence.makeContainer(url: url)
        #expect(try DocumentStore.load(WelcomeReceipt.self, key: "welcome:test", in: reopened.mainContext)?.received == true)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
    }

    @Test func repeatedManualCardEditsAndCatalogRefreshPreserveTheLatestOverride() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext, card = card(context)
        let first = CardDraft(card: card); first.basePercent = 5; #expect(first.save(in: context))
        let second = CardDraft(card: card); second.basePercent = 7; #expect(second.save(in: context))
        #expect(PricingStore.current(card).baseRateBps == 700)
        let incoming = CatalogCard(id: card.catalogID, bank: "Bank", name: "Card", network: "Visa", sourceURL: "https://example.com/card", verifiedOn: "2026-10-21", baseRatePercent: 3, rules: [])
        try CatalogImporter.apply(CatalogPackage(schemaVersion: 1, cards: [incoming]), context: context)
        #expect(card.baseRateBps == 700); #expect(PricingStore.current(card).baseRateBps == 700)
    }
}
