import SwiftUI
import SwiftData

struct TransactionEditor: View {
    @State private var savedFeedback = 0

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BankCard.createdAt) private var cards: [BankCard]
    @State private var draft: TransactionDraft
    @State private var showingDuplicateConfirmation = false
    private let onSaved: ((String) -> Void)?

    init(transaction: SpendTransaction? = nil, cardID: UUID? = nil, onSaved: ((String) -> Void)? = nil) {
        self.onSaved = onSaved
        let draft = TransactionDraft(transaction: transaction, cardID: cardID)
        _draft = State(initialValue: draft)
    }

    private var availableCards: [BankCard] {
        cards.filter { !$0.isArchived || $0.id == draft.existing?.card?.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if availableCards.isEmpty {
                    ContentUnavailableView("先添加一张银行卡", systemImage: "creditcard", description: Text("在卡包中添加银行卡后，即可记录消费。"))
                } else {
                    Form { SpendFields(draft: draft, cards: availableCards) }
                        .formStyle(.grouped)
                        .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle(draft.existing == nil ? "记一笔" : "编辑交易")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DiscardChangesButton(hasChanges: draft.hasUnsavedChanges, discard: { dismiss() })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).bold().disabled(availableCards.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                        .confirmationDialog("可能是已记录的消费", isPresented: $showingDuplicateConfirmation, titleVisibility: .visible) {
                            Button("保存为另一笔消费", action: saveAsAnother)
                            Button("取消", role: .cancel, action: draft.cancelDuplicateConfirmation)
                        } message: {
                            if let transaction = draft.possibleDuplicate?.transaction {
                                Text("已有：\(transaction.merchant) · \(Money.text(transaction.amountCents, currency: transaction.currency))\n\(transaction.date.formatted(date: .abbreviated, time: .shortened))\n确认这是另一笔消费后再保存。")
                            }
                        }
                }
            }
        }
        .editorSize()
        .interactiveDismissDisabled(draft.hasUnsavedChanges)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = draft.error {
                PilotFeedbackBanner(message: error, systemImage: "exclamationmark.circle", isError: true)
            }
        }
        .onChange(of: draft.error) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
        .task { draft.prepare(cards: cards) }
        .sensoryFeedback(.success, trigger: savedFeedback)
    }

    private func save() {
        if draft.save(in: context, cards: cards) { didSave() }
        else if draft.possibleDuplicate != nil { showingDuplicateConfirmation = true }
    }

    private func didSave() {
        savedFeedback &+= 1
        if draft.existing == nil, let card = cards.first(where: { $0.id == draft.cardID }) {
            onSaved?("已记录 " + Money.text(Money.cents(draft.amount), currency: draft.currency) + " · " + card.displayName)
        }
        dismiss()
    }

    private func saveAsAnother() {
        if draft.save(in: context, cards: cards, allowPossibleDuplicate: true) { didSave() }
    }
}
