import Foundation
import OSLog
import SwiftData

/// Explicit local command for an agent to add catalog products and set user-provided tails.
/// Uses the same import and persistence services as the app; never enables personal welcomes.
@MainActor enum LibraryCardConfiguration {
    private static let logger = Logger(subsystem: "com.cardpilot.app", category: "CardConfiguration")

    static func apply(_ entries: [String: String], in context: ModelContext) throws -> MailImportResult {
        let library = try BankLibrary.load()
        guard !entries.isEmpty, entries.count <= 20,
              entries.allSatisfy({ id, tail in
                  library.products.contains { $0.id == id } && tail.count == 4 && tail.allSatisfy { $0.isASCII && $0.isNumber }
              }) else { throw PilotError.invalid("请提供资料库产品 ID 及用户确认的4位尾号。") }
        var result = MailImportResult()
        try Persistence.save(context) {
            for id in entries.keys.sorted() {
                guard let product = library.products.first(where: { $0.id == id }) else { continue }
                let card = try LibraryOnboarding.add(product: product, in: context, commit: false)
                guard !card.isArchived else { throw PilotError.invalid("对应卡片已归档，请先恢复后再填写尾号。") }
                if card.lastFour != entries[id] {
                    card.lastFour = entries[id] ?? ""; card.modifiedAt = .now
                    try Persistence.setProfileRevision(cardKey: card.syncKey, date: .now, context: context, advancing: true)
                }
            }
            // Retry after this outer transaction has saved all cards and their personal tails.
        }
        result = try MailImportService.retryPending(in: context)
        return result
    }

    static func performRequested(in context: ModelContext) {
        guard !RuntimeMode.isEphemeral,
              let flag = ProcessInfo.processInfo.arguments.firstIndex(of: "--configure-library-cards") else { return }
        do {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.indices.contains(flag + 1) else { throw PilotError.invalid("缺少卡片配置参数。") }
            var entries: [String: String] = [:]
            for entry in arguments[flag + 1].split(separator: ",") {
                let fields = entry.split(separator: "=", omittingEmptySubsequences: false)
                guard fields.count == 2, entries[String(fields[0])] == nil else { throw PilotError.invalid("卡片配置参数无效或重复。") }
                entries[String(fields[0])] = String(fields[1])
            }
            let result = try apply(entries, in: context)
            let cards = try context.fetch(FetchDescriptor<BankCard>())
            let reviews = try MailImportService.reviewItems(in: context)
            let groups = Dictionary(grouping: reviews, by: { "\($0.mail.bankID):\($0.cardKey == nil ? "card" : "review")" })
                .mapValues(\.count)
            // These logs intentionally omit merchants, amounts, message IDs and credentials.
            let configured = cards.filter { entries[$0.catalogID] != nil }.map { "\($0.catalogID):tailMatches=\($0.lastFour == entries[$0.catalogID])" }.sorted().joined(separator: ",")
            let pending = groups.keys.sorted().map { "\($0)=\(groups[$0] ?? 0)" }.joined(separator: ",")
            logger.notice("Configured \(configured, privacy: .public); cards=\(cards.count); imported=\(result.saved); updated=\(result.updated); pending=\(reviews.count); groups=\(pending, privacy: .public)")
        } catch {
            let message = PilotError.message(error, fallback: "配置未能完成，原账本已保留。")
            logger.error("Card configuration failed: \(message, privacy: .public)")
        }
    }
}
