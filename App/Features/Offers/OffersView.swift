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
    @State private var search = ""
    @State private var error: String?

    private var phoneLayout: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private var filtered: [BenefitInfo] {
        let _ = cards.map(\.modifiedAt)
        let _ = documents.map(\.modifiedAt)
        let _ = catalog.revision
        return OfferStore.offers(context: context).filter { info in
            (includeHidden || !info.isHidden) && !info.isArchived
                && (includeEnded || (!info.isEnded && !info.isHistorical))
                && (search.isEmpty || info.title.localizedStandardContains(search)
                    || info.cardName.localizedStandardContains(search)
                    || info.conditions.contains(where: { $0.localizedStandardContains(search) }))
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
                        Menu("权益筛选", systemImage: includeEnded || includeHidden ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") {
                            Toggle("包括已结束", isOn: $includeEnded)
                            Toggle("显示已隐藏", isOn: $includeHidden)
                        }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    } else {
                        Toggle("包括已结束", isOn: $includeEnded).toggleStyle(.switch).fixedSize()
                        Toggle("显示已隐藏", isOn: $includeHidden).toggleStyle(.switch).fixedSize()
                    }
                }
                if visible.isEmpty {
                    ContentUnavailableView("暂无匹配的权益", systemImage: "gift", description: Text("试试其他关键词，或为银行卡添加活动。"))
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
