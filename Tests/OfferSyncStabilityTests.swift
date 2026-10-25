import Foundation
import SwiftData
import Testing
@testable import CardPilot

@Suite(.serialized) @MainActor
struct OfferSyncStabilityTests {
    @Test func batchProjectionPreservesOverlayPriorityAndReadsSubsequentChanges() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let product = try #require(BankLibrary.load().product(id: "bochk.chill.platinum"))
        let offerID = try #require(product.displayCatalog.rules.first?.id)
        let card = BankCard(bank: "BOCHK", name: "测试持卡")
        card.catalogID = product.id
        context.insert(card)
        let legacy = RewardRule(name: "旧权益", card: card)
        legacy.externalID = offerID
        legacy.notes = "保留用户修改的旧备注"
        context.insert(legacy)
        var policy = RulePolicyState()
        policy.archived = true
        policy.customized = true
        try DocumentStore.put(policy, key: RulePolicyStore.key(legacy), kind: "policy", in: context)
        let old = OfferPersonalState(hidden: true, favorite: false, enrollment: .notRegistered, notes: "UUID 旧状态")
        let legacyKey = OfferStateStore.legacyKey(cardID: card.id, offerID: offerID)
        try DocumentStore.put(old, key: legacyKey, kind: "offerState", in: context)
        let stable = OfferPersonalState(hidden: false, favorite: true, enrollment: .registered, notes: "稳定键优先")
        try OfferStateStore.save(stable, cardKey: card.overlayKey, offerID: offerID, in: context)

        let first = try #require(OfferStore.offers(for: card, context: context).first { $0.overlayOfferID == offerID })
        #expect(first.personal == stable)
        var updated = stable
        updated.notes = "保存后下次投影立即可见"
        try OfferStateStore.save(updated, cardKey: card.overlayKey, offerID: offerID, in: context)
        let all = try #require(OfferStore.offers(context: context).first { $0.overlayOfferID == offerID })
        #expect(all.personal == updated)

        try DocumentStore.remove(OfferStateStore.key(cardKey: card.overlayKey, offerID: offerID), in: context)
        try context.save()
        let uuidFallback = try #require(OfferStore.offers(for: card, context: context).first { $0.overlayOfferID == offerID })
        #expect(uuidFallback.personal == old)
        try DocumentStore.remove(legacyKey, in: context)
        try context.save()
        let policyFallback = try #require(OfferStore.offers(context: context).first { $0.overlayOfferID == offerID })
        #expect(policyFallback.isHidden)
        #expect(policyFallback.personal.notes == legacy.notes)

        // A corrupt stable record keeps the previous load-error behavior: it
        // does not silently replace the user's state with a lower-priority one.
        let record = try #require(try DocumentStore.record(OfferStateStore.key(cardKey: card.overlayKey, offerID: offerID), in: context))
        record.isDeleted = false
        record.content = Data("invalid JSON".utf8)
        try context.save()
        let corrupt = try #require(OfferStore.offers(for: card, context: context).first { $0.overlayOfferID == offerID })
        #expect(corrupt.personal == OfferPersonalState())
    }

    @Test func batchProjectionRetainsPersonalAndHistoricalRulePolicy() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "自定义银行", name: "自定义卡片")
        context.insert(card)
        for externalID in ["", "old.catalog.offer"] {
            let rule = RewardRule(name: externalID.isEmpty ? "个人权益" : "历史权益", card: card)
            rule.externalID = externalID
            rule.notes = "个人修改说明"
            context.insert(rule)
            var policy = RulePolicyState()
            policy.customized = true
            policy.archived = externalID.isEmpty
            policy.retired = !externalID.isEmpty
            policy.extras.periodUnverified = true
            policy.extras.benefitGroup = "merchant"
            try DocumentStore.put(policy, key: RulePolicyStore.key(rule), kind: "policy", in: context)
        }
        try context.save()

        let offers = OfferStore.offers(context: context)
        #expect(offers.count == 2)
        #expect(offers.contains { $0.origin == .personal })
        #expect(offers.contains { $0.origin == .historical })
        #expect(offers.allSatisfy { $0.isArchived && !$0.hasKnownPeriod && $0.group == .merchant })
        #expect(offers.allSatisfy { $0.personal.notes == "个人修改说明" })
    }

    @Test func favoritePreferencePersistsWithoutChangingOtherPersonalState() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "BOCHK", name: "Favorites")
        context.insert(card)
        let offerID = "bochk.chill.online.foreign.2026h2"
        let initial = OfferPersonalState(hidden: false, favorite: false,
                                         enrollment: .registered, notes: "保留备注")
        try OfferStateStore.save(initial, cardKey: card.overlayKey, offerID: offerID, in: context)

        try OfferStateStore.setFavorite(true, cardKey: card.overlayKey, cardID: card.id,
                                        offerID: offerID, legacy: nil, in: context)
        let favorited = try OfferStateStore.load(cardKey: card.overlayKey, cardID: card.id,
                                                 offerID: offerID, legacy: nil, in: context)
        #expect(favorited.favorite)
        #expect(!favorited.hidden)
        #expect(favorited.enrollment == .registered)
        #expect(favorited.notes == "保留备注")

        try OfferStateStore.setFavorite(false, cardKey: card.overlayKey, cardID: card.id,
                                        offerID: offerID, legacy: nil, in: context)
        let unfavorited = try OfferStateStore.load(cardKey: card.overlayKey, cardID: card.id,
                                                   offerID: offerID, legacy: nil, in: context)
        #expect(!unfavorited.favorite)
        #expect(unfavorited == initial)
    }

    @Test func personalFavoriteAppearsInTheOfferProjection() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "自定义银行", name: "个人收藏")
        context.insert(card)
        let rule = RewardRule(name: "个人权益", card: card, rateBps: 200)
        context.insert(rule)
        try context.save()

        let before = try #require(OfferStore.offers(for: card, context: context)
            .first { $0.origin == .personal })
        #expect(!before.personal.favorite)
        try OfferStateStore.setFavorite(true, cardKey: card.overlayKey, cardID: card.id,
                                        offerID: before.overlayOfferID, legacy: rule, in: context)
        let after = try #require(OfferStore.offers(for: card, context: context)
            .first { $0.overlayOfferID == before.overlayOfferID })
        #expect(after.personal.favorite)
    }

    @Test func personalOfferStateAndWelcomeProgressTravelBetweenIndependentLibraries() throws {
        let mac = try Persistence.makeContainer(inMemory: true)
        let phone = try Persistence.makeContainer(inMemory: true)
        let macContext = mac.mainContext, phoneContext = phone.mainContext

        let product = try #require(BankLibrary.load().products.first { $0.id == "bochk.chill.platinum" })
        let card = try LibraryOnboarding.add(product: product, in: macContext)
        card.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        try macContext.save()

        let offer = try #require(OfferStore.offers(for: card, context: macContext)
            .first { $0.isWelcome && $0.catalogRule != nil })
        let offerID = try #require(offer.catalogRule?.id)
        var state = offer.personal
        state.hidden = true
        state.enrollment = .registered
        state.notes = "只在 Mac 上记录的备注"
        try OfferStateStore.save(state, cardKey: card.overlayKey, offerID: offerID, in: macContext)

        var tracking = try OfferTrackingStore.load(for: offer, context: macContext)
        tracking.status = .achieved
        tracking.notes = "Mac 迎新进度"
        tracking.receivedOn = Date(timeIntervalSince1970: 1_700_000_100)
        try OfferTrackingStore.save(tracking, for: offer, context: macContext)

        let outgoing = try SyncStore.records(macContext)
        #expect(try SyncStore.apply(outgoing, context: phoneContext))

        let phoneCard = try #require(try phoneContext.fetch(FetchDescriptor<BankCard>()).first)
        #expect(phoneCard.overlayKey == card.overlayKey)
        let phoneOffer = try #require(OfferStore.offers(for: phoneCard, context: phoneContext)
            .first { $0.catalogRule?.id == offerID })
        #expect(phoneOffer.isHidden)
        #expect(phoneOffer.personal.enrollment == .registered)
        #expect(phoneOffer.personal.notes == "只在 Mac 上记录的备注")
        let phoneTracking = try OfferTrackingStore.load(for: phoneOffer, context: phoneContext)
        #expect(phoneTracking.status == .achieved)
        #expect(phoneTracking.notes == "Mac 迎新进度")
        #expect(phoneTracking.receivedOn == Date(timeIntervalSince1970: 1_700_000_100))

        var phoneState = phoneOffer.personal
        phoneState.hidden = false
        phoneState.enrollment = .notRegistered
        phoneState.notes = "在 iPhone 上更新"
        try OfferStateStore.save(phoneState, cardKey: phoneCard.overlayKey, offerID: offerID, in: phoneContext)
        var phoneProgress = phoneTracking
        phoneProgress.status = .received
        phoneProgress.notes = "iPhone 已到账"
        try OfferTrackingStore.save(phoneProgress, for: phoneOffer, context: phoneContext)

        let back = try SyncStore.records(phoneContext)
        #expect(try SyncStore.apply(back, context: macContext))
        let macOffer = try #require(OfferStore.offers(for: card, context: macContext)
            .first { $0.catalogRule?.id == offerID })
        #expect(!macOffer.isHidden)
        #expect(macOffer.personal.enrollment == .notRegistered)
        #expect(macOffer.personal.notes == "在 iPhone 上更新")
        let macTracking = try OfferTrackingStore.load(for: macOffer, context: macContext)
        #expect(macTracking.status == .received)
        #expect(macTracking.notes == "iPhone 已到账")
    }

    @Test func legacyUUIDKeyIsMigratedToStableCardKeyWithoutDeletingTheOldRecord() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let product = try #require(BankLibrary.load().products.first { $0.id == "bochk.chill.platinum" })
        let card = try LibraryOnboarding.add(product: product, in: context)
        card.createdAt = Date(timeIntervalSince1970: 1_700_000_200)
        try context.save()
        let offerID = "chill.platinum.online-overseas.2026"
        let legacyKey = OfferStateStore.legacyKey(cardID: card.id, offerID: offerID)
        let old = OfferPersonalState(hidden: true, favorite: false, enrollment: .registered, notes: "旧键备注")
        try DocumentStore.put(old, key: legacyKey, kind: "offerState", in: context)
        try context.save()

        try OfferMigration.migrateLegacy(in: context)
        let migrated = try OfferStateStore.load(cardKey: card.overlayKey, cardID: card.id, offerID: offerID,
                                                legacy: nil, in: context)
        #expect(migrated == old)
        #expect(try DocumentStore.load(OfferPersonalState.self, key: legacyKey, in: context) == old)
        #expect(try DocumentStore.load(OfferPersonalState.self,
                                       key: OfferStateStore.key(cardKey: card.overlayKey, offerID: offerID),
                                       in: context) == old)
    }
}
