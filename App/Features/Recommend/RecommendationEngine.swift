import Foundation

/// Filters public offers by facts the user supplied. It never estimates settlement or reads transactions.
@MainActor enum RecommendationEngine {
    static func suggest(cards: [BankCard], query: RecommendationDraft, now: Date = .now) -> [CardRecommendation] {
        guard query.validationError == nil else { return [] }
        return cards.filter { !$0.isArchived }.map { card in
            let projected = card.modelContext.map { OfferStore.offers(for: card, context: $0) }
                ?? card.rules.filter(\.externalID.isEmpty).map { BenefitInfo(rule: $0) }
            let pricing = PricingStore.current(card)
            let details = PricingStore.details(card)
            let offers = projected.compactMap { offer($0, query: query, now: now) }
                .sorted(by: offerIsOrderedBefore)
            var caveats: [String] = []
            let hasSource = ["https", "http"].contains(URL(string: details.sourceURL)?.scheme ?? "") && !details.verifiedOn.isEmpty
            if query.currency != "HKD", pricing.foreignFeeBps > 0 {
                caveats.append(hasSource
                    ? "外币交易可能收取手续费，资料所列费率为" + Money.percent(pricing.foreignFeeBps) + "，请核对最终结算条款。"
                    : "个人记录了外币手续费，来源及适用条件待核实。")
            }
            if !details.caveats.isEmpty { caveats.append(details.caveats) }
            return CardRecommendation(card: card, offers: offers,
                                      baseBenefit: pricing.baseRateBps > 0
                                        ? (hasSource ? "资料所列基础回赠参考 " + Money.percent(pricing.baseRateBps) + "，合资格消费及兑换条件请核对官方条款。" : "个人记录的基础权益，来源待核实。") : nil,
                                      caveats: caveats)
        }
        .filter { !$0.offers.isEmpty || $0.baseBenefit != nil }
        .sorted {
            if $0.offers.isEmpty != $1.offers.isEmpty { return !$0.offers.isEmpty }
            if $0.bestRateBps != $1.bestRateBps { return $0.bestRateBps > $1.bestRateBps }
            if $0.bestFixedRewardCents != $1.bestFixedRewardCents {
                return $0.bestFixedRewardCents > $1.bestFixedRewardCents
            }
            if $0.knownMatches != $1.knownMatches { return $0.knownMatches > $1.knownMatches }
            if $0.confirmationCount != $1.confirmationCount {
                return $0.confirmationCount < $1.confirmationCount
            }
            return $0.card.displayName.localizedStandardCompare($1.card.displayName) == .orderedAscending
        }
    }

    private static func offerIsOrderedBefore(_ left: SuggestedBenefit, _ right: SuggestedBenefit) -> Bool {
        if left.rateBps != right.rateBps { return left.rateBps > right.rateBps }
        if left.fixedRewardCents != right.fixedRewardCents {
            return left.fixedRewardCents > right.fixedRewardCents
        }
        if left.matchedConditions.count != right.matchedConditions.count {
            return left.matchedConditions.count > right.matchedConditions.count
        }
        if left.confirmationNeeded.count != right.confirmationNeeded.count {
            return left.confirmationNeeded.count < right.confirmationNeeded.count
        }
        return left.title.localizedStandardCompare(right.title) == .orderedAscending
    }

    private static func offer(_ info: BenefitInfo, query: RecommendationDraft, now: Date) -> SuggestedBenefit? {
        guard !info.isWelcome, !info.isHistorical, !info.isArchived, !info.isHidden else { return nil }
        let extras = info.extras
        var matched: [String] = [], missing: [String] = [], keyMissing: [String] = []
        if info.hasKnownEnd, info.endsOn < HKCalendar.start(now) { return nil }
        if info.hasKnownStart, info.startsOn > now { return nil }
        if !info.hasKnownStart {
            missing.append("活动开始日期未核实，请先确认本次消费是否已开始。")
        }
        if !info.hasKnownEnd {
            missing.append("活动结束日期未核实，请先确认本次消费是否仍在活动期内。")
        }
        if !info.hasKnownStart || !info.hasKnownEnd {
            keyMissing.append("活动有效期")
        }
        if !info.category.isEmpty {
            guard info.category == query.category else { return nil }
            matched.append("适用于" + query.category)
        }
        guard !extras.excludedCategories.contains(query.category) else { return nil }
        if !extras.regions.isEmpty {
            guard extras.regions.contains(query.region) else { return nil }
            matched.append("适用于" + SpendLocationPolicy.title(query.region))
        }
        if !info.currency.isEmpty, info.currency != query.currency { return nil }
        if extras.currencyCondition == "foreign", query.currency == "HKD" { return nil }
        if extras.currencyCondition == "local", query.currency != "HKD" { return nil }
        let queryMethod = PaymentMethod.canonical(query.paymentMethod)
        let methods = Array(Set((extras.paymentMethods + (info.paymentMethod.isEmpty ? [] : [info.paymentMethod])).map(PaymentMethod.canonical).filter { !$0.isEmpty })).sorted()
        if !methods.isEmpty {
            if queryMethod.isEmpty {
                missing.append("须使用" + methods.joined(separator: "、") + "；本次支付方式尚未指定。")
                keyMissing.append("支付方式")
            }
            else {
                guard methods.contains(queryMethod) else { return nil }
                matched.append("支付方式符合公开要求：" + queryMethod)
            }
        }
        let excludedMethods = Set(extras.excludedPaymentMethods.map(PaymentMethod.canonical).filter { !$0.isEmpty })
        if !queryMethod.isEmpty, excludedMethods.contains(queryMethod) { return nil }
        if queryMethod.isEmpty, !excludedMethods.isEmpty {
            missing.append("不适用于" + excludedMethods.sorted().joined(separator: "、") + "。")
            keyMissing.append("支付方式")
        }
        let merchants = info.merchantKeywords.split(whereSeparator: { ",，;；\n".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !merchants.isEmpty {
            if query.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missing.append("仅限指定商户：" + merchants.joined(separator: "、") + "；请核对本次商户。")
                keyMissing.append("商户")
            } else {
                guard merchants.contains(where: { MerchantMatcher.matches(query.merchant, keyword: $0) }) else { return nil }
                matched.append("商户名称与公开名单相符，仍需核对银行认定。")
            }
        }
        switch info.channelCondition {
        case "physical": missing.append("仅限实体商户消费，请确认交易渠道。")
        case "online": missing.append("仅限网上消费，请确认交易渠道。")
        case "overseasForeign":
            guard query.region != "HK", query.currency != "HKD" else { return nil }
            missing.append("须由境外商户以外币收单，地区与币种不能证明实际收单方式。")
        case "onlineOrOverseasForeign": missing.append("须为网上消费或境外外币签账，请核对渠道及收单条件。")
        default: break
        }
        if !info.channelCondition.isEmpty, info.channelCondition != "any" {
            keyMissing.append("消费渠道")
        }
        if info.minimumCents > 0 {
            if query.currency == "HKD", let amount = query.amount {
                guard Money.cents(amount) >= info.minimumCents else { return nil }
                matched.append("预计金额达到公开单笔门槛。")
            } else {
                missing.append("单笔消费门槛为" + Money.text(info.minimumCents) + "；请核对结算金额。")
                keyMissing.append("最低单笔消费")
            }
        }
        if extras.minimumOriginalCents > 0 {
            if !info.currency.isEmpty, query.currency == info.currency, let amount = query.amount {
                guard Money.cents(amount) >= extras.minimumOriginalCents else { return nil }
                matched.append("预计原币金额达到公开单笔门槛。")
            } else {
                let minimum = info.currency.isEmpty
                    ? "活动指定原币的最低单笔消费"
                    : Money.text(extras.minimumOriginalCents, currency: info.currency)
                missing.append("需确认最低单笔消费：" + minimum + "；请核对交易币种及原币金额。")
                keyMissing.append("最低单笔消费")
            }
        }
        let monthlyPhysical = info.legacyRule?.monthlyPhysicalThresholdCents
            ?? info.catalogRule?.monthlyPhysicalThresholdHKD.map { Money.cents($0) } ?? 0
        if info.thresholdCents > 0 || extras.monthlyLocalThresholdCents > 0 || monthlyPhysical > 0 {
            missing.append("另设累计消费门槛；此建议不判断你是否已达到。")
        }
        if info.capCents > 0 { missing.append("设有回赠上限，请自行确认剩余名额及额度。") }
        if !info.sharedCapGroup.isEmpty { missing.append("可能与其他活动共享上限或名额。") }
        if info.requiresRegistration, info.personal.enrollment != .registered {
            missing.append(info.personal.enrollment == .notRegistered
                           ? "你记录为尚未登记；请先按银行要求完成登记。"
                           : "需要确认是否已登记；个人登记状态未知。")
            keyMissing.append("登记状态")
        }
        if info.sourceURL.isEmpty || info.verifiedOn.isEmpty { missing.append("公开来源或核实日期不完整，请先向银行核实。") }
        missing.append("合资格签账、推广登记及其他限制以银行条款为准。")
        let rateBps = info.catalogRule?.ratePercent.map { Int(Money.cents($0)) }
            ?? info.legacyRule?.rateBps ?? 0
        let fixedRewardCents = info.catalogRule?.bonusHKD.map { Money.cents($0) }
            ?? info.legacyRule?.bonusCents ?? 0
        return SuggestedBenefit(id: info.id, title: info.title,
                                note: info.legacyRule?.notes ?? info.catalogRule?.notes ?? "",
                                sourceURL: info.sourceURL, endsOn: info.endsOn,
                                hasKnownPeriod: info.hasKnownPeriod,
                                hasKnownStart: info.hasKnownStart,
                                hasKnownEnd: info.hasKnownEnd,
                                legacyRule: info.legacyRule,
                                matchedConditions: matched, confirmationNeeded: missing,
                                headline: info.headline,
                                rateBps: rateBps,
                                fixedRewardCents: fixedRewardCents,
                                capCents: info.capCents,
                                keyMissingConditions: Array(Set(keyMissing)).sorted())
    }
}
