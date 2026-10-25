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


/// Wallet's transaction trigger exposes Amount as a formatted text value on some
/// iOS versions. Keep this separate from the existing numeric manual-recording
/// Intent so older Shortcuts continue working.
enum WalletAmountParser {
    struct Parsed: Equatable {
        let amountCents: Int64
        let currency: String
    }

    enum Failure: Error, LocalizedError, Equatable {
        case missingAmount
        case ambiguousCurrency
        case unsupportedCurrency
        case invalidAmount

        var errorDescription: String? {
            switch self {
            case .missingAmount: "钱包没有传入金额，请检查「数量」变量。"
            case .ambiguousCurrency: "钱包金额没有明确币种，无法可靠区分 HKD/CNY/USD；请检查原文或设置固定备用币种。"
            case .unsupportedCurrency: "钱包交易使用了 CardPilot 尚未支持的币种。"
            case .invalidAmount: "无法识别钱包交易金额，请检查「数量」变量。"
            }
        }
    }

    static func parse(_ raw: String, fallbackCurrency: String = "自动") throws -> Parsed {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.missingAmount }
        let upper = text.uppercased()
        // Strong, explicit currency marks take precedence over the fallback.
        // Shortcuts doesn't expose a consistent standalone currency-code field.
        if ["JPY", "EUR", "SGD", "AUD", "CAD", "GBP", "MOP", "TWD", "KRW"].contains(where: upper.contains) {
            throw Failure.unsupportedCurrency
        }
        var currencies = Set<String>()
        if upper.contains("HKD") || upper.contains("HK$") || upper.contains("HK＄") ||
           text.contains("港币") || text.contains("港幣") {
            currencies.insert("HKD")
        }
        if upper.contains("CNY") || upper.contains("RMB") || upper.contains("CN¥") ||
           upper.contains("CN￥") || text.contains("人民币") || text.contains("人民幣") ||
           text.contains("¥") || text.contains("￥") {
            currencies.insert("CNY")
        }
        if upper.contains("USD") || upper.contains("US$") || upper.contains("US＄") {
            currencies.insert("USD")
        }
        let preference = fallbackCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let fallback: String? = (preference.isEmpty || preference == "自动" || preference == "AUTO") ? nil : preference
        if let fallback, Currency(rawValue: fallback) == nil { throw Failure.unsupportedCurrency }
        guard currencies.count <= 1, let currency = currencies.first ?? fallback else {
            throw Failure.ambiguousCurrency
        }
        // Shortcuts may supply "HK$1,234.56", "1.234,56 CNY" or "¥36.50".
        // Extract the numeric run *without* coercing the original Wallet value
        // to Double. Debit signs don't change the positive expense magnitude.
        guard let range = text.range(of: #"[0-9]+(?:[.,\s][0-9]+)*"#, options: .regularExpression) else {
            throw Failure.invalidAmount
        }
        let number = String(text[range]).filter { !$0.isWhitespace }
        let comma = number.lastIndex(of: ","), dot = number.lastIndex(of: ".")
        let normalized: String
        if let comma, let dot {
            let decimalSeparator: Character = comma > dot ? "," : "."
            let thousandsSeparator: Character = decimalSeparator == "," ? "." : ","
            normalized = number.replacingOccurrences(of: String(thousandsSeparator), with: "")
                .replacingOccurrences(of: String(decimalSeparator), with: ".")
        } else if let separator = comma != nil ? "," : dot != nil ? "." : nil {
            let pieces = number.split(separator: Character(separator), omittingEmptySubsequences: false)
            normalized = (pieces.count > 2 || pieces.last?.count == 3)
                ? number.replacingOccurrences(of: separator, with: "")
                : number.replacingOccurrences(of: separator, with: ".")
        } else {
            normalized = number
        }
        guard let amount = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              amount > 0, amount <= Money.maxAmount else { throw Failure.invalidAmount }
        let cents = Money.cents(amount)
        guard cents > 0 else { throw Failure.invalidAmount }
        return Parsed(amountCents: cents, currency: currency)
    }
}

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
