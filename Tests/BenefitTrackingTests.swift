import Foundation
import SwiftData
import Testing
@testable import CardPilot

@Suite @MainActor struct BenefitTrackingTests {
    private func day(_ value: String) throws -> Date { try CatalogImporter.date(value) }

    @Test func publishedBenefitRendersWithoutTransactionsAndDoesNotTreatDisabledAsArchived() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Example card"); context.insert(card)
        let rule = RewardRule(name: "Specified mobile payment", card: card, rateBps: 120, capCents: 10000,
                              startsOn: try day("2026-01-01"), endsOn: try day("2026-12-31"))
        rule.isEnabled = false; rule.sourceURL = "https://example.com/terms"; rule.verifiedOn = "2026-10-22"
        rule.notes = "Registration required. Bank eligibility applies."; context.insert(rule)
        var extras = RuleExtras(); extras.paymentMethods = ["Apple Pay"]
        try RulePolicyStore.imported(RuleSyncData(rule), extras: extras, into: rule, isNew: true, context: context)
        let info = BenefitInfo(rule: rule)
        #expect(info.id == rule.id); #expect(!info.isArchived); #expect(info.group == .daily)
        #expect(info.headline.contains("1.2%")); #expect(info.conditions.contains { $0.contains("Apple Pay") })
        #expect(info.conditions.contains(rule.notes)); #expect(info.sourceURL == rule.sourceURL)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 0)
    }

    @Test func publishedTermsExposeReadableLabelsAndChipLists() {
        let rule = RewardRule(name: "Streaming offer")
        rule.category = "串流"
        rule.merchantKeywords = "Netflix,Spotify,Disney+"
        rule.paymentMethod = "Apple Pay"
        rule.notes = "Registration required. Bank eligibility applies."
        let info = BenefitInfo(rule: rule)
        #expect(info.labeledTerms.first { $0.label == "指定商户" }?.chips == ["Netflix", "Spotify", "Disney+"])
        #expect(info.labeledTerms.first { $0.label == "适用类别" }?.chips == ["串流"])
        #expect(info.noteTerms.contains { $0.value == rule.notes })
        #expect(info.labeledTerms.allSatisfy { $0.label != nil })
    }

    @Test func historicalReceiptIsPreservedAndManualStatusSurvivesSync() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Example card"); context.insert(card)
        let rule = RewardRule(name: "Welcome gift", kind: "welcome", card: card, thresholdCents: 300000, bonusCents: 60000,
                              startsOn: try day("2026-10-01"), endsOn: try day("2026-12-31"))
        context.insert(rule)
        let receivedOn = try day("2026-10-20")
        let legacy = WelcomeReceipt(received: true, receivedOn: receivedOn)
        try DocumentStore.put(legacy, key: "welcome:" + rule.syncKey, kind: "welcome", in: context)
        try context.save()
        var tracking = try WelcomeTrackingStore.load(rule: rule, context: context)
        #expect(tracking.status == .received); #expect(tracking.receivedOn == receivedOn)
        tracking.status = .achieved; tracking.notes = "Confirmed with bank"; tracking.rewardContent = "Gift voucher"
        tracking.deadline = try day("2027-01-15")
        try WelcomeTrackingStore.save(tracking, rule: rule, context: context)
        #expect(try DocumentStore.load(WelcomeReceipt.self, key: "welcome:" + rule.syncKey, in: context) == legacy)
        let peer = try Persistence.makeContainer(inMemory: true)
        _ = try SyncStore.apply(SyncStore.records(context), context: peer.mainContext)
        let remoteRule = try #require(try peer.mainContext.fetch(FetchDescriptor<RewardRule>()).first)
        #expect(try WelcomeTrackingStore.load(rule: remoteRule, context: peer.mainContext) == tracking)
        #expect(rule.thresholdCents == 300000); #expect(rule.bonusCents == 60000)
        #expect(try context.fetchCount(FetchDescriptor<SpendTransaction>()) == 0)
    }

    @Test func allFiveStatesAreUserControlledAndExpiryDoesNotEraseAwaitingReward() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Example card"); context.insert(card)
        let rule = RewardRule(name: "Welcome", kind: "welcome", card: card,
                              startsOn: try day("2026-01-01"), endsOn: try day("2026-02-01"))
        context.insert(rule)
        for status in WelcomeTrackingStatus.allCases {
            var tracking = try WelcomeTrackingStore.load(rule: rule, context: context)
            tracking.status = status
            try WelcomeTrackingStore.save(tracking, rule: rule, context: context)
            let saved = try WelcomeTrackingStore.load(rule: rule, context: context)
            #expect(saved.status == status)
            let expected: WelcomeTrackingStatus = status == .active || status == .unconfirmed ? .ended : status
            #expect(saved.effectiveStatus(now: try day("2026-10-22")) == expected)
        }
    }

    @Test func oldAddonReceiptCanBeReadByStablePlanIdentifierWithoutRewritingProfile() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Example card"); context.insert(card)
        let rule = RewardRule(name: "Gift", kind: "welcome", card: card,
                              startsOn: try day("2026-10-01"), endsOn: try day("2026-12-31"))
        rule.externalID = "fictional.plan"; context.insert(rule)
        let date = try day("2026-10-01")
        var profile = PersonalCardProfile(cardKey: card.syncKey, productID: "fictional", bankID: "example",
                                          applicationDate: date, applicationChannel: "online", issueDate: date,
                                          welcomePlanID: "", welcomeRuleIDs: [], welcomeEnabled: false,
                                          welcomeStartsOn: date, welcomeEndsOn: rule.endsOn, confirmedEligibility: false)
        let personalDeadline = try day("2026-11-15")
        profile.addons = [WelcomeAddonRecord(planID: rule.externalID, ruleIDs: [], confirmedEligibility: true,
                                             received: true, receivedOn: date, applicationChannel: "online", startsOn: date, endsOn: personalDeadline)]
        try DocumentStore.put(profile, key: "personalCard:" + card.syncKey, kind: "personalCardProfile", in: context)
        let before = try #require(try DocumentStore.record("personalCard:" + card.syncKey, in: context)).content
        let tracking = try WelcomeTrackingStore.load(rule: rule, context: context)
        #expect(tracking.status == .received); #expect(tracking.receivedOn == date)
        #expect(tracking.applicationDate == date); #expect(tracking.issueDate == date)
        #expect(tracking.deadline == personalDeadline); #expect(tracking.hasKnownDeadline)
        #expect(try #require(try DocumentStore.record("personalCard:" + card.syncKey, in: context)).content == before)
    }

    @Test func unverifiedOfficialDatesNeverBecomeExpiryOrPersonalReminderDates() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Example card"); context.insert(card)
        let rule = RewardRule(name: "Gift terms", kind: "welcome", card: card,
                              startsOn: try day("2026-01-01"), endsOn: try day("2026-02-01"))
        context.insert(rule)
        var extras = RuleExtras(); extras.periodUnverified = true
        try RulePolicyStore.imported(RuleSyncData(rule), extras: extras, into: rule, isNew: true, context: context)
        #expect(!BenefitInfo(rule: rule).hasKnownPeriod)
        var tracking = try WelcomeTrackingStore.load(rule: rule, context: context)
        #expect(!tracking.hasKnownDeadline)
        #expect(tracking.effectiveStatus(now: try day("2026-10-22")) == .active)
        tracking.status = .unconfirmed
        try WelcomeTrackingStore.save(tracking, rule: rule, context: context)
        #expect(try WelcomeTrackingStore.load(rule: rule, context: context).status == .unconfirmed)
        tracking.deadline = try day("2026-12-15"); tracking.deadlineConfirmed = true; tracking.status = .active
        try WelcomeTrackingStore.save(tracking, rule: rule, context: context)
        let saved = try WelcomeTrackingStore.load(rule: rule, context: context)
        #expect(saved.hasKnownDeadline); #expect(saved.deadline == tracking.deadline)
        let document = DocumentSyncData(key: WelcomeTrackingStore.key(rule), kind: "welcomeTracking", content: try SyncCodec.encoder().encode(saved), isDeleted: false)
        try DocumentValidator.validate(document)
        #expect(throws: (any Error).self) {
            try DocumentValidator.validate(DocumentSyncData(key: "unrelated", kind: "welcomeTracking", content: document.content, isDeleted: false))
        }
    }

    @Test func archivedLegacyWelcomeStaysEndedAndHistoricalReceiptWins() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Example card"); context.insert(card)
        let rule = RewardRule(name: "Welcome", kind: "welcome", card: card,
                              startsOn: try day("2026-10-01"), endsOn: try day("2026-12-31"))
        context.insert(rule); try RulePolicyStore.archive(rule, context: context)
        #expect(try WelcomeTrackingStore.load(rule: rule, context: context).status == .ended)
        let date = try day("2026-10-20")
        try DocumentStore.put(WelcomeReceipt(received: true, receivedOn: date), key: "welcome:" + rule.syncKey, kind: "welcome", in: context)
        let tracking = try WelcomeTrackingStore.load(rule: rule, context: context)
        #expect(tracking.status == .received); #expect(tracking.receivedOn == date)
        #expect(BenefitInfo(rule: rule).isArchived)
    }

    @Test func creatingPersonalWelcomeDoesNotAssumeAnApplicationOrVerifiedDates() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Example card"); context.insert(card)
        let draft = RuleDraft(rule: nil, cardID: card.id)
        draft.name = "Personal welcome note"; draft.kind = "welcome"; draft.notes = "Gift conditions to confirm"
        #expect(draft.save(in: context, cards: [card]))
        let rule = try #require(try context.fetch(FetchDescriptor<RewardRule>()).first)
        let tracking = try WelcomeTrackingStore.load(rule: rule, context: context)
        #expect(tracking.status == .unconfirmed); #expect(!tracking.hasKnownDeadline)
        #expect(tracking.applicationDate == nil); #expect(!BenefitInfo(rule: rule).hasKnownPeriod)
    }

    @Test func oldExtrasDecodeWithVerifiedPeriodDefaultAndMissingSourcesStayExplicit() throws {
        let extras = try SyncCodec.decoder().decode(RuleExtras.self, from: Data("{}".utf8))
        #expect(!extras.periodUnverified)
        let rule = RewardRule(name: "Unverified note")
        let info = BenefitInfo(rule: rule)
        #expect(info.sourceURL.isEmpty); #expect(info.verifiedOn.isEmpty)
        #expect(info.conditions.contains { $0.contains("待核实") })
    }

    @Test func unselectedOfficialWelcomeDoesNotAssumePersonalDeadlineFromPromotionPeriod() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "Example", name: "Example card"); context.insert(card)
        let rule = RewardRule(name: "Welcome", kind: "welcome", card: card,
                              startsOn: try day("2026-10-01"), endsOn: try day("2026-12-31"))
        rule.isEnabled = false; context.insert(rule)
        let tracking = try WelcomeTrackingStore.load(rule: rule, context: context)
        #expect(tracking.status == .unconfirmed); #expect(!tracking.hasKnownDeadline)
        #expect(BenefitInfo(rule: rule).hasKnownPeriod)
    }
}
