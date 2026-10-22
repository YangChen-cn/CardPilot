import SwiftUI
import SwiftData

struct SMSImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var referenceDate = Date.now
    @State private var preview: [BankMailTransaction] = []
    @State private var omitted = Set<String>()
    @State private var message: String?
    @State private var imported = false

    private var selected: [BankMailTransaction] { preview.filter { !omitted.contains($0.messageID) } }

    var body: some View {
        NavigationStack {
            Form {
                if !imported {
                    Section {
                        TextEditor(text: $text).frame(minHeight: 160)
                            .accessibilityLabel("粘贴银行交易短信")
                        DatePicker("短信参考日期", selection: $referenceDate, in: ...Date.now, displayedComponents: .date)
                        Text("支持中银、东亚交易短信，可一次粘贴多条。中银未写年份的日期以参考日期推定；请在预览中核对。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("识别交易", systemImage: "text.viewfinder", action: recognize)
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if !preview.isEmpty {
                        Section("确认要导入的消费") {
                            ForEach(preview, id: \.messageID) { item in
                                Button { toggle(item.messageID) } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: omitted.contains(item.messageID) ? "circle" : "checkmark.circle.fill")
                                            .foregroundStyle(PilotTheme.accent)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(item.merchant).font(.headline)
                                            Text(Money.text(item.amountCents, currency: item.currency)).monospacedDigit()
                                            Text("\(item.bankID.uppercased()) · 尾号 \(item.lastFour) · \(item.date.formatted(date: .abbreviated, time: .omitted))")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
                                }.buttonStyle(.plain)
                                .accessibilityAddTraits(omitted.contains(item.messageID) ? [] : .isSelected)
                            }
                        }
                        Section {
                            Text("与账本、Apple Pay、邮件相似的消费会进入交易核对。短信未说明的支付方式和地区保留待确认。")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("导入 \(selected.count) 笔消费", action: save)
                                .buttonStyle(.borderedProminent).disabled(selected.isEmpty)
                        }
                    }
                }
                if let message { Section { Text(message) } }
                if imported {
                    Section { NavigationLink("查看交易核对") { ReviewTransactionsView() } }
                }
            }
            .formStyle(.grouped).navigationTitle("短信记账")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(imported ? "完成" : "取消", action: { dismiss() }) } }
            .onChange(of: text) { _, _ in guard !imported else { return }; preview = []; omitted = []; message = nil }
            .onChange(of: referenceDate) { _, _ in preview = []; omitted = []; message = nil }
        }.editorSize()
    }

    private func toggle(_ id: String) {
        if !omitted.insert(id).inserted { omitted.remove(id) }
    }

    private func recognize() {
        do {
            preview = try BankSMSParser.parse(text, referenceDate: referenceDate); omitted = []
            message = preview.isEmpty ? "未识别到支持的交易短信。请粘贴完整原文；开卡通知、验证码和非交易内容不会记账。" : nil
        } catch { message = PilotError.message(error) }
    }

    private func save() {
        do {
            let result = try MailImportService.importTransactions(selected, in: context)
            message = "已新增 \(result.saved) 笔，校正 \(result.updated) 笔，待核对 \(result.pending) 笔。"
            imported = true; text = ""
        } catch { message = PilotError.message(error) }
    }
}
