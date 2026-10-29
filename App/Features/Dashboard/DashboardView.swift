import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CatalogRepository.self) private var catalog
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Query(sort: \BankCard.createdAt) private var cards: [BankCard]
    @Query private var documents: [DomainRecord]
    @State private var adding = false
    @State private var editing: SpendTransaction?
    @State private var showTrends = false
    @State private var wide = false
    @State private var snapshot = DashboardSnapshot(inputs: [], now: .now)
    @State private var recentTransactions: [SpendTransaction] = []
    @State private var spendingRevision = 0
    @State private var spendingError = false

    private var orderedCards: [BankCard] {
        CardOrderStore.ordered(cards, context: context)
    }

    /// Only published guides for cards actually in this wallet. Keep the
    /// saved card order and make every card reachable by horizontal scrolling.
    private var guidedCards: [BankCard] {
        guard let library = try? BankLibrary.load() else { return [] }
        return orderedCards.filter {
            !$0.isArchived && !$0.catalogID.isEmpty
            && library.product(id: $0.catalogID)?.usageGuide != nil
        }
    }

    private var phoneLayout: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        let _ = catalog.revision
        let _ = documents.map(\.modifiedAt)
        ScrollView {
            VStack(alignment: .leading, spacing: phoneLayout ? PilotTheme.phoneSectionSpacing : 28) {
                wallet
                cardGuides
                DashboardActivities(documents: documents)
                if !phoneLayout { Divider() }
                if wide {
                    HStack(alignment: .top, spacing: 32) {
                        spending(snapshot).frame(maxWidth: .infinity, alignment: .leading)
                        recent.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    spending(snapshot)
                    recent
                }
                if snapshot.monthCount > 0 {
                    PilotDisclosureGroup("消费统计", isExpanded: $showTrends) {
                        VStack(alignment: .leading, spacing: 24) {
                            SpendingChart(snapshot: snapshot)
                            CategoryChart(totals: snapshot.categories)
                            cardSpending(snapshot)
                        }.padding(.top, 16)
                    }.font(.subheadline.weight(.medium))
                }
                if orderedCards.contains(where: { !$0.isArchived }) {
                    if phoneLayout {
                        NavigationLink { RecommendView() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles").foregroundStyle(PilotTheme.accent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("这一笔，刷哪张？").font(.headline)
                                    Text("按类别与消费地区查权益").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).contentShape(.rect)
                        }.buttonStyle(.plain)
                    } else {
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                SectionHeading(title: "这一笔，刷哪张？")
                                Spacer()
                                NavigationLink("选卡建议") { RecommendView() }.font(.subheadline)
                            }
                            RecommendationWorkbench(cards: orderedCards, compact: true)
                        }
                    }
                }
            }
            .padding(phoneLayout ? PilotTheme.phonePagePadding : PilotTheme.pagePadding).frame(maxWidth: 1160).frame(maxWidth: .infinity)
        }
        .background(phoneLayout ? PilotTheme.groupedCanvas : PilotTheme.canvas)
        .onGeometryChange(for: Bool.self) { $0.size.width >= 1000 } action: { wide = $0 }
        .sheet(isPresented: $adding) { TransactionEditor() }
        .sheet(item: $editing) { TransactionEditor(transaction: $0) }
        .task(id: spendingRevision) { await refreshSpending() }
        .task {
            // Use the accounting timezone even when the device travels or stays open overnight.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(max(1, HKCalendar.dayAfter(.now).timeIntervalSinceNow))) }
                catch { return }
                spendingRevision &+= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { notification in
            guard let saved = notification.object as? ModelContext,
                  saved.container === context.container else { return }
            spendingRevision &+= 1
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { spendingRevision &+= 1 }
        }
        .navigationTitle("总览")
    }

    private func refreshSpending() async {
        do {
            let data = try await DashboardSpendingData.load(in: context)
            snapshot = data.snapshot
            recentTransactions = data.recent
            spendingError = false
        } catch is CancellationError { }
        catch { spendingError = true }
    }

    private func spending(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                DashboardBalance(snapshot: snapshot)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if spendingError {
                Button("消费统计暂未更新，重试", systemImage: "arrow.clockwise") { spendingRevision &+= 1 }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("记一笔", systemImage: "plus", action: { adding = true })
                    .buttonStyle(.borderedProminent)
                NavigationLink { OffersView() } label: {
                    Label("查看权益", systemImage: "gift")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
    }

    /// A short, immediately visible recommendation per card on Home.
    /// Tapping any preview goes straight to its full guide; no card-detail hop.
    @ViewBuilder private var cardGuides: some View {
        let eligible = guidedCards
        if !eligible.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("我的用卡指南").font(.headline)
                    Spacer(minLength: 8)
                    Text("\(eligible.count) 张卡")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(eligible) { card in
                            CardUsageGuideForCard(card: card, compact: true, showsProductName: true)
                                .frame(width: phoneLayout ? 264 : 300, alignment: .leading)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var wallet: some View {
        GroupBox {
            HStack(spacing: 14) {
                Image(systemName: "creditcard")
                    .font(.title3)
                    .foregroundStyle(PilotTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(PilotTheme.accent.opacity(0.12), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(orderedCards.contains(where: { !$0.isArchived }) ? "我的银行卡" : "还没有银行卡")
                        .font(.headline)
                    Text(walletSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
    }

    private var walletSubtitle: String {
        let active = orderedCards.filter { !$0.isArchived }
        if active.isEmpty { return "在卡包中添加第一张银行卡。" }
        return "\(active.count) 张使用中 · 在卡包中管理"
    }

    private var recent: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("最近消费").font(.headline)
                    Spacer()
                    NavigationLink("全部交易") { TransactionsView() }.font(.subheadline)
                }
                if recentTransactions.isEmpty {
                    Text("手动记录，或连接银行邮件与快捷指令。")
                        .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(recentTransactions) { transaction in
                            Button(action: { editing = transaction }) {
                                TransactionRow(transaction: transaction)
                                    .padding(.vertical, 8).contentShape(.rect)
                            }.buttonStyle(.plain)
                            if transaction.id != recentTransactions.last?.id { Divider() }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
    }

    private func cardSpending(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("各卡本月消费").font(.headline)
            ForEach(snapshot.cardTotals) { card in
                VStack(alignment: .leading, spacing: 6) {
                    let layout = phoneLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())
                    layout {
                        Text(card.name).font(.subheadline)
                        if !phoneLayout { Spacer() }
                        Text(Money.text(card.cents)).font(.subheadline.weight(.medium)).monospacedDigit()
                    }
                    if card.unvaluedCount > 0 {
                        Text(card.originalTotals + " · 部分未折算")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
            }
        }
    }
}
