import Foundation
import SwiftData
import ImageIO

enum CatalogImporter {
    static func optionalDate(_ text: String?) throws -> Date? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try date(text)
    }

    static func date(_ text: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = HKCalendar.calendar
        formatter.timeZone = HKCalendar.calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard text.count == 10, let value = formatter.date(from: text), formatter.string(from: value) == text else {
            throw PilotError.invalid("日期必须为有效的 YYYY-MM-DD：\(text)")
        }
        return value
    }

    static func decode(_ data: Data) throws -> CatalogPackage {
        guard data.count <= 20_000_000 else { throw PilotError.invalid("导入文件不能超过 20 MB。") }
        try rejectUnknownFields(data)
        let package = try JSONDecoder().decode(CatalogPackage.self, from: data)
        guard package.schemaVersion == 1, !package.cards.isEmpty, package.cards.count <= 100 else {
            throw PilotError.invalid("需要 schemaVersion: 1，及 1–100 张卡片。")
        }
        guard Set(package.cards.map(\.id)).count == package.cards.count else { throw PilotError.invalid("卡片 id 重复。") }
        for card in package.cards {
            guard !card.id.isEmpty, !card.bank.isEmpty, !card.name.isEmpty,
                  ["Visa", "Mastercard", "UnionPay", "American Express", "其他"].contains(card.network) else {
                throw PilotError.invalid("卡片名称、银行、id 或卡组织无效。")
            }
            try validateHTTPS(card.sourceURL); _ = try date(card.verifiedOn)
            if let url = card.imageURL { try validateHTTPS(url) }
            try validatePercent(card.baseRatePercent); try validatePercent(card.foreignFeePercent)
            try validatePercent(card.overseasHKDFeePercent)
            if let terms = card.calculation {
                guard terms.cnyFeeBps.map({ (0...10_000).contains($0) }) ?? true,
                      terms.baseRewardBasis.map({ ["hkd", "faceValue"].contains($0) }) ?? true,
                      terms.baseCapPeriod.map({ ["monthly", "statement"].contains($0) }) ?? true,
                      terms.cnyFeeRegions.map({ !$0.isEmpty && $0.allSatisfy { ["HK", "CN", "MO", "other"].contains($0) } }) ?? true else { throw PilotError.invalid("基础回赠或双币卡手续费设置无效。") }
            }
            if let base64 = card.imageBase64 {
                guard let image = Data(base64Encoded: base64) else { throw PilotError.invalid("卡面 Base64 无效。") }
                try validateImage(image)
            }
            guard card.rules.count <= 100, Set(card.rules.map(\.id)).count == card.rules.count else {
                throw PilotError.invalid("活动 id 重复或活动数量超过 100。")
            }
            for rule in card.rules {
                let group = rule.group ?? (rule.kind == "welcome" ? "welcome" : nil)
                guard !rule.id.isEmpty, !rule.name.isEmpty, ["cashback", "welcome"].contains(rule.kind),
                      ["monthly", "campaign"].contains(rule.capPeriod ?? "monthly"),
                      ["any", "physical", "online", "overseasForeign", "onlineOrOverseasForeign"].contains(rule.channelCondition ?? "any") else {
                    throw PilotError.invalid("\(rule.name)：活动类型、分类、上限周期或消费渠道无效。")
                }
                if let group, !["daily", "limited", "merchant", "welcome"].contains(group) {
                    throw PilotError.invalid("\(rule.name)：活动分类必须是 daily、limited、merchant 或 welcome。")
                }
                if let start = rule.startsOn, let end = rule.endsOn, try date(start) > date(end) {
                    throw PilotError.invalid("\(rule.name)：活动开始日期晚于结束日期。")
                }
                _ = try optionalDate(rule.startsOn); _ = try optionalDate(rule.endsOn)
                try validateHTTPS(rule.sourceURL); try validatePercent(rule.ratePercent)
                for amount in [rule.capHKD, rule.thresholdHKD, rule.bonusHKD, rule.minimumHKD, rule.monthlyPhysicalThresholdHKD] {
                    if let amount, amount < 0 || amount > Money.maxAmount { throw PilotError.invalid("金额必须在 0–100,000,000 之间。") }
                }
                if let c = rule.currency, !c.isEmpty, !Currency.allCases.map(\.rawValue).contains(c) { throw PilotError.invalid("不支持币种 \(c)。") }
                if let c = rule.category, !c.isEmpty, !SpendCategory.allCases.map(\.rawValue).contains(c) { throw PilotError.invalid("不支持分类 \(c)。") }
            }
            for rule in card.rules {
                if let extras = rule.calculation {
                    guard [extras.perTransactionCapCents, extras.minimumOriginalCents, extras.monthlyLocalThresholdCents].allSatisfy({ (0...10_000_000_000).contains($0) }),
                          ["total", "extra"].contains(extras.rateMode), ["any", "foreign"].contains(extras.currencyCondition),
                          ["fixed", "percentage"].contains(extras.welcomeMode),
                          ["hkd", "faceValue"].contains(extras.rewardBasis), extras.regions.allSatisfy({ ["HK", "CN", "MO", "other"].contains($0) }),
                          !extras.capIncludesBase || (extras.stackingGroup.isEmpty && extras.rateMode == "total"),
                          extras.excludedCategories.allSatisfy({ SpendCategory(rawValue: $0) != nil }) else {
                        throw PilotError.invalid("活动的叠加方式、原币门槛或单笔上限无效。")
                    }
                }
            }
            let grouped = Dictionary(grouping: card.rules.filter { !($0.sharedCapGroup ?? "").isEmpty }, by: {
                ($0.sharedCapGroup ?? "") + ":" + (($0.calculation?.capScope.isEmpty == false ? $0.calculation?.capScope : nil) ?? (($0.startsOn ?? "") + ":" + ($0.endsOn ?? "")))
            })
            for rules in grouped.values {
                guard let first = rules.first else { continue }
                guard rules.allSatisfy({ $0.capHKD == first.capHKD && ($0.capPeriod ?? "monthly") == (first.capPeriod ?? "monthly") }) else {
                    throw PilotError.invalid("同一共享上限组必须使用相同上限金额及周期。")
                }
            }
        }
        return package
    }

    private static func validatePercent(_ value: Decimal?) throws {
        if let value, value < 0 || value > 100 { throw PilotError.invalid("百分比必须在 0–100 之间。") }
    }

    private static func rejectUnknownFields(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PilotError.invalid("JSON根节点必须为对象。") }
        func check(_ object: [String: Any], allowed: Set<String>) throws {
            let unknown = Set(object.keys).subtracting(allowed)
            if !unknown.isEmpty { throw PilotError.invalid("不支持的字段：\(unknown.sorted().joined(separator: ", "))。请按JSON v1协议填写，复杂条件写入notes并停用规则。") }
        }
        try check(root, allowed: ["schemaVersion", "cards"])
        let cardKeys: Set<String> = ["id", "bank", "name", "network", "sourceURL", "verifiedOn", "kind", "baseRatePercent", "foreignFeePercent", "overseasHKDFeePercent", "excludesWallets", "annualFeeNote", "caveats", "imageURL", "imageBase64", "rules", "calculation"]
        let ruleKeys: Set<String> = ["id", "name", "kind", "group", "startsOn", "endsOn", "sourceURL", "ratePercent", "capHKD", "capPeriod", "sharedCapGroup", "thresholdHKD", "bonusHKD", "minimumHKD", "monthlyPhysicalThresholdHKD", "channelCondition", "category", "currency", "paymentMethod", "merchantKeywords", "requiresPersonalDates", "enabled", "notes", "calculation"]
        for card in root["cards"] as? [[String: Any]] ?? [] {
            try check(card, allowed: cardKeys)
            if let terms = card["calculation"] as? [String: Any] { try check(terms, allowed: ["cnyFeeBps", "baseRewardBasis", "baseCapUsesCreditLimit", "baseCapPeriod", "cnyFeeRegions"]) }
            for rule in card["rules"] as? [[String: Any]] ?? [] {
                try check(rule, allowed: ruleKeys)
                if let extras = rule["calculation"] as? [String: Any] {
                    try check(extras, allowed: ["perTransactionCapCents", "minimumOriginalCents", "monthlyLocalThresholdCents", "stackingGroup", "rateMode", "capScope", "currencyCondition", "excludedCategories", "excludedPaymentMethods", "paymentMethods", "regions", "rewardBasis", "capIncludesBase", "welcomeMode", "periodUnverified"])
                }
            }
        }
    }

    static func validateHTTPS(_ text: String) throws {
        guard let url = URL(string: text), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { throw PilotError.invalid("来源和图片地址必须是 HTTPS URL。") }
    }

    static func validateImage(_ data: Data) throws {
        guard data.count <= 8_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8000, height <= 8000 else {
            throw PilotError.invalid("卡面必须是有效图片，大小不超过 8 MB，边长不超过 8000 像素。")
        }
    }

    @MainActor static func apply(_ package: CatalogPackage, context: ModelContext, images: [String: Data] = [:], commit: Bool = true) throws {
        // Validate again so all callers share the same atomic boundary.
        _ = try decode(JSONEncoder().encode(package))
        let cards = try context.fetch(FetchDescriptor<BankCard>())
        do {
            for incoming in package.cards {
                let card = cards.first(where: { $0.catalogID == incoming.id }) ?? BankCard(bank: incoming.bank, name: incoming.name)
                let wasNew = card.modelContext == nil
                if card.modelContext == nil { context.insert(card); card.statementDay = 0; card.paymentDay = 0 }
                card.catalogID = incoming.id
                // Display identity and artwork may have been customized. Official updates
                // refresh terms without replacing the user's card presentation.
                if wasNew {
                    card.bank = incoming.bank; card.name = incoming.name
                    card.network = incoming.network; card.kind = incoming.kind ?? "信用卡"
                    card.theme = "purple"
                }
                card.baseRateBps = Int(Money.cents(incoming.baseRatePercent ?? 0))
                card.foreignFeeBps = Int(Money.cents(incoming.foreignFeePercent ?? 0))
                card.overseasHKDFeeBps = Int(Money.cents(incoming.overseasHKDFeePercent ?? 0))
                card.excludesWallets = incoming.excludesWallets ?? false
                var terms = incoming.calculation
                if let override = try DocumentStore.load(CardPricing.self, key: "cardOverride:" + card.syncKey, in: context) {
                    card.baseRateBps = override.baseRateBps; card.foreignFeeBps = override.foreignFeeBps
                    card.overseasHKDFeeBps = override.overseasHKDFeeBps; card.excludesWallets = override.excludesWallets
                    terms = override.terms ?? terms
                }
                if let terms { try DocumentStore.put(terms, key: "cardTerms:" + card.syncKey, kind: "cardTerms", in: context) }
                else { try DocumentStore.remove("cardTerms:" + card.syncKey, in: context) }
                card.sourceURL = incoming.sourceURL; card.verifiedOn = incoming.verifiedOn
                card.annualFeeNote = incoming.annualFeeNote ?? ""; card.caveats = incoming.caveats ?? ""
                if wasNew || card.imageData == nil { card.imageURL = incoming.imageURL ?? "" }
                card.modifiedAt = .now
                if (wasNew || card.imageData == nil), let data = incoming.imageBase64.flatMap({ Data(base64Encoded: $0) }) ?? images[incoming.id] {
                    try validateImage(data); card.imageData = data
                }
                for item in incoming.rules {
                    let existing = card.rules.first(where: { $0.externalID == item.id })
                    let rule = existing ?? RewardRule(name: item.name, card: card)
                    if existing == nil { context.insert(rule) }
                    var value = RuleSyncData(rule)
                    value.externalID = item.id; value.name = item.name; value.kind = item.kind
                    value.rateBps = Int(Money.cents(item.ratePercent ?? 0)); value.capCents = Money.cents(item.capHKD ?? 0)
                    value.capPeriod = item.capPeriod ?? "monthly"; value.sharedCapGroup = item.sharedCapGroup ?? ""
                    value.thresholdCents = Money.cents(item.thresholdHKD ?? 0); value.bonusCents = Money.cents(item.bonusHKD ?? 0)
                    value.minimumCents = Money.cents(item.minimumHKD ?? 0)
                    value.monthlyPhysicalThresholdCents = Money.cents(item.monthlyPhysicalThresholdHKD ?? 0)
                    value.channelCondition = item.channelCondition ?? "any"; value.category = item.category ?? ""
                    value.currency = item.currency ?? ""; value.paymentMethod = PaymentMethod.canonical(item.paymentMethod ?? "")
                    value.merchantKeywords = item.merchantKeywords ?? ""; value.sourceURL = item.sourceURL
                    value.verifiedOn = incoming.verifiedOn; value.notes = item.notes ?? ""
                    if existing == nil || item.kind != "welcome" {
                        value.startsOn = try optionalDate(item.startsOn) ?? .distantPast
                        value.endsOn = try optionalDate(item.endsOn) ?? .distantPast
                        // Installing published welcome conditions never starts personal tracking.
                        value.isEnabled = item.kind == "welcome" || item.requiresPersonalDates == true ? false : (item.enabled ?? true)
                    }
                    if existing != nil { value.isEnabled = rule.isEnabled }
                    var extras = item.calculation ?? RuleExtras()
                    extras.paymentMethods = Array(Set(extras.paymentMethods.map(PaymentMethod.canonical))).sorted()
                    extras.excludedPaymentMethods = Array(Set(extras.excludedPaymentMethods.map(PaymentMethod.canonical))).sorted()
                    extras.benefitGroup = item.group
                    if item.startsOn == nil || item.endsOn == nil { extras.periodUnverified = true }
                    try RulePolicyStore.imported(value, extras: extras, into: rule, isNew: existing == nil, context: context)
                }
            }
            if commit { try context.save(); Persistence.notifyChange() }
        } catch { context.rollback(); throw error }
    }

}
