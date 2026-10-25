import SwiftUI

struct CardDetailOverview: View {
    let card: BankCard
    var compact = false
    @Environment(CatalogRepository.self) private var catalog

    var body: some View {
        let _ = catalog.revision
        let pricing = PricingStore.current(card)
        let details = PricingStore.details(card)
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            Text(card.name).font(.title2.weight(.semibold))
            Text(card.bank + " · " + card.network + (card.lastFour.isEmpty ? "" : " · 尾号 " + card.lastFour))
                .font(.subheadline).foregroundStyle(.secondary)
            if !compact {
                HStack(spacing: 8) {
                    Image(systemName: card.isDebitCard ? "banknote" : "creditcard")
                    Text(card.kindLabel)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            if pricing.baseRateBps > 0 {
                if compact {
                    Text("基础权益 " + Money.percent(pricing.baseRateBps)
                         + (details.baseRateVerified ? " · 适用条件以银行条款为准" : " · 比例待核实"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("基础权益").font(.caption).foregroundStyle(.secondary)
                        Text(Money.percent(pricing.baseRateBps)).font(.title2.weight(.semibold)).foregroundStyle(PilotTheme.accent)
                        Text(details.baseRateVerified ? "适用范围及限制以银行条款为准" : "基础权益比例待核实")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !compact, let url = URL(string: details.sourceURL), !details.sourceURL.isEmpty {
                Link("官方产品资料", destination: url).font(.subheadline)
            }
            if !compact, !details.verifiedOn.isEmpty {
                Text("资料核实于 " + details.verifiedOn).font(.caption).foregroundStyle(.secondary)
            }
            if card.isArchived { Label("已归档", systemImage: "archivebox").font(.subheadline).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
