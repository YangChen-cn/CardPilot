import SwiftUI

/// Resolves a catalog asset through the disk/memory cache and keeps the
/// placeholder visible while the image is unavailable.
struct CatalogAssetImage<Content: View, Placeholder: View>: View {
    let asset: CatalogAsset?
    @ViewBuilder let content: (CardImageAsset) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @Environment(CatalogRepository.self) private var catalog
    @State private var image: CardImageAsset?
    @State private var loading = false

    init(asset: CatalogAsset?,
         @ViewBuilder content: @escaping (CardImageAsset) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.asset = asset
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                content(image)
            } else {
                placeholder().overlay {
                    if loading { ProgressView().controlSize(.small) }
                }
            }
        }
        .task(id: "\(asset?.sha256 ?? "none"):\(catalog.assetRetryToken)") {
            await load()
        }
    }

    private func load() async {
        image = nil
        guard let asset else { return }
        loading = true
        defer { loading = false }
        image = await CatalogAssetStore.shared.image(for: asset, baseURL: catalog.assetBaseURL)
    }
}
