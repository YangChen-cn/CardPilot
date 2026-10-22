import Foundation

enum DocumentValidator {
    static func validate(_ value: DocumentSyncData) throws {
        func amount(_ cents: Int64) -> Bool { (0...10_000_000_000).contains(cents) }
        func pricing(_ value: CardPricing) -> Bool { [value.baseRateBps, value.foreignFeeBps, value.overseasHKDFeeBps].allSatisfy { (0...10_000).contains($0) } }
        let decoder = SyncCodec.decoder()
        var valid = true
        switch value.kind {
        case "policy":
            let state = try decoder.decode(RulePolicyState.self, from: value.content)
            valid = state.history.count <= 10_000
            for revision in state.history { valid = valid && revision.since <= revision.until }
            let terms = state.history.map(\.value) + [state.current, state.baseline, state.pending].compactMap { $0 }
            for term in terms {
                try SyncCodec.validate(SyncRecord(key: "rule:validation", kind: "rule", revision: .distantPast, deleted: false,
                                                 cardKey: "card:validation", payload: SyncCodec.encoder().encode(term)))
            }
            for extras in state.history.map(\.extras) + [state.extras] + [state.pendingExtras].compactMap({ $0 }) {
                valid = valid && [extras.perTransactionCapCents, extras.minimumOriginalCents, extras.monthlyLocalThresholdCents].allSatisfy(amount)
                    && ["total", "extra"].contains(extras.rateMode) && ["hkd", "faceValue"].contains(extras.rewardBasis)
                    && ["fixed", "percentage"].contains(extras.welcomeMode)
                    && (extras.benefitGroup.map { ["daily", "limited", "merchant", "welcome"].contains($0) } ?? true)
            }
        case "pricing": valid = try decoder.decode([PricingRevision].self, from: value.content).allSatisfy { pricing($0.value) }
        case "cardOverride": valid = pricing(try decoder.decode(CardPricing.self, from: value.content))
        case "cardTerms":
            let terms = try decoder.decode(CardTerms.self, from: value.content)
            valid = (terms.cnyFeeBps.map { (0...10_000).contains($0) } ?? true) && (terms.baseRewardBasis.map { ["hkd", "faceValue"].contains($0) } ?? true)
                && (terms.cnyFeeRegions.map { !$0.isEmpty && $0.allSatisfy { ["HK", "CN", "MO", "other"].contains($0) } } ?? true)
        case "cardOrder":
            let order = try decoder.decode(CardOrder.self, from: value.content)
            valid = value.key == "cardOrder" && order.keys.count <= 500
                && Set(order.keys).count == order.keys.count
                && order.keys.allSatisfy { $0.hasPrefix("card:") && $0.count <= 600 }
        case "welcome": _ = try decoder.decode(WelcomeReceipt.self, from: value.content)
        case "welcomeTracking":
            let tracking = try decoder.decode(WelcomeTracking.self, from: value.content)
            valid = value.key.hasPrefix("welcomeTracking:rule:") && amount(tracking.thresholdCents)
                && tracking.rewardContent.count <= 2000 && tracking.notes.count <= 10_000
        case "welcomeTrackingOffer":
            let tracking = try decoder.decode(WelcomeTracking.self, from: value.content)
            valid = value.key.hasPrefix("welcomeTracking:offer:") && amount(tracking.thresholdCents)
                && tracking.rewardContent.count <= 2000 && tracking.notes.count <= 10_000
        case "offerState":
            let state = try decoder.decode(OfferPersonalState.self, from: value.content)
            valid = value.key.hasPrefix("offerState:") && state.notes.count <= 10_000
        case "personalCardProfile":
            let profile = try decoder.decode(PersonalCardProfile.self, from: value.content)
            valid = value.key == "personalCard:" + profile.cardKey
                && profile.cardKey == "card:catalog:" + profile.productID && !profile.productID.isEmpty && !profile.bankID.isEmpty
                && profile.welcomeRuleIDs.count <= 20 && Set(profile.welcomeRuleIDs).count == profile.welcomeRuleIDs.count
                && profile.managedIDs.count <= 100 && Set(profile.welcomeRuleIDs).isSubset(of: profile.managedIDs)
                && profile.mainManagedIDs.isSubset(of: profile.managedIDs)
                && (!profile.welcomeEnabled || (!profile.welcomePlanID.isEmpty && !profile.welcomeRuleIDs.isEmpty
                    && profile.confirmedEligibility && profile.applicationDate <= profile.issueDate
                    && profile.issueDate <= profile.welcomeStartsOn && profile.welcomeEndsOn >= profile.welcomeStartsOn))
            let addons = profile.addons ?? []
            valid = valid && addons.count <= 30 && Set(addons.map(\.planID)).count == addons.count
                && (!(profile.mainEligibilityClaimed ?? false) || (!profile.welcomePlanID.isEmpty && profile.confirmedEligibility))
            for addon in addons {
                valid = valid && !addon.planID.isEmpty && addon.ruleIDs.count <= 20
                    && Set(addon.ruleIDs).count == addon.ruleIDs.count && Set(addon.ruleIDs).isSubset(of: profile.managedIDs)
                    && addon.startsOn <= addon.endsOn && (!addon.received || (addon.confirmedEligibility && addon.receivedOn != nil))
            }
        case "review":
            let request = try decoder.decode(TransactionRequest.self, from: value.content)
            valid = amount(request.amountCents) && request.amountCents > 0 && Currency(rawValue: request.currency) != nil
        case "mailEvidence":
            let receipt = try decoder.decode(MailEvidence.self, from: value.content)
            let rate = Decimal(string: receipt.exchangeRate) ?? 0
            valid = MailEvidence.valid(receipt.mail) && value.key == receipt.key && receipt.key == MailEvidence.key(for: receipt.mail)
                && receipt.cardKey.hasPrefix("card:") && receipt.cardKey.count <= 600
                && receipt.externalID.hasPrefix("bankmail:") && receipt.externalID.count <= 512
                && receipt.transactionKey == MailEvidence.transactionKey(cardKey: receipt.cardKey, externalID: receipt.externalID)
                && receipt.aliases.count <= 100 && Set(receipt.aliases).count == receipt.aliases.count
                && receipt.aliases.allSatisfy { $0.hasPrefix("transaction:") && $0.count <= 1200 && $0 != receipt.transactionKey }
                && receipt.merchantAliases.count <= 100 && receipt.merchantAliases.allSatisfy { $0.count <= 500 }
                && (receipt.mail.currency != "HKD" && receipt.exchangeRate.isEmpty || !rate.isNaN && rate > 0 && rate <= 1000)
        case "mailReview":
            let review = try decoder.decode(MailReview.self, from: value.content)
            valid = MailEvidence.valid(review.mail) && value.key == review.key && review.key == MailReview.key(for: review.mail)
                && review.reason.count <= 1000 && review.candidateKeys.count <= 100
                && review.candidateKeys.allSatisfy { $0.hasPrefix("transaction:") && $0.count <= 1200 }
                && (review.cardKey.map { $0.hasPrefix("card:") && $0.count <= 600 } ?? true)
        case "creditGroup":
            let group = try decoder.decode(CreditGroup.self, from: value.content)
            valid = !group.name.isEmpty && amount(group.limitCents) && group.limitCents > 0 && group.cardKeys.count <= 100 && Set(group.cardKeys).count == group.cardKeys.count
        case "statement":
            let statement = try decoder.decode(BillingStatement.self, from: value.content), rate = Decimal(string: statement.exchangeRate) ?? 0
            valid = amount(statement.amountCents) && Currency(rawValue: statement.currency) != nil && rate > 0 && rate <= 1000 && statement.dueDate >= statement.periodEnd
        case "repayment": valid = try decoder.decode(Repayment.self, from: value.content).amountCents > 0
        default: valid = false
        }
        guard valid else { throw PilotError.invalid("同步资料内容无效，已保留本机账本。") }
    }
}
