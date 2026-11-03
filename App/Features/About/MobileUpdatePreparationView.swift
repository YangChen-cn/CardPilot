#if os(iOS)
import SwiftUI

struct MobileUpdatePreparationView: View {
    let release: AppRelease
    @Environment(FolderSyncController.self) private var sync
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("更新前先保护账本", systemImage: "externaldrive.badge.icloud").font(.headline)
                    Text("优先使用侧载工具覆盖更新，不要先删除 App。“删除 App”会清除本地记录。")
                    Text("如需重装：先把账本同步到 iCloud Drive 等云端文件夹，确认同步成功，并在“文件”App 等待云端上传完成。重装后重新选择同一文件夹，再点“立即同步”恢复。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                FolderSyncSettingsSection()
                Section {
                    NavigationLink("加密备份／恢复邮件连接") { MailConnectionSyncView() }
                    Text("邮件连接需先用恢复密码加密备份，重装后用该密码恢复；本机偏好不随账本同步。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("已确认备份并等待云端上传完成", isOn: $confirmed)
                    Button("继续下载 IPA", systemImage: "arrow.down.to.line") {
                        openURL(release.asset.browserDownloadURL)
                        dismiss()
                    }.disabled(!confirmed || sync.isSyncing || sync.isChoosing)
                } footer: { Text("选择“我的 iPhone”中的文件夹不属于云端备份。下载后仍需侧载工具重新签名安装。") }
            }
            .formStyle(.grouped).navigationTitle("更新前备份").inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .task { if sync.isEnabled { sync.syncNow() } }
    }
}
#endif
