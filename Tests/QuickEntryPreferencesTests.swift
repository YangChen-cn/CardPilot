import Testing
import Foundation
import SwiftData
@testable import CardPilot

@Suite @MainActor
struct QuickEntryPreferencesTests {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let name = "CardPilot.QuickEntryTests." + UUID().uuidString
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test func onlyASuccessfulSaveUpdatesPreferencesAndNewEntriesNeverRepeatAmountOrMerchant() throws {
        let (defaults, domain) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let first = BankCard(bank: "Bank", name: "First"), second = BankCard(bank: "Bank", name: "Second")
        first.catalogID = "first"; second.catalogID = "second"
        context.insert(first); context.insert(second)
        let original = QuickEntryPreferences(cardKey: first.syncKey, category: "交通", paymentMethod: "实体卡")
        QuickEntryPreferencesStore.save(original, defaults: defaults)
        let draft = TransactionDraft(transaction: nil, defaults: defaults)
        draft.prepare(cards: [first, second])
        #expect(draft.cardID == first.id); #expect(draft.category == "交通"); #expect(draft.paymentMethod == "实体卡")
        draft.cardID = second.id; draft.category = "购物"; draft.paymentMethod = "支付宝"
        draft.merchant = "Shop"; draft.amount = 0
        #expect(!draft.save(in: context, cards: [first, second]))
        #expect(QuickEntryPreferencesStore.load(defaults: defaults) == original)
        draft.amount = 120; draft.date = try CatalogImporter.date("2026-10-10")
        #expect(draft.save(in: context, cards: [first, second]))
        let saved = QuickEntryPreferences(cardKey: second.syncKey, category: "购物", paymentMethod: "支付宝")
        #expect(QuickEntryPreferencesStore.load(defaults: defaults) == saved)
        let next = TransactionDraft(transaction: nil, defaults: defaults)
        next.prepare(cards: [first, second])
        #expect(next.cardID == second.id); #expect(next.category == "购物"); #expect(next.paymentMethod == "支付宝")
        #expect(next.merchant.isEmpty); #expect(next.amount == 0)
        #expect(next.currency == "HKD"); #expect(next.region.isEmpty)
        next.merchant = "Shop"; next.amount = 120; next.date = draft.date
        next.category = "超市"; next.paymentMethod = "BoC Pay"
        #expect(!next.save(in: context, cards: [first, second])); #expect(next.possibleDuplicate != nil)
        next.cancelDuplicateConfirmation()
        #expect(QuickEntryPreferencesStore.load(defaults: defaults) == saved)
        #expect(next.save(in: context, cards: [first, second], allowPossibleDuplicate: true))
        #expect(QuickEntryPreferencesStore.load(defaults: defaults)?.category == "超市")
        #expect(QuickEntryPreferencesStore.load(defaults: defaults)?.paymentMethod == "BoC Pay")
    }

    @Test func missingOrArchivedPreferredCardsFallBackButAnExplicitCardChoiceWins() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let active = BankCard(bank: "Bank", name: "Active"), archived = BankCard(bank: "Bank", name: "Archived")
        context.insert(active); context.insert(archived); archived.isArchived = true
        let preferences = QuickEntryPreferences(cardKey: archived.syncKey, category: "餐饮", paymentMethod: "Apple Pay")
        let draft = TransactionDraft(transaction: nil, preferences: preferences)
        draft.prepare(cards: [archived, active]); #expect(draft.cardID == active.id)
        let missing = TransactionDraft(transaction: nil, preferences: QuickEntryPreferences(cardKey: "card:missing", category: "餐饮", paymentMethod: "Apple Pay"))
        missing.prepare(cards: [active]); #expect(missing.cardID == active.id)
        archived.isArchived = false
        let explicit = TransactionDraft(transaction: nil, preferences: QuickEntryPreferences(cardKey: active.syncKey, category: "餐饮", paymentMethod: "Apple Pay"))
        explicit.cardID = archived.id; explicit.prepare(cards: [active, archived])
        #expect(explicit.cardID == archived.id)
    }

    @Test func preferencesUseStableCatalogIdentityAndDoNotOverrideAnEditedTransactionsDetails() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Bank", name: "Renamed card"); card.catalogID = "catalog.card"; context.insert(card)
        let preferences = QuickEntryPreferences(cardKey: "card:catalog:catalog.card", category: "交通", paymentMethod: "实体卡")
        let new = TransactionDraft(transaction: nil, preferences: preferences); new.prepare(cards: [card])
        #expect(new.cardID == card.id)
        let transaction = SpendTransaction(merchant: "Flight", amountCents: 10000, category: "旅行", paymentMethod: "Apple Pay", card: card)
        transaction.region = "MO"; transaction.isOverseas = true; context.insert(transaction)
        let edit = TransactionDraft(transaction: transaction, preferences: preferences); edit.prepare(cards: [card])
        #expect(edit.category == "旅行"); #expect(edit.paymentMethod == "Apple Pay")
        #expect(edit.region == "MO"); #expect(edit.isOverseas)
    }

    @Test func changingCurrencyNeverGuessesMainlandLocationOrErasesAnExplicitRegion() throws {
        let draft = TransactionDraft(transaction: nil)
        draft.currency = "CNY"
        #expect(draft.region.isEmpty); #expect(draft.exchangeRate == 0)
        draft.region = "MO"; draft.currency = "USD"
        #expect(draft.region == "MO"); #expect(draft.isOverseas)
        draft.currency = "HKD"
        #expect(draft.region == "MO"); #expect(draft.exchangeRate == 1)
        let hongKong = TransactionDraft(transaction: nil)
        hongKong.region = "HK"; hongKong.currency = "CNY"
        #expect(hongKong.region == "HK"); #expect(!hongKong.isOverseas)
        let transaction = SpendTransaction(merchant: "Unknown location", amountCents: 1000, currency: "CNY", exchangeRate: "1.1")
        let edit = TransactionDraft(transaction: transaction)
        edit.currency = "HKD"
        #expect(edit.region.isEmpty)
    }
}
