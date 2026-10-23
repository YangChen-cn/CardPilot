import SwiftUI

/// Resolves a catalog asset through the disk/memory cache and keeps the
/// placeholder visible while the image is unavailable.
struct CatalogAssetImage<Content: View, Placeholder: View>: View {
    let asset: CatalogAsset?
    @ViewBuilder let content: (CardImageAsset) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @Environment(CatalogRepository.self) private var catalog
    @State private var image: CardImageAsset?
    @State private var displayedHash: String?
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
        guard let asset else {
            image = nil
            displayedHash = nil
            loading = false
            return
        }
        // A catalog check is only a retry signal for missing images. Keeping
        // a successfully decoded hash avoids flashing every card's placeholder.
        guard image == nil || displayedHash != asset.sha256 else { return }
        if displayedHash != asset.sha256 {
            image = nil
            displayedHash = nil
        }
        loading = true
        defer { if !Task.isCancelled { loading = false } }
        let loaded = await CatalogAssetStore.shared.image(for: asset, baseURL: catalog.assetBaseURL)
        guard !Task.isCancelled else { return }
        image = loaded
        displayedHash = loaded == nil ? nil : asset.sha256
    }
}
