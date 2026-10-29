import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \BankCard.createdAt) private var cards: [BankCard]
    @Query(filter: #Predicate<DomainRecord> {
        ($0.kind == "review" || $0.kind == "mailReview") && !$0.isDeleted
    }) private var pendingDocuments: [DomainRecord]
    @State private var cloud = MailCloudController.shared
    @State private var search = ""
    @State private var filterCard: UUID?
    @State private var filterCategory: String?
    @State private var month = LedgerQuery.monthStart(.now)
    @State private var lastCurrentMonth = LedgerQuery.monthStart(.now)
    @State private var selectedDate = Date.now
    @State private var allHistory = false
    @State private var page = LedgerPage(records: [], nextOffset: nil, scannedCount: 0)
    @State private var loadingID: UUID?
    @State private var displayedQuery: LedgerQuery?
    @State private var displayedRevision = -1
    @State private var revision = 0
    @State private var showingMonthPicker = false
    @State private var importingSMS = false
    @State private var importingCSV = false
    @State private var addingCard = false
    @State private var adding = false
    @State private var editing: SpendTransaction?
    @State private var deleting: SpendTransaction?
    @State private var confirmingDelete = false
    @State private var showingCategoryTotals = false
    @State private var error: String?
    @State private var savedMessage: String?
    @State private var feedbackRevision = 0
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private let scopedCardID: UUID?
    private let scopedCardName: String?

    init(card: BankCard? = nil) {
        scopedCardID = card?.id
        scopedCardName = card?.name
    }

    private var phoneLayout: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private var loading: Bool { loadingID != nil }
    private var pageIsCurrent: Bool { displayedQuery == query && displayedRevision == revision }
    private var visibleRecords: [SpendTransaction] { pageIsCurrent ? page.records : [] }
    private var monthLabel: String {
        let parts = HKCalendar.calendar.dateComponents([.year, .month], from: month)
        return "\(parts.year ?? 0) 年 \(parts.month ?? 0) 月"
    }
    private var hasFilters: Bool { filterCard != nil || filterCategory != nil }
    private var canRecord: Bool {
        cards.contains { !$0.isArchived && (scopedCardID == nil || $0.id == scopedCardID) }
    }
    private var query: LedgerQuery {
        LedgerQuery(month: allHistory ? nil : month, cardID: scopedCardID ?? filterCard,
                    category: filterCategory, search: search)
    }

    private struct RefreshKey: Equatable {
        let query: LedgerQuery
        let revision: Int
    }

    var body: some View {
        let groups = Dictionary(grouping: visibleRecords) { HKCalendar.start($0.date) }
            .map { TransactionDayGroup(date: $0.key, transactions: $0.value) }
            .sorted { $0.date > $1.date }
        ledgerContainer {
            Section {
                VStack(alignment: .leading, spacing: phoneLayout ? 16 : 20) {
                    monthControls
                    if !pageIsCurrent && error == nil {
                        ProgressView("正在读取交易").frame(minHeight: 44)
                    } else if allHistory {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("全部历史").font(.headline)
                            Text("已加载 \(visibleRecords.count) 笔" + (search.isEmpty ? "交易" : "匹配交易"))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else {
                        summary(visibleRecords)
                    }
                    if pendingDocuments.count > 0 {
                        NavigationLink {
                            ReviewTransactionsView()
                        } label: {
                            HStack {
                                Label((scopedCardID == nil ? "" : "全部卡片 · ") + "\(pendingDocuments.count) 笔交易待核对", systemImage: "checkmark.bubble")
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: PilotTheme.minimumTouchTarget)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    mailStatus
                    if !visibleRecords.isEmpty || hasFilters || allHistory || !search.isEmpty {
                        HStack {
                            if hasFilters { Text("已筛选").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            filters
                        }
                    }
                }
                .padding(.vertical, 8)
                #if os(iOS)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                #endif
            }
            if pageIsCurrent && !loading && visibleRecords.isEmpty && error == nil {
                Section { emptyState }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.transactions) { transaction in transactionRow(transaction) }
                } header: {
                    groupHeader(group)
                }
            }
            if pageIsCurrent && page.nextOffset != nil {
                Section {
                    Button {
                        Task { await loadMore() }
                    } label: {
                        if loading { ProgressView().frame(maxWidth: .infinity) }
                        else { Text("加载更多交易").frame(maxWidth: .infinity, minHeight: 44) }
                    }.disabled(loading)
                }
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                    Button("重试") { revision &+= 1 }
                }
            }
        }
        .navigationTitle(scopedCardName.map { $0 + "账本" } ?? "交易账本")
        .searchable(text: $search, prompt: "搜索商户、卡片或分类")
        .minimizedSearchToolbar()
        .toolbar { ledgerToolbar }
        .sheet(isPresented: $importingSMS) { SMSImportView() }
        .sheet(isPresented: $importingCSV) { CSVImportView() }
        .sheet(isPresented: $addingCard) { AddCardFlowView() }
        .sheet(isPresented: $adding) {
            TransactionEditor(cardID: scopedCardID) { message in
                savedMessage = message
                feedbackRevision &+= 1
            }
        }
        .sheet(item: $editing) { TransactionEditor(transaction: $0) }
        .sheet(isPresented: $showingMonthPicker) { monthPicker }
        .confirmationDialog("删除这笔交易？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除交易", role: .destructive) { if let deleting { remove(deleting) } }
        } message: {
            if let deleting { Text("\(deleting.merchant) · \(Money.text(deleting.amountCents, currency: deleting.currency))\n这笔消费将从账本和消费统计中移除。") }
        }
        .safeAreaInset(edge: .top) {
            if let savedMessage {
                Label(savedMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(PilotTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .task(id: feedbackRevision) {
            guard feedbackRevision > 0 else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            savedMessage = nil
        }
        .task(id: RefreshKey(query: query, revision: revision)) { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { notification in
            guard let saved = notification.object as? ModelContext,
                  saved.container === context.container else { return }
            revision &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            advanceCurrentMonth()
            revision &+= 1
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                advanceCurrentMonth()
                revision &+= 1
            }
        }
        .task {
            // The ledger uses Hong Kong dates even if the device is elsewhere.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(max(1, HKCalendar.dayAfter(.now).timeIntervalSinceNow))) }
                catch { return }
                advanceCurrentMonth()
                revision &+= 1
            }
        }
    }

    private var emptyState: some View {
        let filtering = !search.isEmpty || hasFilters
        let archivedCard = scopedCardID != nil && !canRecord
        return VStack(spacing: 14) {
            Image(systemName: filtering ? "magnifyingglass" : (!canRecord && !archivedCard ? "creditcard" : "receipt"))
                .font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(filtering ? "没有符合条件的交易" : (!canRecord && !archivedCard ? "先添加一张银行卡" : (allHistory ? "还没有交易记录" : "这个月份还没有记录")))
                .font(.headline)
            Text(filtering ? (allHistory ? "试试其他关键词或筛选条件。" : "试试其他关键词、月份或筛选条件。") : (archivedCard ? "这张卡已归档，仍可切换月份查看记录。" : (!canRecord ? "添加银行卡后，就可以记录日常消费。" : "切换月份查看其他记录，或记下新消费。")))
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if filtering {
                Button("清除筛选", action: clearFilters).frame(minHeight: 44)
            } else if !archivedCard {
                Button(canRecord ? "记一笔" : "从资料库添加", systemImage: "plus") {
                    if canRecord { adding = true } else { addingCard = true }
                }.buttonStyle(.borderedProminent).controlSize(.large).frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, phoneLayout ? 32 : 48)
    }

    private var monthControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    selectedDate = month
                    showingMonthPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Text(allHistory ? "全部历史" : monthLabel).font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.down").font(.caption).accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择月份，当前为" + (allHistory ? "全部历史" : monthLabel))
                Button(action: { changeMonth(-1) }) {
                    Label("上个月", systemImage: "chevron.left").labelStyle(.iconOnly)
                        .frame(width: 44, height: 44).contentShape(.rect)
                }.buttonStyle(.plain).disabled(allHistory)
                Button(action: { changeMonth(1) }) {
                    Label("下个月", systemImage: "chevron.right").labelStyle(.iconOnly)
                        .frame(width: 44, height: 44).contentShape(.rect)
                }.buttonStyle(.plain).disabled(allHistory || month >= LedgerQuery.monthStart(.now))
            }
            if allHistory {
                Button("返回本月") {
                    month = LedgerQuery.monthStart(.now)
                    allHistory = false
                }.font(.subheadline).frame(minHeight: 44)
            }
        }
    }

    private var monthPicker: some View {
        NavigationStack {
            Form {
                DatePicker("选择月份中的任意一天", selection: $selectedDate, in: ...Date.now, displayedComponents: .date)
                    .environment(\.calendar, HKCalendar.calendar)
                    .environment(\.timeZone, HKCalendar.calendar.timeZone)
            }
            .formStyle(.grouped)
            .navigationTitle("选择月份")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showingMonthPicker = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        month = LedgerQuery.monthStart(selectedDate)
                        allHistory = false
                        showingMonthPicker = false
                    }
                }
            }
        }.editorSize()
    }

    private func advanceCurrentMonth() {
        let current = LedgerQuery.monthStart(.now)
        if !allHistory && month == lastCurrentMonth { month = current }
        lastCurrentMonth = current
    }

    private func changeMonth(_ offset: Int) {
        if let value = HKCalendar.calendar.date(byAdding: .month, value: offset, to: month) {
            month = LedgerQuery.monthStart(value)
        }
    }

    private func summary(_ records: [SpendTransaction]) -> some View {
        let valued = records.filter(\.hasHKDValuation)
        let unvalued = records.filter { !$0.hasHKDValuation }
        let originals = OriginalCurrencyTotals.text(unvalued.map(SpendInput.init))
        return VStack(alignment: .leading, spacing: 8) {
            Text(search.isEmpty && !hasFilters ? "已记录消费" : "筛选消费")
                .font(.subheadline).foregroundStyle(.secondary)
            if !valued.isEmpty || unvalued.isEmpty {
                Text(Money.text(valued.reduce(0) { $0 + $1.hkdCents }))
                    .font(.largeTitle.weight(.semibold)).monospacedDigit()
            }
            if !originals.isEmpty {
                Text(originals).font(valued.isEmpty ? .title2.weight(.semibold) : .subheadline).monospacedDigit()
                Text(valued.isEmpty ? "按原币保存，暂无港币折算" : "港币合计仅含可换算记录；其他消费按原币列示")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("\(records.count) 笔交易" + (hasFilters || !search.isEmpty ? " · 已筛选" : ""))
                .font(.subheadline).foregroundStyle(.secondary)
            if showingCategoryTotals {
                let categories = Dictionary(grouping: valued, by: \.category).map { name, purchases in
                    CategoryTotal(name: name, cents: purchases.reduce(0) { $0 + $1.hkdCents })
                }.sorted { $0.cents > $1.cents }
                Divider().padding(.vertical, 4)
                Text("消费分类 · 仅含可换算记录").font(.subheadline.weight(.medium))
                ForEach(categories) { category in
                    LabeledContent(category.name, value: Money.text(category.cents))
                        .font(.subheadline).monospacedDigit()
                }
                if categories.isEmpty { Text("当前月份暂无可换算记录").font(.caption).foregroundStyle(.secondary) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mailStatus: some View {
        Group {
            if cloud.isConnected || cloud.isSyncing || cloud.error != nil {
                NavigationLink {
                    BankMailSettingsView()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: cloud.error == nil ? "envelope" : "exclamationmark.circle")
                        if cloud.isSyncing { Text("银行邮件正在更新") }
                        else if cloud.error != nil { Text("银行邮件暂未更新，查看详情") }
                        else if let date = cloud.lastSyncAt {
                            Text("邮件上次导入：" + date.formatted(date: .abbreviated, time: .shortened))
                        } else { Text("银行邮件已连接") }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: PilotTheme.minimumTouchTarget)
                    .contentShape(.rect)
                }.buttonStyle(.plain)
            }
        }
    }

    private func groupHeader(_ group: TransactionDayGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.title).font(.subheadline.weight(.semibold))
            if !allHistory {
                if group.transactions.contains(where: \.hasHKDValuation) {
                    Text(Money.text(group.totalCents)).font(.caption).monospacedDigit()
                }
                let originals = OriginalCurrencyTotals.text(group.transactions.filter { !$0.hasHKDValuation }.map(SpendInput.init))
                if !originals.isEmpty { Text(originals).font(.caption).monospacedDigit() }
            }
        }.textCase(nil).padding(.vertical, 4)
    }

    @ToolbarContentBuilder private var ledgerToolbar: some ToolbarContent {
        #if os(iOS)
        if phoneLayout {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ledgerOptions.labelStyle(.iconOnly)
                if canRecord && (!visibleRecords.isEmpty || hasFilters || !search.isEmpty) {
                    Button("记一笔", systemImage: "plus", action: { adding = true })
                        .labelStyle(.iconOnly)
                }
            }
        } else {
            ToolbarItem(placement: .primaryAction) { ledgerOptions }
        }
        #else
        ToolbarItem(placement: .primaryAction) {
            Button("记一笔", systemImage: "plus", action: { adding = true })
                .disabled(!canRecord).keyboardShortcut("n", modifiers: .command)
        }
        ToolbarItem(placement: .primaryAction) { ledgerOptions }
        #endif
    }

    private var ledgerOptions: some View {
        Menu("账本选项", systemImage: "ellipsis") {
            Section("筛选消费") { filterOptions }
            if !allHistory { Toggle("查看分类统计", isOn: $showingCategoryTotals) }
            Section("导入") {
                Button("粘贴短信", systemImage: "text.bubble", action: { importingSMS = true })
                Button("导入 CSV", systemImage: "doc.badge.plus", action: { importingCSV = true })
            }
            #if os(iOS)
            if !phoneLayout {
                Button("记一笔", systemImage: "plus", action: { adding = true }).disabled(!canRecord)
            }
            #endif
        }
    }

    @ViewBuilder private func ledgerContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        #if os(macOS)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) { content() }
                .padding(PilotTheme.pagePadding).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.background(PilotTheme.canvas)
        #else
        List { content() }.groupedListStyle().background(PilotTheme.groupedCanvas)
        #endif
    }

    private var filters: some View {
        Menu {
            filterOptions
        } label: {
            Label(hasFilters || allHistory ? "已筛选" : "筛选", systemImage: hasFilters || allHistory ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
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
        Toggle("搜索全部历史", isOn: $allHistory)
        if hasFilters || !search.isEmpty || allHistory { Button("清除筛选", action: clearFilters) }
    }

    private func transactionRow(_ transaction: SpendTransaction) -> some View {
        HStack(spacing: 0) {
            Button(action: { editing = transaction }) { TransactionRow(transaction: transaction) }
                .buttonStyle(.plain)
                .accessibilityHint("编辑这笔消费")
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

    private func reload() async {
        let requested = query
        let requestedRevision = revision
        let token = UUID()
        loadingID = token
        error = nil
        defer { if loadingID == token { loadingID = nil } }
        do {
            if !requested.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await Task.sleep(for: .milliseconds(200))
            }
            let result = try await LedgerData.load(requested, in: context)
            guard !Task.isCancelled, requested == query, requestedRevision == revision, loadingID == token else { return }
            page = result
            displayedQuery = requested
            displayedRevision = requestedRevision
            error = nil
        } catch is CancellationError { }
        catch {
            if requested == query, requestedRevision == revision, loadingID == token { self.error = "交易暂时无法读取，请重试。" }
        }
    }

    private func loadMore() async {
        guard pageIsCurrent, let offset = page.nextOffset, !loading else { return }
        let requested = query
        let requestedRevision = revision
        let token = UUID()
        loadingID = token
        defer { if loadingID == token { loadingID = nil } }
        do {
            let result = try await LedgerData.load(requested, in: context, from: offset)
            guard !Task.isCancelled, requested == query, requestedRevision == revision, loadingID == token else { return }
            page.records.append(contentsOf: result.records)
            page.nextOffset = result.nextOffset
            page.scannedCount += result.scannedCount
        } catch is CancellationError { }
        catch {
            if requested == query, requestedRevision == revision, loadingID == token { self.error = "更多交易暂时无法读取，请重试。" }
        }
    }

    private func confirmDeletion(_ transaction: SpendTransaction) {
        deleting = transaction
        confirmingDelete = true
    }

    private func clearFilters() {
        filterCard = nil
        filterCategory = nil
        search = ""
        allHistory = false
    }

    private func remove(_ transaction: SpendTransaction) {
        do { try Persistence.save(context) { Persistence.remove(transaction, context: context) }; deleting = nil }
        catch { self.error = PilotError.message(error) }
    }
}
