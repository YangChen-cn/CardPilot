import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
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

    private var phoneLayout: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        let _ = documents.map(\.modifiedAt)
        ScrollView {
            VStack(alignment: .leading, spacing: phoneLayout ? PilotTheme.phoneSectionSpacing : 28) {
                wallet
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
        .background(PilotTheme.canvas)
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
            DashboardBalance(snapshot: snapshot)
            if spendingError {
                Button("消费统计暂未更新，重试", systemImage: "arrow.clockwise") { spendingRevision &+= 1 }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if phoneLayout {
                Button("记一笔", systemImage: "plus", action: { adding = true }).phonePrimaryAction()
            } else {
                Button("记一笔", systemImage: "plus", action: { adding = true })
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
    }

    private var wallet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeading(title: "我的银行卡")
                Spacer()
                NavigationLink("全部卡片") { CardsView() }.font(.subheadline).frame(minHeight: phoneLayout ? 44 : nil)
            }
            if orderedCards.contains(where: { !$0.isArchived }) {
                if phoneLayout {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(orderedCards.filter { !$0.isArchived }.prefix(6)) { card in
                                NavigationLink { CardDetailView(card: card) } label: {
                                    VStack(alignment: .leading, spacing: 12) {
                                        CardArtwork(card: card, compact: true)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 180)
                                        Text(card.name).font(.headline)
                                        Text(card.bank + " · " + card.kindLabel)
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .containerRelativeFrame(.horizontal)
                                    .contentShape(.rect)
                                }.buttonStyle(.plain)
                            }
                        }.scrollTargetLayout().padding(.vertical, 8)
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollIndicators(.hidden)
                } else {
                    ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 22) {
                        ForEach(orderedCards.filter { !$0.isArchived }.prefix(6)) { card in
                            NavigationLink { CardDetailView(card: card) } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 0) {
                                        Spacer(minLength: 0)
                                        CardArtwork(card: card, compact: true)
                                            .frame(height: 164)
                                            .fixedSize(horizontal: true, vertical: false)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(minWidth: 170)
                                    Text(card.name).font(.subheadline.weight(.medium)).lineLimit(2)
                                        .frame(width: 170, alignment: .leading)
                                    Text(card.bank + " · " + card.kindLabel).font(.caption).foregroundStyle(.secondary)
                                        .frame(width: 170, alignment: .leading)
                                }.fixedSize(horizontal: true, vertical: false)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 8)
                    }.scrollIndicators(.hidden)
                }
            } else {
                NavigationLink { CardsView() } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "creditcard.badge.plus").font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("添加第一张银行卡").font(.headline)
                            Text("收藏权益，轻松查优惠。 ").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }.frame(minHeight: 70).contentShape(.rect)
                }.buttonStyle(.plain)
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeading(title: "最近消费")
                Spacer()
                NavigationLink("全部交易") { TransactionsView() }.font(.subheadline).frame(minHeight: phoneLayout ? 44 : nil)
            }
            if recentTransactions.isEmpty {
                Text("手动记录，或连接银行邮件与快捷指令。")
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
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
