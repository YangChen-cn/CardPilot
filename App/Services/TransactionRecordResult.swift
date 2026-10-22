import Foundation

enum TransactionRecordResult {
    case recorded(UUID)
    case duplicate(UUID)
    case needsReview(String)
}
