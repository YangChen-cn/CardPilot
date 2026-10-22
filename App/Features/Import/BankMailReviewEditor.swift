import SwiftUI
import SwiftData

struct BankMailReviewEditor: View {
    @Environment(\.modelContext) private var context
    @Query private var cards: [BankCard]
    @Query(sort: \SpendTransaction.date, order: .reverse) private var transactions: [SpendTransaction]
    let review: MailReview
    let finished: () -> Void
    @State private var transactionKey = ""
    @State private var cardKey = ""
    @State private var rate = Decimal(0)
    @State private var error: String?

    private var candidates: [SpendTransaction] {
        let keys = Set(compatibleCards.map(\.syncKey))
        return transactions.filter { review.candidateKeys.contains($0.syncKey) && $0.card.map { keys.contains($0.syncKey) } == true }
    }
    private var compatibleCards: [BankCard] { MailImportService.compatibleCards(for: review.mail, cards: cards) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(review.mail.merchant).font(.headline)
                    LabeledContent("银行金额", value: Money.text(review.mail.amountCents, currency: review.mail.currency))
                    LabeledContent("通知卡片", value: "\(review.mail.bankID.uppercased()) · 尾号 \(review.mail.lastFour)\(review.mail.requiredCardKind == "借记卡" ? " · 扣账卡" : "")")
                    LabeledContent("交易日期", value: review.mail.date.formatted(date: .abbreviated, time: review.mail.hasExactTime ? .shortened : .omitted))
                    Text(review.reason).font(.subheadline).foregroundStyle(.secondary)
                }
                Section("核对结果") {
                    Picker("处理方式", selection: $transactionKey) {
                        Text("记录为另一笔消费").tag("")
                        ForEach(candidates) { transaction in
                            Text("更新 \(transaction.merchant) · \(Money.text(transaction.amountCents, currency: transaction.currency))")
                                .tag(transaction.syncKey)
                        }
                    }
                    Picker("银行卡", selection: $cardKey) {
                        Text("请选择").tag("")
                        ForEach(compatibleCards) { Text($0.displayName + ($0.lastFour.isEmpty ? " · 未填尾号" : " · " + $0.lastFour)).tag($0.syncKey) }
                    }
                    if compatibleCards.isEmpty {
                        Text("请先在「我的卡片」添加对应\(review.mail.requiredCardKind == "借记卡" ? "扣账卡" : "银行卡")，填写后4位，再返回重新匹配。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if review.mail.currency != "HKD" {
                        TextField("1 \(review.mail.currency) 折合 HKD", value: $rate, format: .number.precision(.fractionLength(0...6)))
                        #if os(iOS)
                            .keyboardType(.decimalPad)
                        #endif
                        Text("原币直接入账；汇率可不填，仅用于港币消费统计。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button(transactionKey.isEmpty ? "保存为另一笔消费" : "用银行通知校正这笔消费", action: save)
                        .buttonStyle(.borderedProminent)
                    Button(review.mail.source == "sms" ? "忽略这条短信" : "忽略这封邮件", role: .destructive) {
                        do { try MailImportService.ignoreReview(key: review.key, in: context); finished() }
                        catch { self.error = PilotError.message(error) }
                    }
                }
            }
            .formStyle(.grouped).editorSize().navigationTitle("核对银行交易")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消", action: finished) } }
            .onChange(of: transactionKey) { _, key in
                if let transaction = transactions.first(where: { $0.syncKey == key }) {
                    cardKey = transaction.card?.syncKey ?? ""
                    rate = Decimal(string: transaction.exchangeRate) ?? 0
                }
            }
            .task {
                if let key = review.cardKey { cardKey = key }
                if candidates.count == 1, let transaction = candidates.first {
                    transactionKey = transaction.syncKey; cardKey = transaction.card?.syncKey ?? ""
                    rate = Decimal(string: transaction.exchangeRate) ?? 0
                }
            }
        }
    }

    private func save() {
        do {
            _ = try MailImportService.resolveReview(key: review.key, transactionKey: transactionKey.isEmpty ? nil : transactionKey,
                cardKey: cardKey.isEmpty ? nil : cardKey, exchangeRate: rate > 0 ? rate.description : nil,
                saveAsAnother: transactionKey.isEmpty, in: context)
            finished()
        } catch { self.error = PilotError.message(error) }
    }
}
