import SwiftUI
import SwiftData

struct MailConnectionSyncView: View {
    @Environment(\.modelContext) private var context
    @Environment(FolderSyncController.self) private var sync
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Text("邮件连接随账本同步").font(.headline)
                Text("网址和连接码自动随你选择的共享文件夹同步，另一端同步后自动连接。本机仍使用钥匙串保存，偏好设置各自保留。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("同步此设备的邮件连接") {
                    guard !RuntimeMode.isEphemeral else { return }
                    do {
                        guard let connection = try MailCloudConnectionStore.load() else { throw PilotError.invalid("请先连接邮件采集服务，或同步已有云端账本。") }
                        try MailConnectionSyncStore.save(connection, in: context)
                        sync.syncNow()
                        message = sync.isEnabled ? "已保存连接并开始同步。" : "已保存连接，请选择云端文件夹并开启同步。"
                    } catch { message = PilotError.message(error) }
                }.disabled(sync.isSyncing || RuntimeMode.isEphemeral)
            }
            Section {
                Button("使用云端邮件连接") {
                    MailCloudController.shared.resumeConnectionSync()
                    MailConnectionSyncStore.refresh(in: context)
                    sync.syncNow()
                }.disabled(RuntimeMode.isEphemeral)
            }
            FolderSyncSettingsSection()
            if let message { Section { Text(message) } }
        }.formStyle(.grouped).navigationTitle("邮件连接同步").inlineNavigationTitle()
    }
}
