import Foundation
import Observation
import SwiftData

@MainActor @Observable final class RuleDraft {
    var name = ""
    var kind = "cashback"
    var cardID: UUID?
    var rate = Decimal(0)
    var cap = Decimal(0)
    var period = "monthly"
    var periodKnown = false
    var threshold = Decimal(0)
    var bonus = Decimal(0)
    var category = ""
    var currency = ""
    var paymentMethod = ""
    var merchants = ""
    var startsOn = Date.now
    var endsOn = HKCalendar.calendar.date(byAdding: .month, value: 3, to: .now) ?? .now
    var notes = ""
    var sourceURL = ""
    var error: String?
    let existing: RewardRule?
    @ObservationIgnored private var initialValues: Values?

    init(rule: RewardRule?, cardID: UUID? = nil) {
        existing = rule; self.cardID = cardID
        defer { initialValues = values }
        guard let rule else { return }
        name = rule.name; kind = rule.kind; self.cardID = rule.card?.id
        rate = Decimal(rule.rateBps) / 100; cap = Decimal(rule.capCents) / 100; period = rule.capPeriod
        threshold = Decimal(rule.thresholdCents) / 100; bonus = Decimal(rule.bonusCents) / 100
        category = rule.category; currency = rule.currency; paymentMethod = rule.paymentMethod
        merchants = rule.merchantKeywords; startsOn = rule.startsOn; endsOn = rule.endsOn
        notes = rule.notes; sourceURL = rule.sourceURL
        periodKnown = !((try? RulePolicyStore.state(rule).extras.periodUnverified) ?? false)
    }

    func prepare(cards: [BankCard]) {
        guard existing == nil, cardID == nil else { return }
        cardID = cards.first(where: { !$0.isArchived })?.id
        initialValues?.cardID = cardID
    }

    var hasUnsavedChanges: Bool { initialValues != values }

    private var values: Values {
        Values(name: name, kind: kind, cardID: cardID, rate: rate, cap: cap, period: period,
               periodKnown: periodKnown, threshold: threshold, bonus: bonus, category: category,
               currency: currency, paymentMethod: paymentMethod, merchants: merchants,
               startsOn: startsOn, endsOn: endsOn, notes: notes, sourceURL: sourceURL)
    }

    private struct Values: Equatable {
        var name: String
        var kind: String
        var cardID: UUID?
        var rate: Decimal
        var cap: Decimal
        var period: String
        var periodKnown: Bool
        var threshold: Decimal
        var bonus: Decimal
        var category: String
        var currency: String
        var paymentMethod: String
        var merchants: String
        var startsOn: Date
        var endsOn: Date
        var notes: String
        var sourceURL: String
    }

    func save(in context: ModelContext, cards: [BankCard]) -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "请填写活动名称。"; return false }
        guard let card = cards.first(where: { $0.id == cardID }) else { error = "请选择银行卡。"; return false }
        guard existing == nil || existing?.card?.id == cardID else { error = "已有活动需保留原卡片归属。"; return false }
        guard HKCalendar.start(startsOn) <= HKCalendar.start(endsOn), !rate.isNaN, rate >= 0, rate <= 100,
              [cap, threshold, bonus].allSatisfy({ !$0.isNaN && $0 >= 0 && $0 <= Money.maxAmount }) else {
            error = "请检查有效期、比例及金额。"; return false
        }
        do {
            if !sourceURL.isEmpty { try CatalogImporter.validateHTTPS(sourceURL) }
            try Persistence.save(context) {
                let rule = existing ?? RewardRule(name: name, card: card)
                if existing == nil { context.insert(rule) }
                if existing == nil && kind == "welcome" { rule.isEnabled = false }
                var extras = (try? RulePolicyStore.state(rule).extras) ?? RuleExtras()
                extras.periodUnverified = !periodKnown
                rule.name = name; rule.kind = kind; rule.card = card
                rule.rateBps = Int(Money.cents(rate)); rule.capCents = Money.cents(cap); rule.capPeriod = period
                rule.thresholdCents = Money.cents(threshold); rule.bonusCents = Money.cents(bonus)
                rule.category = category; rule.currency = currency; rule.paymentMethod = PaymentMethod.canonical(paymentMethod)
                rule.merchantKeywords = merchants; rule.startsOn = HKCalendar.start(startsOn); rule.endsOn = HKCalendar.start(endsOn)
                rule.notes = notes; rule.sourceURL = sourceURL; rule.modifiedAt = .now; card.modifiedAt = .now
                // Legacy limits/history remain stored, but no longer drive reward simulation.
                try RulePolicyStore.edited(rule, extras: extras, context: context)
            }
            return true
        } catch { self.error = PilotError.message(error); return false }
    }
}
