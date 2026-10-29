import SwiftUI

struct CardGridItem: View {
    let card: BankCard
    let transition: Namespace.ID
    let onDrop: (String, Bool) -> Bool
    let onMoveToStart: () -> Bool
    let onMoveToEnd: () -> Bool
    let onLedger: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0
    @State private var isDropTarget = false

    var body: some View {
        NavigationLink {
            WalletCardDestination(card: card, transition: transition)
        } label: {
            WalletCardTile(card: card, transition: transition)
                .draggable(card.syncKey)
        }
        .buttonStyle(WalletCardButtonStyle())
        .contentShape(.rect)
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: PilotTheme.radius, style: .continuous)
                    .strokeBorder(PilotTheme.accent.opacity(0.8), lineWidth: 2)
                    .padding(1)
            }
        }
        .scaleEffect(isDropTarget && !reduceMotion ? 1.012 : 1)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isDropTarget)
        .dropDestination(for: String.self) { items, location in
            guard let source = items.first else { return false }
            return onDrop(source, width > 0 && location.x > width / 2)
        } isTargeted: { isDropTarget = $0 }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width = $0 }
        .contextMenu {
            #if os(macOS)
            Button("查看消费账本", action: onLedger)
            #else
            NavigationLink("查看消费账本") { TransactionsView(card: card) }
            #endif
            Divider()
            Button("移到最前", systemImage: "arrow.up.to.line") { _ = onMoveToStart() }
            Button("移到最后", systemImage: "arrow.down.to.line") { _ = onMoveToEnd() }
        }
        .accessibilityAction(named: "移到最前") { _ = onMoveToStart() }
        .accessibilityAction(named: "移到最后") { _ = onMoveToEnd() }
        .help("拖动卡片调整顺序")
    }
}
