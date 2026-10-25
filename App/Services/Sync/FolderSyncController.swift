import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class FolderSyncController {
    private let engine = FolderSyncEngine()
    private let access = SyncFolderAccess()
    private let selectOverride: (@Sendable (URL) async throws -> Data)?
    private let defaults: UserDefaults
    private let allowsSync: Bool
    private let deviceID: UUID
    private var context: ModelContext?
    private var folder: URL?
    private var generation = UUID()
    private var syncTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var observer: (any NSObjectProtocol)?
    private var queued = false
    private var restoring = false

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            guard allowsSync else { return }
            defaults.set(isEnabled, forKey: "sync.enabled")
            if isEnabled { Task { await activate() } }
            else { suspend(); Task { await access.stop() }; folder = nil }
        }
    }
    private(set) var isSyncing = false
    private(set) var isChoosing = false
    private(set) var folderName: String?
    private(set) var lastSyncAt: Date?
    private(set) var errorMessage: String?
    var hasFolder: Bool { allowsSync && defaults.data(forKey: "sync.bookmark") != nil }
    var statusSummary: String {
        if isSyncing { return "正在同步…" }
        if errorMessage != nil { return "同步待重试" }
        return isEnabled ? "自动同步已开启" : "保存在此设备"
    }

    static func failureMessage(for error: any Error) -> String {
        let reason: String
        if let failure = error as? SyncFailure {
            switch failure {
            case .waitingForDownload:
                reason = "云盘中的同步资料尚未下载完成，请稍后重试。"
            case .unsupportedSnapshot:
                reason = "同步资料版本不兼容，请更新两端的 CardPilot 后重试。"
            case .invalidSnapshot:
                reason = "同步资料不完整或已损坏，请更新两端 CardPilot 后重试。"
            case .snapshotTooLarge:
                reason = "同步资料过大，请减少卡面图片大小后重试。"
            case .folderUnavailable:
                reason = "无法访问共享文件夹，请重新选择该文件夹。"
            }
        } else if let pilot = error as? PilotError, let message = pilot.errorDescription {
            if message.contains("同步文件夹") {
                reason = "无法访问共享文件夹，请重新选择该文件夹。"
            } else if message.contains("过大") {
                reason = "同步资料过大，请减少卡面图片大小后重试。"
            } else if message.contains("无法识别") || message.contains("不完整") || message.contains("无效") {
                reason = "同步资料无法识别或已损坏，请更新两端 CardPilot 后重试。"
            } else {
                reason = message
            }
        } else if error is DecodingError {
            reason = "同步资料无法识别或已损坏，请更新两端 CardPilot 后重试。"
        } else {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain {
                switch nsError.code {
                case NSFileReadNoPermissionError, NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError:
                    reason = "无法访问共享文件夹，请重新选择该文件夹或恢复云盘权限。"
                case NSFileNoSuchFileError, NSFileReadNoSuchFileError, NSFileReadUnknownError:
                    reason = "同步文件暂时不可用，请确认云盘已完成下载后重试。"
                case NSFileWriteOutOfSpaceError:
                    reason = "云盘空间不足，请释放空间后重试。"
                case NSFileReadCorruptFileError, NSFileReadTooLargeError, NSFileReadInapplicableStringEncodingError:
                    reason = "同步资料无法读取，请更新另一端后重试。"
                default:
                    reason = "暂时无法完成同步，请检查云盘连接后重试。"
                }
            } else {
                reason = "暂时无法完成同步，请检查云盘连接后重试。"
            }
        }
        guard !reason.contains("本机资料"), !reason.contains("本机账本") else { return reason }
        return reason + "本机资料已保留。"
    }

    init(defaults: UserDefaults = .standard, allowsSync: Bool = true,
         selectOverride: (@Sendable (URL) async throws -> Data)? = nil) {
        self.defaults = defaults
        self.selectOverride = selectOverride
        self.allowsSync = allowsSync
        let id = defaults.string(forKey: "sync.deviceID").flatMap(UUID.init(uuidString:)) ?? UUID()
        deviceID = id; defaults.set(id.uuidString, forKey: "sync.deviceID")
        isEnabled = allowsSync && defaults.bool(forKey: "sync.enabled")
        folderName = defaults.string(forKey: "sync.folderName")
        lastSyncAt = defaults.object(forKey: "sync.lastDate") as? Date
    }

    func attach(_ context: ModelContext) async {
        guard self.context == nil else { return }
        self.context = context
        observer = NotificationCenter.default.addObserver(forName: Persistence.didChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.localChanged() }
        }
        if isEnabled { await activate() }
    }

    func selectFolder(_ url: URL) async {
        guard allowsSync else { errorMessage = "演示账本不进行设备同步。"; return }
        let hadPreviousFolder = folder != nil
        let wasEnabled = isEnabled
        suspend(); isChoosing = true; errorMessage = nil
        let selection = UUID(); generation = selection
        defer { isChoosing = false }
        do {
            let bookmark: Data
            if let selectOverride {
                bookmark = try await selectOverride(url)
            } else {
                bookmark = try await access.select(url)
            }
            guard generation == selection else { return }
            folder = url; folderName = url.lastPathComponent
            defaults.set(bookmark, forKey: "sync.bookmark")
            defaults.set(folderName, forKey: "sync.folderName")
            defaults.set(false, forKey: "sync.previouslyPublished")
            if !isEnabled { isEnabled = true }
            else { startPolling(); syncNow() }
        } catch {
            guard generation == selection else { return }
            if wasEnabled, hadPreviousFolder {
                // The picker failed after suspend(); resume the old folder so
                // the enabled switch and the polling state stay consistent.
                startPolling()
                syncNow()
                errorMessage = "无法打开这个文件夹，已继续使用原共享文件夹。"
            } else {
                if isEnabled { isEnabled = false }
                errorMessage = "无法打开这个文件夹，请重新选择。"
            }
        }
    }

    func resume() { if isEnabled { Task { await activate() } } }
    func suspend() {
        generation = UUID(); syncTask?.cancel(); deadlineTask?.cancel(); debounceTask?.cancel(); pollingTask?.cancel()
        syncTask = nil; deadlineTask = nil; pollingTask = nil; isSyncing = false; queued = false
    }

    private func activate() async {
        guard allowsSync, isEnabled, !restoring else { return }
        if folder == nil {
            guard let bookmark = defaults.data(forKey: "sync.bookmark") else { errorMessage = "请先选择共享文件夹。"; return }
            restoring = true; defer { restoring = false }
            let token = generation
            do {
                let (url, fresh) = try await access.restore(bookmark)
                guard isEnabled, token == generation else { return }
                folder = url
                if let fresh { defaults.set(fresh, forKey: "sync.bookmark") }
            } catch { errorMessage = "需要重新选择共享文件夹，以恢复访问权限。"; return }
        }
        startPolling(); syncNow()
    }

    private func localChanged() {
        guard isEnabled else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1500)); try Task.checkCancellation(); self?.syncNow() }
            catch { }
        }
    }

    private func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(12)); try Task.checkCancellation(); self?.syncNow() }
                catch { return }
            }
        }
    }

    func syncNow() {
        guard allowsSync, isEnabled, let folder, let context else { return }
        guard syncTask == nil else { queued = true; return }
        let token = UUID(); generation = token
        isSyncing = true; errorMessage = nil
        let published = defaults.bool(forKey: "sync.previouslyPublished")
        deadlineTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(25)); try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                self.suspend(); self.errorMessage = "云盘暂时没有响应，本机资料已保存。稍后可重试同步。"
                self.startPolling()
            } catch { }
        }
        syncTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == token {
                    self.deadlineTask?.cancel(); self.deadlineTask = nil; self.syncTask = nil; self.isSyncing = false
                    if self.queued { self.queued = false; self.syncNow() }
                }
            }
            do {
                let local = try SyncStore.records(context)
                let merged = try await engine.read(folder: folder, deviceID: deviceID, local: local, previouslyPublished: published)
                guard !Task.isCancelled, generation == token, isEnabled else { return }
                _ = try SyncStore.apply(merged, context: context)
                let fresh = try SyncStore.records(context)
                _ = try await engine.publish(folder: folder, deviceID: deviceID, records: fresh)
                guard !Task.isCancelled, generation == token, isEnabled else { return }
                lastSyncAt = .now; defaults.set(lastSyncAt, forKey: "sync.lastDate")
                defaults.set(true, forKey: "sync.previouslyPublished")
                try? await WelcomeReminderService.refresh(context: context)
            } catch is CancellationError { }
            catch {
                guard generation == token else { return }
                errorMessage = Self.failureMessage(for: error)
            }
        }
    }
}
