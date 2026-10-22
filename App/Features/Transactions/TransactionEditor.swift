import SwiftUI
import SwiftData

struct TransactionEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BankCard.createdAt) private var cards: [BankCard]
    @State private var draft: TransactionDraft
    @State private var showingDuplicateConfirmation = false

    init(transaction: SpendTransaction? = nil, cardID: UUID? = nil) {
        let draft = TransactionDraft(transaction: transaction)
        if let cardID { draft.cardID = cardID }
        _draft = State(initialValue: draft)
    }

    private var availableCards: [BankCard] {
        cards.filter { !$0.isArchived || $0.id == draft.cardID }
    }

    var body: some View {
        NavigationStack {
            Form {
                if availableCards.isEmpty {
                    Section {
                        ContentUnavailableView("先添加一张银行卡", systemImage: "creditcard", description: Text("在卡片页添加银行卡后，即可记录消费。"))
                    }
                } else {
                    SpendFields(draft: draft, cards: availableCards)
                }
                if let error = draft.error {
                    Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(draft.existing == nil ? "记一笔" : "编辑交易")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: { dismiss() }) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).bold().disabled(availableCards.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .editorSize()
        .task { draft.prepare(cards: cards) }
        .confirmationDialog("可能是已记录的消费", isPresented: $showingDuplicateConfirmation, titleVisibility: .visible) {
            Button("保存为另一笔消费", action: saveAsAnother)
            Button("取消", role: .cancel, action: draft.cancelDuplicateConfirmation)
        } message: {
            if let transaction = draft.possibleDuplicate?.transaction {
                Text("已有：\(transaction.merchant) · \(Money.text(transaction.amountCents, currency: transaction.currency))\n\(transaction.date.formatted(date: .abbreviated, time: .shortened))\n确认这是另一笔消费后再保存。")
            }
        }
    }

    private func save() {
        if draft.save(in: context, cards: cards) { dismiss() }
        else if draft.possibleDuplicate != nil { showingDuplicateConfirmation = true }
    }

    private func saveAsAnother() {
        if draft.save(in: context, cards: cards, allowPossibleDuplicate: true) { dismiss() }
    }
}
