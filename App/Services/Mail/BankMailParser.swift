import Foundation

/// Deliberately narrow parsers for bank mail formats observed in the connected mailbox.
/// Unknown messages do not become purchases, and a malformed known purchase fails the batch.
enum BankMailParser {
    static func decodePackage(_ data: Data) throws -> [BankMailTransaction] {
        guard data.count <= 5_000_000 else { throw invalid("邮件包不能超过 5 MB。") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            let text = try value.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else { throw invalid("邮件收件日期须为完整 ISO8601 时间。") }
            return date
        }
        let package = try decoder.decode(BankMailPackage.self, from: data)
        guard package.schemaVersion == 1, package.messages.count <= 500,
              Set(package.messages.map(\.id)).count == package.messages.count else {
            throw invalid("邮件包版本、数量或邮件标识无效。")
        }
        return try package.messages.compactMap(parse)
    }

    static func parse(_ message: BankMailMessage) throws -> BankMailTransaction? {
        guard !message.id.isEmpty, message.id.count <= 512, message.body.utf8.count <= 1_000_000,
              message.receivedAt.timeIntervalSince1970.isFinite else { throw invalid("邮件标识、日期或正文无效。") }
        let sender = emailAddress(message.sender)
        let bank: String, domain: String
        switch sender {
        case "istatement@bochk.com": bank = "bochk"; domain = "bochk.com"
        case "lcccaut@hkbea.com": bank = "bea"; domain = "hkbea.com"
        case "hsbc_cnp@notification.hsbc.com.hk", "onlineservicesnotification@hsbc.com.hk": bank = "hsbc"; domain = "hsbc.com.hk"
        default: return nil
        }
        let subject = message.subject.lowercased()
        let isHSBCCredit = sender == "hsbc_cnp@notification.hsbc.com.hk"
        let supported: Bool
        switch bank {
        case "bochk": supported = subject.contains("transaction notification") || subject.contains("交易通知")
        case "bea": supported = subject.contains("contactless payment transaction notification")
        default: supported = isHSBCCredit
            ? subject.range(of: #"^hsbc credit card transaction notification(?:\s*(?:/\s*)?滙豐信用卡交易通知)?$"#, options: .regularExpression) != nil
            : subject.contains("online transaction has been made on your debit card") || subject.contains("您的扣賬卡網上交易已完成")
        }
        guard supported else { return nil }
        guard authenticated(message.authenticationResults, domain: domain) else { throw invalid("银行交易邮件未通过 Gmail 发件域验证。") }
        let body = plainText(message.body)
        guard !excluded(subject: subject, body: body) else { return nil }
        switch bank {
        case "bochk": return try bochk(message, body: body)
        case "bea": return try bea(message, body: body)
        default: return try isHSBCCredit ? hsbcCredit(message, body: body) : hsbc(message, body: body)
        }
    }

    private static func bochk(_ message: BankMailMessage, body: String) throws -> BankMailTransaction {
        let tail = try required(#"Card\s+Account\s+Number\s+Ending\s+with\s*[:：]\s*(\d{4})(?!\d)"#, in: body)
        let rawDate = try required(#"Transaction\s+Date\s*[:：]\s*(\d{1,2}/\d{1,2})(?![\d/])"#, in: body)
        let merchant = try required(#"Merchant\s+Name\s*[:：]\s*(.+?)(?=\s*(?:Transaction\s+Amount|交易金額|交易金额)\s*[:：]|\n|$)"#, in: body)
        let money = try required(#"Transaction\s+Amount\s*[:：]\s*((?:HKD|CNY|USD)\s*[\d,]+(?:\.\d{1,2})?)(?![\d.])"#, in: body)
        let (currency, cents) = try amount(money)
        let date = try yearlessDate(rawDate, receivedAt: message.receivedAt)
        return transaction(message, bank: "bochk", tail: tail, merchant: merchant, cents: cents, currency: currency, date: date, exact: false)
    }

    private static func bea(_ message: BankMailMessage, body: String) throws -> BankMailTransaction {
        let tail = try required(#"BEA\s+Credit\s+Card\s*\(\s*last\s+4\s+digits\s+(\d{4})\s*\)"#, in: body)
        let money = try required(#"has\s+made\s+a\s+contactless\s+payment\s+transaction\s+with\s+((?:HKD|CNY|USD)\s*[\d,]+(?:\.\d{1,2})?)(?![\d.])"#, in: body)
        let merchant = try required(#"contactless\s+payment\s+transaction\s+with\s+(?:HKD|CNY|USD)\s*[\d,]+(?:\.\d{1,2})?\s+at\s+(.+?)\s*\*?\s*on\s+\d{4}/\d{1,2}/\d{1,2}"#, in: body)
        let rawDate = try required(#"(?:\s|\*)on\s+(\d{4}/\d{1,2}/\d{1,2})(?![\d/])"#, in: body)
        let (currency, cents) = try amount(money)
        let date = try fullDate(rawDate, format: "yyyy/M/d", receivedAt: message.receivedAt)
        return transaction(message, bank: "bea", tail: tail, merchant: merchant, cents: cents, currency: currency, date: date, exact: false, channel: "physical")
    }

    private static func hsbc(_ message: BankMailMessage, body: String) throws -> BankMailTransaction {
        let tail = try required(#"HSBC\s+Mastercard\s+Debit\s+Card\s+number\s+ending\s+(\d{4})(?!\d)"#, in: body)
        let merchant = try required(#"Merchant\s*[:：]\s*(.+?)(?=\s*(?:Transaction\s+currency\s+and\s+amount|交易貨幣及金額|交易货币及金额)\s*[:：]|\n|$)"#, in: body)
        let money = try required(#"Transaction\s+currency\s+and\s+amount\s*[:：]\s*((?:HKD|CNY|USD)\s*[\d,]+(?:\.\d{1,2})?)(?![\d.])"#, in: body)
        let rawDate = try required(#"Transaction\s+date\s+and\s+time\s*[:：]\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(?::\d{2})?)(?![\d:])"#, in: body)
        let (currency, cents) = try amount(money)
        let format = rawDate.filter { $0 == ":" }.count == 2 ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd HH:mm"
        let date = try fullDate(rawDate, format: format, receivedAt: message.receivedAt)
        let region = capture(#"(?:\s|^)(HK|CN|MO)\s*$"#, in: merchant)?.uppercased()
        return transaction(message, bank: "hsbc", tail: tail, merchant: merchant, cents: cents, currency: currency, date: date, exact: true,
                           payment: "网上支付", channel: "online", region: region)
    }

    private static func hsbcCredit(_ message: BankMailMessage, body: String) throws -> BankMailTransaction {
        let tail = try required(#"(?:^|\n)\s*Credit\s+card\s+number\s*[:：]?\s*Ending\s+with\s*(\d{4})(?!\d)"#, in: body)
        let merchant = try required(#"(?:^|\n)[ \t]*Merchant[ \t]*[:：]?[ \t]*(?:\n[ \t]*)*([^\n]+?)[ \t]*(?=\n+\s*Date\b)"#, in: body)
        let rawDate = try required(#"(?:^|\n)\s*Date\s*[:：]?\s*(\d{1,2}\s+[A-Za-z]{3})(?=\s|$)"#, in: body)
        let money = try required(#"(?:^|\n)\s*Amount\s*[:：]?\s*((?:HKD|CNY|USD)\s*[\d,]+(?:\.\d{1,2})?)(?![\d.])"#, in: body)
        let parts = rawDate.split(whereSeparator: { $0.isWhitespace })
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard parts.count == 2, let month = months.firstIndex(of: parts[1].lowercased()) else {
            throw invalid("汇丰交易日期无效。")
        }
        let date = try yearlessDate("\(parts[0])/\(month + 1)", receivedAt: message.receivedAt)
        let (currency, cents) = try amount(money)
        // Card-not-present does not identify a wallet, channel, or transaction region.
        return transaction(message, bank: "hsbc", tail: tail, merchant: merchant, cents: cents,
                           currency: currency, date: date, exact: false, cardKind: "信用卡")
    }

    private static func transaction(_ message: BankMailMessage, bank: String, tail: String, merchant: String,
                                    cents: Int64, currency: String, date: Date, exact: Bool,
                                    payment: String? = nil, channel: String? = nil, region: String? = nil, cardKind: String? = nil) -> BankMailTransaction {
        BankMailTransaction(messageID: message.id, bankID: bank, lastFour: tail, merchant: merchant,
            amountCents: cents, currency: currency, date: date, hasExactTime: exact, receivedAt: message.receivedAt,
            paymentMethod: payment, channel: channel, region: region, bankReference: nil,
            cardKind: cardKind ?? (bank == "hsbc" ? "借记卡" : bank == "bea" ? "信用卡" : nil))
    }

    private static func emailAddress(_ sender: String) -> String? {
        capture(#"(?:^|<)\s*([A-Z0-9._%+\-]+@[A-Z0-9.\-]+)\s*>?\s*$"#, in: sender)?.lowercased()
    }

    private static func authenticated(_ header: String, domain: String) -> Bool {
        // The first Authentication-Results value must be Gmail's delivery assessment.
        guard header.range(of: #"^\s*(?:Authentication-Results:\s*)?mx\.google\.com\s*;"#, options: [.regularExpression, .caseInsensitive]) != nil else { return false }
        guard let result = header.components(separatedBy: ";").dropFirst().first(where: {
            $0.range(of: #"^\s*dmarc\s*="#, options: [.regularExpression, .caseInsensitive]) != nil
        }) else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: domain)
        return capture(#"^\s*dmarc\s*=\s*(pass)\b[^;]*\bheader\.from\s*=\s*"# + escaped + #"(?=\s|$)"#, in: result) != nil
    }

    private static func excluded(subject: String, body: String) -> Bool {
        let subjectExclusion = #"\b(?:refund|refunded|reversal|reversed|declined|unsuccessful|otp|one.time.password|transfer|repayment|statement|investment|balance)\b|退款|退回|撤銷|撤销|拒絕|拒绝|不成功|還款|还款|轉賬|转账|一次性密碼|一次性密码|結餘|结余"#
        if subject.range(of: subjectExclusion, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        // Match transaction status wording, not footer text mentioning refund/help policies.
        let statusExclusion = #"(?:transaction|payment|purchase)\s+(?:has\s+been\s+|was\s+|is\s+)?(?:declined|reversed|refunded|unsuccessful)|(?:refund|repayment|transfer)\s+(?:amount|notification|confirmation)|交易(?:已)?(?:失敗|失败|被拒|撤銷|撤销)|退款金額|退款金额"#
        return body.range(of: statusExclusion, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func amount(_ raw: String) throws -> (String, Int64) {
        guard let currency = capture(#"^(HKD|CNY|USD)"#, in: raw)?.uppercased(),
              let number = capture(#"^(?:HKD|CNY|USD)\s*((?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?)$"#, in: raw),
              let value = Decimal(string: number.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN, value > 0, value <= 100_000_000 else { throw invalid("银行交易邮件的金额无效或币种尚不支持。") }
        return (currency, NSDecimalNumber(decimal: value * 100).int64Value)
    }

    private static func yearlessDate(_ raw: String, receivedAt: Date) throws -> Date {
        let parts = raw.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 2 else { throw invalid("银行交易日期无效。") }
        let year = HKCalendar.calendar.component(.year, from: receivedAt)
        for candidateYear in [year, year - 1] {
            let components = DateComponents(year: candidateYear, month: parts[1], day: parts[0])
            guard let date = HKCalendar.calendar.date(from: components),
                  HKCalendar.calendar.component(.month, from: date) == parts[1],
                  HKCalendar.calendar.component(.day, from: date) == parts[0], date <= HKCalendar.start(receivedAt),
                  let age = HKCalendar.calendar.dateComponents([.day], from: date, to: HKCalendar.start(receivedAt)).day,
                  (0...14).contains(age) else { continue }
            return date
        }
        throw invalid("银行交易日期与收件日期不符，请人工核对。")
    }

    private static func fullDate(_ raw: String, format: String, receivedAt: Date) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = HKCalendar.calendar; formatter.timeZone = HKCalendar.calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = format; formatter.isLenient = false
        guard let date = formatter.date(from: raw), date <= receivedAt.addingTimeInterval(300),
              HKCalendar.calendar.component(.year, from: date) >= 2000 else { throw invalid("银行交易邮件的交易日期无效。") }
        return date
    }

    private static func plainText(_ html: String) -> String {
        var result = html.replacingOccurrences(of: #"(?is)<(?:script|style)\b[^>]*>.*?</(?:script|style)\s*>"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?i)<\s*(?:br\b[^>]*|/(?:p|div|tr|li|table|h[1-6])\s*)>"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        for (entity, decoded) in ["&nbsp;": " ", "&#160;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"] {
            result = result.replacingOccurrences(of: entity, with: decoded)
        }
        result = result.replacingOccurrences(of: "[\t \u{00A0}]+", with: " ", options: .regularExpression)
        return result.replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
    }

    private static func required(_ pattern: String, in text: String) throws -> String {
        guard let value = capture(pattern, in: text), !value.isEmpty, value.count <= 500 else { throw invalid("银行交易邮件格式已改变或缺少必要字段，请人工核对。") }
        return value
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return text[range].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func invalid(_ message: String) -> PilotError { .invalid(message) }
}
