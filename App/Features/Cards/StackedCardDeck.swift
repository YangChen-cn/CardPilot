import SwiftUI

/// A Wallet-like deck for iPhone. The front card opens its detail; the other
/// cards stay reachable by swiping, tapping their exposed edge, or using the
/// position controls. The deck only changes presentation, never card order.
struct StackedCardDeck: View {
    let cards: [BankCard]
    let transition: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frontKey: String?
    @State private var dragOffset: CGFloat = 0
    @State private var feedback = 0

    private var count: Int { cards.count }

    // A stable identity is the single source of selection. When filtering or
    // deleting cards, a numeric index can be stale before onChange runs.
    private var frontIndex: Int {
        guard let frontKey else { return 0 }
        return cards.firstIndex { $0.syncKey == frontKey } ?? 0
    }

    private var visibleIndices: [Int] {
        guard count > 0 else { return [] }
        return (0..<count).filter { depth(for: $0) < 4 }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                ForEach(visibleIndices, id: \.self) { index in
                    layer(index)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 32)
            .padding(.bottom, 8)
            .offset(x: reduceMotion ? 0 : dragOffset * 0.08)
            .contentShape(.rect)
            .simultaneousGesture(dragGesture)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("叠放卡包，\(count) 张卡")
            .accessibilityValue(frontCard.map { "当前 \($0.name)，第 \(frontIndex + 1) 张，共 \(count) 张" } ?? "")
            .accessibilityAction(named: "下一张") { advance(by: 1) }
            .accessibilityAction(named: "上一张") { advance(by: -1) }

            if count > 1 {
                // Keep a constant-width control group even with a large wallet.
                // Every action remains a full touch target; no tiny compressed dots.
                HStack(spacing: 16) {
                    Button { advance(by: -1) } label: {
                        Label("上一张", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PilotTheme.accent)
                    Text("\(frontIndex + 1) / \(count)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("第 \(frontIndex + 1) 张，共 \(count) 张")
                    Button { advance(by: 1) } label: {
                        Label("下一张", systemImage: "chevron.right")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PilotTheme.accent)
                }
                .frame(maxWidth: .infinity)
                .sensoryFeedback(.selection, trigger: feedback)
            }
        }
        .onAppear { frontKey = frontCard?.syncKey }
        .onChange(of: cards.map(\.syncKey)) { _, _ in
            dragOffset = 0
            if !cards.contains(where: { $0.syncKey == frontKey }) {
                frontKey = cards.first?.syncKey
            }
        }
    }

    private var frontCard: BankCard? {
        guard count > 0 else { return nil }
        return cards[min(frontIndex, count - 1)]
    }

    private func depth(for index: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index - frontIndex + count) % count
    }

    @ViewBuilder
    private func layer(_ index: Int) -> some View {
        let card = cards[index]
        let depth = depth(for: index)
        let base = WalletCardFace(card: card)
            .scaleEffect(1 - CGFloat(depth) * 0.035)
            .offset(y: -CGFloat(depth) * 10)
            .accessibilityHidden(depth != 0)

        Group {
            if depth == 0 {
                NavigationLink {
                    WalletCardDestination(card: card, transition: transition)
                } label: {
                    base
                        .matchedTransitionSource(id: card.id, in: transition)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(card.name)，打开卡片详情")
            } else {
                Button { select(index) } label: {
                    base
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(card.name)，移到最前")
            }
        }
        .zIndex(Double(-depth))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard !reduceMotion,
                      abs(value.translation.width) > abs(value.translation.height) else {
                    dragOffset = 0
                    return
                }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                defer { dragOffset = 0 }
                guard abs(value.translation.width) > 44,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                advance(by: value.translation.width < 0 ? 1 : -1)
            }
    }

    private func advance(by step: Int) {
        guard count > 1 else { return }
        let index = (frontIndex + step + count) % count
        select(index)
    }

    private func select(_ index: Int) {
        guard cards.indices.contains(index), index != frontIndex else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            frontKey = cards[index].syncKey
        }
        feedback &+= 1
    }

}
