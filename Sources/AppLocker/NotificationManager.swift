// NotificationManager.swift
// Handles local and cross-device notifications when locked apps are accessed

import Foundation
import UserNotifications
import CryptoKit
import Security
#if os(macOS)
import AppKit
#endif

// MARK: - Command HMAC Signer

private enum CommandSigner {
    private static let secretKey = "com.applocker.commandSecret"
    private static let service   = "com.applocker.security"

    static func sharedSecret() -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: secretKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data {
            return SymmetricKey(data: data)
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        let newSecret = Data(bytes)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: secretKey,
            kSecValueData as String: newSecret,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanTrue!
        ]
        SecItemAdd(add as CFDictionary, nil)
        return SymmetricKey(data: newSecret)
    }

    static func sign(_ cmd: RemoteCommand) -> String {
        let msg = Data((cmd.id.uuidString + cmd.action.rawValue + String(cmd.timestamp.timeIntervalSince1970)).utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: msg, using: sharedSecret())
        return Data(mac).base64EncodedString()
    }

    static func verify(_ cmd: RemoteCommand) -> Bool {
        guard let hmac = cmd.hmac,
              let hmacData = Data(base64Encoded: hmac),
              Date().timeIntervalSince(cmd.timestamp) < 120 else { return false }
        let msg = Data((cmd.id.uuidString + cmd.action.rawValue + String(cmd.timestamp.timeIntervalSince1970)).utf8)
        // Constant-time comparison via CryptoKit — no timing side-channel
        return HMAC<SHA256>.isValidAuthenticationCode(hmacData, authenticating: msg, using: sharedSecret())
    }
}

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var notificationsEnabled = true
    @Published var crossDeviceEnabled = true
    @Published var notificationHistory: [NotificationRecord] = []
    
    private let historyKey = "com.applocker.notificationHistory"
    private let notificationsEnabledKey = "com.applocker.notificationsEnabled"
    private let crossDeviceEnabledKey = "com.applocker.crossDeviceEnabled"
    
    private init() {
        loadSettings()
        loadHistory()

        // Listen for iCloud KV changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudKVChanged),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        NSUbiquitousKeyValueStore.default.synchronize()
    }
    
    // MARK: - Permissions
    
    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("Notification permissions granted")
                } else if let error = error {
                    print("Notification permission error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Local Notifications
    
    func sendBlockedAppNotification(appName: String, bundleID: String) {
        guard notificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "App Access Blocked"
        content.subtitle = "\(appName) was blocked"
        content.body = "Someone attempted to open \(appName) which is locked by AppLocker."
        content.sound = .default
        content.categoryIdentifier = "APP_BLOCKED"
        content.userInfo = [
            "bundleID": bundleID,
            "appName": appName,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // Add action buttons
        let unlockAction = UNNotificationAction(identifier: "UNLOCK", title: "Unlock Temporarily", options: [.authenticationRequired])
        let dismissAction = UNNotificationAction(identifier: "DISMISS", title: "Dismiss", options: [.destructive])
        let category = UNNotificationCategory(identifier: "APP_BLOCKED", actions: [unlockAction, dismissAction], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let request = UNNotificationRequest(
            identifier: "blocked-\(bundleID)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error.localizedDescription)")
            }
        }
        
        // Record the notification
        let record = NotificationRecord(
            appName: appName,
            bundleID: bundleID,
            timestamp: Date(),
            type: .blocked
        )
        addToHistory(record)
        
        // Send cross-device notification
        if crossDeviceEnabled {
            sendCrossDeviceNotification(appName: appName, bundleID: bundleID)
        }
    }
    
    func sendUnlockedAppNotification(appName: String, bundleID: String) {
        guard notificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "App Unlocked"
        content.body = "\(appName) was unlocked successfully."
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "unlocked-\(bundleID)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
        
        let record = NotificationRecord(
            appName: appName,
            bundleID: bundleID,
            timestamp: Date(),
            type: .unlocked
        )
        addToHistory(record)
    }
    
    func sendFailedAuthNotification(appName: String, bundleID: String) {
        guard notificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Failed Unlock Attempt"
        content.subtitle = "Incorrect passcode for \(appName)"
        content.body = "Someone entered an incorrect passcode trying to unlock \(appName). This could be an unauthorized access attempt."
        content.sound = UNNotificationSound.defaultCritical
        content.interruptionLevel = .critical
        
        let request = UNNotificationRequest(
            identifier: "failed-\(bundleID)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
        
        let record = NotificationRecord(
            appName: appName,
            bundleID: bundleID,
            timestamp: Date(),
            type: .failedAttempt
        )
        addToHistory(record)
        
        // Always send cross-device for failed attempts
        sendCrossDeviceNotification(appName: appName, bundleID: bundleID, isFailed: true)
    }
    
    // MARK: - Cross-Device Notifications (via NSDistributedNotificationCenter + iCloud)
    
    func sendCrossDeviceNotification(appName: String, bundleID: String, isFailed: Bool = false) {
        guard crossDeviceEnabled else { return }
        
        // Use NSUbiquitousKeyValueStore (iCloud Key-Value) to sync alerts across devices
        let store = NSUbiquitousKeyValueStore.default
        let deviceName = ProcessInfo.processInfo.hostName
        
        let alert: [String: Any] = [
            "appName": appName,
            "bundleID": bundleID,
            "timestamp": Date().timeIntervalSince1970,
            "deviceName": deviceName,
            "type": isFailed ? "failed_attempt" : "blocked",
            "message": isFailed
                ? "ALERT: Failed unlock attempt on \(appName) from \(deviceName)"
                : "Access to \(appName) was blocked on \(deviceName)"
        ]
        
        // Store latest alert in iCloud KV store - syncs to all devices with same Apple ID
        if let data = try? JSONSerialization.data(withJSONObject: alert) {
            store.set(data, forKey: "com.applocker.latestAlert")
            store.set(Date().timeIntervalSince1970, forKey: "com.applocker.alertTimestamp")
            store.synchronize()
        }
        
        #if os(macOS)
        // Also use distributed notifications for same-machine processes
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.applocker.appBlocked"),
            object: nil,
            userInfo: ["appName": appName, "bundleID": bundleID],
            deliverImmediately: true
        )
        
        // Use AppleScript to send notification to other devices via Messages/FindMy
        if isFailed {
            sendUrgentAlertViaAppleScript(appName: appName)
        }
        #endif
    }
    
    #if os(macOS)
    private func sendUrgentAlertViaAppleScript(appName: String) {
        let deviceName = ProcessInfo.processInfo.hostName
        let script = """
        display notification "SECURITY ALERT: Failed unlock attempt on \(appName) from \(deviceName)" with title "AppLocker Security Alert" sound name "Sosumi"
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
    #endif

    // MARK: - Remote Commands

    func sendRemoteCommand(_ action: RemoteCommand.Action, bundleID: String? = nil) {
        var command = RemoteCommand(
            id: UUID(),
            action: action,
            bundleID: bundleID,
            sourceDevice: ProcessInfo.processInfo.hostName,
            timestamp: Date()
        )
        command.hmac = CommandSigner.sign(command)

        if let data = try? JSONEncoder().encode(command) {
            NSUbiquitousKeyValueStore.default.set(data, forKey: "com.applocker.latestCommand")
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    @objc func iCloudKVChanged(_ notification: Notification) {
        let store = NSUbiquitousKeyValueStore.default
        let thisDevice = ProcessInfo.processInfo.hostName

        // Check for Alerts
        if let data = store.data(forKey: "com.applocker.latestAlert"),
           let alert = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let timestamp = alert["timestamp"] as? TimeInterval,
           let deviceName = alert["deviceName"] as? String,
           let message = alert["message"] as? String,
           deviceName != thisDevice,
           Date().timeIntervalSince1970 - timestamp < 60 {

            // Show alert
            let content = UNMutableNotificationContent()
            content.title = "AppLocker Alert from \(deviceName)"
            content.body = message
            content.sound = .defaultCritical

            let request = UNNotificationRequest(
                identifier: "cross-device-\(timestamp)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }

        // Check for Commands
        if let data = store.data(forKey: "com.applocker.latestCommand"),
           let command = try? JSONDecoder().decode(RemoteCommand.self, from: data),
           command.sourceDevice != thisDevice,
           Date().timeIntervalSince(command.timestamp) < 60,
           CommandSigner.verify(command) {

             DispatchQueue.main.async {
                 NotificationCenter.default.post(name: NSNotification.Name("RemoteCommandReceived"), object: command)
             }
        }
    }
    
    // MARK: - History
    
    private func addToHistory(_ record: NotificationRecord) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.notificationHistory.insert(record, at: 0)
            if self.notificationHistory.count > 100 {
                self.notificationHistory = Array(self.notificationHistory.prefix(100))
            }
            self.saveHistory()
        }
    }
    
    func clearHistory() {
        notificationHistory.removeAll()
        saveHistory()
    }
    
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let records = try? JSONDecoder().decode([NotificationRecord].self, from: data) else { return }
        notificationHistory = records
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(notificationHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
    
    private func loadSettings() {
        if UserDefaults.standard.object(forKey: notificationsEnabledKey) != nil {
            notificationsEnabled = UserDefaults.standard.bool(forKey: notificationsEnabledKey)
        }
        if UserDefaults.standard.object(forKey: crossDeviceEnabledKey) != nil {
            crossDeviceEnabled = UserDefaults.standard.bool(forKey: crossDeviceEnabledKey)
        }
    }
    
    func saveSettings() {
        UserDefaults.standard.set(notificationsEnabled, forKey: notificationsEnabledKey)
        UserDefaults.standard.set(crossDeviceEnabled, forKey: crossDeviceEnabledKey)
    }
}

