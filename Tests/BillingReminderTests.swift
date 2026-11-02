import Foundation
import SwiftData
import Testing
@testable import CardPilot

@Suite @MainActor
struct BillingReminderTests {
    private func day(_ value: String) throws -> Date { try CatalogImporter.date(value) }

    private func snapshot(for card: BankCard, advance: Int = 3) -> FinanceSnapshot {
        var result = FinanceSnapshot()
        result.billingPreferences[card.syncKey] = CardBillingPreferences(cardKey: card.syncKey, statementReminder: true, paymentReminder: true, advanceDays: advance)
        return result
    }

    @Test(arguments: [("2027-02-01", 31, "2027-02-28"), ("2028-02-01", 29, "2028-02-29"), ("2026-04-01", 31, "2026-04-30"), ("2026-12-01", 30, "2026-12-30")])
    func monthlyDatesClampToActualMonthEnd(_ input: (String, Int, String)) throws {
        #expect(BillingDates.date(day: input.1, inMonth: try day(input.0)) == (try day(input.2)))
    }

    @Test func unknownDaysAndOptOutProduceNoInferredDates() throws {
        let card = BankCard(bank: "Test", name: "Credit", statementDay: 0, paymentDay: 0)
        let now = try day("2026-11-01")
        #expect(BillingReminders.plan(cards: [card], finance: snapshot(for: card), now: now).isEmpty)
        card.statementDay = 5; card.paymentDay = 25
        #expect(BillingReminders.plan(cards: [card], finance: FinanceSnapshot(), now: now).isEmpty)
        var finance = snapshot(for: card)
        finance.billingPreferences[card.syncKey]?.statementReminder = false
        finance.billingPreferences[card.syncKey]?.paymentReminder = false
        #expect(BillingReminders.plan(cards: [card], finance: finance, now: now).isEmpty)
    }

    @Test func actualStatementsOverrideMonthlyDateAndPaidBillsCancelBothAlerts() throws {
        let card = BankCard(bank: "Test", name: "Credit", statementDay: 3, paymentDay: 25)
        var finance = snapshot(for: card)
        let bill = BillingStatement(cardKey: card.syncKey, amountCents: 10000, currency: "CNY", exchangeRate: "", periodEnd: try day("2026-11-03"), dueDate: try day("2026-11-18"))
        finance.statements = [bill]
        let now = try day("2026-11-01")
        let reminders = BillingReminders.plan(cards: [card], finance: finance, now: now)
        let novemberPayments = reminders.filter { $0.id.contains(".payment") && HKCalendar.isThisMonth($0.date, now: now) }
        #expect(novemberPayments.count == 2)
        #expect(novemberPayments.map { HKCalendar.calendar.component(.day, from: $0.date) } == [15, 18])
        #expect(novemberPayments.allSatisfy { HKCalendar.calendar.component(.hour, from: $0.date) == 10 })
        finance.payments = [Repayment(statementID: bill.id, amountCents: 10000, date: now)]
        let paid = BillingReminders.plan(cards: [card], finance: finance, now: now)
        #expect(!paid.contains { $0.id.contains(".payment") && HKCalendar.isThisMonth($0.date, now: now) })
        #expect(paid.contains { $0.id.contains(".statement") && HKCalendar.isThisMonth($0.date, now: now) })
    }

    @Test func partialPaymentsRetainAlertAndSameDateCurrenciesShareOneReminder() throws {
        let card = BankCard(bank: "Test", name: "Credit", statementDay: 0, paymentDay: 0)
        var finance = snapshot(for: card, advance: 0)
        let now = try day("2026-11-01")
        let hkd = BillingStatement(cardKey: card.syncKey, amountCents: 10000, currency: "HKD", exchangeRate: "1", periodEnd: now, dueDate: try day("2026-11-18"))
        let cny = BillingStatement(cardKey: card.syncKey, amountCents: 20000, currency: "CNY", exchangeRate: "", periodEnd: now, dueDate: hkd.dueDate)
        finance.statements = [hkd, cny]
        finance.payments = [Repayment(statementID: hkd.id, amountCents: 10000, date: now), Repayment(statementID: cny.id, amountCents: 5000, date: now)]
        let reminders = BillingReminders.plan(cards: [card], finance: finance, now: now)
        #expect(reminders.count == 1)
        #expect(HKCalendar.start(try #require(reminders.first).date) == hkd.dueDate)
        #expect(!reminders[0].body.contains("150.00"))
    }

    @Test func noPastNotificationsOrRemindersForArchivedAndDebitCards() throws {
        let card = BankCard(bank: "Test", name: "Credit", statementDay: 31, paymentDay: 1)
        let now = try day("2027-02-28").addingTimeInterval(11 * 3600)
        let finance = snapshot(for: card)
        let reminders = BillingReminders.plan(cards: [card], finance: finance, now: now)
        #expect(!reminders.isEmpty)
        #expect(reminders.allSatisfy { $0.date > now })
        #expect(Set(reminders.map(\.id)).count == reminders.count)
        card.isArchived = true
        #expect(BillingReminders.plan(cards: [card], finance: finance, now: now).isEmpty)
        card.isArchived = false; card.kind = "借记卡"
        #expect(BillingReminders.plan(cards: [card], finance: finance, now: now).isEmpty)
    }

    @Test func dueDateSuggestionsCrossYearsAndStatusTreatsDueDayAsToday() throws {
        #expect(BillingDates.dueDate(after: try day("2026-12-20"), day: 5) == (try day("2027-01-05")))
        #expect(BillingDates.dueDate(after: try day("2026-12-20"), day: 0) == nil)
        let now = try day("2026-11-18").addingTimeInterval(23 * 3600)
        #expect(BillingDates.status(due: try day("2026-11-18"), paid: false, now: now) == "今天到期")
        #expect(BillingDates.status(due: try day("2026-11-17"), paid: false, now: now) == "已过期 1 天")
        #expect(BillingDates.status(due: try day("2026-11-17"), paid: true, now: now) == "已记录还清")
    }

    @Test func originalCurrencyBillsRepaymentsAndPreferencesSyncWithoutRate() throws {
        let a = try Persistence.makeContainer(inMemory: true), b = try Persistence.makeContainer(inMemory: true)
        let card = BankCard(bank: "Test", name: "Credit", statementDay: 3, paymentDay: 25)
        a.mainContext.insert(card)
        let preferences = CardBillingPreferences(cardKey: card.syncKey, paymentReminder: true, advanceDays: 7, hour: 9, minute: 30)
        let bill = BillingStatement(cardKey: card.syncKey, amountCents: 10000, currency: "CNY", exchangeRate: "", periodEnd: try day("2026-09-03"), dueDate: try day("2026-09-25"))
        try FinanceStore.save(preferences, context: a.mainContext)
        try FinanceStore.save(bill, context: a.mainContext)
        let payment = Repayment(statementID: bill.id, amountCents: 4000, date: try day("2026-09-20"))
        try FinanceStore.save(payment, context: a.mainContext)
        try a.mainContext.save()
        #expect(try SyncStore.apply(SyncStore.records(a.mainContext), context: b.mainContext))
        let synced = try FinanceStore.snapshot(context: b.mainContext)
        #expect(synced.billingPreferences[card.syncKey] == preferences)
        #expect(synced.statements == [bill])
        #expect(synced.unpaid(bill) == 6000)
        #expect(try !SyncStore.apply(SyncStore.records(a.mainContext), context: b.mainContext))
        try DocumentStore.remove("repayment:" + payment.id.uuidString, in: b.mainContext)
        #expect(try FinanceStore.snapshot(context: b.mainContext).unpaid(bill) == 10000)
    }

    @Test func removingStatementRemovesOnlyItsRepaymentsAndSyncsDeletion() throws {
        let a = try Persistence.makeContainer(inMemory: true), b = try Persistence.makeContainer(inMemory: true)
        let card = BankCard(bank: "Test", name: "Credit"); a.mainContext.insert(card)
        let bill = BillingStatement(cardKey: card.syncKey, amountCents: 10000, currency: "HKD", exchangeRate: "1", periodEnd: try day("2026-09-03"), dueDate: try day("2026-09-25"))
        let other = BillingStatement(cardKey: card.syncKey, amountCents: 20000, currency: "HKD", exchangeRate: "1", periodEnd: try day("2026-10-03"), dueDate: try day("2026-10-25"))
        try FinanceStore.save(bill, context: a.mainContext)
        try FinanceStore.save(other, context: a.mainContext)
        try FinanceStore.save(Repayment(statementID: bill.id, amountCents: 1000, date: try day("2026-09-20")), context: a.mainContext)
        try Persistence.save(a.mainContext) { }
        _ = try SyncStore.apply(SyncStore.records(a.mainContext), context: b.mainContext)
        try Persistence.save(a.mainContext) { try FinanceStore.removeStatement(bill, context: a.mainContext) }
        _ = try SyncStore.apply(SyncStore.records(a.mainContext), context: b.mainContext)
        let synced = try FinanceStore.snapshot(context: b.mainContext)
        #expect(synced.statements.map(\.id) == [other.id])
        #expect(synced.payments.isEmpty)
    }

    @Test func invalidPreferencesAndBillEditsCannotCorruptRepayments() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Test", name: "Credit")
        context.insert(card)
        var preferences = CardBillingPreferences(cardKey: card.syncKey)
        preferences.hour = 24
        #expect(throws: (any Error).self) { try FinanceStore.save(preferences, context: context) }
        let invalid = DocumentSyncData(key: preferences.key, kind: "billingPreferences", content: try SyncCodec.encoder().encode(preferences), isDeleted: false)
        #expect(throws: (any Error).self) { try DocumentValidator.validate(invalid) }
        var bill = BillingStatement(cardKey: card.syncKey, amountCents: 10000, currency: "HKD", exchangeRate: "1", periodEnd: try day("2026-09-03"), dueDate: try day("2026-09-25"))
        try FinanceStore.save(bill, context: context)
        try FinanceStore.save(Repayment(statementID: bill.id, amountCents: 6000, date: try day("2026-09-20")), context: context)
        bill.amountCents = 5999
        #expect(throws: (any Error).self) { try FinanceStore.save(bill, context: context) }
        bill.amountCents = 10000; bill.currency = "CNY"; bill.exchangeRate = ""
        #expect(throws: (any Error).self) { try FinanceStore.save(bill, context: context) }
        #expect(try FinanceStore.snapshot(context: context).statements.first?.currency == "HKD")
    }

    @Test func ephemeralRunsCannotEnableNotificationsOrChangeDeviceOptIn() async throws {
        let context = try Persistence.makeContainer(inMemory: true).mainContext
        let key = "tests.billing-reminders." + UUID().uuidString
        defer { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.set(true, forKey: key)
        #expect(RuntimeMode.isEphemeral)
        #expect(try await !LocalReminderService.enable(key, context: context))
        try await LocalReminderService.disable(key, context: context)
        #expect(UserDefaults.standard.bool(forKey: key))
    }
}
