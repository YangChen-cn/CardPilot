import SwiftUI
import SwiftData

/// A quick look at the selected card, using published benefits rather than its ledger.
struct DeckCardSummary: View {
    let card: BankCard
    @Environment(\.modelContext) private var context
    @Environment(CatalogRepository.self) private var catalog
    @Query(filter: #Predicate<DomainRecord> {
        $0.kind == "offerState" || $0.kind == "policy" || $0.kind == "cardOverride"
    }) private var documents: [DomainRecord]
    @State private var reading: BenefitInfo?

    private var highlights: [BenefitInfo] {
        OfferStore.offers(for: card, context: context)
            .filter { !$0.isArchived && !$0.isHidden && !$0.isHistorical && !$0.isEnded && !$0.isNotStarted }
            .sorted {
                if $0.personal.favorite != $1.personal.favorite { return $0.personal.favorite }
                if $0.isWelcome != $1.isWelcome { return !$0.isWelcome }
                if $0.hasKnownEnd != $1.hasKnownEnd { return $0.hasKnownEnd }
                if $0.endsOn != $1.endsOn { return $0.endsOn < $1.endsOn }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            .prefix(2).map { $0 }
    }

    var body: some View {
        let _ = catalog.revision
        let _ = documents.map(\.modifiedAt)
        let benefits = highlights
        let pricing = PricingStore.current(card)
        let details = PricingStore.details(card)
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink {
                CardDetailView(card: card)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.name).font(.headline).foregroundStyle(.primary)
                        Text(card.bank + " · " + card.network
                             + (card.lastFour.isEmpty ? "" : " · 尾号 " + card.lastFour))
                            .font(.caption).foregroundStyle(.secondary)
                        if benefits.isEmpty && pricing.baseRateBps > 0 {
                            Text("基础权益 " + Money.percent(pricing.baseRateBps)
                                 + (details.baseRateVerified ? " · 以条款为准" : " · 比例待核实"))
                                .font(.subheadline).foregroundStyle(PilotTheme.accent)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        .padding(.top, 4).accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("查看卡片的全部权益和个人资料")

            // The selected card's strategy appears before per-offer highlights.
            // Tapping this panel goes straight to the complete card guide.
            CardUsageGuideForCard(card: card, compact: true)

            if benefits.isEmpty {
                Text("暂无当前活动")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(benefits) { info in
                    Divider()
                    Button { reading = info } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                if info.personal.favorite {
                                    Image(systemName: "star.fill").font(.caption)
                                        .foregroundStyle(PilotTheme.accent).accessibilityHidden(true)
                                }
                                Text(info.title).font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary).lineLimit(2)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption2)
                                    .foregroundStyle(.tertiary).accessibilityHidden(true)
                            }
                            if info.headline != "查看适用权益与条件" {
                                Text(info.headline).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(PilotTheme.accent)
                            }
                            Text(info.compactPeriodLabel)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("阅读适用条件及完整条款")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $reading) { BenefitDetailView(info: $0) }
    }
}
