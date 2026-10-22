import SwiftUI

struct BankProductsView: View {
    let bank: LibraryBank
    let products: [CardProduct]
    let onFinish: () -> Void
    @State private var search = ""

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
                    } label: {
                        LibraryProductTile(product: product)
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
    }
}
