#if os(macOS)
import AppKit
import SwiftData

@MainActor final class AppTerminationDelegate: NSObject, NSApplicationDelegate {
    var context: ModelContext?
    weak var updates: AppUpdateController?
    weak var sync: FolderSyncController?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if updates?.isInstalling == true, sync?.isSyncing == true || MailCloudController.shared.isSyncing {
            return .terminateCancel
        }
        do {
            try context?.save()
            sync?.suspend()
            return .terminateNow
        } catch {
            let alert = NSAlert()
            alert.messageText = "账本尚未保存"
            alert.informativeText = "请解决保存问题后再退出或安装更新。原版本会保留。"
            alert.addButton(withTitle: "返回 CardPilot")
            alert.runModal()
            return .terminateCancel
        }
    }
}
#endif
