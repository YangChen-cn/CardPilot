import SwiftUI
import SwiftData

struct DashboardActivities: View {
    @Environment(\.modelContext) private var context
    @Environment(CatalogRepository.self) private var catalog
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    var documents: [DomainRecord] = []
    @State private var editingWelcome: BenefitInfo?
    @State private var reading: BenefitInfo?

    private var phoneLayout: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private var allOffers: [BenefitInfo] {
        _ = catalog.revision
        _ = documents.map(\.modifiedAt)
        return OfferStore.offers(context: context)
    }

    private var trackedWelcome: [BenefitInfo] {
        allOffers.filter { info in
            guard info.isWelcome, !info.isArchived,
                  info.hasKnownPeriod || (try? OfferTrackingStore.load(for: info, context: context)) != nil,
                  let tracking = try? OfferTrackingStore.load(for: info, context: context) else { return false }
            let status = tracking.effectiveStatus(now: .now)
            return status == .active || status == .achieved
        }.sorted {
            let first = try? OfferTrackingStore.load(for: $0, context: context)
            let second = try? OfferTrackingStore.load(for: $1, context: context)
            let firstKnown = first?.hasKnownDeadline == true, secondKnown = second?.hasKnownDeadline == true
            if firstKnown != secondKnown { return firstKnown }
            if firstKnown, let first, let second { return first.deadline < second.deadline }
            return $0.title < $1.title
        }
    }

    private var featured: [BenefitInfo] {
        allOffers.filter {
            !$0.isWelcome && !$0.isHidden && !$0.isArchived && !$0.isEnded && !$0.isNotStarted && !$0.isHistorical
        }.sorted {
            if $0.group == .daily && $1.group != .daily { return true }
            if $0.group != .daily && $1.group == .daily { return false }
            if $0.hasKnownEnd != $1.hasKnownEnd { return $0.hasKnownEnd }
            return $0.hasKnownEnd ? $0.endsOn < $1.endsOn : $0.title < $1.title
        }
    }

    private var pending: Int { documents.count { ["review", "mailReview"].contains($0.kind) && !$0.isDeleted } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !featured.isEmpty {
                HStack {
                    SectionHeading(title: "值得关注的权益")
                    Spacer()
                    NavigationLink("全部权益") { OffersView() }.font(.subheadline).frame(minHeight: phoneLayout ? 44 : nil)
                }
                if phoneLayout {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(featured.prefix(2)) { info in
                            Button(action: { reading = info }) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(info.cardName).font(.caption).foregroundStyle(.secondary)
                                    Text(info.title).font(.headline)
                                    Text(info.headline).font(.subheadline.weight(.medium)).foregroundStyle(PilotTheme.accent)
                                    Label(info.periodDescription, systemImage: "calendar")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(.vertical, 12).contentShape(.rect)
                            }.buttonStyle(.plain)
                            if info.id != featured.prefix(2).last?.id { Divider() }
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), alignment: .top)], alignment: .leading, spacing: 16) {
                        ForEach(featured.prefix(2)) { info in OfferPanel(info: info) }
                    }
                }
            }
            if !trackedWelcome.isEmpty {
                HStack {
                    SectionHeading(title: "迎新提醒")
                    Spacer()
                    NavigationLink("迎新中心") { WelcomeCenterView() }.font(.subheadline).frame(minHeight: phoneLayout ? 44 : nil)
                }
                ForEach(trackedWelcome.prefix(2)) { info in
                    if let tracking = try? OfferTrackingStore.load(for: info, context: context) {
                        Button(action: { editingWelcome = info }) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "gift").foregroundStyle(PilotTheme.accent)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(info.cardName).font(.caption).foregroundStyle(.secondary)
                                    Text(info.title).font(.subheadline.weight(.semibold))
                                    Text(tracking.effectiveStatus(now: .now).label).font(.caption).foregroundStyle(.secondary)
                                    if phoneLayout { deadline(tracking) }
                                }
                                Spacer(minLength: 8)
                                if !phoneLayout {
                                    VStack(alignment: .trailing, spacing: 6) { deadline(tracking) }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).contentShape(.rect)
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            if pending > 0 {
                NavigationLink { ReviewTransactionsView() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.bubble").foregroundStyle(PilotTheme.accent)
                        Text("\(pending) 笔导入记录待核对").font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }.frame(minHeight: 44).contentShape(.rect)
                }.buttonStyle(.plain)
            }
        }
        .sheet(item: $editingWelcome) { WelcomeTrackingEditor(info: $0) }
        .sheet(item: $reading) { BenefitDetailView(info: $0) }
    }

    @ViewBuilder private func deadline(_ tracking: WelcomeTracking) -> some View {
        if tracking.hasKnownDeadline {
            Text(tracking.deadline, format: .dateTime.month().day()).font(.subheadline.weight(.medium))
            let days = HKCalendar.daysLeft(tracking.deadline)
            Text(days < 0 ? "已过截止日期" : days == 0 ? "今天截止" : "还剩 \(days) 天")
                .font(.caption).foregroundStyle(days <= 7 ? .orange : .secondary)
        } else {
            Text("截止日期待记录").font(.caption).foregroundStyle(.secondary)
        }
    }
}
