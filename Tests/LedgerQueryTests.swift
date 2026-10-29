import Foundation
import SwiftData
import Testing
@testable import CardPilot

@Suite(.serialized) @MainActor
struct LedgerQueryTests {
    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }

    @Test func monthBoundariesUseHongKongTimeAndApplyCardAndCategory() async throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let first = BankCard(bank: "A", name: "First"), second = BankCard(bank: "B", name: "Second")
        context.insert(first); context.insert(second)
        let january = try date("2026-01-31T15:59:59Z") // Jan 31, 23:59:59 in Hong Kong
        let february = try date("2026-01-31T16:00:00Z") // Feb 1, 00:00 in Hong Kong
        let janRecord = SpendTransaction(merchant: "One", amountCents: 100, category: "餐饮", date: january, card: first)
        let febRecord = SpendTransaction(merchant: "Two", amountCents: 200, category: "餐饮", date: february, card: first)
        let otherCard = SpendTransaction(merchant: "Three", amountCents: 300, category: "餐饮", date: february, card: second)
        let otherCategory = SpendTransaction(merchant: "Four", amountCents: 400, category: "其他", date: february, card: first)
        [janRecord, febRecord, otherCard, otherCategory].forEach(context.insert)
        try context.save()

        let query = LedgerQuery(month: february, cardID: first.id, category: "餐饮")
        let result = try await LedgerData.load(query, in: context)
        #expect(result.records.map(\.id) == [febRecord.id])
        #expect(result.nextOffset == nil)
        #expect(result.scannedCount == 1)
        let interval = try #require(query.interval)
        #expect(interval.start == february)
        #expect(!interval.contains(january))
    }

    @Test func monthAcrossYearBoundaryUsesHalfOpenInterval() throws {
        let dec = try date("2026-12-10T00:00:00Z")
        let start = try #require(LedgerQuery(month: dec, cardID: nil, category: nil).interval?.start)
        let end = try #require(LedgerQuery(month: dec, cardID: nil, category: nil).interval?.end)
        #expect(start == (try date("2026-11-30T16:00:00Z")))
        #expect(end == (try date("2026-12-31T16:00:00Z")))
        #expect(LedgerQuery.monthStart(end) == end)
    }

    @Test func allHistorySearchPagesWithoutLosingOrRepeatingMatches() async throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        var expected: Set<UUID> = []
        let base = try date("2026-01-01T12:00:00Z")
        for index in 0..<275 {
            let matched = index % 5 != 0
            let transaction = SpendTransaction(merchant: matched ? "Cafe Sample" : "Other", amountCents: 100,
                                               date: base.addingTimeInterval(Double(index)))
            transaction.createdAt = base.addingTimeInterval(Double(index))
            context.insert(transaction)
            if matched { expected.insert(transaction.id) }
        }
        try context.save()
        let query = LedgerQuery(month: nil, cardID: nil, category: nil, search: "cafe")
        var offset = 0, resultIDs: [UUID] = []
        repeat {
            let page = try await LedgerData.load(query, in: context, from: offset)
            #expect(page.records.count <= 100)
            resultIDs.append(contentsOf: page.records.map(\.id))
            guard let next = page.nextOffset else { break }
            #expect(next > offset)
            offset = next
        } while true
        #expect(resultIDs.count == expected.count)
        #expect(Set(resultIDs) == expected)
    }

    @Test func sparseHistorySearchCanScanPastFirstBatch() async throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let base = try date("2026-02-01T12:00:00Z")
        for index in 0..<225 {
            let transaction = SpendTransaction(merchant: index == 0 ? "Needle Shop" : "Other", amountCents: 100,
                                               date: base.addingTimeInterval(Double(index)))
            transaction.createdAt = base.addingTimeInterval(Double(index))
            context.insert(transaction)
        }
        try context.save()
        let page = try await LedgerData.load(LedgerQuery(month: nil, cardID: nil, category: nil, search: "Needle"), in: context)
        #expect(page.records.map(\.merchant) == ["Needle Shop"])
        #expect(page.nextOffset == nil)
        #expect(page.scannedCount == 225)
    }

    @Test(arguments: [1_000, 10_000])
    func isolatedBenchmarkComparesWholeLedgerAndMonthlyQuery(count: Int) async throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let base = try date("2026-10-15T12:00:00Z")
        for index in 0..<count {
            let date = try #require(HKCalendar.calendar.date(byAdding: .month, value: -(index % 24), to: base))
            let transaction = SpendTransaction(merchant: "Benchmark", amountCents: 100, date: date)
            transaction.createdAt = base.addingTimeInterval(Double(index))
            context.insert(transaction)
        }
        try context.save()
        let query = LedgerQuery(month: base, cardID: nil, category: nil)
        let interval = try #require(query.interval)
        let clock = ContinuousClock()
        // Separate read contexts keep the benchmark from reusing registered models
        // from insertion or the preceding full-ledger fetch.
        let oldReader = ModelContext(container), newReader = ModelContext(container)
        let allStart = clock.now
        let allRecords = try oldReader.fetch(FetchDescriptor<SpendTransaction>())
        let baselineCount = allRecords.filter { $0.date >= interval.start && $0.date < interval.end }.count
        let allDuration = clock.now - allStart
        let monthStart = clock.now
        let monthPage = try await LedgerData.load(query, in: newReader)
        let monthDuration = clock.now - monthStart
        #expect(allRecords.count == count)
        #expect(monthPage.records.count == baselineCount)
        #expect(monthPage.scannedCount < allRecords.count)
        print("Ledger benchmark \(count): old fetch \(allRecords.count) records in \(allDuration); month fetch \(monthPage.scannedCount) records in \(monthDuration)")
    }
}
