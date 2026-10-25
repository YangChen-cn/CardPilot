import Foundation
import SwiftData

/// One read for the documents used by this offer projection, shared by all
/// cards in it. It is deliberately short-lived: the next projection observes
/// edits, imports and sync updates without a separate invalidation mechanism.
@MainActor struct OfferProjectionDocuments {
    private let contents: [String: Data]

    init(cards: [BankCard], library: BankLibrary?, context: ModelContext) {
        var requested: Set<String> = []
        for card in cards {
            for rule in library?.product(id: card.catalogID)?.displayCatalog.rules ?? [] {
                requested.insert(OfferStateStore.key(cardKey: card.overlayKey, offerID: rule.id))
                requested.insert(OfferStateStore.legacyKey(cardID: card.id, offerID: rule.id))
            }
            for rule in card.rules {
                requested.insert(RulePolicyStore.key(rule))
                let offerID = rule.externalID.isEmpty ? rule.id.uuidString : rule.externalID
                requested.insert(OfferStateStore.key(cardKey: card.overlayKey, offerID: offerID))
                requested.insert(OfferStateStore.legacyKey(cardID: card.id, offerID: offerID))
            }
        }
        guard !requested.isEmpty else { contents = [:]; return }
        let keys = Array(requested)
        let descriptor = FetchDescriptor<DomainRecord>(predicate: #Predicate {
            keys.contains($0.key) && !$0.isDeleted
        })
        let records = (try? context.fetch(descriptor)) ?? []
        contents = Dictionary(records.map { ($0.key, $0.content) }, uniquingKeysWith: { first, _ in first })
    }

    func state(card: BankCard, offerID: String, legacy: RewardRule?) throws -> OfferPersonalState {
        if let saved: OfferPersonalState = try load(key: OfferStateStore.key(cardKey: card.overlayKey, offerID: offerID)) {
            return saved
        }
        if let old: OfferPersonalState = try load(key: OfferStateStore.legacyKey(cardID: card.id, offerID: offerID)) {
            return old
        }
        guard let legacy else { return OfferPersonalState() }
        let policy = policy(for: legacy)
        return OfferPersonalState(hidden: policy.archived || policy.isRetired, favorite: false,
                                  enrollment: .unknown, notes: policy.customized ? legacy.notes : "")
    }

    func policy(for rule: RewardRule) -> RulePolicyState {
        (try? load(key: RulePolicyStore.key(rule))) ?? RulePolicyState()
    }

    private func load<T: Decodable>(key: String) throws -> T? {
        guard let data = contents[key] else { return nil }
        return try SyncCodec.decoder().decode(T.self, from: data)
    }
}
