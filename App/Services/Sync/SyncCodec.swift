import Foundation

enum SyncCodec {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var value = encoder.singleValueContainer()
            try value.encode(Int64((date.timeIntervalSince1970 * 1000).rounded()))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(Int64.self)
            guard (-100_000_000_000_000...100_000_000_000_000).contains(value) else {
                throw PilotError.invalid("同步日期无效。")
            }
            return Date(timeIntervalSince1970: Double(value) / 1000)
        }
        return decoder
    }
    static func decode(_ data: Data, expectedDevice: UUID? = nil) throws -> SyncSnapshot {
        guard data.count <= 100_000_000 else { throw PilotError.invalid("同步资料过大，已保留本机账本。") }
        let snapshot = try decoder().decode(SyncSnapshot.self, from: data)
        guard snapshot.format == "cardpilot.sync", [1, 2].contains(snapshot.version),
              snapshot.records.count <= 200_000,
              expectedDevice == nil || snapshot.deviceID == expectedDevice,
              Set(snapshot.records.map(\.key)).count == snapshot.records.count else {
            throw PilotError.invalid("同步资料无法识别，请更新两端的CardPilot。")
        }
        for record in snapshot.records { try validate(record) }
        return snapshot
    }
    static func validate(_ record: SyncRecord) throws {
        guard ["card", "rule", "transaction", "document"].contains(record.kind),
              record.key.hasPrefix(record.kind + ":"), record.key.count <= 1000,
              record.revision.timeIntervalSince1970.isFinite else { throw PilotError.invalid("同步资料不完整，已保留本机账本。") }
        if record.deleted { return }
        guard let payload = record.payload else { throw PilotError.invalid("同步资料不完整，已保留本机账本。") }
        switch record.kind {
        case "document":
            let value = try decoder().decode(DocumentSyncData.self, from: payload)
            guard record.key == "document:" + value.key, value.content.count <= 20_000_000,
                  !value.key.isEmpty, !value.kind.isEmpty,
                  (try? JSONSerialization.jsonObject(with: value.content)) != nil else {
                throw PilotError.invalid("同步资料无效，已保留本机账本。")
            }
            try DocumentValidator.validate(value)
        case "card":
            let value = try decoder().decode(CardSyncData.self, from: payload)
            guard !value.name.isEmpty, !value.bank.isEmpty, (0...31).contains(value.statementDay), (0...31).contains(value.paymentDay),
                  [value.baseRateBps, value.foreignFeeBps, value.overseasHKDFeeBps].allSatisfy({ (0...10_000).contains($0) }) else {
                throw PilotError.invalid("同步卡片资料无效，已保留本机账本。")
            }
            if let image = value.imageData { try CatalogImporter.validateImage(image) }
        case "rule":
            let value = try decoder().decode(RuleSyncData.self, from: payload)
            guard record.cardKey?.hasPrefix("card:") == true, ["cashback", "welcome"].contains(value.kind),
                  value.startsOn <= value.endsOn, (0...10_000).contains(value.rateBps),
                  [value.capCents, value.thresholdCents, value.bonusCents, value.minimumCents, value.monthlyPhysicalThresholdCents].allSatisfy({ (0...10_000_000_000).contains($0) }) else {
                throw PilotError.invalid("同步活动资料无效，已保留本机账本。")
            }
        default:
            let value = try decoder().decode(TransactionSyncData.self, from: payload)
            let rate = Decimal(string: value.exchangeRate) ?? 0
            guard record.cardKey?.hasPrefix("card:") == true, value.amountCents > 0, value.amountCents <= 10_000_000_000,
                  Currency(rawValue: value.currency) != nil,
                  (value.currency != "HKD" && value.exchangeRate.isEmpty || !rate.isNaN && rate > 0 && rate <= 1000) else {
                throw PilotError.invalid("同步消费资料无效，已保留本机账本。")
            }
        }
    }
}
