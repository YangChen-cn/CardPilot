import Testing
import Foundation
import SwiftData
@testable import CardPilot

@Suite @MainActor
struct RecommendationTests {
    private func day(_ text: String) throws -> Date { try CatalogImporter.date(text) }
    private func rule(_ card: BankCard, context: ModelContext) throws -> RewardRule {
        let rule = RewardRule(name: "Published offer", card: card, rateBps: 500,
                              startsOn: try day("2026-10-01"), endsOn: try day("2026-12-31"))
        rule.sourceURL = "https://example.com/terms"; rule.verifiedOn = "2026-10-01"
        context.insert(rule); return rule
    }
    private func query() -> RecommendationDraft {
        let query = RecommendationDraft(); query.region = "HK"; return query
    }

    @Test func suppliedDateControlsOfferAvailabilityIncludingTheLastDay() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Dated offer"); context.insert(card)
        _ = try rule(card, context: context)
        let input = query()
        #expect(RecommendationEngine.suggest(cards: [card], query: input, now: try day("2026-09-30")).isEmpty)
        #expect(RecommendationEngine.suggest(cards: [card], query: input, now: try day("2026-10-01")).count == 1)
        let lastEvening = try day("2026-12-31").addingTimeInterval(23 * 3600)
        #expect(RecommendationEngine.suggest(cards: [card], query: input, now: lastEvening).count == 1)
        #expect(RecommendationEngine.suggest(cards: [card], query: input, now: try day("2027-01-01")).isEmpty)
    }

    @Test func optionalAmountAndMerchantDoNotPreventCategorySuggestions() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Dining"); context.insert(card)
        let offer = try rule(card, context: context); offer.category = "餐饮"
        let input = query()
        #expect(input.amount == nil); #expect(input.merchant.isEmpty); #expect(input.paymentMethod.isEmpty)
        let suggestions = RecommendationEngine.suggest(cards: [card], query: input, now: try day("2026-10-22"))
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.offers.first?.matchedConditions.contains("适用于餐饮") == true)
        input.category = "购物"
        #expect(RecommendationEngine.suggest(cards: [card], query: input, now: try day("2026-10-22")).isEmpty)
    }

    @Test func unknownPaymentAndMerchantAreExplicitConditionsNotProvenEligibility() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Mobile"); context.insert(card)
        let offer = try rule(card, context: context); offer.paymentMethod = "Apple Pay"; offer.merchantKeywords = "GU"
        let input = query()
        var suggestions = RecommendationEngine.suggest(cards: [card], query: input, now: try day("2026-10-22"))
        var possible = try #require(suggestions.first?.offers.first)
        #expect(possible.confirmationNeeded.contains { $0.contains("支付方式尚未指定") })
        #expect(possible.confirmationNeeded.contains { $0.contains("指定商户") })
        input.paymentMethod = "实体卡"
        #expect(RecommendationEngine.suggest(cards: [card], query: input, now: try day("2026-10-22")).isEmpty)
        input.paymentMethod = "Apple Pay"; input.merchant = "GUCCI"
        #expect(RecommendationEngine.suggest(cards: [card], query: input, now: try day("2026-10-22")).isEmpty)
        input.merchant = "GU Hong Kong"
        suggestions = RecommendationEngine.suggest(cards: [card], query: input, now: try day("2026-10-22"))
        possible = try #require(suggestions.first?.offers.first)
        #expect(possible.matchedConditions.count == 2)
        #expect(!possible.confirmationNeeded.contains { $0.contains("推广登记") })
    }

    @Test func publicValueBeatsMatchCountEvenWhenAnotherCardMatchesMoreConditions() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let highValue = BankCard(bank: "Example", name: "High value"); context.insert(highValue)
        let highOffer = try rule(highValue, context: context)
        highOffer.rateBps = 800
        highOffer.paymentMethod = "Apple Pay"
        let manyMatches = BankCard(bank: "Example", name: "Many matches"); context.insert(manyMatches)
        for index in 0..<2 {
            let small = try rule(manyMatches, context: context)
            small.name = "Small offer \(index)"
            small.rateBps = 100
            small.category = "餐饮"
        }
        let input = query()
        input.paymentMethod = "Apple Pay"

        let suggestions = RecommendationEngine.suggest(cards: [manyMatches, highValue], query: input,
                                                       now: try day("2026-10-22"))
        let first = try #require(suggestions.first)
        let second = try #require(suggestions.dropFirst().first)
        #expect(first.card.name == "High value")
        #expect(first.knownMatches < second.knownMatches)
        #expect(first.bestRateBps == 800)
    }

    @Test func higherPublicOfferValueRanksAheadOfAMatchCountTie() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let library = try BankLibrary.load()
        let goProduct = try #require(library.products.first { $0.id == "bochk.go.diamond" })
        let chillProduct = try #require(library.products.first { $0.id == "bochk.chill.platinum" })
        let go = try LibraryOnboarding.add(product: goProduct, in: context)
        let chill = try LibraryOnboarding.add(product: chillProduct, in: context)
        let input = query()
        input.region = "CN"; input.currency = "CNY"; input.paymentMethod = "Apple Pay"

        let suggestions = RecommendationEngine.suggest(cards: [chill, go], query: input,
                                                       now: try day("2026-10-22"))
        let first = try #require(suggestions.first)
        let offer = try #require(first.topOffer)
        #expect(first.card.catalogID == "bochk.go.diamond")
        #expect(offer.rateBps == 800)
        #expect(offer.title.contains("8%"))
        #expect(first.rankingLabel == "需补充信息")
        #expect(offer.keyMissingConditions.contains("登记状态"))
        _ = try OfferStateStore.setEnrollment(.notRegistered, cardKey: go.overlayKey, cardID: go.id,
                                              offerID: "go.diamond.mobile.mainland.2026q4", legacy: nil, in: context)
        let unregistered = try #require(RecommendationEngine.suggest(cards: [go], query: input,
                                                                     now: try day("2026-10-22")).first?.topOffer)
        #expect(unregistered.keyMissingConditions.contains("登记状态"))
        #expect(unregistered.confirmationNeeded.contains { $0.contains("尚未登记") })
    }

    @Test func unspecifiedPaymentMethodKeepsTheCandidateOpenInsteadOfCallingItBest() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let library = try BankLibrary.load()
        let goProduct = try #require(library.products.first { $0.id == "bochk.go.diamond" })
        let chillProduct = try #require(library.products.first { $0.id == "bochk.chill.platinum" })
        let go = try LibraryOnboarding.add(product: goProduct, in: context)
        let chill = try LibraryOnboarding.add(product: chillProduct, in: context)
        let input = query(); input.region = "CN"; input.currency = "CNY"

        let first = try #require(RecommendationEngine.suggest(
            cards: [go, chill], query: input, now: try day("2026-10-22")
        ).first)
        let offer = try #require(first.topOffer)
        #expect(first.card.catalogID == "bochk.go.diamond")
        #expect(offer.keyMissingConditions.contains("支付方式"))
        #expect(offer.confirmationNeeded.contains { $0.contains("支付方式尚未指定") })
        #expect(first.isConditional)
        #expect(first.rankingSummary.contains("先确认支付方式"))
    }

    @Test func physicalCardComparisonDropsTheMobileOnlyQuarterlyOffer() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let library = try BankLibrary.load()
        let goProduct = try #require(library.products.first { $0.id == "bochk.go.diamond" })
        let chillProduct = try #require(library.products.first { $0.id == "bochk.chill.platinum" })
        let go = try LibraryOnboarding.add(product: goProduct, in: context)
        let chill = try LibraryOnboarding.add(product: chillProduct, in: context)
        let input = query()
        input.region = "CN"; input.currency = "CNY"; input.paymentMethod = "实体卡"

        let suggestions = RecommendationEngine.suggest(cards: [go, chill], query: input,
                                                       now: try day("2026-10-22"))
        #expect(suggestions.first?.card.catalogID == "bochk.chill.platinum")
        let goResult = try #require(suggestions.first { $0.card.catalogID == "bochk.go.diamond" })
        #expect(goResult.offers.allSatisfy { $0.rateBps < 800 })
    }

    @Test func foreignCurrencyNeverSelectsRegionOrNeedsAnExchangeRate() throws {
        let input = RecommendationDraft(); input.currency = "CNY"
        #expect(input.region.isEmpty); #expect(input.validationError != nil)
        input.region = "HK"
        #expect(input.validationError == nil)
        input.currency = "USD"
        #expect(input.region == "HK"); #expect(input.validationError == nil)
        input.amount = -1
        #expect(input.validationError != nil)
        input.amount = nil
        #expect(input.validationError == nil)
    }

    @Test(arguments: [10000, 399999, 400000])
    func catalogOriginalCurrencyMinimumUsesTheEnteredCurrency(_ cents: Int64) throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let library = try BankLibrary.load()
        let product = try #require(library.products.first { product in
            product.catalog.rules.contains { $0.id == "cny6" }
        })
        let card = try LibraryOnboarding.add(product: product, in: context)
        let input = query(); input.currency = "CNY"; input.region = "CN"; input.paymentMethod = "实体卡"
        input.amount = Decimal(cents) / 100
        let offers = RecommendationEngine.suggest(cards: [card], query: input).flatMap(\.offers)
        let candidate = offers.first { $0.title.contains("CNY4,000") }
        if cents == 400000 {
            let match = try #require(candidate)
            #expect(match.matchedConditions.contains("预计原币金额达到公开单笔门槛。"))
            #expect(!match.confirmationNeeded.isEmpty)
        } else {
            #expect(candidate == nil)
        }
        input.amount = nil
        let unknown = try #require(RecommendationEngine.suggest(cards: [card], query: input)
            .flatMap(\.offers).first { $0.title.contains("CNY4,000") })
        #expect(unknown.keyMissingConditions.contains("最低单笔消费"))
        #expect(!unknown.matchedConditions.contains("预计原币金额达到公开单笔门槛。"))
        input.amount = 4000; input.currency = "HKD"
        #expect(RecommendationEngine.suggest(cards: [card], query: input)
            .flatMap(\.offers).allSatisfy { !$0.title.contains("CNY4,000") })
    }

    @Test func unknownOriginalCurrencyAndUnconvertedHKDMinimumRemainUnconfirmed() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Minimums"); context.insert(card)
        let offer = try rule(card, context: context); offer.minimumCents = 50000
        var extras = RuleExtras(); extras.minimumOriginalCents = 400000
        try RulePolicyStore.imported(RuleSyncData(offer), extras: extras, into: offer, isNew: true, context: context)
        let input = query(); input.currency = "CNY"; input.amount = 5000
        let candidate = try #require(RecommendationEngine.suggest(cards: [card], query: input).first?.offers.first)
        #expect(candidate.keyMissingConditions.contains("最低单笔消费"))
        #expect(candidate.confirmationNeeded.contains { $0.contains("结算金额") })
        #expect(candidate.confirmationNeeded.contains { $0.contains("交易币种及原币金额") })
        #expect(!candidate.matchedConditions.contains { $0.contains("门槛") })
        input.currency = "HKD"; input.amount = 499.99
        #expect(RecommendationEngine.suggest(cards: [card], query: input).isEmpty)
    }

    @Test func publishedRegionExclusionsAreRespectedWhileCapsStayUnconfirmed() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Mainland"); context.insert(card)
        let offer = try rule(card, context: context); offer.capCents = 10000; offer.sharedCapGroup = "shared"
        var extras = RuleExtras(); extras.regions = ["CN"]
        try RulePolicyStore.imported(RuleSyncData(offer), extras: extras, into: offer, isNew: true, context: context)
        let input = query(); input.currency = "CNY"
        #expect(RecommendationEngine.suggest(cards: [card], query: input, now: try day("2026-10-22")).isEmpty)
        input.region = "CN"
        let possible = try #require(RecommendationEngine.suggest(cards: [card], query: input, now: day("2026-10-22")).first?.offers.first)
        #expect(possible.confirmationNeeded.contains { $0.contains("剩余名额") })
        #expect(possible.confirmationNeeded.contains { $0.contains("共享上限") })
    }

    @Test func expiredArchivedAndWelcomeOffersNeverBecomeSpendRecommendations() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Card"); context.insert(card)
        let expired = try rule(card, context: context); expired.endsOn = try day("2026-10-01")
        let future = try rule(card, context: context); future.startsOn = try day("2026-11-01")
        let welcome = try rule(card, context: context); welcome.kind = "welcome"
        let archived = try rule(card, context: context)
        try RulePolicyStore.archive(archived, context: context)
        #expect(RecommendationEngine.suggest(cards: [card], query: query(), now: try day("2026-10-22")).isEmpty)
        card.baseRateBps = 100; card.isArchived = true
        #expect(RecommendationEngine.suggest(cards: [card], query: query(), now: try day("2026-10-22")).isEmpty)
    }

    @Test func suggestionsDoNotReadPurchaseHistoryOrWriteAnyData() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Card", baseRateBps: 100); context.insert(card)
        let offer = try rule(card, context: context); offer.monthlyPhysicalThresholdCents = 100000
        let purchase = SpendTransaction(merchant: "Example", amountCents: 999999, card: card)
        context.insert(purchase); try context.save()
        for _ in 0..<3 {
            let possible = try #require(RecommendationEngine.suggest(cards: [card], query: query(), now: day("2026-10-22")).first?.offers.first)
            #expect(possible.confirmationNeeded.contains { $0.contains("每月实体消费须满") })
        }
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 1)
        #expect(!context.hasChanges)
    }

    @Test func unknownPeriodDoesNotTurnCompatibilityDatesIntoVerifiedAvailability() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Card"); context.insert(card)
        let offer = try rule(card, context: context)
        offer.startsOn = try day("2020-01-01"); offer.endsOn = try day("2020-12-31")
        var extras = RuleExtras(); extras.periodUnverified = true
        try RulePolicyStore.imported(RuleSyncData(offer), extras: extras, into: offer, isNew: true, context: context)
        let possible = try #require(RecommendationEngine.suggest(cards: [card], query: query(), now: day("2026-10-22")).first?.offers.first)
        #expect(possible.confirmationNeeded.contains { $0.contains("开始日期未列明") })
        #expect(!possible.hasKnownEnd)
        #expect(!BenefitInfo(rule: possible.rule).hasKnownPeriod)
    }

    @Test func recommendationKeepsSpecificConditionsWithoutCopyingProductNotes() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Card"); context.insert(card)
        card.caveats = "产品专属长说明，不应混入支付条件"
        let activity = try rule(card, context: context)
        activity.capCents = 10000
        activity.monthlyPhysicalThresholdCents = 300000
        let candidate = try #require(RecommendationEngine.suggest(cards: [card], query: query(), now: day("2026-10-22")).first)
        #expect(candidate.caveats.isEmpty)
        let offer = try #require(candidate.topOffer)
        #expect(offer.confirmationNeeded.contains { $0.contains("上限") })
        #expect(offer.confirmationNeeded.contains { $0.contains("每月实体消费须满") })
        #expect(offer.keyMissingConditions.contains("累计消费门槛"))
        #expect(!offer.confirmationNeeded.contains { $0.contains("其他限制以银行条款为准") })
    }

    @Test func unsourcedPersonalBaseRateIsNotLabelledAsVerifiedPublishedTerms() throws {
        let card = BankCard(bank: "Example", name: "Personal card", baseRateBps: 500)
        let personal = try #require(RecommendationEngine.suggest(cards: [card], query: query()).first)
        #expect(personal.baseBenefit == "个人记录的基础权益，来源待核实。")
        card.sourceURL = "https://example.com/card"; card.verifiedOn = "2026-10-01"
        let sourced = try #require(RecommendationEngine.suggest(cards: [card], query: query()).first)
        #expect(sourced.baseBenefit?.contains("参考") == true)
        #expect(sourced.baseBenefit?.contains("核对官方条款") == false)
    }
}
