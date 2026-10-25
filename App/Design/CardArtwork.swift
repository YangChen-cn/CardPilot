import SwiftUI

struct CardArtwork: View {
    let card: BankCard
    var compact = false
    var source: CardArtworkSource? = nil
    @Environment(CatalogRepository.self) private var catalog

    private var product: CardProduct? {
        guard !card.catalogID.isEmpty else { return nil }
        return (try? BankLibrary.load())?.product(id: card.catalogID)
    }

    var body: some View {
        let _ = catalog.revision
        let _ = card.modifiedAt
        Group {
            if (source ?? card.artworkSource) == .custom {
                if let data = card.imageData, !data.isEmpty {
                    LocalCardImage(data: data)
                } else {
                    ContentUnavailableView("自定义卡面暂不可用", systemImage: "photo")
                }
            } else if let product {
                CatalogAssetImage(asset: product.artwork) { image in
                    Image(decorative: image.image, scale: 1)
                        .resizable()
                        .aspectRatio(image.aspectRatio, contentMode: .fit)
                } placeholder: {
                    ProgrammaticCardFace(card: card, compact: compact)
                }
            } else {
                ProgrammaticCardFace(card: card, compact: compact)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: compact ? 8 : 14, y: compact ? 4 : 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.displayName)，\(card.network)\(card.lastFour.isEmpty ? "" : "，尾号" + card.lastFour)")
    }
}
