import SwiftUI
import SwiftData

struct CardsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Query(sort: \BankCard.createdAt) private var cards: [BankCard]
    @Query private var documents: [DomainRecord]
    @State private var showingAdd = false
    @State private var showingCatalog = false
    #if os(macOS)
    @State private var ledgerCard: BankCard?
    #endif
    @State private var search = ""
    @State private var showArchived = false
    @AppStorage("cards.displayMode") private var displayModeRaw = CardDisplayMode.together.rawValue
    @AppStorage("cards.phoneStyle") private var phoneStyleRaw = ""
    @AppStorage("cards.phoneCompactList") private var legacyCompactList = false
    @State private var kindFilter: CardKind?
    @State private var highlightedCardKey: String?
    @State private var addedDuringPresentation: String?
    @State private var revealCardKey: String?
    @State private var addedFeedback = 0
    @Namespace private var cardTransition

    private var isCompact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    /// Card artwork is decorative at accessibility sizes. Switching to the
    /// compact row keeps names, metadata, and actions readable without
    /// squeezing the card face into a fixed-height slot.
    private var phoneStyle: CardPhoneStyle {
        if let style = CardPhoneStyle(rawValue: phoneStyleRaw) { return style }
        return legacyCompactList ? .compact : .deck
    }

    private var phoneStyleSelection: Binding<CardPhoneStyle> {
        Binding(get: { phoneStyle }, set: { style in
            phoneStyleRaw = style.rawValue
            legacyCompactList = style == .compact
        })
    }

    private var usesCompactList: Bool {
        isCompact && (phoneStyle == .compact || typeSize.isAccessibilitySize)
    }

    private var displayMode: CardDisplayMode {
        CardDisplayMode(rawValue: displayModeRaw) ?? .together
    }

    private var orderedCards: [BankCard] {
        CardOrderStore.ordered(cards, context: context)
    }

    private var filtered: [BankCard] {
        let matching = orderedCards.filter {
            $0.isArchived == showArchived && (search.isEmpty || $0.displayName.localizedStandardContains(search))
        }
        guard displayMode == .together, let kindFilter else { return matching }
        return matching.filter { $0.cardKind == kindFilter }
    }

    private func cards(of kind: CardKind) -> [BankCard] {
        filtered.filter { $0.cardKind == kind }
    }

    var body: some View {
        let _ = documents.map(\.modifiedAt)
        let visible = filtered
        ScrollViewReader { proxy in
        ScrollView {
            if cards.isEmpty && isCompact {
                CardsEmptyState(onCatalog: { showingCatalog = true }, onManual: { showingAdd = true })
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, isCompact ? 24 : PilotTheme.pagePadding)
                    .padding(.vertical, isCompact ? 44 : 64)
            } else {
                VStack(alignment: .leading, spacing: isCompact ? 24 : PilotTheme.spacing + 8) {
                    if isCompact {
                        Text(showArchived ? "\(cards.count(where: \.isArchived)) 张已归档" : "\(cards.count(where: { !$0.isArchived })) 张使用中")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        desktopControls
                    }
                    if cards.isEmpty {
                        ContentUnavailableView {
                            Label("你的第一张卡", systemImage: "creditcard")
                        } description: {
                            Text("添加银行卡，集中查看权益、优惠与消费。")
                        } actions: {
                            Button("从资料库添加", action: { showingCatalog = true }).buttonStyle(.borderedProminent)
                            Button("手动添加", action: { showingAdd = true }).buttonStyle(.bordered)
                        }
                    } else if visible.isEmpty {
                        ContentUnavailableView {
                            Label("没有符合条件的卡片", systemImage: "creditcard")
                        } description: {
                            Text("试试其他卡片类型、状态，或清除搜索。")
                        } actions: {
                            Button("重置筛选", action: resetFilters)
                        }
                    } else if displayMode == .grouped {
                        ForEach(CardKind.allCases) { kind in
                            let group = cards(of: kind)
                            if !group.isEmpty {
                                VStack(alignment: .leading, spacing: isCompact ? 16 : 12) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(kind.label).font(.headline)
                                        Text("\(group.count) 张").font(.caption).foregroundStyle(.secondary)
                                    }
                                    cardCollection(group)
                                }
                            }
                        }
                    } else {
                        cardCollection(visible)
                    }
                    if !cards.isEmpty {
                        NavigationLink {
                            FinanceView()
                        } label: {
                            HStack {
                                Label("额度、账单与还款", systemImage: "chart.pie")
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.frame(minHeight: 44).pilotPanel()
                        }.buttonStyle(.plain)
                    }
                }
                .padding(isCompact ? 16 : PilotTheme.pagePadding)
                .padding(.bottom, isCompact ? 28 : 0)
                .frame(maxWidth: 1180).frame(maxWidth: .infinity)
            }
        }
        .onChange(of: highlightedCardKey) { _, key in
            guard isCompact, let key, key == revealCardKey,
                  filtered.contains(where: { $0.syncKey == key }) else { return }
            let target = scrollTarget(for: key)
            if reduceMotion { proxy.scrollTo(target, anchor: .center) }
            else { withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .center) } }
        }
        }
        .searchable(text: $search, prompt: "银行或卡片名称")
        .minimizedSearchToolbar()
        .background(PilotTheme.canvas)
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: kindFilter)
        .sensoryFeedback(.selection, trigger: orderedCards.map(\.syncKey))
        .sensoryFeedback(.success, trigger: addedFeedback)
        .onChange(of: cards.map(\.syncKey)) { oldKeys, newKeys in
            guard let added = newKeys.first(where: { !oldKeys.contains($0) }) else { return }
            if showingAdd || showingCatalog { addedDuringPresentation = added }
            else { highlightedCardKey = added }
            addedFeedback &+= 1
        }
        .task(id: highlightedCardKey) {
            guard highlightedCardKey != nil else { return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                highlightedCardKey = nil
                revealCardKey = nil
            }
        }
        .toolbar {
            if isCompact {
                ToolbarItem(placement: .topBarTrailing) { compactOptions }
                if !cards.isEmpty {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("添加银行卡", systemImage: "plus") {
                            addActions
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityHint("从资料库或手动添加银行卡")
                    }
                }
            }
        }
        #endif
        .sheet(isPresented: $showingAdd, onDismiss: revealAddedCard) { CardEditor() }
        .sheet(isPresented: $showingCatalog, onDismiss: revealAddedCard) { AddCardFlowView() }
        #if os(macOS)
        .sheet(item: $ledgerCard) { CardLedgerSheet(card: $0) }
        #endif
    }

    private var desktopControls: some View {
        VStack(alignment: .leading, spacing: PilotTheme.spacing + 8) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Text("\(cards.count(where: { !$0.isArchived })) 张使用中").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Picker("显示方式", selection: $displayModeRaw) {
                            ForEach(CardDisplayMode.allCases) { mode in Text(mode.label).tag(mode.rawValue) }
                        }
                    } label: {
                        Label("显示方式", systemImage: "square.grid.2x2")
                    }.buttonStyle(.glass)
                    Menu("添加卡片", systemImage: "plus") { addActions }.buttonStyle(.glassProminent)
                }
            }
            if cards.count > 1 {
                Text("拖动卡片可调整顺序").font(.caption).foregroundStyle(.tertiary)
            }
            if cards.contains(where: \.isArchived) {
                Picker("卡片状态", selection: $showArchived) {
                    Text("使用中").tag(false)
                    Text("已归档").tag(true)
                }.pickerStyle(.segmented).frame(maxWidth: 320)
            }
            if displayMode == .together {
                Picker("卡片类型", selection: $kindFilter) {
                    Text("全部").tag(CardKind?.none)
                    ForEach(CardKind.allCases) { kind in Text(kind.label).tag(Optional(kind)) }
                }.pickerStyle(.segmented).frame(maxWidth: 360)
            }
        }
    }

    private var addActions: some View {
        Group {
            Button("从卡片资料库添加", systemImage: "square.stack", action: { showingCatalog = true })
            Button("手动添加", systemImage: "pencil", action: { showingAdd = true })
        }
    }

    private var compactOptions: some View {
        Menu("卡片选项", systemImage: "ellipsis") {
            if !cards.isEmpty {
                Picker("卡片样式", selection: phoneStyleSelection) {
                    ForEach(CardPhoneStyle.allCases) { style in
                        Label(style.label, systemImage: style.symbol).tag(style)
                    }
                }
                Picker("显示方式", selection: $displayModeRaw) {
                    ForEach(CardDisplayMode.allCases) { mode in Text(mode.label).tag(mode.rawValue) }
                }
                if displayMode == .together {
                    Picker("卡片类型", selection: $kindFilter) {
                        Text("全部卡片").tag(CardKind?.none)
                        ForEach(CardKind.allCases) { kind in Text(kind.label).tag(Optional(kind)) }
                    }
                }
            }
            if cards.contains(where: \.isArchived) {
                Picker("卡片状态", selection: $showArchived) {
                    Text("使用中").tag(false)
                    Text("已归档").tag(true)
                }
            }
            if cards.count > 1 {
                Section("卡片顺序") {
                    Button("按添加时间排列", systemImage: "arrow.up.arrow.down", action: restoreAddedOrder)
                }
            }
        }.labelStyle(.iconOnly)
    }

    @ViewBuilder
    private func cardCollection(_ items: [BankCard]) -> some View {
        if isCompact {
            Group {
                if usesCompactList {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { card in
                            phoneCard(card)
                            if card.id != items.last?.id { Divider().padding(.leading, 102) }
                        }
                    }
                    .background(PilotTheme.surface, in: .rect(cornerRadius: PilotTheme.cardCornerRadius, style: .continuous))
                } else if phoneStyle == .deck {
                    StackedCardDeck(cards: items, transition: cardTransition, revealCardKey: revealCardKey)
                        .id(deckID(items.first?.cardKind))
                } else {
                    LazyVStack(spacing: 24) {
                        ForEach(items) { card in
                            phoneCard(card)
                        }
                    }
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: items.map(\.syncKey))
        } else {
            cardGrid(items)
        }
    }

    private func phoneCard(_ card: BankCard) -> some View {
        CompactWalletCardItem(card: card, transition: cardTransition, showsCompactRow: usesCompactList,
                              isHighlighted: highlightedCardKey == card.syncKey,
                              onDrop: { source, after in reorder(source, onto: card.syncKey, after: after) },
                              onMoveToStart: { move(card, toEnd: false) },
                              onMoveToEnd: { move(card, toEnd: true) })
            .id(card.syncKey)
    }

    private func deckID(_ kind: CardKind?) -> String {
        displayMode == .grouped ? "wallet-deck:" + (kind?.rawValue ?? "") : "wallet-deck:all"
    }

    private func scrollTarget(for key: String) -> String {
        guard !usesCompactList, phoneStyle == .deck,
              let selected = filtered.first(where: { $0.syncKey == key }) else { return key }
        return deckID(selected.cardKind)
    }

    private func revealAddedCard() {
        guard isCompact, let key = addedDuringPresentation,
              let card = cards.first(where: { $0.syncKey == key }) else {
            addedDuringPresentation = nil
            return
        }
        addedDuringPresentation = nil
        showArchived = false
        if !search.isEmpty && !card.displayName.localizedStandardContains(search) { search = "" }
        if displayMode == .together, let kindFilter, kindFilter != card.cardKind { self.kindFilter = nil }
        revealCardKey = key
        highlightedCardKey = key
    }

    private func resetFilters() {
        kindFilter = nil
        showArchived = false
        search = ""
    }

    private func restoreAddedOrder() {
        _ = persist(cards.sorted {
            $0.createdAt == $1.createdAt ? $0.syncKey < $1.syncKey : $0.createdAt < $1.createdAt
        }.map(\.syncKey))
    }

    @ViewBuilder
    private func cardGrid(_ items: [BankCard]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 24, alignment: .top)], alignment: .leading, spacing: 24) {
            ForEach(items) { card in
                CardGridItem(card: card, transition: cardTransition,
                             onDrop: { source, after in
                                 reorder(source, onto: card.syncKey, after: after)
                             },
                             onMoveToStart: { move(card, toEnd: false) },
                             onMoveToEnd: { move(card, toEnd: true) },
                             onLedger: {
                                 #if os(macOS)
                                 ledgerCard = card
                                 #endif
                             })
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: items.map(\.syncKey))
    }

    private func reorder(_ source: String, onto target: String, after: Bool) -> Bool {
        let keys = orderedCards.map(\.syncKey)
        guard let moved = CardOrderStore.moved(keys, source: source, target: target, after: after) else { return false }
        return persist(moved)
    }

    private func move(_ card: BankCard, toEnd: Bool) -> Bool {
        var keys = orderedCards.map(\.syncKey)
        guard let index = keys.firstIndex(of: card.syncKey) else { return false }
        let key = keys.remove(at: index)
        keys.insert(key, at: toEnd ? keys.endIndex : keys.startIndex)
        return keys == orderedCards.map(\.syncKey) ? false : persist(keys)
    }

    private func persist(_ keys: [String]) -> Bool {
        do {
            try CardOrderStore.save(keys, context: context)
            return true
        } catch {
            return false
        }
    }
}
