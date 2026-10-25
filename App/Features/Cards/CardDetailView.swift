import SwiftUI
import SwiftData

struct CardDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogRepository.self) private var catalog
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Query private var documents: [DomainRecord]
    let card: BankCard
    @State private var editing = false
    @State private var addingRule = false
    @State private var editingRule: RewardRule?
    @State private var addingTransaction = false
    #if os(macOS)
    @State private var showingLedger = false
    #endif
    @State private var deleting = false
    @State private var error: String?
    @State private var libraryProduct: CardProduct?
    @State private var personalProduct: CardProduct?
    @State private var readingHistory: BenefitInfo?

    private var phoneLayout: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private var displayedBenefits: [BenefitInfo] {
        _ = catalog.revision
        _ = documents.map(\.modifiedAt)
        return OfferStore.offers(for: card, context: context)
            .filter { $0.isHistorical ? $0.isHistoricalReadable : (!$0.isArchived && !$0.isHidden) }
            .sorted {
                if $0.isEnded != $1.isEnded { return !$0.isEnded }
                if $0.hasKnownEnd != $1.hasKnownEnd { return $0.hasKnownEnd }
                return $0.hasKnownEnd ? $0.endsOn < $1.endsOn : $0.title < $1.title
            }
    }

    var body: some View {
        let _ = catalog.revision
        let benefits = displayedBenefits
        let favoriteBenefits = benefits.filter { $0.personal.favorite && !$0.isHistorical }
        let currentBenefits = benefits.filter { !$0.isHistorical && !$0.personal.favorite }
        let historicalBenefits = benefits.filter(\.isHistorical)
        let pricing = PricingStore.current(card)
        let details = PricingStore.details(card)
        ScrollView {
            VStack(alignment: .leading, spacing: phoneLayout ? 20 : 28) {
                CardDetailHeader(card: card)
                if !favoriteBenefits.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 7) {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                            Text("常看权益").font(.title3.weight(.semibold))
                        }
                        ForEach(favoriteBenefits) { info in
                            OfferPanel(info: info, onEdit: info.canEdit ? { editingRule = info.legacyRule } : nil)
                        }
                    }
                }
                if !phoneLayout {
                    HStack(spacing: 12) {
                        ledgerEntry
                        Button("记一笔", systemImage: "plus", action: { addingTransaction = true }).buttonStyle(.bordered)
                    }.controlSize(.large)
                    Divider()
                }
                if !currentBenefits.isEmpty || favoriteBenefits.isEmpty {
                    HStack {
                        Text(favoriteBenefits.isEmpty ? "银行卡权益" : "其他权益").font(.title3.weight(.semibold))
                        Spacer()
                        Button("添加活动", systemImage: "plus", action: { addingRule = true }).frame(minHeight: 44)
                    }
                }
                if currentBenefits.isEmpty {
                    if favoriteBenefits.isEmpty {
                        ContentUnavailableView("暂无当前权益", systemImage: "gift", description: Text("可添加自己的活动记录，或查看银行官方产品资料。"))
                    }
                } else {
                    ForEach(BenefitGroup.allCases) { group in
                        let grouped = currentBenefits.filter { $0.group == group }
                        if !grouped.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(group.title).font(.headline).foregroundStyle(.secondary)
                                ForEach(grouped) { info in
                                    OfferPanel(info: info, onEdit: info.canEdit ? { editingRule = info.legacyRule } : nil)
                                }
                            }
                        }
                    }
                }
                if !historicalBenefits.isEmpty {
                    GroupBox("历史活动与个人记录") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("旧版本中保存的活动、备注和日期，仅作历史保留，不代表当前官方条款。")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(historicalBenefits) { info in
                                Button { readingHistory = info } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(info.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                            Text(info.periodDescription).font(.caption).foregroundStyle(.secondary)
                                            if !info.personal.notes.isEmpty {
                                                Text(info.personal.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                            }
                                        }
                                        Spacer(minLength: 8)
                                        Text("历史记录")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                if info.id != historicalBenefits.last?.id { Divider() }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }
                }
                Divider()
                if phoneLayout {
                    HStack(spacing: 12) {
                        ledgerEntry
                        Button("记一笔", systemImage: "plus", action: { addingTransaction = true }).buttonStyle(.bordered)
                    }.controlSize(.large)
                }
                CardFinancialSummary(card: card)
                if !details.annualFeeNote.isEmpty || !details.caveats.isEmpty || pricing.foreignFeeBps > 0 || pricing.overseasHKDFeeBps > 0 {
                    GroupBox("费用与其他说明") {
                        VStack(alignment: .leading, spacing: 12) {
                            if pricing.foreignFeeBps > 0 { LabeledContent("外币手续费", value: Money.percent(pricing.foreignFeeBps)) }
                            if pricing.overseasHKDFeeBps > 0 { LabeledContent("境外港币手续费", value: Money.percent(pricing.overseasHKDFeeBps)) }
                            if !details.annualFeeNote.isEmpty { Text(details.annualFeeNote).font(.subheadline) }
                            if !details.caveats.isEmpty { Text(details.caveats).font(.caption).foregroundStyle(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }
                }
                if phoneLayout, !details.verifiedOn.isEmpty {
                    Text("产品资料核实于 " + details.verifiedOn).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(phoneLayout ? PilotTheme.phonePagePadding : PilotTheme.pagePadding)
            .frame(maxWidth: 940).frame(maxWidth: .infinity)
        }
        .background(PilotTheme.canvas)
        .navigationTitle("卡片详情")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("卡片操作", systemImage: "ellipsis") {
                    Button("添加活动", systemImage: "gift.badge.plus", action: { addingRule = true })
                    if phoneLayout {
                        NavigationLink { TransactionsView(card: card) } label: {
                            Label("消费账本", systemImage: "list.bullet.rectangle")
                        }
                        Button("记一笔", systemImage: "plus", action: { addingTransaction = true })
                        Divider()
                    }
                    Button("编辑卡片", systemImage: "pencil", action: { editing = true })
                    if libraryProduct != nil {
                        Button("个人持卡资料", systemImage: "person.crop.rectangle", action: { personalProduct = libraryProduct })
                    }
                    if phoneLayout, let url = URL(string: details.sourceURL), url.scheme == "https" {
                        Link(destination: url) { Label("官方产品资料", systemImage: "safari") }
                    }
                    Button("删除卡片", systemImage: "trash", role: .destructive, action: { deleting = true })
                }
                .confirmationDialog("删除这张卡及其 \(card.transactions.count) 笔交易？", isPresented: $deleting, titleVisibility: .visible) {
                    Button("删除全部关联数据", role: .destructive, action: delete)
                }
            }
        }
        .sheet(isPresented: $editing) { CardEditor(card: card) }
        .sheet(isPresented: $addingRule) { RuleEditor(cardID: card.id) }
        .sheet(item: $editingRule) { RuleEditor(rule: $0) }
        .sheet(isPresented: $addingTransaction) { TransactionEditor(cardID: card.id) }
        .sheet(item: $readingHistory) { BenefitDetailView(info: $0) }
        .sheet(item: $personalProduct) { product in
            NavigationStack {
                PersonalCardSetupView(card: card, product: product, onFinish: { personalProduct = nil })
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭", action: { personalProduct = nil }) } }
            }.editorSize()
        }
        .task(id: card.catalogID + ":" + String(catalog.revision)) {
            guard !card.catalogID.isEmpty else { libraryProduct = nil; return }
            libraryProduct = (try? BankLibrary.load())?.product(id: card.catalogID)
        }
        .alert("未能删除卡片", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) { error = nil }
        } message: { Text(error ?? "请稍后重试。") }
    }

    private func delete() {
        do { try Persistence.save(context) { Persistence.remove(card, context: context) }; dismiss() }
        catch { self.error = PilotError.message(error) }
    }

    @ViewBuilder private var ledgerEntry: some View {
        #if os(macOS)
        Button("消费账本", systemImage: "list.bullet.rectangle", action: { showingLedger = true })
            .buttonStyle(.borderedProminent)
            .sheet(isPresented: $showingLedger) { CardLedgerSheet(card: card) }
        #else
        NavigationLink { TransactionsView(card: card) } label: { Label("消费账本", systemImage: "list.bullet.rectangle") }
            .buttonStyle(.borderedProminent)
        #endif
    }
}
