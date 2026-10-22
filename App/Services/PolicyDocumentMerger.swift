import Foundation

enum PolicyDocumentMerger {
    static func merge(winner: DocumentSyncData, loser: DocumentSyncData) -> DocumentSyncData {
        var output = winner
        if winner.kind == "policy", !winner.isDeleted, !loser.isDeleted,
           var state = try? SyncCodec.decoder().decode(RulePolicyState.self, from: winner.content),
           let old = try? SyncCodec.decoder().decode(RulePolicyState.self, from: loser.content) {
            var secondary = old
            if !state.customized && old.customized {
                let template = state
                state.pending = template.current; state.pendingExtras = template.extras
                state.current = old.current; state.currentSince = old.currentSince
                state.extras = old.extras; state.customized = true; state.archived = old.archived
                state.history = old.history
                secondary = template
            }
            var supplement = secondary.history
            if secondary.currentSince < state.currentSince, let current = secondary.current {
                supplement.append(RuleRevision(since: secondary.currentSince, until: state.currentSince,
                                               value: current, extras: secondary.extras))
            }
            // Preserve legacy archives as data only; no interval normalization or reward replay.
            var archive: [Data: RuleRevision] = [:]
            for revision in state.history + supplement {
                if let data = try? SyncCodec.encoder().encode(revision) { archive[data] = revision }
            }
            state.history = archive.keys.sorted { $0.lexicographicallyPrecedes($1) }.compactMap { archive[$0] }
            if let data = try? SyncCodec.encoder().encode(state) { output.content = data }
        }
        if winner.kind == "pricing", !winner.isDeleted, !loser.isDeleted,
           let current = try? SyncCodec.decoder().decode([PricingRevision].self, from: winner.content),
           let old = try? SyncCodec.decoder().decode([PricingRevision].self, from: loser.content) {
            var unique: [Data: PricingRevision] = [:]
            for item in current + old { if let data = try? SyncCodec.encoder().encode(item) { unique[data] = item } }
            if let data = try? SyncCodec.encoder().encode(unique.keys.sorted { $0.lexicographicallyPrecedes($1) }.compactMap { unique[$0] }) { output.content = data }
        }
        return output
    }
}
