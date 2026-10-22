import Foundation
import SwiftData
import Testing
@testable import CardPilot

@Suite @MainActor
struct SpendConditionsAndScopeTests {
    @Test func manualEntryNeedsNoPaymentRegionChannelOrForeignExchangeRate() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Dual currency"); context.insert(card)
        let defaults = UserDefaults(suiteName: "CardPilot-entry-test-" + UUID().uuidString)!
        let draft = TransactionDraft(transaction: nil, defaults: defaults)
        draft.cardID = card.id; draft.merchant = "Example shop"; draft.amount = 100; draft.currency = "CNY"
        #expect(draft.region.isEmpty); #expect(draft.channel == "unknown")
        #expect(draft.paymentMethod == PaymentMethod.unknown.rawValue)
        #expect(draft.validationError == nil)
        #expect(draft.save(in: context, cards: [card]))
        let saved = try #require(context.fetch(FetchDescriptor<SpendTransaction>()).first)
        #expect(saved.amountCents == 10000); #expect(saved.currency == "CNY")
        #expect(saved.exchangeRate.isEmpty); #expect(saved.region.isEmpty)
        #expect(saved.paymentMethod == PaymentMethod.unknown.rawValue)
    }

    @Test func currencyChangesNeverInventOrReplaceAnExplicitLocation() {
        let input = RecommendationDraft()
        input.currency = "CNY"; #expect(input.region.isEmpty)
        input.currency = "HKD"; #expect(input.region.isEmpty)
        input.region = "MO"; input.currency = "USD"
        #expect(input.region == "MO")
        let draft = TransactionDraft(transaction: nil)
        draft.currency = "CNY"; #expect(draft.region.isEmpty)
        draft.region = "HK"; draft.currency = "USD"
        #expect(draft.region == "HK")
    }
}
