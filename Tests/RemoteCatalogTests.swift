import Foundation
import SwiftData
import Testing
@testable import CardPilot

private final class StubCatalogURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unknown) }
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
struct RemoteCatalogTests {
    private let endpoint = URL(string: "https://catalog.example.test/catalog.json")!
    private func asset(_ path: String, type: String = "image/png") -> CatalogAsset {
        CatalogAsset(path: path, sha256: String(repeating: "a", count: 64), contentType: type)
    }
    private func bank() -> RemoteCatalogBank {
        RemoteCatalogBank(id: "bochk", name: "BOCHK 中银香港", shortName: "BOCHK",
                          logo: asset("images/banks/bochk.png"), searchTerms: ["中银"])
    }

    private func product(rate: Decimal = 2, includeOld: Bool = true, verifiedOn: String = "2026-10-22") throws -> CardProduct {
        var rules: [[String: Any]] = [
            ["id": "daily", "name": "Daily", "kind": "cashback", "group": "daily", "startsOn": "2026-10-01",
             "endsOn": "2026-12-31", "sourceURL": "https://example.com/official",
             "ratePercent": NSDecimalNumber(decimal: rate)]
        ]
        if includeOld {
            rules.append(["id": "old-activity", "name": "Old activity", "kind": "cashback", "group": "daily",
                          "startsOn": "2026-01-01", "endsOn": "2026-02-01",
                          "sourceURL": "https://example.com/old", "ratePercent": 1])
        }
        let object: [String: Any] = [
            "id": "remote.test", "bank": "Test bank", "name": "Remote test product", "network": "Visa",
            "sourceURL": "https://example.com/official", "verifiedOn": verifiedOn, "baseRatePercent": 0.4,
            "rules": rules
        ]
        let catalog = try JSONDecoder().decode(CatalogCard.self, from: JSONSerialization.data(withJSONObject: object))
        return CardProduct(bankID: "bochk", catalog: catalog, artwork: asset("images/cards/bochk-chill-platinum.png"),
                           baseRewardVerified: true, welcomePlans: [], searchTerms: [])
    }

    private func document(version: Int, rate: Decimal = 4, includeOld: Bool = true,
                          verifiedOn: String = "2026-10-23") throws -> RemoteCatalogDocument {
        let card = try product(rate: rate, includeOld: includeOld, verifiedOn: verifiedOn).catalog
        return RemoteCatalogDocument(schemaVersion: 2, contentVersion: version, publishedAt: "2026-10-23",
                                     banks: [bank()],
                                     products: [RemoteCatalogProduct(id: card.id, bankID: "bochk",
                                                                     artwork: asset("images/cards/bochk-chill-platinum.png"),
                                                                     baseRewardVerified: true, welcomePlans: [],
                                                                     catalog: card, searchTerms: [])])
    }

    private func data(_ document: RemoteCatalogDocument) throws -> Data {
        try JSONEncoder().encode(document)
    }

    private func temporaryCache() -> RemoteCatalogCache {
        RemoteCatalogCache(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("CardPilotRemoteCatalogTests/\(UUID().uuidString)", isDirectory: true))
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubCatalogURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test func downloadsAppliesAndCachesOfficialChanges() async throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let initial = try product()
        let card = try LibraryOnboarding.add(product: initial, in: context)
        let cache = temporaryCache(), doc = try document(version: 1)
        let payload = try data(doc)
        StubCatalogURLProtocol.handler = { request in
            #expect(request.httpMethod == "GET")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                    headerFields: ["ETag": "\"catalog-v1\"", "Content-Type": "application/json"])!, payload)
        }
        let repository = CatalogRepository(endpoint: endpoint, session: session(), cache: cache)
        await repository.check(force: true)

        #expect(repository.phase == .updated(1))
        #expect(repository.contentVersion == 1)
        #expect(repository.lastAppliedAt != nil)
        #expect(repository.lastUpdatedText.contains("2026-10-23"))
        #expect(card.rules.isEmpty)
        #expect(cache.loadDocument()?.document.contentVersion == 1)
        #expect(cache.loadMetadata().etag == "\"catalog-v1\"")
    }

    @Test func etag304DoesNotReapplyOrReplacePersonalData() async throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let initial = try product()
        let card = try LibraryOnboarding.add(product: initial, in: context)
        card.name = "My card"; card.lastFour = "4321"; card.statementDay = 17
        card.rules.first { $0.externalID == "daily" }?.isEnabled = false
        let manual = RewardRule(name: "My manual rule", card: card, rateBps: 700)
        context.insert(manual)
        try context.save()

        let cache = temporaryCache(), doc = try document(version: 1)
        let payload = try data(doc)
        nonisolated(unsafe) var conditionalHeader: String?
        StubCatalogURLProtocol.handler = { request in
            if request.value(forHTTPHeaderField: "If-None-Match") != nil {
                conditionalHeader = request.value(forHTTPHeaderField: "If-None-Match")
                return (HTTPURLResponse(url: request.url!, statusCode: 304, httpVersion: "HTTP/1.1",
                                        headerFields: ["ETag": "\"catalog-v1\""])!, Data())
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                    headerFields: ["ETag": "\"catalog-v1\""])!, payload)
        }
        let repository = CatalogRepository(endpoint: endpoint, session: session(), cache: cache)
        await repository.check(force: true)
        let modified = card.modifiedAt
        await repository.check(force: true)

        #expect(repository.phase == .upToDate)
        #expect(conditionalHeader == "\"catalog-v1\"")
        #expect(card.modifiedAt == modified)
        #expect(card.name == "My card"); #expect(card.lastFour == "4321"); #expect(card.statementDay == 17)
        #expect(card.rules.contains { $0.id == manual.id })
    }

    @Test func corruptOrOlderResponseKeepsLastValidCacheAndCardContent() async throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let initial = try product()
        let card = try LibraryOnboarding.add(product: initial, in: context)
        let cache = temporaryCache(), first = try document(version: 2)
        try cache.save(document: first, data: try data(first),
                       metadata: CatalogCacheMetadata(etag: "\"v2\"", contentVersion: 2, publishedAt: "2026-10-23"))

        StubCatalogURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
             Data("{\"schemaVersion\":1".utf8))
        }
        let repository = CatalogRepository(endpoint: endpoint, session: session(), cache: cache)
        await repository.check(force: true)

        #expect(repository.lastAppliedAt == nil)
        #expect(cache.loadDocument()?.document.contentVersion == 2)
        #expect(card.rules.isEmpty)
        if case .invalidData = repository.phase {} else { Issue.record("expected invalid-data phase") }

        StubCatalogURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
             try! self.data(self.document(version: 1)))
        }
        await repository.check(force: true)
        #expect(cache.loadDocument()?.document.contentVersion == 2)
        #expect(card.rules.isEmpty)
    }

    @Test func unavailableNetworkLeavesCacheAndBundledPreviewAvailable() async throws {
        let cache = temporaryCache(), doc = try document(version: 7, rate: 6)
        let saved = try data(doc)
        try cache.save(document: doc, data: saved, metadata: CatalogCacheMetadata(contentVersion: 7, publishedAt: "2026-10-23"))
        BankLibrary.invalidate()
        let library = try BankLibrary.load(remoteCache: cache)
        #expect(library.products.count == 1)
        #expect(library.retiredProducts.count == 13)
        let remote = try #require(library.products.first { $0.id == "remote.test" })
        #expect(remote.catalog.rules.first { $0.id == "daily" }?.ratePercent == 6)

        try Data("not-json".utf8).write(to: cache.directory.appendingPathComponent("snapshot.json"))
        BankLibrary.invalidate()
        let fallback = try BankLibrary.load(remoteCache: cache)
        #expect(fallback.products.contains { $0.id == "remote.test" } == false)
        BankLibrary.invalidate()
    }

    @Test func legacyOfficialActivityIsShownAsHistoryWithoutWritingAgain() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let product = try #require(BankLibrary.load().products.first { $0.id == "bochk.chill.platinum" })
        let card = BankCard(bank: "BOCHK", name: "History copy")
        card.catalogID = product.id; context.insert(card)
        let old = RewardRule(name: "Old activity", card: card, rateBps: 100,
                             startsOn: try CatalogImporter.date("2026-01-01"),
                             endsOn: try CatalogImporter.date("2026-02-01"))
        old.externalID = "old-activity"; context.insert(old)
        let info = try #require(OfferStore.offers(for: card, context: context).first { $0.legacyRule?.externalID == "old-activity" })
        #expect(info.origin == .historical)
        #expect(info.isHistorical)
        #expect(card.rules.count == 1)
        #expect(card.rules.first?.id == old.id)
    }

    @Test func remoteDocumentRequiresExplicitOfferGroup() throws {
        let doc = try document(version: 1)
        var object = try #require(try JSONSerialization.jsonObject(with: data(doc)) as? [String: Any])
        var products = try #require(object["products"] as? [[String: Any]])
        var catalog = try #require(products[0]["catalog"] as? [String: Any])
        var rules = try #require(catalog["rules"] as? [[String: Any]])
        rules[0].removeValue(forKey: "group")
        catalog["rules"] = rules
        products[0]["catalog"] = catalog
        object["products"] = products
        #expect(throws: (any Error).self) {
            _ = try RemoteCatalogDocument.decode(JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test func missingOfficialDatesStayUnknownRatherThanBorrowingOtherDates() throws {
        let card = BankCard(bank: "BOCHK", name: "Date copy")
        var rule = CatalogRule(id: "unknown-dates", name: "Unknown dates", kind: "cashback", group: "limited",
                               startsOn: nil, endsOn: nil, sourceURL: "https://example.com/official")
        rule.capPeriod = "campaign"
        let catalog = CatalogCard(id: "date.test", bank: "BOCHK", name: "Date product", network: "Visa",
                                  sourceURL: "https://example.com/official", verifiedOn: "2026-10-23", rules: [rule])
        let product = CardProduct(bankID: "bochk", catalog: catalog, artwork: asset("images/cards/bochk-chill-platinum.png"),
                                  baseRewardVerified: false, welcomePlans: [], searchTerms: [])
        let info = BenefitInfo(official: rule, product: product, card: card, state: OfferPersonalState())
        #expect(!info.hasKnownPeriod)
        #expect(info.startsOn == .distantPast)
        #expect(info.endsOn == .distantFuture)
        #expect(info.conditions.first?.contains("有效期尚未核实") == true)
    }

    @Test func rejectsUnknownFieldsAndIncompatibleSchema() throws {
        let doc = try document(version: 1)
        var object = try #require(try JSONSerialization.jsonObject(with: data(doc)) as? [String: Any])
        object["unexpected"] = true
        #expect(throws: (any Error).self) {
            _ = try RemoteCatalogDocument.decode(JSONSerialization.data(withJSONObject: object))
        }
        let schemaOne = RemoteCatalogDocument(schemaVersion: 1, contentVersion: 1, publishedAt: "2026-10-23",
                                              banks: doc.banks, products: doc.products)
        #expect(throws: (any Error).self) { _ = try RemoteCatalogDocument.decode(JSONEncoder().encode(schemaOne)) }
        var unknownBank = try #require(try JSONSerialization.jsonObject(with: data(doc)) as? [String: Any])
        var banks = try #require(unknownBank["banks"] as? [[String: Any]])
        banks[0]["unexpected"] = true; unknownBank["banks"] = banks
        #expect(throws: (any Error).self) {
            _ = try RemoteCatalogDocument.decode(JSONSerialization.data(withJSONObject: unknownBank))
        }
    }

    @Test func offerPersonalStateIsIsolatedBetweenDifferentCards() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let first = try #require(BankLibrary.load().products.first { $0.id == "bochk.chill.platinum" })
        let second = try #require(BankLibrary.load().products.first { $0.id == "bochk.go.diamond" })
        let cardA = BankCard(bank: "BOCHK", name: "First card")
        cardA.catalogID = first.id; context.insert(cardA)
        let cardB = BankCard(bank: "BOCHK", name: "Second card")
        cardB.catalogID = second.id; context.insert(cardB)
        let offerA = try #require(OfferStore.offers(for: cardA, context: context).first { $0.origin == .official && !$0.isWelcome })
        let offerID = try #require(offerA.catalogRule?.id)
        try OfferStateStore.setHidden(true, cardKey: cardA.overlayKey, cardID: cardA.id, offerID: offerID,
                                      legacy: nil, in: context)

        let reloadedA = try #require(OfferStore.offers(for: cardA, context: context).first { $0.catalogRule?.id == offerID })
        #expect(reloadedA.isHidden)
        #expect(cardA.overlayKey != cardB.overlayKey)
        let reloadedB = try #require(OfferStore.offers(for: cardB, context: context).first { $0.origin == .official && !$0.isWelcome })
        #expect(!reloadedB.isHidden)
    }

    @Test func welcomeTrackingMigratesReadOnlyAndNewOffersSaveIndependently() throws {
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let product = try #require(BankLibrary.load().products.first { $0.id == "bochk.chill.platinum" })
        let welcomeRuleID = try #require(product.welcomePlans.first?.ruleIDs.first)
        let card = BankCard(bank: "BOCHK", name: "Welcome copy")
        card.catalogID = product.id; context.insert(card)
        let legacy = RewardRule(name: "Legacy welcome", kind: "welcome", card: card,
                                startsOn: try CatalogImporter.date("2026-09-01"), endsOn: try CatalogImporter.date("2026-12-31"))
        legacy.externalID = welcomeRuleID
        context.insert(legacy)
        var old = try WelcomeTrackingStore.load(rule: legacy, context: context)
        old.status = .achieved; old.notes = "Old personal note"
        try WelcomeTrackingStore.save(old, rule: legacy, context: context)

        let info = try #require(OfferStore.offers(for: card, context: context).first { $0.isWelcome && $0.catalogRule?.id == welcomeRuleID })
        let migrated = try OfferTrackingStore.load(for: info, context: context)
        #expect(migrated.status == .achieved)
        #expect(migrated.notes == "Old personal note")
        #expect(try DocumentStore.load(WelcomeTracking.self, key: info.trackingKey, in: context) == nil)

        var updated = migrated; updated.status = .received; updated.notes = "New overlay note"
        try OfferTrackingStore.save(updated, for: info, context: context)
        #expect(try OfferTrackingStore.load(for: info, context: context) == updated)
        #expect(try WelcomeTrackingStore.load(rule: legacy, context: context).notes == "Old personal note")
    }
    @Test func sameVersionWithDifferentBytesIsRejectedAndKeepsCache() async throws {
        let cache = temporaryCache(), first = try document(version: 3, rate: 4)
        try cache.save(document: first, data: try data(first),
                       metadata: CatalogCacheMetadata(etag: "\"v3\"", contentVersion: 3, publishedAt: "2026-10-23"))
        let changed = try document(version: 3, rate: 5)
        StubCatalogURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
             try! self.data(changed))
        }
        let repository = CatalogRepository(endpoint: endpoint, session: session(), cache: cache)
        await repository.check(force: true)
        if case .invalidData(let message) = repository.phase {
            #expect(message.contains("版本号未更新"))
        } else { Issue.record("expected invalid-data phase") }
        #expect(cache.loadDocument()?.document.contentVersion == 3)
        #expect(cache.loadDocument()?.document.products.first?.catalog.rules.first?.ratePercent == 4)
    }

    @Test func networkFailureDoesNotMakeFailTimeLookSuccessful() async throws {
        let cache = temporaryCache()
        StubCatalogURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let repository = CatalogRepository(endpoint: endpoint, session: session(), cache: cache)
        await repository.check(force: true)
        if case .networkUnavailable = repository.phase {} else { Issue.record("expected network phase") }
        #expect(repository.lastFailureAt != nil)
        #expect(repository.lastSuccessAt == nil)
        #expect(repository.isUsingBundled)
        #expect(repository.cacheSourceText == "App 内置资料")
    }

    @Test func oneSidedOfficialDatesAreNotTreatedAsUnknown() throws {
        let card = BankCard(bank: "BOCHK", name: "Date copy")
        func info(starts: String?, ends: String?) throws -> BenefitInfo {
            var rule = CatalogRule(id: UUID().uuidString, name: "Dates", kind: "cashback", group: "limited",
                                   startsOn: starts, endsOn: ends, sourceURL: "https://example.com/official")
            rule.capPeriod = "campaign"
            let catalog = CatalogCard(id: "date.test", bank: "BOCHK", name: "Date product", network: "Visa",
                                      sourceURL: "https://example.com/official", verifiedOn: "2026-10-23", rules: [rule])
            let product = CardProduct(bankID: "bochk", catalog: catalog, artwork: asset("images/cards/bochk-chill-platinum.png"),
                                      baseRewardVerified: false, welcomePlans: [], searchTerms: [])
            return BenefitInfo(official: rule, product: product, card: card, state: OfferPersonalState())
        }
        let ended = try info(starts: nil, ends: "2026-01-01")
        #expect(ended.hasKnownStart == false)
        #expect(ended.hasKnownEnd)
        #expect(ended.isEnded)
        #expect(ended.periodStatus == .ended)
        let future = try info(starts: "2027-01-01", ends: nil)
        #expect(future.hasKnownStart)
        #expect(future.hasKnownEnd == false)
        #expect(future.isNotStarted)
        #expect(future.periodStatus == .notStarted)
    }

    @Test func delistedProductStaysAvailableForHeldCardButNotForAdding() throws {
        let cache = temporaryCache(), doc = try document(version: 4)
        try cache.save(document: doc, data: try data(doc), metadata: CatalogCacheMetadata(contentVersion: 4, publishedAt: "2026-10-23"))
        BankLibrary.invalidate()
        let library = try BankLibrary.load(remoteCache: cache)
        #expect(library.products.map(\.id) == ["remote.test"])
        #expect(library.retiredProducts.contains { $0.id == "bochk.chill.platinum" })
        let container = try Persistence.makeContainer(inMemory: true), context = container.mainContext
        let card = BankCard(bank: "BOCHK", name: "Held delisted")
        card.catalogID = "bochk.chill.platinum"; context.insert(card)
        let offers = OfferStore.offers(for: card, context: context)
        #expect(!offers.isEmpty)
        #expect(offers.allSatisfy { $0.isHistorical })
        BankLibrary.invalidate()
    }

}
