import SwiftUI

struct AboutView: View {
    @Environment(AppUpdateController.self) private var updates
    @AppStorage(AppUpdateController.automaticCheckKey) private var automaticCheck = true
    static let projectURL = URL(string: "https://github.com/YangChen-cn/CardPilot")!
    static let releasesURL = URL(string: "https://github.com/YangChen-cn/CardPilot/releases")!

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CardPilot").font(.title.weight(.semibold))
                    Text("银行卡权益与轻量消费记录").font(.subheadline).foregroundStyle(.secondary)
                    Text("版本 \(updates.installedVersion)（\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")）")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }.padding(.vertical, 8)
                LabeledContent("作者", value: "YangChen")
                Link("GitHub · YangChen-cn/CardPilot", destination: Self.projectURL)
            }
            Section("软件更新") {
                Toggle("自动检查更新", isOn: $automaticCheck)
                    .onChange(of: automaticCheck) { _, enabled in if enabled { Task { await updates.check() } } }
                Button("检查更新", systemImage: "arrow.clockwise") { Task { await updates.check(force: true) } }
                    .disabled(updates.isChecking || updates.isDownloading || updates.isInstalling || updates.downloadedArchive != nil)
                if updates.isChecking { ProgressView("正在检查更新…") }
                if let message = updates.statusMessage { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                if let release = updates.release { AppUpdateDetails(release: release) }
                if let error = updates.errorMessage { Text(error).font(.subheadline).foregroundStyle(.red) }
                Link("所有版本与下载", destination: Self.releasesURL)
            }
            #if os(iOS)
            Section("更新与重装前备份") {
                Text("不要先删除 App。覆盖更新通常会保留记录；如需重装，请先同步账本并确认云盘上传完成。")
                    .font(.subheadline).foregroundStyle(.secondary)
                NavigationLink("备份／恢复云端账本") {
                    Form { FolderSyncSettingsSection() }.formStyle(.grouped).navigationTitle("云端同步")
                }
                NavigationLink("加密备份／恢复邮件连接") { MailConnectionSyncView() }
                Text("重装后选择同一云端文件夹并立即同步；邮件连接再用恢复密码恢复。本机偏好各自保存。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #endif
            Section("0.2.0 本版更新") {
                Label("可选的账单日与还款提醒，按卡记录账单和分次还款。", systemImage: "calendar")
                Label("卡包支持叠放与紧凑列表，快速查看日期、权益和整卡用法。", systemImage: "creditcard")
                Label("优化 iPhone 搜索、阅读面板及原生导航交互。", systemImage: "iphone")
                Label("云端资料与清晰卡面更新，保留离线查看能力。", systemImage: "photo")
                Label("新增关于页与更新检查，Mac 支持下载后自动安装并重启。", systemImage: "arrow.down.app")
            }
            .font(.subheadline)
        }
        .formStyle(.grouped)
        .navigationTitle("关于 CardPilot")
        .inlineNavigationTitle()
        .task { await updates.check() }
    }
}
