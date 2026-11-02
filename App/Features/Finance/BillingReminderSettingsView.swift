import SwiftUI
import SwiftData
import UserNotifications

struct BillingReminderSettingsView: View {
    var showsCards = true
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Query(filter: #Predicate<BankCard> { !$0.isArchived && $0.kind == "信用卡" }, sort: \BankCard.createdAt) private var cards: [BankCard]
    @Query(filter: #Predicate<DomainRecord> { $0.kind == "billingPreferences" && !$0.isDeleted }) private var preferenceDocuments: [DomainRecord]
    @AppStorage("billing.reminders.enabled") private var enabled = false
    @State private var requested = false
    @State private var updating = false
    @State private var allowed = false
    @State private var permissionDenied = false
    @State private var count = 0
    @State private var nextDate: Date?
    @State private var editing: BankCard?
    @State private var message: String?

    var body: some View {
        let preferences = (try? FinanceStore.snapshot(preferenceDocuments))?.billingPreferences ?? [:]
        Form {
            Section {
                Toggle("在此设备提醒", isOn: $requested).disabled(updating || RuntimeMode.isEphemeral)
                if RuntimeMode.isEphemeral {
                    Text("演示模式不发送通知，也不会更改本机通知偏好。")
                        .font(.caption).foregroundStyle(.secondary)
                } else if permissionDenied {
                    Label("系统通知尚未允许", systemImage: "bell.slash").foregroundStyle(.secondary)
                    #if os(iOS)
                    Button("打开通知设置") { openURL(URL(string: UIApplication.openNotificationSettingsURLString)!) }
                    #else
                    Text("可在系统设置 → 通知 → CardPilot 中允许通知。")
                        .font(.caption).foregroundStyle(.secondary)
                    #endif
                }
                if enabled && allowed {
                    LabeledContent("已安排", value: "\(count) 条提醒")
                    if let nextDate { LabeledContent("下次提醒", value: nextDate.formatted(date: .abbreviated, time: .shortened)) }
                    Button("更新提醒", systemImage: "arrow.clockwise", action: refresh).disabled(updating)
                }
            } footer: {
                Text("只发送你为各卡开启的账单和还款提醒。本机开关独立设置，卡片日期与提醒选项随账本同步。")
            }
            if showsCards {
                Section("选择要提醒的信用卡") {
                    if cards.isEmpty { Text("添加信用卡后，可为每张卡设置日期与提醒。").foregroundStyle(.secondary) }
                    ForEach(cards) { card in
                        Button { editing = card } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(card.name).foregroundStyle(.primary)
                                    Text(selectionSummary(preferences[card.syncKey]))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.frame(minHeight: PilotTheme.minimumTouchTarget).contentShape(.rect)
                        }.buttonStyle(.plain)
                    }
                }
            }
            Section {
                Text("提醒使用香港时间，提前交给系统安排，打开 App 时自动续排。通知不含账单金额；还款状态以你的记录和银行账单为准。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message { Section { Text(message).foregroundStyle(.secondary) } }
        }
        .formStyle(.grouped)
        .navigationTitle("账单提醒")
        .inlineNavigationTitle()
        .sheet(item: $editing, onDismiss: refresh) { BillingScheduleEditor(card: $0) }
        .task { requested = enabled; await readStatus() }
        .onChange(of: requested) { _, value in update(value) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func selectionSummary(_ preferences: CardBillingPreferences?) -> String {
        guard let preferences, preferences.hasReminder else { return "未选提醒" }
        return [preferences.statementReminder ? "账单日" : nil,
                preferences.paymentReminder ? "还款日" : nil].compactMap { $0 }.joined(separator: "、") + "提醒"
    }

    private func update(_ value: Bool) {
        guard !updating, value != enabled, !RuntimeMode.isEphemeral else { return }
        updating = true
        Task {
            defer { updating = false }
            do {
                if value {
                    let granted = try await LocalReminderService.enable(LocalReminderService.billingEnabledKey, context: context)
                    message = granted ? nil : "请在系统设置中允许 CardPilot 通知。"
                } else {
                    try await LocalReminderService.disable(LocalReminderService.billingEnabledKey, context: context)
                    message = nil
                }
            } catch { message = "提醒未能更新，请重试。日期与账单记录已保留。" }
            requested = enabled
            await readStatus()
        }
    }

    private func refresh() {
        guard !updating else { return }
        updating = true
        Task {
            defer { updating = false }
            do { try await LocalReminderService.refresh(context: context); message = nil }
            catch { message = "提醒未能更新，请重试。" }
            await readStatus()
        }
    }

    private func readStatus() async {
        guard !RuntimeMode.isEphemeral else { count = 0; nextDate = nil; return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        permissionDenied = settings.authorizationStatus == .denied
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("cardpilot.billing.") }
        count = pending.count
        nextDate = pending.compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }.min()
    }
}
