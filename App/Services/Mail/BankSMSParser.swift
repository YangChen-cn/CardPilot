import Foundation

/// User-pasted notifications are not authenticated email. Unknown/activation/OTP texts
/// never become transactions. Each occurrence remains distinct until the user reconciles it.
enum BankSMSParser {
    static func parse(_ text: String, referenceDate: Date = .now) throws -> [BankMailTransaction] {
        guard text.utf8.count <= 100_000 else { throw PilotError.invalid("请分批粘贴短信，每批不超过100 KB。") }
        let patterns: [(String, String)] = [
            ("bochk", #"(?:【中銀香港】|【中银香港】)\s*您的中[銀银]信用卡尾[號号]\s*(\d{4})\s*[於于]\s*(\d{1,2}/\d{1,2})\s*在\s*([^【】]{1,500}?)\s*透[過过]手機支付交易\s*(HKD|CNY|USD)\s*([\d,]+(?:\.\d{1,2})?)(?![\d.])"#),
            ("bea", #"(?:東亞銀行|东亚银行)\s*[:：]\s*信用卡尾[數数]\s*(\d{4})\s*[於于]\s*(\d{4}/\d{1,2}/\d{1,2})\s*在\s*([^【】]{1,500}?)\s*\*?作[無无]卡支付\s*(HKD|CNY|USD)\s*([\d,]+(?:\.\d{1,2})?)(?![\d.])"#)
        ]
        var output: [(Int, BankMailTransaction)] = []
        for (bank, pattern) in patterns {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                func field(_ index: Int) -> String {
                    Range(match.range(at: index), in: text).map { String(text[$0]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                }
                let rawAmount = field(5).replacingOccurrences(of: ",", with: "")
                guard let amount = Decimal(string: rawAmount), amount > 0, amount <= Money.maxAmount else {
                    throw PilotError.invalid("短信金额无法识别，请检查原文。")
                }
                let date = try date(field(2), bank: bank, reference: referenceDate)
                var value = BankMailTransaction(messageID: "sms:" + UUID().uuidString, bankID: bank,
                    lastFour: field(1), merchant: field(3).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                        .trimmingCharacters(in: CharacterSet(charactersIn: " *")),
                    amountCents: Money.cents(amount), currency: field(4).uppercased(), date: date,
                    hasExactTime: false, receivedAt: referenceDate, paymentMethod: nil, channel: nil,
                    region: nil, bankReference: nil, cardKind: "信用卡", evidenceSource: "sms")
                // “手机支付/无卡支付” does not prove Apple Pay, physical channel or CN.
                value.paymentMethod = "待确认"
                guard MailEvidence.valid(value) else { throw PilotError.invalid("短信交易资料不完整，请核对原文。") }
                output.append((match.range.location, value))
            }
        }
        guard output.count <= 200 else { throw PilotError.invalid("每次最多导入200条短信，请分批处理。") }
        return output.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private static func date(_ raw: String, bank: String, reference: Date) throws -> Date {
        let parts = raw.split(separator: "/").compactMap { Int($0) }
        let calendar = HKCalendar.calendar
        guard parts.count == (bank == "bochk" ? 2 : 3) else { throw PilotError.invalid("短信日期无效。") }
        let year = bank == "bochk" ? calendar.component(.year, from: reference) : parts[0]
        let month = parts[1]
        let day = bank == "bochk" ? parts[0] : parts[2]
        let years = bank == "bochk" ? [year, year - 1] : [year]
        for year in years where year >= 2000 {
            if let value = calendar.date(from: DateComponents(year: year, month: month, day: day)),
               calendar.component(.month, from: value) == month, calendar.component(.day, from: value) == day,
               value <= HKCalendar.start(reference) { return value }
        }
        throw PilotError.invalid("短信日期无效或晚于所选日期，请检查日期及原文。")
    }
}
