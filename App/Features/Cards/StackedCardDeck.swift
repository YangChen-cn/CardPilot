import SwiftUI

/// A Wallet-like deck for iPhone. The front card opens its detail; the other
/// cards stay reachable by swiping, tapping their exposed edge, or using the
/// position controls. The deck only changes presentation, never card order.
struct StackedCardDeck: View {
    let cards: [BankCard]
    let transition: Namespace.ID
    let revealCardKey: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var interaction: CardDeckInteraction
    @State private var deckWidth: CGFloat = 0
    @State private var openedCard: BankCard?
    @State private var feedback = 0
    @GestureState private var gestureActive = false

    init(cards: [BankCard], transition: Namespace.ID, revealCardKey: String? = nil) {
        self.cards = cards
        self.transition = transition
        self.revealCardKey = revealCardKey
        _interaction = State(initialValue: CardDeckInteraction(keys: cards.map(\.syncKey)))
    }

    private var count: Int { cards.count }
    private var frontIndex: Int { interaction.selectedIndex }

    var body: some View {
        let renderedKeys = Set(interaction.renderedKeys)
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                // Keep each card's identity and artwork alive through the handoff.
                ForEach(cards.filter { renderedKeys.contains($0.syncKey) }, id: \.syncKey) { card in
                    layer(card)
                }
                if let card = frontCard {
                    // The outgoing card's rear edge fades in underneath the deck.
                    // At handoff its real layer occupies this exact same position.
                    WalletCardFace(card: card)
                        .scaleEffect(scale(at: interaction.depth(of: card.syncKey)))
                        .offset(y: -interaction.depth(of: card.syncKey) * 10)
                        .opacity(reduceMotion || interaction.depth(of: card.syncKey) >= 4 ? 0 : interaction.lift)
                        .zIndex(-Double(interaction.depth(of: card.syncKey)))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
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
        .onChange(of: cards.map(\.syncKey)) { _, keys in
            withoutAnimation { interaction.reconcile(keys: keys) }
        }
        .onChange(of: revealCardKey, initial: true) { _, key in
            guard let key, cards.contains(where: { $0.syncKey == key }) else { return }
            // Present a card explicitly added from the sheet without changing
            // saved order or the swipe/animation handoff logic.
            withoutAnimation {
                interaction.reconcile(keys: cards.map(\.syncKey))
                if interaction.select(key, direction: 1) {
                    _ = interaction.complete(generation: interaction.generation)
                }
            }
        }
        .onChange(of: gestureActive) { _, active in
            // GestureState also resets when the system cancels a touch (no onEnded).
            if !active, interaction.phase == .dragging {
                interaction.returnToRest()
                animateHandoff()
            } else if !active {
                interaction.endTouch()
                continuePendingSelection()
            }
        }
        .onChange(of: reduceMotion) { _, _ in
            if interaction.phase == .settling {
                completeHandoff(generation: interaction.generation)
            } else {
                withoutAnimation { interaction.cancel() }
            }
        }
        .onDisappear { withoutAnimation { interaction.cancel() } }
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
        cards.first { $0.syncKey == interaction.selectedKey } ?? cards.first
    }

    private func open(_ card: BankCard) {
        guard interaction.canSelect else { return }
        openedCard = card
    }

    private func scale(at depth: CGFloat) -> CGFloat {
        1 - depth * 0.035
    }

    private func layer(_ card: BankCard) -> some View {
        let isFront = card.syncKey == interaction.selectedKey
        let depth: CGFloat = isFront ? 0 : reduceMotion
            ? interaction.restingDepth(of: card.syncKey)
            : interaction.depth(of: card.syncKey)
        return WalletCardFace(card: card)
            .scaleEffect(scale(at: depth))
            .offset(x: isFront && !reduceMotion ? interaction.offset : 0, y: -depth * 10)
            .opacity(!isFront && depth > 3 ? max(0, Double(4 - depth)) : 1)
            .matchedTransitionSource(id: card.id, in: transition)
            .onTapGesture {
                if isFront { open(card) } else { select(card.syncKey) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(!isFront)
            .accessibilityLabel("\(card.name)，打开卡片详情")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "打开卡片详情") { open(card) }
            .zIndex(isFront ? 100 : -Double(depth))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($gestureActive) { _, active, _ in active = true }
            .onChanged { value in
                interaction.updateDrag(x: value.translation.width, y: value.translation.height, width: deckWidth)
            }
            .onEnded { value in
                // Capture the final touch position, including reversals through zero.
                interaction.updateDrag(x: value.translation.width, y: value.translation.height, width: deckWidth)
                let needsAnimation = interaction.phase == .dragging
                interaction.release(projectedX: value.predictedEndTranslation.width, width: deckWidth)
                if needsAnimation { animateHandoff() } else { continuePendingSelection() }
            }
    }

    private func animateHandoff() {
        let generation = interaction.generation
        if reduceMotion {
            completeHandoff(generation: generation)
            return
        }
        let animation: Animation = interaction.phase == .returning
            ? .spring(response: 0.3, dampingFraction: 0.86)
            : .smooth(duration: 0.22)
        withAnimation(animation, completionCriteria: .removed) {
            interaction.finishMotion(width: deckWidth)
        } completion: {
            completeHandoff(generation: generation)
        }
    }

    private func completeHandoff(generation: Int) {
        withoutAnimation {
            if interaction.complete(generation: generation) { feedback &+= 1 }
        }
        continuePendingSelection()
    }

    private func continuePendingSelection() {
        if let step = interaction.nextStep() { advance(by: step) }
    }

    private func advance(by step: Int) {
        guard count > 1 else { return }
        guard interaction.canSelect else { interaction.enqueue(step: step); return }
        let index = (frontIndex + step + count) % count
        if interaction.select(cards[index].syncKey, direction: step) { animateHandoff() }
    }

    private func select(_ key: String) {
        if interaction.select(key, direction: interaction.direction) { animateHandoff() }
    }

    private func withoutAnimation(_ changes: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, changes)
    }
}
