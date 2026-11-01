import Foundation
import UserNotifications

enum NotificationService {
    static let identifier = "myradio.morning"

    static func schedule(minutes: Int) async throws {
        let center = UNUserNotificationCenter.current()
        let allowed = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        guard allowed else { throw ReminderError.denied }
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        var parts = DateComponents()
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        let content = UNMutableNotificationContent()
        content.title = "おはようございます ☀️"
        content.body = "マイラジオを開いて、あなた専用の番組を聴きましょう。"
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

enum ReminderError: LocalizedError {
    case denied
    var errorDescription: String? { "通知が許可されていません。iPhoneの設定からマイラジオの通知を許可してください。" }
}
