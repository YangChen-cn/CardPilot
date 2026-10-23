import SwiftUI

/// A dense card row keeps the full official image visible as a thumbnail;
/// actions are in the selected-card area or the row's context menu.
struct CompactWalletCardItem: View {
    let card: BankCard
    var isSelected = false
    var onSelect: (() -> Void)?
    let onDrop: (String, Bool) -> Bool
    let onMoveToStart: () -> Bool
    let onMoveToEnd: () -> Bool
    @State private var height: CGFloat = 0

    var body: some View {
        entry
            .buttonStyle(WalletCardButtonStyle())
            .draggable(card.syncKey)
            .dropDestination(for: String.self) { items, location in
                guard let source = items.first else { return false }
                return onDrop(source, height > 0 && location.y > height / 2)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .contextMenu {
                NavigationLink("查看消费账本") { TransactionsView(card: card) }
                Divider()
                Button("移到最前", systemImage: "arrow.up.to.line") { _ = onMoveToStart() }
                Button("移到最后", systemImage: "arrow.down.to.line") { _ = onMoveToEnd() }
            }
            .accessibilityValue(isSelected ? "当前精选卡片" : "")
            .accessibilityAction(named: "移到最前") { _ = onMoveToStart() }
            .accessibilityAction(named: "移到最后") { _ = onMoveToEnd() }
    }

    @ViewBuilder private var entry: some View {
        if let onSelect {
            Button(action: onSelect) { rowLabel }
        } else {
            NavigationLink { CardDetailView(card: card) } label: { rowLabel }
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 14) {
            CardArtwork(card: card, compact: true)
                .environment(\.dynamicTypeSize, .medium)
                .frame(width: 288, height: 208)
                .scaleEffect(0.25)
                .frame(width: 72, height: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(card.name).font(.body).bold().foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text([card.bank, card.network, card.lastFour.isEmpty ? nil : card.lastFour, card.isArchived ? "已归档" : card.kindLabel]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                .foregroundStyle(isSelected ? PilotTheme.accent : .secondary)
                .font(isSelected ? .body : .caption)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(isSelected ? PilotTheme.accent.opacity(0.06) : .clear)
        .contentShape(.rect)
    }
}
