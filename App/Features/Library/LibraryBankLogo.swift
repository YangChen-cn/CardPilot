import SwiftUI

struct LibraryBankLogo: View {
    let asset: CatalogAsset?

    var body: some View {
        CatalogAssetImage(asset: asset) { image in
            Image(decorative: image.image, scale: 1)
                .resizable()
                .aspectRatio(image.aspectRatio, contentMode: .fit)
        } placeholder: {
            Image(systemName: "building.columns")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
