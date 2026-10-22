import Foundation
import SwiftData
import UserNotifications

@MainActor enum WelcomeReminderService {
    static func enable(context: ModelContext) async throws -> Bool {
        let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        UserDefaults.standard.set(allowed, forKey: "welcome.reminders")
        if allowed { try await refresh(context: context) }
        return allowed
    }

    static func refresh(context: ModelContext) async throws {
        guard !RuntimeMode.isEphemeral, UserDefaults.standard.bool(forKey: "welcome.reminders") else { return }
        let offers = OfferStore.offers(context: context).filter(\.isWelcome)
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("cardpilot.welcome.") }
        try Task.checkCancellation()
        center.removePendingNotificationRequests(withIdentifiers: existing.map(\.identifier))
        var count = 0
        for info in offers where !info.isArchived && !info.isHidden {
            let tracking = try OfferTrackingStore.load(for: info, context: context)
            guard tracking.status == .active, tracking.hasKnownDeadline else { continue }
            let cardName = info.cardName.components(separatedBy: " · ").last ?? info.cardName
            for days in [7, 1] where count < 60 {
                try Task.checkCancellation()
                guard let day = HKCalendar.calendar.date(byAdding: .day, value: -days, to: HKCalendar.start(tracking.deadline)),
                      let date = HKCalendar.calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day), date > .now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "迎新活动即将到期"
                content.body = "\(cardName)：\(info.title)即将截止，请查看活动条件并更新个人状态。"
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: HKCalendar.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
                try await center.add(UNNotificationRequest(identifier: "cardpilot.welcome.\(info.id).\(days)", content: content, trigger: trigger))
                count += 1
            }
        }
    }
}
