import SwiftUI
import SwiftData

struct BillingScheduleEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let card: BankCard
    @AppStorage("billing.reminders.enabled") private var deviceEnabled = false
    @State private var statementDay: Int
    @State private var paymentDay: Int
    @State private var preferences: CardBillingPreferences
    @State private var original: CardBillingPreferences?
    @State private var message: String?

    init(card: BankCard) {
        self.card = card
        _statementDay = State(initialValue: card.statementDay)
        _paymentDay = State(initialValue: card.paymentDay)
        _preferences = State(initialValue: CardBillingPreferences(cardKey: card.syncKey))
    }

    private var hasChanges: Bool {
        original.map { $0 != preferences || statementDay != card.statementDay || paymentDay != card.paymentDay } ?? false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(card.name).font(.headline)
                    dayPicker("账单日", selection: $statementDay)
                    dayPicker("常用还款日", selection: $paymentDay)
                } footer: {
                    Text("每月固定日期仅作提醒，实际日期以银行账单为准。29–31 日在短月份按月末提醒。")
                }
                Section {
                    Toggle("账单日提醒", isOn: $preferences.statementReminder).disabled(statementDay == 0)
                    Toggle("还款提醒", isOn: $preferences.paymentReminder)
                    if preferences.paymentReminder {
                        Picker("提醒日期", selection: $preferences.advanceDays) {
                            Text("仅当天").tag(0)
                            Text("提前 1 天及当天").tag(1)
                            Text("提前 3 天及当天").tag(3)
                            Text("提前 7 天及当天").tag(7)
                        }
                    }
                    if preferences.hasReminder {
                        DatePicker("提醒时间", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                } header: { Text("这张卡的提醒") } footer: {
                    Text("已记录账单的实际还款日优先；同月已记录还清后不再提醒还款。未设置常用还款日时，只提醒已记录账单。时间为香港时间。")
                }
                Section {
                    NavigationLink {
                        BillingReminderSettingsView(showsCards: false)
                    } label: {
                        Label(deviceEnabled ? "本机提醒设置" : "开启本机通知", systemImage: deviceEnabled ? "bell" : "bell.slash")
                    }
                    if !deviceEnabled {
                        Text("本机通知尚未开启。保存日期和卡片提醒选项后，可随时开启。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let message { Section { Text(message).foregroundStyle(.red) } }
            }
            .formStyle(.grouped)
            .navigationTitle("日期与提醒")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DiscardChangesButton(hasChanges: hasChanges, discard: { dismiss() }) }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(original == nil) }
            }
        }
        .editorSize()
        .interactiveDismissDisabled(hasChanges)
        .task {
            guard original == nil else { return }
            do {
                preferences = try FinanceStore.snapshot(context: context).billingPreferences[card.syncKey] ?? CardBillingPreferences(cardKey: card.syncKey)
                original = preferences
            } catch { message = "暂时无法读取提醒设置。请重新打开，原有记录会保留。" }
        }
        .onChange(of: statementDay) { _, day in if day == 0 { preferences.statementReminder = false } }
    }

    private var reminderTime: Binding<Date> {
        Binding {
            HKCalendar.calendar.date(bySettingHour: preferences.hour, minute: preferences.minute, second: 0, of: .now) ?? .now
        } set: { date in
            preferences.hour = HKCalendar.calendar.component(.hour, from: date)
            preferences.minute = HKCalendar.calendar.component(.minute, from: date)
        }
    }

    private func dayPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            Text("未设置").tag(0)
            ForEach(1...31, id: \.self) { Text("每月 \($0) 日").tag($0) }
        }
    }

    private func save() {
        do {
            try Persistence.save(context) {
                try FinanceStore.save(preferences, context: context)
                card.statementDay = statementDay
                card.paymentDay = paymentDay
                card.modifiedAt = .now
                try Persistence.setProfileRevision(cardKey: card.syncKey, date: card.modifiedAt, context: context, advancing: true)
            }
            dismiss()
        } catch { message = PilotError.message(error) }
    }
}
