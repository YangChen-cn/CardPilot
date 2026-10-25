import SwiftUI
import SwiftData

struct RuleEditor: View {
    @State private var savedFeedback = 0

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BankCard.createdAt) private var cards: [BankCard]
    @State private var draft: RuleDraft

    init(rule: RewardRule? = nil, cardID: UUID? = nil) {
        _draft = State(initialValue: RuleDraft(rule: rule, cardID: cardID))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("活动资料") {
                    TextField("活动名称", text: $draft.name)
                    Picker("银行卡", selection: $draft.cardID) {
                        Text("请选择").tag(nil as UUID?)
                        ForEach(cards) { Text($0.displayName).tag(Optional($0.id)) }
                    }.disabled(draft.existing != nil)
                    Picker("活动类型", selection: $draft.kind) {
                        Text("日常或限时优惠").tag("cashback")
                        Text("迎新奖励").tag("welcome")
                    }.disabled(draft.existing != nil)
                    Toggle("已核实活动有效期", isOn: $draft.periodKnown)
                    if draft.periodKnown {
                        DatePicker("开始日期", selection: $draft.startsOn, displayedComponents: .date)
                        DatePicker("截止日期", selection: $draft.endsOn, displayedComponents: .date)
                    }
                }
                Section("主要优惠 · 选填") {
                    TextField("公开优惠比例（%）", value: $draft.rate, format: .number)
                    TextField("回赠上限（HKD）", value: $draft.cap, format: .number)
                    Picker("上限范围", selection: $draft.period) { Text("每月").tag("monthly"); Text("整期").tag("campaign") }
                    if draft.kind == "welcome" {
                        TextField("消费门槛（HKD）", value: $draft.threshold, format: .number)
                        TextField("现金奖励（HKD）", value: $draft.bonus, format: .number)
                    }
                    Text("礼品、登记要求及特殊限制可写在下方条款说明中。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("适用范围 · 选填") {
                    Picker("消费类别", selection: $draft.category) {
                        Text("未指定").tag("")
                        ForEach(SpendCategory.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    Picker("币种", selection: $draft.currency) {
                        Text("未指定").tag("")
                        ForEach(Currency.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    TextField("指定商户", text: $draft.merchants, axis: .vertical).lineLimit(2...4)
                    TextField("支付方式限制", text: $draft.paymentMethod)
                }
                Section("条款与来源") {
                    TextField("优惠内容、登记要求及其他限制", text: $draft.notes, axis: .vertical).lineLimit(4...10)
                    TextField("官方条款网址", text: $draft.sourceURL)
                }
                if let rule = draft.existing, (try? RulePolicyStore.state(rule).pending) != nil {
                    Section("官方资料有更新") {
                        Text("采用更新不会清除个人迎新状态或已到账记录。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("采用最新官方资料", action: { acceptPending(rule) })
                    }
                }
                if let error = draft.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .formStyle(.grouped)
            .navigationTitle(draft.existing == nil ? "添加活动" : "编辑活动资料")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: { dismiss() }) }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).bold().disabled(cards.isEmpty) }
            }
        }.editorSize()
        .onAppear { if draft.cardID == nil { draft.cardID = cards.first?.id } }
        .sensoryFeedback(.success, trigger: savedFeedback)
    }

    private func save() { if draft.save(in: context, cards: cards) { savedFeedback &+= 1; dismiss() } }
    private func acceptPending(_ rule: RewardRule) {
        do { try Persistence.save(context) { try RulePolicyStore.acceptPending(rule, context: context) }; dismiss() }
        catch { draft.error = "未能更新资料，请重试。" }
    }
}
