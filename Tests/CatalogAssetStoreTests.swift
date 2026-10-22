import Foundation
import Testing
@testable import CardPilot

private final class StubAssetURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.notConnectedToInternet) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@Suite(.serialized) @MainActor
struct CatalogAssetStoreTests {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubAssetURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test func downloadsByHashAndKeepsValidCacheAfterNetworkFailure() async throws {
        let source = try #require(BankLibrary.load().product(id: "bochk.chill.platinum")?.artwork.bundledData())
        let hash = CatalogAssetStore.hash(source)
        let asset = CatalogAsset(path: "images/cards/test-\(UUID().uuidString).png",
                                 sha256: hash, contentType: "image/png")
        let directory = FileManager.default.temporaryDirectory.appending(path: "catalog-assets-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        StubAssetURLProtocol.handler = { request in
            #expect(request.url?.lastPathComponent.hasSuffix(".png") == true)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                    headerFields: ["Content-Type": "image/png"])!, source)
        }
        let store = CatalogAssetStore(directory: directory, session: session())
        let base = URL(string: "https://catalog.example.test/docs/")!
        #expect(await store.data(for: asset, baseURL: base) == source)

        StubAssetURLProtocol.handler = nil
        #expect(await store.data(for: asset, baseURL: base) == source)
        #expect(await store.data(for: asset, baseURL: base, force: true) == nil)
        #expect(await store.data(for: asset, baseURL: base) == source)
    }

    @Test func rejectsOversizedDeclaredResponseBeforeReadingBody() async throws {
        let source = try #require(BankLibrary.load().product(id: "bochk.chill.platinum")?.artwork.bundledData())
        let asset = CatalogAsset(path: "images/cards/oversized.png",
                                 sha256: CatalogAssetStore.hash(source), contentType: "image/png")
        let directory = FileManager.default.temporaryDirectory.appending(path: "catalog-assets-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        StubAssetURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                             headerFields: ["Content-Type": "image/png",
                                            "Content-Length": String(CatalogAssetStore.maximumBytes + 1)])!, source)
        }
        let store = CatalogAssetStore(directory: directory, session: session())
        let base = URL(string: "https://catalog.example.test/docs/")!
        #expect(await store.data(for: asset, baseURL: base) == nil)
    }

    @Test func rejectsCrossOriginArtworkURLs() {
        let base = URL(string: "https://catalog.example.test/docs/")!
        #expect(CatalogAssetStore.isTrustedRemoteURL(URL(string: "https://catalog.example.test/docs/a.png")!, baseURL: base))
        #expect(!CatalogAssetStore.isTrustedRemoteURL(URL(string: "https://evil.example.test/a.png")!, baseURL: base))
        #expect(!CatalogAssetStore.isTrustedRemoteURL(URL(string: "http://catalog.example.test/a.png")!, baseURL: base))
        #expect(!CatalogAssetStore.isTrustedRemoteURL(URL(string: "https://catalog.example.test/other/a.png")!, baseURL: base))
    }

    @Test func pruneKeepsCurrentCatalogAndHeldCardArtwork() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "catalog-assets-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let product = try #require(BankLibrary.load().product(id: "bochk.chill.platinum"))
        let current = String(repeating: "a", count: 64)
        let held = product.artwork.sha256
        let stale = String(repeating: "c", count: 64)
        for name in [current, held, stale] {
            try Data(name.utf8).write(to: directory.appending(path: name))
        }
        let store = CatalogAssetStore(directory: directory, session: session())
        await store.retain(product.artwork, forCatalogID: product.id)
        await store.prune(keeping: [current], maximumBytes: 1)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: current).path))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: held).path))
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: stale).path))
    }

    @Test func corruptedCacheIsDiscardedAndRedownloaded() async throws {
        let source = try #require(BankLibrary.load().product(id: "bochk.chill.platinum")?.artwork.bundledData())
        let hash = CatalogAssetStore.hash(source)
        let asset = CatalogAsset(path: "images/cards/test-\(UUID().uuidString).png",
                                 sha256: hash, contentType: "image/png")
        let directory = FileManager.default.temporaryDirectory.appending(path: "catalog-assets-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not an image".utf8).write(to: directory.appending(path: hash))
        StubAssetURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                             headerFields: ["Content-Type": "image/png"])!, source)
        }
        let store = CatalogAssetStore(directory: directory, session: session())
        let base = URL(string: "https://catalog.example.test/docs/")!
        #expect(await store.data(for: asset, baseURL: base) == source)
        #expect(try Data(contentsOf: directory.appending(path: hash)) == source)
    }
}
