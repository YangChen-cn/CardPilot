import Testing
import Foundation
import SwiftData
@testable import CardPilot

@Suite @MainActor
struct FolderSyncTests {
    private func folder() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "CardPilot-sync-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sample(_ context: ModelContext) throws -> BankCard {
        let card = BankCard(bank: "Test Bank", name: "Test Card", statementDay: 0, paymentDay: 0, baseRateBps: 100)
        card.catalogID = "test.card"; card.modifiedAt = .now
        context.insert(card)
        let rule = RewardRule(name: "Dining", card: card, rateBps: 500,
                              startsOn: try CatalogImporter.date("2026-01-01"), endsOn: try CatalogImporter.date("2027-01-01"))
        rule.externalID = "dining"; rule.modifiedAt = .now; context.insert(rule)
        let imageURL = try #require(Bundle.main.url(forResource: "chill-platinum", withExtension: "png"))
        card.imageData = try Data(contentsOf: imageURL)
        try card.setArtworkSource(.custom, in: context)
        try context.save()
        return card
    }

    @Test func twoDevicesRoundTripEditsDeletionAndCardImages() async throws {
        let folder = try folder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = try Persistence.makeContainer(inMemory: true)
        let b = try Persistence.makeContainer(inMemory: true)
        let cardA = try sample(a.mainContext)
        let deviceA = UUID(), deviceB = UUID()
        let engineA = FolderSyncEngine(), engineB = FolderSyncEngine()
        let first = try SyncStore.records(a.mainContext)
        #expect(try await engineA.publish(folder: folder, deviceID: deviceA, records: first))
        let imported = try await engineB.read(folder: folder, deviceID: deviceB, local: [], previouslyPublished: false)
        #expect(try SyncStore.apply(imported, context: b.mainContext))
        let cardB = try #require(b.mainContext.fetch(FetchDescriptor<BankCard>()).first)
        #expect(cardB.name == "Test Card"); #expect(cardB.rules.count == 1)
        #expect(cardB.imageData == cardA.imageData)
        let draft = TransactionDraft(transaction: nil)
        draft.cardID = cardB.id; draft.merchant = "Coffee"; draft.amount = 120
        #expect(draft.save(in: b.mainContext, cards: [cardB]))
        #expect(try await engineB.publish(folder: folder, deviceID: deviceB, records: SyncStore.records(b.mainContext)))
        let received = try await engineA.read(folder: folder, deviceID: deviceA, local: SyncStore.records(a.mainContext), previouslyPublished: true)
        _ = try SyncStore.apply(received, context: a.mainContext)
        #expect(cardA.transactions.count == 1)
        let transactionA = try #require(cardA.transactions.first)
        let edit = TransactionDraft(transaction: transactionA); edit.amount = 250
        #expect(edit.save(in: a.mainContext, cards: [cardA]))
        _ = try await engineA.publish(folder: folder, deviceID: deviceA, records: SyncStore.records(a.mainContext))
        let back = try await engineB.read(folder: folder, deviceID: deviceB, local: SyncStore.records(b.mainContext), previouslyPublished: true)
        _ = try SyncStore.apply(back, context: b.mainContext)
        #expect(cardB.transactions.first?.amountCents == 25_000)
        let transactionB = try #require(cardB.transactions.first)
        try Persistence.save(b.mainContext) { Persistence.remove(transactionB, context: b.mainContext) }
        _ = try await engineB.publish(folder: folder, deviceID: deviceB, records: SyncStore.records(b.mainContext))
        let deleted = try await engineA.read(folder: folder, deviceID: deviceA, local: SyncStore.records(a.mainContext), previouslyPublished: true)
        _ = try SyncStore.apply(deleted, context: a.mainContext)
        #expect(cardA.transactions.isEmpty)
        #expect(try a.mainContext.fetchCount(FetchDescriptor<SyncTombstone>()) == 1)
        // The stale first/previous snapshots cannot resurrect an explicitly deleted transaction.
        _ = try SyncStore.apply(received, context: a.mainContext)
        #expect(cardA.transactions.isEmpty)
        let stable = try SyncStore.records(a.mainContext)
        #expect(try !SyncStore.apply(stable, context: a.mainContext))
        _ = try await engineA.publish(folder: folder, deviceID: deviceA, records: stable)
        #expect(try await engineA.publish(folder: folder, deviceID: deviceA, records: stable) == false)
    }

    @Test func tiedProfileRevisionCannotFlipArtworkAfterReplayingAnOriginalSnapshot() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let card = try sample(container.mainContext)
        var a = CardSyncData(card)
        a.profileRevision = Date(timeIntervalSince1970: 1000)
        a.annualFeeNote = "A"
        var b = a
        b.annualFeeNote = "Z"
        b.artworkSource = .catalog; b.imageData = nil
        let originalA = SyncRecord(key: card.syncKey, kind: "card", revision: Date(timeIntervalSince1970: 3000),
                                   deleted: false, payload: try SyncCodec.encoder().encode(a))
        let originalB = SyncRecord(key: card.syncKey, kind: "card", revision: Date(timeIntervalSince1970: 2000),
                                   deleted: false, payload: try SyncCodec.encoder().encode(b))
        let merged = SyncMerger.merge([originalA, originalB])
        #expect(merged == SyncMerger.merge([originalB, originalA]))
        let value = try SyncCodec.decoder().decode(CardSyncData.self, from: #require(merged.first?.payload))
        #expect(value.annualFeeNote == "A")
        #expect(value.artworkSource == .custom); #expect(value.imageData == a.imageData)
        #expect(SyncMerger.merge(merged + [originalA]) == merged)
        #expect(SyncMerger.merge(merged + [originalB]) == merged)
        #expect(SyncMerger.merge(merged + [originalB, originalA]) == merged)
        #expect(SyncMerger.merge([originalA] + merged) == merged)
    }

    @Test func tiedWelcomeProfileKeepsPersonalDatesStableWhenReplayingSnapshots() throws {
        let start = try CatalogImporter.date("2026-10-01"), end = try CatalogImporter.date("2026-12-31")
        let rule = RewardRule(name: "Example welcome", kind: "welcome", startsOn: start, endsOn: end)
        var a = RuleSyncData(rule); a.profileRevision = Date(timeIntervalSince1970: 1000)
        var b = a; b.startsOn = start.addingTimeInterval(-86400); b.bonusCents = 100
        let originalA = SyncRecord(key: "rule:example", kind: "rule", revision: Date(timeIntervalSince1970: 3000),
                                   deleted: false, cardKey: "card:example", payload: try SyncCodec.encoder().encode(a))
        let originalB = SyncRecord(key: "rule:example", kind: "rule", revision: Date(timeIntervalSince1970: 2000),
                                   deleted: false, cardKey: "card:example", payload: try SyncCodec.encoder().encode(b))
        let merged = SyncMerger.merge([originalA, originalB])
        #expect(merged == SyncMerger.merge([originalB, originalA]))
        let value = try SyncCodec.decoder().decode(RuleSyncData.self, from: #require(merged.first?.payload))
        #expect(value.startsOn == a.startsOn); #expect(value.bonusCents == a.bonusCents)
        #expect(SyncMerger.merge(merged + [originalA]) == merged)
        #expect(SyncMerger.merge(merged + [originalB]) == merged)
        #expect(SyncMerger.merge([originalA] + merged) == merged)
    }

    @Test func simultaneousDifferentRecordEditsAreBothKeptAndConverge() throws {
        let time = Date(timeIntervalSince1970: 100)
        let old = SyncRecord(key: "card:a", kind: "card", revision: time, deleted: false, payload: Data([0]))
        let editA = SyncRecord(key: "card:a", kind: "card", revision: time.addingTimeInterval(1), deleted: false, payload: Data([1]))
        let editB = SyncRecord(key: "card:b", kind: "card", revision: time.addingTimeInterval(2), deleted: false, payload: Data([2]))
        #expect(SyncMerger.merge([old, editA, editB]) == SyncMerger.merge([editB, editA, old]))
        #expect(SyncMerger.merge([old, editA, editB]).count == 2)
        let deletion = SyncRecord(key: "card:a", kind: "card", revision: editA.revision, deleted: true)
        #expect(SyncMerger.merge([editA, deletion]).first?.deleted == true)
        #expect(SyncMerger.merge([deletion, old, editA]).first?.deleted == true)
    }

    @Test func sameCatalogImportedOnBothDevicesDoesNotDuplicate() throws {
        let a = try Persistence.makeContainer(inMemory: true), b = try Persistence.makeContainer(inMemory: true)
        let cardA = try sample(a.mainContext), cardB = try sample(b.mainContext)
        #expect(cardA.id != cardB.id)
        let merged = SyncMerger.merge(try SyncStore.records(a.mainContext) + SyncStore.records(b.mainContext))
        _ = try SyncStore.apply(merged, context: a.mainContext)
        _ = try SyncStore.apply(merged, context: b.mainContext)
        #expect(try a.mainContext.fetchCount(FetchDescriptor<BankCard>()) == 1)
        #expect(try b.mainContext.fetchCount(FetchDescriptor<RewardRule>()) == 1)
        #expect(try SyncStore.records(a.mainContext) == SyncStore.records(b.mainContext))
    }

    @Test func freshCatalogCannotErasePersonalSettingsButExplicitClearSyncs() throws {
        let a = try Persistence.makeContainer(inMemory: true), b = try Persistence.makeContainer(inMemory: true)
        let cardA = try sample(a.mainContext), cardB = try sample(b.mainContext)
        let personal = CardDraft(card: cardA); personal.lastFour = "8123"; personal.statementDay = 12
        #expect(personal.save(in: a.mainContext))
        cardB.modifiedAt = Date.now.addingTimeInterval(1)
        let merged = SyncMerger.merge(try SyncStore.records(a.mainContext) + SyncStore.records(b.mainContext))
        _ = try SyncStore.apply(merged, context: b.mainContext)
        #expect(cardB.lastFour == "8123"); #expect(cardB.statementDay == 12)
        let clear = CardDraft(card: cardB); clear.lastFour = ""; clear.statementDay = 0
        #expect(clear.save(in: b.mainContext))
        _ = try SyncStore.apply(SyncStore.records(b.mainContext), context: a.mainContext)
        #expect(cardA.lastFour.isEmpty); #expect(cardA.statementDay == 0)
        let ruleA = try #require(cardA.rules.first), ruleB = try #require(cardB.rules.first)
        ruleA.kind = "welcome"; ruleA.thresholdCents = 300_000
        ruleB.kind = "welcome"; ruleB.thresholdCents = 300_000; ruleB.isEnabled = false
        let welcome = RuleDraft(rule: ruleA)
        welcome.startsOn = try CatalogImporter.date("2026-10-02")
        #expect(welcome.save(in: a.mainContext, cards: [cardA]))
        ruleB.modifiedAt = Date.now.addingTimeInterval(2)
        _ = try SyncStore.apply(SyncStore.records(a.mainContext), context: b.mainContext)
        #expect(ruleB.isEnabled)
        #expect(ruleB.startsOn == (try CatalogImporter.date("2026-10-02")))
    }

    @Test func corruptPeerAndDisappearingOwnFileCannotOverwriteValidSnapshot() async throws {
        let folder = try folder(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = try Persistence.makeContainer(inMemory: true)
        _ = try sample(store.mainContext)
        let engine = FolderSyncEngine(), device = UUID()
        _ = try await engine.publish(folder: folder, deviceID: device, records: SyncStore.records(store.mainContext))
        let directory = FolderSyncEngine.directory(in: folder)
        let own = directory.appending(path: device.uuidString + ".json")
        let before = try Data(contentsOf: own)
        let corrupt = directory.appending(path: UUID().uuidString + ".json")
        try Data("broken file".utf8).write(to: corrupt)
        var rejected = false
        do { _ = try await engine.read(folder: folder, deviceID: device, local: SyncStore.records(store.mainContext), previouslyPublished: true) }
        catch { rejected = true }
        #expect(rejected); #expect(try Data(contentsOf: own) == before)
        try FileManager.default.removeItem(at: corrupt)
        try FileManager.default.removeItem(at: own)
        rejected = false
        do { _ = try await engine.read(folder: folder, deviceID: device, local: [], previouslyPublished: true) }
        catch { rejected = true }
        #expect(rejected)
        #expect(try store.mainContext.fetchCount(FetchDescriptor<BankCard>()) == 1)
    }

    @Test func selectingSyncFolderItselfDoesNotNestItAndDevicesHaveSeparateFiles() async throws {
        let folder = try folder(); defer { try? FileManager.default.removeItem(at: folder) }
        let engine = FolderSyncEngine(), first = UUID(), second = UUID()
        _ = try await engine.publish(folder: folder, deviceID: first, records: [])
        let direct = FolderSyncEngine.directory(in: folder)
        _ = try await engine.publish(folder: direct, deviceID: second, records: [])
        #expect(!FileManager.default.fileExists(atPath: direct.appending(path: "CardPilotSync").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: direct.path).count == 2)
    }

    @Test func originalStoreMigratesWithoutLosingCardsRulesOrTransactions() throws {
        let folder = try folder(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "CardPilot.store")
        var originalID: UUID?
        do {
            let schema = Schema(versionedSchema: LegacySchemaV1.self)
            let config = ModelConfiguration("CardPilot", schema: schema, url: url, cloudKitDatabase: .none)
            let legacy = try ModelContainer(for: schema, configurations: config)
            let card = LegacySchemaV1.BankCard(bank: "Original", name: "Old Card", lastFour: "8123")
            legacy.mainContext.insert(card); originalID = card.id
            let rule = LegacySchemaV1.RewardRule(name: "Old Rule", card: card)
            legacy.mainContext.insert(rule)
            legacy.mainContext.insert(LegacySchemaV1.SpendTransaction(merchant: "Original purchase", amountCents: 9988, card: card))
            try legacy.mainContext.save()
        }
        let migrated = try Persistence.makeContainer(url: url)
        let card = try #require(migrated.mainContext.fetch(FetchDescriptor<BankCard>()).first)
        #expect(card.id == originalID); #expect(card.lastFour == "8123")
        #expect(card.rules.count == 1); #expect(card.transactions.first?.amountCents == 9988)
        #expect(try migrated.mainContext.fetchCount(FetchDescriptor<SyncTombstone>()) == 0)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "CardPilot Backups/Before Sync Upgrade/complete").path))
    }
}
