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
    private var workspaceObserver: Any?
    private var activationObserver: Any?
    /// Tracks when we last showed UI for a bundle ID to avoid spamming the dialog
    private var lastNotifiedTime: [String: Date] = [:]
    private let notificationCooldown: TimeInterval = 3.0

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

    // MARK: - Monitoring Control

    func startMonitoring() {
        // Cancel any existing task first
        monitoringTask?.cancel()
        monitoringTask = nil

        isMonitoring = true
        addLog("Monitoring started")
        UserDefaults.standard.set(true, forKey: "com.applocker.monitoringEnabled")

        // 1) Observe app launches for immediate blocking
        setupWorkspaceObservers()

        // 2) Polling loop as backup (catches apps that were already running)
        monitoringTask = Task {
            while !Task.isCancelled {
                checkRunningApps()
                try? await Task.sleep(nanoseconds: 200 * 1_000_000) // 200ms
            }
        }

        // 3) Immediately check currently running apps
        checkRunningApps()
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        isMonitoring = false
        removeWorkspaceObservers()
        addLog("Monitoring stopped")
        UserDefaults.standard.set(false, forKey: "com.applocker.monitoringEnabled")
    }

    // MARK: - Workspace Observers (Immediate Detection)

    private func setupWorkspaceObservers() {
        removeWorkspaceObservers()

        let center = NSWorkspace.shared.notificationCenter

        // Fires the moment an app finishes launching
        workspaceObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self, self.isMonitoring else { return }
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self.handleDetectedApp(app)
                }
            }
        }

        // Also catch when a locked app gets activated (brought to front)
        activationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self, self.isMonitoring else { return }
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self.handleDetectedApp(app)
                }
            }
        }
    }

    private func removeWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        if let obs = workspaceObserver {
            center.removeObserver(obs)
            workspaceObserver = nil
        }
        if let obs = activationObserver {
            center.removeObserver(obs)
            activationObserver = nil
        }
    }

    // MARK: - App Detection & Blocking

    private func checkRunningApps() {
        guard isMonitoring else { return }
        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            handleDetectedApp(app)
        }
    }

    /// Core blocking logic: determines if an app should be blocked and terminates it
    private func handleDetectedApp(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }

        // Skip AppLocker itself
        if bundleID == Bundle.main.bundleIdentifier { return }

        // Check if app is in the locked list
        guard let lockedApp = lockedApps.first(where: { $0.bundleID == bundleID }) else { return }

        // Check if temporarily unlocked
        if temporarilyUnlockedApps.contains(bundleID) { return }

        // Check schedule
        if let schedule = lockedApp.schedule, schedule.enabled {
            if !schedule.isActiveNow() { return }
        }

        // --- BLOCK THE APP ---
        let terminated = terminateApp(app)

        let appName = app.localizedName ?? lockedApp.displayName

        // Show UI/notification with cooldown to avoid spamming
        let now = Date()
        let lastTime = lastNotifiedTime[bundleID] ?? .distantPast
        if now.timeIntervalSince(lastTime) >= notificationCooldown {
            lastNotifiedTime[bundleID] = now

            addLog("Blocked \(appName) (\(bundleID)) — terminated: \(terminated)")
            recordUsage(bundleID: bundleID, appName: appName, event: .blocked)
            NotificationManager.shared.sendBlockedAppNotification(appName: appName, bundleID: bundleID)

            // Show unlock dialog
            self.lastBlockedBundleID = bundleID
            self.lastBlockedAppName = appName
            NSApp.activate(ignoringOtherApps: true)
            self.showUnlockDialog = true
        }
    }

    /// Attempts to terminate an app using multiple strategies.
    /// Returns true if the app appears to have been terminated.
    @discardableResult
    private func terminateApp(_ app: NSRunningApplication) -> Bool {
        // Strategy 1: graceful quit
        if app.terminate() {
            // Give it a moment, then verify
            return true
        }

        // Strategy 2: force terminate (SIGKILL)
        if app.forceTerminate() {
            return true
        }

        // Strategy 3: kill via process ID as last resort
        let pid = app.processIdentifier
        if pid > 0 {
            kill(pid, SIGKILL)
            return true
        }

        return false
    }

    // MARK: - Temporary Unlock

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

    // MARK: - Installed App Discovery

    func getInstalledApps() -> [InstalledAppInfo] {
        var apps: [String: InstalledAppInfo] = [:]

        let searchPaths = [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications"
        ]

        for searchPath in searchPaths {
            let url = URL(fileURLWithPath: searchPath)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for itemURL in contents {
                guard itemURL.pathExtension == "app" else { continue }
                guard let bundle = Bundle(url: itemURL),
                      let bundleID = bundle.bundleIdentifier else { continue }

                let displayName = FileManager.default.displayName(atPath: itemURL.path)
                let info = InstalledAppInfo(
                    bundleID: bundleID,
                    displayName: displayName,
                    path: itemURL.path
                )
                apps[bundleID] = info
            }
        }

        // Also include currently running apps not found on disk
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  apps[bundleID] == nil else { continue }
            let name = app.localizedName ?? bundleID
            let path = app.bundleURL?.path ?? ""
            apps[bundleID] = InstalledAppInfo(bundleID: bundleID, displayName: name, path: path)
        }

        return Array(apps.values).sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Reset

    func resetAllData() {
        stopMonitoring()
        lockedApps.removeAll()
        blockLog.removeAll()
        categories = AppCategory.defaults
        usageRecords.removeAll()
        temporarilyUnlockedApps.removeAll()
        unlockDuration = 300
        autoLockOnSleep = true
        blockingOverlayDuration = 3.0
        showUnlockDialog = false
        lastBlockedBundleID = ""
        lastBlockedAppName = nil
        lastNotifiedTime.removeAll()

        saveLockedApps()
        saveBlockLog()
        saveCategories()
        saveUsageRecords()
        saveSettings()
        UserDefaults.standard.removeObject(forKey: "com.applocker.monitoringEnabled")

        addLog("All data has been reset")
    }

    // MARK: - Per-App Passcode

    func updateAppPasscode(bundleID: String, passcodeHash: String?) {
        if let index = lockedApps.firstIndex(where: { $0.bundleID == bundleID }) {
            var app = lockedApps[index]
            app.passcode = passcodeHash
            lockedApps[index] = app
            saveLockedApps()
        }
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

            // If monitoring is active, immediately check if this app is currently running
            if isMonitoring {
                checkRunningApps()
            }
        }
    }

    func removeLockedApp(bundleID: String) {
        // Clean up membership in AppCategory.appBundleIDs before removing
        if let app = lockedApps.first(where: { $0.bundleID == bundleID }),
           let categoryName = app.category,
           let catIdx = categories.firstIndex(where: { $0.name == categoryName }) {
            var updatedCat = categories[catIdx]
            updatedCat.appBundleIDs.removeAll { $0 == bundleID }
            categories[catIdx] = updatedCat
            saveCategories()
        }
        lockedApps.removeAll { $0.bundleID == bundleID }
        saveLockedApps()
        addLog("Removed lock for: \(bundleID)")
    }

    func updateAppCategory(bundleID: String, category: String?) {
        guard let index = lockedApps.firstIndex(where: { $0.bundleID == bundleID }) else { return }

        let oldCategory = lockedApps[index].category

        // Remove from old category's appBundleIDs
        if let oldCat = oldCategory,
           let catIdx = categories.firstIndex(where: { $0.name == oldCat }) {
            var updatedCat = categories[catIdx]
            updatedCat.appBundleIDs.removeAll { $0 == bundleID }
            categories[catIdx] = updatedCat
        }

        var app = lockedApps[index]
        app.category = category
        lockedApps[index] = app

        // Add to new category's appBundleIDs
        if let newCat = category,
           let catIdx = categories.firstIndex(where: { $0.name == newCat }) {
            var updatedCat = categories[catIdx]
            if !updatedCat.appBundleIDs.contains(bundleID) {
                updatedCat.appBundleIDs.append(bundleID)
            }
            categories[catIdx] = updatedCat
        }

        saveLockedApps()
        saveCategories()
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
        // Detach apps from this category first, then remove the category
        let affectedIDs = lockedApps.filter { $0.category == name }.map { $0.bundleID }
        for bundleID in affectedIDs {
            if let i = lockedApps.firstIndex(where: { $0.bundleID == bundleID }) {
                lockedApps[i].category = nil
            }
        }
        if !affectedIDs.isEmpty { saveLockedApps() }

        categories.removeAll { $0.name == name }
        saveCategories()
    }

    func lockAllInCategory(_ categoryName: String) {
        guard let category = categories.first(where: { $0.name == categoryName }) else { return }
        // Add any predefined bundle IDs that aren't yet locked
        for bundleID in category.appBundleIDs { addLockedApp(bundleID: bundleID) }
        // Re-enforce lock: remove all tagged apps from the temporary unlock set
        let taggedIDs = lockedApps.filter { $0.category == categoryName }.map { $0.bundleID }
        for bundleID in taggedIDs { temporarilyUnlockedApps.remove(bundleID) }
        addLog("Locked all apps in category: \(categoryName)")
    }

    func unlockAllInCategory(_ categoryName: String) {
        // Temporarily unlock all locked apps tagged with this category
        let appsInCategory = lockedApps.filter { $0.category == categoryName }
        for app in appsInCategory {
            temporarilyUnlock(bundleID: app.bundleID)
        }
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
