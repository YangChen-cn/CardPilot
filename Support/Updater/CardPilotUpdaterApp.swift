import AppKit
import SwiftUI

@main
struct CardPilotUpdaterApp: App {
    @State private var installer = InstallerController()

    var body: some Scene {
        WindowGroup("CardPilot 更新") {
            VStack(alignment: .leading, spacing: 18) {
                Label("安装 CardPilot 更新", systemImage: "arrow.down.circle.fill").font(.title2)
                if let error = installer.error {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                    Button("返回 CardPilot") { Task { await installer.returnToReader() } }
                        .buttonStyle(.borderedProminent)
                } else {
                    ProgressView(installer.message)
                    Text("安装完成后会自动重新打开。")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(width: 420)
            .fixedSize(horizontal: true, vertical: true)
            .onAppear { installer.start() }
        }
        .windowResizability(.contentSize)
    }
}
