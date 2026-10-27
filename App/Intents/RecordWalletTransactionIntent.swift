import AppIntents
import SwiftData
import Foundation

/// A Wallet/Transaction automation action: feed the Wallet Amount magic variable
/// to a String, not the numeric Double parameter of RecordTransactionIntent.
struct RecordWalletTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "记录 Apple Pay 交易"
    static let description = IntentDescription("从钱包交易的金额原文识别金额和币种，记录到选定银行卡。")
    static let openAppWhenRun = false

    @Parameter(title: "钱包金额原文") var amountText: String?
    @Parameter(title: "商户") var merchant: String?
    @Parameter(title: "CardPilot 银行卡") var card: CardEntity?
    @Parameter(title: "币种不明确时（自动/HKD/CNY/USD）", default: "自动")
    var fallbackCurrency: String

    static var parameterSummary: some ParameterSummary {
        Summary("用 \(\.$card) 记录 \(\.$amountText) 的 \(\.$merchant) 消费") {
            \.$fallbackCurrency
        }
    }

    func transactionRequest(cardID: String, now: Date = .now) throws -> TransactionRequest {
        let parsed = try WalletAmountParser.parse(amountText ?? "", fallbackCurrency: fallbackCurrency)
        let name = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PilotError.invalid("钱包没有传入商户，请检查「商家」变量。") }
        var request = TransactionRequest(cardID: cardID, merchant: name,
                                         amountCents: parsed.amountCents, date: now)
        request.currency = parsed.currency
        request.paymentMethod = "Apple Pay"
        request.channel = "physical"
        // The Wallet trigger doesn't reliably expose the original transaction
        // timestamp or a stable transaction ID. Don't claim it does.
        request.hasStableDate = false
        return request
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let card else { throw PilotError.invalid("请在自动化中选择 CardPilot 银行卡。") }
        let request = try transactionRequest(cardID: card.id)
        let context = try Persistence.live.get().mainContext
        let result: TransactionRecordResult
        do {
            result = try TransactionRecorder.record(request, in: context)
            try context.save()
            Persistence.notifyChange()
        } catch {
            context.rollback()
            throw error
        }
        switch result {
        case .recorded: return .result(dialog: "已记录 \(request.merchant) · \(request.currency)。")
        case .duplicate: return .result(dialog: "这笔交易已记录，没有重复保存。")
        case .needsReview: return .result(dialog: "发现相似交易，请到 CardPilot 交易核对中确认。")
        }
    }
}
