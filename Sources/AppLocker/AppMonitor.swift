#if os(macOS)
// AppMonitor.swift
// Monitors and blocks locked applications

import Foundation
import AppKit
import ApplicationServices
import Combine
import SwiftUI

@MainActor
class AppMonitor: ObservableObject {
    static let shared = AppMonitor()
    
    @Published var lockedApps: [LockedAppInfo] = []
    @Published var isMonitoring = false
    @Published var blockLog: [String] = []
    @Published var categories: [AppCategory] = []
    @Published var usageRecords: [UsageRecord] = []
    @Published var temporarilyUnlockedApps: Set<String> = [] // Bundle IDs
    
    // Config
    @Published var unlockDuration: TimeInterval = 300 // 5 minutes default
    @Published var autoLockOnSleep: Bool = true
    @Published var blockingOverlayDuration: TimeInterval = 3.0
    
    // State for UI
    @Published var showUnlockDialog = false
    @Published var lastBlockedBundleID: String = ""
    @Published var lastBlockedAppName: String?
    
    private var monitoringTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    private let lockedAppsKey = "com.applocker.lockedApps"
    private let logKey = "com.applocker.blockLog"
    private let categoriesKey = "com.applocker.categories"
    private let usageKey = "com.applocker.usageRecords"
    private let settingsUnlockDurationKey = "com.applocker.unlockDuration"
    private let settingsAutoLockKey = "com.applocker.autoLockOnSleep"
    private let settingsOverlayDurationKey = "com.applocker.blockingOverlayDuration"
    
    private init() {
        loadSettings()
        loadLockedApps()
        loadCategories()
        loadBlockLog()
        loadUsageRecords()
        
        // Listen for sleep notifications if enabled
        NotificationCenter.default.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if self.autoLockOnSleep {
                        self.temporarilyUnlockedApps.removeAll()
                        self.addLog("Auto-locked all apps due to system sleep")
                    }
                }
            }
            .store(in: &cancellables)
            
        // Listen for remote commands
        NotificationCenter.default.addObserver(self, selector: #selector(handleRemoteCommand(_:)), name: NSNotification.Name("RemoteCommandReceived"), object: nil)
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        addLog("Monitoring started")
        UserDefaults.standard.set(true, forKey: "com.applocker.monitoringEnabled")
        
        monitoringTask = Task {
            while !Task.isCancelled {
                await checkRunningApps()
                try? await Task.sleep(nanoseconds: 200 * 1_000_000) // 200ms
            }
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
        addLog("Monitoring stopped")
        UserDefaults.standard.set(false, forKey: "com.applocker.monitoringEnabled")
    }
    
    private func checkRunningApps() {
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }
            
            // Skip if AppLocker itself
            if bundleID == Bundle.main.bundleIdentifier { continue }
            
            // Check if app is locked
            if let lockedApp = lockedApps.first(where: { $0.bundleID == bundleID }) {
                // Check if temporarily unlocked
                if temporarilyUnlockedApps.contains(bundleID) { continue }

                // Check schedule if active
                if let schedule = lockedApp.schedule, schedule.enabled {
                    if !schedule.isActiveNow() { continue }
                }

                // BLOCK THE APP
                terminateApp(app)

                // Only log and notify if not recently logged (debounce)
                if lastBlockedBundleID != bundleID {
                    let appName = app.localizedName ?? lockedApp.displayName
                    addLog("Blocked access to \(appName) (\(bundleID))")
                    recordUsage(bundleID: bundleID, appName: appName, event: .blocked)

                    // Show notification
                    NotificationManager.shared.sendBlockedAppNotification(appName: appName, bundleID: bundleID)

                    // Trigger UI for unlock
                    self.lastBlockedBundleID = bundleID
                    self.lastBlockedAppName = appName

                    // Bring AppLocker to front
                    NSApp.activate(ignoringOtherApps: true)
                    self.showUnlockDialog = true
                }
            }
        }
    }
    
    private func terminateApp(_ app: NSRunningApplication) {
        app.forceTerminate()
    }
    
    func temporarilyUnlock(bundleID: String) {
        temporarilyUnlockedApps.insert(bundleID)
        addLog("Temporarily unlocked \(bundleID) for \(Int(unlockDuration/60)) minutes")
        recordUsage(bundleID: bundleID, appName: bundleID, event: .unlocked)

        // Schedule re-lock
        Task {
            try? await Task.sleep(nanoseconds: UInt64(unlockDuration * 1_000_000_000))
            await MainActor.run {
                if self.temporarilyUnlockedApps.contains(bundleID) {
                    self.temporarilyUnlockedApps.remove(bundleID)
                    self.addLog("Re-locked \(bundleID) after timeout")
                }
            }
        }
        
        // Notify
        if let appName = lockedApps.first(where: { $0.bundleID == bundleID })?.displayName {
            NotificationManager.shared.sendUnlockedAppNotification(appName: appName, bundleID: bundleID)
        }
        
        showUnlockDialog = false
        lastBlockedBundleID = ""
        lastBlockedAppName = nil
    }
    
    // MARK: - Management
    
    func addLockedApp(bundleID: String) {
        if !lockedApps.contains(where: { $0.bundleID == bundleID }) {
            // Get app name and icon if possible
            var displayName = bundleID
            var path: String? = nil

            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                path = url.path
                displayName = FileManager.default.displayName(atPath: url.path)
            }

            let info = LockedAppInfo(bundleID: bundleID, displayName: displayName, path: path, dateAdded: Date(), category: nil, schedule: nil)
            lockedApps.append(info)
            saveLockedApps()
            addLog("Locked new app: \(displayName)")
        }
    }
    
    func removeLockedApp(bundleID: String) {
        lockedApps.removeAll { $0.bundleID == bundleID }
        saveLockedApps()
        addLog("Removed lock for: \(bundleID)")
    }
    
    func updateAppCategory(bundleID: String, category: String?) {
        if let index = lockedApps.firstIndex(where: { $0.bundleID == bundleID }) {
            var app = lockedApps[index]
            app.category = category
            lockedApps[index] = app
            saveLockedApps()
        }
    }
    
    func updateAppSchedule(bundleID: String, schedule: LockSchedule?) {
        if let index = lockedApps.firstIndex(where: { $0.bundleID == bundleID }) {
            var app = lockedApps[index]
            app.schedule = schedule
            lockedApps[index] = app
            saveLockedApps()
        }
    }
    
    // MARK: - Category Management
    
    func addCategory(_ category: AppCategory) {
        if !categories.contains(where: { $0.name == category.name }) {
            categories.append(category)
            saveCategories()
        }
    }
    
    func removeCategory(name: String) {
        categories.removeAll { $0.name == name }
        for i in 0..<lockedApps.count {
            if lockedApps[i].category == name {
                updateAppCategory(bundleID: lockedApps[i].bundleID, category: nil)
            }
        }
        saveCategories()
    }
    
    func lockAllInCategory(_ categoryName: String) {
        guard let category = categories.first(where: { $0.name == categoryName }) else { return }
        for bundleID in category.appBundleIDs { addLockedApp(bundleID: bundleID) }
    }
    
    func unlockAllInCategory(_ categoryName: String) {
        guard let category = categories.first(where: { $0.name == categoryName }) else { return }
        for bundleID in category.appBundleIDs { removeLockedApp(bundleID: bundleID) }
    }
    
    private func loadCategories() {
        if let data = UserDefaults.standard.data(forKey: categoriesKey),
           let cats = try? JSONDecoder().decode([AppCategory].self, from: data) {
            categories = cats
        } else {
            categories = AppCategory.defaults
            saveCategories()
        }
    }
    
    private func saveCategories() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: categoriesKey)
        }
    }
    
    // MARK: - Usage Tracking
    
    func recordUsage(bundleID: String, appName: String, event: UsageRecord.UsageEvent) {
        let record = UsageRecord(bundleID: bundleID, appName: appName, timestamp: Date(), event: event)
        usageRecords.insert(record, at: 0)
        if usageRecords.count > 1000 {
            usageRecords = Array(usageRecords.prefix(1000))
        }
        saveUsageRecords()
    }
    
    func getUsageStats() -> [UsageStats] {
        return computeStats(from: usageRecords)
    }
    
    func getUsageStatsForPeriod(days: Int) -> [UsageStats] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return computeStats(from: usageRecords.filter { $0.timestamp >= cutoff })
    }
    
    private func computeStats(from records: [UsageRecord]) -> [UsageStats] {
        var statsMap: [String: UsageStats] = [:]
        for record in records {
            var stats = statsMap[record.bundleID] ?? UsageStats(
                bundleID: record.bundleID, appName: record.appName,
                blockedCount: 0, unlockedCount: 0, failedAttemptCount: 0, lastBlocked: nil
            )
            switch record.event {
            case .blocked:
                stats.blockedCount += 1
                if stats.lastBlocked == nil || record.timestamp > stats.lastBlocked! { stats.lastBlocked = record.timestamp }
            case .unlocked: stats.unlockedCount += 1
            case .failedAttempt: stats.failedAttemptCount += 1
            case .launched: break
            }
            statsMap[record.bundleID] = stats
        }
        return Array(statsMap.values).sorted { ($0.blockedCount + $0.failedAttemptCount) > ($1.blockedCount + $1.failedAttemptCount) }
    }
    
    private func loadUsageRecords() {
        if let data = UserDefaults.standard.data(forKey: usageKey),
           let records = try? JSONDecoder().decode([UsageRecord].self, from: data) {
            usageRecords = records
        }
    }
    
    private func saveUsageRecords() {
        if let data = try? JSONEncoder().encode(usageRecords) {
            UserDefaults.standard.set(data, forKey: usageKey)
        }
    }
    
    // MARK: - Export / Import
    
    func exportConfiguration() -> Data? {
        let export = AppLockerExport(
            version: "3.0", exportDate: Date(), lockedApps: lockedApps, categories: categories,
            settings: ExportedSettings(unlockDuration: unlockDuration, autoLockOnSleep: autoLockOnSleep, blockingOverlayDuration: blockingOverlayDuration)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(export)
    }
    
    func exportToFile() {
        guard let data = exportConfiguration() else { return }
        let panel = NSSavePanel()
        panel.title = "Export AppLocker Configuration"
        panel.nameFieldStringValue = "AppLocker-Config.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }
    
    func importFromFile() {
        let panel = NSOpenPanel()
        panel.title = "Import AppLocker Configuration"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.urls.first else { return }
            guard let data = try? Data(contentsOf: url) else { return }
            self?.importConfiguration(data: data)
        }
    }
    
    func importConfiguration(data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let imported = try? decoder.decode(AppLockerExport.self, from: data) else {
            addLog("IMPORT FAILED: Invalid format")
            return
        }
        for app in imported.lockedApps {
            if !lockedApps.contains(where: { $0.bundleID == app.bundleID }) { lockedApps.append(app) }
        }
        saveLockedApps()
        for cat in imported.categories {
            if !categories.contains(where: { $0.name == cat.name }) { categories.append(cat) }
        }
        saveCategories()
        unlockDuration = imported.settings.unlockDuration
        autoLockOnSleep = imported.settings.autoLockOnSleep
        blockingOverlayDuration = imported.settings.blockingOverlayDuration
        saveSettings()
        addLog("IMPORTED: \(imported.lockedApps.count) apps, \(imported.categories.count) categories")
    }
    
    // MARK: - Persistence
    
    private func loadLockedApps() {
        if let data = UserDefaults.standard.data(forKey: lockedAppsKey),
           let apps = try? JSONDecoder().decode([LockedAppInfo].self, from: data) {
            lockedApps = apps
        }
        if UserDefaults.standard.bool(forKey: "com.applocker.monitoringEnabled") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startMonitoring()
            }
        }
    }
    
    private func saveLockedApps() {
        if let data = try? JSONEncoder().encode(lockedApps) {
            UserDefaults.standard.set(data, forKey: lockedAppsKey)
        }
    }
    
    // MARK: - Permissions
    
    func requestAccessibilityPermissions() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    
    func hasAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }
    
    // MARK: - Logging
    
    func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let entry = "[\(timestamp)] \(message)"

        self.blockLog.insert(entry, at: 0)
        if self.blockLog.count > 500 {
            self.blockLog = Array(self.blockLog.prefix(500))
        }
        self.saveBlockLog()

        print("AppLocker: \(entry)")
    }
    
    func clearLog() {
        blockLog.removeAll()
        saveBlockLog()
    }
    
    private func loadBlockLog() {
        if let logs = UserDefaults.standard.stringArray(forKey: logKey) {
            blockLog = logs
        }
    }
    
    private func saveBlockLog() {
        UserDefaults.standard.set(blockLog, forKey: logKey)
    }

    private func loadSettings() {
        if UserDefaults.standard.object(forKey: settingsUnlockDurationKey) != nil {
            unlockDuration = UserDefaults.standard.double(forKey: settingsUnlockDurationKey)
        }
        if UserDefaults.standard.object(forKey: settingsAutoLockKey) != nil {
            autoLockOnSleep = UserDefaults.standard.bool(forKey: settingsAutoLockKey)
        }
        if UserDefaults.standard.object(forKey: settingsOverlayDurationKey) != nil {
            blockingOverlayDuration = UserDefaults.standard.double(forKey: settingsOverlayDurationKey)
        }
    }

    func saveSettings() {
        UserDefaults.standard.set(unlockDuration, forKey: settingsUnlockDurationKey)
        UserDefaults.standard.set(autoLockOnSleep, forKey: settingsAutoLockKey)
        UserDefaults.standard.set(blockingOverlayDuration, forKey: settingsOverlayDurationKey)
    }

    @objc func handleRemoteCommand(_ notification: Notification) {
        guard let command = notification.object as? RemoteCommand else { return }

        Task { @MainActor in
            switch command.action {
            case .lockAll:
                self.lockMacScreen()
            case .unlockAll:
                // Temporarily unlock all locked apps
                for app in self.lockedApps {
                    self.temporarilyUnlock(bundleID: app.bundleID)
                }
                self.addLog("Remote Command: Unlock All executed")
            case .unlockApp:
                if let bundleID = command.bundleID {
                    self.temporarilyUnlock(bundleID: bundleID)
                    self.addLog("Remote Command: Unlock \(bundleID) executed")
                }
            }
        }
    }

    private func lockMacScreen() {
        let source = """
        tell application "System Events" to sleep
        """
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }
        self.addLog("Remote Command: Lock Screen executed")
    }
}
#endif
