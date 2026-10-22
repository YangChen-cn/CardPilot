import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BankMailSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var documents: [DomainRecord]
    @State private var cloud = MailCloudController.shared
    @State private var url = ""
    @State private var token = ""
    @State private var importingSMS = false
    @State private var importing = false
    @State private var importMessage: String?

    private var pendingCount: Int { documents.count { $0.kind == "mailReview" && !$0.isDeleted } }

    var body: some View {
        Form {
            Section {
                Label(cloud.isConnected ? "邮箱采集已连接" : "连接邮箱采集服务", systemImage: "envelope.badge.shield.half.filled")
                    .font(.headline)
                Text("云端每天整理银行交易提醒，打开 CardPilot 时导入并核对。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("支持中银、东亚消费通知及汇丰扣账卡网上消费；转账、还款和投资通知不会计为消费。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("云端连接") {
                TextField("服务网址", text: $url)
                    .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never).keyboardType(.URL)
                #endif
                SecureField("连接码", text: $token)
                    .autocorrectionDisabled()
                Button(cloud.isSyncing ? "正在连接…" : "保存并读取邮件") {
                    Task { await cloud.connect(url: url, token: token, in: context) }
                }.disabled(cloud.isSyncing)
                Link("打开 Google 云端脚本", destination: URL(string: "https://script.google.com/home")!)
                Text("连接码保存在此设备的钥匙串中，不随账本同步。两端可分别连接同一服务。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if cloud.isConnected {
                Section("导入") {
                    Toggle("自动导入新邮件", isOn: $cloud.automatic)
                    if let date = cloud.lastSyncAt { LabeledContent("最近导入", value: date.formatted(date: .abbreviated, time: .shortened)) }
                    Button("立即更新", systemImage: "arrow.clockwise") { Task { await cloud.sync(in: context, force: true) } }
                        .disabled(cloud.isSyncing)
                    Button("断开连接", role: .destructive, action: cloud.disconnect).disabled(cloud.isSyncing)
                }
            }
            Section("邮件核对") {
                NavigationLink("待核对邮件 · \(pendingCount) 笔", destination: ReviewTransactionsView())
                Text("邮件优先校正已匹配消费。有多笔候选、未找到卡片或缺少汇率时，先由你核对。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("粘贴短信记账", systemImage: "text.bubble", action: { importingSMS = true })
                Button("从邮件资料文件导入", systemImage: "doc.badge.plus", action: { importing = true })
            }
            if let error = cloud.error { Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) } }
            if let message = cloud.message ?? importMessage { Section { Text(message).foregroundStyle(.secondary) } }
        }
        .formStyle(.grouped)
        .navigationTitle("银行邮件记账")
        .task {
            if let connection = try? MailCloudConnectionStore.load() { url = connection.url; token = connection.token }
        }
        .sheet(isPresented: $importingSMS) { SMSImportView() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let file = try result.get(), scoped = file.startAccessingSecurityScopedResource()
                defer { if scoped { file.stopAccessingSecurityScopedResource() } }
                let transactions = try BankMailParser.decodePackage(Data(contentsOf: file))
                let imported = try MailImportService.importTransactions(transactions, in: context)
                importMessage = "新增 \(imported.saved) 笔，校正 \(imported.updated) 笔，待核对 \(imported.pending) 笔。"
            } catch { importMessage = PilotError.message(error) }
        }
    }
}
