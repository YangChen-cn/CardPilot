import Foundation
import SwiftData

@MainActor enum SyncStore {
    static func records(_ context: ModelContext) throws -> [SyncRecord] {
        SyncMerger.merge(try rawRecords(context))
    }

    private static func rawRecords(_ context: ModelContext) throws -> [SyncRecord] {
        let encoder = SyncCodec.encoder()
        var records: [SyncRecord] = []
        let metadata = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<AppMetadata>()).map { ($0.key, $0.value) })
        for card in try context.fetch(FetchDescriptor<BankCard>()) {
            var value = CardSyncData(card)
            if let milliseconds = metadata["profile.modified." + card.syncKey].flatMap(Double.init) {
                value.profileRevision = Date(timeIntervalSince1970: milliseconds / 1000)
            } else if !card.lastFour.isEmpty || card.statementDay > 0 || card.paymentDay > 0 || card.isArchived {
                value.profileRevision = max(card.createdAt, card.modifiedAt)
            }
            records.append(SyncRecord(key: card.syncKey, kind: "card", revision: max(card.createdAt, card.modifiedAt),
                                      deleted: false, payload: try encoder.encode(value)))
        }
        for rule in try context.fetch(FetchDescriptor<RewardRule>()) where rule.card != nil {
            var value = RuleSyncData(rule)
            if let milliseconds = metadata["profile.modified." + rule.syncKey].flatMap(Double.init) {
                value.profileRevision = Date(timeIntervalSince1970: milliseconds / 1000)
            } else if rule.isWelcome && rule.isEnabled { value.profileRevision = rule.modifiedAt }
            records.append(SyncRecord(key: rule.syncKey, kind: "rule", revision: rule.modifiedAt,
                                      deleted: false, cardKey: rule.card?.syncKey, payload: try encoder.encode(value)))
        }
        for transaction in try context.fetch(FetchDescriptor<SpendTransaction>()) where transaction.card != nil {
            records.append(SyncRecord(key: transaction.syncKey, kind: "transaction", revision: max(transaction.createdAt, transaction.modifiedAt),
                                      deleted: false, cardKey: transaction.card?.syncKey, payload: try encoder.encode(TransactionSyncData(transaction))))
        }
        // Artwork source is a local projection of CardSyncData. Sending it as a
        // separate document would let its LWW winner disagree with the image.
        for document in try context.fetch(FetchDescriptor<DomainRecord>()) where document.kind != "cardArtwork" {
            let value = DocumentSyncData(key: document.key, kind: document.kind, content: document.content, isDeleted: document.isDeleted)
            records.append(SyncRecord(key: "document:" + document.key, kind: "document", revision: document.modifiedAt,
                                      deleted: false, payload: try encoder.encode(value)))
        }
        for deletion in try context.fetch(FetchDescriptor<SyncTombstone>()) {
            let kind = deletion.key.components(separatedBy: ":").first ?? ""
            records.append(SyncRecord(key: deletion.key, kind: kind, revision: deletion.deletedAt, deleted: true))
        }
        // A stale tombstone and a model may temporarily share a key. Coalesce their
        // ordinary LWW state without running domain projections yet.
        return Dictionary(records.map { ($0.key, $0) }, uniquingKeysWith: { lhs, rhs in
            if lhs.revisionMillis != rhs.revisionMillis { return lhs.revisionMillis > rhs.revisionMillis ? lhs : rhs }
            if lhs.deleted != rhs.deleted { return lhs.deleted ? lhs : rhs }
            return (lhs.payload ?? Data()).lexicographicallyPrecedes(rhs.payload ?? Data()) ? rhs : lhs
        }).values.sorted { $0.key < $1.key }
    }

    static func apply(_ incoming: [SyncRecord], context: ModelContext, saving: Bool = true) throws -> Bool {
        // Re-merge with fresh local changes after I/O; do not overwrite edits made while waiting for the cloud folder.
        // Compare against unprojected models. A local email/Wallet reconciliation also
        // needs to be applied when no remote record changed during this sync pass.
        let local = try rawRecords(context)
        let merged = SyncMerger.merge(local + incoming)
        guard merged != local else { return false }
        for record in merged { try SyncCodec.validate(record) }
        var cards = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<BankCard>()).map { ($0.syncKey, $0) })
        var rules = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<RewardRule>()).map { ($0.syncKey, $0) })
        var transactions = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<SpendTransaction>()).map { ($0.syncKey, $0) })
        let current = Dictionary(uniqueKeysWithValues: local.map { ($0.key, $0) })
        do {
            for record in merged where record.kind == "document" && !record.deleted && current[record.key] != record {
                let value = try SyncCodec.decoder().decode(DocumentSyncData.self, from: record.payload ?? Data())
                if let document = try DocumentStore.record(value.key, in: context) {
                    document.content = value.content; document.kind = value.kind
                    document.isDeleted = value.isDeleted; document.modifiedAt = record.revision
                } else {
                    context.insert(DomainRecord(key: value.key, kind: value.kind, content: value.content,
                                                modifiedAt: record.revision, isDeleted: value.isDeleted))
                }
            }
            for record in merged where record.kind == "card" && !record.deleted && current[record.key] != record {
                let value = try SyncCodec.decoder().decode(CardSyncData.self, from: record.payload ?? Data())
                let card = cards[record.key] ?? BankCard(bank: value.bank, name: value.name)
                if card.modelContext == nil { card.id = SyncIdentity.id(for: record.key); context.insert(card) }
                try value.apply(to: card); card.modifiedAt = record.revision; cards[record.key] = card
                if let date = value.profileRevision { try Persistence.setProfileRevision(cardKey: record.key, date: date, context: context) }
            }
            for record in merged where ["rule", "transaction"].contains(record.kind) && !record.deleted && current[record.key] != record {
                guard let cardKey = record.cardKey, let card = cards[cardKey],
                      !merged.contains(where: { $0.key == cardKey && $0.deleted }) else { continue }
                if record.kind == "rule" {
                    let value = try SyncCodec.decoder().decode(RuleSyncData.self, from: record.payload ?? Data())
                    let rule = rules[record.key] ?? RewardRule(name: value.name, card: card)
                    if rule.modelContext == nil { rule.id = SyncIdentity.id(for: record.key); context.insert(rule) }
                    value.apply(to: rule); rule.card = card; rule.modifiedAt = record.revision; rules[record.key] = rule
                    if let date = value.profileRevision { try Persistence.setProfileRevision(cardKey: record.key, date: date, context: context) }
                } else {
                    let value = try SyncCodec.decoder().decode(TransactionSyncData.self, from: record.payload ?? Data())
                    let transaction = transactions[record.key] ?? SpendTransaction(merchant: value.merchant, amountCents: value.amountCents, card: card)
                    if transaction.modelContext == nil { transaction.id = SyncIdentity.id(for: record.key); context.insert(transaction) }
                    value.apply(to: transaction); transaction.card = card; transaction.modifiedAt = record.revision
                    transactions[record.key] = transaction
                }
            }
            for record in merged where record.deleted {
                Persistence.markDeleted(key: record.key, context: context, now: record.revision)
                if record.kind == "card", let card = cards[record.key] {
                    try DocumentStore.remove(card.artworkStateKey, in: context)
                    context.delete(card)
                }
                if record.kind == "rule", let rule = rules[record.key] { context.delete(rule) }
                if record.kind == "transaction", let transaction = transactions[record.key] { context.delete(transaction) }
            }
            for rule in rules.values {
                if let state = try DocumentStore.load(RulePolicyState.self, key: RulePolicyStore.key(rule), in: context), let current = state.current {
                    current.apply(to: rule)
                }
            }
            for card in cards.values {
                if let value = try DocumentStore.load(CardPricing.self, key: "cardOverride:" + card.syncKey, in: context) {
                    card.baseRateBps = value.baseRateBps; card.foreignFeeBps = value.foreignFeeBps
                    card.overseasHKDFeeBps = value.overseasHKDFeeBps; card.excludesWallets = value.excludesWallets
                }
            }
            if saving { try context.save() }
            return true
        } catch { context.rollback(); throw error }
    }
}
