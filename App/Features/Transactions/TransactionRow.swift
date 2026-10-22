import SwiftUI

struct TransactionRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let transaction: SpendTransaction

    private var category: SpendCategory { SpendCategory(rawValue: transaction.category) ?? .other }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: category.symbol).font(.body.weight(.medium))
                .foregroundStyle(PilotTheme.accent).frame(width: 42, height: 42)
                .background(PilotTheme.accent.opacity(0.08), in: .circle).accessibilityHidden(true)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { description; amounts }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    description.frame(maxWidth: .infinity, alignment: .leading)
                    amounts.layoutPriority(1)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(transaction.merchant).font(.body.weight(.medium)).lineLimit(2)
            Text("\(transaction.card?.name ?? "未关联卡片") · \(transaction.category)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    private var amounts: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(Money.text(transaction.amountCents, currency: transaction.currency))
                .font(.body.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
            if transaction.currency != "HKD" {
                Text(transaction.hasHKDValuation ? "≈ \(Money.text(transaction.hkdCents))" : "原币入账 · 未折算港币").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
