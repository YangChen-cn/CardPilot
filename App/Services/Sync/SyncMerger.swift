import Foundation

enum SyncMerger {
    /// Latest edit wins per record, not per ledger. A deletion wins an exact timestamp tie.
    static func merge(_ records: [SyncRecord]) -> [SyncRecord] {
        var result: [String: SyncRecord] = [:]
        for record in records {
            guard let previous = result[record.key] else { result[record.key] = record; continue }
            var winner = precedes(previous, record) ? record : previous
            if winner.kind == "document", !winner.deleted,
               let value = try? SyncCodec.decoder().decode(DocumentSyncData.self, from: winner.payload ?? Data()),
               let other = try? SyncCodec.decoder().decode(DocumentSyncData.self, from: (precedes(previous, record) ? previous : record).payload ?? Data()) {
                var merged = PolicyDocumentMerger.merge(winner: value, loser: other)
                if value.kind == "mailEvidence", other.kind == "mailEvidence", !value.isDeleted, !other.isDeleted,
                   var receipt = try? SyncCodec.decoder().decode(MailEvidence.self, from: value.content),
                   let previousReceipt = try? SyncCodec.decoder().decode(MailEvidence.self, from: other.content),
                   receipt.transactionKey == previousReceipt.transactionKey {
                    receipt.aliases = Array(Set(receipt.aliases + previousReceipt.aliases)).sorted()
                    receipt.merchantAliases = Array(Set(receipt.merchantAliases + previousReceipt.merchantAliases)).sorted()
                    merged.content = (try? SyncCodec.encoder().encode(receipt)) ?? merged.content
                }
                winner.payload = try? SyncCodec.encoder().encode(merged)
            }
            if previous.kind == "card", !previous.deleted, !record.deleted,
               let oldPayload = previous.payload, let newPayload = record.payload,
               let old = try? SyncCodec.decoder().decode(CardSyncData.self, from: oldPayload),
               let new = try? SyncCodec.decoder().decode(CardSyncData.self, from: newPayload),
               var value = try? SyncCodec.decoder().decode(CardSyncData.self, from: winner.payload ?? Data()) {
                let oldTime = Int64(((old.profileRevision ?? Date.distantPast).timeIntervalSince1970 * 1000).rounded())
                let newTime = Int64(((new.profileRevision ?? Date.distantPast).timeIntervalSince1970 * 1000).rounded())
                let profile = oldTime == newTime ? (cardProfilePrecedes(old, new) ? new : old) : (oldTime > newTime ? old : new)
                value.lastFour = profile.lastFour; value.statementDay = profile.statementDay
                value.paymentDay = profile.paymentDay; value.isArchived = profile.isArchived
                value.artworkSource = profile.artworkSource ?? .catalog
                value.imageData = value.artworkSource == .custom ? profile.imageData : nil
                value.profileRevision = profile.profileRevision
                winner.payload = try? SyncCodec.encoder().encode(value)
            }
            if previous.kind == "rule", !previous.deleted, !record.deleted,
               let oldPayload = previous.payload, let newPayload = record.payload,
               let old = try? SyncCodec.decoder().decode(RuleSyncData.self, from: oldPayload),
               let new = try? SyncCodec.decoder().decode(RuleSyncData.self, from: newPayload),
               var value = try? SyncCodec.decoder().decode(RuleSyncData.self, from: winner.payload ?? Data()), value.kind == "welcome" {
                let oldTime = Int64(((old.profileRevision ?? Date.distantPast).timeIntervalSince1970 * 1000).rounded())
                let newTime = Int64(((new.profileRevision ?? Date.distantPast).timeIntervalSince1970 * 1000).rounded())
                let profile = oldTime == newTime ? (ruleProfilePrecedes(old, new) ? new : old) : (oldTime > newTime ? old : new)
                value.startsOn = profile.startsOn; value.endsOn = profile.endsOn; value.isEnabled = profile.isEnabled
                value.profileRevision = profile.profileRevision
                winner.payload = try? SyncCodec.encoder().encode(value)
            }
            result[record.key] = winner
        }
        // Project authoritative policy documents before comparing snapshots, so a fresh template
        // cannot cause the same manual setting to be overwritten and restored on every poll.
        for key in Array(result.keys) {
            guard var record = result[key], !record.deleted else { continue }
            if record.kind == "rule", let document = result["document:policy:" + key],
               let payload = try? SyncCodec.decoder().decode(DocumentSyncData.self, from: document.payload ?? Data()), !payload.isDeleted,
               let state = try? SyncCodec.decoder().decode(RulePolicyState.self, from: payload.content), var current = state.current {
                current.profileRevision = (try? SyncCodec.decoder().decode(RuleSyncData.self, from: record.payload ?? Data()))?.profileRevision
                record.payload = try? SyncCodec.encoder().encode(current)
                record.revision = max(record.revision, document.revision); result[key] = record
            }
            if record.kind == "card", let document = result["document:cardOverride:" + key],
               let payload = try? SyncCodec.decoder().decode(DocumentSyncData.self, from: document.payload ?? Data()), !payload.isDeleted,
               let override = try? SyncCodec.decoder().decode(CardPricing.self, from: payload.content),
               var current = try? SyncCodec.decoder().decode(CardSyncData.self, from: record.payload ?? Data()) {
                current.baseRateBps = override.baseRateBps; current.foreignFeeBps = override.foreignFeeBps
                current.overseasHKDFeeBps = override.overseasHKDFeeBps; current.excludesWallets = override.excludesWallets
                record.payload = try? SyncCodec.encoder().encode(current)
                record.revision = max(record.revision, document.revision); result[key] = record
            }
        }
        return MailReconciliation.project(result).values.sorted { $0.key < $1.key }
    }
    private static func precedes(_ lhs: SyncRecord, _ rhs: SyncRecord) -> Bool {
        if lhs.revisionMillis != rhs.revisionMillis { return lhs.revisionMillis < rhs.revisionMillis }
        if lhs.deleted != rhs.deleted { return !lhs.deleted }
        // Stable tie-breaking makes both devices converge even with identical clocks.
        return (lhs.payload ?? Data()).lexicographicallyPrecedes(rhs.payload ?? Data())
    }

    /// Public/catalog fields can come from a different revision. Comparing the
    /// whole payload here would change the tie-break after projecting a profile,
    /// letting an older image or personal setting win again on the next sync.
    private static func cardProfilePrecedes(_ lhs: CardSyncData, _ rhs: CardSyncData) -> Bool {
        let left = [lhs.lastFour, String(lhs.statementDay), String(lhs.paymentDay),
                    String(lhs.isArchived), (lhs.artworkSource ?? .catalog).rawValue]
        let right = [rhs.lastFour, String(rhs.statementDay), String(rhs.paymentDay),
                     String(rhs.isArchived), (rhs.artworkSource ?? .catalog).rawValue]
        if left != right { return left.lexicographicallyPrecedes(right) }
        let leftImage = lhs.artworkSource == .custom ? lhs.imageData ?? Data() : Data()
        let rightImage = rhs.artworkSource == .custom ? rhs.imageData ?? Data() : Data()
        return leftImage.lexicographicallyPrecedes(rightImage)
    }

    private static func ruleProfilePrecedes(_ lhs: RuleSyncData, _ rhs: RuleSyncData) -> Bool {
        if lhs.startsOn != rhs.startsOn { return lhs.startsOn < rhs.startsOn }
        if lhs.endsOn != rhs.endsOn { return lhs.endsOn < rhs.endsOn }
        return !lhs.isEnabled && rhs.isEnabled
    }
}
