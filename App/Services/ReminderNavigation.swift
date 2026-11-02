import Foundation
import Observation
import UserNotifications

@MainActor @Observable final class ReminderNavigation: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderNavigation()
    var destination: Destination?

    enum Destination: String, Identifiable {
        case billing, welcome
        var id: String { rawValue }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let route = response.notification.request.content.userInfo["cardpilot.route"] as? String else { return }
        await MainActor.run { self.destination = Destination(rawValue: route) }
    }
}
