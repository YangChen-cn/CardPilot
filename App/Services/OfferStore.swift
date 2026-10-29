import Foundation
import SwiftData

enum OfferEnrollment: String, Codable, CaseIterable, Sendable {
    case unknown, notRegistered, registered

    var label: String {
        switch self {
        case .unknown: "需要确认是否已登记"
        case .notRegistered: "用户确认未登记"
        case .registered: "用户确认已登记"
        }
    }
}

/// Personal settings for one published offer. The key includes the card
/// instance, so two cards of the same product never share this state.
struct OfferPersonalState: Codable, Equatable, Sendable {
    var hidden = false
    var favorite = false
    var enrollment: OfferEnrollment = .unknown
    var notes = ""
}

@MainActor enum OfferStateStore {
    /// Stable card identity is based on syncKey, not the device-local UUID.
    static func key(cardKey: String, offerID: String) -> String {
        "offerState:\(cardKey):\(offerID)"
    }

    /// Old records used the device-local UUID. They are read during migration
    /// and never rewritten or deleted.
    static func legacyKey(cardID: UUID, offerID: String) -> String {
        "offerState:\(cardID.uuidString):\(offerID)"
    }

    static func load(cardKey: String, cardID: UUID?, offerID: String, legacy: RewardRule?,
                     in context: ModelContext) throws -> OfferPersonalState {
        let key = key(cardKey: cardKey, offerID: offerID)
        if let saved = try DocumentStore.load(OfferPersonalState.self, key: key, in: context) { return saved }
        if let cardID,
           let old = try DocumentStore.load(OfferPersonalState.self, key: legacyKey(cardID: cardID, offerID: offerID), in: context) {
            return old
        }
        guard let legacy else { return OfferPersonalState() }
        let policy = (try? RulePolicyStore.state(legacy)) ?? RulePolicyState()
        return OfferPersonalState(hidden: policy.archived,
                                  favorite: false,
                                  enrollment: .unknown,
                                  notes: policy.customized ? legacy.notes : "")
    }

    static func save(_ state: OfferPersonalState, cardKey: String, offerID: String, in context: ModelContext) throws {
        guard state.notes.count <= 10_000 else { throw PilotError.invalid("个人备注过长。") }
        try Persistence.save(context) {
            try DocumentStore.put(state, key: key(cardKey: cardKey, offerID: offerID), kind: "offerState", in: context)
        }
    }

    static func setHidden(_ hidden: Bool, cardKey: String, cardID: UUID?, offerID: String,
                          legacy: RewardRule?, in context: ModelContext) throws {
        var state = try load(cardKey: cardKey, cardID: cardID, offerID: offerID, legacy: legacy, in: context)
        state.hidden = hidden
        try save(state, cardKey: cardKey, offerID: offerID, in: context)
    }

    static func setFavorite(_ favorite: Bool, cardKey: String, cardID: UUID?, offerID: String,
                            legacy: RewardRule?, in context: ModelContext) throws {
        var state = try load(cardKey: cardKey, cardID: cardID, offerID: offerID, legacy: legacy, in: context)
        state.favorite = favorite
        try save(state, cardKey: cardKey, offerID: offerID, in: context)
    }

    @discardableResult
    static func setEnrollment(_ enrollment: OfferEnrollment, cardKey: String, cardID: UUID?, offerID: String,
                              legacy: RewardRule?, in context: ModelContext) throws -> OfferPersonalState {
        var state = try load(cardKey: cardKey, cardID: cardID, offerID: offerID, legacy: legacy, in: context)
        guard state.enrollment != enrollment else { return state }
        state.enrollment = enrollment
        try save(state, cardKey: cardKey, offerID: offerID, in: context)
        return state
    }
}

@MainActor enum OfferTrackingStore {
    static func key(cardKey: String, offerID: String) -> String {
        "welcomeTracking:offer:\(cardKey):\(offerID)"
    }

    static func legacyKey(cardID: UUID, offerID: String) -> String {
        "welcomeTracking:offer:\(cardID.uuidString):\(offerID)"
    }

    static func load(for info: BenefitInfo, context: ModelContext) throws -> WelcomeTracking {
        if info.origin == .personal, let rule = info.legacyRule {
            return try WelcomeTrackingStore.load(rule: rule, context: context)
        }
        if let saved = try DocumentStore.load(WelcomeTracking.self, key: info.trackingKey, in: context) {
            return saved
        }
        // Read-only migration from the old device-local UUID key.
        if let cardID = info.cardID, let offerID = info.catalogRule?.id,
           let old = try? DocumentStore.load(WelcomeTracking.self,
                                             key: legacyKey(cardID: cardID, offerID: offerID), in: context) {
            return old
        }
        // Read-only migration from the legacy rule-keyed record. It is never
        // rewritten or deleted, so old clients keep working.
        if let cardID = info.cardID, let external = info.catalogRule?.id,
           let legacy = info.legacyRule ?? legacyRule(cardID: cardID, externalID: external, context: context),
           let old = try? WelcomeTrackingStore.load(rule: legacy, context: context) {
            return old
        }
        let deadline = info.hasKnownEnd ? info.endsOn : .now
        return WelcomeTracking(status: .unconfirmed, applicationDate: nil, issueDate: nil,
                               deadline: deadline, thresholdCents: info.thresholdCents,
                               rewardContent: info.headline, notes: info.personal.notes,
                               receivedOn: nil, deadlineConfirmed: false)
    }

    /// Unlike `load`, this does not manufacture a default unconfirmed record.
    /// It is used only when showing the user's history for archived cards.
    static func hasPersonalRecord(for info: BenefitInfo, context: ModelContext) throws -> Bool {
        guard info.isWelcome else { return false }
        if info.origin == .personal, info.legacyRule != nil { return true }
        if !info.personal.notes.isEmpty { return true }
        // Presence, not successful decoding, controls visibility: a damaged
        // record must remain reachable so the UI can report its read error.
        func exists(_ key: String) throws -> Bool {
            guard let record = try DocumentStore.record(key, in: context) else { return false }
            return !record.isDeleted
        }
        if try exists(info.trackingKey) { return true }
        if let cardID = info.cardID,
           try exists(legacyKey(cardID: cardID, offerID: info.overlayOfferID)) { return true }
        guard let cardID = info.cardID,
              let legacy = info.legacyRule ?? legacyRule(cardID: cardID, externalID: info.overlayOfferID, context: context)
        else { return false }
        if legacy.isEnabled { return true }
        if try exists(WelcomeTrackingStore.key(legacy)) { return true }
        if try exists("welcome:" + legacy.syncKey) { return true }
        guard let card = legacy.card,
              let record = try DocumentStore.record("personalCard:" + card.syncKey, in: context), !record.isDeleted
        else { return false }
        guard let profile = try? SyncCodec.decoder().decode(PersonalCardProfile.self, from: record.content) else { return true }
        return profile.welcomePlanID == legacy.externalID || profile.welcomeRuleIDs.contains(legacy.externalID)
            || (profile.addons?.contains { $0.ruleIDs.contains(legacy.externalID) || $0.planID == legacy.externalID } ?? false)
    }

    static func save(_ value: WelcomeTracking, for info: BenefitInfo, context: ModelContext) throws {
        if info.origin == .personal, let rule = info.legacyRule {
            try WelcomeTrackingStore.save(value, rule: rule, context: context)
            return
        }
        guard info.isWelcome, let cardKey = info.cardKey,
              (0...10_000_000_000).contains(value.thresholdCents),
              value.rewardContent.count <= 2000, value.notes.count <= 10_000 else {
            throw PilotError.invalid("请检查迎新目标和备注。")
        }
        let offerID = info.overlayOfferID
        try Persistence.save(context) {
            try DocumentStore.put(value, key: key(cardKey: cardKey, offerID: offerID),
                                  kind: "welcomeTrackingOffer", in: context)
        }
    }

    private static func legacyRule(cardID: UUID, externalID: String, context: ModelContext) -> RewardRule? {
        let descriptor = FetchDescriptor<RewardRule>(predicate: #Predicate {
            $0.externalID == externalID && $0.card?.id == cardID
        })
        return try? context.fetch(descriptor).first
    }
}

/// One-time, idempotent upgrade of personal overlay keys. It only adds new
/// records; old UUID-keyed records remain as history and are never deleted.
@MainActor enum OfferMigration {
    static func migrateLegacy(in context: ModelContext) throws {
        let cards = (try? context.fetch(FetchDescriptor<BankCard>())) ?? []
        let cardsByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        var states: [(String, OfferPersonalState)] = []
        var trackings: [(String, WelcomeTracking)] = []
        var seenStateKeys: Set<String> = []
        var seenTrackingKeys: Set<String> = []

        // Upgrade documents written by earlier builds, which keyed personal
        // overlays by the device-local BankCard UUID. The new key is based on
        // the synced card identity, so the same card can read it on any device.
        let records = (try? context.fetch(FetchDescriptor<DomainRecord>())) ?? []
        for record in records where !record.isDeleted {
            if record.kind == "offerState",
               let (cardID, offerID) = legacyOverlayComponents(record.key, prefix: "offerState:"),
               let card = cardsByID[cardID] {
                let newKey = OfferStateStore.key(cardKey: card.overlayKey, offerID: offerID)
                guard !seenStateKeys.contains(newKey),
                      (try? DocumentStore.record(newKey, in: context)) == nil,
                      let value = try? DocumentStore.load(OfferPersonalState.self, key: record.key, in: context)
                else { continue }
                seenStateKeys.insert(newKey)
                states.append((newKey, value))
            } else if record.kind == "welcomeTrackingOffer",
                      let (cardID, offerID) = legacyOverlayComponents(record.key, prefix: "welcomeTracking:offer:"),
                      let card = cardsByID[cardID] {
                let newKey = OfferTrackingStore.key(cardKey: card.overlayKey, offerID: offerID)
                guard !seenTrackingKeys.contains(newKey),
                      (try? DocumentStore.record(newKey, in: context)) == nil,
                      let value = try? DocumentStore.load(WelcomeTracking.self, key: record.key, in: context)
                else { continue }
                seenTrackingKeys.insert(newKey)
                trackings.append((newKey, value))
            }
        }

        // Older builds also kept welcome progress under the legacy rule key.
        for card in cards {
            for rule in card.rules where !rule.externalID.isEmpty {
                let offerID = rule.externalID
                let newStateKey = OfferStateStore.key(cardKey: card.overlayKey, offerID: offerID)
                if !seenStateKeys.contains(newStateKey),
                   (try? DocumentStore.record(newStateKey, in: context)) == nil,
                   let policy = try? RulePolicyStore.state(rule),
                   policy.archived || policy.isRetired || policy.customized {
                    seenStateKeys.insert(newStateKey)
                    states.append((newStateKey, OfferPersonalState(hidden: policy.archived,
                                                                   favorite: false, enrollment: .unknown,
                                                                   notes: policy.customized ? rule.notes : "")))
                }
                let newTrackingKey = OfferTrackingStore.key(cardKey: card.overlayKey, offerID: offerID)
                if !seenTrackingKeys.contains(newTrackingKey),
                   (try? DocumentStore.record(newTrackingKey, in: context)) == nil,
                   let old = try? WelcomeTrackingStore.load(rule: rule, context: context) {
                    seenTrackingKeys.insert(newTrackingKey)
                    trackings.append((newTrackingKey, old))
                }
            }
        }

        guard !states.isEmpty || !trackings.isEmpty else { return }
        try Persistence.save(context) {
            for (key, state) in states {
                try DocumentStore.put(state, key: key, kind: "offerState", in: context)
            }
            for (key, tracking) in trackings {
                try DocumentStore.put(tracking, key: key, kind: "welcomeTrackingOffer", in: context)
            }
        }
    }

    private static func legacyOverlayComponents(_ key: String, prefix: String) -> (UUID, String)? {
        guard key.hasPrefix(prefix) else { return nil }
        let rest = key.dropFirst(prefix.count)
        guard let separator = rest.firstIndex(of: ":") else { return nil }
        let idText = rest[..<separator]
        let offerID = String(rest[rest.index(after: separator)...])
        guard !offerID.isEmpty, let cardID = UUID(uuidString: String(idText)) else { return nil }
        return (cardID, offerID)
    }
}

@MainActor enum OfferStore {
    static func offers(context: ModelContext, includeArchivedCards: Bool = false) -> [BenefitInfo] {
        let cards = ((try? context.fetch(FetchDescriptor<BankCard>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
            .filter { includeArchivedCards || !$0.isArchived }
        let library = try? BankLibrary.load()
        let documents = OfferProjectionDocuments(cards: cards, library: library, context: context)
        return cards.flatMap { card in
            let projected = offers(for: card, library: library, documents: documents,
                                   includeArchivedCards: includeArchivedCards)
            guard card.isArchived else { return projected }
            return projected.filter { (try? OfferTrackingStore.hasPersonalRecord(for: $0, context: context)) == true }
        }
    }

    static func offers(for card: BankCard, context: ModelContext, includeArchivedCards: Bool = false) -> [BenefitInfo] {
        guard includeArchivedCards || !card.isArchived else { return [] }
        let library = try? BankLibrary.load()
        let documents = OfferProjectionDocuments(cards: [card], library: library, context: context)
        let projected = offers(for: card, library: library, documents: documents, includeArchivedCards: includeArchivedCards)
        guard card.isArchived else { return projected }
        return projected.filter { (try? OfferTrackingStore.hasPersonalRecord(for: $0, context: context)) == true }
    }

    /// Current official offers are pure projections of the read-only catalog.
    /// Legacy rules are used only for user-created offers, migration and history.
    private static func offers(for card: BankCard, library: BankLibrary?, documents: OfferProjectionDocuments,
                               includeArchivedCards: Bool) -> [BenefitInfo] {
        guard includeArchivedCards || !card.isArchived else { return [] }
        let product = library?.product(id: card.catalogID)
        let isCurrentProduct = library?.products.contains { $0.id == card.catalogID } ?? false
        var result: [BenefitInfo] = []
        let officialRules = product?.displayCatalog.rules ?? []
        let officialIDs = Set(officialRules.map(\.id))

        for rule in officialRules {
            let legacy = card.rules.first { $0.externalID == rule.id }
            let state = (try? documents.state(card: card, offerID: rule.id, legacy: legacy)) ?? OfferPersonalState()
            result.append(BenefitInfo(official: rule, product: product!, card: card, state: state,
                                      historical: !isCurrentProduct))
        }

        for rule in card.rules {
            let shouldInclude = rule.externalID.isEmpty
                || (product != nil && !officialIDs.contains(rule.externalID))
                || product == nil
            guard shouldInclude else { continue }
            var info = BenefitInfo(rule: rule, policy: documents.policy(for: rule))
            if info.cardKey != nil,
               let state = try? documents.state(card: card, offerID: info.overlayOfferID, legacy: rule) {
                info.personal = state
            }
            result.append(info)
        }
        return result.sorted { lhs, rhs in
            if lhs.isWelcome != rhs.isWelcome { return lhs.isWelcome && !rhs.isWelcome }
            if lhs.isHistorical != rhs.isHistorical { return !lhs.isHistorical && rhs.isHistorical }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}
