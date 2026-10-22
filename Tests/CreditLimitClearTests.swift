import Foundation
import SwiftData
import Testing
@testable import CardPilot

@Suite @MainActor
struct CreditLimitClearTests {
    private func day(_ text: String) throws -> Date { try CatalogImporter.date(text) }

    @Test func zeroLimitTombstonesStandaloneGroupAndRepeatedClearIsIdempotent() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Test", name: "Card", baseRateBps: 400)
        card.catalogID = "test.credit.clear"; context.insert(card)
        try DocumentStore.put(CardTerms(cnyFeeBps: nil, baseRewardBasis: nil, baseCapUsesCreditLimit: true, baseCapPeriod: "monthly"),
                              key: "cardTerms:" + card.syncKey, kind: "cardTerms", in: context)
        try Persistence.save(context) {
            try FinanceStore.setPersonalCreditLimit(card: card, cents: 10_000, context: context, now: day("2026-10-01"))
        }
        let group = try #require(try FinanceStore.snapshot(context: context).groups.first)
        try Persistence.save(context) {
            try FinanceStore.setPersonalCreditLimit(card: card, cents: 0, context: context, now: day("2026-10-15"))
        }
        #expect(try FinanceStore.snapshot(context: context).groups.isEmpty)
        #expect(PricingStore.current(card).creditLimitCents == nil)
        #expect(try DocumentStore.record("creditGroup:" + group.id.uuidString, in: context)?.isDeleted == true)
        let unchanged = try SyncStore.records(context)
        try Persistence.save(context) { try FinanceStore.setPersonalCreditLimit(card: card, cents: 0, context: context) }
        #expect(try SyncStore.records(context) == unchanged)
    }

    @Test func zeroDetachesOnlyCurrentCardAndPreservesOtherMembersBillsAndPayments() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let a = BankCard(bank: "B", name: "A"), b = BankCard(bank: "B", name: "B")
        a.catalogID = "clear.shared.a"; b.catalogID = "clear.shared.b"; context.insert(a); context.insert(b)
        let group = CreditGroup(name: "Shared", limitCents: 2_000_000, cardKeys: [a.syncKey, b.syncKey])
        try FinanceStore.save(group, context: context, now: day("2026-10-01"))
        let statement = BillingStatement(cardKey: a.syncKey, amountCents: 20_000, currency: "HKD", exchangeRate: "1",
                                         periodEnd: try day("2026-10-05"), dueDate: try day("2026-10-25"))
        let repayment = Repayment(statementID: statement.id, amountCents: 5000, date: try day("2026-10-10"))
        try FinanceStore.save(statement, context: context); try FinanceStore.save(repayment, context: context)
        try context.save()
        try Persistence.save(context) {
            try FinanceStore.setPersonalCreditLimit(card: a, cents: 0, context: context, now: day("2026-10-15"))
        }
        let snapshot = try FinanceStore.snapshot(context: context), remaining = try #require(snapshot.groups.first)
        #expect(remaining.id == group.id); #expect(remaining.cardKeys == [b.syncKey]); #expect(remaining.limitCents == group.limitCents)
        #expect(snapshot.statements.count == 1); #expect(snapshot.statements.first?.id == statement.id)
        #expect(snapshot.payments.count == 1); #expect(snapshot.payments.first?.id == repayment.id)
        #expect(PricingStore.current(a).creditLimitCents == nil); #expect(PricingStore.current(b).creditLimitCents == group.limitCents)
    }

    @Test func clearedGroupSyncsAndOlderSnapshotsCannotRestoreIt() throws {
        let a = try Persistence.makeContainer(inMemory: true), b = try Persistence.makeContainer(inMemory: true)
        let card = BankCard(bank: "B", name: "Card"); card.catalogID = "credit.clear.sync"; a.mainContext.insert(card)
        try Persistence.save(a.mainContext) {
            try FinanceStore.setPersonalCreditLimit(card: card, cents: 20_000, context: a.mainContext, now: day("2026-10-01"))
        }
        let older = try SyncStore.records(a.mainContext)
        #expect(try SyncStore.apply(older, context: b.mainContext))
        try Persistence.save(a.mainContext) {
            try FinanceStore.setPersonalCreditLimit(card: card, cents: 0, context: a.mainContext, now: day("2026-10-01"))
        }
        let cleared = try SyncStore.records(a.mainContext)
        #expect(try SyncStore.apply(cleared, context: b.mainContext))
        #expect(try FinanceStore.snapshot(context: b.mainContext).groups.isEmpty)
        #expect(try !SyncStore.apply(cleared, context: b.mainContext))
        _ = try SyncStore.apply(older, context: b.mainContext)
        #expect(try FinanceStore.snapshot(context: b.mainContext).groups.isEmpty)
        _ = try SyncStore.apply(SyncStore.records(b.mainContext), context: a.mainContext)
        #expect(try FinanceStore.snapshot(context: a.mainContext).groups.isEmpty)
    }

    @Test func positiveLimitContinuesUpdatingExistingSharedGroup() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let a = BankCard(bank: "B", name: "A"), b = BankCard(bank: "B", name: "B")
        context.insert(a); context.insert(b)
        let group = CreditGroup(name: "Shared", limitCents: 100_000, cardKeys: [a.syncKey, b.syncKey])
        try FinanceStore.save(group, context: context, now: day("2026-10-01")); try context.save()
        try Persistence.save(context) {
            try FinanceStore.setPersonalCreditLimit(card: a, cents: 200_000, context: context, now: day("2026-10-15"))
        }
        let saved = try #require(try FinanceStore.snapshot(context: context).groups.first)
        #expect(saved.id == group.id); #expect(saved.cardKeys == group.cardKeys); #expect(saved.limitCents == 200_000)
        #expect(PricingStore.current(a).creditLimitCents == 200_000); #expect(PricingStore.current(b).creditLimitCents == 200_000)
    }
}
