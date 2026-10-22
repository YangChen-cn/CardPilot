#if os(macOS)
import SwiftUI

/// Keep the ledger's search and toolbar outside the card-detail navigation hierarchy.
struct CardLedgerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let card: BankCard

    var body: some View {
        NavigationStack {
            TransactionsView(card: card)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭", systemImage: "xmark", action: { dismiss() })
                            .keyboardShortcut(.cancelAction)
                    }
                }
        }
        .frame(minWidth: 760, idealWidth: 920, minHeight: 600, idealHeight: 720)
    }
}
#endif
