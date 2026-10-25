import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CardEditor: View {
    @State private var savedFeedback = 0

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CardDraft
    @State private var choosingImage = false
    private let onSaved: (() -> Void)?

    init(card: BankCard? = nil, onSaved: (() -> Void)? = nil) {
        _draft = State(initialValue: CardDraft(card: card))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("卡片资料") {
                    TextField("银行", text: $draft.bank)
                    TextField("卡片名称", text: $draft.name)
                    Picker("卡组织", selection: $draft.network) {
                        ForEach(["Visa", "Mastercard", "UnionPay", "American Express", "其他"], id: \.self) { Text($0) }
                    }
                    Picker("类型", selection: $draft.kind) { Text("信用卡").tag("信用卡"); Text("扣账卡").tag("借记卡") }
                    TextField("卡片尾号（后4位）", text: $draft.lastFour)
                    Text("用于匹配银行交易邮件，只需后4位，无需完整卡号或安全码。").font(.caption).foregroundStyle(.secondary)
                }
                Section("账单与权益") {
                    Stepper(draft.statementDay == 0 ? "账单日：待填写" : "账单日：每月 \(draft.statementDay) 日", value: $draft.statementDay, in: 0...31)
                    Stepper(draft.paymentDay == 0 ? "还款日：待填写" : "还款日：每月 \(draft.paymentDay) 日", value: $draft.paymentDay, in: 0...31)
                    TextField("基础回赠（%）", value: $draft.basePercent, format: .number)
                    TextField("外币手续费（%）", value: $draft.feePercent, format: .number)
                    TextField("境外港币手续费（%）", value: $draft.overseasHKDPercent, format: .number)
                    Text("31日在较短月份按月末显示。提醒日期是个人设置，请以银行账单为准。").font(.caption).foregroundStyle(.secondary)
                }
                Section("外观与来源") {
                    Picker("卡片配色", selection: $draft.theme) {
                        Text("松石绿").tag("teal"); Text("紫罗兰").tag("purple"); Text("海蓝").tag("blue")
                        Text("朱红").tag("red"); Text("琥珀").tag("orange")
                    }
                    if let image = draft.imageData { LocalCardImage(data: image).frame(height: 100) }
                    Button("导入卡面图片", systemImage: "photo", action: { choosingImage = true })
                    if draft.imageData != nil { Button("移除卡面", role: .destructive, action: { draft.imageData = nil }) }
                    TextField("官方资料 URL（选填）", text: $draft.sourceURL)
                    Toggle("归档卡片（隐藏卡片，保留账本与权益历史）", isOn: $draft.isArchived)
                }
                if let error = draft.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .formStyle(.grouped)
            .navigationTitle(draft.existing == nil ? "添加银行卡" : "编辑银行卡")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: { dismiss() }) }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).bold() }
            }
        }
        .editorSize()
        .fileImporter(isPresented: $choosingImage, allowedContentTypes: [.image]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                guard (values.fileSize ?? 0) <= 8_000_000 else { throw PilotError.invalid("图片超过8MB。") }
                let data = try Data(contentsOf: url); try CatalogImporter.validateImage(data)
                draft.imageData = data
            } catch { draft.error = PilotError.message(error) }
        }
        .sensoryFeedback(.success, trigger: savedFeedback)
    }
    private func save() { if draft.save(in: context) { savedFeedback &+= 1; onSaved?(); dismiss() } }
}
