import SwiftUI

/// A Wallet-like deck for iPhone. The front card opens its detail; the other
/// cards stay reachable by swiping, tapping their exposed edge, or using the
/// page controls. The deck only changes presentation, never card order.
struct StackedCardDeck: View {
    let cards: [BankCard]
    let transition: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frontIndex = 0
    @State private var frontKey: String?
    @State private var dragOffset: CGFloat = 0
    @State private var feedback = 0

    private var count: Int { cards.count }

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
            .offset(x: dragOffset * 0.08)
            .contentShape(.rect)
            .gesture(dragGesture)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("叠放卡包，\(count) 张卡")
            .accessibilityValue(frontCard.map { "当前 \($0.name)，第 \(frontIndex + 1) 张，共 \(count) 张" } ?? "")
            .accessibilityAction(named: "下一张") { advance(by: 1) }
            .accessibilityAction(named: "上一张") { advance(by: -1) }

            if count > 1 {
                HStack(spacing: 0) {
                    ForEach(cards.indices, id: \.self) { index in
                        pageDot(index)
                    }
                }
                .frame(maxWidth: .infinity)
                .sensoryFeedback(.selection, trigger: feedback)
                .accessibilityLabel("卡片位置")
            }
        }
        .onAppear { frontKey = frontCard?.syncKey }
        .onChange(of: cards.map(\.syncKey)) { _, _ in
            if let frontKey, let index = cards.firstIndex(where: { $0.syncKey == frontKey }) {
                frontIndex = index
            } else {
                frontIndex = 0
                frontKey = cards.first?.syncKey
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: frontIndex)
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
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
                        frontIndex = index
                        frontKey = cards[index].syncKey
                    }
                    feedback &+= 1
                } label: {
                    base
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(card.name)，移到最前")
            }
        }
        .zIndex(Double(-depth))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                defer { dragOffset = 0 }
                guard abs(value.translation.width) > 44 else { return }
                advance(by: value.translation.width < 0 ? 1 : -1)
            }
    }

    private func advance(by step: Int) {
        guard count > 1 else { return }
        let index = (frontIndex + step + count) % count
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            frontIndex = index
            frontKey = cards[index].syncKey
        }
        feedback &+= 1
    }

    private func pageDot(_ index: Int) -> some View {
        let selected = index == frontIndex
        return Button {
            select(index)
        } label: {
            Capsule()
                .fill(selected ? PilotTheme.accent : Color.secondary.opacity(0.35))
                .frame(width: selected ? 18 : 6, height: 6)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("第 \(index + 1) 张，\(cards[index].name)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func select(_ index: Int) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            frontIndex = index
            frontKey = cards[index].syncKey
        }
        feedback &+= 1
    }

}
