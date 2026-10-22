import Foundation
import SwiftData

@MainActor enum FinanceStore {
    static func snapshot(_ documents: [DomainRecord]) throws -> FinanceSnapshot {
        var snapshot = FinanceSnapshot()
        for record in documents where !record.isDeleted {
            switch record.kind {
            case "creditGroup": snapshot.groups.append(try SyncCodec.decoder().decode(CreditGroup.self, from: record.content))
            case "statement": snapshot.statements.append(try SyncCodec.decoder().decode(BillingStatement.self, from: record.content))
            case "repayment": snapshot.payments.append(try SyncCodec.decoder().decode(Repayment.self, from: record.content))
            default: break
            }
        }
        return snapshot
    }
    static func snapshot(context: ModelContext) throws -> FinanceSnapshot { try snapshot(context.fetch(FetchDescriptor<DomainRecord>())) }

    /// Personal settings may clear a limit without deleting statements or another card's shared limit.
    /// The caller owns the surrounding Persistence.save transaction.
    static func setPersonalCreditLimit(card: BankCard, cents: Int64, context: ModelContext, now: Date = .now) throws {
        guard (0...10_000_000_000).contains(cents) else { throw PilotError.invalid("信用额度须在0至100,000,000港币之间。") }
        let groups = try snapshot(context: context).groups.filter { $0.cardKeys.contains(card.syncKey) }
        if cents > 0 {
            guard groups.count <= 1 else { throw PilotError.invalid("这张卡存在重复额度组，请先在额度管理中整理。") }
            var group = groups.first ?? CreditGroup(name: card.displayName, limitCents: cents, cardKeys: [card.syncKey])
            group.limitCents = cents
            try save(group, context: context, now: now)
            return
        }

        guard !groups.isEmpty else { return }
        for var group in groups {
            group.cardKeys.removeAll { $0 == card.syncKey }
            let key = "creditGroup:" + group.id.uuidString
            let record = try DocumentStore.record(key, in: context)
            // Sync timestamps are encoded to milliseconds. A rapid clear must win
            // over the saved group even when both operations share that millisecond.
            let revision = max(now, record?.modifiedAt.addingTimeInterval(0.001) ?? now)
            if group.cardKeys.isEmpty {
                if let record {
                    record.isDeleted = true
                    record.modifiedAt = revision
                }
            } else {
                try DocumentStore.put(group, key: key, kind: "creditGroup", in: context, now: revision)
            }
        }
    }

    static func save(_ group: CreditGroup, context: ModelContext, now: Date = .now) throws {
        guard !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...10_000_000_000).contains(group.limitCents), !group.cardKeys.isEmpty else { throw PilotError.invalid("请填写额度组名称、信用额度并选择银行卡。") }
        let others = try snapshot(context: context).groups
        guard !others.contains(where: { $0.id != group.id && !Set($0.cardKeys).isDisjoint(with: group.cardKeys) }) else {
            throw PilotError.invalid("所选银行卡已属于另一个额度组，请先从原组移除。")
        }
        try DocumentStore.put(group, key: "creditGroup:" + group.id.uuidString, kind: "creditGroup", in: context, now: now)
    }
    static func save(_ statement: BillingStatement, context: ModelContext) throws {
        let existing = try snapshot(context: context).statements
        guard !existing.contains(where: { $0.id != statement.id && $0.cardKey == statement.cardKey && $0.currency == statement.currency && HKCalendar.start($0.periodEnd) == HKCalendar.start(statement.periodEnd) }) else {
            throw PilotError.invalid("这张卡同一币种及截止日的账单已存在，请编辑原账单。")
        }
        let rate = Decimal(string: statement.exchangeRate) ?? 0
        guard (0...10_000_000_000).contains(statement.amountCents), Currency(rawValue: statement.currency) != nil,
              rate > 0, rate <= 1000, statement.dueDate >= statement.periodEnd else { throw PilotError.invalid("请检查账单金额、汇率及还款日期。") }
        try DocumentStore.put(statement, key: "statement:" + statement.id.uuidString, kind: "statement", in: context)
    }
    static func save(_ payment: Repayment, context: ModelContext) throws {
        let snapshot = try snapshot(context: context)
        guard let statement = snapshot.statements.first(where: { $0.id == payment.statementID }), payment.amountCents > 0,
              payment.amountCents <= snapshot.unpaid(statement), payment.date <= .now else { throw PilotError.invalid("还款金额须大于零且不超过未还账单，日期不能晚于今天。") }
        try DocumentStore.put(payment, key: "repayment:" + payment.id.uuidString, kind: "repayment", in: context)
    }
}
