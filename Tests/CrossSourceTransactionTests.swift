import Testing
import Foundation
import SwiftData
@testable import CardPilot

@Suite @MainActor
struct CrossSourceTransactionTests {
    private func day(_ text: String = "2026-10-10") throws -> Date { try CatalogImporter.date(text) }

    private func card(_ context: ModelContext, name: String = "Card") -> BankCard {
        let card = BankCard(bank: "Bank", name: name)
        context.insert(card); return card
    }

    private func manual(_ context: ModelContext, card: BankCard, at date: Date) throws -> SpendTransaction {
        let transaction = SpendTransaction(merchant: "Cafe", amountCents: 12000, paymentMethod: "实体卡", date: date, card: card)
        context.insert(transaction); try context.save(); return transaction
    }

    private func pending(_ context: ModelContext) throws -> [DomainRecord] {
        try context.fetch(FetchDescriptor<DomainRecord>()).filter { $0.kind == "review" && !$0.isDeleted }
    }

    @Test func shortcutAtTheSameTimeAsAManualEntryRequiresReviewEvenWithADifferentPaymentMethod() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext, card = card(context)
        let timestamp = try day().addingTimeInterval(13 * 3600)
        let original = try manual(context, card: card, at: timestamp)
        var request = TransactionRequest(cardID: card.syncKey, merchant: "  CAFE  ", amountCents: 12000, date: timestamp)
        request.paymentMethod = "Apple Pay"
        guard case .needsReview(let key) = try TransactionRecorder.record(request, in: context) else {
            Issue.record("A cross-source match was silently discarded or inserted"); return
        }
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        #expect(try pending(context).count == 1)
        #expect(original.paymentMethod == "实体卡")
        guard case .recorded = try TransactionRecorder.record(request, in: context, allowPossibleDuplicate: true) else {
            Issue.record("A legitimate second purchase could not be approved"); return
        }
        try DocumentStore.remove(key, in: context); try context.save()
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 2)
        guard case .duplicate = try TransactionRecorder.record(request, in: context) else {
            Issue.record("The same stable Wallet retry was no longer idempotent"); return
        }
    }

    @Test func manualConfirmationCanCancelOrSaveAnotherPurchaseWithoutCreatingHiddenReviewRows() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext, card = card(context)
        let timestamp = try day().addingTimeInterval(12 * 3600)
        var automatic = TransactionRequest(cardID: card.syncKey, merchant: "Cafe", amountCents: 12000, date: timestamp)
        automatic.externalID = "wallet-1"
        _ = try TransactionRecorder.record(automatic, in: context); try context.save()
        let draft = TransactionDraft(transaction: nil)
        draft.cardID = card.id; draft.merchant = "Cafe"; draft.amount = 120; draft.date = timestamp
        #expect(!draft.save(in: context, cards: [card]))
        #expect(draft.possibleDuplicate != nil); #expect(draft.error == nil)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        #expect(try pending(context).isEmpty)
        draft.cancelDuplicateConfirmation()
        #expect(draft.possibleDuplicate == nil)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        #expect(draft.save(in: context, cards: [card], allowPossibleDuplicate: true))
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 2)
        #expect(try pending(context).isEmpty)
    }

    @Test func dateOnlyCSVMatchesAnExistingPurchaseThroughoutItsHongKongCalendarDay() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext, card = card(context)
        _ = try manual(context, card: card, at: day().addingTimeInterval(20 * 3600))
        let requests = try CanonicalCSVAdapter().parse(Data("merchant,date,amount\nCafe,2026-10-10,120\n".utf8), cardID: card.syncKey)
        #expect(!requests[0].hasStableDate)
        guard case .needsReview = try TransactionRecorder.record(requests[0], in: context) else {
            Issue.record("A date-only statement missed a same-day manual purchase"); return
        }
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        #expect(try pending(context).count == 1)
    }

    @Test func distinctTrustedReferencesRemainDistinctButDifferentSourcesStillNeedReview() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext, card = card(context)
        var request = TransactionRequest(cardID: card.syncKey, merchant: "Cafe", amountCents: 12000, date: try day())
        request.externalID = "wallet-first"
        _ = try TransactionRecorder.record(request, in: context)
        request.externalID = "wallet-second"
        guard case .recorded = try TransactionRecorder.record(request, in: context) else {
            Issue.record("Distinct strong same-source references were mistaken for duplicates"); return
        }
        request.source = "csv"; request.externalID = "bank-reference"
        guard case .needsReview = try TransactionRecorder.record(request, in: context) else {
            Issue.record("Uncorrelated IDs across sources were treated as proof of different purchases"); return
        }
        request.externalID = "wallet-first"
        guard case .duplicate = try TransactionRecorder.record(request, in: context) else {
            Issue.record("A shared strong reference was not deduplicated across sources"); return
        }
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 2)
    }

    @Test func anEditIgnoresItselfButChecksOtherTransactionsAndPreservesItsIdentity() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext, card = card(context)
        let timestamp = try day().addingTimeInterval(10 * 3600)
        let first = try manual(context, card: card, at: timestamp)
        let unchanged = TransactionDraft(transaction: first)
        #expect(unchanged.save(in: context, cards: [card]))
        #expect(unchanged.possibleDuplicate == nil)
        let second = SpendTransaction(merchant: "Different shop", amountCents: 8000, date: timestamp, card: card)
        context.insert(second); try context.save()
        let id = second.id
        let edit = TransactionDraft(transaction: second)
        edit.merchant = "Cafe"; edit.amount = 120
        #expect(!edit.save(in: context, cards: [card]))
        #expect(edit.possibleDuplicate?.id == first.id)
        #expect(second.merchant == "Different shop"); #expect(second.amountCents == 8000)
        #expect(edit.save(in: context, cards: [card], allowPossibleDuplicate: true))
        #expect(second.id == id); #expect(second.merchant == "Cafe")
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 2)
        #expect(try pending(context).isEmpty)
    }

    @Test func identicalPurchasesOnDifferentCardsDoNotMatch() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let first = card(context), second = card(context, name: "Other")
        _ = try manual(context, card: first, at: day())
        let request = TransactionRequest(cardID: second.syncKey, merchant: "Cafe", amountCents: 12000, date: try day())
        #expect(try TransactionRecorder.assess(request, in: context) == nil)
        guard case .recorded = try TransactionRecorder.record(request, in: context) else {
            Issue.record("A different card's purchase prevented recording"); return
        }
    }

    @Test func csvRowsAreReviewedSeparatelyAndTheSameFileCanBeRetriedWithoutLosingDecisions() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext, card = card(context)
        _ = try manual(context, card: card, at: day().addingTimeInterval(14 * 3600))
        let csv = "merchant,date,amount\nCafe,2026-10-10,120\nCafe,2026-10-10,120\nNew shop,2026-10-11,50\n"
        let requests = try CanonicalCSVAdapter().parse(Data(csv.utf8), cardID: card.syncKey)
        #expect(requests[0].externalID != requests[1].externalID)
        let first = try TransactionBatchRecorder.record(requests, in: context)
        #expect(first == TransactionBatchResult(saved: 1, duplicate: 0, pending: 2))
        #expect(try pending(context).count == 2)
        let retry = try TransactionBatchRecorder.record(requests, in: context)
        #expect(retry == TransactionBatchResult(saved: 0, duplicate: 1, pending: 2))
        #expect(try pending(context).count == 2)
        let reviews = try pending(context)
        let approve = try #require(reviews.first)
        let request = try SyncCodec.decoder().decode(TransactionRequest.self, from: approve.content)
        try Persistence.save(context) {
            _ = try TransactionRecorder.record(request, in: context, allowPossibleDuplicate: true)
            try DocumentStore.remove(approve.key, in: context)
        }
        let remaining = try #require(pending(context).first)
        try Persistence.save(context) { try DocumentStore.remove(remaining.key, in: context) }
        #expect(try pending(context).isEmpty)
        let afterDecisions = try TransactionBatchRecorder.record(requests, in: context)
        #expect(afterDecisions == TransactionBatchResult(saved: 0, duplicate: 3, pending: 0))
        #expect(try pending(context).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 3)
    }

    @Test func invalidCSVBatchRollsBackBothAcceptedRowsAndReviewDocuments() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext, card = card(context)
        _ = try manual(context, card: card, at: day().addingTimeInterval(14 * 3600))
        let csv = "merchant,date,amount\nNew shop,2026-10-10,50\nCafe,2026-10-10,120\nInvalid,2026-10-11,90\n"
        var requests = try CanonicalCSVAdapter().parse(Data(csv.utf8), cardID: card.syncKey)
        requests[2].paymentMethod = "unsupported"
        #expect(throws: PilotError.self) { try TransactionBatchRecorder.record(requests, in: context) }
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        #expect(try pending(context).isEmpty)
    }

    @Test func reorderedCSVRowsBecomePossibleMatchesRatherThanSilentlyDroppingPurchases() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext, card = card(context)
        let original = "merchant,date,amount\nCafe,2026-10-10,120\nShop,2026-10-11,50\n"
        let reordered = "merchant,date,amount\nShop,2026-10-11,50\nCafe,2026-10-10,120\n"
        let first = try CanonicalCSVAdapter().parse(Data(original.utf8), cardID: card.syncKey)
        let second = try CanonicalCSVAdapter().parse(Data(reordered.utf8), cardID: card.syncKey)
        #expect(try TransactionBatchRecorder.record(first, in: context).saved == 2)
        let result = try TransactionBatchRecorder.record(second, in: context)
        #expect(result.pending == 2); #expect(result.duplicate == 0)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 2)
    }

    @Test func duplicateCSVRowsWithoutBankIDsCanBothRepresentRealPurchases() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext, card = card(context)
        let csv = "merchant,date,amount\nCafe,2026-10-10,120\nCafe,2026-10-10,120\n"
        let requests = try CanonicalCSVAdapter().parse(Data(csv.utf8), cardID: card.syncKey)
        let result = try TransactionBatchRecorder.record(requests, in: context)
        #expect(result.saved == 1); #expect(result.pending == 1); #expect(result.duplicate == 0)
        let document = try #require(pending(context).first)
        let second = try SyncCodec.decoder().decode(TransactionRequest.self, from: document.content)
        _ = try TransactionRecorder.record(second, in: context, allowPossibleDuplicate: true)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 2)
    }
}
