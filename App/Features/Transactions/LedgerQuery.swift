import Foundation
import SwiftData

/// A bounded, read-only ledger query. The month is interpreted in Hong Kong time.
struct LedgerQuery: Equatable {
    /// nil means the user explicitly chose all history.
    var month: Date?
    var cardID: UUID?
    var category: String?
    var search = ""

    var interval: DateInterval? {
        month.flatMap { HKCalendar.calendar.dateInterval(of: .month, for: $0) }
    }

    static func monthStart(_ date: Date) -> Date {
        HKCalendar.calendar.dateInterval(of: .month, for: date)?.start ?? HKCalendar.start(date)
    }
}

@MainActor
struct LedgerPage {
    var records: [SpendTransaction]
    /// nil when the complete result is loaded. Otherwise this is a source-row offset,
    /// not a guessed transaction identity; a save restarts the query.
    var nextOffset: Int?
    var scannedCount: Int
}

@MainActor
enum LedgerData {
    private static let batchSize = 200
    static let historyPageSize = 100

    static func load(_ query: LedgerQuery, in context: ModelContext,
                     from offset: Int = 0, pageSize: Int = historyPageSize) async throws -> LedgerPage {
        let descriptor = descriptor(for: query)
        let search = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.month != nil {
            let records = try context.fetch(descriptor)
            try Task.checkCancellation()
            return LedgerPage(records: records.filter { matches($0, search: search) },
                              nextOffset: nil, scannedCount: records.count)
        }

        // Search all history in bounded source batches. Yield between batches so a
        // sparse match cannot monopolize the main actor; never load the full ledger.
        let limit = max(1, pageSize)
        var cursor = max(0, offset)
        var scanned = 0
        var matches: [SpendTransaction] = []
        while true {
            try Task.checkCancellation()
            var batchDescriptor = descriptor
            batchDescriptor.fetchOffset = cursor
            batchDescriptor.fetchLimit = batchSize
            let batch = try context.fetch(batchDescriptor)
            scanned += batch.count
            guard !batch.isEmpty else { return LedgerPage(records: matches, nextOffset: nil, scannedCount: scanned) }
            for transaction in batch {
                if self.matches(transaction, search: search) {
                    // Probe one matching row beyond the page; leave it for the next page.
                    if matches.count == limit {
                        return LedgerPage(records: matches, nextOffset: cursor, scannedCount: scanned)
                    }
                    matches.append(transaction)
                }
                cursor += 1
            }
            if batch.count < batchSize {
                return LedgerPage(records: matches, nextOffset: nil, scannedCount: scanned)
            }
            await Task.yield()
        }
    }

    private static func descriptor(for query: LedgerQuery) -> FetchDescriptor<SpendTransaction> {
        let start = query.interval?.start ?? .distantPast
        let end = query.interval?.end ?? .distantFuture
        let predicate: Predicate<SpendTransaction>
        switch (query.cardID, query.category) {
        case let (.some(card), .some(category)):
            predicate = #Predicate { $0.date >= start && $0.date < end && $0.card?.id == card && $0.category == category }
        case let (.some(card), .none):
            predicate = #Predicate { $0.date >= start && $0.date < end && $0.card?.id == card }
        case let (.none, .some(category)):
            predicate = #Predicate { $0.date >= start && $0.date < end && $0.category == category }
        case (.none, .none):
            predicate = #Predicate { $0.date >= start && $0.date < end }
        }
        return FetchDescriptor(predicate: predicate, sortBy: [
            SortDescriptor(\SpendTransaction.date, order: .reverse),
            SortDescriptor(\SpendTransaction.createdAt, order: .reverse),
            SortDescriptor(\SpendTransaction.id, order: .reverse)
        ])
    }

    private static func matches(_ transaction: SpendTransaction, search: String) -> Bool {
        guard !search.isEmpty else { return true }
        return transaction.merchant.localizedStandardContains(search)
            || transaction.notes.localizedStandardContains(search)
            || transaction.category.localizedStandardContains(search)
            || (transaction.card?.displayName.localizedStandardContains(search) ?? false)
    }
}
