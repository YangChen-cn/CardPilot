import Foundation
import SwiftData

enum DemoData {
    @MainActor static func populate(_ context: ModelContext) throws {
        try CatalogImporter.installBundledExampleIfNeeded(context)
        guard let chill = try context.fetch(FetchDescriptor<BankCard>()).first else { return }
        let start = HKCalendar.calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let end = HKCalendar.calendar.date(byAdding: .day, value: 18, to: .now) ?? .now
        let hsbc = BankCard(bank: "HSBC", name: "Red · 演示卡", network: "Mastercard", lastFour: "8028", statementDay: 12, paymentDay: 6, baseRateBps: 100, theme: "red")
        let bea = BankCard(bank: "BEA 东亚银行", name: "日常消费 · 演示卡", lastFour: "1886", statementDay: 20, paymentDay: 15, baseRateBps: 100, theme: "blue")
        context.insert(hsbc); context.insert(bea)
        let welcome = RewardRule(name: "首三个月消费目标 · 演示", kind: "welcome", card: hsbc,
                                 thresholdCents: 800_000, bonusCents: 80_000, startsOn: start, endsOn: end)
        context.insert(welcome)
        let examples: [(String, Int64, SpendCategory, Int, BankCard)] = [
            ("Citysuper", 126_800, .groceries, 0, chill), ("Apple Store", 159_900, .shopping, 1, hsbc),
            ("Blue Bottle Coffee", 6_800, .dining, 2, bea), ("UNIQLO", 89_900, .shopping, 3, hsbc),
            ("MTR", 12_000, .transport, 4, bea), ("Netflix", 10_800, .entertainment, 5, chill),
            ("Cathay Pacific", 248_000, .travel, 6, hsbc), ("Starbucks", 9_600, .dining, 7, chill),
            ("MARKS & SPENCER", 35_800, .groceries, 8, hsbc), ("The Coffee Academics", 18_400, .dining, 9, hsbc)
        ]
        for (merchant, amount, category, offset, card) in examples {
            let date = HKCalendar.calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            let transaction = SpendTransaction(merchant: merchant, amountCents: amount, category: category.rawValue,
                                               date: date, notes: "演示数据", card: card)
            if merchant == "Netflix" || merchant == "Apple Store" { transaction.channel = "online" }
            context.insert(transaction)
        }
        try context.save()
    }
}
