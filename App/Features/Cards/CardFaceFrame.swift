import SwiftUI

/// A stable card-shaped stage for artwork with different source proportions.
///
/// The artwork is never cropped. A subtle system surface fills the unused area
/// so portrait card images no longer leave an accidental white gap, while every
/// card row keeps the same visual rhythm.
struct CardFaceFrame<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PilotTheme.cardCornerRadius, style: .continuous)
                .fill(PilotTheme.cardBackdrop)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(PilotTheme.cardAspectRatio, contentMode: .fit)
        .clipShape(.rect(cornerRadius: PilotTheme.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PilotTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.06))
        }
        .accessibilityHidden(true)
    }
}

/// Shared card artwork presentation for the wallet list and compact rows.
struct WalletCardFace: View {
    let card: BankCard

    var body: some View {
        CardFaceFrame {
            CardArtwork(card: card, compact: true)
        }
    }
}
