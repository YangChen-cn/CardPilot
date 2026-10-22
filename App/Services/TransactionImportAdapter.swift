import Foundation

/// Future bank-email / CSV parsers produce the same value input before a user reviews and commits it.
protocol TransactionImportAdapter {
    var sourceIdentifier: String { get }
    func parse(_ data: Data, cardID: String) throws -> [TransactionRequest]
}
