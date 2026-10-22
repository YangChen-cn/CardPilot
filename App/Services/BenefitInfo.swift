import Foundation

enum BenefitGroup: String, CaseIterable, Identifiable {
    case daily, limited, merchant, welcome
    var id: Self { self }
    var title: String {
        switch self {
        case .daily: "日常权益"
        case .limited: "限时优惠"
        case .merchant: "指定商户"
        case .welcome: "迎新奖励"
        }
    }
}

enum BenefitOrigin: Equatable {
    case official
    case personal
    case historical
}

enum BenefitPeriodStatus: Equatable {
    case unknown
    case notStarted
    case active
    case ended

    var label: String {
        switch self {
        case .unknown: "有效期待核实"
        case .notStarted: "尚未开始"
        case .active: "进行中"
        case .ended: "已结束"
        }
    }
}

/// A readable projection of published terms. It deliberately contains no
/// transaction matching or reward replay. Official offers are built from the
/// read-only catalog cache; personal overlays are keyed by card instance + offer.
@MainActor struct BenefitInfo: Identifiable {
    let id: UUID
    let offerKey: String
    let cardID: UUID?
    let cardKey: String?
    let cardName: String
    let title: String
    let headline: String
    let conditions: [String]
    let group: BenefitGroup
    let startsOn: Date
    let endsOn: Date
    let sourceURL: String
    let verifiedOn: String
    let updatedAt: String?
    let isArchived: Bool
    let isHidden: Bool
    let isEnabled: Bool
    let hasKnownStart: Bool
    let hasKnownEnd: Bool
    let origin: BenefitOrigin
    let isUserAdded: Bool
    let isHistorical: Bool
    let personal: OfferPersonalState
    let trackingKey: String
    /// Stable offer identifier used by the personal overlay. Official and
    /// historical rules use the same value for reading and saving.
    let overlayOfferID: String
    let catalogRule: CatalogRule?
    let legacyRule: RewardRule?

    // Facts used by the recommendation filter. They come from the published
    // rule, never from transaction history.
    let category: String
    let currency: String
    let paymentMethod: String
    let merchantKeywords: String
    let channelCondition: String
    let thresholdCents: Int64
    let minimumCents: Int64
    let capCents: Int64
    let sharedCapGroup: String
    let extras: RuleExtras

    var terms: [BenefitTerm] {
        conditions.map { condition in
            guard let colon = condition.firstIndex(of: "：") else {
                return BenefitTerm(label: nil, value: condition)
            }
            let label = String(condition[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(condition[condition.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            return BenefitTerm(label: label.isEmpty ? nil : label, value: value)
        }
    }

    var labeledTerms: [BenefitTerm] { terms.filter { $0.label != nil } }
    var noteTerms: [BenefitTerm] { terms.filter { $0.label == nil } }
    var isWelcome: Bool { group == .welcome }
    var canEdit: Bool { origin == .personal }
    var canChangeHiddenState: Bool { origin == .official }

    var hasKnownPeriod: Bool { hasKnownStart && hasKnownEnd }

    /// A known end date is enough to decide that an offer has ended. A missing
    /// start date must never hide an expired offer.
    var isEnded: Bool {
        hasKnownEnd && endsOn < HKCalendar.start(.now)
    }

    var isNotStarted: Bool {
        hasKnownStart && startsOn > .now
    }

    var isActive: Bool { periodStatus == .active }

    var periodDescription: String {
        switch (hasKnownStart, hasKnownEnd) {
        case (true, true):
            return startsOn.formatted(.dateTime.year().month().day())
                + " – " + endsOn.formatted(.dateTime.year().month().day())
        case (true, false):
            return startsOn.formatted(.dateTime.year().month().day()) + " 起，结束日期未核实"
        case (false, true):
            return "结束日期 " + endsOn.formatted(.dateTime.year().month().day()) + "，开始日期未核实"
        case (false, false):
            return "活动有效期未核实"
        }
    }

    var periodStatus: BenefitPeriodStatus {
        if isEnded { return .ended }
        if isNotStarted { return .notStarted }
        if hasKnownStart { return .active }
        // A future end date with an unknown start date is not enough to say the
        // offer has started. Keep it as needing verification.
        return .unknown
    }

    /// Legacy initializer. Kept for personal rules and for reading old local
    /// records during migration. New official offers use `init(official:...)`.
    init(rule: RewardRule) {
        let policy = try? RulePolicyStore.state(rule)
        let extras = policy?.extras ?? RuleExtras()
        let cardID = rule.card?.id
        let cardKey = rule.card?.overlayKey
        let external = rule.externalID
        let offerID = external.isEmpty ? rule.id.uuidString : external
        offerKey = "\(cardKey ?? "none"):\(offerID)"
        id = external.isEmpty ? rule.id : SyncIdentity.id(for: "offer:" + offerKey)
        self.cardID = cardID; self.cardKey = cardKey; cardName = rule.card?.displayName ?? "未关联卡片"
        title = rule.name; startsOn = rule.startsOn; endsOn = rule.endsOn
        sourceURL = rule.sourceURL; verifiedOn = rule.verifiedOn; updatedAt = nil
        isArchived = (policy?.archived ?? false) || (policy?.isRetired ?? false)
        isHidden = false
        isEnabled = rule.isEnabled
        hasKnownStart = !extras.periodUnverified
        hasKnownEnd = !extras.periodUnverified
        origin = external.isEmpty ? .personal : .historical
        isUserAdded = external.isEmpty
        isHistorical = !external.isEmpty
        personal = OfferPersonalState(hidden: isArchived, favorite: false, enrollment: .unknown,
                                      notes: policy?.customized == true ? rule.notes : "")
        trackingKey = cardKey.map { OfferTrackingStore.key(cardKey: $0, offerID: offerID) }
            ?? "welcomeTracking:offer:none:\(offerID)"
        overlayOfferID = offerID
        catalogRule = nil; legacyRule = rule
        category = rule.category; currency = rule.currency; paymentMethod = rule.paymentMethod
        merchantKeywords = rule.merchantKeywords; channelCondition = rule.channelCondition
        thresholdCents = rule.thresholdCents; minimumCents = rule.minimumCents
        capCents = rule.capCents; sharedCapGroup = rule.sharedCapGroup; self.extras = extras
        group = Self.group(for: extras.benefitGroup, welcome: rule.isWelcome,
                           merchant: !rule.merchantKeywords.isEmpty, capPeriod: rule.capPeriod)
        if rule.isWelcome, extras.welcomeMode != "percentage", rule.bonusCents > 0 {
            headline = "奖励 " + Money.text(rule.bonusCents)
        } else if rule.rateBps > 0 {
            headline = Money.percent(rule.rateBps) + (extras.rateMode == "extra" ? " 额外回赠" : " 回赠")
        } else { headline = "查看适用权益与条件" }
        conditions = Self.conditions(category: rule.category, merchants: rule.merchantKeywords,
                                     currency: rule.currency, paymentMethod: rule.paymentMethod,
                                     extras: extras, channel: rule.channelCondition,
                                     threshold: rule.thresholdCents, minimum: rule.minimumCents,
                                     monthlyPhysical: rule.monthlyPhysicalThresholdCents,
                                     cap: rule.capCents, capPeriod: rule.capPeriod,
                                     sharedCapGroup: rule.sharedCapGroup, notes: rule.notes,
                                     sourceURL: rule.sourceURL, verifiedOn: rule.verifiedOn)
    }

    /// Official offers come from the bundled/read-only catalog cache. Personal
    /// state is an overlay and is never written into the catalog document.
    init(official rule: CatalogRule, product: CardProduct, card: BankCard, state: OfferPersonalState,
         updatedAt: String? = nil, historical: Bool = false) {
        let cardID = card.id
        let cardKey = card.overlayKey
        offerKey = "\(cardKey):\(rule.id)"
        id = SyncIdentity.id(for: "offer:" + offerKey)
        self.cardID = cardID; self.cardKey = cardKey; cardName = card.displayName
        title = rule.name
        sourceURL = rule.sourceURL; verifiedOn = product.catalog.verifiedOn; self.updatedAt = updatedAt
        let start = rule.startsOn.flatMap { try? CatalogImporter.date($0) }
        let end = rule.endsOn.flatMap { try? CatalogImporter.date($0) }
        startsOn = start ?? .distantPast; endsOn = end ?? .distantFuture
        hasKnownStart = start != nil
        hasKnownEnd = end != nil
        group = BenefitGroup(rawValue: rule.group ?? "") ?? .limited
        let extras = rule.calculation ?? RuleExtras()
        self.extras = extras
        category = rule.category ?? ""; currency = rule.currency ?? ""; paymentMethod = rule.paymentMethod ?? ""
        merchantKeywords = rule.merchantKeywords ?? ""; channelCondition = rule.channelCondition ?? "any"
        thresholdCents = Money.cents(rule.thresholdHKD ?? 0); minimumCents = Money.cents(rule.minimumHKD ?? 0)
        capCents = Money.cents(rule.capHKD ?? 0); sharedCapGroup = rule.sharedCapGroup ?? ""
        catalogRule = rule; legacyRule = nil
        personal = state
        isArchived = false; isHidden = state.hidden; isEnabled = true
        origin = historical ? .historical : .official; isUserAdded = false; isHistorical = historical
        trackingKey = OfferTrackingStore.key(cardKey: cardKey, offerID: rule.id)
        overlayOfferID = rule.id
        if group == .welcome, extras.welcomeMode != "percentage", let bonus = rule.bonusHKD, bonus > 0 {
            headline = "奖励 " + Money.text(Money.cents(bonus))
        } else if let rate = rule.ratePercent, rate > 0 {
            headline = Money.percent(Int(Money.cents(rate))) + (extras.rateMode == "extra" ? " 额外回赠" : " 回赠")
        } else { headline = "查看适用权益与条件" }
        var monthlyLocal = extras.monthlyLocalThresholdCents
        if let monthly = rule.monthlyPhysicalThresholdHKD { monthlyLocal = max(monthlyLocal, Money.cents(monthly)) }
        var items = Self.conditions(category: category, merchants: merchantKeywords, currency: currency,
                                    paymentMethod: paymentMethod, extras: extras, channel: channelCondition,
                                    threshold: thresholdCents, minimum: minimumCents,
                                    monthlyPhysical: monthlyLocal,
                                    cap: capCents, capPeriod: rule.capPeriod ?? "monthly",
                                    sharedCapGroup: sharedCapGroup, notes: rule.notes ?? "",
                                    sourceURL: sourceURL, verifiedOn: verifiedOn)
        if !hasKnownStart || !hasKnownEnd {
            items.insert("官方活动有效期尚未核实，请以银行最新条款为准。", at: 0)
        }
        conditions = items
    }

    private static func group(for explicit: String?, welcome: Bool, merchant: Bool, capPeriod: String) -> BenefitGroup {
        if let explicit, let value = BenefitGroup(rawValue: explicit) { return value }
        // Legacy local records only. Official records always carry an explicit
        // group and never use this fallback.
        if welcome { return .welcome }
        if merchant { return .merchant }
        // Old user-created records have no explicit group. Keep their historical
        // display behavior; official records always bypass this fallback.
        return capPeriod == "monthly" ? .daily : .limited
    }

    private static func conditions(category: String, merchants: String, currency: String, paymentMethod: String,
                                   extras: RuleExtras, channel: String, threshold: Int64, minimum: Int64,
                                   monthlyPhysical: Int64, cap: Int64, capPeriod: String, sharedCapGroup: String,
                                   notes: String, sourceURL: String, verifiedOn: String) -> [String] {
        var items: [String] = []
        if !category.isEmpty { items.append("适用类别：" + category) }
        if !merchants.isEmpty { items.append("指定商户：" + merchants) }
        if !currency.isEmpty { items.append("交易币种：" + currency) }
        let methods = Array(Set((extras.paymentMethods + (paymentMethod.isEmpty ? [] : [paymentMethod])).map(PaymentMethod.canonical).filter { !$0.isEmpty })).sorted()
        if !methods.isEmpty { items.append("指定支付方式：" + methods.joined(separator: "、")) }
        let excludedMethods = Array(Set(extras.excludedPaymentMethods.map(PaymentMethod.canonical).filter { !$0.isEmpty })).sorted()
        if !excludedMethods.isEmpty { items.append("不适用：" + excludedMethods.joined(separator: "、")) }
        if !extras.regions.isEmpty {
            let names = extras.regions.map { ["HK": "香港", "CN": "中国内地", "MO": "澳门", "other": "其他地区"][$0] ?? $0 }
            items.append("适用地区：" + names.joined(separator: "、"))
        }
        let channelText: String? = switch channel {
        case "physical": "实体商户消费"
        case "online": "网上消费"
        case "overseasForeign": "境外外币消费"
        case "onlineOrOverseasForeign": "网上或境外外币消费"
        default: nil
        }
        if let channelText { items.append("消费渠道：" + channelText) }
        if threshold > 0 { items.append("消费门槛：" + Money.text(threshold)) }
        if minimum > 0 { items.append("单笔最低消费：" + Money.text(minimum)) }
        if monthlyPhysical > 0 { items.append("当月实体消费须满 " + Money.text(monthlyPhysical)) }
        if cap > 0 { items.append((capPeriod == "monthly" ? "每月" : "整期") + "回赠上限 " + Money.text(cap)) }
        if extras.perTransactionCapCents > 0 { items.append("每笔回赠上限 " + Money.text(extras.perTransactionCapCents)) }
        if !sharedCapGroup.isEmpty { items.append("与其他指定优惠共享上限，使用情况请向银行核实。") }
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { items.append(notes) }
        if sourceURL.isEmpty || verifiedOn.isEmpty { items.append("资料待核实，请以银行最新公布为准。") }
        return items
    }
}

/// A term from a published offer. `label == nil` means a free-form note.
struct BenefitTerm: Identifiable, Hashable {
    let label: String?
    let value: String
    var id: String { (label ?? "_note") + "|" + value }

    private static let chipLabels: Set<String> = ["指定商户", "适用类别", "指定支付方式", "不适用", "适用地区"]

    var isChipList: Bool {
        guard let label else { return false }
        return Self.chipLabels.contains(label)
    }

    var chips: [String] {
        guard isChipList else { return [] }
        return value
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "、" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
