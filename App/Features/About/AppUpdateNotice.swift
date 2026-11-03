import SwiftUI

struct AppUpdateNotice: View {
    @Environment(AppUpdateController.self) private var updates
    @State private var showingAbout = false

    var body: some View {
        if updates.showsNotice, let release = updates.release {
            HStack(alignment: .top, spacing: 12) {
                Button { showingAbout = true } label: {
                    Label("CardPilot \(release.version) 可更新", systemImage: "arrow.down.app")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
                }.buttonStyle(.plain)
                Button(action: updates.dismissNotice) {
                    Label("暂时忽略此版本", systemImage: "xmark").labelStyle(.iconOnly)
                        .frame(width: 44, height: 44).contentShape(.rect)
                }.buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            .foregroundStyle(PilotTheme.accent)
            .sheet(isPresented: $showingAbout) {
                NavigationStack {
                    AboutView().toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("完成") { showingAbout = false } }
                    }
                }.editorSize()
            }
        }
    }
}
