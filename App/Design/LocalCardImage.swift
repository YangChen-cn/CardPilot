import SwiftUI

struct LocalCardImage: View {
    let data: Data
    @State private var asset: CardImageAsset?
    @State private var failed = false

    var body: some View {
        Group {
            if let asset {
                Image(decorative: asset.image, scale: 1)
                    .resizable()
                    .aspectRatio(asset.aspectRatio, contentMode: .fit)
            } else if failed {
                ContentUnavailableView("卡面暂不可用", systemImage: "creditcard")
            } else {
                Color.clear.aspectRatio(1.586, contentMode: .fit)
                    .overlay { ProgressView().controlSize(.small) }
            }
        }
        .accessibilityLabel("官方卡面")
        .task(id: data) { await load() }
    }

    private func load() async {
        asset = nil; failed = false
        do {
            let image = try await CardImageStore.shared.image(for: data)
            guard !Task.isCancelled else { return }
            asset = image; failed = image == nil
        } catch { }
    }
}
