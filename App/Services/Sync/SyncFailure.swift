import Foundation

/// Failures that need a user-facing explanation rather than a generic sync error.
enum SyncFailure: Error, Equatable {
    case waitingForDownload
    case unsupportedSnapshot
    case invalidSnapshot
    case snapshotTooLarge
    case folderUnavailable
}
