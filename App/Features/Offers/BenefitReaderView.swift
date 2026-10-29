import SwiftUI
import SwiftData

/// Compact condition list used on offer cards and in the welcome editor.
/// The full reader below uses the same model with more breathing room.
struct BenefitConditionGrid: View {
    let info: BenefitInfo
    var compact = false

    var body: some View {
        if info.labeledTerms.isEmpty {
            Text("暂无更多条件，请以官方条款为准。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leading, horizontalSpacing: compact ? 10 : 16, verticalSpacing: compact ? 9 : 14) {
                ForEach(info.labeledTerms) { term in
                    GridRow(alignment: .firstTextBaseline) {
                        Text(term.label ?? "")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: compact ? 72 : 88, alignment: .leading)
                            .gridColumnAlignment(.leading)
                        BenefitTermValue(term: term, compact: compact)
                    }
                }
            }
        }
    }
}

private struct BenefitTermValue: View {
    let term: BenefitTerm
    var compact = false
    private let maxCompactChips = 4

    var body: some View {
        if term.isChipList, !term.chips.isEmpty {
            let shown = compact ? Array(term.chips.prefix(maxCompactChips)) : term.chips
            FlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, chip in
                    Text(chip)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(PilotTheme.accent.opacity(0.08), in: .capsule)
                        .overlay { Capsule().strokeBorder(PilotTheme.accent.opacity(0.12)) }
                }
                if compact, term.chips.count > maxCompactChips {
                    Text("+\(term.chips.count - maxCompactChips)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.primary.opacity(0.05), in: .capsule)
                }
            }
        } else {
            Text(term.value)
                .font(compact ? .subheadline : .body)
                .lineSpacing(compact ? 2 : 5)
                .lineLimit(compact ? 3 : nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BenefitNotesView: View {
    let info: BenefitInfo
    var compact = false
    var limit: Int?

    var body: some View {
        let notes = Array(info.noteTerms.prefix(limit ?? info.noteTerms.count))
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: compact ? 7 : 12) {
                ForEach(notes) { note in
                    Text(note.value)
                        .font(compact ? .subheadline : .callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(compact ? 2 : 5)
                        .lineLimit(compact ? 3 : nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A calm reading surface for the long merchant lists and policy notes that
/// would otherwise turn an offer card into a wall of text.
struct BenefitDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var personalDocuments: [DomainRecord]
    let info: BenefitInfo
    @State private var editingWelcome = false
    @State private var editingRule: RewardRule?
    @State private var personal: OfferPersonalState
    @State private var personalError: String?
    @State private var favoriteFeedback = 0

    init(info: BenefitInfo) {
        self.info = info
        _personal = State(initialValue: info.personal)
        var stateKeys: [String] = []
        if let cardKey = info.cardKey {
            stateKeys.append(OfferStateStore.key(cardKey: cardKey, offerID: info.overlayOfferID))
        }
        if let cardID = info.cardID {
            stateKeys.append(OfferStateStore.legacyKey(cardID: cardID, offerID: info.overlayOfferID))
        }
        let watchedKeys = stateKeys
        _personalDocuments = Query(filter: #Predicate<DomainRecord> { watchedKeys.contains($0.key) })
    }

    // The reader can present the personal rule editor. Rebuild that rule's
    // projection after a save instead of keeping the original title and terms.
    private var currentInfo: BenefitInfo {
        guard info.origin == .personal, let rule = info.legacyRule else { return info }
        var current = BenefitInfo(rule: rule)
        current.personal = personal
        return current
    }

    var body: some View {
        let current = currentInfo
        let tracking = current.isWelcome ? (try? OfferTrackingStore.load(for: current, context: context)) : nil
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header(current)
                    terms(current)
                    facts(current)
                    if let tracking { welcome(tracking) }
                    if info.origin == .official, info.requiresRegistration { personalSection }
                    official(current)
                }
                .padding(28)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(PilotTheme.canvas)
            .navigationTitle("权益详情")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if info.cardKey != nil, !info.isHistorical {
                        Button(personal.favorite ? "取消收藏" : "收藏",
                               systemImage: personal.favorite ? "star.fill" : "star",
                               action: toggleFavorite)
                            .tint(personal.favorite ? .yellow : nil)
                            .accessibilityLabel(personal.favorite ? "取消收藏" : "收藏此权益")
                            .symbolEffect(.bounce, value: personal.favorite)
                            .symbolEffectsRemoved(reduceMotion)
                            .sensoryFeedback(.selection, trigger: favoriteFeedback)
                    }
                    if info.canEdit, info.legacyRule != nil {
                        Menu("更多操作", systemImage: "ellipsis") {
                            Button("编辑活动", systemImage: "pencil", action: { editingRule = info.legacyRule })
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: { dismiss() })
                }
            }
        }
        .readerSize()
        .sheet(isPresented: $editingWelcome) { WelcomeTrackingEditor(info: currentInfo) }
        .sheet(item: $editingRule) { RuleEditor(rule: $0) }
        .onAppear(perform: refreshPersonal)
        .onChange(of: personalDocuments.map(\.modifiedAt)) { _, _ in refreshPersonal() }
        .alert("未能保存个人记录", isPresented: Binding(get: { personalError != nil }, set: { if !$0 { personalError = nil } })) {
            Button("好", role: .cancel) { personalError = nil }
        } message: { Text(personalError ?? "请重试。") }
    }

    private var personalSection: some View {
        GroupBox("我的记录") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("登记状态") {
                    Picker("登记状态", selection: $personal.enrollment) {
                        ForEach(OfferEnrollment.allCases, id: \.rawValue) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: personal.enrollment) { _, _ in saveEnrollment() }
                }
                Text("只记录你是否已登记，不会改动官方活动内容。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private func refreshPersonal() {
        guard let cardKey = info.cardKey else { return }
        do {
            personal = try OfferStateStore.load(cardKey: cardKey, cardID: info.cardID,
                                               offerID: info.overlayOfferID, legacy: info.legacyRule, in: context)
        } catch {
            personalError = PilotError.message(error, fallback: "暂时无法读取个人记录，请重试。")
        }
    }

    private func saveEnrollment() {
        guard let cardKey = info.cardKey else { return }
        do {
            personal = try OfferStateStore.setEnrollment(personal.enrollment, cardKey: cardKey, cardID: info.cardID,
                                                        offerID: info.overlayOfferID, legacy: info.legacyRule, in: context)
        } catch {
            personalError = PilotError.message(error, fallback: "请重试。")
        }
    }

    private func toggleFavorite() {
        guard !info.isHistorical, let cardKey = info.cardKey else { return }
        let favorite = !personal.favorite
        do {
            try OfferStateStore.setFavorite(favorite, cardKey: cardKey, cardID: info.cardID,
                                            offerID: info.overlayOfferID, legacy: info.legacyRule, in: context)
            personal.favorite = favorite
            favoriteFeedback &+= 1
        } catch {
            personalError = PilotError.message(error, fallback: "请重试。")
        }
    }

    private func header(_ info: BenefitInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(info.cardName).font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(info.group.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.primary.opacity(0.05), in: .capsule)
            }
            Text(info.title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(info.headline)
                .font(.title3.weight(.semibold))
                .foregroundStyle(PilotTheme.accent)
        }
    }

    private func welcome(_ tracking: WelcomeTracking) -> some View {
        let status = tracking.effectiveStatus()
        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label(status.label, systemImage: status.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PilotTheme.accent)
                    Spacer(minLength: 12)
                    Button("更新状态", action: { editingWelcome = true })
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if !tracking.rewardContent.isEmpty {
                    Text(tracking.rewardContent).font(.headline)
                }
                if tracking.thresholdCents > 0 {
                    DetailFact(label: "个人消费门槛", value: Money.text(tracking.thresholdCents))
                }
                if tracking.hasKnownDeadline {
                    DetailFact(label: "个人截止日", value: tracking.deadline.formatted(.dateTime.year().month().day()))
                }
                if !tracking.notes.isEmpty {
                    Text(tracking.notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private func facts(_ info: BenefitInfo) -> some View {
        GroupBox("活动信息") {
            VStack(alignment: .leading, spacing: 0) {
                DetailFact(label: "活动期", value: period(info))
                Divider().padding(.vertical, 12)
                DetailFact(label: "资料核实", value: info.verifiedOn.isEmpty ? "待核实" : info.verifiedOn)
                if let updated = info.updatedAt, !updated.isEmpty {
                    Divider().padding(.vertical, 12)
                    DetailFact(label: "内容更新", value: updated)
                }
                if !info.sourceURL.isEmpty {
                    Divider().padding(.vertical, 12)
                    DetailFact(label: "资料来源", value: sourceHost(info.sourceURL))
                }
            }
            .padding(.top, 4)
        }
    }

    private func terms(_ info: BenefitInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("适用条件与限制").font(.title3.bold())
            BenefitConditionGrid(info: info)
            if !info.noteTerms.isEmpty {
                Text("活动说明").font(.headline).padding(.top, 8)
                BenefitNotesView(info: info)
            }
        }
        .textSelection(.enabled)
    }

    private func official(_ info: BenefitInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = URL(string: info.sourceURL), url.scheme == "https" {
                Link(destination: url) {
                    Label("打开官方条款", systemImage: "safari")
                }
                .font(.subheadline.weight(.medium))
            } else {
                Text("暂无官方条款链接，请以银行公布的资料为准。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("CardPilot 仅整理公开条款，不判断你的交易或资格。个人迎新状态由你自行记录。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func sourceHost(_ source: String) -> String {
        URL(string: source)?.host ?? source
    }

    private func period(_ info: BenefitInfo) -> String {
        info.periodDescription + "（" + info.periodStatus.label + "）"
    }
}

private struct DetailFact: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private extension View {
    @ViewBuilder func readerSize() -> some View {
        #if os(macOS)
        frame(minWidth: 700, idealWidth: 820, minHeight: 620, idealHeight: 780)
        #else
        self
        #endif
    }
}
