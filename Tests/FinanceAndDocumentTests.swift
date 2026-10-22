import Testing
import Foundation
import SwiftData
@testable import CardPilot

@Suite @MainActor
struct FinanceAndDocumentTests {
    private func day(_ value: String) throws -> Date { try CatalogImporter.date(value) }

    @Test func latestStatementPerCurrencyAvoidsDoubleCountingAndPaymentsRestoreSharedCredit() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let a = BankCard(bank: "B", name: "A"), b = BankCard(bank: "B", name: "B")
        context.insert(a); context.insert(b)
        let group = CreditGroup(name: "Shared", limitCents: 1_000_000, cardKeys: [a.syncKey, b.syncKey])
        try FinanceStore.save(group, context: context)
        let old = BillingStatement(cardKey: a.syncKey, amountCents: 200_000, currency: "HKD", exchangeRate: "1", periodEnd: try day("2026-09-10"), dueDate: try day("2026-09-30"))
        let latest = BillingStatement(cardKey: a.syncKey, amountCents: 300_000, currency: "HKD", exchangeRate: "1", periodEnd: try day("2026-10-10"), dueDate: try day("2026-10-30"))
        let rmb = BillingStatement(cardKey: a.syncKey, amountCents: 100_000, currency: "CNY", exchangeRate: "1.1", periodEnd: try day("2026-10-10"), dueDate: try day("2026-10-30"))
        let other = BillingStatement(cardKey: b.syncKey, amountCents: 50_000, currency: "HKD", exchangeRate: "1", periodEnd: try day("2026-10-10"), dueDate: try day("2026-10-30"))
        for statement in [old, latest, rmb, other] { try FinanceStore.save(statement, context: context) }
        try FinanceStore.save(Repayment(statementID: latest.id, amountCents: 50_000, date: try day("2026-10-15")), context: context)
        let unbilled = SpendTransaction(merchant: "Shop", amountCents: 10_000, date: try day("2026-10-12"), card: a)
        context.insert(unbilled)
        let snapshot = try FinanceStore.snapshot(context: context)
        #expect(snapshot.available(group, transactions: [unbilled], now: try day("2026-10-21")) == 580_000)
        #expect(snapshot.unpaid(latest) == 250_000)
        do { try FinanceStore.save(Repayment(statementID: latest.id, amountCents: 250_001, date: try day("2026-10-20")), context: context); Issue.record("Overpayment accepted") } catch { }
    }

    @Test func domainDocumentsSyncAndRepeatedApplicationDoesNotChangeThem() throws {
        let a = try Persistence.makeContainer(inMemory: true), b = try Persistence.makeContainer(inMemory: true)
        let card = BankCard(bank: "B", name: "Card"); card.catalogID = "stable.card"; a.mainContext.insert(card)
        let rule = RewardRule(name: "Offer", card: card, rateBps: 400); rule.externalID = "offer"; a.mainContext.insert(rule)
        try RulePolicyStore.imported(RuleSyncData(rule), extras: RuleExtras(), into: rule, isNew: true, context: a.mainContext)
        try FinanceStore.save(CreditGroup(name: "Shared", limitCents: 1_000_000, cardKeys: [card.syncKey]), context: a.mainContext)
        try DocumentStore.put(WelcomeReceipt(received: true, receivedOn: .now), key: "welcome:" + rule.syncKey, kind: "welcome", in: a.mainContext)
        try a.mainContext.save()
        let records = try SyncStore.records(a.mainContext)
        #expect(try SyncStore.apply(records, context: b.mainContext))
        #expect(try FinanceStore.snapshot(context: b.mainContext).groups.count == 1)
        #expect(try DocumentStore.load(WelcomeReceipt.self, key: "welcome:" + rule.syncKey, in: b.mainContext)?.received == true)
        #expect(try !SyncStore.apply(records, context: b.mainContext))
    }

    @Test func badFinancialDocumentIsRejectedBeforeChangingLocalData() throws {
        let invalid = CreditGroup(name: "Invalid", limitCents: -1, cardKeys: [])
        let value = DocumentSyncData(key: "creditGroup:invalid", kind: "creditGroup", content: try SyncCodec.encoder().encode(invalid), isDeleted: false)
        let record = SyncRecord(key: "document:" + value.key, kind: "document", revision: .now, deleted: false, payload: try SyncCodec.encoder().encode(value))
        do { try SyncCodec.validate(record); Issue.record("Invalid group accepted") } catch { }
    }

    @Test func freshDeviceTemplateCannotEraseManualPolicyAndRepeatedSyncConverges() throws {
        let a = try Persistence.makeContainer(inMemory: true), b = try Persistence.makeContainer(inMemory: true)
        func seed(_ context: ModelContext) throws -> (BankCard, RewardRule) {
            let card = BankCard(bank: "B", name: "Card"); card.catalogID = "same.catalog"; context.insert(card)
            let rule = RewardRule(name: "Offer", card: card, rateBps: 400, startsOn: try day("2026-10-01"), endsOn: try day("2026-12-31"))
            rule.externalID = "offer"; context.insert(rule)
            try RulePolicyStore.imported(RuleSyncData(rule), extras: RuleExtras(), into: rule, isNew: true, context: context)
            return (card, rule)
        }
        let (card, rule) = try seed(a.mainContext)
        rule.isEnabled = false
        let draft = RuleDraft(rule: rule); draft.rate = 7
        #expect(draft.save(in: a.mainContext, cards: [card]))
        let (_, fresh) = try seed(b.mainContext)
        fresh.modifiedAt = .now.addingTimeInterval(60)
        for document in try b.mainContext.fetch(FetchDescriptor<DomainRecord>()) { document.modifiedAt = fresh.modifiedAt }
        let incoming = try SyncStore.records(b.mainContext)
        _ = try SyncStore.apply(incoming, context: a.mainContext)
        #expect(rule.rateBps == 700); #expect(!rule.isEnabled)
        #expect(try !SyncStore.apply(incoming, context: a.mainContext))
        let normalized = try SyncStore.records(a.mainContext)
        #expect(SyncMerger.merge(normalized + incoming) == SyncMerger.merge(incoming + normalized))
    }
}
