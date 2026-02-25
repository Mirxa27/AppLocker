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
            // Keep Quit in the menu but route it through NSApp.terminate
            // so applicationShouldTerminate intercepts it
            CommandGroup(replacing: .appTermination) {
                Button("Quit AppLocker") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate, NSMenuDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem?
    private var isQuitAuthInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if !DEBUG
        applyAntiDebugger()
        #endif
        // Hide from Dock — menu bar only
        NSApp.setActivationPolicy(.accessory)

        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = self

        // Request permissions
        AppMonitor.shared.requestAccessibilityPermissions()
        NotificationManager.shared.requestNotificationPermissions()

        // Set up menu bar icon
        setupMenuBar()
        InactivityMonitor.shared.start()
        Task { CloudKitManager.shared.pruneOldRecords() }

        ScreenPrivacyManager.shared.applyWindowProtection()

        // Listen for iCloud KV changes (cross-device alerts)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudKVChanged),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        NSUbiquitousKeyValueStore.default.synchronize()

        // Assign window delegate to intercept the close button
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowBecameKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    // MARK: - Anti-Debugger

    #if !DEBUG
    private func applyAntiDebugger() {
        // PT_DENY_ATTACH (31): prevents a debugger from attaching after this point.
        // Called via dlsym to avoid direct ptrace symbol reference.
        typealias PtraceT = @convention(c) (Int32, Int32, UnsafeMutableRawPointer?, Int32) -> Int32
        if let handle = dlopen(nil, RTLD_LAZY),
           let sym = dlsym(handle, "ptrace") {
            let ptrace = unsafeBitCast(sym, to: PtraceT.self)
            _ = ptrace(31, 0, nil, 0)  // 31 == PT_DENY_ATTACH
        }
    }
    #endif

    // MARK: - Quit Protection

    /// Intercepts every quit path (Cmd+Q, dock menu, menu bar Quit).
    /// Force Quit (Cmd+Option+Esc) is a system-level signal and cannot be blocked by design.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // If passcode isn't set yet (first-launch setup), allow quit freely
        guard AuthenticationManager.shared.isPasscodeSet() else {
            return .terminateNow
        }
        // Prevent stacking multiple auth dialogs
        guard !isQuitAuthInProgress else {
            return .terminateLater
        }
        isQuitAuthInProgress = true
        showQuitAuthDialog()
        return .terminateLater   // macOS waits for reply(toApplicationShouldTerminate:)
    }

    private func showQuitAuthDialog() {
        let alert = NSAlert()
        alert.messageText = "Authentication Required"
        alert.informativeText = "Enter your AppLocker passcode to quit. Quitting stops all app monitoring."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit AppLocker")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Passcode"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let response = alert.runModal()
        isQuitAuthInProgress = false

        if response == .alertFirstButtonReturn {
            if AuthenticationManager.shared.verifyPasscode(field.stringValue) {
                NSApp.reply(toApplicationShouldTerminate: true)
            } else {
                AuthenticationManager.shared.recordFailedAttempt()
                let err = NSAlert()
                err.messageText = "Incorrect Passcode"
                err.informativeText = "AppLocker will continue running."
                err.alertStyle = .critical
                err.addButton(withTitle: "OK")
                err.runModal()
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        } else {
            NSApp.reply(toApplicationShouldTerminate: false)
        }
    }

    // MARK: - Window Close Protection

    @objc private func mainWindowBecameKey(_ notification: Notification) {
        // Attach self as delegate to every non-panel window (skips alerts/sheets)
        if let window = notification.object as? NSWindow, !(window is NSPanel) {
            window.delegate = self
        }
    }

    /// Red X close button: hide the window instead of closing it.
    /// App keeps running in the background so monitoring continues.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard AuthenticationManager.shared.isPasscodeSet() else {
            return true   // Setup not done yet — allow close
        }
        sender.orderOut(nil)   // Hide window; monitoring is unaffected
        return false
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
