import Foundation

enum WelcomeTrackingStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case unconfirmed, active, achieved, received, ended
    var id: Self { self }
    var label: String {
        switch self {
        case .unconfirmed: "未确认"
        case .active: "进行中"
        case .achieved: "用户确认已达标"
        case .received: "奖励已到账"
        case .ended: "已结束"
        }
    }
    var symbol: String {
        switch self {
        case .unconfirmed: "questionmark.circle"
        case .active: "clock"
        case .achieved: "checkmark.circle"
        case .received: "checkmark.seal.fill"
        case .ended: "archivebox"
        }
    }
}

/// Personal declaration, deliberately independent of transaction eligibility.
struct WelcomeTracking: Codable, Equatable, Sendable {
    var status: WelcomeTrackingStatus = .unconfirmed
    var applicationDate: Date?
    var issueDate: Date?
    var deadline: Date
    var thresholdCents: Int64
    var rewardContent: String
    var notes = ""
    var receivedOn: Date?
    /// Optional for backward decoding of existing personal records; unknown official dates stay unknown.
    var deadlineConfirmed: Bool? = nil
    var hasKnownDeadline: Bool { deadlineConfirmed ?? true }

    func effectiveStatus(now: Date = .now) -> WelcomeTrackingStatus {
        if hasKnownDeadline, (status == .active || status == .unconfirmed), HKCalendar.daysLeft(deadline, now: now) < 0 { return .ended }
        return status
    }
}
