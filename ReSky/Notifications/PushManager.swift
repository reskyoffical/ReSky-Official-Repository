import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            PushManager.shared.deviceToken = token
            await SessionStore.shared.registerDevice()
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push registration failed: \(error.localizedDescription)")
    }

    // Foreground notifications: hide message banners for the chat you're looking at.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let info = notification.request.content.userInfo
        let conv = (info["conversation_id"] as? String).flatMap(UUID.init(uuidString:))
        let current = await MainActor.run { ActiveChat.current }
        if let conv, conv == current { return [] }
        if info["call_id"] != nil { return [] } // in-app call screen handles it
        return [.banner, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let s = info["conversation_id"] as? String, let id = UUID(uuidString: s) {
            await MainActor.run { SessionStore.shared.pendingConversation = id }
        }
    }
}

@MainActor
final class PushManager {
    static let shared = PushManager()
    var deviceToken: String?

    func requestPermission() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }
}

/// Which conversation is on screen (used to suppress duplicate banners and sounds).
@MainActor
enum ActiveChat {
    static var current: UUID?
}
