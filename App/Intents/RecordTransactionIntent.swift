import AppIntents
import SwiftData
import Foundation

struct RecordTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "记录银行卡消费"
    static let description = IntentDescription("保存银行卡消费。外币可按原币记录，汇率和支付详情选填。")
    static let openAppWhenRun = false
    static var parameterSummary: some ParameterSummary {
        Summary("用\(\.$card)记录\(\.$amount)的\(\.$merchant)消费") {
            \.$transactionDate
            \.$currency
            \.$paymentMethod
            \.$category
            \.$hkdRate
            \.$online
            \.$region
            \.$overseas
            \.$externalID
        }
    }

    @Parameter(title: "商户") var merchant: String
    @Parameter(title: "金额") var amount: Double
    @Parameter(title: "银行卡") var card: CardEntity?
    @Parameter(title: "稳定卡片ID（选填）", default: "") var cardID: String
    @Parameter(title: "卡片完整名称（兼容旧快捷指令）", default: "") var cardName: String
    @Parameter(title: "交易时间") var transactionDate: Date?
    @Parameter(title: "支付方式（选填）", default: "待确认") var paymentMethod: String
    @Parameter(title: "消费分类", default: "其他") var category: String
    @Parameter(title: "币种（HKD/CNY/USD）", default: "HKD") var currency: String
    @Parameter(title: "1单位原币折合HKD（选填，0表示未知）", default: 0) var hkdRate: Double
    @Parameter(title: "网上消费", default: false) var online: Bool
    @Parameter(title: "交易地区", default: .unspecified) var region: TransactionRegion
    @Parameter(title: "境外商户", default: false) var overseas: Bool
    @Parameter(title: "交易标识（选填，用于去重）", default: "") var externalID: String

    func transactionRequest(cardID: String, now: Date = .now) throws -> TransactionRequest {
        guard amount.isFinite, amount >= 0.01, amount <= 100_000_000,
              Currency(rawValue: currency) != nil,
              currency == "HKD" || (hkdRate.isFinite && hkdRate >= 0 && hkdRate <= 1000),
              !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PilotError.invalid("金额、商户、币种或外币汇率无效。")
        }
        var request = TransactionRequest(cardID: cardID, merchant: merchant, amountCents: Money.cents(Decimal(amount)), date: transactionDate ?? now)
        request.hasStableDate = transactionDate != nil; request.currency = currency
        request.exchangeRate = currency == "HKD" ? "1" : (hkdRate > 0 ? Decimal(hkdRate).description : "")
        request.paymentMethod = paymentMethod; request.category = category
        request.channel = online ? "online" : "unknown"
        request.region = region.rawValue; request.isOverseas = overseas || region.isOverseas
        request.externalID = externalID
        return request
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try Persistence.live.get()
        let context = container.mainContext
        var stableID = card?.id ?? cardID
        if stableID.isEmpty {
            let matches = try context.fetch(FetchDescriptor<BankCard>()).filter { !$0.isArchived && ($0.name == cardName || $0.displayName == cardName) }
            guard matches.count == 1, let match = matches.first else { throw PilotError.invalid("请在快捷指令中选择银行卡，或填写唯一的完整名称。") }
            stableID = match.syncKey
        }
        let request = try transactionRequest(cardID: stableID)
        let result: TransactionRecordResult
        do { result = try TransactionRecorder.record(request, in: context); try context.save(); Persistence.notifyChange() }
        catch { context.rollback(); throw error }
        switch result {
        case .duplicate: return .result(dialog: "这笔交易已记录，未重复保存。")
        case .needsReview: return .result(dialog: "发现相似交易，已放入待核对列表。")
        case .recorded: break
        }
        return .result(dialog: "已保存到CardPilot：\(merchant)。")
    }
}
