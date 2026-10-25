import Foundation

enum SyncFileAccess {
    static func coordinate<T>(url: URL, writing: Bool, operation: (URL) throws -> T) throws -> T {
        try Task.checkCancellation()
        let coordinator = NSFileCoordinator()
        var error: NSError?
        var result: Result<T, any Error>?
        if writing {
            coordinator.coordinate(writingItemAt: url, options: [], error: &error) { location in
                result = Result { try Task.checkCancellation(); return try operation(location) }
            }
        } else {
            coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { location in
                result = Result { try Task.checkCancellation(); return try operation(location) }
            }
        }
        try Task.checkCancellation()
        if let error { throw error }
        guard let result else { throw SyncFailure.folderUnavailable }
        return try result.get()
    }

    static func isMissing(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
    }
}
