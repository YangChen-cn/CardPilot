import SwiftUI

struct RecommendationRow: View {
    let result: CardRecommendation
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var phoneLayout: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(result.rankingLabel,
                  systemImage: result.topOffer == nil
                    ? "info.circle"
                    : (result.isConditional ? "questionmark.circle" : "checkmark.circle"))
                .font(.caption)
                .foregroundStyle(result.topOffer == nil || result.isConditional
                                 ? AnyShapeStyle(.secondary) : AnyShapeStyle(PilotTheme.accent))
            Text(result.card.displayName).font(.title3.bold())
            Text(result.rankingSummary).font(.caption).foregroundStyle(.secondary)
            if let base = result.baseBenefit { Text(base).font(.subheadline).foregroundStyle(.secondary) }
            ForEach(result.offers) { offer in
                VStack(alignment: .leading, spacing: 8) {
                    Text(offer.title).font(.headline)
                    if phoneLayout {
                        ForEach(Array(offer.matchedConditions.prefix(2)), id: \.self) { Text($0).font(.subheadline) }
                        if let first = offer.confirmationNeeded.first {
                            Text("需确认：" + first).font(.subheadline).foregroundStyle(.secondary)
                        }
                        PilotDisclosureGroup("适用条件与条款") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(offer.matchedConditions, id: \.self) { Text($0).font(.subheadline) }
                                ForEach(offer.confirmationNeeded, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
                                if !offer.note.isEmpty { Text(offer.note).font(.subheadline).foregroundStyle(.secondary) }
                                if !offer.hasKnownStart { Text("开始日期未核实").font(.caption).foregroundStyle(.secondary) }
                                if offer.hasKnownEnd {
                                    Label(offer.endsOn.formatted(.dateTime.year().month().day()) + " 截止", systemImage: "calendar")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else { Text("结束日期未核实").font(.caption).foregroundStyle(.secondary) }
                            }.padding(.top, 4)
                        }.font(.subheadline)
                        if let url = URL(string: offer.sourceURL), ["https", "http"].contains(url.scheme ?? "") {
                            Link("官方条款", destination: url).font(.subheadline).frame(minHeight: 44)
                        }
                    } else {
                        ForEach(offer.matchedConditions, id: \.self) { Text($0).font(.subheadline) }
                        ForEach(offer.confirmationNeeded, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                        if !offer.note.isEmpty { Text(offer.note).font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            if !offer.hasKnownStart { Text("开始日期未核实") }
                            if offer.hasKnownEnd {
                                Text(offer.endsOn, format: .dateTime.year().month().day())
                                Text("截止")
                            } else { Text("结束日期未核实") }
                            Spacer()
                            if let url = URL(string: offer.sourceURL), ["https", "http"].contains(url.scheme ?? "") {
                                Link("官方条款", destination: url)
                            }
                        }.font(.caption)
                    }
                }
                if offer.id != result.offers.last?.id { Divider() }
            }
            if !result.caveats.isEmpty {
                PilotDisclosureGroup("卡片注意事项") {
                    ForEach(result.caveats, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }.font(.subheadline)
            }
            if result.offers.isEmpty, let url = URL(string: PricingStore.details(result.card).sourceURL), ["https", "http"].contains(url.scheme ?? "") {
                Link("查看官方权益", destination: url).font(.subheadline).frame(minHeight: phoneLayout ? 44 : nil)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).pilotPanel()
    }
}
