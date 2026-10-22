import SwiftUI
import UniformTypeIdentifiers

struct FolderSyncSettingsSection: View {
    @Environment(FolderSyncController.self) private var sync
    @State private var choosing = false

    var body: some View {
        @Bindable var sync = sync
        Section {
            Button(sync.hasFolder ? "更换共享文件夹" : "选择共享文件夹", systemImage: "folder", action: { choosing = true })
            if let name = sync.folderName { LabeledContent("共享位置", value: name) }
            Toggle("自动同步", isOn: $sync.isEnabled).disabled(!sync.hasFolder || sync.isChoosing)
            if sync.isChoosing { ProgressView("正在打开文件夹…") }
            Button("立即同步", systemImage: "arrow.triangle.2.circlepath", action: sync.syncNow)
                .disabled(!sync.isEnabled || sync.isSyncing || sync.isChoosing)
            if sync.isSyncing { ProgressView("正在同步…") }
            if let date = sync.lastSyncAt { LabeledContent("上次同步", value: date.formatted(date: .abbreviated, time: .shortened)) }
            if let message = sync.errorMessage { Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.subheadline) }
        } header: { Text("设备同步") } footer: {
            Text("两端选择同一个iCloud云盘文件夹，会自动创建CardPilotSync；也可直接选择已有的CardPilotSync，不会重复创建。")
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { Task { await sync.selectFolder(url) } }
        }
    }
}
