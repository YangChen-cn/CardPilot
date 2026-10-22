import Foundation

enum StoreBackup {
    /// Preserve the original store and external image files before the first schema upgrade.
    static func beforeFirstUpgrade(storeURL: URL) throws {
        let files = FileManager.default
        guard files.fileExists(atPath: storeURL.path) else { return }
        let parent = storeURL.deletingLastPathComponent()
        for stage in ["Before Sync Upgrade", "Before Account Upgrade V3"] {
            let backup = parent.appending(path: "CardPilot Backups/" + stage, directoryHint: .isDirectory)
            guard !files.fileExists(atPath: backup.appending(path: "complete").path) else { continue }
            try files.createDirectory(at: backup, withIntermediateDirectories: true)
            let names = [storeURL.lastPathComponent, storeURL.lastPathComponent + "-wal", storeURL.lastPathComponent + "-shm", ".CardPilot_SUPPORT"]
            for name in names {
                let source = parent.appending(path: name)
                let destination = backup.appending(path: name)
                if files.fileExists(atPath: source.path), !files.fileExists(atPath: destination.path) {
                    try files.copyItem(at: source, to: destination)
                }
            }
            try Data("On-device store preserved before migration".utf8).write(to: backup.appending(path: "complete"), options: .atomic)
        }
    }
}
