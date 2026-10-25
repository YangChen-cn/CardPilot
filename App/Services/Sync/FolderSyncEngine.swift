import Foundation

actor FolderSyncEngine {
    static let directoryName = "CardPilotSync"

    static func directory(in folder: URL) -> URL {
        folder.lastPathComponent == directoryName ? folder : folder.appending(path: directoryName, directoryHint: .isDirectory)
    }

    func read(folder: URL, deviceID: UUID, local: [SyncRecord], previouslyPublished: Bool) throws -> [SyncRecord] {
        let directory = Self.directory(in: folder)
        try ensureDirectory(directory)
        let ownURL = directory.appending(path: deviceID.uuidString + ".json")
        if previouslyPublished {
            // A disappearing provider placeholder is not a new empty account.
            let own = try readSnapshot(ownURL, expected: deviceID)
            guard own != nil else { throw SyncFailure.waitingForDownload }
        }
        let files = try SyncFileAccess.coordinate(url: directory, writing: false) {
            try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: [.fileSizeKey])
        }
        var records = local
        for file in files where file.pathExtension == "json" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
            if let snapshot = try readSnapshot(file, expected: id) { records += snapshot.records }
        }
        return SyncMerger.merge(records)
    }

    @discardableResult func publish(folder: URL, deviceID: UUID, records: [SyncRecord]) throws -> Bool {
        let directory = Self.directory(in: folder)
        try ensureDirectory(directory)
        let destination = directory.appending(path: deviceID.uuidString + ".json")
        if let previous = try readSnapshot(destination, expected: deviceID), previous.records == records { return false }
        let snapshot = SyncSnapshot(deviceID: deviceID, updatedAt: .now, records: records)
        let data = try SyncCodec.encoder().encode(snapshot)
        guard data.count <= 100_000_000 else { throw SyncFailure.snapshotTooLarge }
        try SyncFileAccess.coordinate(url: destination, writing: true) { location in
            try data.write(to: location, options: .atomic)
        }
        return true
    }

    private func ensureDirectory(_ directory: URL) throws {
        try SyncFileAccess.coordinate(url: directory, writing: true) { location in
            var folder: ObjCBool = false
            if FileManager.default.fileExists(atPath: location.path, isDirectory: &folder) {
                guard folder.boolValue else { throw SyncFailure.folderUnavailable }
            } else {
                try FileManager.default.createDirectory(at: location, withIntermediateDirectories: false)
            }
        }
    }

    private func readSnapshot(_ url: URL, expected: UUID) throws -> SyncSnapshot? {
        do {
            return try SyncFileAccess.coordinate(url: url, writing: false) { location in
                let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 100_000_000 else { throw SyncFailure.snapshotTooLarge }
                return try SyncCodec.decode(Data(contentsOf: location), expectedDevice: expected)
            }
        } catch where SyncFileAccess.isMissing(error) { return nil }
    }
}
