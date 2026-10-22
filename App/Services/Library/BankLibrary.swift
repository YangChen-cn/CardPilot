import Foundation

struct BankLibrary: Sendable {
    let banks: [LibraryBank]
    /// Products that the current valid official snapshot allows users to add.
    let products: [CardProduct]
    /// Products that were present in the bundled catalog but are no longer in
    /// the current official snapshot. They remain available for held cards so
    /// personal history is never lost.
    let retiredProducts: [CardProduct]

    init(banks: [LibraryBank], products: [CardProduct], retiredProducts: [CardProduct] = []) {
        self.banks = banks
        self.products = products
        self.retiredProducts = retiredProducts
    }
    @MainActor private static var cached: BankLibrary?
    @MainActor private static var images: [String: Data] = [:]
    private static let bankDefinitions = [
        LibraryBank(id: "hsbc", name: "HSBC 汇丰银行", shortName: "HSBC", logoResource: "hsbc-logo.png"),
        LibraryBank(id: "bochk", name: "BOCHK 中银香港", shortName: "BOCHK", logoResource: "bochk-logo.png"),
        LibraryBank(id: "bea", name: "BEA 东亚银行", shortName: "BEA", logoResource: "bea-logo.png"),
        LibraryBank(id: "cncbi", name: "CNCBI 信银国际", shortName: "CNCBI", logoResource: "cncbi-logo.png")
    ]

    func products(for bankID: String) -> [CardProduct] { products.filter { $0.bankID == bankID } }

    /// Looks up both current and retired products. Held cards keep their
    /// official details even after a product is removed from the addable list.
    func product(id: String) -> CardProduct? {
        products.first(where: { $0.id == id }) ?? retiredProducts.first(where: { $0.id == id })
    }

    @MainActor static func load() throws -> BankLibrary {
        try load(remoteCache: RuntimeMode.isTesting ? nil : .application)
    }

    /// Tests can supply an isolated cache; production callers use `load()`.
    @MainActor static func load(remoteCache: RemoteCatalogCache?) throws -> BankLibrary {
        if let cached { return cached }
        let bundled = try loadBundled()
        let library: BankLibrary
        if let cachedDocument = remoteCache?.loadDocument() {
            // A corrupt or incompatible cache must never prevent the bundled
            // fallback from opening the app.
            library = (try? merged(bundled, with: cachedDocument.document)) ?? bundled
        } else {
            library = bundled
        }
        cached = library
        return library
    }

    @MainActor static func invalidate() {
        cached = nil
    }

    nonisolated static func validateRemote(_ document: RemoteCatalogDocument) throws {
        let bankIDs = Set(bankDefinitions.map(\.id))
        for product in document.cardProducts { try validate(product, bankIDs: bankIDs) }
    }

    @MainActor private static func loadBundled() throws -> BankLibrary {
        let banks = bankDefinitions
        let decoder = JSONDecoder()
        var products: [CardProduct] = [], packages: [String: CatalogPackage] = [:]
        let bankIDs = Set(banks.map(\.id))
        for file in ["hsbc-products.json", "bochk-bea-products.json", "cncbi-products.json"] {
            guard let data = resourceData(file) else { throw PilotError.invalid("暂时无法读取银行卡资料库，请重新打开 App。") }
            let manifest = try decoder.decode(LibraryManifest.self, from: data)
            for definition in manifest.products {
                guard bankIDs.contains(definition.bankID), !products.contains(where: { $0.id == definition.id }) else {
                    throw PilotError.invalid("银行卡资料库含重复或不支持的产品。")
                }
                if packages[definition.catalogResource] == nil {
                    guard let data = resourceData(definition.catalogResource + ".json") else { throw PilotError.invalid("缺少银行卡产品资料。") }
                    packages[definition.catalogResource] = try CatalogImporter.decode(data)
                }
                guard let card = packages[definition.catalogResource]?.cards.first(where: { $0.id == definition.id }) else {
                    throw PilotError.invalid("找不到银行卡产品资料。")
                }
                let product = CardProduct(bankID: definition.bankID, catalog: card, imageResource: definition.imageResource,
                                          baseRewardVerified: definition.baseRewardVerified, welcomePlans: definition.welcomePlans)
                try validate(product, bankIDs: bankIDs)
                products.append(product)
            }
        }
        let library = BankLibrary(banks: banks, products: products)
        cached = library
        return library
    }

    nonisolated private static func merged(_ bundled: BankLibrary, with document: RemoteCatalogDocument) throws -> BankLibrary {
        let bankIDs = Set(bundled.banks.map(\.id))
        let products = document.cardProducts
        for product in products { try validate(product, bankIDs: bankIDs) }
        let currentIDs = Set(products.map(\.id))
        let retired = bundled.products.filter { !currentIDs.contains($0.id) }
        return BankLibrary(banks: bundled.banks, products: products, retiredProducts: retired)
    }

    nonisolated static func validate(_ product: CardProduct, bankIDs: Set<String>) throws {
        guard bankIDs.contains(product.bankID), product.id == product.catalog.id else {
            throw PilotError.invalid("银行卡产品与银行资料不一致。")
        }
        _ = try CatalogImporter.decode(JSONEncoder().encode(CatalogPackage(schemaVersion: 1, cards: [product.catalog])))
        for plan in product.welcomePlans {
            try CatalogImporter.validateHTTPS(plan.sourceURL)
            if let start = plan.applicationStartsOn { _ = try CatalogImporter.date(start) }
            if let end = plan.applicationEndsOn { _ = try CatalogImporter.date(end) }
            if let start = plan.applicationStartsOn, let end = plan.applicationEndsOn,
               try CatalogImporter.date(start) > CatalogImporter.date(end) { throw PilotError.invalid("迎新申请期无效。") }
            guard !plan.id.isEmpty, !plan.title.isEmpty, ["main", "addon"].contains(plan.kind),
                  Set(plan.ruleIDs).count == plan.ruleIDs.count,
                  plan.ruleIDs.allSatisfy({ id in product.catalog.rules.contains { $0.id == id && $0.kind == "welcome" } }) else {
                throw PilotError.invalid("迎新方案与卡片资料不一致。")
            }
        }
        guard Set(product.welcomePlans.map(\.id)).count == product.welcomePlans.count else {
            throw PilotError.invalid("迎新方案标识重复。")
        }
        guard let image = resourceData(product.imageResource) else { throw PilotError.invalid("缺少银行卡卡面。") }
        try CatalogImporter.validateImage(image)
    }

    @MainActor static func imageData(resource: String) -> Data? {
        if let data = images[resource] { return data }
        guard let data = resourceData(resource) else { return nil }
        images[resource] = data
        return data
    }

    static func resourceData(_ resource: String) -> Data? {
        let name = (resource as NSString).deletingPathExtension, ext = (resource as NSString).pathExtension
        let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "BankLibrary") ??
                  Bundle.main.url(forResource: name, withExtension: ext)
        return url.flatMap { try? Data(contentsOf: $0) }
    }
}
