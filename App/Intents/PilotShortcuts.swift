import AppIntents

struct PilotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordTransactionIntent(), phrases: ["用 \(.applicationName) 记账"],
                    shortTitle: "记录消费", systemImageName: "creditcard")
        AppShortcut(intent: RecordWalletTransactionIntent(), phrases: ["用 \(.applicationName) 记录钱包消费"],
                    shortTitle: "Apple Pay 记账", systemImageName: "creditcard")
    }
}
