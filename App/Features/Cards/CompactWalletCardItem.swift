import SwiftUI

/// Compact cards use vertical drop positions; the desktop grid keeps its horizontal behavior.
struct CompactWalletCardItem: View {
    let card: BankCard
    let transition: Namespace.ID
    var showsCompactRow = false
    var isHighlighted = false
    let onDrop: (String, Bool) -> Bool
    let onMoveToStart: () -> Bool
    let onMoveToEnd: () -> Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var height: CGFloat = 0
    @State private var isDropTarget = false

    var body: some View {
        NavigationLink {
            WalletCardDestination(card: card, transition: transition)
        } label: {
            Group {
                if showsCompactRow {
                    CompactWalletCardRow(card: card)
                } else {
                    WalletCardTile(card: card)
                }
            }
                .overlay {
                    if isHighlighted {
                        RoundedRectangle(cornerRadius: showsCompactRow ? PilotTheme.cardCornerRadius : PilotTheme.radius, style: .continuous)
                            .strokeBorder(PilotTheme.accent, lineWidth: 2)
                            .padding(1)
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: isHighlighted)
                .overlay {
                    if isDropTarget {
                        RoundedRectangle(cornerRadius: showsCompactRow ? PilotTheme.cardCornerRadius : PilotTheme.radius, style: .continuous)
                            .strokeBorder(PilotTheme.accent.opacity(0.8), lineWidth: 2)
                            .padding(1)
                    }
                }
                .scaleEffect(isDropTarget && !reduceMotion ? 1.012 : 1)
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isDropTarget)
                .matchedTransitionSource(id: card.id, in: transition)
                .draggable(card.syncKey)
        }
        .buttonStyle(WalletCardButtonStyle())
        .contentShape(.rect)
        .accessibilityHint("打开卡片详情")
        .dropDestination(for: String.self) { items, location in
            guard let source = items.first else { return false }
            return onDrop(source, height > 0 && location.y > height / 2)
        } isTargeted: { isDropTarget = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .contextMenu {
            NavigationLink("查看消费账本") { TransactionsView(card: card) }
            Divider()
            Button("移到最前", systemImage: "arrow.up.to.line") { _ = onMoveToStart() }
            Button("移到最后", systemImage: "arrow.down.to.line") { _ = onMoveToEnd() }
        }
        .accessibilityAction(named: "移到最前") { _ = onMoveToStart() }
        .accessibilityAction(named: "移到最后") { _ = onMoveToEnd() }
    }
}
