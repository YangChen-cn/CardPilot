import Foundation
import SwiftData
import Testing
@testable import CardPilot

@Suite(.serialized) @MainActor
struct OfferSyncStabilityTests {
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
