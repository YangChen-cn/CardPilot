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

    var referencedArtworkHashes: Set<String> {
        var hashes = Set(banks.map { $0.logo.sha256 })
        for product in products { hashes.insert(product.artwork.sha256) }
        for product in retiredProducts { hashes.insert(product.artwork.sha256) }
        return hashes
    }

    func products(for bankID: String) -> [CardProduct] { products.filter { $0.bankID == bankID } }

    func bank(id: String) -> LibraryBank? { banks.first { $0.id == id } }

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
        let bankIDs = Set(document.banks.map(\.id))
        for product in document.cardProducts { try validate(product, bankIDs: bankIDs) }
    }

    @MainActor private static func loadBundled() throws -> BankLibrary {
        let urls = [
            Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "Catalog"),
            Bundle.main.url(forResource: "catalog", withExtension: "json")
        ].compactMap { $0 }
        guard let url = urls.first, let data = try? Data(contentsOf: url) else {
            throw PilotError.invalid("暂时无法读取银行卡资料库，请重新打开 App。")
        }
        let document = try RemoteCatalogDocument.decode(data)
        try validateRemote(document)
        let library = BankLibrary(banks: document.libraryBanks, products: document.cardProducts)
        cached = library
        return library
    }

    nonisolated private static func merged(_ bundled: BankLibrary, with document: RemoteCatalogDocument) throws -> BankLibrary {
        try validateRemote(document)
        let products = document.cardProducts
        let currentIDs = Set(products.map(\.id))
        let retired = bundled.products.filter { !currentIDs.contains($0.id) }
        return BankLibrary(banks: document.libraryBanks, products: products, retiredProducts: retired)
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
        try product.artwork.validate()
    }

}
