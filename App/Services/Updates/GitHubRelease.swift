import Foundation

struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let body: String?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadURL: URL
        let size: Int64
        let digest: String?

        var sha256: String? {
            guard let digest, digest.hasPrefix("sha256:") else { return nil }
            let hash = String(digest.dropFirst(7)).lowercased()
            guard hash.count == 64, hash.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
            return hash
        }

        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case body, draft, prerelease, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
