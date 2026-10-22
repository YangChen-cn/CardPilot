import Testing
import Foundation
import SwiftData
@testable import CardPilot

@Suite @MainActor
struct CardOrderTests {
    private func card(_ catalogID: String, createdAt: Date) -> BankCard {
        let card = BankCard(bank: "Test", name: catalogID)
        card.catalogID = catalogID
        card.createdAt = createdAt
        return card
    }

    @Test func savedOrderSurvivesAndUnknownCardsAppendByCreationDate() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let old = card("a", createdAt: Date(timeIntervalSince1970: 100))
        let new = card("b", createdAt: Date(timeIntervalSince1970: 200))
        let later = card("c", createdAt: Date(timeIntervalSince1970: 300))
        [old, new, later].forEach(context.insert)

        try CardOrderStore.save([new.syncKey, old.syncKey, "not-a-card", new.syncKey], context: context)
        #expect(CardOrderStore.load(context: context) == [new.syncKey, old.syncKey])
        #expect(CardOrderStore.ordered([old, new, later], context: context) == [new, old, later])
    }

    @Test func orderDocumentSyncsAcrossDevicesUsingStableCardKeys() throws {
        let first = try Persistence.makeContainer(inMemory: true)
        let a = card("a", createdAt: Date(timeIntervalSince1970: 100))
        let b = card("b", createdAt: Date(timeIntervalSince1970: 200))
        first.mainContext.insert(a); first.mainContext.insert(b)
        try CardOrderStore.save([b.syncKey, a.syncKey], context: first.mainContext)

        let second = try Persistence.makeContainer(inMemory: true)
        second.mainContext.insert(card("a", createdAt: Date(timeIntervalSince1970: 100)))
        second.mainContext.insert(card("b", createdAt: Date(timeIntervalSince1970: 200)))
        #expect(try SyncStore.apply(SyncStore.records(first.mainContext), context: second.mainContext))
        #expect(CardOrderStore.load(context: second.mainContext) == [b.syncKey, a.syncKey])
    }

    @Test func movingBeforeAndAfterUsesTheDropTarget() throws {
        let keys = ["card:a", "card:b", "card:c"]
        #expect(CardOrderStore.moved(keys, source: "card:c", target: "card:a", after: false) == ["card:c", "card:a", "card:b"])
        #expect(CardOrderStore.moved(keys, source: "card:a", target: "card:c", after: true) == ["card:b", "card:c", "card:a"])
        #expect(CardOrderStore.moved(keys, source: "card:a", target: "card:a", after: true) == nil)
        #expect(CardOrderStore.moved(keys, source: "missing", target: "card:a", after: false) == nil)
    }
}
