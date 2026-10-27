import Testing
import Foundation
import SwiftData
@testable import CardPilot

@Suite @MainActor
struct TransactionRegionTests {
    private func date(_ text: String) throws -> Date { try CatalogImporter.date(text) }

    private func intent(region: TransactionRegion) throws -> RecordTransactionIntent {
        let intent = RecordTransactionIntent()
        intent.merchant = "Test shop"; intent.amount = 100
        intent.transactionDate = try date("2026-10-10")
        intent.region = region
        return intent
    }

    @Test(arguments: [TransactionRegion.hongKong, .mainlandChina, .macao])
    func shortcutsExplicitRegionIsStoredWithoutEligibilityCalculation(region: TransactionRegion) throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Bank", name: "Regional", baseRateBps: 0)
        context.insert(card)
        let request = try intent(region: region).transactionRequest(cardID: card.syncKey)
        #expect(request.region == region.rawValue)
        #expect(request.isOverseas == (region != .hongKong))
        #expect(request.currency == "HKD")
        _ = try TransactionRecorder.record(request, in: context)
        let transaction = try #require(context.fetch(FetchDescriptor<SpendTransaction>()).first)
        #expect(transaction.region == region.rawValue)
        #expect(transaction.isOverseas == (region != .hongKong))

    }

    @Test func unknownRegionRemainsUnknownAndLegacyOverseasFlagRemainsEffective() throws {
        let unknown = try intent(region: .unspecified)
        let request = try unknown.transactionRequest(cardID: "card")
        #expect(request.region.isEmpty); #expect(!request.isOverseas)
        unknown.region = .hongKong; unknown.overseas = true
        #expect(try unknown.transactionRequest(cardID: "card").isOverseas)
    }

    @Test func importedMainlandRegionSetsOverseasEvenWhenLegacyFlagIsMissing() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Bank", name: "Card"); context.insert(card)
        var request = TransactionRequest(cardID: card.syncKey, merchant: "Shop", amountCents: 10000, date: try date("2026-10-10"))
        request.region = "CN"; request.isOverseas = false; request.externalID = "mainland-1"
        _ = try TransactionRecorder.record(request, in: context)
        let record = try #require(context.fetch(FetchDescriptor<SpendTransaction>()).first)
        #expect(record.region == "CN"); #expect(record.isOverseas)
        request.region = "unrecognised"; request.externalID = "invalid-1"
        #expect(throws: PilotError.self) { try TransactionRecorder.record(request, in: context) }
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
    }

    @Test func manualEntryPreservesItsRegionWhenEditedAndRejectsInvalidAmounts() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Bank", name: "Card"); context.insert(card)
        let draft = TransactionDraft(transaction: nil)
        #expect(draft.region.isEmpty)
        draft.cardID = card.id; draft.merchant = "Macao shop"; draft.amount = 100
        draft.date = try date("2026-10-10"); draft.region = "MO"
        #expect(draft.save(in: context, cards: [card]))
        let transaction = try #require(context.fetch(FetchDescriptor<SpendTransaction>()).first)
        #expect(transaction.region == "MO"); #expect(transaction.isOverseas)
        let edit = TransactionDraft(transaction: transaction)
        edit.merchant = "Edited shop"
        #expect(edit.save(in: context, cards: [card])); #expect(transaction.region == "MO")
        edit.amount = .nan
        #expect(!edit.save(in: context, cards: [card]))
        #expect(transaction.amountCents == 10000)
    }
}
