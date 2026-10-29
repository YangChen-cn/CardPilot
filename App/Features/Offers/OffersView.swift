import SwiftUI
import SwiftData

struct OffersView: View {
    @Environment(\.modelContext) private var context
    @Environment(CatalogRepository.self) private var catalog
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Query private var cards: [BankCard]
    @Query private var documents: [DomainRecord]
    @State private var showingAdd = false
    @State private var editing: BenefitInfo?
    @State private var hiding: BenefitInfo?
    @State private var includeEnded = false
    @State private var includeHidden = false
    @State private var favoritesOnly = false
    @State private var selectedCardID: UUID?
    @State private var search = ""
    @State private var error: String?

    private var phoneLayout: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private var activeCards: [BankCard] {
        cards.filter { !$0.isArchived }.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private var hasActiveFilters: Bool {
        selectedCardID != nil || includeEnded || includeHidden || favoritesOnly ||
            !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filterSummary: String {
        var labels: [String] = []
        if let selectedCardID, let card = activeCards.first(where: { $0.id == selectedCardID }) {
            labels.append(card.displayName)
        }
        if favoritesOnly { labels.append("只看收藏") }
        if includeEnded { labels.append("含已结束") }
        if includeHidden { labels.append("含已隐藏") }
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { labels.append("搜索中") }
        return labels.joined(separator: " · ")
    }

    private var filtered: [BenefitInfo] {
        let _ = cards.map(\.modifiedAt)
        let _ = documents.map(\.modifiedAt)
        let _ = catalog.revision
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return OfferStore.offers(context: context).filter { info in
            let archiveVisible = info.isHistorical ? info.isHistoricalReadable : !info.isArchived
            return archiveVisible && (selectedCardID == nil || info.cardID == selectedCardID)
                && (includeHidden || !info.isHidden)
                && (!favoritesOnly || (!info.isHistorical && info.personal.favorite))
                && (includeEnded || (!info.isEnded && !info.isHistorical))
                && (query.isEmpty || info.title.localizedStandardContains(query)
                    || info.cardName.localizedStandardContains(query)
                    || info.conditions.contains(where: { $0.localizedStandardContains(query) }))
        }
    }

    var body: some View {
        let visible = filtered
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 16) {
                    NavigationLink { WelcomeCenterView() } label: { Label("迎新记录", systemImage: "gift").frame(minHeight: 44) }
                    Spacer()
                    if phoneLayout {
                        Menu("权益筛选", systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") {
                            if activeCards.count > 1 {
                                cardPicker
                            }
                            Toggle("只看收藏", isOn: $favoritesOnly)
                            Toggle("包括已结束", isOn: $includeEnded)
                            Toggle("显示已隐藏", isOn: $includeHidden)
                            if hasActiveFilters {
                                Button("清除筛选", systemImage: "xmark.circle", action: clearFilters)
                            }
                        }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    } else {
                        Toggle("只看收藏", isOn: $favoritesOnly).toggleStyle(.switch).fixedSize()
                        Toggle("包括已结束", isOn: $includeEnded).toggleStyle(.switch).fixedSize()
                        Toggle("显示已隐藏", isOn: $includeHidden).toggleStyle(.switch).fixedSize()
                    }
                }
                if !phoneLayout && activeCards.count > 1 {
                    cardPicker.pickerStyle(.menu).frame(maxWidth: 320, alignment: .leading)
                }
                if hasActiveFilters {
                    HStack(alignment: .top, spacing: 12) {
                        Label(filterSummary, systemImage: "line.3.horizontal.decrease.circle")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("清除", action: clearFilters)
                            .font(.subheadline)
                            .frame(minHeight: PilotTheme.minimumTouchTarget)
                    }
                }
                if visible.isEmpty {
                    ContentUnavailableView {
                        Label(favoritesOnly ? "暂无收藏的权益" : "暂无匹配的权益",
                              systemImage: favoritesOnly ? "star" : "gift")
                    } description: {
                        Text(favoritesOnly ? "在权益详情中点按星标，即可在这里快速找到。" : "试试其他关键词或筛选条件，也可以为银行卡添加活动。")
                    } actions: {
                        if hasActiveFilters { Button("清除筛选", action: clearFilters) }
                    }
                }
                ForEach(BenefitGroup.allCases) { group in
                    let items = visible.filter { $0.group == group }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text(group.title).font(.title3.bold())
                                Spacer()
                                Text("\(items.count) 项").font(.caption).foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: phoneLayout ? [GridItem(.flexible(), alignment: .top)] : [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                                ForEach(items) { info in
                                    OfferPanel(info: info, onEdit: info.canEdit ? {
                                        editing = info
                                    } : nil)
                                    .padding(.bottom, 8)
                                    .contextMenu {
                                        if info.canEdit, let rule = info.legacyRule {
                                            Button("编辑活动", systemImage: "pencil") { editing = info }
                                            if !rule.isWelcome { Button("归档活动", systemImage: "archivebox") { hiding = info } }
                                        } else if info.canChangeHiddenState {
                                            Button(info.isHidden ? "取消隐藏" : "隐藏活动",
                                                   systemImage: info.isHidden ? "eye" : "eye.slash") {
                                                hiding = info
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
            }
            .padding(phoneLayout ? PilotTheme.phonePagePadding : PilotTheme.pagePadding).frame(maxWidth: 1120).frame(maxWidth: .infinity)
        }
        .background(PilotTheme.canvas)
        .searchable(text: $search, prompt: "活动、卡片或优惠条件")
        .onChange(of: cards.filter { !$0.isArchived }.map(\.id)) { _, visibleIDs in
            if let selectedCardID, !visibleIDs.contains(selectedCardID) { self.selectedCardID = nil }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if phoneLayout {
                    Button("添加活动", systemImage: "plus", action: { showingAdd = true }).labelStyle(.iconOnly)
                } else {
                    Button("添加活动", systemImage: "plus", action: { showingAdd = true })
                }
            }
        }
        .sheet(isPresented: $showingAdd) { RuleEditor() }
        .sheet(item: $editing) { info in
            if let rule = info.legacyRule { RuleEditor(rule: rule) }
        }
        .alert(hiding?.isUserAdded == true ? "归档活动？" : "隐藏活动？", isPresented: Binding(get: { hiding != nil }, set: { if !$0 { hiding = nil } })) {
            Button("取消", role: .cancel) { hiding = nil }
            Button("确认") { if let info = hiding { setHidden(info, hidden: !info.isHidden) } }
        } message: {
            Text("活动将从权益列表隐藏；个人迎新记录、备注和已到账奖励会保留。")
        }
    }

    private var cardPicker: some View {
        Picker("银行卡", selection: $selectedCardID) {
            Text("所有银行卡").tag(nil as UUID?)
            ForEach(activeCards) { card in
                Text(card.displayName).tag(Optional(card.id))
            }
        }
    }

    private func clearFilters() {
        selectedCardID = nil
        includeEnded = false
        includeHidden = false
        favoritesOnly = false
        search = ""
    }

    private func setHidden(_ info: BenefitInfo, hidden: Bool) {
        do {
            if info.isUserAdded, let rule = info.legacyRule {
                if hidden { try RulePolicyStore.archive(rule, context: context) }
            } else if let cardKey = info.cardKey, let rule = info.catalogRule {
                try OfferStateStore.setHidden(hidden, cardKey: cardKey, cardID: info.cardID,
                                              offerID: rule.id, legacy: info.legacyRule, in: context)
            }
            hiding = nil
        } catch { self.error = PilotError.message(error) }
    }
}
