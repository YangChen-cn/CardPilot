import AppKit
import Observation
import Foundation

@MainActor
@Observable
final class InstallerController {
    var message = "正在校验安装包…"
    var error: String?
    private var started = false
    private var target: URL?
    private let worker = MacUpdateInstaller()

    func start() {
        guard !started else { return }
        started = true
        Task { await install() }
    }

    private func install() async {
        let args = ProcessInfo.processInfo.arguments
        var prepared: MacUpdateInstaller.Prepared?
        var archive: URL?
        do {
            guard args.count == 9, args[1] == "--install", let pid = Int32(args[6]),
                  args[7] == LaunchConfirmation.markerArgument,
                  LaunchConfirmation.markerURL(in: args) != nil,
                  let host = NSRunningApplication(processIdentifier: pid) else { throw MacUpdateInstaller.Failure.invalidPackage }
            let location = URL(fileURLWithPath: args[3]).resolvingSymlinksInPath()
            let embeddedHost = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().resolvingSymlinksInPath()
            guard location == embeddedHost, host.bundleURL?.resolvingSymlinksInPath() == location,
                  host.bundleIdentifier == "com.cardpilot.app.mac" else { throw MacUpdateInstaller.Failure.invalidPackage }
            guard try UpdateSigning.certificate(of: Bundle.main.bundleURL, identifier: "com.cardpilot.updater") == UpdateSigning.certificate(of: location, identifier: "com.cardpilot.app.mac") else { throw MacUpdateInstaller.Failure.invalidPackage }
            target = location
            let download = URL(fileURLWithPath: args[2]).resolvingSymlinksInPath()
            let cache = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.cardpilot.app.mac/Data/Library/Caches/CardPilotUpdates")
                .resolvingSymlinksInPath()
            guard download.lastPathComponent == "update.dmg",
                  UUID(uuidString: download.deletingLastPathComponent().lastPathComponent) != nil,
                  download.deletingLastPathComponent().deletingLastPathComponent().path == cache.path else {
                throw MacUpdateInstaller.Failure.invalidPackage
            }
            guard LaunchConfirmation.markerURL(in: args)?.standardizedFileURL == LaunchConfirmation.markerURL(forArchive: download).standardizedFileURL else { throw MacUpdateInstaller.Failure.invalidPackage }
            archive = download
            let staged = try await worker.prepare(archive: download, target: location, version: args[4], digest: args[5])
            prepared = staged
            message = "正在保存进度并退出 CardPilot…"
            guard host.terminate() else { throw MacUpdateInstaller.Failure.quit }
            for _ in 0..<90 {
                if host.isTerminated { break }
                try await Task.sleep(for: .milliseconds(500))
            }
            guard host.isTerminated else { throw MacUpdateInstaller.Failure.quit }
            message = "正在替换并重新打开…"
            try await worker.replace(staged)
            let marker = LaunchConfirmation.markerURL(in: args)
            if let marker { try? FileManager.default.removeItem(at: marker) }
            let launch = NSWorkspace.OpenConfiguration()
            launch.createsNewApplicationInstance = true
            launch.allowsRunningApplicationSubstitution = false
            if let marker { launch.arguments = [LaunchConfirmation.markerArgument, marker.path] }
            // Process launch alone is not proof the new build is usable: the backup
            // is discarded only after the new app confirms it opened its store.
            message = "正在确认新版本可以打开…"
            var application: NSRunningApplication?
            do {
                application = try await NSWorkspace.shared.openApplication(at: location, configuration: launch)
            } catch {
                // Launching itself failed: the previous version is restored.
                try await worker.rollback(staged)
                _ = try? await NSWorkspace.shared.openApplication(at: location, configuration: .init())
                throw MacUpdateInstaller.Failure.launchFailed(error.localizedDescription)
            }
            if let marker, await !MacUpdateInstaller.waitForLaunchMarker(at: marker, timeout: .seconds(60)) {
                if let application, !application.isTerminated {
                    _ = application.terminate()
                    for _ in 0..<20 {
                        if application.isTerminated { break }
                        try await Task.sleep(for: .milliseconds(500))
                    }
                }
                if application?.isTerminated != false {
                    try await worker.rollback(staged)
                    _ = try? await NSWorkspace.shared.openApplication(at: location, configuration: .init())
                    throw MacUpdateInstaller.Failure.launchFailed("新版未能完成打开账本。")
                }
                // Never overwrite a running build that refuses a normal quit.
                throw MacUpdateInstaller.Failure.upgradeUnconfirmed("启动后 60 秒内没有完成打开。")
            }
            do { try await worker.finish(staged, archive: download) }
            catch { NSLog("CardPilot update cleanup: %@", error.localizedDescription) } // Update already succeeded; keep any leftover backup.
            NSApp.terminate(nil)
        } catch {
            self.error = error.localizedDescription
            if let prepared {
                do { try await worker.discardStaging(prepared) }
                catch { NSLog("CardPilot staging cleanup: %@", error.localizedDescription) }
            }
            if let archive {
                do { try Data(error.localizedDescription.utf8).write(to: archive.deletingLastPathComponent().appendingPathComponent("failure.txt"), options: .atomic) }
                catch { NSLog("CardPilot update status: %@", error.localizedDescription) }
            }
        }
    }

    func returnToReader() async {
        if let target {
            do { _ = try await NSWorkspace.shared.openApplication(at: target, configuration: .init()) }
            catch { self.error = error.localizedDescription; return }
        }
        NSApp.terminate(nil)
    }
}
