import Foundation
import CryptoKit

/// A small, synced receipt. No email body, account address or local model UUID is retained.
struct MailEvidence: Codable, Equatable, Sendable {
    var key: String
    var mail: BankMailTransaction
    var cardKey: String
    var transactionKey: String
    var externalID: String
    var aliases: [String]
    var merchantAliases: [String]
    var exchangeRate: String
    var explicitlyMatched: Bool
    var keepSeparate = false

    static func key(for mail: BankMailTransaction) -> String {
        "mailEvidence:" + digest(mail.bankID + "\u{1f}" + mail.messageID)
    }

    static func identity(for mail: BankMailTransaction) -> String {
        // A delivery ID proves a retry. A bank reference may additionally join re-deliveries,
        // but is scoped to the card and day: some banks recycle authorisation references.
        let reference = mail.bankReference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fields = reference.isEmpty ? [mail.bankID, "message", mail.messageID] :
            [mail.bankID, "reference", mail.lastFour, String(Int64(HKCalendar.start(mail.date).timeIntervalSince1970)), reference]
        return "bankmail:" + digest(fields.joined(separator: "\u{1f}"))
    }

    static func transactionKey(cardKey: String, externalID: String) -> String {
        "transaction:" + cardKey + ":" + externalID
    }

    static func merchant(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    static func matches(_ mail: BankMailTransaction, transaction: TransactionSyncData, aliases: [String] = []) -> Bool {
        guard mail.amountCents == transaction.amountCents, mail.currency == transaction.currency,
              withinTimeWindow(mail, transaction: transaction),
              Set(([mail.merchant] + aliases).map(merchant)).contains(merchant(transaction.merchant)) else { return false }
        return true
    }

    static func withinTimeWindow(_ mail: BankMailTransaction, transaction: TransactionSyncData) -> Bool {
        guard HKCalendar.calendar.isDate(mail.date, inSameDayAs: transaction.date) else { return false }
        let csvDateOnly = transaction.source == "csv" && transaction.date == HKCalendar.start(transaction.date)
        return !mail.hasExactTime || csvDateOnly || abs(mail.date.timeIntervalSince(transaction.date)) <= 180
    }

    static func valid(_ mail: BankMailTransaction) -> Bool {
        !mail.messageID.isEmpty && mail.messageID.count <= 512 && ["hsbc", "bochk", "bea"].contains(mail.bankID)
            && mail.lastFour.count == 4 && mail.lastFour.allSatisfy(\.isNumber)
            && !merchant(mail.merchant).isEmpty && mail.merchant.count <= 500
            && (1...10_000_000_000).contains(mail.amountCents) && Currency(rawValue: mail.currency) != nil
            && mail.date.timeIntervalSince1970.isFinite && abs(mail.date.timeIntervalSince1970) <= 100_000_000_000
            && mail.receivedAt.timeIntervalSince1970.isFinite && abs(mail.receivedAt.timeIntervalSince1970) <= 100_000_000_000
            && (mail.paymentMethod.map { PaymentMethod(rawValue: $0) != nil } ?? true)
            && (mail.channel.map { ["physical", "online", "unknown"].contains($0) } ?? true)
            && (mail.region.map { ["", "HK", "CN", "MO", "other"].contains($0) } ?? true)
            && (mail.bankReference?.count ?? 0) <= 512
            && ["email", "sms"].contains(mail.source)
            && (mail.cardKind.map { ["信用卡", "借记卡"].contains($0) } ?? true)
    }

    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct MailReview: Codable, Equatable, Sendable, Identifiable {
    var key: String
    var mail: BankMailTransaction
    var reason: String
    var candidateKeys: [String]
    var cardKey: String?
    var id: String { key }

    static func key(for mail: BankMailTransaction) -> String {
        "mailReview:" + MailEvidence.digest(mail.bankID + "\u{1f}" + mail.messageID)
    }
}

struct MailImportResult: Equatable, Sendable {
    var saved = 0
    var updated = 0
    var duplicate = 0
    var pending = 0
}
