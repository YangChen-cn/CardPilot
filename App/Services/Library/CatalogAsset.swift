import Foundation

/// A public image referenced by the catalog. Paths are always relative to the
/// trusted catalog root; the document cannot point the app at another host.
struct CatalogAsset: Codable, Hashable, Sendable {
    let path: String
    let sha256: String
    let contentType: String

    var filename: String { (path as NSString).lastPathComponent }
    var fileExtension: String { (filename as NSString).pathExtension.lowercased() }

    func validate() throws {
        let lowerHash = sha256.lowercased()
        guard path.count <= 300, !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !path.contains("://"), !path.contains("?"), !path.contains("#"),
              !path.split(separator: "/").contains(".."),
              URLComponents(string: path)?.scheme == nil else {
            throw PilotError.invalid("图片路径无效。")
        }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts.count <= 5,
              parts.allSatisfy({ !$0.isEmpty && $0.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil }),
              let ext = parts.last?.split(separator: ".").last.map(String.init)?.lowercased(),
              ["png", "jpg", "jpeg", "webp"].contains(ext),
              ["image/png", "image/jpeg", "image/webp"].contains(contentType.lowercased()),
              (ext == "png") == (contentType.lowercased() == "image/png"),
              (ext == "webp") == (contentType.lowercased() == "image/webp"),
              lowerHash.count == 64,
              lowerHash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw PilotError.invalid("图片资源描述无效。")
        }
    }

    /// Resolves a path only when it stays on the catalog endpoint's origin.
    func remoteURL(baseURL: URL) throws -> URL {
        try validate()
        guard let baseHost = baseURL.host, baseURL.scheme == "https" else {
            throw PilotError.invalid("资料资源地址必须是 HTTPS。")
        }
        let url = baseURL.appendingPathComponent(path).standardizedFileURL
        guard url.scheme == "https", url.host == baseHost, url.port == baseURL.port else {
            throw PilotError.invalid("图片地址必须位于资料库站点。")
        }
        return url
    }

    /// The same bytes may be shipped inside the app as an offline fallback.
    func bundledData(bundle: Bundle = .main) -> Data? {
        let parent = (path as NSString).deletingLastPathComponent
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        let urls = [
            parent.isEmpty ? nil : bundle.url(forResource: name, withExtension: ext, subdirectory: "Catalog/" + parent),
            bundle.url(forResource: name, withExtension: ext, subdirectory: "BankLibrary"),
            bundle.url(forResource: name, withExtension: ext)
        ].compactMap { $0 }
        for url in urls {
            guard let data = try? Data(contentsOf: url), CatalogAssetStore.hash(data) == sha256.lowercased() else { continue }
            return data
        }
        return nil
    }

    var normalized: CatalogAsset {
        CatalogAsset(path: path, sha256: sha256.lowercased(), contentType: contentType.lowercased())
    }
}
