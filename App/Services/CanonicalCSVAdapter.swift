import Foundation
import CryptoKit

/// A documented neutral format. Bank-specific adapters can map their headers into these requests.
struct CanonicalCSVAdapter: TransactionImportAdapter {
    let sourceIdentifier = "cardpilot.csv.v1"
    func parse(_ data: Data, cardID: String) throws -> [TransactionRequest] {
        guard data.count <= 5_000_000, var text = String(data: data, encoding: .utf8) else { throw PilotError.invalid("请选择5MB以内的UTF-8消费记录文件。") }
        if text.first == "\u{feff}" { text.removeFirst() }
        let rows = try cells(text)
        guard let header = rows.first, rows.count <= 10_001 else { throw PilotError.invalid("文件为空或超过10,000笔记录。") }
        let columns = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard Set(columns).count == columns.count, ["merchant", "amount", "date"].allSatisfy(columns.contains) else {
            throw PilotError.invalid("文件须包含merchant、amount、date三列；请先转换为CardPilot消费记录格式。")
        }
        let fileIdentity = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return try rows.dropFirst().enumerated().filter { !$0.element.allSatisfy(\.isEmpty) }.map { index, row in
            guard row.count == columns.count else { throw PilotError.invalid("文件中有列数不一致的记录，请检查引号及逗号。") }
            let values = Dictionary(uniqueKeysWithValues: zip(columns, row))
            let amount = Decimal(string: values["amount"] ?? "", locale: Locale(identifier: "en_US_POSIX"))
            guard let amount, !amount.isNaN, amount > 0, amount <= Money.maxAmount else { throw PilotError.invalid("消费金额必须大于零；退款请先核对原交易。") }
            let rawDate = values["date"] ?? ""
            let date: Date
            if rawDate.count == 10 { date = try CatalogImporter.date(rawDate) }
            else {
                let parser = ISO8601DateFormatter()
                parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let value = parser.date(from: rawDate) { date = value }
                else {
                    parser.formatOptions = [.withInternetDateTime]
                    guard let value = parser.date(from: rawDate) else { throw PilotError.invalid("请使用完整的ISO8601交易时间或YYYY-MM-DD日期。") }
                    date = value
                }
            }
            var request = TransactionRequest(cardID: values["card_id"] ?? cardID, merchant: values["merchant"] ?? "", amountCents: Money.cents(amount), date: date)
            request.hasStableDate = rawDate.count > 10; request.currency = values["currency"] ?? "HKD"
            request.exchangeRate = values["hkd_rate"] ?? ""; request.category = values["category"] ?? "其他"
            request.paymentMethod = values["payment"].flatMap { $0.isEmpty ? nil : $0 } ?? "待确认"
            request.channel = values["channel"].flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
            request.isOverseas = values["overseas"] == "true"
            let reference = values["id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            request.externalID = reference.isEmpty ? "csv-row:\(fileIdentity):\(index)" : reference
            request.region = values["region"] ?? ""; request.source = "csv"
            request.notes = values["notes"]
            if let eligible = values["reward_eligible"] {
                guard ["true", "false"].contains(eligible) else { throw PilotError.invalid("reward_eligible只能填写true或false。") }
                request.isRewardEligible = eligible == "true"
            }
            guard !request.cardID.isEmpty else { throw PilotError.invalid("请选择这份账单所属的银行卡。") }
            return request
        }
    }
    private func cells(_ text: String) throws -> [[String]] {
        let characters = Array(text)
        var rows: [[String]] = [], row: [String] = [], cell = "", quoted = false, index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted && index + 1 < characters.count && characters[index + 1] == "\"" { cell.append("\""); index += 1 }
                else if quoted || cell.isEmpty { quoted.toggle() }
                else { throw PilotError.invalid("文件中的引号格式无效。") }
            } else if !quoted && character == "," { row.append(cell); cell = "" }
            else if !quoted && (character == "\n" || character == "\r" || character == "\r\n") {
                row.append(cell); rows.append(row); row = []; cell = ""
                if character == "\r" && index + 1 < characters.count && characters[index + 1] == "\n" { index += 1 }
            } else { cell.append(character) }
            index += 1
        }
        guard !quoted else { throw PilotError.invalid("文件有未闭合的引号。") }
        if !cell.isEmpty || !row.isEmpty { row.append(cell); rows.append(row) }
        return rows
    }
}
