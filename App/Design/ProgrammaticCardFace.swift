import SwiftUI

struct ProgrammaticCardFace: View {
    let card: BankCard
    var compact = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var surface: Color { PilotTheme.color(card.theme).mix(with: .black, by: 0.64) }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                content.padding(PilotTheme.spacing + 4).frame(minHeight: 240).background(surface)
            } else {
                RoundedRectangle(cornerRadius: PilotTheme.radius)
                    .fill(surface)
                    .aspectRatio(1.586, contentMode: .fit)
                    .overlay { content.padding(PilotTheme.spacing + 4) }
            }
        }
        .foregroundStyle(.white)
        .clipShape(.rect(cornerRadius: PilotTheme.radius))
        .overlay { RoundedRectangle(cornerRadius: PilotTheme.radius).strokeBorder(.white.opacity(0.13)) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(card.bank).font(.subheadline).bold()
                Spacer(minLength: 8)
                Image(systemName: "wave.3.right").font(.subheadline).foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 12)
            Text(card.name).font(compact ? .title3 : .title2).bold().fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            HStack(alignment: .firstTextBaseline) {
                Text(card.lastFour.isEmpty ? card.kind : "••••  " + card.lastFour)
                    .font(.subheadline).monospacedDigit().foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 8)
                Text(card.network).font(.headline)
            }
        }
    }
}
