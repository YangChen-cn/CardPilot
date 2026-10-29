import Foundation
import Testing
@testable import CardPilot

@Suite @MainActor
struct CardUsageGuideTests {
    @Test func bundledProductsExposeOneHolisticGuideEach() throws {
        let document = try BankLibrary.loadBundledSnapshot().document
        let guides = document.cardProducts.compactMap(\.usageGuide)
        #expect(!guides.isEmpty)
        #expect(guides.allSatisfy { $0.scenarios.count == 1 })
    }

    private func scenario() -> [String: Any] {
        ["id": "example.mobile", "title": "示例场景", "whenToUse": "示例消费条件",
         "howToUse": "按官方条款选择支付方式", "capNote": "上限须按官方条款核实",
         "stopAfter": "达到所述上限后比较其他卡", "warnings": ["不判断个人剩余额度"],
         "relatedOfferIDs": ["example.offer"], "sourceURLs": ["https://example.test/terms"],
         "startsOn": "2026-10-01", "endsOn": "2026-12-31"]
    }

    private func guide(_ scenario: [String: Any]? = nil) -> [String: Any] {
        ["summary": "仅供测试的用卡参考", "reviewedOn": "2026-10-29", "scenarios": [scenario ?? self.scenario()]]
    }

    private func decode(_ guide: Any?) throws -> RemoteCatalogDocument {
        let rule = CatalogRule(id: "example.offer", name: "Example offer", kind: "cashback", group: "daily",
                               startsOn: nil, endsOn: nil,
                               sourceURL: "https://example.test/terms")
        let card = CatalogCard(id: "example.card", bank: "Example Bank", name: "Example Card", network: "Visa",
                               sourceURL: "https://example.test/product", verifiedOn: "2026-10-29", rules: [rule])
        let product = RemoteCatalogProduct(id: card.id, bankID: "example", artwork: nil,
                                           baseRewardVerified: false, welcomePlans: [], catalog: card, searchTerms: [])
        let document = RemoteCatalogDocument(schemaVersion: 2, contentVersion: 1, publishedAt: "2026-10-29",
            banks: [RemoteCatalogBank(id: "example", name: "Example Bank", shortName: "Example", logo: nil, searchTerms: [])],
            products: [product])
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        var products = try #require(root["products"] as? [[String: Any]])
        products[0]["usageGuide"] = guide
        root["products"] = products
        return try RemoteCatalogDocument.decode(JSONSerialization.data(withJSONObject: root))
    }

    @Test(arguments: [false, true])
    func missingOrNullGuideKeepsOldCatalogReadable(explicitNull: Bool) throws {
        let document = try decode(explicitNull ? NSNull() : nil)
        #expect(document.products.first?.usageGuide == nil)
        #expect(document.cardProducts.first?.usageGuide == nil)
        try BankLibrary.validateRemote(document)
    }

    @Test func guideSurvivesProjectionAndOfflineCache() throws {
        let document = try decode(guide())
        try BankLibrary.validateRemote(document)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = RemoteCatalogCache(directory: directory)
        try cache.save(document: document, data: JSONEncoder().encode(document), metadata: CatalogCacheMetadata())
        let value = try #require(cache.loadSnapshot()?.document.cardProducts.first?.usageGuide)
        #expect(value.summary == "仅供测试的用卡参考")
        #expect(value.scenarios.first?.stopAfter == "达到所述上限后比较其他卡")
        #expect(value.scenarios.first?.relatedOfferIDs == ["example.offer"])
        #expect(value.scenarios.first?.sourceURLs == ["https://example.test/terms"])
    }

    @Test func optionalDetailsAndDatesCanRemainUnknown() throws {
        var item = scenario()
        for key in ["capNote", "stopAfter", "warnings", "startsOn", "endsOn"] { item[key] = NSNull() }
        item["relatedOfferIDs"] = [] as [String]
        let value = try #require(decode(guide(item)).cardProducts.first?.usageGuide?.scenarios.first)
        #expect(value.capNote == nil && value.stopAfter == nil)
        #expect(value.periodDescription() == "有效期未列明")
    }

    @Test(arguments: ["multipleStrategies", "duplicateID", "missingOffer", "wrongType", "insecureURL", "credentials", "invalidDate",
                      "reversedDates", "unknownField", "emptySummary", "emptyScenarios", "tooManyScenarios", "longText"])
    func invalidGuidesAreRejected(problem: String) throws {
        var item = scenario()
        var value = guide()
        switch problem {
        case "multipleStrategies":
            var other = item; other["id"] = "example.other"
            value["scenarios"] = [item, other]
        case "duplicateID": value["scenarios"] = [item, item]
        case "missingOffer": item["relatedOfferIDs"] = ["another.card.offer"]
        case "wrongType": item["stopAfter"] = 2000
        case "insecureURL": item["sourceURLs"] = ["http://example.test/terms"]
        case "credentials": item["sourceURLs"] = ["https://secret@example.test/terms"]
        case "invalidDate": item["endsOn"] = "2026-02-30"
        case "reversedDates": item["endsOn"] = "2026-09-01"
        case "unknownField": item["stopAmount"] = 2000
        case "emptySummary": value["summary"] = "  \n"
        case "emptyScenarios": value["scenarios"] = [] as [[String: Any]]
        case "tooManyScenarios": value["scenarios"] = Array(repeating: item, count: 2)
        default: item["howToUse"] = String(repeating: "x", count: 221)
        }
        if !["multipleStrategies", "duplicateID", "emptySummary", "emptyScenarios", "tooManyScenarios"].contains(problem) {
            value["scenarios"] = [item]
        }
        #expect(throws: (any Error).self) { try decode(value) }
    }

    @Test func knownExpiryIsInclusiveAndFutureIsNotPresentedAsActive() throws {
        let value = try #require(decode(guide()).cardProducts.first?.usageGuide?.scenarios.first)
        #expect(value.periodDescription(on: try CatalogImporter.date("2026-09-30")) == "尚未开始 · 2026-10-01")
        #expect(value.periodDescription(on: try CatalogImporter.date("2026-12-31")) == "2026-10-01 至 2026-12-31")
        #expect(value.periodDescription(on: try CatalogImporter.date("2027-01-01")) == "已结束 · 2026-12-31")
    }
}
