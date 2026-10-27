import Testing
import Foundation
import SwiftData
@testable import CardPilot

@Suite @MainActor
struct WalletAmountParsingTests {
    @Test func walletAmountTextSupportsHongKongAndMainlandFormats() throws {
        let hkd = try WalletAmountParser.parse("HK$1,234.56")
        #expect(hkd.currency == "HKD")
        #expect(hkd.amountCents == 123_456)
        let cny = try WalletAmountParser.parse("CN¥ 23,50")
        #expect(cny.currency == "CNY")
        #expect(cny.amountCents == 2_350)
        let yen = try WalletAmountParser.parse("￥89.00", fallbackCurrency: "CNY")
        #expect(yen.currency == "CNY")
        #expect(yen.amountCents == 8_900)
        let euroStyle = try WalletAmountParser.parse("1.234,56 HKD")
        #expect(euroStyle.amountCents == 123_456)
        let usd = try WalletAmountParser.parse("US$1,234.50")
        #expect(usd.currency == "USD")
        #expect(usd.amountCents == 123_450)
    }

    @Test func walletParserDoesNotInventCurrencyWhenAmountHasNone() throws {
        #expect(throws: WalletAmountParser.Failure.self) {
            try WalletAmountParser.parse("$12.50")
        }
        #expect(throws: WalletAmountParser.Failure.self) {
            try WalletAmountParser.parse("12.50")
        }
        #expect(try WalletAmountParser.parse("12.50", fallbackCurrency: "CNY").currency == "CNY")
        #expect(throws: WalletAmountParser.Failure.self) {
            try WalletAmountParser.parse("JPY 100")
        }
        #expect(throws: WalletAmountParser.Failure.self) {
            try WalletAmountParser.parse("HK$0.00")
        }
    }

    @Test(arguments: ["¥12.50", "￥12.50", "HKD ¥12.50", "HKD 12.50 USD"])
    func ambiguousOrConflictingCurrencyIsRejected(text: String) {
        #expect(throws: WalletAmountParser.Failure.self) { try WalletAmountParser.parse(text) }
    }

    @Test(arguments: ["HK$12.3.4", "HK$12,34,567", "HK$1.2345", "HK$12.00 / 20.00",
                      "HK$12abc", "HK$-12.00", "-HK$12.00", "(HK$12.00)", "HK$1e3",
                      "HK$100000000.01", "HK$0.001", "HK$12 34"])
    func malformedAmountsAreNotPartiallyParsedOrRounded(text: String) {
        #expect(throws: WalletAmountParser.Failure.self) { try WalletAmountParser.parse(text) }
    }

    @Test func validGroupingBoundariesAndExplicitCodes() throws {
        #expect(try WalletAmountParser.parse("HK$1,234").amountCents == 123_400)
        #expect(try WalletAmountParser.parse("CNY 1.234").amountCents == 123_400)
        #expect(try WalletAmountParser.parse("HKD 1\u{202f}234,56").amountCents == 123_456)
        #expect(try WalletAmountParser.parse("HK$0.01").amountCents == 1)
        #expect(try WalletAmountParser.parse("HK$100000000.00").amountCents == 10_000_000_000)
        #expect(try WalletAmountParser.parse("HK$12.50", fallbackCurrency: "USD").currency == "HKD")
        #expect(try WalletAmountParser.parse("$12.50", fallbackCurrency: "USD").currency == "USD")
        #expect(throws: WalletAmountParser.Failure.self) {
            try WalletAmountParser.parse("JPY 100", fallbackCurrency: "CNY")
        }
    }

    @Test func walletRetryUsesPossibleDuplicateReviewInsteadOfInventedIdentity() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Bank", name: "Card"); context.insert(card)
        let intent = RecordWalletTransactionIntent()
        intent.merchant = "Cafe"; intent.amountText = "HK$12.50"
        let date = Date.now.addingTimeInterval(-60)
        _ = try TransactionRecorder.record(intent.transactionRequest(cardID: card.syncKey, now: date), in: context)
        let result = try TransactionRecorder.record(intent.transactionRequest(cardID: card.syncKey, now: date.addingTimeInterval(1)), in: context)
        guard case .needsReview = result else { Issue.record("Uncertain retries must ask for review"); return }
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
    }

    @Test func walletIntentProducesCorrectOriginalCurrencyAndPaymentMethod() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "BOCHK", name: "GO")
        context.insert(card)
        let intent = RecordWalletTransactionIntent()
        intent.merchant = "Cafe"
        intent.amountText = "CN¥36.80"
        intent.fallbackCurrency = "自动"
        let request = try intent.transactionRequest(cardID: card.syncKey)
        #expect(request.amountCents == 3_680)
        #expect(request.currency == "CNY")
        #expect(request.paymentMethod == "Apple Pay")
        #expect(request.channel == "physical")
        #expect(!request.hasStableDate)
        #expect(request.exchangeRate.isEmpty)
        _ = try TransactionRecorder.record(request, in: context)
        let saved = try #require(context.fetch(FetchDescriptor<SpendTransaction>()).first)
        #expect(saved.currency == "CNY")
        #expect(saved.amountCents == 3_680)
        #expect(saved.paymentMethod == "Apple Pay")
    }
}
