import SwiftUI

struct BankProductsView: View {
    let bank: LibraryBank
    let onFinish: () -> Void
    @Environment(CatalogRepository.self) private var catalog
    @State private var products: [CardProduct]
    @State private var search = ""
    @State private var showingProducts = false
    @Namespace private var productTransition

    init(bank: LibraryBank, products: [CardProduct], onFinish: @escaping () -> Void) {
        self.bank = bank
        self.onFinish = onFinish
        _products = State(initialValue: products)
    }

    private var filtered: [CardProduct] {
        products.filter {
            search.isEmpty ||
            $0.catalog.name.localizedStandardContains(search) ||
            $0.catalog.network.localizedStandardContains(search) ||
            $0.searchKeywords.contains(where: { $0.localizedStandardContains(search) })
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 380), spacing: 24)], alignment: .leading, spacing: 24) {
                ForEach(filtered) { product in
                    NavigationLink {
                        CardProductPreviewView(product: product, onFinish: onFinish)
                            .pilotZoomTransition(sourceID: product.id, in: productTransition)
                    } label: {
                        LibraryProductTile(product: product, transition: productTransition)
                    }.buttonStyle(WalletCardButtonStyle())
                }
                if filtered.isEmpty { ContentUnavailableView.search }
            }
            .padding(PilotTheme.pagePadding)
            .frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .background(PilotTheme.canvas)
        .navigationTitle(bank.name)
        .searchable(text: $search, prompt: "搜索卡片")
        .onAppear { showingProducts = true; refreshProducts() }
        .onDisappear { showingProducts = false }
        .onChange(of: catalog.revision) { _, _ in
            if showingProducts { refreshProducts() }
        }
    }

    private func refreshProducts() {
        guard let library = try? BankLibrary.load() else { return }
        products = library.products(for: bank.id)
    }
}
