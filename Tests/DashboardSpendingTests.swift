import Foundation
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
}
