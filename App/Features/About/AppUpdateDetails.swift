import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct AppUpdateDetails: View {
    let release: AppRelease
    @Environment(AppUpdateController.self) private var updates
    @State private var expanded = false
    @State private var packageError = false
    @State private var preparingMobile = false
    @State private var confirmingInstall = false
    @Environment(\.modelContext) private var context
    @Environment(FolderSyncController.self) private var sync

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("发现新版本 \(release.version)").font(.headline)
            #if os(macOS)
            if updates.isDownloading {
                ProgressView(value: updates.downloadProgress)
                HStack {
                    Text(updates.downloadProgress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                    Spacer()
                    Button("取消下载", action: updates.cancelDownload).buttonStyle(.borderless)
                }
                Text(release.asset.size.formatted(.byteCount(style: .file))).font(.caption).foregroundStyle(.secondary)
            } else if updates.isInstalling {
                ProgressView("正在校验并准备安装…")
            } else if let archive = updates.downloadedArchive {
                Label("下载完成，SHA-256 校验通过", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                Button("安装并重启", systemImage: "arrow.clockwise") { confirmingInstall = true }
                    .buttonStyle(.borderedProminent)
                Button("在 Finder 中显示", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([archive]) }
                if packageError { Text("未能打开安装包，请在 Finder 中打开，或从下方发布页重新下载。").foregroundStyle(.red).font(.caption) }
                Text("保存账本后自动替换并重新打开，保留账本与个人设置。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if release.canDownloadInApp {
                Button("下载更新", systemImage: "arrow.down.to.line", action: updates.download).buttonStyle(.borderedProminent)
                Text("安装包 \(release.asset.size.formatted(.byteCount(style: .file)))").font(.caption).foregroundStyle(.secondary)
            } else {
                Link("前往发布页下载", destination: release.pageURL).buttonStyle(.bordered)
                Text("此安装包未提供校验值，请从发布页下载。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #else
            Button("下载 IPA") { preparingMobile = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .sheet(isPresented: $preparingMobile) { MobileUpdatePreparationView(release: release) }
            Text("下载后使用 SideStore、Sideloadly 等工具重新签名安装。")
                .font(.caption).foregroundStyle(.secondary)
            #endif
            if !release.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DisclosureGroup("更新内容", isExpanded: $expanded) {
                    Text(String(release.notes.prefix(30_000))).textSelection(.enabled)
                        .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
            }
            Link("查看 GitHub 发布说明", destination: release.pageURL).font(.subheadline)
        }.padding(.vertical, 6).buttonStyle(.borderless)
        .alert("安装更新并重启？", isPresented: $confirmingInstall) {
            #if os(macOS)
            Button("安装并重启") { Task { await updates.install(context: context, sync: sync) } }
            #endif
            Button("取消", role: .cancel) { }
        } message: { Text("请先保存其他窗口尚未完成的编辑。App 会保存账本后退出，新版本启动成功前保留旧版备份。") }
    }
}
