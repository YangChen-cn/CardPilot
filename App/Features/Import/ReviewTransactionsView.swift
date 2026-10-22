import SwiftUI
import SwiftData

struct ReviewTransactionsView: View {
    @Environment(\.modelContext) private var context
    @Query private var documents: [DomainRecord]
    @Query private var cards: [BankCard]
    @Query private var transactions: [SpendTransaction]
    @State private var message: String?
    @State private var selectedMail: MailReview?
    @State private var retryMessage: String?
    @State private var showingResult = false

    var body: some View {
        let pending = documents.filter { $0.kind == "review" && !$0.isDeleted }.sorted { $0.modifiedAt > $1.modifiedAt }
        let mail = documents.filter { $0.kind == "mailReview" && !$0.isDeleted }
            .compactMap { try? SyncCodec.decoder().decode(MailReview.self, from: $0.content) }
            .sorted { $0.mail.receivedAt > $1.mail.receivedAt }
        List {
            if pending.isEmpty && mail.isEmpty {
                ContentUnavailableView("没有待核对交易", systemImage: "checkmark.circle", description: Text("自动记账与导入中可能重复的消费，会在这里等待确认。"))
            }
            if !mail.isEmpty {
                Section("银行通知 · \(mail.count) 笔") {
                    ForEach(mail, id: \.key) { review in
                        Button { selectedMail = review } label: { BankMailReviewRow(review: review) }.buttonStyle(.plain)
                    }
                }
            }
            ForEach(pending, id: \.key) { document in
                if let request = try? SyncCodec.decoder().decode(TransactionRequest.self, from: document.content) {
                    Section {
                        TransactionReviewItem(request: request, cardName: cardName(request),
                                              duplicate: try? TransactionRecorder.assess(request, in: context),
                                              approve: { approve(request, key: document.key) }, ignore: { ignore(document.key) })
                    }
                } else { Text("这条待核对记录无法读取，请保留资料并重试。") }
            }
            if let message { Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
        }
        .navigationTitle("交易核对")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("重新匹配", systemImage: "arrow.clockwise", action: retry) } }
        .alert("邮件匹配结果", isPresented: $showingResult) { Button("好", role: .cancel) {} } message: { Text(retryMessage ?? "") }
        .sheet(item: $selectedMail) { review in
            BankMailReviewEditor(review: review, finished: { selectedMail = nil })
        }
        .onChange(of: transactions.count) { _, _ in message = nil }
    }

    private func retry() {
        do {
            let result = try MailImportService.retryPending(in: context)
            retryMessage = "新增 \(result.saved) 笔，校正 \(result.updated) 笔，仍待核对 \(try MailImportService.reviewItems(in: context).count) 笔。"
        } catch { retryMessage = PilotError.message(error) }
        showingResult = true
    }

    private func cardName(_ request: TransactionRequest) -> String {
        cards.first(where: { $0.syncKey == request.cardID || $0.id.uuidString == request.cardID })?.displayName ?? "未找到银行卡"
    }

    private func approve(_ request: TransactionRequest, key: String) {
        do {
            try Persistence.save(context) {
                _ = try TransactionRecorder.record(request, in: context, allowPossibleDuplicate: true)
                try DocumentStore.remove(key, in: context)
            }
        } catch { message = PilotError.message(error) }
    }

    private func ignore(_ key: String) {
        do { try Persistence.save(context) { try DocumentStore.remove(key, in: context) } }
        catch { message = "未能保存核对结果，请重试。" }
    }
}
