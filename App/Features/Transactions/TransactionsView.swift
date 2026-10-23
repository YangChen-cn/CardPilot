import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SpendTransaction.date, order: .reverse) private var transactions: [SpendTransaction]
    @Query(sort: \BankCard.createdAt) private var cards: [BankCard]
    @State private var search = ""
    @State private var filterCard: UUID?
    @State private var filterCategory: String?
    @State private var monthOnly = false
    @State private var importingSMS = false
    @State private var adding = false
    @State private var editing: SpendTransaction?
    @State private var deleting: SpendTransaction?
    @State private var confirmingDelete = false
    @State private var error: String?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var addingCard = false
    @State private var importingCSV = false
    @State private var showingCategoryTotals = false
    #endif

    private let scopedCardID: UUID?
    private let scopedCardName: String?

    init(card: BankCard? = nil) {
        scopedCardID = card?.id; scopedCardName = card?.name
        if let id = card?.id {
            _transactions = Query(filter: #Predicate<SpendTransaction> { $0.card?.id == id }, sort: \SpendTransaction.date, order: .reverse)
        }
    }

    private var hasFilters: Bool { filterCard != nil || filterCategory != nil || monthOnly }

    private var filtered: [SpendTransaction] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return transactions.filter {
            (filterCard == nil || $0.card?.id == filterCard) &&
            (filterCategory == nil || $0.category == filterCategory) &&
            (!monthOnly || HKCalendar.isThisMonth($0.date)) &&
            (query.isEmpty || $0.merchant.localizedStandardContains(query) || $0.notes.localizedStandardContains(query) ||
                $0.category.localizedStandardContains(query) || ($0.card?.displayName.localizedStandardContains(query) ?? false))
        }
    }

    var body: some View {
        ledger
            .navigationTitle(scopedCardName.map { $0 + "账本" } ?? "交易账本")
            .toolbar { ledgerToolbar }
            .sheet(isPresented: $importingSMS) { SMSImportView() }
            .sheet(isPresented: $adding) { TransactionEditor(cardID: scopedCardID) }
            .sheet(item: $editing) { TransactionEditor(transaction: $0) }
            #if os(iOS)
            .sheet(isPresented: $addingCard) { AddCardFlowView() }
            .sheet(isPresented: $importingCSV) { CSVImportView() }
            #endif
            .confirmationDialog("删除这笔交易？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除交易", role: .destructive) { if let deleting { remove(deleting) } }
            } message: {
                if let deleting { Text("\(deleting.merchant) · \(Money.text(deleting.amountCents, currency: deleting.currency))\n这笔消费将从账本和消费统计中移除。") }
            }
    }

    @ViewBuilder private var ledger: some View {
        #if os(iOS)
        if sizeClass == .compact { phoneLedger }
        else { existingLedger }
        #else
        existingLedger
        #endif
    }

    private var existingLedger: some View {
        let filtered = filtered
        let groups = Dictionary(grouping: filtered) { HKCalendar.start($0.date) }
            .map { TransactionDayGroup(date: $0.key, transactions: $0.value) }.sorted { $0.date > $1.date }
        return ledgerContainer {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(monthOnly ? "本月已记录消费 · HKD" : "已记录消费 · HKD").font(.subheadline).foregroundStyle(.secondary)
                    Text(Money.text(filtered.reduce(0) { $0 + $1.hkdCents }))
                        .font(.largeTitle.weight(.semibold)).monospacedDigit()
                    if filtered.contains(where: { !$0.hasHKDValuation }) {
                        Text("港币合计仅含可换算记录；其他消费按原币列示。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(OriginalCurrencyTotals.text(filtered.map(SpendInput.init)))
                            .font(.subheadline).monospacedDigit()
                    }
                    HStack {
                        Text("\(filtered.count) 笔交易").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        filters
                    }
                }.padding(.vertical, 10)
            }
            if filtered.isEmpty {
                Section {
                    if transactions.isEmpty {
                        ContentUnavailableView {
                            Label("记录第一笔消费", systemImage: "receipt")
                        } description: {
                            Text("记录金额、商户和类别，轻松了解日常消费。")
                        } actions: {
                            Button("记一笔", systemImage: "plus", action: { adding = true }).buttonStyle(.borderedProminent)
                        }
                    } else {
                        ContentUnavailableView {
                            Label("没有符合条件的交易", systemImage: "magnifyingglass")
                        } description: {
                            Text("换个关键词，或清除筛选条件。")
                        } actions: {
                            Button("清除筛选", action: clearFilters)
                        }
                    }
                }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.transactions) { transaction in
                        transactionRow(transaction)
                    }
                } header: {
                    HStack {
                        Text(group.title)
                        Spacer()
                        Text(Money.text(group.totalCents)).monospacedDigit()
                    }.textCase(nil)
                }
            }
            if let error {
                Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            }
        }
        .searchable(text: $search, prompt: "搜索商户、卡片或分类")
    }

    @ToolbarContentBuilder private var ledgerToolbar: some ToolbarContent {
        #if os(iOS)
        if sizeClass == .compact {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !cards.isEmpty {
                    Menu("账本选项", systemImage: "ellipsis") {
                        if !transactions.isEmpty {
                            Section("筛选消费") { filterOptions }
                            Toggle("查看分类统计", isOn: $showingCategoryTotals)
                        }
                        Section("导入") {
                            Button("粘贴短信", systemImage: "text.bubble", action: { importingSMS = true })
                            Button("导入 CSV", systemImage: "doc.badge.plus", action: { importingCSV = true })
                        }
                    }.labelStyle(.iconOnly)
                }
                if !transactions.isEmpty {
                    Button("记一笔", systemImage: "plus", action: { adding = true })
                        .labelStyle(.iconOnly)
                }
            }
        } else {
            ToolbarItem(placement: .primaryAction) { existingToolbarAction }
        }
        #else
        ToolbarItem(placement: .primaryAction) { existingToolbarAction }
        #endif
    }

    @ViewBuilder private var existingToolbarAction: some View {
        if scopedCardID != nil { Button("记一笔", systemImage: "plus", action: { adding = true }) }
        else { Button("短信记账", systemImage: "text.bubble", action: { importingSMS = true }) }
    }

    #if os(iOS)
    @ViewBuilder private var phoneLedger: some View {
        if transactions.isEmpty {
            // A first-use action is not a list row. List/Section styling previously
            // compressed ContentUnavailableView's action label into an empty pill.
            ScrollView {
                ContentUnavailableView {
                    Label(cards.isEmpty ? "先添加一张银行卡" : "记录第一笔消费", systemImage: cards.isEmpty ? "creditcard" : "receipt")
                } description: {
                    Text(cards.isEmpty ? "选择银行卡，再记录日常消费。" : "记录金额、商户和类别，了解日常消费。")
                } actions: {
                    Button(cards.isEmpty ? "从资料库添加" : "记一笔", systemImage: "plus") {
                        if cards.isEmpty { addingCard = true } else { adding = true }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(.horizontal, PilotTheme.phonePagePadding)
                .padding(.vertical, PilotTheme.phoneSectionSpacing)
            }
            .defaultScrollAnchor(.center, for: .alignment)
            .background(PilotTheme.canvas)
        } else {
            let visible = filtered
            let groups = Dictionary(grouping: visible) { HKCalendar.start($0.date) }
                .map { TransactionDayGroup(date: $0.key, transactions: $0.value) }.sorted { $0.date > $1.date }
            List {
                Section {
                    phoneSummary(visible)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: PilotTheme.phonePagePadding, bottom: 20, trailing: PilotTheme.phonePagePadding))
                }
                if visible.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("没有符合条件的交易").font(.headline)
                            Text("试试其他关键词，或清除筛选。").font(.subheadline).foregroundStyle(.secondary)
                            Button("清除筛选", action: clearFilters).frame(minHeight: PilotTheme.minimumTouchTarget)
                        }.padding(.vertical, 12)
                    }.listRowSeparator(.hidden)
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.transactions) { transaction in transactionRow(transaction) }
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.title).font(.subheadline.weight(.semibold))
                            if group.transactions.contains(where: \.hasHKDValuation) {
                                Text(Money.text(group.totalCents)).font(.caption).monospacedDigit()
                            }
                            let originals = OriginalCurrencyTotals.text(group.transactions.map(SpendInput.init))
                            if !originals.isEmpty {
                                Text(originals).font(.caption).monospacedDigit()
                            }
                        }.textCase(nil).padding(.vertical, 4)
                    }
                }
                if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
            }
            .groupedListStyle()
            .background(PilotTheme.groupedCanvas)
            .searchable(text: $search, prompt: "搜索商户或分类")
            .minimizedSearchToolbar()
        }
    }

    private func phoneSummary(_ visible: [SpendTransaction]) -> some View {
        let isFiltering = hasFilters || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let records = isFiltering ? visible : transactions.filter { HKCalendar.isThisMonth($0.date) && $0.date <= .now }
        let valued = records.filter(\.hasHKDValuation)
        let categories = Dictionary(grouping: valued, by: \.category).map { name, purchases in
            CategoryTotal(name: name, cents: purchases.reduce(0) { $0 + $1.hkdCents })
        }.sorted { $0.cents > $1.cents }
        return VStack(alignment: .leading, spacing: 10) {
            Text(isFiltering ? "筛选消费 · HKD" : "本月已记录消费 · HKD")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(Money.text(valued.reduce(0) { $0 + $1.hkdCents }))
                .font(.largeTitle.weight(.semibold)).monospacedDigit()
            Text("\(records.count) 笔交易" + (hasFilters ? " · 已筛选" : ""))
                .font(.subheadline).foregroundStyle(.secondary)
            if records.contains(where: { !$0.hasHKDValuation }) {
                Text("港币合计仅含可换算记录").font(.caption).foregroundStyle(.secondary)
                Text(OriginalCurrencyTotals.text(records.filter { !$0.hasHKDValuation }.map(SpendInput.init)))
                    .font(.subheadline).monospacedDigit()
            }
            if showingCategoryTotals {
                Divider().padding(.vertical, 4)
                Text("消费分类 · 仅含可换算记录").font(.subheadline.weight(.medium))
                ForEach(categories) { category in
                    LabeledContent(category.name, value: Money.text(category.cents))
                        .font(.subheadline).monospacedDigit()
                }
                if categories.isEmpty {
                    Text("当前范围暂无可换算记录").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    #endif

    @ViewBuilder private func ledgerContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        #if os(macOS)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) { content() }
                .padding(PilotTheme.pagePadding).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.background(PilotTheme.canvas)
        #else
        List { content() }.listStyle(.inset)
        #endif
    }

    private var filters: some View {
        Menu {
            filterOptions
        } label: {
            Label(hasFilters ? "已筛选" : "筛选", systemImage: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.subheadline).frame(minHeight: 44)
        }
    }

    @ViewBuilder private var filterOptions: some View {
            if scopedCardID == nil {
                Picker("银行卡", selection: $filterCard) {
                    Text("全部卡片").tag(nil as UUID?)
                    ForEach(cards) { Text($0.displayName).tag(Optional($0.id)) }
                }
            }
            Picker("分类", selection: $filterCategory) {
                Text("全部分类").tag(nil as String?)
                ForEach(SpendCategory.allCases) { Text($0.rawValue).tag(Optional($0.rawValue)) }
            }
            Toggle("仅本月", isOn: $monthOnly)
            if hasFilters { Button("清除筛选", action: clearFilters) }
    }

    private func transactionRow(_ transaction: SpendTransaction) -> some View {
        HStack(spacing: 0) {
            Button(action: { editing = transaction }) { TransactionRow(transaction: transaction) }
                .buttonStyle(.plain)
            #if os(macOS)
            Menu("交易操作", systemImage: "ellipsis") {
                Button("编辑", systemImage: "pencil", action: { editing = transaction })
                Button("删除", systemImage: "trash", role: .destructive, action: { confirmDeletion(transaction) })
            }
            .menuStyle(.borderlessButton).labelStyle(.iconOnly).frame(width: 44, height: 44)
            #endif
        }
        .contextMenu {
            Button("编辑交易", systemImage: "pencil", action: { editing = transaction })
            Button("删除交易", systemImage: "trash", role: .destructive, action: { confirmDeletion(transaction) })
        }
        .swipeActions(allowsFullSwipe: false) {
            Button("删除", systemImage: "trash", role: .destructive, action: { confirmDeletion(transaction) })
            Button("编辑", systemImage: "pencil", action: { editing = transaction })
        }
    }

    private func confirmDeletion(_ transaction: SpendTransaction) {
        deleting = transaction; confirmingDelete = true
    }

    private func clearFilters() {
        filterCard = nil; filterCategory = nil; monthOnly = false; search = ""
    }

    private func remove(_ transaction: SpendTransaction) {
        do { try Persistence.save(context) { Persistence.remove(transaction, context: context) }; deleting = nil }
        catch { self.error = PilotError.message(error) }
    }
}
