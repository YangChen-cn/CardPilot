import SwiftUI

#if os(iOS)
struct PhoneWalletCarousel: View {
    let cards: [BankCard]
    @Binding var selectedKey: String?
    let transition: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedIndex: Int {
        cards.firstIndex { $0.syncKey == selectedKey } ?? 0
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(cards) { card in
                        NavigationLink {
                            WalletCardDestination(card: card, transition: transition)
                        } label: {
                            CardArtwork(card: card, compact: true)
                                // Artwork is decorative; readable card metadata below
                                // follows Dynamic Type without changing image proportions.
                                .environment(\.dynamicTypeSize, .medium)
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)
                                .padding(8)
                                .contentShape(.rect)
                                .matchedTransitionSource(id: card.id, in: transition)
                        }
                        .buttonStyle(WalletCardButtonStyle())
                        .accessibilityLabel(card.displayName)
                        .accessibilityHint("查看这张卡的权益与详情")
                        .containerRelativeFrame(.horizontal)
                        .id(card.syncKey)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedKey)
            if cards.count > 1 {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.and.right").accessibilityHidden(true)
                    Text("\(selectedIndex + 1) / \(cards.count)").monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minHeight: PilotTheme.minimumTouchTarget)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("切换精选卡片")
                .accessibilityValue("第 \(selectedIndex + 1) 张，共 \(cards.count) 张")
                .accessibilityAdjustableAction { direction in
                    let next: Int
                    switch direction {
                    case .increment: next = min(selectedIndex + 1, cards.count - 1)
                    case .decrement: next = max(selectedIndex - 1, 0)
                    @unknown default: return
                    }
                    withAnimation(reduceMotion ? nil : .snappy) { selectedKey = cards[next].syncKey }
                }
            }
        }
    }
}
#endif
