import Foundation

actor AppUpdateService {
    private struct Cache: Codable {
        let date: Date
        let etag: String?
        let data: Data
    }
    private let session: URLSession
    private let directory: URL
    private let endpoint = URL(string: "https://api.github.com/repos/YangChen-cn/CardPilot/releases?per_page=100")!

    init(session: URLSession = .shared, directory: URL = URL.cachesDirectory.appendingPathComponent("CardPilotUpdates", isDirectory: true)) {
        self.session = session
        self.directory = directory
    }

    func releases(force: Bool) async throws -> [GitHubRelease] {
        let file = directory.appendingPathComponent("releases.json")
        let cached: Cache?
        do { cached = try JSONDecoder().decode(Cache.self, from: Data(contentsOf: file)) }
        catch { cached = nil } // An absent/evicted metadata cache simply needs a network check.
        if !force, let cached, Date().timeIntervalSince(cached.date) < 6 * 3600 {
            return try JSONDecoder().decode([GitHubRelease].self, from: cached.data)
        }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CardPilot", forHTTPHeaderField: "User-Agent")
        if let etag = cached?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (responseData, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AppUpdateError.request(0) }
        let data: Data
        if http.statusCode == 304, let cached { data = cached.data }
        else if http.statusCode == 200 { data = responseData }
        else { throw AppUpdateError.request(http.statusCode) }
        guard data.count <= 4_000_000 else { throw AppUpdateError.invalidDownload }
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let etag = http.value(forHTTPHeaderField: "ETag") ?? (http.statusCode == 304 ? cached?.etag : nil)
        try JSONEncoder().encode(Cache(date: .now, etag: etag, data: data))
            .write(to: file, options: .atomic)
        return releases
    }

    func download(_ release: AppRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard AppRelease.trustedReleaseURL(release.asset.browserDownloadURL), let digest = release.asset.sha256 else {
            throw AppUpdateError.missingChecksum
        }
        guard release.asset.size > 0, release.asset.size <= 536_870_912 else { throw AppUpdateError.invalidDownload }
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("update.dmg")
        do {
            var request = URLRequest(url: release.asset.browserDownloadURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 60
            let delegate = UpdateDownloadProgress(expectedSize: release.asset.size, report: progress)
            let (temporary, response) = try await session.download(for: request, delegate: delegate)
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw AppUpdateError.request((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
            try Self.verify(destination, size: release.asset.size, digest: digest)
            try Task.checkCancellation()
            progress(1)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: folder) // Only our disposable partial download.
            throw error
        }
    }

    nonisolated static func verify(_ file: URL, size: Int64, digest: String) throws {
        let actualSize = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard actualSize.map(Int64.init) == size else { throw AppUpdateError.invalidDownload }
        guard try UpdateChecksum.sha256(of: file) == digest else { throw AppUpdateError.checksum }
    }

    func discard(_ archive: URL) throws {
        guard archive.deletingLastPathComponent().deletingLastPathComponent() == directory else { return }
        try FileManager.default.removeItem(at: archive.deletingLastPathComponent())
    }

    func resetInstallationStatus(_ archive: URL) throws {
        let status = archive.deletingLastPathComponent().appendingPathComponent("failure.txt")
        if FileManager.default.fileExists(atPath: status.path) { try FileManager.default.removeItem(at: status) }
    }

    func installationError(_ archive: URL) throws -> String? {
        let status = archive.deletingLastPathComponent().appendingPathComponent("failure.txt")
        guard FileManager.default.fileExists(atPath: status.path) else { return nil }
        return try String(contentsOf: status, encoding: .utf8)
    }
}
