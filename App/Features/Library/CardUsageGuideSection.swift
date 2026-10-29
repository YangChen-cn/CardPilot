import SwiftUI

/// One entry per card, shown both in the library and directly in the wallet.
/// The preview opens the complete card-level guide without first navigating
/// through the detail page or an individual promotion.
struct CardUsageGuideSection: View {
    let guide: CardUsageGuide
    let productName: String
    var compact = false
    var showsProductName = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingGuide = false

    var body: some View {
        Button { showingGuide = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("推荐用法", systemImage: "lightbulb")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PilotTheme.accent)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                if showsProductName {
                    Text(productName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                }
                Text(guide.summary)
                    .font(compact ? .subheadline : .body)
                    .foregroundStyle(.primary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : (compact ? 2 : 3))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: PilotTheme.minimumTouchTarget, alignment: .leading)
            .contentShape(.rect)
            .pilotPanel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(productName + "的推荐用法：" + guide.summary)
        .accessibilityHint("直接打开这张卡的完整用卡指南")
        .sheet(isPresented: $showingGuide) {
            CardUsageGuideView(guide: guide, productName: productName)
        }
    }
}
