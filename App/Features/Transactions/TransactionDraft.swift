import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class TransactionDraft {
    var merchant = ""
    var amount = Decimal(0)
    var currency = "HKD" {
        didSet {
            guard oldValue != currency else { return }
            exchangeRate = currency == "HKD" ? 1 : 0
        }
    }
    var exchangeRate = Decimal(1)
    var cardID: UUID?
    var category = "餐饮"
    var paymentMethod = PaymentMethod.unknown.rawValue
    var channel = "unknown"
    var isOverseas = false
    var isRewardEligible = true
    var region = "" {
        didSet {
            if !region.isEmpty { isOverseas = region != "HK" }
        }
    }
    var date = Date.now
    var notes = ""
    var error: String?
    var possibleDuplicate: TransactionDuplicate?
    let existing: SpendTransaction?
    @ObservationIgnored private var preferredCardKey: String?
    @ObservationIgnored private let preferenceDefaults: UserDefaults?

    init(transaction: SpendTransaction?, preferences: QuickEntryPreferences? = nil, defaults: UserDefaults? = nil) {
        existing = transaction
        preferenceDefaults = defaults
        if let transaction {
            merchant = transaction.merchant; amount = Decimal(transaction.amountCents) / 100
            currency = transaction.currency; exchangeRate = Decimal(string: transaction.exchangeRate) ?? 0
            cardID = transaction.card?.id; category = transaction.category; paymentMethod = transaction.paymentMethod
            channel = transaction.channel
            isRewardEligible = transaction.isRewardEligible; date = transaction.date; notes = transaction.notes
            region = transaction.region; isOverseas = transaction.isOverseas
        } else if let preferences = preferences ?? QuickEntryPreferencesStore.load(defaults: defaults) {
            preferredCardKey = preferences.cardKey
            if SpendCategory(rawValue: preferences.category) != nil { category = preferences.category }
            if PaymentMethod(rawValue: preferences.paymentMethod) != nil { paymentMethod = preferences.paymentMethod }
        }
    }

    func prepare(cards: [BankCard]) {
        guard existing == nil else { return }
        if let cardID, cards.contains(where: { $0.id == cardID && !$0.isArchived }) { return }
        cardID = cards.first(where: { !$0.isArchived && $0.syncKey == preferredCardKey })?.id ?? cards.first(where: { !$0.isArchived })?.id
    }

    var validationError: String? {
        if merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写商户。" }
        if merchant.count > 500 { return "商户名称不能超过500字。" }
        if amount.isNaN || amount < 0.01 || amount > Money.maxAmount { return "金额须为0.01–100,000,000。" }
        if currency != "HKD" && (exchangeRate.isNaN || exchangeRate < 0 || exchangeRate > 1000) { return "港币估值汇率须大于0且不超过1000；填0可先按原币记账。" }
        if Currency(rawValue: currency) == nil || PaymentMethod(rawValue: paymentMethod) == nil ||
            SpendCategory(rawValue: category) == nil || !["physical", "online", "unknown"].contains(channel) { return "请检查币种、分类及支付方式。" }
        if date > .now { return "交易日期不能在未来。" }
        if !["", "HK", "CN", "MO", "other"].contains(region) { return "请选择有效的商户地区。" }
        return nil
    }

    func save(in context: ModelContext, cards: [BankCard], allowPossibleDuplicate: Bool = false) -> Bool {
        error = nil; possibleDuplicate = nil
        if let validationError { error = validationError; return false }
        guard let card = cards.first(where: { $0.id == cardID && (!$0.isArchived || $0.id == existing?.card?.id) }) else {
            error = "请选择银行卡。"; return false
        }
        let request = request(card: card)
        do {
            if let match = try TransactionRecorder.assess(request, in: context, editing: existing) {
                if match.isExact { error = "这笔交易已存在，没有重复保存。"; return false }
                if !allowPossibleDuplicate { possibleDuplicate = match; return false }
            }
            var result: TransactionRecordResult?
            try Persistence.save(context) {
                result = try TransactionRecorder.record(request, in: context, allowPossibleDuplicate: allowPossibleDuplicate, editing: existing)
            }
            guard let result, case .recorded = result else {
                error = "这笔交易已存在，没有重复保存。"; return false
            }
            QuickEntryPreferencesStore.save(QuickEntryPreferences(cardKey: card.syncKey, category: category, paymentMethod: paymentMethod), defaults: preferenceDefaults)
            return true
        } catch { self.error = PilotError.message(error); return false }
    }

    func cancelDuplicateConfirmation() { possibleDuplicate = nil }

    private func request(card: BankCard) -> TransactionRequest {
        var request = TransactionRequest(cardID: card.syncKey, merchant: merchant, amountCents: Money.cents(amount), date: date)
        request.currency = currency; request.exchangeRate = currency == "HKD" ? "1" : (exchangeRate == 0 ? "" : exchangeRate.description)
        request.category = category; request.paymentMethod = paymentMethod
        request.channel = channel; request.isOverseas = isOverseas; request.region = region
        request.isRewardEligible = isRewardEligible; request.notes = notes
        request.source = existing?.source ?? "manual"; request.externalID = existing?.externalID ?? ""
        return request
    }
}
