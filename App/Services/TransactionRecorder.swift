import Foundation
import SwiftData
import CryptoKit

@MainActor enum TransactionRecorder {
    /// All sources share the same check. An identity proves a retry; similar fields only ask for review.
    static func assess(_ request: TransactionRequest, in context: ModelContext,
                       excludingID: UUID? = nil, editing existing: SpendTransaction? = nil) throws -> TransactionDuplicate? {
        try validate(request, now: .now)
        let card = try resolveCard(request, in: context, allowingArchivedID: existing?.card?.id)
        let ignored = excludingID ?? existing?.id
        return duplicate(request, card: card, previous: card.transactions.filter { $0.id != ignored })
    }

    static func record(_ request: TransactionRequest, in context: ModelContext,
                       allowPossibleDuplicate: Bool = false, editing existing: SpendTransaction? = nil,
                       now: Date = .now) throws -> TransactionRecordResult {
        try validate(request, now: now)
        let card = try resolveCard(request, in: context, allowingArchivedID: existing?.card?.id)
        if existing == nil, let reconciled = try MailImportService.reconcileIncoming(request, card: card,
                                                                                   identity: identity(request, card: card),
                                                                                   allowPossibleDuplicate: allowPossibleDuplicate, in: context) {
            return reconciled
        }
        let previous = card.transactions.filter { $0.id != existing?.id }
        if let match = duplicate(request, card: card, previous: previous) {
            if match.isExact { return .duplicate(match.id) }
            if !allowPossibleDuplicate {
                let key = reviewKey(request, card: card)
                if let review = try DocumentStore.record(key, in: context), review.isDeleted {
                    return .duplicate(match.id)
                }
                try DocumentStore.put(request, key: key, kind: "review", in: context)
                return .needsReview(key)
            }
        }
        let transaction = existing ?? SpendTransaction(merchant: "", amountCents: request.amountCents)
        let oldSyncKey = existing?.syncKey
        if existing == nil {
            transaction.source = request.source
            transaction.externalID = identity(request, card: card)
            context.insert(transaction)
        }
        transaction.merchant = request.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.amountCents = request.amountCents; transaction.currency = request.currency
        transaction.exchangeRate = request.currency == "HKD" ? "1" : request.exchangeRate
        transaction.date = request.date; transaction.card = card
        transaction.paymentMethod = request.paymentMethod; transaction.category = request.category
        transaction.channel = request.channel
        transaction.isOverseas = request.isOverseas || ["CN", "MO", "other"].contains(request.region)
        transaction.region = request.region
        transaction.isRewardEligible = request.isRewardEligible ?? true; transaction.notes = request.notes ?? ""
        transaction.modifiedAt = now; card.modifiedAt = now
        if let oldSyncKey, oldSyncKey != transaction.syncKey {
            Persistence.markDeleted(key: oldSyncKey, context: context, now: now)
        }
        return .recorded(transaction.id)
    }

    private static func resolveCard(_ request: TransactionRequest, in context: ModelContext,
                                    allowingArchivedID: UUID?) throws -> BankCard {
        let cards = try context.fetch(FetchDescriptor<BankCard>()).filter {
            (!$0.isArchived || $0.id == allowingArchivedID) && ($0.syncKey == request.cardID || $0.id.uuidString == request.cardID)
        }
        guard cards.count == 1, let card = cards.first else { throw PilotError.invalid("请选择一张有效的银行卡。") }
        return card
    }

    private static func validate(_ request: TransactionRequest, now: Date) throws {
        let merchant = request.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let rate = Decimal(string: request.exchangeRate) ?? 0
        guard !merchant.isEmpty, merchant.count <= 500, (1...10_000_000_000).contains(request.amountCents),
              Currency(rawValue: request.currency) != nil,
              (request.exchangeRate.isEmpty || !rate.isNaN && rate > 0 && rate <= 1000),
              PaymentMethod(rawValue: request.paymentMethod) != nil, SpendCategory(rawValue: request.category) != nil,
              ["physical", "online", "unknown"].contains(request.channel), request.externalID.count <= 512,
              ["", "HK", "CN", "MO", "other"].contains(request.region),
              request.date.timeIntervalSince1970.isFinite, request.date <= now.addingTimeInterval(300) else {
            throw PilotError.invalid("请检查交易金额、时间、币种和支付方式。")
        }
    }

    private static func duplicate(_ request: TransactionRequest, card: BankCard,
                                  previous: [SpendTransaction]) -> TransactionDuplicate? {
        if !request.externalID.isEmpty, let exact = previous.first(where: {
            ($0.externalID == request.externalID && (!request.externalID.hasPrefix("csv-row:") || $0.source == request.source)) ||
            (request.source == "csv" && $0.id.uuidString.caseInsensitiveCompare(request.externalID) == .orderedSame)
        }) { return TransactionDuplicate(transaction: exact, isExact: true) }
        // Preserve idempotent Wallet retries without treating a different source's matching timestamp as proof.
        if request.source == "shortcuts", request.externalID.isEmpty, request.hasStableDate {
            let fingerprint = fingerprint(request, card: card)
            if let exact = previous.first(where: { $0.source == "shortcuts" && $0.externalID == fingerprint }) {
                return TransactionDuplicate(transaction: exact, isExact: true)
            }
        }
        let normalized = normalizedMerchant(request.merchant)
        let candidates = previous.filter { previous in
            guard previous.amountCents == request.amountCents, previous.currency == request.currency,
                  normalizedMerchant(previous.merchant) == normalized else { return false }
            // Two different bank references from the same source identify separate real purchases.
            if previous.source == request.source, isTrustedReference(previous.externalID), isTrustedReference(request.externalID),
               previous.externalID != request.externalID { return false }
            let incomingDateOnly = ["csv", "sms"].contains(request.source) && !request.hasStableDate
            let previousDateOnly = ["csv", "sms", "email"].contains(previous.source) && previous.date == HKCalendar.start(previous.date)
            if incomingDateOnly || previousDateOnly { return HKCalendar.calendar.isDate(previous.date, inSameDayAs: request.date) }
            return abs(previous.date.timeIntervalSince(request.date)) <= 90
        }
        guard let possible = candidates.min(by: {
            let lhs = abs($0.date.timeIntervalSince(request.date)), rhs = abs($1.date.timeIntervalSince(request.date))
            return lhs != rhs ? lhs < rhs : $0.id.uuidString < $1.id.uuidString
        }) else { return nil }
        return TransactionDuplicate(transaction: possible, isExact: false)
    }

    private static func isTrustedReference(_ value: String) -> Bool {
        !value.isEmpty && !["auto:", "auto-unverified:", "csv-row:", "bankmail:"].contains(where: { value.hasPrefix($0) })
    }

    private static func normalizedMerchant(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func fingerprint(_ request: TransactionRequest, card: BankCard) -> String {
        let fields = [card.syncKey, normalizedMerchant(request.merchant), String(request.amountCents), request.currency,
                      request.paymentMethod, String(Int64((request.date.timeIntervalSince1970 * 1000).rounded()))]
        return "auto:" + digest(fields.joined(separator: "\u{1f}"))
    }

    private static func reviewKey(_ request: TransactionRequest, card: BankCard) -> String {
        "review:" + digest([fingerprint(request, card: card), request.source, request.externalID].joined(separator: "\u{1f}"))
    }

    private static func identity(_ request: TransactionRequest, card: BankCard) -> String {
        if !request.externalID.isEmpty { return request.externalID }
        if request.source == "shortcuts" {
            return request.hasStableDate ? fingerprint(request, card: card) : "auto-unverified:" + UUID().uuidString
        }
        return request.source == "manual" ? "" : "auto-unverified:" + UUID().uuidString
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
