import SwiftUI
import SwiftData

struct MailConnectionSyncView: View {
    @Environment(\.modelContext) private var context
    @Environment(FolderSyncController.self) private var sync
    @Query(filter: #Predicate<DomainRecord> { $0.kind == "mailConnectionBackup" && !$0.isDeleted }) private var backups: [DomainRecord]
    @State private var password = ""
    @State private var confirmation = ""
    @State private var working = false
    @State private var message: String?
    @State private var replacing = false

    var body: some View {
        Form {
            Section {
                Text("加密同步邮件连接").font(.headline)
                Text("服务网址和连接码加密后随账本同步。恢复时输入密码，再保存到此设备的钥匙串；本机偏好各自保留。")
                    .font(.subheadline).foregroundStyle(.secondary)
                NavigationLink("设置云端共享文件夹") {
                    Form { FolderSyncSettingsSection() }.formStyle(.grouped).navigationTitle("云端同步")
                }
            }
            Section {
                SecureField("恢复密码（至少12个字符）", text: $password)
                SecureField("上传时确认恢复密码", text: $confirmation)
                Button("加密备份此设备的邮件连接") {
                    if backups.isEmpty { upload() } else { replacing = true }
                }
                    .disabled(working || password.count < 12 || password != confirmation || RuntimeMode.isEphemeral)
                Button("从云端备份恢复连接", action: restore)
                    .disabled(working || backups.isEmpty || password.count < 12 || RuntimeMode.isEphemeral)
                if working { ProgressView("正在处理…") }
            } footer: {
                Text("请把恢复密码保存到系统“密码”或其他安全位置，勿放进共享文件夹。忘记密码无法解密备份，但仍可在有连接的设备重新备份。")
            }
            Section {
                Text(backups.isEmpty ? "尚未读到连接备份。重装后先在设置中选择原来的云端文件夹并同步，再回来恢复。" : "已读到加密备份，可在 Mac 或 iPhone 输入恢复密码恢复。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("本地备份写入同步文件夹后，请等待云盘上传完成。断开本机邮件连接不会删除云端备份。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message { Section { Text(message).textSelection(.enabled) } }
        }
        .formStyle(.grouped).navigationTitle("邮件连接云端备份").inlineNavigationTitle()
        .onDisappear { password = ""; confirmation = "" }
        .confirmationDialog("替换现有的云端连接备份？", isPresented: $replacing, titleVisibility: .visible) {
            Button("替换加密备份", action: upload)
        } message: { Text("其他设备下次恢复时需要使用本次填写的密码。本机已保存的连接不会被删除。") }
    }

    private func upload() {
        guard !working else { return }
        working = true; message = nil
        Task {
            defer { working = false }
            do {
                guard let connection = try MailCloudConnectionStore.load() else { throw PilotError.invalid("请先在此设备连接邮件采集服务。") }
                let secret = password
                let backup = try await Task.detached(priority: .userInitiated) { try MailConnectionBackup.encrypt(connection, password: secret) }.value
                try Persistence.save(context) {
                    try DocumentStore.put(backup, key: MailConnectionBackup.key, kind: "mailConnectionBackup", in: context)
                }
                password = ""; confirmation = ""
                if sync.isEnabled { sync.syncNow() }
                message = sync.isEnabled ? "加密备份已保存，正在同步。请确认同步完成并等待云盘上传。" : "加密备份已保存在本机。请设置云端共享文件夹并同步。"
            } catch { message = PilotError.message(error) }
        }
    }

    private func restore() {
        guard !working, let document = backups.first else { return }
        working = true; message = nil
        Task {
            defer { working = false }
            do {
                let backup = try SyncCodec.decoder().decode(MailConnectionBackup.self, from: document.content)
                let secret = password
                let connection = try await Task.detached(priority: .userInitiated) { try backup.decrypt(password: secret) }.value
                try MailCloudController.shared.restoreConnection(connection)
                password = ""; confirmation = ""
                message = "邮件连接已恢复到本机钥匙串，可返回邮件设置读取交易。本机偏好未更改。"
            } catch { message = PilotError.message(error) }
        }
    }
}
