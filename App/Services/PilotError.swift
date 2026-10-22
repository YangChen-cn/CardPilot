import Foundation

enum PilotError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
    static func message(_ error: any Error, fallback: String = "暂时无法保存，请重试。") -> String {
        (error as? PilotError)?.errorDescription ?? fallback
    }
    static func isCancellation(_ error: any Error) -> Bool {
        let value = error as NSError
        return error is CancellationError || (value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError)
    }
}
