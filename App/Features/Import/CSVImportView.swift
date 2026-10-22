import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CSVImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var cards: [BankCard]
    @State private var cardID = ""
    @State private var choosing = false
    @State private var requests: [TransactionRequest] = []
    @State private var message: String?
    @State private var imported = false
    var body: some View {
        NavigationStack {
            Form {
                Section("消费记录文件") {
                    Picker("银行卡", selection: $cardID) {
                        Text("请选择").tag("")
                        ForEach(cards.filter { !$0.isArchived }) { Text($0.displayName).tag($0.syncKey) }
                    }.disabled(!requests.isEmpty)
                    Button("选择CSV文件", systemImage: "doc", action: { choosing = true }).disabled(cardID.isEmpty)
                    Text("支持CardPilot格式的消费记录。银行账单需先转换列名；导入前会显示预览。").font(.caption).foregroundStyle(.secondary)
                }
                if !requests.isEmpty {
                    Section("预览 · \(requests.count)笔") {
                        ForEach(Array(requests.prefix(50).enumerated()), id: \.offset) { _, request in
                            LabeledContent(request.merchant, value: Money.text(request.amountCents, currency: request.currency))
                        }
                        Button("确认导入", action: apply).disabled(imported)
                    }
                }
                if let message { Text(message).foregroundStyle(.secondary) }
            }
            .formStyle(.grouped).navigationTitle("导入消费记录")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: { dismiss() }) } }
        }.editorSize()
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            do {
                let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 5_000_000 else { throw PilotError.invalid("文件不能超过5MB。") }
                requests = try CanonicalCSVAdapter().parse(Data(contentsOf: url), cardID: cardID)
                imported = false; message = nil
            } catch {
                if !PilotError.isCancellation(error) { requests = []; message = PilotError.message(error, fallback: "无法读取这份消费记录，请检查文件格式后重试。") }
            }
        }
    }
    private func apply() {
        do {
            let result = try TransactionBatchRecorder.record(requests, in: context)
            imported = true; message = "已导入\(result.saved)笔，跳过重复\(result.duplicate)笔，待核对\(result.pending)笔。"
        } catch { message = "导入未完成，未保存本批记录。\(PilotError.message(error))" }
    }
}
