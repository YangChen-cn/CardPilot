import CryptoKit
import Foundation

/// The public, versioned catalog snapshot downloaded from GitHub Pages.
/// It contains official product and offer content only; personal data never
/// belongs in this document.
struct RemoteCatalogDocument: Codable, Sendable {
    let schemaVersion: Int
    let contentVersion: Int
    let publishedAt: String
    let products: [RemoteCatalogProduct]

    static let currentSchemaVersion = 1
    static let maximumBytes = 5_000_000

    static func decode(_ data: Data) throws -> RemoteCatalogDocument {
        guard data.count <= maximumBytes else { throw PilotError.invalid("资料文件过大，已保留本地资料。") }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PilotError.invalid("资料格式无效，已保留本地资料。")
        }
        try rejectUnknownFields(root)
        let document = try JSONDecoder().decode(RemoteCatalogDocument.self, from: data)
        guard document.schemaVersion == currentSchemaVersion else {
            throw PilotError.invalid("资料格式版本暂不支持，已保留本地资料。")
        }
        guard document.contentVersion > 0 else { throw PilotError.invalid("资料版本无效。") }
        _ = try CatalogImporter.date(document.publishedAt)
        guard !document.products.isEmpty, document.products.count <= 20 else {
            throw PilotError.invalid("资料产品数量无效。")
        }
        guard Set(document.products.map(\.id)).count == document.products.count else {
            throw PilotError.invalid("资料产品 ID 重复。")
        }
        for product in document.products {
            guard product.id == product.catalog.id, product.bankID == "hsbc" || product.bankID == "bochk" || product.bankID == "bea" else {
                throw PilotError.invalid("资料产品标识不一致。")
            }
            _ = try CatalogImporter.decode(JSONEncoder().encode(CatalogPackage(schemaVersion: 1, cards: [product.catalog])))
            for rule in product.catalog.rules {
                guard let group = rule.group,
                      ["daily", "limited", "merchant", "welcome"].contains(group) else {
                    throw PilotError.invalid("\(product.id)：\(rule.name) 缺少有效的活动分类。")
                }
            }
        }
        return document
    }

    private static func rejectUnknownFields(_ root: [String: Any]) throws {
        func check(_ object: [String: Any], allowed: Set<String>, name: String) throws {
            let unknown = Set(object.keys).subtracting(allowed)
            if !unknown.isEmpty { throw PilotError.invalid("\(name)含不支持的字段：\(unknown.sorted().joined(separator: ", "))。") }
        }
        try check(root, allowed: ["schemaVersion", "contentVersion", "publishedAt", "products"], name: "资料")
        for (index, value) in (root["products"] as? [[String: Any]] ?? []).enumerated() {
            try check(value, allowed: ["id", "bankID", "imageResource", "baseRewardVerified", "welcomePlans", "catalog"],
                      name: "产品 \(index + 1)")
        }
    }

    var cardProducts: [CardProduct] {
        products.map { product in
            CardProduct(bankID: product.bankID, catalog: product.catalog, imageResource: product.imageResource,
                        baseRewardVerified: product.baseRewardVerified, welcomePlans: product.welcomePlans)
        }
    }
}

struct RemoteCatalogProduct: Codable, Sendable {
    let id: String
    let bankID: String
    let imageResource: String
    let baseRewardVerified: Bool
    let welcomePlans: [WelcomePlan]
    let catalog: CatalogCard
}

struct CatalogCacheMetadata: Codable, Sendable {
    var etag: String?
    var lastModified: String?
    var contentVersion: Int?
    var publishedAt: String?
    var lastCheckedAt: Date?
    var lastAppliedAt: Date?
    var lastSuccessAt: Date?
    var lastFailureAt: Date?
    var lastFailureMessage: String?
    var lastFailureKind: String?
}

struct RemoteCatalogSnapshot: Sendable {
    let document: RemoteCatalogDocument
    let data: Data
    let metadata: CatalogCacheMetadata
    var bodyHash: String { RemoteCatalogCache.hash(data) }
}

/// Persists the last completely valid snapshot independently of SwiftData.
/// Content and metadata live in one atomically-written file so a crash cannot
/// leave a version that points at different bytes. The old two-file layout is
/// still read once and upgraded in place. If everything is missing or corrupt,
/// BankLibrary falls back to the bundled catalog.
struct RemoteCatalogCache: Sendable {
    let directory: URL
    private var snapshotURL: URL { directory.appendingPathComponent("snapshot.json") }
    private var statusURL: URL { directory.appendingPathComponent("status.json") }
    private var legacyDocumentURL: URL { directory.appendingPathComponent("catalog.json") }
    private var legacyMetadataURL: URL { directory.appendingPathComponent("metadata.json") }

    private static let formatVersion = 1
    private static let maximumSnapshotBytes = 8_000_000

    static var application: RemoteCatalogCache {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return RemoteCatalogCache(directory: root.appendingPathComponent("CardPilot/Catalog", isDirectory: true))
    }

    init(directory: URL) { self.directory = directory }

    func loadDocument() -> (document: RemoteCatalogDocument, data: Data)? {
        guard let snapshot = loadSnapshot() else { return nil }
        return (snapshot.document, snapshot.data)
    }

    func loadMetadata() -> CatalogCacheMetadata {
        if let snapshot = loadSnapshot() { return snapshot.metadata }
        if let data = try? Data(contentsOf: statusURL),
           let value = try? JSONDecoder().decode(CatalogCacheMetadata.self, from: data) {
            return value
        }
        return loadLegacyMetadata()
    }

    /// Loads the valid snapshot and reconciles metadata with the actual body.
    /// A mismatch is treated as invalid rather than silently choosing a version.
    func loadSnapshot() -> RemoteCatalogSnapshot? {
        if let data = try? Data(contentsOf: snapshotURL) {
            if data.count <= Self.maximumSnapshotBytes,
               let envelope = try? JSONDecoder().decode(SnapshotEnvelope.self, from: data),
               envelope.formatVersion == Self.formatVersion,
               envelope.body.count <= RemoteCatalogDocument.maximumBytes,
               envelope.bodyHash == Self.hash(envelope.body),
               let document = try? RemoteCatalogDocument.decode(envelope.body),
               envelope.metadata.contentVersion == nil || envelope.metadata.contentVersion == document.contentVersion {
                var metadata = envelope.metadata
                metadata.contentVersion = document.contentVersion
                metadata.publishedAt = document.publishedAt
                return RemoteCatalogSnapshot(document: document, data: envelope.body, metadata: metadata)
            }
            // A corrupt snapshot must not make a still-valid legacy cache
            // unusable during the upgrade window.
        }
        return loadLegacySnapshot()
    }

    func save(document: RemoteCatalogDocument, data: Data, metadata: CatalogCacheMetadata) throws {
        guard data.count <= RemoteCatalogDocument.maximumBytes else {
            throw PilotError.invalid("资料文件过大，未写入缓存。")
        }
        var metadata = metadata
        metadata.contentVersion = document.contentVersion
        metadata.publishedAt = document.publishedAt
        let envelope = SnapshotEnvelope(formatVersion: Self.formatVersion, body: data,
                                        bodyHash: Self.hash(data), metadata: metadata)
        try write(envelope, to: snapshotURL)
        try? FileManager.default.removeItem(at: statusURL)
    }

    /// Updates check/status times without touching the cached body. When no
    /// snapshot exists yet, this only writes a small status file.
    func save(metadata: CatalogCacheMetadata) throws {
        if let snapshot = loadSnapshot() {
            var updated = metadata
            updated.contentVersion = snapshot.document.contentVersion
            updated.publishedAt = snapshot.document.publishedAt
            let envelope = SnapshotEnvelope(formatVersion: Self.formatVersion, body: snapshot.data,
                                            bodyHash: Self.hash(snapshot.data), metadata: updated)
            try write(envelope, to: snapshotURL)
            return
        }
        var status = metadata
        status.contentVersion = nil
        status.publishedAt = nil
        try write(status, to: statusURL)
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func loadLegacySnapshot() -> RemoteCatalogSnapshot? {
        guard let data = try? Data(contentsOf: legacyDocumentURL),
              data.count <= RemoteCatalogDocument.maximumBytes,
              let document = try? RemoteCatalogDocument.decode(data) else { return nil }
        var metadata = loadLegacyMetadata()
        if let cachedVersion = metadata.contentVersion, cachedVersion != document.contentVersion {
            // Never let a stale metadata version invalidate valid content, nor
            // let a newer metadata version outlive the body it described.
            metadata.lastAppliedAt = nil
        }
        metadata.contentVersion = document.contentVersion
        metadata.publishedAt = document.publishedAt
        let snapshot = RemoteCatalogSnapshot(document: document, data: data, metadata: metadata)
        try? save(document: document, data: data, metadata: metadata)
        return snapshot
    }

    private func loadLegacyMetadata() -> CatalogCacheMetadata {
        guard let data = try? Data(contentsOf: legacyMetadataURL),
              let value = try? JSONDecoder().decode(CatalogCacheMetadata.self, from: data) else {
            return CatalogCacheMetadata()
        }
        return value
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private struct SnapshotEnvelope: Codable {
        let formatVersion: Int
        let body: Data
        let bodyHash: String
        let metadata: CatalogCacheMetadata
    }
}
