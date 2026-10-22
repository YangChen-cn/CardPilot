import CryptoKit
import Foundation
import ImageIO

/// Fetches official artwork independently from the catalog document. A failed
/// image never invalidates the catalog, and every cached file is addressed by
/// the content hash declared in the catalog.
actor CatalogAssetStore {
    static let shared = CatalogAssetStore()

    private let directory: URL
    private let referencesURL: URL
    private let session: URLSession
    private let fileManager = FileManager.default
    private var permits = 3
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var inflight: [String: Task<Data?, Never>] = [:]
    private var references: [String: String]?

    static let maximumBytes = 4_000_000
    private static let maximumDimension = 2400

    init(directory: URL? = nil, session: URLSession? = nil) {
        self.directory = directory ?? Self.applicationDirectory
        self.referencesURL = self.directory.deletingLastPathComponent().appendingPathComponent("references.json")
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpMaximumConnectionsPerHost = 3
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 40
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    static var applicationDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("CardPilot/Catalog/Assets", isDirectory: true)
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func image(for asset: CatalogAsset, baseURL: URL, force: Bool = false) async -> CardImageAsset? {
        guard let data = await data(for: asset, baseURL: baseURL, force: force) else { return nil }
        return try? await CardImageStore.shared.image(for: data)
    }

    func data(for asset: CatalogAsset, baseURL: URL, force: Bool = false) async -> Data? {
        guard (try? asset.validate()) != nil else { return nil }
        let key = asset.sha256.lowercased()
        if !force, let data = cachedData(for: key, asset: asset) { return data }
        if !force, let data = asset.bundledData() { return data }
        if let running = inflight[key] { return await running.value }

        let task = Task<Data?, Never> { await self.download(asset: asset, baseURL: baseURL, key: key) }
        inflight[key] = task
        let data = await task.value
        inflight[key] = nil
        return data
    }

    func removeCachedData(for asset: CatalogAsset) {
        try? fileManager.removeItem(at: directory.appendingPathComponent(asset.sha256.lowercased()))
    }

    /// Remembers artwork used by a held card even after its product leaves the
    /// current catalog. This is deliberately separate from SwiftData: it is a
    /// cache-retention hint, not personal card data.
    func retain(_ asset: CatalogAsset, forCatalogID catalogID: String) {
        guard !catalogID.isEmpty, (try? asset.validate()) != nil else { return }
        var values = loadedReferences()
        values[catalogID] = asset.sha256.lowercased()
        references = values
        saveReferences(values)
    }

    /// Removes unreferenced files and keeps every asset referenced by the
    /// current/retired catalog or by a held official card. Referenced assets are
    /// never evicted just because the cache exceeded its budget.
    func prune(keeping: Set<String>, maximumBytes: Int = 128_000_000) {
        let keep = keeping.union(loadedReferences().values)
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var entries: [(url: URL, name: String, bytes: Int, date: Date)] = []
        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]),
                  values.isDirectory != true else { continue }
            entries.append((file, file.lastPathComponent, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast))
        }
        var total = entries.reduce(0) { $0 + $1.bytes }
        guard total > maximumBytes else { return }
        // Evict least-recently-used unreferenced files until the budget is met.
        // Referenced assets are never evicted, even if they alone exceed it.
        for entry in entries.filter({ !keep.contains($0.name) }).sorted(by: { $0.date < $1.date }) {
            guard total > maximumBytes else { break }
            try? fileManager.removeItem(at: entry.url)
            total -= entry.bytes
        }
    }

    private func cachedData(for key: String, asset: CatalogAsset) -> Data? {
        let url = directory.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: url), data.count <= Self.maximumBytes,
              Self.hash(data) == key, Self.validImage(data) else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    private static func validImage(_ data: Data) -> Bool {
        guard data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return width > 0 && height > 0 && width <= maximumDimension && height <= maximumDimension
    }

    private func download(asset: CatalogAsset, baseURL: URL, key: String) async -> Data? {
        await acquire()
        defer { release() }
        guard let url = try? asset.remoteURL(baseURL: baseURL) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        do {
            let redirectGuard = CatalogRedirectGuard(baseURL: baseURL)
            let (bytes, response) = try await session.bytes(for: request, delegate: redirectGuard)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let finalURL = http.url,
                  Self.isTrustedRemoteURL(finalURL, baseURL: baseURL) else { return nil }
            if http.expectedContentLength > Int64(Self.maximumBytes) { return nil }
            if let declared = http.value(forHTTPHeaderField: "Content-Length"),
               let length = Int(declared), length < 0 || length > Self.maximumBytes {
                return nil
            }
            if let mime = http.mimeType, !mime.hasPrefix("image/") { return nil }
            var data = Data()
            data.reserveCapacity(max(0, min(Int(http.expectedContentLength), Self.maximumBytes)))
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < Self.maximumBytes else { return nil }
                data.append(byte)
            }
            guard data.count > 0, Self.validImage(data), Self.hash(data) == key else { return nil }
            let target = directory.appendingPathComponent(key)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let temporary = directory.appendingPathComponent(".\(key).\(UUID().uuidString).tmp")
            do {
                try data.write(to: temporary, options: .atomic)
                if fileManager.fileExists(atPath: target.path) { try? fileManager.removeItem(at: target) }
                try fileManager.moveItem(at: temporary, to: target)
            } catch {
                try? fileManager.removeItem(at: temporary)
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    /// Only HTTPS downloads from the same origin as the catalog document are
    /// followed. This is shared by the redirect guard so a 3xx response cannot
    /// move the request to an untrusted host.
    static func isTrustedRemoteURL(_ url: URL, baseURL: URL) -> Bool {
        guard baseURL.scheme == "https", let baseHost = baseURL.host,
              url.scheme == "https", url.host == baseHost, url.port == baseURL.port,
              url.user == nil, url.password == nil else { return false }
        let root = baseURL.standardizedFileURL.path.hasSuffix("/")
            ? baseURL.standardizedFileURL.path
            : baseURL.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(root)
    }
    private func loadedReferences() -> [String: String] {
        if let references { return references }
        guard let data = try? Data(contentsOf: referencesURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            references = [:]
            return [:]
        }
        let valid = decoded.filter { $0.value.count == 64 && $0.value.allSatisfy { $0.isHexDigit } }
        references = valid
        return valid
    }

    private func saveReferences(_ values: [String: String]) {
        do {
            try fileManager.createDirectory(at: referencesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(values)
            let temporary = referencesURL.appendingPathExtension("tmp")
            try data.write(to: temporary, options: .atomic)
            if fileManager.fileExists(atPath: referencesURL.path) {
                _ = try fileManager.replaceItemAt(referencesURL, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: referencesURL)
            }
        } catch {
            // Retention hints are best-effort; never block catalog/image loading.
        }
    }

    private func acquire() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            permits += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}


/// Rejects redirects that leave the catalog origin. A rejected redirect is
/// cancelled by returning nil; the caller then sees a non-200 response.
private final class CatalogRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let target = request.url, CatalogAssetStore.isTrustedRemoteURL(target, baseURL: baseURL) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
