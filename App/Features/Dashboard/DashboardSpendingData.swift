import Foundation
import SwiftData

/// The dashboard reads six calendar months for charts and only three records for its recent list.
/// Live models remain on the main actor; the statistical calculation uses plain, immutable inputs.
@MainActor
struct DashboardSpendingData {
    let snapshot: DashboardSnapshot
    let recent: [SpendTransaction]

    static func load(in context: ModelContext, now: Date = .now) async throws -> Self {
        let start = DashboardSnapshot.historyStart(now: now)
        let history = FetchDescriptor<SpendTransaction>(predicate: #Predicate {
            $0.date >= start && $0.date <= now
        })
        let inputs = try context.fetch(history).map(SpendInput.init)
        let cards = try context.fetch(FetchDescriptor<BankCard>())
        let names = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.name) })
        var latest = FetchDescriptor<SpendTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        latest.fetchLimit = 3
        let recent = try context.fetch(latest)
        let snapshot = await Task.detached(priority: .userInitiated) {
            DashboardSnapshot(inputs: inputs, cardNames: names, now: now)
        }.value
        try Task.checkCancellation()
        return Self(snapshot: snapshot, recent: recent)
    }
}
