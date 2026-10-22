import CryptoKit
import Foundation
import ImageIO

/// Fetches official artwork independently from the catalog document. A failed
/// image never invalidates the catalog, and every cached file is addressed by
/// the content hash declared in the catalog.
actor CatalogAssetStore {
    static let shared = CatalogAssetStore()

    private let directory: URL
    private let session: URLSession
    private let fileManager = FileManager.default
    private var permits = 3
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var inflight: [String: Task<Data?, Never>] = [:]

    private static let maximumBytes = 4_000_000
    private static let maximumDimension = 2400

    init(directory: URL? = nil, session: URLSession? = nil) {
        self.directory = directory ?? Self.applicationDirectory
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

    private func cachedData(for key: String, asset: CatalogAsset) -> Data? {
        let url = directory.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: url), data.count <= Self.maximumBytes,
              Self.hash(data) == key, Self.validImage(data) else {
            try? fileManager.removeItem(at: url)
            return nil
        }
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
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count > 0, data.count <= Self.maximumBytes,
                  Self.validImage(data),
                  Self.hash(data) == key else { return nil }
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
