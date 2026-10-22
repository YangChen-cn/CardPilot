import SwiftUI

struct LibraryProductArtwork: View {
    let product: CardProduct
    @State private var data: Data?

    var body: some View {
        Group {
            if let data {
                LocalCardImage(data: data)
            } else {
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
        }
        .accessibilityLabel(product.catalog.name + "卡面")
        .task(id: product.imageResource) { data = BankLibrary.imageData(resource: product.imageResource) }
    }
}
