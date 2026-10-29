import SwiftUI
import SwiftData

@main
struct CardPilotApp: App {
    private let container: ModelContainer?
    private let startupError: String?
    @State private var folderSync = FolderSyncController(allowsSync: !RuntimeMode.isEphemeral)
    @State private var catalog = CatalogRepository.shared

    init() {
        do {
            let store = try RuntimeMode.isEphemeral ? Persistence.makeContainer(inMemory: true) : Persistence.live.get()
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--preview-library-cards") {
                let previewIDs: Set<String> = ["bochk.chill.platinum", "bochk.go.diamond", "hsbc.student.visa.gold", "bea.hku.student.visa", "hsbc.mastercard.debit"]
                for product in try BankLibrary.load().products where previewIDs.contains(product.id) {
                    _ = try LibraryOnboarding.add(product: product, in: store.mainContext)
                }
            }
            #endif
            if RuntimeMode.isDemo { try DemoData.populate(store.mainContext) }
            LibraryCardConfiguration.performRequested(in: store.mainContext)
            container = store; startupError = nil
        } catch {
            container = nil; startupError = "请退出后重新打开。原有账本会保留，不会被空账本替换。"
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                ContentView().modelContainer(container).tint(PilotTheme.accent)
                    .environment(folderSync)
                    .environment(catalog)
                    .environment(\.locale, Locale(identifier: "zh_Hans_HK"))
                    .environment(\.timeZone, HKCalendar.calendar.timeZone)
                    .preferredColorScheme(RuntimeMode.isDemo && ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : nil)
                    .transformEnvironment(\.dynamicTypeSize) { size in
                        if RuntimeMode.isDemo && ProcessInfo.processInfo.arguments.contains("--large-text") { size = .accessibility3 }
                    }
            } else {
                ContentUnavailableView("无法打开本地账本", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(startupError ?? "请重试。原有数据不会被清除。"))
                    .padding()
            }
        }
        #if os(macOS)
        .defaultSize(width: 1240, height: 860)
        #endif

        #if os(macOS)
        Settings {
            if let container {
                NavigationStack { SettingsView() }
                    .modelContainer(container)
                    .environment(folderSync)
                    .environment(catalog)
                    .environment(\.locale, Locale(identifier: "zh_Hans_HK"))
                    .environment(\.timeZone, HKCalendar.calendar.timeZone)
                    .tint(PilotTheme.accent)
                    .frame(minWidth: 560, minHeight: 620)
            }
        }
        #endif
    }
}
