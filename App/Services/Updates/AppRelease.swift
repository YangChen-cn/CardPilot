import Foundation

struct AppRelease: Sendable, Identifiable {
    enum Platform: String, Sendable {
        case macOS, iOS
        static var current: Self {
            #if os(macOS)
            .macOS
            #else
            .iOS
            #endif
        }
    }

    let version: String
    let notes: String
    let pageURL: URL
    let asset: GitHubRelease.Asset
    var id: String { version }

    /// Download inside the app only when a published SHA-256 digest is available.
    var canDownloadInApp: Bool { asset.sha256 != nil }

    static func newest(in releases: [GitHubRelease], platform: Platform, installed: String) -> Self? {
        guard let current = ReleaseVersion(installed) else { return nil }
        let prefix = "v"
        return releases.compactMap { release -> Self? in
            guard !release.draft, !release.prerelease, release.tagName.hasPrefix(prefix) else { return nil }
            let version = String(release.tagName.dropFirst(prefix.count))
            guard let parsed = ReleaseVersion(version), parsed > current,
                  trustedReleaseURL(release.htmlURL) && release.htmlURL.path == "/YangChen-cn/CardPilot/releases/tag/" + release.tagName else { return nil }
            let name = platform == .macOS ? "CardPilot-\(version).dmg" : "CardPilot-\(version).ipa"
            guard let asset = release.assets.first(where: { $0.name == name && $0.size > 0 && $0.size <= 536_870_912 && trustedReleaseURL($0.browserDownloadURL) && $0.browserDownloadURL.path == "/YangChen-cn/CardPilot/releases/download/" + release.tagName + "/" + name }) else { return nil }
            return Self(version: version, notes: release.body ?? "", pageURL: release.htmlURL, asset: asset)
        }.max { ReleaseVersion($0.version)! < ReleaseVersion($1.version)! }
    }

    static func trustedReleaseURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil
            && url.query == nil && url.fragment == nil && url.port == nil && url.path.hasPrefix("/YangChen-cn/CardPilot/releases/")
    }
}
