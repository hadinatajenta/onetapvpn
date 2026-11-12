import Foundation
import UserNotifications

final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { [center] settings in
            guard settings.authorizationStatus == .notDetermined else {
                return
            }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func notifyConnectionFailed() {
        deliver(
            title: "OneTapVPN connection failed",
            body: "Open the menu bar icon to review the error and try again."
        )
    }

    func notifyAutoReconnectSucceeded() {
        deliver(
            title: "OneTapVPN reconnected",
            body: "The VPN connection was restored automatically."
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func deliver(title: String, body: String) {
        center.getNotificationSettings { [center] settings in
            let status = settings.authorizationStatus
            guard status == .authorized || status == .provisional else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(request) { _ in }
        }
    }
}
