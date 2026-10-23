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
            GeometryReader { proxy in
                ZStack {
                    // Official card art is not always landscape. A muted
                    // version of the same face keeps portrait cards from
                    // floating in an unrelated empty panel.
                    CardArtwork(card: card, compact: true)
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .blur(radius: 20)
                        .saturation(1.15)
                        .opacity(0.58)
                        .overlay {
                            LinearGradient(
                                colors: [.black.opacity(0.12), .clear, .black.opacity(0.12)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                    CardArtwork(card: card, compact: true)
                        .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                }
            }
        }
    }
}
