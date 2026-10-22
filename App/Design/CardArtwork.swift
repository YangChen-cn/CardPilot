import SwiftUI

struct CardArtwork: View {
    let card: BankCard
    var compact = false

    var body: some View {
        Group {
            if let data = card.imageData, !data.isEmpty {
                LocalCardImage(data: data)
            } else {
                ProgrammaticCardFace(card: card, compact: compact)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: compact ? 8 : 14, y: compact ? 4 : 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.displayName)，\(card.network)\(card.lastFour.isEmpty ? "" : "，尾号" + card.lastFour)")
    }
}
