import Foundation
import SwiftData

/// Current activity notes and import protection. Legacy history remains readable, but is never replayed.
@MainActor enum RulePolicyStore {
    static func key(_ rule: RewardRule) -> String { "policy:" + rule.syncKey }
    static func state(_ rule: RewardRule) throws -> RulePolicyState {
        guard let context = rule.modelContext else { return RulePolicyState() }
        return try DocumentStore.load(RulePolicyState.self, key: key(rule), in: context) ?? RulePolicyState()
    }

    static func imported(_ incoming: RuleSyncData, extras: RuleExtras, into rule: RewardRule, isNew: Bool,
                         context: ModelContext, now: Date = .now) throws {
        var state = try state(rule)
        if !isNew && (state.customized || state.baseline == nil || state.baseline != RuleSyncData(rule)) {
            state.customized = true; state.pending = incoming; state.pendingExtras = extras
        } else {
            incoming.apply(to: rule)
            state.current = incoming; state.extras = extras; state.baseline = incoming
            state.pending = nil; state.pendingExtras = nil; rule.modifiedAt = now
        }
        try DocumentStore.put(state, key: key(rule), kind: "policy", in: context, now: now)
    }

    static func edited(_ rule: RewardRule, extras: RuleExtras,
                       context: ModelContext, now: Date = .now) throws {
        var state = try state(rule)
        state.customized = true; state.extras = extras; state.current = RuleSyncData(rule)
        try DocumentStore.put(state, key: key(rule), kind: "policy", in: context, now: now)
    }

    static func archive(_ rule: RewardRule, context: ModelContext, now: Date = .now) throws {
        var state = try state(rule)
        state.archived = true; state.customized = true
        rule.isEnabled = false; rule.modifiedAt = now; state.current = RuleSyncData(rule)
        try DocumentStore.put(state, key: key(rule), kind: "policy", in: context, now: now)
    }

    /// An official activity absent from a complete remote snapshot is retired, not deleted.
    /// Personal welcome tracking remains available from the welcome center.
    static func retire(_ rule: RewardRule, context: ModelContext, now: Date = .now) throws {
        var state = try state(rule)
        guard !state.isRetired else { return }
        state.retired = true
        state.enabledBeforeRetirement = rule.isEnabled
        rule.isEnabled = false
        rule.modifiedAt = now
        state.current = RuleSyncData(rule)
        try DocumentStore.put(state, key: key(rule), kind: "policy", in: context, now: now)
    }

    /// A previously retired official activity reappeared in a newer snapshot.
    static func revive(_ rule: RewardRule, context: ModelContext, now: Date = .now) throws {
        var state = try state(rule)
        guard state.isRetired else { return }
        state.retired = false
        rule.isEnabled = state.enabledBeforeRetirement ?? rule.isEnabled
        state.enabledBeforeRetirement = nil
        rule.modifiedAt = now
        state.current = RuleSyncData(rule)
        try DocumentStore.put(state, key: key(rule), kind: "policy", in: context, now: now)
    }

    static func acceptPending(_ rule: RewardRule, context: ModelContext) throws {
        var state = try state(rule)
        guard var incoming = state.pending else { return }
        incoming.isEnabled = rule.isEnabled
        if rule.isWelcome { incoming.startsOn = rule.startsOn; incoming.endsOn = rule.endsOn }
        let extras = state.pendingExtras ?? state.extras
        state.customized = false; state.baseline = RuleSyncData(rule)
        try DocumentStore.put(state, key: key(rule), kind: "policy", in: context)
        try imported(incoming, extras: extras, into: rule, isNew: false, context: context)
    }
}
