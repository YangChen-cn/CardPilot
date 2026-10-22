import Foundation
import SwiftData

@MainActor enum MailImportService {
    static func importTransactions(_ messages: [BankMailTransaction], in context: ModelContext,
                                   reconsiderReviews: Bool = false) throws -> MailImportResult {
        guard messages.count <= 10_000, messages.allSatisfy(MailEvidence.valid) else {
            throw PilotError.invalid("银行邮件交易资料不完整，未修改账本。")
        }
        var result = MailImportResult()
        try Persistence.save(context) {
            for mail in messages {
                let outcome = try process(mail, reconsiderReviews: reconsiderReviews, in: context)
                if outcome.saved + outcome.updated > 0 { try DocumentStore.remove(MailReview.key(for: mail), in: context) }
                result.saved += outcome.saved; result.updated += outcome.updated
                result.duplicate += outcome.duplicate; result.pending += outcome.pending
            }
            _ = try SyncStore.apply([], context: context, saving: false)
        }
        return result
    }

    /// Retry locally saved evidence after adding a card or filling its tail. No Gmail refetch is needed.
    static func retryPending(in context: ModelContext) throws -> MailImportResult {
        try importTransactions(reviewItems(in: context).map(\.mail), in: context, reconsiderReviews: true)
    }

    static func reviewItems(in context: ModelContext) throws -> [MailReview] {
        try context.fetch(FetchDescriptor<DomainRecord>()).filter { $0.kind == "mailReview" && !$0.isDeleted }
            .map { try SyncCodec.decoder().decode(MailReview.self, from: $0.content) }
            .sorted { $0.mail.receivedAt == $1.mail.receivedAt ? $0.key < $1.key : $0.mail.receivedAt > $1.mail.receivedAt }
    }

    static func resolveReview(key: String, transactionKey: String? = nil, cardKey: String? = nil,
                              exchangeRate: String? = nil, saveAsAnother: Bool = false,
                              in context: ModelContext) throws -> MailImportResult {
        guard let review = try DocumentStore.load(MailReview.self, key: key, in: context) else {
            throw PilotError.invalid("这项邮件已处理，请刷新列表。")
        }
        var result = MailImportResult()
        try Persistence.save(context) {
            let transactions = try context.fetch(FetchDescriptor<SpendTransaction>())
            let target = transactionKey.flatMap { key in transactions.first { $0.syncKey == key } }
            if transactionKey != nil && target == nil { throw PilotError.invalid("对应交易已删除，请重新选择。") }
            let cards = try context.fetch(FetchDescriptor<BankCard>())
            let card = cardKey.flatMap { key in cards.first { $0.syncKey == key } } ?? target?.card
                ?? matchingCards(review.mail, cards: cards).only
            guard let card, compatibleCards(for: review.mail, cards: [card]).count == 1,
                  target == nil || target?.card?.syncKey == card.syncKey else {
                throw PilotError.invalid("请选择这家银行的对应银行卡。")
            }
            guard target != nil || saveAsAnother else { throw PilotError.invalid("请选择对应交易，或确认保存为另一笔。") }
            result = try save(review.mail, card: card, target: target, rate: exchangeRate,
                              explicitlyMatched: target != nil, keepSeparate: saveAsAnother, in: context)
            try DocumentStore.remove(key, in: context)
            _ = try SyncStore.apply([], context: context, saving: false)
        }
        return result
    }

    static func ignoreReview(key: String, in context: ModelContext) throws {
        try Persistence.save(context) {
            if let review = try DocumentStore.load(MailReview.self, key: key, in: context),
               var evidence = try DocumentStore.load(MailEvidence.self, key: MailEvidence.key(for: review.mail), in: context) {
                evidence.keepSeparate = true
                try DocumentStore.put(evidence, key: evidence.key, kind: "mailEvidence", in: context)
            }
            try DocumentStore.remove(key, in: context)
        }
    }

    /// Called before the normal recorder. A known Wallet identity follows its synced alias,
    /// even after the canonical transaction has been deleted. A similarity alone needs a
    /// unique, unclaimed email receipt and never consumes a second real Wallet purchase.
    static func reconcileIncoming(_ request: TransactionRequest, card: BankCard, identity: String,
                                  allowPossibleDuplicate: Bool = false, in context: ModelContext) throws -> TransactionRecordResult? {
        guard request.source == "shortcuts", !identity.isEmpty else { return nil }
        let alias = MailEvidence.transactionKey(cardKey: card.syncKey, externalID: identity)
        let receipts = try evidence(in: context)
        if let linked = receipts.first(where: { $0.aliases.contains(alias) }) {
            let transaction = try context.fetch(FetchDescriptor<SpendTransaction>()).first { $0.syncKey == linked.transactionKey }
            return .duplicate(transaction?.id ?? SyncIdentity.id(for: linked.transactionKey))
        }
        // The old identity can already be a synced tombstone while its evidence document
        // is arriving. A stable retry still must not recreate that record.
        if try isDeleted(alias, in: context) { return .duplicate(SyncIdentity.id(for: alias)) }
        if allowPossibleDuplicate { return nil }
        let transactions = try context.fetch(FetchDescriptor<SpendTransaction>())
        let matching = receipts.filter { receipt in
            guard receipt.cardKey == card.syncKey, !receipt.keepSeparate,
                  receipt.aliases.isEmpty,
                  transactions.contains(where: { $0.syncKey == receipt.transactionKey }) else { return false }
            return matches(receipt.mail, request: request, merchantAliases: receipt.merchantAliases)
        }
        let groups = Dictionary(grouping: matching, by: \.transactionKey)
        guard groups.count == 1, let group = groups.values.first, let first = group.first,
              let transaction = transactions.first(where: { $0.syncKey == first.transactionKey }) else {
            let suspected = receipts.filter { receipt in
                guard receipt.cardKey == card.syncKey,
                      transactions.contains(where: { $0.syncKey == receipt.transactionKey }),
                      HKCalendar.calendar.isDate(receipt.mail.date, inSameDayAs: request.date),
                      !receipt.mail.hasExactTime || abs(receipt.mail.date.timeIntervalSince(request.date)) <= 180 else { return false }
                return (receipt.mail.amountCents == request.amountCents && receipt.mail.currency == request.currency)
                    || Set(([receipt.mail.merchant] + receipt.merchantAliases).map(MailEvidence.merchant)).contains(MailEvidence.merchant(request.merchant))
            }
            guard let first = suspected.first else { return nil }
            let key = "review:mail:" + MailEvidence.digest(alias)
            if let review = try DocumentStore.record(key, in: context), review.isDeleted {
                return .duplicate(transactions.first { $0.syncKey == first.transactionKey }?.id ?? SyncIdentity.id(for: first.transactionKey))
            }
            try DocumentStore.put(request, key: key, kind: "review", in: context)
            return .needsReview(key)
        }
        for var receipt in group {
            receipt.aliases = [alias]
            receipt.merchantAliases = Array(Set(receipt.merchantAliases + [request.merchant])).sorted()
            try DocumentStore.put(receipt, key: receipt.key, kind: "mailEvidence", in: context)
        }
        // Fill only missing context; all financial values continue to come from the email.
        if transaction.paymentMethod == "待确认" { transaction.paymentMethod = request.paymentMethod }
        if transaction.channel == "unknown" { transaction.channel = request.channel }
        if transaction.region.isEmpty { transaction.region = request.region; transaction.isOverseas = request.isOverseas }
        if transaction.category == "其他" { transaction.category = request.category }
        if transaction.notes.isEmpty { transaction.notes = request.notes ?? "" }
        transaction.isRewardEligible = transaction.isRewardEligible && (request.isRewardEligible ?? true)
        if !first.mail.hasExactTime { transaction.date = request.date }
        Persistence.markDeleted(key: alias, context: context)
        return .duplicate(transaction.id)
    }

    private static func process(_ mail: BankMailTransaction, reconsiderReviews: Bool, in context: ModelContext) throws -> MailImportResult {
        let evidenceKey = MailEvidence.key(for: mail), reviewKey = MailReview.key(for: mail)
        if let old = try DocumentStore.load(MailEvidence.self, key: evidenceKey, in: context) {
            if try isDeleted(old.transactionKey, in: context) { return MailImportResult(duplicate: 1) }
            if old.mail == mail { return MailImportResult(duplicate: 1) }
            if let card = try context.fetch(FetchDescriptor<BankCard>()).first(where: { $0.syncKey == old.cardKey }),
               let target = try context.fetch(FetchDescriptor<SpendTransaction>()).first(where: { $0.syncKey == old.transactionKey }) {
                if mail.currency != "HKD", old.mail.currency != mail.currency {
                    return try pending(mail, reason: "银行通知中的币种发生变化，请核对是否为同一笔消费。",
                                       candidates: [target.syncKey], cardKey: card.syncKey, in: context)
                }
                return try save(mail, card: card, target: target,
                                rate: target.currency == mail.currency ? target.exchangeRate : old.exchangeRate,
                                explicitlyMatched: old.explicitlyMatched, keepSeparate: old.keepSeparate, in: context)
            }
        }
        if let review = try DocumentStore.record(reviewKey, in: context) {
            if review.isDeleted { return MailImportResult(duplicate: 1) }
            if !reconsiderReviews { return MailImportResult(pending: 1) }
        }
        let cards = try context.fetch(FetchDescriptor<BankCard>())
        guard let card = matchingCards(mail, cards: cards).only else {
            let alternatives = try context.fetch(FetchDescriptor<SpendTransaction>()).filter {
                ["shortcuts", "manual", "csv", "sms", "email"].contains($0.source) && $0.card.map { compatibleCards(for: mail, cards: [$0]).count == 1 } == true
                    && MailEvidence.withinTimeWindow(mail, transaction: TransactionSyncData($0))
                    && ((mail.amountCents == $0.amountCents && mail.currency == $0.currency) || sameMerchantAndTime(mail, transaction: $0))
            }
            return try pending(mail, reason: missingCardReason(mail, cards: cards),
                               candidates: alternatives.map(\.syncKey), cardKey: nil, in: context)
        }
        let externalID = MailEvidence.identity(for: mail)
        let canonical = MailEvidence.transactionKey(cardKey: card.syncKey, externalID: externalID)
        if try isDeleted(canonical, in: context) { return MailImportResult(duplicate: 1) }
        let transactions = try context.fetch(FetchDescriptor<SpendTransaction>()).filter { $0.card?.syncKey == card.syncKey }
        if let target = transactions.first(where: { $0.syncKey == canonical }) {
            if mail.currency != "HKD", target.currency != mail.currency {
                return try pending(mail, reason: "银行通知中的币种发生变化，请核对是否为同一笔消费。",
                                   candidates: [target.syncKey], cardKey: card.syncKey, in: context)
            }
            return try save(mail, card: card, target: target, rate: target.exchangeRate,
                            explicitlyMatched: false, keepSeparate: false, in: context)
        }
        let receipts = try evidence(in: context)
        let aliases = receipts.filter {
            $0.cardKey == card.syncKey && $0.explicitlyMatched && MailEvidence.merchant($0.mail.merchant) == MailEvidence.merchant(mail.merchant)
        }.flatMap(\.merchantAliases)
        let candidates = transactions.filter {
            $0.source == "shortcuts" && MailEvidence.matches(mail, transaction: TransactionSyncData($0), aliases: aliases)
        }
        let claimed = Set(receipts.flatMap(\.aliases))
        let available = candidates.filter { !claimed.contains($0.syncKey) }
        if candidates.count > 1 || available.count != candidates.count {
            return try pending(mail, reason: "有多笔相似交易，请选择对应交易或保留为另一笔。",
                               candidates: candidates.map(\.syncKey), cardKey: card.syncKey, in: context)
        }
        let conflicts = transactions.filter { transaction in
            guard (["shortcuts", "manual", "csv", "sms"].contains(transaction.source) ||
                   (mail.source == "sms" && transaction.source == "email")),
                  MailEvidence.withinTimeWindow(mail, transaction: TransactionSyncData(transaction)) else { return false }
            return (mail.amountCents == transaction.amountCents && mail.currency == transaction.currency)
                || Set(([mail.merchant] + aliases).map(MailEvidence.merchant)).contains(MailEvidence.merchant(transaction.merchant))
        }
        if available.isEmpty, !conflicts.isEmpty {
            return try pending(mail, reason: "发现相似消费，请确认是否为同一笔；邮件、短信及手动记录可能对应同一交易。",
                               candidates: conflicts.map(\.syncKey), cardKey: card.syncKey, in: context)
        }
        return try save(mail, card: card, target: available.first, rate: nil,
                        explicitlyMatched: false, keepSeparate: false, in: context)
    }

    private static func save(_ mail: BankMailTransaction, card: BankCard, target: SpendTransaction?, rate: String?,
                             explicitlyMatched: Bool, keepSeparate: Bool, in context: ModelContext) throws -> MailImportResult {
        let known = try evidence(in: context)
        let prior = target.flatMap { target in known.first { $0.transactionKey == target.syncKey } }
        let externalID = prior?.externalID ?? MailEvidence.identity(for: mail)
        let key = prior?.transactionKey ?? MailEvidence.transactionKey(cardKey: card.syncKey, externalID: externalID)
        if try isDeleted(key, in: context) { return MailImportResult(duplicate: 1) }
        let originalKey = target?.syncKey
        let selectedRate = mail.currency == "HKD" ? "1" : rate ?? (target?.currency == mail.currency ? target?.exchangeRate : nil) ?? ""
        let decimal = Decimal(string: selectedRate) ?? 0
        guard mail.currency != "HKD" && selectedRate.isEmpty || !decimal.isNaN && decimal > 0 && decimal <= 1000 else {
            throw PilotError.invalid("请填写有效的港币估值汇率，或留空先按原币入账。")
        }
        var receipt = MailEvidence(key: MailEvidence.key(for: mail), mail: mail, cardKey: card.syncKey,
                                   transactionKey: key, externalID: externalID,
                                   aliases: prior?.aliases ?? [], merchantAliases: prior?.merchantAliases ?? [],
                                   exchangeRate: selectedRate, explicitlyMatched: explicitlyMatched, keepSeparate: keepSeparate)
        if let originalKey, originalKey != key { receipt.aliases.append(originalKey) }
        if let target { receipt.merchantAliases.append(target.merchant) }
        receipt.aliases = Array(Set(receipt.aliases)).sorted()
        receipt.merchantAliases = Array(Set(receipt.merchantAliases)).sorted()
        let canonical = try context.fetch(FetchDescriptor<SpendTransaction>()).first { $0.syncKey == key }
        let transaction = canonical ?? target ?? SpendTransaction(merchant: mail.merchant, amountCents: mail.amountCents,
                                                                  currency: mail.currency, exchangeRate: selectedRate,
                                                                  paymentMethod: "待确认", date: mail.date, source: mail.source, card: card)
        let isNew = canonical == nil && target == nil
        if isNew { transaction.channel = "unknown"; context.insert(transaction) }
        var value = TransactionSyncData(target ?? transaction)
        if value.currency == mail.currency { value.exchangeRate = selectedRate }
        MailReconciliation.project(receipt, onto: &value)
        value.apply(to: transaction); transaction.card = card; transaction.modifiedAt = .now
        if let target, target.id != transaction.id { context.delete(target) }
        if let originalKey, originalKey != key { Persistence.markDeleted(key: originalKey, context: context) }
        try DocumentStore.put(receipt, key: receipt.key, kind: "mailEvidence", in: context)
        return isNew ? MailImportResult(saved: 1) : MailImportResult(updated: 1)
    }

    private static func pending(_ mail: BankMailTransaction, reason: String, candidates: [String], cardKey: String?,
                                in context: ModelContext) throws -> MailImportResult {
        let review = MailReview(key: MailReview.key(for: mail), mail: mail, reason: reason,
                                candidateKeys: candidates.sorted(), cardKey: cardKey)
        if let existing = try DocumentStore.record(review.key, in: context), existing.isDeleted { return MailImportResult(duplicate: 1) }
        try DocumentStore.put(review, key: review.key, kind: "mailReview", in: context)
        return MailImportResult(pending: 1)
    }

    private static func evidence(in context: ModelContext) throws -> [MailEvidence] {
        try context.fetch(FetchDescriptor<DomainRecord>()).filter { $0.kind == "mailEvidence" && !$0.isDeleted }
            .map { try SyncCodec.decoder().decode(MailEvidence.self, from: $0.content) }
    }

    private static func isDeleted(_ key: String, in context: ModelContext) throws -> Bool {
        try context.fetch(FetchDescriptor<SyncTombstone>()).contains { $0.key == key }
    }

    private static func matchingCards(_ mail: BankMailTransaction, cards: [BankCard]) -> [BankCard] {
        compatibleCards(for: mail, cards: cards).filter { $0.lastFour == mail.lastFour }
    }

    static func compatibleCards(for mail: BankMailTransaction, cards: [BankCard]) -> [BankCard] {
        cards.filter { !$0.isArchived && bankID($0) == mail.bankID && (mail.requiredCardKind == nil || $0.kind == mail.requiredCardKind) }
    }

    private static func missingCardReason(_ mail: BankMailTransaction, cards: [BankCard]) -> String {
        let compatible = compatibleCards(for: mail, cards: cards)
        if compatible.isEmpty {
            return "尚未添加对应的\(mail.requiredCardKind == "借记卡" ? "扣账卡" : "银行卡")（尾号 \(mail.lastFour)）。请先添加；扣账卡消费不会计入信用卡。"
        }
        if compatible.allSatisfy({ $0.lastFour.isEmpty }) {
            return "卡片还未填写尾号。请在个人设置填写邮件中的后4位 \(mail.lastFour)，再重新匹配，无需完整卡号。"
        }
        if compatible.filter({ $0.lastFour == mail.lastFour }).count > 1 {
            return "多张卡片使用尾号 \(mail.lastFour)，请选择这笔消费对应的卡片。"
        }
        return "没有尾号 \(mail.lastFour) 的对应卡片。请核对后4位，再重新匹配；无需完整卡号。"
    }

    static func bankID(_ card: BankCard) -> String? {
        if let prefix = card.catalogID.split(separator: ".").first, ["hsbc", "bochk", "bea"].contains(String(prefix)) { return String(prefix) }
        let bank = MailEvidence.merchant(card.bank)
        if bank.contains("bochk") || bank.contains("中銀") || bank.contains("中银") || bank.contains("bankofchina") { return "bochk" }
        if bank.contains("hsbc") || bank.contains("匯豐") || bank.contains("汇丰") { return "hsbc" }
        if bank.contains("bea") || bank.contains("東亞") || bank.contains("东亚") || bank.contains("bankofeastasia") { return "bea" }
        return nil
    }

    private static func matches(_ mail: BankMailTransaction, request: TransactionRequest, merchantAliases: [String]) -> Bool {
        mail.currency == request.currency && mail.amountCents == request.amountCents
            && HKCalendar.calendar.isDate(mail.date, inSameDayAs: request.date)
            && Set(([mail.merchant] + merchantAliases).map(MailEvidence.merchant)).contains(MailEvidence.merchant(request.merchant))
            && (!mail.hasExactTime || abs(mail.date.timeIntervalSince(request.date)) <= 180)
    }

    private static func sameMerchantAndTime(_ mail: BankMailTransaction, transaction: SpendTransaction) -> Bool {
        MailEvidence.merchant(mail.merchant) == MailEvidence.merchant(transaction.merchant)
            && MailEvidence.withinTimeWindow(mail, transaction: TransactionSyncData(transaction))
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
