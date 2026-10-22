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
        #expect(possible.confirmationNeeded.contains { $0.contains("推广登记") })
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
            #expect(possible.confirmationNeeded.contains { $0.contains("不判断你是否已达到") })
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
        #expect(possible.confirmationNeeded.contains { $0.contains("活动开始日期未核实") })
        #expect(possible.confirmationNeeded.contains { $0.contains("活动结束日期未核实") })
        #expect(!BenefitInfo(rule: possible.rule).hasKnownPeriod)
    }

    @Test func unsourcedPersonalBaseRateIsNotLabelledAsVerifiedPublishedTerms() throws {
        let card = BankCard(bank: "Example", name: "Personal card", baseRateBps: 500)
        let personal = try #require(RecommendationEngine.suggest(cards: [card], query: query()).first)
        #expect(personal.baseBenefit == "个人记录的基础权益，来源待核实。")
        card.sourceURL = "https://example.com/card"; card.verifiedOn = "2026-10-01"
        let sourced = try #require(RecommendationEngine.suggest(cards: [card], query: query()).first)
        #expect(sourced.baseBenefit?.contains("参考") == true)
        #expect(sourced.baseBenefit?.contains("核对官方条款") == true)
    }
}
