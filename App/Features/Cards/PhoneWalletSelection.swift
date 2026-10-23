import SwiftUI

#if os(iOS)
struct PhoneWalletSelection: View {
    let card: BankCard
    let benefits: [BenefitInfo]
    let transition: Namespace.ID
    let onRecord: () -> Void
    @State private var readingBenefit: BenefitInfo?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(card.name).font(.title2).bold().fixedSize(horizontal: false, vertical: true)
                Text([card.bank, card.network, card.lastFour.isEmpty ? nil : "尾号 " + card.lastFour]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !benefits.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(benefits.prefix(2)) { info in
                        Button { readingBenefit = info } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(info.title).font(.subheadline).foregroundStyle(.primary)
                                Text(info.headline).font(.subheadline).bold().foregroundStyle(PilotTheme.accent)
                            }
                            .frame(maxWidth: .infinity, minHeight: PilotTheme.minimumTouchTarget, alignment: .leading)
                            .padding(.vertical, 8)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if info.id != benefits.prefix(2).last?.id { Divider() }
                    }
                }
            }
            NavigationLink {
                WalletCardDestination(card: card, transition: transition)
            } label: {
                HStack {
                    Label(card.isArchived ? "查看卡片详情" : "查看全部权益", systemImage: "gift")
                    Spacer(minLength: 8)
                    if !benefits.isEmpty { Text("\(benefits.count)").monospacedDigit() }
                    Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
                }
                .font(.subheadline)
                .frame(minHeight: PilotTheme.minimumTouchTarget)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(PilotTheme.accent)
            if typeSize.isAccessibilitySize {
                VStack(spacing: 8) { ledgerAction; recordAction }
            } else {
                HStack(spacing: 12) { ledgerAction; recordAction }
            }
        }
        .sheet(item: $readingBenefit) { BenefitDetailView(info: $0) }
    }

    private var ledgerAction: some View {
        NavigationLink { TransactionsView(card: card) } label: {
            Label("消费账本", systemImage: "list.bullet.rectangle")
                .frame(maxWidth: .infinity, minHeight: PilotTheme.minimumTouchTarget)
        }
        .buttonStyle(.bordered)
    }

    private var recordAction: some View {
        Button(action: onRecord) {
            Label("记一笔", systemImage: "plus")
                .frame(maxWidth: .infinity, minHeight: PilotTheme.minimumTouchTarget)
        }
        .buttonStyle(.borderedProminent)
        .labelStyle(.titleAndIcon)
    }
}
#endif
