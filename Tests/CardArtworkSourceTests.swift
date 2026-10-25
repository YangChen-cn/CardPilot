import Foundation
import SwiftData
import Testing
@testable import CardPilot

@Suite @MainActor
struct CardArtworkSourceTests {
    private func artwork() throws -> Data {
        try #require(BankLibrary.load().product(id: "bea.udc.diamond")?.artwork.bundledData())
    }

    private func product() throws -> CardProduct {
        try #require(BankLibrary.load().product(id: "bochk.chill.platinum"))
    }

    @Test func officialReferenceDoesNotTreatUnmarkedBytesAsCustomArtwork() throws {
        let store = try Persistence.makeContainer(inMemory: true)
        let card = try LibraryOnboarding.add(product: product(), in: store.mainContext)
        #expect(card.artworkSource == .catalog)
        #expect(card.imageData == nil)
        card.imageData = try artwork()
        #expect(!card.isCustomArtwork)
        let snapshot = CardSyncData(card)
        #expect(snapshot.artworkSource == .catalog)
        #expect(snapshot.imageData == nil)
        // The local projection is not a competing independent sync record.
        #expect(try SyncStore.records(store.mainContext).allSatisfy { !$0.key.hasPrefix("document:cardArtwork:") })
    }

    @Test func explicitCustomChoiceAndRestoringOfficialSurviveReopeningTheLedger() throws {
        let directory = URL.temporaryDirectory.appending(path: "CardPilot-artwork-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "ledger.store")
        let custom = try artwork()
        let expectedID: UUID
        do {
            let store = try Persistence.makeContainer(url: url), context = store.mainContext
            let card = try LibraryOnboarding.add(product: product(), in: context)
            expectedID = card.id
            let transaction = SpendTransaction(merchant: "Example store", amountCents: 1200, card: card)
            context.insert(transaction)
            let draft = CardDraft(card: card)
            try draft.importArtwork(custom)
            #expect(draft.save(in: context))
            #expect(card.artworkSource == .custom)
        }
        do {
            let store = try Persistence.makeContainer(url: url), context = store.mainContext
            let card = try #require(context.fetch(FetchDescriptor<BankCard>()).first)
            #expect(card.id == expectedID)
            #expect(card.artworkSource == .custom)
            #expect(card.imageData == custom)
            let draft = CardDraft(card: card)
            draft.restoreCatalogArtwork()
            #expect(draft.save(in: context))
            #expect(card.artworkSource == .catalog)
            #expect(card.imageData == nil)
        }
        let store = try Persistence.makeContainer(url: url), context = store.mainContext
        let card = try #require(context.fetch(FetchDescriptor<BankCard>()).first)
        #expect(card.id == expectedID)
        #expect(card.artworkSource == .catalog)
        #expect(card.imageData == nil)
        #expect(card.catalogID == (try product()).id)
        #expect(card.transactions.count == 1)
        #expect(card.transactions.first?.amountCents == 1200)
    }

    @Test func sourceAndCustomImageSyncTogetherAndAnOldSnapshotCannotUndoRestore() throws {
        let first = try Persistence.makeContainer(inMemory: true), context = first.mainContext
        let card = try LibraryOnboarding.add(product: product(), in: context)
        let custom = try artwork()
        let draft = CardDraft(card: card); try draft.importArtwork(custom)
        #expect(draft.save(in: context))
        let customSnapshot = try SyncStore.records(context)
        let peer = try Persistence.makeContainer(inMemory: true)
        _ = try SyncStore.apply(customSnapshot, context: peer.mainContext)
        let peerCard = try #require(peer.mainContext.fetch(FetchDescriptor<BankCard>()).first)
        #expect(peerCard.artworkSource == .custom)
        #expect(peerCard.imageData == custom)

        let restore = CardDraft(card: card); restore.restoreCatalogArtwork()
        #expect(restore.save(in: context))
        let restored = try SyncStore.records(context)
        _ = try SyncStore.apply(restored, context: peer.mainContext)
        _ = try SyncStore.apply(customSnapshot, context: peer.mainContext)
        #expect(peerCard.artworkSource == .catalog)
        #expect(peerCard.imageData == nil)
        #expect(SyncMerger.merge(customSnapshot + restored) == SyncMerger.merge(restored + customSnapshot))
        #expect(try SyncStore.records(peer.mainContext) == restored)
    }

    @Test func profileWinnerKeepsArtworkChoiceAndBytesPairedWhenAnotherEditIsNewer() throws {
        let store = try Persistence.makeContainer(inMemory: true), context = store.mainContext
        let card = try LibraryOnboarding.add(product: product(), in: context)
        let custom = try artwork()
        var customProfile = CardSyncData(card)
        customProfile.artworkSource = .custom; customProfile.imageData = custom
        customProfile.profileRevision = Date(timeIntervalSince1970: 200)
        var staleProfile = CardSyncData(card)
        staleProfile.artworkSource = .catalog; staleProfile.imageData = nil
        staleProfile.profileRevision = Date(timeIntervalSince1970: 100)
        let old = SyncRecord(key: card.syncKey, kind: "card", revision: Date(timeIntervalSince1970: 200),
                             deleted: false, payload: try SyncCodec.encoder().encode(customProfile))
        let newerOtherEdit = SyncRecord(key: card.syncKey, kind: "card", revision: Date(timeIntervalSince1970: 300),
                                        deleted: false, payload: try SyncCodec.encoder().encode(staleProfile))
        let record = try #require(SyncMerger.merge([old, newerOtherEdit]).first)
        let result = try SyncCodec.decoder().decode(CardSyncData.self, from: #require(record.payload))
        #expect(result.artworkSource == .custom)
        #expect(result.imageData == custom)
    }

    @Test func newManualCustomCardRecordsTheExplicitProfileChoice() throws {
        let store = try Persistence.makeContainer(inMemory: true), context = store.mainContext
        let draft = CardDraft(card: nil); draft.bank = "Example bank"; draft.name = "Example card"
        try draft.importArtwork(artwork())
        #expect(draft.save(in: context))
        let card = try #require(context.fetch(FetchDescriptor<BankCard>()).first)
        #expect(card.statementDay == 0); #expect(card.paymentDay == 0); #expect(card.lastFour.isEmpty)
        let record = try #require(SyncStore.records(context).first { $0.kind == "card" })
        let value = try SyncCodec.decoder().decode(CardSyncData.self, from: #require(record.payload))
        #expect(value.profileRevision != nil)
        #expect(value.artworkSource == .custom)
        #expect(value.imageData != nil)
    }

    @Test func invalidSourceOrCustomWithoutAnImageIsRejected() throws {
        let store = try Persistence.makeContainer(inMemory: true), context = store.mainContext
        let card = try LibraryOnboarding.add(product: product(), in: context)
        var value = CardSyncData(card); value.artworkSource = .custom
        let record = SyncRecord(key: card.syncKey, kind: "card", revision: .now, deleted: false,
                                payload: try SyncCodec.encoder().encode(value))
        #expect(throws: (any Error).self) { try SyncCodec.validate(record) }
        let data = try #require(String(data: SyncCodec.encoder().encode(value), encoding: .utf8))
            .replacingOccurrences(of: "\"custom\"", with: "\"invalid\"")
        #expect(throws: (any Error).self) { try SyncCodec.decoder().decode(CardSyncData.self, from: Data(data.utf8)) }
    }
}
