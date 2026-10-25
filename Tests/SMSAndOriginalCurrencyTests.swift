import Testing
import Foundation
import SwiftData
@testable import CardPilot

@Suite @MainActor
struct SMSAndOriginalCurrencyTests {
    private var date: Date { get throws { try CatalogImporter.date("2026-10-22") } }
    private let boc = "【中銀香港】您的中銀信用卡尾號0007於16/10在EXAMPLE SHOP透過手機支付交易CNY794.00，如懷疑電(852)28538828"
    private let bea = "東亞銀行:信用卡尾數0008於2026/10/21在EXAMPLE CAMPUS 0*作無卡支付HKD600.00。如懷疑電36086628"

    @Test func parsesMultipleNoticesWithoutInventingPaymentRegionOrTime() throws {
        let parsed = try BankSMSParser.parse(boc + "\n" + bea + "\n" + bea, referenceDate: date)
        #expect(parsed.count == 3)
        #expect(parsed[0].amountCents == 79400); #expect(parsed[0].currency == "CNY")
        #expect(parsed[1].merchant == "EXAMPLE CAMPUS 0")
        #expect(parsed.allSatisfy { $0.source == "sms" && !$0.hasExactTime && $0.region == nil && $0.paymentMethod == "待确认" })
        #expect(Set(parsed.map(\.messageID)).count == 3)
        #expect(try BankSMSParser.parse("【中銀香港】中銀信用卡尾號0007已確認卡。開卡驗證碼123456", referenceDate: date).isEmpty)
        #expect(try BankSMSParser.parse("東亞銀行:信用卡尾數0008於2026/10/21退款HKD600.00", referenceDate: date).isEmpty)
        #expect(throws: (any Error).self) { try BankSMSParser.parse(boc.replacingOccurrences(of: "16/10", with: "31/02"), referenceDate: date) }
        let rollover = try BankSMSParser.parse(boc.replacingOccurrences(of: "16/10", with: "31/12"), referenceDate: CatalogImporter.date("2026-01-02"))
        #expect(HKCalendar.calendar.component(.year, from: try #require(rollover.first).date) == 2025)
    }

    @Test func repeatedPastesAndEmailWalletConflictsRequireReviewAndOriginalCurrencySyncs() throws {
        let a = try Persistence.makeContainer(inMemory: true), b = try Persistence.makeContainer(inMemory: true)
        let context = a.mainContext
        let card = BankCard(bank: "BOCHK", name: "Example dual currency", lastFour: "0007")
        context.insert(card); try context.save()
        let parsed = try BankSMSParser.parse(boc, referenceDate: date)
        #expect(try MailImportService.importTransactions(parsed, in: context).saved == 1)
        #expect(try MailImportService.importTransactions(parsed, in: context).duplicate == 1)
        #expect(try MailImportService.importTransactions(BankSMSParser.parse(boc, referenceDate: date), in: context).pending == 1)
        let saved = try #require(try context.fetch(FetchDescriptor<SpendTransaction>()).first)
        #expect(saved.source == "sms"); #expect(saved.exchangeRate.isEmpty); #expect(saved.amountCents == 79400)
        var manual = TransactionRequest(cardID: card.syncKey, merchant: "EXAMPLE SHOP", amountCents: 79400,
                                        date: try date.addingTimeInterval(-6 * 86400 + 3600))
        manual.source = "manual"; manual.currency = "CNY"; manual.exchangeRate = ""
        #expect(try TransactionRecorder.assess(manual, in: context)?.isExact == false)
        manual.source = "csv"; manual.externalID = "fictional-row"
        #expect(try TransactionRecorder.assess(manual, in: context)?.isExact == false)
        var email = try #require(parsed.first); email.messageID = "fictional-gmail"; email.evidenceSource = nil
        #expect(try MailImportService.importTransactions([email], in: context).pending == 1)
        let review = try #require(try MailImportService.reviewItems(in: context).first { $0.mail.messageID == email.messageID })
        _ = try MailImportService.resolveReview(key: review.key, transactionKey: saved.syncKey, in: context)
        #expect(saved.source == "email"); #expect(saved.exchangeRate.isEmpty)
        _ = try SyncStore.apply(SyncStore.records(context), context: b.mainContext)
        let peer = try #require(try b.mainContext.fetch(FetchDescriptor<SpendTransaction>()).first)
        #expect(peer.amountCents == 79400); #expect(peer.currency == "CNY"); #expect(!peer.hasHKDValuation)
        #expect(try b.mainContext.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        var wallet = TransactionRequest(cardID: card.syncKey, merchant: "EXAMPLE SHOP", amountCents: 79400, date: try date.addingTimeInterval(-6 * 86400))
        wallet.currency = "CNY"; wallet.exchangeRate = "1.1"; wallet.externalID = "fixture-wallet"
        if case .duplicate = try TransactionRecorder.record(wallet, in: context) {} else { Issue.record("Wallet retry should use the existing confirmed receipt") }
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
    }

    @Test func currencySubtotalsExcludeUnknownFXButKeepOriginalAmounts() throws {
        let card = BankCard(bank: "Example", name: "Dual currency")
        let unknown = SpendTransaction(merchant: "Original only", amountCents: 10000, currency: "CNY", exchangeRate: "", date: try date, card: card)
        let known = SpendTransaction(merchant: "Known rate", amountCents: 20000, currency: "CNY", exchangeRate: "1.1", date: try date, card: card)
        let local = SpendTransaction(merchant: "Local", amountCents: 5000, date: try date, card: card)
        let snapshot = DashboardSnapshot(cards: [card], transactions: [unknown, known, local], now: try date)
        #expect(snapshot.monthSpend == 27000); #expect(snapshot.monthCount == 3)
        #expect(snapshot.unvaluedCount == 1); #expect(snapshot.categories.reduce(0) { $0 + $1.cents } == 27000)
        #expect(unknown.hkdCents == 0); #expect(unknown.amountCents == 10000)
        #expect(known.hkdCents == 22000)
        #expect(snapshot.originalTotals == Money.text(30000, currency: "CNY"))
    }

    @Test func shortcutsAndCSVAllowForeignOriginalCurrencyWithoutAssumedRate() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Dual currency"); context.insert(card)
        let intent = RecordTransactionIntent(); intent.merchant = "Wallet shop"; intent.amount = 123.45
        intent.currency = "CNY"; intent.transactionDate = try date; intent.externalID = "fictional-wallet"
        let request = try intent.transactionRequest(cardID: card.syncKey)
        #expect(request.exchangeRate.isEmpty); #expect(request.region.isEmpty)
        #expect(request.paymentMethod == PaymentMethod.unknown.rawValue); #expect(request.channel == "unknown")
        _ = try TransactionRecorder.record(request, in: context)
        let csv = Data("merchant,amount,date,currency\nCSV shop,67.89,2026-10-20,CNY\n".utf8)
        let row = try #require(CanonicalCSVAdapter().parse(csv, cardID: card.syncKey).first)
        #expect(row.exchangeRate.isEmpty); #expect(row.paymentMethod == PaymentMethod.unknown.rawValue)
        #expect(row.region.isEmpty); #expect(row.channel == "unknown")
        _ = try TransactionRecorder.record(row, in: context); try context.save()
        let saved = try context.fetch(FetchDescriptor<SpendTransaction>())
        #expect(saved.count == 2); #expect(saved.allSatisfy { $0.currency == "CNY" && $0.exchangeRate.isEmpty })
        #expect(saved.reduce(0) { $0 + $1.amountCents } == 19134)
        #expect(try MailImportService.reviewItems(in: context).isEmpty)
    }

    @Test func blueLionIsIndependentDebitProductWithOfflineArtwork() throws {
        let product = try #require(BankLibrary.load().products.first { $0.id == "hsbc.mastercard.debit" })
        let container = try Persistence.makeContainer(inMemory: true)
        let card = try LibraryOnboarding.add(product: product, in: container.mainContext)
        #expect(card.kind == "借记卡"); #expect(card.network == "Mastercard")
        #expect(card.baseRateBps == 40); #expect(card.foreignFeeBps == 0)
        #expect(card.imageData == nil); #expect(card.artworkSource == .catalog)
    }
}
