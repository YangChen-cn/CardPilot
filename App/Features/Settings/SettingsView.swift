import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SpendTransaction.date, order: .reverse) private var transactions: [SpendTransaction]
    @Environment(\.modelContext) private var context
    @Environment(CatalogRepository.self) private var catalog
    @State private var exporting = false
    @State private var shortcuts = false
    @State private var document = TextDocument(text: "")
    @State private var message: String?
    @State private var importingCSV = false

    var body: some View {
        Form {
            FolderSyncSettingsSection()
            Section("快捷记账") {
                Button("添加快捷指令", systemImage: "bolt", action: { shortcuts = true })
                NavigationLink("银行邮件记账", destination: BankMailSettingsView())
            }
            Section("官方资料更新") {
                LabeledContent("资料来源", value: catalog.cacheSourceText)
                LabeledContent("资料版本", value: catalog.versionText)
                if let published = catalog.publishedText {
                    LabeledContent("发布日期", value: published)
                }
                if let success = catalog.lastSuccessText {
                    LabeledContent("最近成功", value: success.replacingOccurrences(of: "上次成功：", with: ""))
                }
                if let applied = catalog.lastAppliedText {
                    LabeledContent("最近应用", value: applied.replacingOccurrences(of: "最近应用：", with: ""))
                }
                if let checked = catalog.lastCheckedText {
                    LabeledContent("上次检查", value: checked.replacingOccurrences(of: "上次检查：", with: ""))
                }
                if let failure = catalog.lastFailureText {
                    LabeledContent("最近失败") {
                        Text(failure).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(catalog.statusText).font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if catalog.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("立即检查更新") {
                            Task { await catalog.check(force: true) }
                        }
                    }
                }
                Text("只更新只读的官方产品与活动缓存；你的卡片、账本、手工修改和迎新状态不会被覆盖。启动、回到前台（每 6 小时最多一次）或手动检查。离线时继续使用最近一次完整缓存，没有缓存则使用 App 内置资料。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Link("查看资料源", destination: catalog.endpoint)
            }
            Section("我的数据") {
                Button("导入消费记录", systemImage: "doc.badge.plus", action: { importingCSV = true })
                NavigationLink("交易核对", destination: ReviewTransactionsView())
                NavigationLink("额度与还款", destination: FinanceView())
                NavigationLink("迎新管理中心", destination: WelcomeCenterView())
                Button("导出消费记录", systemImage: "square.and.arrow.up", action: prepareExport)
            }
            Section {
                Text("权益以银行最新条款为准；迎新完成与到账状态由你记录。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let message { Section { Text(message).textSelection(.enabled) } }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .sheet(isPresented: $shortcuts) { ShortcutSetupView() }
        .sheet(isPresented: $importingCSV) { CSVImportView() }
        .fileExporter(isPresented: $exporting, document: document, contentType: .commaSeparatedText, defaultFilename: "CardPilot-transactions") { result in
            switch result {
            case .success: message = "交易已导出。"
            case .failure(let error): message = PilotError.message(error)
            }
        }
    }

    private func prepareExport() {
        let header = ["id", "card_id", "card", "merchant", "date", "amount", "currency", "hkd_rate", "hkd_amount", "category", "payment", "channel", "overseas", "region", "reward_eligible", "notes"]
        var rows = [header]
        for t in transactions {
            rows.append([t.externalID.isEmpty ? t.id.uuidString : t.externalID, t.card?.syncKey ?? "", t.card?.displayName ?? "", t.merchant, t.date.ISO8601Format(),
                         (Decimal(t.amountCents) / 100).description, t.currency, t.exchangeRate,
                         t.hasHKDValuation ? (Decimal(t.hkdCents) / 100).description : "", t.category, t.paymentMethod, t.channel,
                         String(t.isOverseas), t.region, String(t.isRewardEligible), t.notes])
        }
        document = TextDocument(text: rows.map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\r\n"))
        exporting = true
    }
    private func csvCell(_ value: String) -> String {
        let safe = ["=", "+", "-", "@"].contains(where: value.hasPrefix) ? "'" + value : value
        return "\"" + safe.replacing("\"", with: "\"\"") + "\""
    }
}
