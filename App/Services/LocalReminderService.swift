import Foundation
import SwiftData
import UserNotifications

/// One owner of the app's notification queue, shared by billing and welcome reminders.
@MainActor enum LocalReminderService {
    static let billingEnabledKey = "billing.reminders.enabled"
    static let welcomeEnabledKey = "welcome.reminders"
    private static var refreshTask: Task<Void, Error>?
    private static var refreshNeeded = false
    private static var needsCleanup = true

    static func enable(_ key: String, context: ModelContext) async throws -> Bool {
        guard !RuntimeMode.isEphemeral else { return false }
        let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        UserDefaults.standard.set(allowed, forKey: key)
        try await refresh(context: context)
        return allowed
    }

    static func disable(_ key: String, context: ModelContext) async throws {
        guard !RuntimeMode.isEphemeral else { return }
        UserDefaults.standard.set(false, forKey: key)
        try await refresh(context: context)
    }

    static func refresh(context: ModelContext) async throws {
        guard !RuntimeMode.isEphemeral else { return }
        refreshNeeded = true
        if let refreshTask { try await refreshTask.value; return }
        // A later save or toggle queues a fresh pass instead of racing an in-flight center.add.
        let task = Task { @MainActor in
            defer { refreshTask = nil }
            repeat {
                refreshNeeded = false
                try await synchronize(context: context)
            } while refreshNeeded
        }
        refreshTask = task
        try await task.value
    }

    private static func synchronize(context: ModelContext) async throws {
        let center = UNUserNotificationCenter.current()
        let billingEnabled = UserDefaults.standard.bool(forKey: billingEnabledKey)
        let welcomeEnabled = UserDefaults.standard.bool(forKey: welcomeEnabledKey)
        if !billingEnabled && !welcomeEnabled {
            guard needsCleanup else { return }
            let existing = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: existing.filter { owns($0.identifier) }.map(\.identifier))
            needsCleanup = false
            return
        }
        needsCleanup = true
        let settings = await center.notificationSettings()
        let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        var reminders: [LocalReminder] = []
        if allowed && billingEnabled {
            reminders += BillingReminders.plan(cards: try context.fetch(FetchDescriptor<BankCard>()), finance: try FinanceStore.snapshot(context: context))
        }
        if allowed && welcomeEnabled {
            reminders += try welcomeReminders(context: context)
        }
        let existing = await center.pendingNotificationRequests()
        let otherCount = existing.count { !owns($0.identifier) }
        // Keep a bounded, chronological rolling queue rather than letting features displace each other.
        let planned = reminders.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }.prefix(max(0, 60 - otherCount))
        let wanted = Set(planned.map(\.id))
        center.removePendingNotificationRequests(withIdentifiers: existing.filter { owns($0.identifier) && !wanted.contains($0.identifier) }.map(\.identifier))
        let byID = Dictionary(existing.map { ($0.identifier, $0) }, uniquingKeysWith: { _, rhs in rhs })
        for reminder in planned {
            if let old = byID[reminder.id], old.content.title == reminder.title, old.content.body == reminder.body,
               old.content.userInfo["cardpilot.route"] as? String == reminder.route,
               (old.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() == reminder.date { continue }
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.userInfo = ["cardpilot.route": reminder.route]
            var components = HKCalendar.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            components.timeZone = HKCalendar.calendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }

    private static func owns(_ id: String) -> Bool {
        id.hasPrefix("cardpilot.billing.") || id.hasPrefix("cardpilot.welcome.")
    }

    private static func welcomeReminders(context: ModelContext) throws -> [LocalReminder] {
        var reminders: [LocalReminder] = []
        for info in OfferStore.offers(context: context) where info.isWelcome && !info.isArchived && !info.isHidden {
            let tracking = try OfferTrackingStore.load(for: info, context: context)
            guard tracking.status == .active, tracking.hasKnownDeadline else { continue }
            let cardName = info.cardName.components(separatedBy: " · ").last ?? info.cardName
            for days in [7, 1] {
                guard let day = HKCalendar.calendar.date(byAdding: .day, value: -days, to: HKCalendar.start(tracking.deadline)),
                      let date = HKCalendar.calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day), date > .now else { continue }
                reminders.append(LocalReminder(id: "cardpilot.welcome.\(info.id).\(days)", title: "迎新活动即将到期",
                    body: "\(cardName)：\(info.title)即将截止，请查看活动条件并更新个人状态。", date: date, route: "welcome"))
            }
        }
        return reminders
    }
}
