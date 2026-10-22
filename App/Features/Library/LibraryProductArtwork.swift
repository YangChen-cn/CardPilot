import SwiftUI

struct LibraryProductArtwork: View {
    let product: CardProduct

    var body: some View {
        CatalogAssetImage(asset: product.artwork) { image in
            Image(decorative: image.image, scale: 1)
                .resizable()
                .aspectRatio(image.aspectRatio, contentMode: .fit)
        } placeholder: {
            RoundedRectangle(cornerRadius: PilotTheme.radius)
                .fill(PilotTheme.accent.mix(with: .black, by: 0.66))
                .aspectRatio(1.586, contentMode: .fit)
                .overlay {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(product.catalog.bank).font(.subheadline)
                        Spacer(minLength: 12)
                        Text(product.catalog.name).font(.title3).bold()
                        HStack { Spacer(); Text(product.catalog.network).font(.headline) }
                    }
                    .padding(PilotTheme.spacing + 4)
                    .foregroundStyle(.white)
                }
        }
        .accessibilityLabel(product.catalog.name + "卡面")
    }
}
