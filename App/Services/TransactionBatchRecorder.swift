import SwiftData

@MainActor enum TransactionBatchRecorder {
    /// Review documents and accepted rows commit together, or the entire batch rolls back.
    static func record(_ requests: [TransactionRequest], in context: ModelContext) throws -> TransactionBatchResult {
        var result = TransactionBatchResult()
        try Persistence.save(context) {
            for request in requests {
                switch try TransactionRecorder.record(request, in: context) {
                case .recorded: result.saved += 1
                case .duplicate: result.duplicate += 1
                case .needsReview: result.pending += 1
                }
            }
        }
        return result
    }
}
