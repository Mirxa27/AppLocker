#if os(macOS)
// AppLockerApp.swift
// Main app entry point with menu bar support

import SwiftUI
import LocalAuthentication
import UserNotifications

@main
struct MacAppLockerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MacContentView()
                .frame(minWidth: 800, minHeight: 550)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Request permissions
        AppMonitor.shared.requestAccessibilityPermissions()
        NotificationManager.shared.requestNotificationPermissions()
        
        // Set up menu bar icon
        setupMenuBar()
        
        // Listen for iCloud KV changes (cross-device alerts)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudKVChanged),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        NSUbiquitousKeyValueStore.default.synchronize()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running in background for monitoring
    }
    
    // MARK: - Menu Bar
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "AppLocker")
        }
        
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }
    
    // Rebuild menu items on demand when the menu is about to open
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        let statusTitle = AppMonitor.shared.isMonitoring
            ? "Status: Monitoring (\(AppMonitor.shared.lockedApps.count) apps)"
            : "Status: Not Monitoring"
        let statusMenuItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Open AppLocker", action: #selector(openApp), keyEquivalent: "o"))
        
        let monitorTitle = AppMonitor.shared.isMonitoring ? "Stop Monitoring" : "Start Monitoring"
        let monitorItem = NSMenuItem(title: monitorTitle, action: #selector(toggleMonitoring), keyEquivalent: "m")
        menu.addItem(monitorItem)
        
        menu.addItem(NSMenuItem.separator())
        
        if !AppMonitor.shared.temporarilyUnlockedApps.isEmpty {
            let relockItem = NSMenuItem(title: "Re-lock All Unlocked Apps", action: #selector(relockAll), keyEquivalent: "r")
            menu.addItem(relockItem)
            menu.addItem(NSMenuItem.separator())
        }
        
        menu.addItem(NSMenuItem(title: "Quit AppLocker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
    
    @objc func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc func toggleMonitoring() {
        if AppMonitor.shared.isMonitoring {
            AppMonitor.shared.stopMonitoring()
        } else {
            AppMonitor.shared.startMonitoring()
        }
    }
    
    @objc func relockAll() {
        AppMonitor.shared.temporarilyUnlockedApps.removeAll()
        AppMonitor.shared.addLog("Re-locked all temporarily unlocked apps via menu bar")
    }
    
    // MARK: - Notification Delegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        if response.actionIdentifier == "UNLOCK" {
            if let bundleID = userInfo["bundleID"] as? String {
                if AuthenticationManager.shared.isAuthenticated {
                    AppMonitor.shared.temporarilyUnlock(bundleID: bundleID)
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                    AppMonitor.shared.lastBlockedBundleID = bundleID
                    AppMonitor.shared.lastBlockedAppName = userInfo["appName"] as? String
                    AppMonitor.shared.showUnlockDialog = true
                }
            }
        }
        
        completionHandler()
    }
    
    // MARK: - iCloud KV Sync (Cross-device alerts)
    
    @objc func iCloudKVChanged(_ notification: Notification) {
        let store = NSUbiquitousKeyValueStore.default
        
        guard let data = store.data(forKey: "com.applocker.latestAlert"),
              let alert = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = alert["message"] as? String,
              let deviceName = alert["deviceName"] as? String else { return }
        
        let thisDevice = Host.current().localizedName ?? "Mac"
        if deviceName == thisDevice { return }
        
        let content = UNMutableNotificationContent()
        content.title = "AppLocker Alert from \(deviceName)"
        content.body = message
        content.sound = .defaultCritical
        
        let request = UNNotificationRequest(
            identifier: "cross-device-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}
#endif
