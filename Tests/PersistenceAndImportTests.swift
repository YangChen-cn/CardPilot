import Testing
import Foundation
import SwiftData
@testable import CardPilot

@Suite @MainActor
struct PersistenceAndImportTests {
    @Test func realDiskStoreSurvivesReopenEditsAndDeletes() throws {
        let directory = URL.temporaryDirectory.appending(path: "CardPilot-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "ledger.store")
        var id: UUID?
        do {
            let container = try Persistence.makeContainer(url: url)
            let context = container.mainContext
            let cardDraft = CardDraft(card: nil); cardDraft.name = "Persistence card"; cardDraft.lastFour = "1234"
            #expect(cardDraft.save(in: context))
            let card = try #require(context.fetch(FetchDescriptor<BankCard>()).first)
            id = card.id
            let tx = TransactionDraft(transaction: nil)
            tx.merchant = "Merchant"; tx.amount = Decimal(string: "12.34")!; tx.currency = "USD"
            tx.exchangeRate = Decimal(string: "7.8")!; tx.cardID = card.id
            #expect(tx.save(in: context, cards: [card]))
            let rule = RuleDraft(rule: nil, cardID: card.id); rule.name = "Welcome"; rule.kind = "welcome"
            #expect(rule.save(in: context, cards: [card]))
        }
        do {
            let container = try Persistence.makeContainer(url: url)
            let context = container.mainContext
            let card = try #require(context.fetch(FetchDescriptor<BankCard>()).first)
            #expect(card.id == id); #expect(card.lastFour == "1234"); #expect(card.rules.count == 1)
            let tx = try #require(card.transactions.first)
            #expect(tx.amountCents == 1234); #expect(tx.hkdCents == 9625)
            let edit = TransactionDraft(transaction: tx); edit.amount = 20
            #expect(edit.save(in: context, cards: [card]))
            #expect(tx.hkdCents == 15600)
        }
        do {
            let container = try Persistence.makeContainer(url: url)
            let context = container.mainContext
            let card = try #require(context.fetch(FetchDescriptor<BankCard>()).first)
            #expect(card.transactions.first?.amountCents == 2000)
            try Persistence.save(context) { context.delete(card) }
            #expect(try context.fetchCount(FetchDescriptor<BankCard>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<RewardRule>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 0)
        }
    }

    @Test func legacyImportValidationRejectsUnsupportedSchemaAndBadValues() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let text = #"{"schemaVersion":99,"cards":[]}"#
        #expect(throws: (any Error).self) { try CatalogImporter.decode(Data(text.utf8)) }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<BankCard>()) == 0)
        #expect(throws: (any Error).self) { try CatalogImporter.date("2026-02-30") }
        #expect(throws: (any Error).self) { try CatalogImporter.validateHTTPS("file:///etc/passwd") }
    }

    @Test func cancelDraftDoesNotChangePersistentModels() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let card = BankCard(bank: "BOCHK", name: "Original")
        container.mainContext.insert(card); try container.mainContext.save()
        let draft = CardDraft(card: card); draft.name = "Unsaved"; draft.basePercent = 99
        #expect(card.name == "Original"); #expect(card.baseRateBps == 0)
        let invalid = CardDraft(card: card); invalid.basePercent = -1
        #expect(!invalid.save(in: container.mainContext))
        #expect(card.baseRateBps == 0)
    }

    @Test func statementDateClampsToMonthEnd() throws {
        let reference = try CatalogImporter.date("2027-02-01")
        #expect(HKCalendar.nextDay(31, now: reference) == (try CatalogImporter.date("2027-02-28")))
    }
}
