#if os(iOS)
import SwiftUI
import UserNotifications

@main
struct iOSAppLockerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            iOSContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Initialize NotificationManager which sets itself as delegate
        NotificationManager.shared.requestNotificationPermissions()

        // Sync iCloud KV
        NSUbiquitousKeyValueStore.default.synchronize()

        return true
    }
}
#endif
