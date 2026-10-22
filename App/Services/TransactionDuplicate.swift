import Foundation

@MainActor struct TransactionDuplicate {
    let transaction: SpendTransaction
    let isExact: Bool
    var id: UUID { transaction.id }
}
