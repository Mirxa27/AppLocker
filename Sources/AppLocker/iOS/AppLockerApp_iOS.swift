#if os(iOS)
import SwiftUI
import UserNotifications
import UIKit

@main
struct iOSAppLockerApp: App {
    @UIApplicationDelegateAdaptor(iOSAppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            iOSRootView()
        }
    }
}

class iOSAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ app: UIApplication,
                     didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationManager.shared.requestNotificationPermissions()
        NSUbiquitousKeyValueStore.default.synchronize()
        Task { @MainActor in KVStoreManager.shared.decodeAllKeys() }
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Task { @MainActor in AppProtectionManager.shared.handleBackground() }
        addPrivacySnapshot()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        Task { @MainActor in AppProtectionManager.shared.handleForeground() }
        removePrivacySnapshot()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound, .badge])
    }

    func application(_ app: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler handler: @escaping (UIBackgroundFetchResult) -> Void) {
        handler(.newData)
    }

    private func addPrivacySnapshot() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.windows.first else { return }
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        blur.frame = window.bounds
        blur.tag   = 9999
        window.addSubview(blur)
    }

    private func removePrivacySnapshot() {
        UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.windows.first?
            .viewWithTag(9999)?.removeFromSuperview()
    }
}
#endif
