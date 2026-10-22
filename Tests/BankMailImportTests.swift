import Testing
import Foundation
import SwiftData
@testable import CardPilot

/// All fixtures are invented; no mailbox contents or real card identifiers belong here.
@Suite @MainActor
struct BankMailImportTests {
    @Test func unknownPaymentRegionChannelAndRateDoNotRequireReviewAndLegacyRateReviewCanRetry() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = try card(context)
        var notification = mail(currency: "CNY")
        notification.paymentMethod = nil; notification.region = nil; notification.channel = nil
        // A pending item created by an older client must be able to enter the lightweight ledger.
        let review = MailReview(key: MailReview.key(for: notification), mail: notification,
                                reason: "Legacy exchange rate review", candidateKeys: [], cardKey: card.syncKey)
        try DocumentStore.put(review, key: review.key, kind: "mailReview", in: context)
        try context.save()
        let result = try MailImportService.retryPending(in: context)
        #expect(result.saved == 1); #expect(result.pending == 0)
        let saved = try #require(context.fetch(FetchDescriptor<SpendTransaction>()).first)
        #expect(saved.amountCents == notification.amountCents); #expect(saved.currency == "CNY")
        #expect(saved.exchangeRate.isEmpty); #expect(saved.region.isEmpty)
        #expect(saved.paymentMethod == PaymentMethod.unknown.rawValue); #expect(saved.channel == "unknown")
        #expect(try MailImportService.reviewItems(in: context).isEmpty)
        let peer = try Persistence.makeContainer(inMemory: true)
        _ = try SyncStore.apply(SyncStore.records(context), context: peer.mainContext)
        let synced = try #require(peer.mainContext.fetch(FetchDescriptor<SpendTransaction>()).first)
        #expect(synced.amountCents == notification.amountCents); #expect(synced.exchangeRate.isEmpty)
        #expect(synced.region.isEmpty); #expect(synced.paymentMethod == PaymentMethod.unknown.rawValue)
    }

    @Test func missingPersonalTailCanBeRetriedWithoutDownloadingTheMailAgain() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = try card(context, tail: "")
        #expect(try MailImportService.importTransactions([mail()], in: context).pending == 1)
        let pending = try #require(try MailImportService.reviewItems(in: context).first)
        #expect(pending.reason.contains("未填写尾号"))
        card.lastFour = "0007"; try context.save()
        #expect(try MailImportService.retryPending(in: context).saved == 1)
        #expect(try MailImportService.reviewItems(in: context).isEmpty)
        #expect(try MailImportService.retryPending(in: context).saved == 0)
        #expect(try MailImportService.importTransactions([mail()], in: context).duplicate == 1)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
    }

    @Test func retrySavesOriginalCurrencyAfterAddingCardAndNeverRestoresIgnoredMail() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let foreign = mail(currency: "CNY"), ignored = mail("fictional-ignored")
        _ = try MailImportService.importTransactions([foreign, ignored], in: context)
        try MailImportService.ignoreReview(key: MailReview.key(for: ignored), in: context)
        let card = try card(context)
        let result = try MailImportService.retryPending(in: context)
        #expect(result.saved == 1); #expect(result.pending == 0)
        let transaction = try #require(try context.fetch(FetchDescriptor<SpendTransaction>()).first)
        #expect(transaction.card?.id == card.id); #expect(transaction.currency == "CNY")
        #expect(transaction.exchangeRate.isEmpty); #expect(!transaction.hasHKDValuation)
        #expect(try MailImportService.importTransactions([ignored], in: context).duplicate == 1)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
    }

    @Test func hsbcDebitMailDoesNotMatchOrManuallyOverwriteCreditCardsWithTheSameTail() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let credit = try card(context, bank: "hsbc")
        var debitMail = mail(); debitMail.bankID = "hsbc"; debitMail.cardKind = "借记卡"
        #expect(try MailImportService.importTransactions([debitMail], in: context).pending == 1)
        #expect(throws: (any Error).self) {
            try MailImportService.resolveReview(key: MailReview.key(for: debitMail), cardKey: credit.syncKey, saveAsAnother: true, in: context)
        }
        let debit = BankCard(bank: "HSBC", name: "Fictional debit", kind: "借记卡", lastFour: "0007")
        context.insert(debit); try context.save()
        #expect(try MailImportService.retryPending(in: context).saved == 1)
        let saved = try #require(try context.fetch(FetchDescriptor<SpendTransaction>()).first)
        #expect(saved.card?.id == debit.id); #expect(credit.transactions.isEmpty)
        debitMail.cardKind = nil
        #expect(MailImportService.compatibleCards(for: debitMail, cards: [credit, debit]).map(\.id) == [debit.id])
    }

    @Test func requestedProductSetupAddsOnlyRequestedCardsPreservesPreferencesAndRetries() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let library = try BankLibrary.load()
        let chill = try LibraryOnboarding.add(product: #require(library.products.first { $0.id == "bochk.chill.platinum" }), in: context)
        chill.statementDay = 17; chill.paymentDay = 9; chill.name = "Personal nickname"
        try context.save()
        _ = try MailImportService.importTransactions([mail()], in: context)
        let entries = ["bochk.chill.platinum": "0007", "bochk.go.diamond": "0008",
                       "hsbc.student.visa.gold": "0009", "bea.hku.student.visa": "0010"]
        #expect(try LibraryCardConfiguration.apply(entries, in: context).saved == 1)
        _ = try LibraryCardConfiguration.apply(entries, in: context)
        let cards = try context.fetch(FetchDescriptor<BankCard>())
        #expect(cards.count == 4); #expect(cards.allSatisfy { entries[$0.catalogID] == $0.lastFour })
        #expect(chill.name == "Personal nickname"); #expect(chill.statementDay == 17); #expect(chill.paymentDay == 9)
        #expect(cards.allSatisfy { $0.rules.isEmpty })
        #expect(try MailImportService.reviewItems(in: context).isEmpty)
        let peer = try Persistence.makeContainer(inMemory: true)
        _ = try SyncStore.apply(SyncStore.records(context), context: peer.mainContext)
        #expect(try peer.mainContext.fetch(FetchDescriptor<BankCard>()).allSatisfy { entries[$0.catalogID] == $0.lastFour })
        #expect(throws: (any Error).self) { try LibraryCardConfiguration.apply(["not.a.product": "0001"], in: context) }
        #expect(try context.fetchCount(FetchDescriptor<BankCard>()) == 4)
    }

    private var time: Date { Date(timeIntervalSince1970: 1_768_360_800) }

    private func card(_ context: ModelContext, bank: String = "bochk", tail: String = "0007") throws -> BankCard {
        let card = BankCard(bank: bank.uppercased(), name: "Fictional test card", lastFour: tail)
        card.catalogID = bank + ".test.card"; context.insert(card); try context.save()
        return card
    }

    private func mail(_ id: String = "fictional-message-a", amount: Int64 = 12345, merchant: String = "Example Cafe",
                      currency: String = "HKD", exact: Bool = true, offset: TimeInterval = 0) -> BankMailTransaction {
        BankMailTransaction(messageID: id, bankID: "bochk", lastFour: "0007", merchant: merchant,
                            amountCents: amount, currency: currency, date: exact ? time.addingTimeInterval(offset) : HKCalendar.start(time),
                            hasExactTime: exact, receivedAt: time.addingTimeInterval(600 + offset),
                            paymentMethod: nil, channel: nil, region: nil, bankReference: nil)
    }

    private func request(_ card: BankCard, merchant: String = "Example Cafe", amount: Int64 = 12345,
                         currency: String = "HKD", offset: TimeInterval = 0, reference: String = "fictional-wallet-a") -> TransactionRequest {
        TransactionRequest(cardID: card.syncKey, merchant: merchant, amountCents: amount, currency: currency,
                           exchangeRate: currency == "HKD" ? "1" : "1.09", date: time.addingTimeInterval(offset),
                           paymentMethod: "Apple Pay", category: "餐饮", channel: "physical", isOverseas: true,
                           externalID: reference, source: "shortcuts", region: "CN", isRewardEligible: false,
                           notes: "Personal note")
    }

    @discardableResult private func wallet(_ request: TransactionRequest, in context: ModelContext) throws -> SpendTransaction {
        _ = try TransactionRecorder.record(request, in: context)
        try context.save()
        return try #require(try context.fetch(FetchDescriptor<SpendTransaction>()).first { $0.externalID == request.externalID })
    }

    @Test func newMailIsStableAndUnknownDetailsStayUnknown() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = try card(context)
        let first = try MailImportService.importTransactions([mail()], in: context)
        #expect(first.saved == 1)
        let transaction = try #require(try context.fetch(FetchDescriptor<SpendTransaction>()).first)
        let key = transaction.syncKey
        #expect(key.contains(":bankmail:")); #expect(transaction.card?.id == card.id)
        #expect(transaction.source == "email"); #expect(transaction.paymentMethod == "待确认")
        #expect(transaction.channel == "unknown"); #expect(transaction.region.isEmpty)
        #expect(try MailImportService.importTransactions([mail()], in: context).duplicate == 1)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        #expect(transaction.syncKey == key)
        let records = try SyncStore.records(context)
        for record in records { try SyncCodec.validate(record) }
        #expect(try !SyncStore.apply(records, context: context))
    }

    @Test func walletFirstMailKeepsPersonalFieldsAndDeletedMessagesCannotReturn() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = try card(context), input = request(card)
        let original = try wallet(input, in: context), alias = original.syncKey
        let imported = try MailImportService.importTransactions([mail()], in: context)
        #expect(imported.updated == 1)
        let transaction = try #require(try context.fetch(FetchDescriptor<SpendTransaction>()).first)
        #expect(transaction.category == "餐饮"); #expect(transaction.notes == "Personal note")
        #expect(!transaction.isRewardEligible); #expect(transaction.paymentMethod == "Apple Pay")
        #expect(transaction.channel == "physical"); #expect(transaction.region == "CN")
        #expect(transaction.syncKey != alias)
        if case .duplicate = try TransactionRecorder.record(input, in: context) {} else { Issue.record("Wallet retry was not deduplicated") }
        try Persistence.save(context) { Persistence.remove(transaction, context: context) }
        #expect(try MailImportService.importTransactions([mail()], in: context).duplicate == 1)
        if case .duplicate = try TransactionRecorder.record(input, in: context) {} else { Issue.record("Deleted alias resurrected") }
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 0)
    }

    @Test func mailFirstThenWalletIsOneTransactionWithWalletContext() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = try card(context)
        _ = try MailImportService.importTransactions([mail()], in: context)
        if case .duplicate = try TransactionRecorder.record(request(card), in: context) {} else { Issue.record("Email-first pair was not reconciled") }
        try context.save()
        let transaction = try #require(try context.fetch(FetchDescriptor<SpendTransaction>()).first)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        #expect(transaction.category == "餐饮"); #expect(transaction.paymentMethod == "Apple Pay")
        #expect(transaction.region == "CN"); #expect(transaction.notes == "Personal note")
    }

    @Test func foreignCurrencySavesWithoutFXAndPersonalEstimateCanBeAddedLater() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = try card(context)
        let foreign = mail(currency: "CNY")
        #expect(try MailImportService.importTransactions([foreign], in: context).saved == 1)
        let transaction = try #require(try context.fetch(FetchDescriptor<SpendTransaction>()).first)
        #expect(transaction.amountCents == foreign.amountCents); #expect(transaction.exchangeRate.isEmpty)
        #expect(transaction.hkdCents == 0); #expect(transaction.region.isEmpty)
        let draft = TransactionDraft(transaction: transaction)
        draft.exchangeRate = Decimal(string: "1.09")!
        #expect(draft.save(in: context, cards: [card]))
        #expect(transaction.exchangeRate == "1.09")
        #expect(try MailImportService.importTransactions([foreign], in: context).duplicate == 1)
    }

    @Test func changedMerchantAndAmountNeedConfirmationThenEmailOwnsFinancialFacts() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = try card(context)
        let original = try wallet(request(card, merchant: "Coffee Counter"), in: context)
        let alias = original.syncKey
        let bankMail = mail(merchant: "COFFEE COUNTER CENTRAL")
        #expect(try MailImportService.importTransactions([bankMail], in: context).pending == 1)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        var review = try #require(try MailImportService.reviewItems(in: context).first)
        #expect(review.candidateKeys == [alias])
        _ = try MailImportService.resolveReview(key: review.key, transactionKey: alias, in: context)
        let transaction = try #require(try context.fetch(FetchDescriptor<SpendTransaction>()).first)
        #expect(transaction.merchant == bankMail.merchant); #expect(transaction.notes == "Personal note")
        #expect(transaction.category == "餐饮"); #expect(!transaction.isRewardEligible)
        // A second day teaches no new identity: the confirmed merchant alias is reusable.
        _ = try wallet(request(card, merchant: "Coffee Counter", offset: 86400, reference: "fictional-wallet-b"), in: context)
        #expect(try MailImportService.importTransactions([mail("fictional-message-b", merchant: bankMail.merchant, offset: 86400)], in: context).updated == 1)
        // A financial disagreement stays pending until the target is explicitly selected.
        _ = try wallet(request(card, amount: 11000, offset: 172800, reference: "fictional-wallet-c"), in: context)
        #expect(try MailImportService.importTransactions([mail("fictional-message-c", amount: 12000, offset: 172800)], in: context).pending == 1)
        review = try #require(try MailImportService.reviewItems(in: context).first)
        _ = try MailImportService.resolveReview(key: review.key, transactionKey: try #require(review.candidateKeys.first), in: context)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 3)
        #expect(try context.fetch(FetchDescriptor<SpendTransaction>()).contains { $0.amountCents == 12000 })
    }

    @Test func mailFirstUnfamiliarWalletMerchantIsPendingUntilUserChoosesAnotherPurchase() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = try card(context)
        _ = try MailImportService.importTransactions([mail(merchant: "BANK MERCHANT CENTRAL")], in: context)
        let input = request(card, merchant: "Friendly merchant")
        if case .needsReview = try TransactionRecorder.record(input, in: context) {} else { Issue.record("Uncertain Wallet purchase bypassed review") }
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        if case .recorded = try TransactionRecorder.record(input, in: context, allowPossibleDuplicate: true) {} else { Issue.record("Confirmed separate purchase was swallowed") }
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 2)
    }

    @Test func virtualTailNeedsExplicitBankMatchedCardAndConflictingBankIsRejected() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let chosen = try card(context, tail: "0099"), other = try card(context, bank: "bea")
        let original = try wallet(request(chosen), in: context)
        #expect(try MailImportService.importTransactions([mail()], in: context).pending == 1)
        let review = try #require(try MailImportService.reviewItems(in: context).first)
        #expect(review.candidateKeys == [original.syncKey])
        #expect(throws: (any Error).self) {
            try MailImportService.resolveReview(key: review.key, cardKey: other.syncKey, saveAsAnother: true, in: context)
        }
        _ = try MailImportService.resolveReview(key: review.key, transactionKey: original.syncKey, cardKey: chosen.syncKey, in: context)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        #expect(try MailImportService.importTransactions([mail()], in: context).duplicate == 1)
    }

    @Test func dateOnlyEmailsPairOneToOneWithoutCollapsingTwoRealPurchases() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = try card(context)
        let first = try wallet(request(card), in: context)
        _ = try wallet(request(card, offset: 3600, reference: "fictional-wallet-b"), in: context)
        #expect(try MailImportService.importTransactions([mail(exact: false)], in: context).pending == 1)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 2)
        let review = try #require(try MailImportService.reviewItems(in: context).first)
        #expect(review.candidateKeys.count == 2)
        _ = try MailImportService.resolveReview(key: review.key, transactionKey: first.syncKey, in: context)
        #expect(try MailImportService.importTransactions([mail("fictional-message-b", exact: false)], in: context).updated == 1)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 2)
        let keys = try context.fetch(FetchDescriptor<SpendTransaction>()).map(\.syncKey)
        #expect(Set(keys).count == 2); #expect(keys.allSatisfy { $0.contains(":bankmail:") })
    }

    @Test func concurrentEmailAndWalletSnapshotsConvergeAndLaterDeleteWins() throws {
        let a = try Persistence.makeContainer(inMemory: true), b = try Persistence.makeContainer(inMemory: true)
        let cardA = try card(a.mainContext)
        _ = try SyncStore.apply(SyncStore.records(a.mainContext), context: b.mainContext)
        _ = try wallet(request(cardA), in: a.mainContext)
        _ = try MailImportService.importTransactions([mail()], in: b.mainContext)
        let walletSnapshot = try SyncStore.records(a.mainContext), mailSnapshot = try SyncStore.records(b.mainContext)
        #expect(SyncMerger.merge(walletSnapshot + mailSnapshot) == SyncMerger.merge(mailSnapshot + walletSnapshot))
        _ = try SyncStore.apply(mailSnapshot, context: a.mainContext)
        _ = try SyncStore.apply(walletSnapshot, context: b.mainContext)
        #expect(try a.mainContext.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        #expect(try b.mainContext.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        #expect(try SyncStore.records(a.mainContext) == SyncStore.records(b.mainContext))
        let transaction = try #require(try a.mainContext.fetch(FetchDescriptor<SpendTransaction>()).first)
        #expect(transaction.notes == "Personal note"); #expect(transaction.region == "CN")
        try Persistence.save(a.mainContext) { Persistence.remove(transaction, context: a.mainContext) }
        _ = try SyncStore.apply(SyncStore.records(a.mainContext), context: b.mainContext)
        _ = try SyncStore.apply(walletSnapshot + mailSnapshot, context: b.mainContext)
        #expect(try b.mainContext.fetchCount(FetchDescriptor<SpendTransaction>()) == 0)
        #expect(try MailImportService.importTransactions([mail()], in: b.mainContext).duplicate == 1)
        #expect(try !SyncStore.apply(SyncStore.records(b.mainContext), context: b.mainContext))
    }

    @Test func ambiguousConcurrentSnapshotsRequireReviewAndManualResolutionDoesNotDuplicateKeys() throws {
        let a = try Persistence.makeContainer(inMemory: true), b = try Persistence.makeContainer(inMemory: true)
        let cardA = try card(a.mainContext)
        _ = try SyncStore.apply(SyncStore.records(a.mainContext), context: b.mainContext)
        _ = try wallet(request(cardA), in: a.mainContext)
        _ = try wallet(request(cardA, offset: 3600, reference: "fictional-wallet-b"), in: a.mainContext)
        _ = try MailImportService.importTransactions([mail(exact: false), mail("fictional-message-b", exact: false)], in: b.mainContext)
        _ = try SyncStore.apply(SyncStore.records(a.mainContext), context: b.mainContext)
        let reviews = try MailImportService.reviewItems(in: b.mainContext)
        #expect(reviews.count == 2)
        let first = try #require(reviews.first), candidate = try #require(first.candidateKeys.first)
        _ = try MailImportService.resolveReview(key: first.key, transactionKey: candidate, in: b.mainContext)
        // Selecting one pair leaves one unique unclaimed pair, which can safely reconcile.
        #expect(try b.mainContext.fetchCount(FetchDescriptor<SpendTransaction>()) == 2)
        #expect(try MailImportService.reviewItems(in: b.mainContext).isEmpty)
    }

    @Test func wholeBatchIsAtomicAndIgnoredMailRemainsIgnored() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        _ = try card(context)
        var malformed = mail("fictional-malformed"); malformed.amountCents = -1
        #expect(throws: (any Error).self) { try MailImportService.importTransactions([mail(), malformed], in: context) }
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 0)
        var foreign = mail(currency: "USD"); foreign.lastFour = "9999"
        _ = try MailImportService.importTransactions([foreign], in: context)
        let review = try #require(try MailImportService.reviewItems(in: context).first)
        try MailImportService.ignoreReview(key: review.key, in: context)
        #expect(try MailImportService.importTransactions([foreign], in: context).duplicate == 1)
        #expect(try MailImportService.reviewItems(in: context).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 0)
    }

    @Test func preciseMailFindsSameDayDateOnlyCSVWithoutAutomaticallyOverwritingIt() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = try card(context)
        var csv = request(card, merchant: "Friendly CSV merchant")
        csv.date = HKCalendar.start(time); csv.hasStableDate = false; csv.source = "csv"; csv.externalID = "fictional-csv-row"
        let transaction = try wallet(csv, in: context), key = transaction.syncKey
        #expect(abs(mail().date.timeIntervalSince(csv.date)) > 180)
        #expect(try MailImportService.importTransactions([mail()], in: context).pending == 1)
        let review = try #require(try MailImportService.reviewItems(in: context).first)
        #expect(review.candidateKeys == [key])
        #expect(transaction.merchant == "Friendly CSV merchant")
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        _ = try MailImportService.resolveReview(key: review.key, transactionKey: key, in: context)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        #expect(transaction.merchant == mail().merchant)
    }

    @Test func correctedMailCurrencyRequiresItsOwnExchangeRateInsteadOfReusingOne() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = try card(context)
        _ = try MailImportService.importTransactions([mail()], in: context)
        let transaction = try #require(try context.fetch(FetchDescriptor<SpendTransaction>()).first)
        let canonical = transaction.syncKey
        let corrected = mail(currency: "CNY")
        #expect(try MailImportService.importTransactions([corrected], in: context).pending == 1)
        #expect(transaction.currency == "HKD"); #expect(transaction.exchangeRate == "1")
        let review = try #require(try MailImportService.reviewItems(in: context).first)
        #expect(review.candidateKeys == [canonical])
        _ = try MailImportService.resolveReview(key: review.key, transactionKey: canonical, cardKey: card.syncKey, exchangeRate: "1.08", in: context)
        #expect(transaction.currency == "CNY"); #expect(transaction.exchangeRate == "1.08")
        #expect(transaction.syncKey == canonical); #expect(transaction.region.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        // A completed review cannot be silently reopened by later parser changes.
        #expect(try MailImportService.importTransactions([mail(currency: "USD")], in: context).duplicate == 1)
        #expect(transaction.currency == "CNY"); #expect(transaction.exchangeRate == "1.08")
    }

    @Test func personallyEditedMailExchangeRateSurvivesProjectionSyncAndOldWalletReplay() throws {
        let a = try Persistence.makeContainer(inMemory: true), b = try Persistence.makeContainer(inMemory: true)
        let cardA = try card(a.mainContext)
        _ = try wallet(request(cardA, currency: "CNY"), in: a.mainContext)
        let oldWallet = try SyncStore.records(a.mainContext)
        #expect(try MailImportService.importTransactions([mail(currency: "CNY")], in: a.mainContext).updated == 1)
        let imported = try SyncStore.records(a.mainContext)
        _ = try SyncStore.apply(imported, context: b.mainContext)
        let transaction = try #require(try a.mainContext.fetch(FetchDescriptor<SpendTransaction>()).first)
        let suite = "CardPilot-mail-FX-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let draft = TransactionDraft(transaction: transaction, defaults: defaults)
        draft.exchangeRate = Decimal(string: "1.25")!
        #expect(draft.save(in: a.mainContext, cards: [cardA]))
        let edited = try SyncStore.records(a.mainContext)
        let projected = try #require(edited.first { $0.key == transaction.syncKey })
        let snapshot = try SyncCodec.decoder().decode(TransactionSyncData.self, from: try #require(projected.payload))
        #expect(snapshot.exchangeRate == "1.25")
        #expect(snapshot.currency == "CNY"); #expect(snapshot.amountCents == mail().amountCents)
        _ = try SyncStore.apply(edited, context: b.mainContext)
        _ = try SyncStore.apply(imported + oldWallet, context: a.mainContext)
        _ = try SyncStore.apply(imported + oldWallet, context: b.mainContext)
        let peer = try #require(try b.mainContext.fetch(FetchDescriptor<SpendTransaction>()).first)
        #expect(transaction.exchangeRate == "1.25"); #expect(peer.exchangeRate == "1.25")
        #expect(try a.mainContext.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        #expect(try b.mainContext.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        #expect(try SyncStore.records(a.mainContext) == SyncStore.records(b.mainContext))
    }
}
