import AppIntents

struct PilotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordTransactionIntent(), phrases: ["用 \(.applicationName) 记账"],
                    shortTitle: "记录消费", systemImageName: "creditcard")
    }
}
