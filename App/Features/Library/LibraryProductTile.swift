import SwiftUI

struct LibraryProductTile: View {
    let product: CardProduct
    var transition: Namespace.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LibraryProductArtwork(product: product)
                .aspectRatio(PilotTheme.cardAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .cardTransitionSource(id: product.id, in: transition)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline) {
                Text(product.catalog.name).font(.headline)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            Text(product.catalog.network + " · " + CardKind.normalized(product.catalog.kind ?? "").label).font(.subheadline).foregroundStyle(.secondary)
            if product.baseRewardVerified, let rate = product.catalog.baseRatePercent {
                Text(rate.formatted(.number.precision(.fractionLength(0...2))) + "% 基础回赠")
                    .font(.subheadline).foregroundStyle(PilotTheme.accent)
            } else {
                Text("基础回赠待核实").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(PilotTheme.spacing)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(.rect)
    }
}
