import Foundation
import Observation

enum CatalogFailureKind: String, Sendable {
    case network
    case invalid
}

enum CatalogUpdatePhase: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case updated(Int)
    case networkUnavailable(String)
    case invalidData(String)
}

/// Fetches the public static catalog, validates it, and keeps the last valid
/// snapshot for offline use. It never writes personal SwiftData records.
@MainActor
@Observable
final class CatalogRepository {
    static let shared = CatalogRepository()

    static let defaultEndpoint = URL(string: "https://yangchen-cn.github.io/CardPilot-Catalog/catalog.json")!

    let endpoint: URL
    let checkInterval: TimeInterval
    private let session: URLSession
    private let cache: RemoteCatalogCache
    private let now: () -> Date
    private(set) var snapshot: RemoteCatalogSnapshot?

    private(set) var phase: CatalogUpdatePhase = .idle
    private(set) var isChecking = false
    private(set) var lastCheckedAt: Date?
    private(set) var lastAppliedAt: Date?
    private(set) var lastSuccessAt: Date?
    private(set) var lastFailureAt: Date?
    private(set) var lastFailureMessage: String?
    private(set) var lastFailureKind: CatalogFailureKind?
    private(set) var contentVersion: Int?
    private(set) var publishedAt: String?
    /// Bumped after a successful cache replacement so views can recompute
    /// their official offers without observing SwiftData.
    private(set) var revision = 0
    /// Incremented after every check so failed artwork can be retried by the UI.
    private(set) var assetRetryToken = 0

    var assetBaseURL: URL { endpoint.deletingLastPathComponent() }

    init(endpoint: URL = CatalogRepository.defaultEndpoint,
         session: URLSession = .shared,
         cache: RemoteCatalogCache = .application,
         checkInterval: TimeInterval = 6 * 60 * 60,
         now: @escaping () -> Date = Date.init) {
        self.endpoint = endpoint
        self.session = session
        self.cache = cache
        self.checkInterval = checkInterval
        self.now = now
        snapshot = cache.loadSnapshot()
        let metadata = cache.loadMetadata()
        lastCheckedAt = metadata.lastCheckedAt
        lastAppliedAt = metadata.lastAppliedAt
        lastSuccessAt = metadata.lastSuccessAt ?? metadata.lastAppliedAt ?? metadata.lastCheckedAt
        lastFailureAt = metadata.lastFailureAt
        lastFailureMessage = metadata.lastFailureMessage
        lastFailureKind = metadata.lastFailureKind.flatMap(CatalogFailureKind.init(rawValue:))
        contentVersion = snapshot?.document.contentVersion
        publishedAt = snapshot?.document.publishedAt
    }

    var isUsingBundled: Bool { snapshot == nil }
    var hasCachedSnapshot: Bool { snapshot != nil }

    var cacheSourceText: String {
        isUsingBundled ? "App 内置资料" : "云端缓存"
    }

    var versionText: String {
        guard let contentVersion else { return "内置版本" }
        return "版本 \(contentVersion)"
    }

    var publishedText: String? { publishedAt }

    var lastUpdatedText: String {
        if isUsingBundled { return "正在使用 App 内置资料" }
        if let publishedAt { return "使用云端缓存（\(versionText)，发布于 \(publishedAt)）" }
        return "使用云端缓存（\(versionText)）"
    }

    var lastCheckedText: String? {
        guard let lastCheckedAt else { return nil }
        return "上次检查：" + lastCheckedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var lastSuccessText: String? {
        guard let lastSuccessAt else { return nil }
        return "上次成功：" + lastSuccessAt.formatted(date: .abbreviated, time: .shortened)
    }

    var lastAppliedText: String? {
        guard let lastAppliedAt else { return nil }
        return "最近应用：" + lastAppliedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var lastFailureText: String? {
        guard let lastFailureMessage else { return nil }
        return lastFailureMessage
    }

    var statusText: String {
        switch phase {
        case .checking: return "正在检查官方资料更新…"
        case .updated(let count): return "已更新官方资料（\(count) 个产品）。"
        case .upToDate: return "资料已是最新版本。"
        case .networkUnavailable:
            return "当前网络不可用，继续使用\(cacheSourceText)。"
        case .invalidData:
            return "云端资料无效，已保留\(cacheSourceText)。"
        case .idle:
            if lastFailureAt != nil {
                return lastFailureKind == .network ? "当前网络不可用，继续使用\(cacheSourceText)。" : "云端资料无效，已保留\(cacheSourceText)。"
            }
            return isUsingBundled ? "尚未从云端更新，使用 App 内置资料。" : "可在有网络时检查官方资料更新。"
        }
    }

    /// Foreground/startup entry point. A failed attempt still counts as a check,
    /// so the app does not retry on every scene activation. Manual refresh can
    /// always bypass the interval.
    func checkIfNeeded() async {
        guard !isChecking else { return }
        if let lastCheckedAt, now().timeIntervalSince(lastCheckedAt) < checkInterval { return }
        await check(force: false)
    }

    func check(force: Bool) async {
        guard !isChecking else { return }
        if !force, let lastCheckedAt, now().timeIntervalSince(lastCheckedAt) < checkInterval { return }
        isChecking = true
        phase = .checking
        defer {
            isChecking = false
            assetRetryToken &+= 1
        }

        let cached = cache.loadSnapshot()
        var metadata = cached?.metadata ?? cache.loadMetadata()
        let cachedVersion = cached?.document.contentVersion ?? 0
        let cachedHash = cached?.bodyHash
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if cached != nil, let etag = metadata.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        else if cached != nil, let modified = metadata.lastModified { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw PilotError.invalid("资料服务返回了无效响应。") }
            let checkedAt = now()
            switch http.statusCode {
            case 304:
                guard let cached else { throw PilotError.invalid("资料服务返回 304，但本地没有可用的资料缓存。") }
                metadata.lastCheckedAt = checkedAt
                metadata.lastSuccessAt = checkedAt
                metadata.lastFailureAt = nil
                metadata.lastFailureMessage = nil
                metadata.lastFailureKind = nil
                if let etag = http.value(forHTTPHeaderField: "ETag") { metadata.etag = etag }
                if let modified = http.value(forHTTPHeaderField: "Last-Modified") { metadata.lastModified = modified }
                try cache.save(metadata: metadata)
                snapshot = RemoteCatalogSnapshot(document: cached.document, data: cached.data, metadata: metadata)
                lastCheckedAt = checkedAt
                lastSuccessAt = checkedAt
                clearFailure()
                phase = .upToDate
            case 200:
                // Decode and validate off the main actor so a slow or damaged
                // response cannot stall the UI.
                let document = try await Task.detached(priority: .utility) {
                    let document = try RemoteCatalogDocument.decode(data)
                    try BankLibrary.validateRemote(document)
                    return document
                }.value
                guard document.contentVersion >= cachedVersion else {
                    throw PilotError.invalid("云端资料版本低于本地缓存，已保留本地资料。")
                }
                let incomingHash = RemoteCatalogCache.hash(data)
                if document.contentVersion == cachedVersion, let cached {
                    guard cachedHash == incomingHash else {
                        throw PilotError.invalid("云端资料版本号未更新，但内容发生了变化，已保留本地资料。")
                    }
                    metadata.lastCheckedAt = checkedAt
                    metadata.lastSuccessAt = checkedAt
                    metadata.lastFailureAt = nil
                    metadata.lastFailureMessage = nil
                    metadata.lastFailureKind = nil
                    metadata.contentVersion = document.contentVersion
                    metadata.publishedAt = document.publishedAt
                    metadata.etag = http.value(forHTTPHeaderField: "ETag")
                    metadata.lastModified = http.value(forHTTPHeaderField: "Last-Modified")
                    try cache.save(metadata: metadata)
                    snapshot = RemoteCatalogSnapshot(document: cached.document, data: cached.data, metadata: metadata)
                    lastCheckedAt = checkedAt
                    lastSuccessAt = checkedAt
                    contentVersion = document.contentVersion
                    publishedAt = document.publishedAt
                    clearFailure()
                    phase = .upToDate
                } else {
                    let appliedAt = now()
                    metadata.lastCheckedAt = checkedAt
                    metadata.lastAppliedAt = appliedAt
                    metadata.lastSuccessAt = checkedAt
                    metadata.lastFailureAt = nil
                    metadata.lastFailureMessage = nil
                    metadata.lastFailureKind = nil
                    metadata.contentVersion = document.contentVersion
                    metadata.publishedAt = document.publishedAt
                    metadata.etag = http.value(forHTTPHeaderField: "ETag")
                    metadata.lastModified = http.value(forHTTPHeaderField: "Last-Modified")
                    let savedMetadata = metadata
                    let directory = cache.directory
                    try await Task.detached(priority: .utility) {
                        try RemoteCatalogCache(directory: directory)
                            .save(document: document, data: data, metadata: savedMetadata)
                    }.value
                    snapshot = RemoteCatalogSnapshot(document: document, data: data, metadata: savedMetadata)
                    BankLibrary.invalidate()
                    let keptAssets = (try? BankLibrary.load())?.referencedArtworkHashes ?? []
                    Task(priority: .utility) {
                        await CatalogAssetStore.shared.prune(keeping: keptAssets)
                    }
                    revision &+= 1
                    lastCheckedAt = checkedAt
                    lastAppliedAt = appliedAt
                    lastSuccessAt = checkedAt
                    contentVersion = document.contentVersion
                    publishedAt = document.publishedAt
                    clearFailure()
                    phase = .updated(document.products.count)
                }
            default:
                throw PilotError.invalid("资料服务暂时不可用（HTTP \(http.statusCode)）。")
            }
        } catch {
            let checkedAt = now()
            metadata.lastCheckedAt = checkedAt
            metadata.lastFailureAt = checkedAt
            let isNetwork = error is URLError
            let kind: CatalogFailureKind = isNetwork ? .network : .invalid
            let message: String
            if isNetwork {
                message = "网络不可用，继续使用\(cacheSourceText)。"
            } else {
                message = PilotError.message(error, fallback: "无法读取云端资料，继续使用\(cacheSourceText)。")
            }
            metadata.lastFailureMessage = message
            metadata.lastFailureKind = kind.rawValue
            try? cache.save(metadata: metadata)
            lastCheckedAt = checkedAt
            lastFailureAt = checkedAt
            lastFailureMessage = message
            lastFailureKind = kind
            phase = isNetwork ? .networkUnavailable(message) : .invalidData(message)
        }
    }

    private func clearFailure() {
        lastFailureAt = nil
        lastFailureMessage = nil
        lastFailureKind = nil
    }
}
