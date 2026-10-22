import Foundation
import SwiftData

@MainActor enum DocumentStore {
    static func record(_ key: String, in context: ModelContext) throws -> DomainRecord? {
        try context.fetch(FetchDescriptor<DomainRecord>(predicate: #Predicate { $0.key == key })).first
    }
    static func load<T: Decodable>(_ type: T.Type, key: String, in context: ModelContext) throws -> T? {
        guard let record = try record(key, in: context), !record.isDeleted else { return nil }
        return try SyncCodec.decoder().decode(type, from: record.content)
    }
    static func put<T: Encodable>(_ value: T, key: String, kind: String, in context: ModelContext, now: Date = .now) throws {
        let data = try SyncCodec.encoder().encode(value)
        if let existing = try record(key, in: context) {
            guard existing.content != data || existing.isDeleted else { return }
            existing.content = data; existing.modifiedAt = now; existing.isDeleted = false
        } else { context.insert(DomainRecord(key: key, kind: kind, content: data, modifiedAt: now)) }
    }
    static func remove(_ key: String, in context: ModelContext) throws {
        if let record = try record(key, in: context) { record.isDeleted = true; record.modifiedAt = .now }
    }
}
