import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()

    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[NotificationManager] Permission error: \(error.localizedDescription)")
            }
        }
    }

    func sendResetNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Claude Code"
        content.body = "👍🏼 Your Claude Code token limit has been reset"
        content.sound = .default
        schedule(content: content, identifier: "token.reset.\(Date().timeIntervalSince1970)")
    }

    func sendLowTokenNotification(percent: Double, threshold: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Claude Code"
        content.body = "⚠️ Claude Code tokens at \(threshold)% remaining"
        content.sound = .default
        schedule(content: content, identifier: "token.low.\(threshold)")
    }

    func sendCompletionNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Claude Code"
        content.body = "✅ Claude has finished generating your response"
        content.sound = .default
        schedule(content: content, identifier: "claude.completion.\(Date().timeIntervalSince1970)")
    }

    private func schedule(content: UNMutableNotificationContent, identifier: String) {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NotificationManager] Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }
}
