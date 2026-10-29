import SwiftUI
import SwiftData

struct WelcomeTrackingEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let info: BenefitInfo
    @State private var tracking: WelcomeTracking?
    @State private var initialTracking: WelcomeTracking?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let tracking {
                    editor(tracking)
                } else if let error { ContentUnavailableView("暂时无法读取迎新记录", systemImage: "exclamationmark.circle", description: Text(error)) }
                else { ProgressView() }
            }
            .navigationTitle("个人迎新记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DiscardChangesButton(hasChanges: tracking != initialTracking, discard: { dismiss() })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).bold().disabled(tracking == nil)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }.editorSize()
        .interactiveDismissDisabled(tracking != initialTracking)
        .task {
            guard initialTracking == nil else { return }
            do {
                let value = try OfferTrackingStore.load(for: info, context: context)
                tracking = value
                initialTracking = value
            } catch { self.error = PilotError.message(error) }
        }
    }

    private func editor(_ current: WelcomeTracking) -> some View {
        return Form {
            Section {
                Text(info.title).font(.headline)
                Text("按你的实际情况更新状态；App 不判断银行是否认可合资格消费。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker("当前状态", selection: field(\.status, fallback: current.status)) {
                    ForEach(WelcomeTrackingStatus.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("个人日期") {
                optionalDate("申请日期", keyPath: \.applicationDate, current: current)
                optionalDate("发卡日期", keyPath: \.issueDate, current: current)
                Toggle("记录个人消费截止日期", isOn: Binding(get: { tracking?.hasKnownDeadline ?? false }, set: { tracking?.deadlineConfirmed = $0 }))
                if current.hasKnownDeadline {
                    DatePicker("个人截止日期（请按条款确认）", selection: field(\.deadline, fallback: current.deadline), displayedComponents: .date)
                }
                if current.status == .received {
                    DatePicker("奖励到账日期", selection: Binding(get: { tracking?.receivedOn ?? .now }, set: { tracking?.receivedOn = $0 }), displayedComponents: .date)
                }
            }
            Section("目标与奖励") {
                TextField("消费门槛（HKD参考）", value: Binding(get: { Decimal(tracking?.thresholdCents ?? 0) / 100 }, set: { value in
                    if !value.isNaN, value >= 0, value <= Money.maxAmount { tracking?.thresholdCents = Money.cents(value) }
                }), format: .number)
                TextField("奖励内容", text: field(\.rewardContent, fallback: current.rewardContent), axis: .vertical).lineLimit(2...5)
                TextField("个人备注", text: field(\.notes, fallback: current.notes), axis: .vertical).lineLimit(3...8)
            }
            if !info.conditions.isEmpty {
                Section("官方条件与限制") {
                    BenefitConditionGrid(info: info)
                    BenefitNotesView(info: info)
                    if let url = URL(string: info.sourceURL), url.scheme == "https" { Link("查看官方条款", destination: url) }
                }
            } else if let url = URL(string: info.sourceURL), url.scheme == "https" {
                Section { Link("查看官方条款", destination: url) }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }.formStyle(.grouped).scrollDismissesKeyboard(.interactively)
    }

    private func field<Value>(_ keyPath: WritableKeyPath<WelcomeTracking, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { tracking?[keyPath: keyPath] ?? fallback }, set: { tracking?[keyPath: keyPath] = $0 })
    }

    private func optionalDate(_ title: String, keyPath: WritableKeyPath<WelcomeTracking, Date?>, current: WelcomeTracking) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("记录" + title, isOn: Binding(get: { tracking?[keyPath: keyPath] != nil }, set: { enabled in
                tracking?[keyPath: keyPath] = enabled ? (tracking?[keyPath: keyPath] ?? .now) : nil
            }))
            if let date = current[keyPath: keyPath] {
                DatePicker(title, selection: Binding(get: { tracking?[keyPath: keyPath] ?? date }, set: { tracking?[keyPath: keyPath] = $0 }), displayedComponents: .date)
            }
        }
    }

    private func save() {
        guard var value = tracking else { return }
        if value.status == .received && value.receivedOn == nil { value.receivedOn = .now }
        do { try OfferTrackingStore.save(value, for: info, context: context); dismiss() }
        catch { self.error = PilotError.message(error) }
    }
}
