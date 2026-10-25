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
    @State private var deckWidth: CGFloat = 0
    @State private var isHorizontalDragging = false
    @State private var isSwitching = false
    @State private var openedCard: BankCard?
    @State private var switchTask: Task<Void, Never>?
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
            .contentShape(.rect)
            .simultaneousGesture(dragGesture)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { deckWidth = $0 }
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

            if let card = frontCard {
                DeckCardSummary(card: card)
                    .id(card.id)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .onAppear { frontKey = frontCard?.syncKey }
        .onChange(of: cards.map(\.syncKey)) { _, _ in
            switchTask?.cancel()
            isSwitching = false
            isHorizontalDragging = false
            dragOffset = 0
            if !cards.contains(where: { $0.syncKey == frontKey }) {
                frontKey = cards.first?.syncKey
            }
        }
        .onDisappear {
            switchTask?.cancel()
        }
        .navigationDestination(isPresented: Binding(
            get: { openedCard != nil },
            set: { if !$0 { openedCard = nil } }
        )) {
            if let openedCard {
                WalletCardDestination(card: openedCard, transition: transition)
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

    private func open(_ card: BankCard) {
        guard !isHorizontalDragging, !isSwitching else { return }
        openedCard = card
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
                base
                    .offset(x: dragOffset)
                    .matchedTransitionSource(id: card.id, in: transition)
                    .onTapGesture { open(card) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(card.name)，打开卡片详情")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: "打开卡片详情") { open(card) }
            } else {
                Button { select(index) } label: {
                    base
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!isHorizontalDragging)
                .accessibilityLabel("\(card.name)，移到最前")
            }
        }
        .zIndex(Double(-depth))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !reduceMotion, !isSwitching else { return }
                let horizontal = abs(value.translation.width) > abs(value.translation.height)
                if horizontal {
                    isHorizontalDragging = true
                    dragOffset = value.translation.width
                } else if isHorizontalDragging {
                    isHorizontalDragging = false
                    dragOffset = 0
                }
            }
            .onEnded { value in
                let wasHorizontal = isHorizontalDragging
                isHorizontalDragging = false
                guard !reduceMotion, !isSwitching, wasHorizontal else {
                    dragOffset = 0
                    return
                }
                let threshold = max(56, deckWidth * 0.18)
                let projected = value.predictedEndTranslation.width
                guard abs(value.translation.width) > threshold || abs(projected) > threshold * 2 else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                    return
                }
                commitSwipe(direction: value.translation.width < 0 ? 1 : -1)
            }
    }

    private func commitSwipe(direction: Int) {
        guard count > 1, !isSwitching else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { dragOffset = 0 }
            return
        }
        let nextIndex = (frontIndex + direction + count) % count
        if reduceMotion {
            select(nextIndex)
            dragOffset = 0
            return
        }
        let width = max(deckWidth, 320)
        let exitOffset = direction > 0 ? -width : width
        isSwitching = true
        switchTask?.cancel()
        // Only the front card leaves. The next card is already visible behind
        // it and becomes the full-size front once the old card is out of view.
        withAnimation(.easeIn(duration: 0.18)) {
            dragOffset = exitOffset
        }
        switchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, cards.indices.contains(nextIndex) else {
                isSwitching = false
                dragOffset = 0
                return
            }
            // The old front is already offscreen. Do not animate the shared
            // drag offset onto the incoming card, or the second-next card is
            // briefly exposed while the incoming card springs in from the edge.
            withTransaction(Transaction(animation: nil)) {
                dragOffset = 0
                frontKey = cards[nextIndex].syncKey
            }
            feedback &+= 1
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            isSwitching = false
        }
    }

    private func advance(by step: Int) {
        guard count > 1, !isSwitching else { return }
        let index = (frontIndex + step + count) % count
        select(index)
    }

    private func select(_ index: Int) {
        guard cards.indices.contains(index), index != frontIndex else { return }
        switchTask?.cancel()
        isSwitching = false
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            frontKey = cards[index].syncKey
            dragOffset = 0
        }
        feedback &+= 1
    }

}
