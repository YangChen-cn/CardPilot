import Foundation
import SwiftData
import Testing
@testable import CardPilot

@Suite @MainActor
struct EditorDraftTests {
    @Test func offerDraftProtectsUserEditsAndKeepsAutomaticSelectionClean() throws {
        let card = BankCard(bank: "Example", name: "Card")
        let draft = RuleDraft(rule: nil)
        draft.prepare(cards: [card])
        #expect(draft.cardID == card.id)
        #expect(!draft.hasUnsavedChanges)
        draft.notes = "Register before paying"
        draft.prepare(cards: [card])
        #expect(draft.hasUnsavedChanges)
        draft.notes = ""
        #expect(!draft.hasUnsavedChanges)
        let rule = RewardRule(name: "Example offer", card: card)
        let editing = RuleDraft(rule: rule)
        #expect(!editing.hasUnsavedChanges)
        editing.name = "Draft title"
        #expect(editing.hasUnsavedChanges)
        #expect(rule.name == "Example offer")
    }

    @Test func automaticCardAndPreferencesDoNotCreateDiscardWarnings() throws {
        let card = BankCard(bank: "Example", name: "Preferred")
        let preferences = QuickEntryPreferences(cardKey: card.syncKey, category: "交通", paymentMethod: "实体卡")
        let draft = TransactionDraft(transaction: nil, preferences: preferences)
        #expect(!draft.hasUnsavedChanges)
        draft.prepare(cards: [card])
        #expect(draft.cardID == card.id)
        #expect(!draft.hasUnsavedChanges)
        let scoped = TransactionDraft(transaction: nil, preferences: preferences, cardID: card.id)
        scoped.prepare(cards: [card])
        #expect(!scoped.hasUnsavedChanges)
        draft.amount = 18
        draft.prepare(cards: [card])
        #expect(draft.hasUnsavedChanges)
        draft.amount = 0
        #expect(!draft.hasUnsavedChanges)
    }

    @Test func transactionEditsStayInDraftAndRevertingRestoresCleanState() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let card = BankCard(bank: "Example", name: "Card")
        container.mainContext.insert(card)
        let transaction = SpendTransaction(merchant: "Cafe", amountCents: 1800, card: card)
        container.mainContext.insert(transaction)
        try container.mainContext.save()
        let draft = TransactionDraft(transaction: transaction)
        #expect(!draft.hasUnsavedChanges)
        draft.notes = "A draft note"
        #expect(draft.hasUnsavedChanges)
        #expect(transaction.notes.isEmpty)
        draft.notes = ""
        #expect(!draft.hasUnsavedChanges)
        let date = draft.date
        draft.date = date.addingTimeInterval(-86400)
        #expect(draft.hasUnsavedChanges)
        draft.date = date
        #expect(!draft.hasUnsavedChanges)
        draft.currency = "CNY"
        #expect(draft.hasUnsavedChanges)
        #expect(draft.exchangeRate == 0)
        #expect(transaction.currency == "HKD")
        #expect(!container.mainContext.hasChanges)
    }

    @Test func cardMetadataAndArtworkChangesAreProtectedWithoutSaving() throws {
        let product = try #require(BankLibrary.load().product(id: "bochk.go.diamond"))
        let container = try Persistence.makeContainer(inMemory: true)
        let card = try LibraryOnboarding.add(product: product, in: container.mainContext)
        let draft = CardDraft(card: card)
        #expect(!draft.hasUnsavedChanges)
        draft.lastFour = "1234"
        #expect(draft.hasUnsavedChanges)
        #expect(card.lastFour.isEmpty)
        draft.lastFour = ""
        #expect(!draft.hasUnsavedChanges)
        try draft.importArtwork(#require(product.artwork?.bundledData()))
        #expect(draft.hasUnsavedChanges)
        #expect(card.artworkSource == .catalog)
        draft.restoreCatalogArtwork()
        #expect(!draft.hasUnsavedChanges)
        let newCard = CardDraft(card: nil)
        #expect(!newCard.hasUnsavedChanges)
        newCard.isArchived = true
        #expect(newCard.hasUnsavedChanges)
    }
}
