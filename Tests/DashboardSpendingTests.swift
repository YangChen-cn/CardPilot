import Foundation
import SwiftData
import Testing
@testable import CardPilot

struct DashboardSpendingTests {
    @Test func originalCurrencyIsPreservedAndNeverUsedAsAnInventedHKDValue() throws {
        let now = try CatalogImporter.date("2026-10-22")
        let card = UUID()
        var hkd = SpendInput(cardID: card, merchant: "Example", amountCents: 10000, date: try CatalogImporter.date("2026-10-10"))
        hkd.category = "餐饮"
        var cny = SpendInput(cardID: card, merchant: "Example", amountCents: 20000, currency: "CNY", exchangeRate: "", date: try CatalogImporter.date("2026-10-12"))
        cny.category = "购物"
        let usd = SpendInput(cardID: nil, merchant: "Example", amountCents: 1000, currency: "USD", exchangeRate: "7.8", date: try CatalogImporter.date("2026-10-15"))
        let future = SpendInput(cardID: card, merchant: "Future", amountCents: 100000, date: try CatalogImporter.date("2026-10-30"))
        let snapshot = DashboardSnapshot(inputs: [hkd, cny, usd, future], cardNames: [card: "Example card"], now: now)
        #expect(snapshot.monthSpend == 17800)
        #expect(snapshot.monthCount == 3)
        #expect(snapshot.unvaluedCount == 1)
        #expect(snapshot.originalTotals.contains(Money.text(20000, currency: "CNY")))
        #expect(!snapshot.originalTotals.contains("HKD"))
        #expect(snapshot.categories.reduce(0) { $0 + $1.cents } == 17800)
        #expect(snapshot.cardTotals.first { $0.id == card }?.cents == 10000)
        #expect(snapshot.cardTotals.first { $0.id == card }?.unvaluedCount == 1)
    }

    @Test func monthlyStatisticsDoNotCountBoundaryPurchaseTwice() throws {
        let now = try CatalogImporter.date("2026-10-22")
        let purchase = SpendInput(cardID: nil, merchant: "Example", amountCents: 12345, date: try CatalogImporter.date("2026-10-01"))
        let snapshot = DashboardSnapshot(inputs: [purchase], now: now)
        #expect(snapshot.monthly.count == 6)
        #expect(snapshot.monthly.reduce(0) { $0 + $1.cents } == 12345)
        #expect(snapshot.monthly.last?.cents == 12345)
    }

    @Test @MainActor func boundedHistoryAndRecentListHaveIndependentScopes() async throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let now = try CatalogImporter.date("2026-10-22")
        let oldest = DashboardSnapshot.historyStart(now: now)
        #expect(oldest == (try CatalogImporter.date("2026-05-01")))
        let old = SpendTransaction(merchant: "Old", amountCents: 10000, date: oldest.addingTimeInterval(-1))
        context.insert(old)
        try context.save()
        let initial = try await DashboardSpendingData.load(in: context, now: now)
        #expect(initial.snapshot.monthly.allSatisfy { $0.cents == 0 })
        #expect(initial.recent.map(\.id) == [old.id])

        for (date, amount) in [(oldest, Int64(200)), (now.addingTimeInterval(-2), 300), (now.addingTimeInterval(-1), 400), (now, 500)] {
            context.insert(SpendTransaction(merchant: "Purchase", amountCents: amount, date: date))
        }
        try context.save()
        let data = try await DashboardSpendingData.load(in: context, now: now)
        #expect(data.snapshot.monthly.first?.cents == 200)
        #expect(data.snapshot.monthSpend == 1200)
        #expect(data.snapshot.monthCount == 3)
        #expect(data.recent.count == 3)
        #expect(!data.recent.contains { $0.id == old.id })
    }

    @Test @MainActor func refreshReflectsSavedEditsCardNamesDeletionAndMonthRollover() async throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let now = try CatalogImporter.date("2026-10-22")
        let card = BankCard(bank: "Test", name: "Original")
        let purchase = SpendTransaction(merchant: "Purchase", amountCents: 100, date: now, card: card)
        context.insert(card); context.insert(purchase)
        try context.save()
        let initial = try await DashboardSpendingData.load(in: context, now: now)
        #expect(initial.snapshot.monthSpend == 100)

        purchase.amountCents = 250
        card.name = "Renamed"
        card.isArchived = true
        try context.save()
        let edited = try await DashboardSpendingData.load(in: context, now: now)
        #expect(edited.snapshot.monthSpend == 250)
        #expect(edited.snapshot.cardTotals.first?.name == "Renamed")

        let nextMonth = try CatalogImporter.date("2026-11-01")
        let rolled = try await DashboardSpendingData.load(in: context, now: nextMonth)
        #expect(rolled.snapshot.monthCount == 0)
        #expect(rolled.snapshot.monthly.dropLast().last?.cents == 250)
        purchase.date = nextMonth
        try context.save()
        #expect(try await DashboardSpendingData.load(in: context, now: nextMonth).snapshot.monthSpend == 250)

        context.delete(purchase)
        try context.save()
        let deleted = try await DashboardSpendingData.load(in: context, now: nextMonth)
        #expect(deleted.snapshot.monthCount == 0)
        #expect(deleted.recent.isEmpty)
    }

    @Test @MainActor func synchronizedTransactionsRefreshTheSameSnapshot() async throws {
        let source = try Persistence.makeContainer(inMemory: true)
        let destination = try Persistence.makeContainer(inMemory: true)
        let now = try CatalogImporter.date("2026-10-22")
        let card = BankCard(bank: "Test", name: "Synced card")
        card.catalogID = "test.dashboard"
        source.mainContext.insert(card)
        source.mainContext.insert(SpendTransaction(merchant: "Purchase", amountCents: 1234, date: now, card: card))
        try source.mainContext.save()
        #expect(try await DashboardSpendingData.load(in: destination.mainContext, now: now).snapshot.monthCount == 0)
        #expect(try SyncStore.apply(SyncStore.records(source.mainContext), context: destination.mainContext))
        let data = try await DashboardSpendingData.load(in: destination.mainContext, now: now)
        #expect(data.snapshot.monthSpend == 1234)
        #expect(data.snapshot.cardTotals.first?.name == "Synced card")
        #expect(data.recent.count == 1)
    }
}
