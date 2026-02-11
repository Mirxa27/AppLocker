// NotificationManager.swift
// Handles local and cross-device notifications when locked apps are accessed

import Foundation
import UserNotifications
import AppKit

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
        requestNotificationPermissions()
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
        
        let alert: [String: Any] = [
            "appName": appName,
            "bundleID": bundleID,
            "timestamp": Date().timeIntervalSince1970,
            "deviceName": Host.current().localizedName ?? "Mac",
            "type": isFailed ? "failed_attempt" : "blocked",
            "message": isFailed
                ? "ALERT: Failed unlock attempt on \(appName) from \(Host.current().localizedName ?? "Mac")"
                : "Access to \(appName) was blocked on \(Host.current().localizedName ?? "Mac")"
        ]
        
        // Store latest alert in iCloud KV store - syncs to all devices with same Apple ID
        if let data = try? JSONSerialization.data(withJSONObject: alert) {
            store.set(data, forKey: "com.applocker.latestAlert")
            store.set(Date().timeIntervalSince1970, forKey: "com.applocker.alertTimestamp")
            store.synchronize()
        }
        
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
    }
    
    private func sendUrgentAlertViaAppleScript(appName: String) {
        let deviceName = Host.current().localizedName ?? "Mac"
        let script = """
        display notification "SECURITY ALERT: Failed unlock attempt on \(appName) from \(deviceName)" with title "AppLocker Security Alert" sound name "Sosumi"
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
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

// MARK: - Notification Record Model

struct NotificationRecord: Codable, Identifiable {
    let id: UUID
    let appName: String
    let bundleID: String
    let timestamp: Date
    let type: NotificationType
    
    init(appName: String, bundleID: String, timestamp: Date, type: NotificationType) {
        self.id = UUID()
        self.appName = appName
        self.bundleID = bundleID
        self.timestamp = timestamp
        self.type = type
    }
    
    enum NotificationType: String, Codable {
        case blocked
        case unlocked
        case failedAttempt
        
        var displayName: String {
            switch self {
            case .blocked: return "Blocked"
            case .unlocked: return "Unlocked"
            case .failedAttempt: return "Failed Attempt"
            }
        }
        
        var icon: String {
            switch self {
            case .blocked: return "hand.raised.fill"
            case .unlocked: return "lock.open.fill"
            case .failedAttempt: return "exclamationmark.triangle.fill"
            }
        }
        
        var color: String {
            switch self {
            case .blocked: return "orange"
            case .unlocked: return "green"
            case .failedAttempt: return "red"
            }
        }
    }
}
