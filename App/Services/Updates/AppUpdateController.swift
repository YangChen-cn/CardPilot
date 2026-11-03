import Foundation
import Observation
import SwiftData
#if os(macOS)
import AppKit
#endif

@MainActor @Observable final class AppUpdateController {
    static let automaticCheckKey = "updates.automaticCheck"
    let installedVersion: String
    private(set) var release: AppRelease?
    private(set) var isChecking = false
    private(set) var isDownloading = false
    private(set) var isInstalling = false
    private(set) var downloadProgress = 0.0
    private(set) var downloadedArchive: URL?
    private(set) var statusMessage: String?
    private(set) var errorMessage: String?
    private var hiddenVersion: String
    @ObservationIgnored private let service: AppUpdateService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let allowsChecks: Bool
    @ObservationIgnored private var nextAutomaticCheck = Date.distantPast
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var downloadID = UUID()
    @ObservationIgnored private var installationTask: Task<Void, Never>?

    var showsNotice: Bool { release != nil && release?.version != hiddenVersion }

    init(installedVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0",
         service: AppUpdateService = AppUpdateService(), defaults: UserDefaults = .standard,
         allowsChecks: Bool = !RuntimeMode.isEphemeral) {
        self.installedVersion = installedVersion
        self.service = service
        self.defaults = defaults
        self.allowsChecks = allowsChecks
        hiddenVersion = defaults.string(forKey: "updates.hiddenVersion") ?? ""
    }

    func check(force: Bool = false) async {
        guard allowsChecks else { if force { statusMessage = "演示模式不检查软件更新。" }; return }
        guard !isChecking, !isDownloading, !isInstalling, downloadedArchive == nil else { return }
        if !force {
            guard defaults.object(forKey: Self.automaticCheckKey) as? Bool ?? true, Date.now >= nextAutomaticCheck else { return }
        }
        isChecking = true
        errorMessage = nil
        statusMessage = nil
        defer { isChecking = false }
        do {
            let releases = try await service.releases(force: force)
            try Task.checkCancellation()
            release = AppRelease.newest(in: releases, platform: .current, installed: installedVersion)
            nextAutomaticCheck = .now.addingTimeInterval(6 * 3600)
            if force {
                statusMessage = release == nil ? "暂未发现更新的正式版本。" : nil
                hiddenVersion = ""
                defaults.removeObject(forKey: "updates.hiddenVersion")
            }
        } catch is CancellationError { }
        catch {
            nextAutomaticCheck = .now.addingTimeInterval(300)
            errorMessage = "暂时无法检查更新，请稍后重试或查看 GitHub 发布页。"
        }
    }

    func dismissNotice() {
        hiddenVersion = release?.version ?? ""
        defaults.set(hiddenVersion, forKey: "updates.hiddenVersion")
    }

    func download() {
        guard allowsChecks, let release, !isDownloading, !isInstalling, downloadedArchive == nil else { return }
        isDownloading = true
        downloadProgress = 0
        errorMessage = nil
        let id = UUID()
        downloadID = id
        downloadTask = Task { [weak self, service] in
            do {
                let archive = try await service.download(release) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.downloadID == id, self.isDownloading else { return }
                        self.downloadProgress = max(self.downloadProgress, progress)
                    }
                }
                guard let self, !Task.isCancelled, self.downloadID == id else { try await service.discard(archive); return }
                self.downloadedArchive = archive
                self.downloadProgress = 1
            } catch {
                if let self, self.downloadID == id, !Task.isCancelled { self.errorMessage = "下载或校验失败，请重试。" }
            }
            if let self, self.downloadID == id { self.isDownloading = false; self.downloadTask = nil }
        }
    }

    func cancelDownload() {
        downloadID = UUID()
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0
    }
    #if os(macOS)
    func install(context: ModelContext, sync: FolderSyncController) async {
        guard allowsChecks, let archive = downloadedArchive, let release, let digest = release.asset.sha256, !isInstalling else { return }
        guard !sync.isSyncing, !MailCloudController.shared.isSyncing else {
            errorMessage = "请等待同步或邮件导入完成，再安装更新。"
            return
        }
        do { try context.save() }
        catch { errorMessage = "账本尚未保存，请稍后重试。"; return }
        let target = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard !target.path.contains("/AppTranslocation/"), !target.path.hasPrefix("/Volumes/"),
              !target.path.hasPrefix("/private/tmp/"), !target.path.hasPrefix("/tmp/") else {
            errorMessage = "当前位置无法更新，请将 App 放在可写文件夹后重试。"
            return
        }
        let helper = target.appendingPathComponent("Contents/Helpers/CardPilotUpdater.app")
        guard FileManager.default.fileExists(atPath: helper.path) else {
            errorMessage = "安装助手缺失，请重新下载完整安装包。"
            return
        }
        errorMessage = nil
        isInstalling = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        // The helper keeps the old version as a backup until the new build writes
        // this marker, so a build that cannot open its store is rolled back.
        configuration.arguments = ["--install", archive.path, target.path, release.version, digest,
                                   String(ProcessInfo.processInfo.processIdentifier),
                                   LaunchConfirmation.markerArgument,
                                   LaunchConfirmation.markerURL(forArchive: archive).path]
        do {
            guard try UpdateSigning.certificate(of: helper, identifier: "com.cardpilot.updater") == UpdateSigning.certificate(of: target, identifier: "com.cardpilot.app.mac") else { throw MacUpdateInstaller.Failure.invalidPackage }
            try await service.resetInstallationStatus(archive)
            let application = try await NSWorkspace.shared.openApplication(at: helper, configuration: configuration)
            // The helper stages and verifies before requesting a normal app quit.
            // AppTerminationDelegate saves the ledger before allowing termination.
            installationTask = Task { [weak self, service] in
                // A helper that never reports back must not leave isInstalling set forever.
                // Bound the wait so the failure path can reset the state and allow a retry.
                let deadline = Date.now.addingTimeInterval(300)
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(1))
                        if Date.now >= deadline {
                            self?.errorMessage = "安装助手长时间未响应，请重试或从发布页面下载安装。"
                            self?.isInstalling = false
                            return
                        }
                        if let message = try await service.installationError(archive) {
                            self?.errorMessage = message
                            self?.isInstalling = false
                            return
                        }
                        if application.isTerminated {
                            self?.errorMessage = "安装助手已退出，请重试或从发布页面下载安装。"
                            self?.isInstalling = false
                            return
                        }
                    } catch {
                        if !Task.isCancelled { self?.errorMessage = error.localizedDescription; self?.isInstalling = false }
                        return
                    }
                }
            }
        } catch {
            isInstalling = false
            errorMessage = error.localizedDescription
        }
    }
    #endif
}
