// AppMonitor.swift
// Monitors and blocks locked applications

import Foundation
import AppKit
import ApplicationServices
import Combine
import SwiftUI

// MARK: - Data Models

struct LockedAppInfo: Codable, Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let displayName: String
    let path: String?
    let dateAdded: Date
    var category: String?
    var schedule: LockSchedule?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleID)
    }
    
    static func == (lhs: LockedAppInfo, rhs: LockedAppInfo) -> Bool {
        lhs.bundleID == rhs.bundleID
    }
}

struct LockSchedule: Codable, Hashable {
    var enabled: Bool = false
    var startHour: Int = 0
    var startMinute: Int = 0
    var endHour: Int = 23
    var endMinute: Int = 59
    var activeDays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    
    var startTimeFormatted: String {
        String(format: "%02d:%02d", startHour, startMinute)
    }
    
    var endTimeFormatted: String {
        String(format: "%02d:%02d", endHour, endMinute)
    }
    
    func isActiveNow() -> Bool {
        guard enabled else { return true }
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        guard activeDays.contains(weekday) else { return false }
        let currentMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute
        if startMinutes <= endMinutes {
            return currentMinutes >= startMinutes && currentMinutes <= endMinutes
        } else {
            return currentMinutes >= startMinutes || currentMinutes <= endMinutes
        }
    }
}

struct AppCategory: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let icon: String
    var appBundleIDs: [String]
    
    static let defaults: [AppCategory] = [
        AppCategory(name: "Social Media", icon: "bubble.left.and.bubble.right.fill", appBundleIDs: []),
        AppCategory(name: "Games", icon: "gamecontroller.fill", appBundleIDs: []),
        AppCategory(name: "Entertainment", icon: "play.tv.fill", appBundleIDs: []),
        AppCategory(name: "Productivity", icon: "briefcase.fill", appBundleIDs: []),
        AppCategory(name: "Communication", icon: "message.fill", appBundleIDs: []),
        AppCategory(name: "Browsers", icon: "globe", appBundleIDs: []),
    ]
}

struct UsageRecord: Codable {
    let bundleID: String
    let appName: String
    let timestamp: Date
    let event: UsageEvent
    
    enum UsageEvent: String, Codable {
        case blocked
        case unlocked
        case failedAttempt
        case launched
    }
}

struct UsageStats: Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let appName: String
    var blockedCount: Int
    var unlockedCount: Int
    var failedAttemptCount: Int
    var lastBlocked: Date?
}

// MARK: - App Monitor

class AppMonitor: ObservableObject {
    static let shared = AppMonitor()
    
    @Published var lockedApps: [LockedAppInfo] = []
    @Published var isMonitoring = false
    @Published var lastBlockedAppName: String?
    @Published var lastBlockedBundleID: String?
    @Published var showUnlockDialog = false
    @Published var installedApps: [LockedAppInfo] = []
    @Published var runningApps: [LockedAppInfo] = []
    @Published var blockLog: [String] = []
    @Published var categories: [AppCategory] = []
    @Published var usageRecords: [UsageRecord] = []
    
    // Settings
    @Published var unlockDuration: TimeInterval = 300
    @Published var autoLockOnSleep: Bool = true
    @Published var blockingOverlayDuration: TimeInterval = 5.0
    
    // Temporary unlock tracking
    var temporarilyUnlockedApps: Set<String> = []
    
    // Blocking state
    private var isCurrentlyBlocking = false
    private var lastBlockedApp: String?
    private var lastBlockTime: Date = .distantPast
    
    private var pollTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var systemObservers: [NSObjectProtocol] = []
    private let lockedAppsKey = "com.applocker.lockedAppsV2"
    private let categoriesKey = "com.applocker.categories"
    private let usageKey = "com.applocker.usageRecords"
    private let logKey = "com.applocker.blockLog"
    private let settingsPrefix = "com.applocker.settings."
    
    private var blockingWindow: NSWindow?
    
    private init() {
        loadLockedApps()
        loadCategories()
        loadUsageRecords()
        loadBlockLog()
        loadSettings()
        refreshInstalledApps()
        refreshRunningApps()
        setupSystemObservers()
    }
    
    // MARK: - Settings Persistence
    
    private func loadSettings() {
        if let duration = UserDefaults.standard.object(forKey: settingsPrefix + "unlockDuration") as? TimeInterval {
            unlockDuration = duration
        }
        if UserDefaults.standard.object(forKey: settingsPrefix + "autoLockOnSleep") != nil {
            autoLockOnSleep = UserDefaults.standard.bool(forKey: settingsPrefix + "autoLockOnSleep")
        }
        if let overlayDuration = UserDefaults.standard.object(forKey: settingsPrefix + "overlayDuration") as? TimeInterval {
            blockingOverlayDuration = overlayDuration
        }
    }
    
    func saveSettings() {
        UserDefaults.standard.set(unlockDuration, forKey: settingsPrefix + "unlockDuration")
        UserDefaults.standard.set(autoLockOnSleep, forKey: settingsPrefix + "autoLockOnSleep")
        UserDefaults.standard.set(blockingOverlayDuration, forKey: settingsPrefix + "overlayDuration")
    }
    
    // MARK: - System Observers
    
    private func setupSystemObservers() {
        let ws = NSWorkspace.shared.notificationCenter
        
        let sleepObs = ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleSystemSleep()
        }
        let screenObs = ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleSystemSleep()
        }
        let switchObs = ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleSystemSleep()
        }
        
        systemObservers = [sleepObs, screenObs, switchObs]
    }
    
    private func handleSystemSleep() {
        guard autoLockOnSleep else { return }
        temporarilyUnlockedApps.removeAll()
        addLog("Auto-locked all apps (system sleep)")
        AuthenticationManager.shared.logout()
    }
    
    // MARK: - App Discovery
    
    func refreshInstalledApps() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var apps: [LockedAppInfo] = []
            let fileManager = FileManager.default
            
            let searchPaths = [
                "/Applications",
                "/Applications/Utilities",
                "/System/Applications",
                NSHomeDirectory() + "/Applications"
            ]
            
            for searchPath in searchPaths {
                guard let urls = try? fileManager.contentsOfDirectory(
                    at: URL(fileURLWithPath: searchPath),
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { continue }
                
                for url in urls where url.pathExtension == "app" {
                    if let bundle = Bundle(url: url),
                       let bundleID = bundle.bundleIdentifier {
                        let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String
                            ?? bundle.infoDictionary?["CFBundleName"] as? String
                            ?? url.deletingPathExtension().lastPathComponent
                        
                        let isSystemFramework = bundleID.hasPrefix("com.apple.") &&
                            (url.path.contains("/System/") || url.path.contains("/Library/"))
                        
                        if !apps.contains(where: { $0.bundleID == bundleID }) && !isSystemFramework {
                            apps.append(LockedAppInfo(
                                bundleID: bundleID,
                                displayName: name,
                                path: url.path,
                                dateAdded: Date()
                            ))
                        }
                    }
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.installedApps = apps.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
            }
        }
    }
    
    func refreshRunningApps() {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> LockedAppInfo? in
                guard let bundleID = app.bundleIdentifier,
                      bundleID != Bundle.main.bundleIdentifier else { return nil }
                return LockedAppInfo(
                    bundleID: bundleID,
                    displayName: app.localizedName ?? bundleID,
                    path: app.bundleURL?.path,
                    dateAdded: Date()
                )
            }
        self.runningApps = running.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }
    
    func addAppFromFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "Select Application to Lock"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls {
                if let bundle = Bundle(url: url),
                   let bundleID = bundle.bundleIdentifier {
                    let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String
                        ?? bundle.infoDictionary?["CFBundleName"] as? String
                        ?? url.deletingPathExtension().lastPathComponent
                    let info = LockedAppInfo(
                        bundleID: bundleID,
                        displayName: name,
                        path: url.path,
                        dateAdded: Date()
                    )
                    self?.addLockedApp(info: info)
                }
            }
        }
    }
    
    // MARK: - BLOCKING ENGINE
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        UserDefaults.standard.set(true, forKey: "com.applocker.monitoringEnabled")
        
        addLog("MONITORING STARTED - Watching \(lockedApps.count) apps")
        
        // Use Timer instead of DispatchSource for simplicity
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.checkAndBlockFrontmostApp()
        }
        
        let nc = NSWorkspace.shared.notificationCenter
        let activateObs = nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            self?.handleAppActivated(note)
        }
        let launchObs = nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            self?.handleAppLaunched(note)
        }
        workspaceObservers = [activateObs, launchObs]
        
        // Immediate check
        checkAndBlockFrontmostApp()
    }
    
    func stopMonitoring() {
        isMonitoring = false
        UserDefaults.standard.set(false, forKey: "com.applocker.monitoringEnabled")
        
        pollTimer?.invalidate()
        pollTimer = nil
        
        for obs in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        workspaceObservers.removeAll()
        
        dismissBlockingOverlay()
        addLog("MONITORING STOPPED")
    }
    
    private var lastDebugLog: Date = .distantPast
    
    private func checkAndBlockFrontmostApp() {
        guard isMonitoring else { return }
        guard !lockedApps.isEmpty else { return }
        
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier else { return }
        
        // Debug log every 2 seconds
        let now = Date()
        if now.timeIntervalSince(lastDebugLog) > 2.0 {
            addLog("DEBUG: Frontmost=\(frontApp.localizedName ?? "?") (\(bundleID)), Locked=\(lockedApps.count), Temp=\(temporarilyUnlockedApps.count)")
            lastDebugLog = now
        }
        
        // Note: We check ourselves too, but won't block ourselves
        
        // Check if temporarily unlocked
        if temporarilyUnlockedApps.contains(bundleID) { return }
        
        // Check if locked
        guard let lockedApp = lockedApps.first(where: { $0.bundleID == bundleID }) else { return }
        
        // Check schedule
        if let schedule = lockedApp.schedule, schedule.enabled && !schedule.isActiveNow() { return }
        
        // Throttle: don't block same app within 1.5 seconds
        if lastBlockedApp == bundleID && now.timeIntervalSince(lastBlockTime) < 1.5 {
            frontApp.hide()
            return
        }
        
        // Block it
        let appName = frontApp.localizedName ?? bundleID
        performBlock(app: frontApp, name: appName, bundleID: bundleID)
    }
    
    private func handleAppActivated(_ note: Notification) {
        guard isMonitoring else { return }
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        
        if shouldBlock(bundleID: bundleID) {
            let now = Date()
            if lastBlockedApp == bundleID && now.timeIntervalSince(lastBlockTime) < 1.5 {
                app.hide()
                return
            }
            let appName = app.localizedName ?? bundleID
            performBlock(app: app, name: appName, bundleID: bundleID)
        }
    }
    
    private func handleAppLaunched(_ note: Notification) {
        guard isMonitoring else { return }
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        
        if shouldBlock(bundleID: bundleID) {
            let appName = app.localizedName ?? bundleID
            addLog("APP LAUNCHED: Blocking \(appName)")
            
            // Hide immediately
            app.hide()
            
            // Terminate after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                app.forceTerminate()
            }
            
            // Record and notify
            recordUsage(bundleID: bundleID, appName: appName, event: .blocked)
            NotificationManager.shared.sendBlockedAppNotification(appName: appName, bundleID: bundleID)
            
            // Update state
            lastBlockedApp = bundleID
            lastBlockTime = Date()
            lastBlockedAppName = appName
            lastBlockedBundleID = bundleID
            
            // Show overlay and dialog
            showBlockingOverlay(appName: appName)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.showUnlockDialog = true
            }
        }
        
        refreshRunningApps()
    }
    
    private func shouldBlock(bundleID: String) -> Bool {
        guard lockedApps.contains(where: { $0.bundleID == bundleID }) else { return false }
        if temporarilyUnlockedApps.contains(bundleID) { return false }
        if bundleID == Bundle.main.bundleIdentifier { return false }
        if bundleID.hasPrefix("com.apple.") { return false }
        
        if let lockedApp = lockedApps.first(where: { $0.bundleID == bundleID }),
           let schedule = lockedApp.schedule, schedule.enabled && !schedule.isActiveNow() {
            return false
        }
        return true
    }
    
    private func performBlock(app: NSRunningApplication, name: String, bundleID: String) {
        guard !isCurrentlyBlocking else { return }
        isCurrentlyBlocking = true
        
        addLog("BLOCKING: \(name) (\(bundleID))")
        
        // Hide and terminate
        app.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            app.forceTerminate()
        }
        
        // Record
        recordUsage(bundleID: bundleID, appName: name, event: .blocked)
        NotificationManager.shared.sendBlockedAppNotification(appName: name, bundleID: bundleID)
        
        // Update state
        lastBlockedApp = bundleID
        lastBlockTime = Date()
        lastBlockedAppName = name
        lastBlockedBundleID = bundleID
        
        // Show overlay
        showBlockingOverlay(appName: name)
        
        // Bring AppLocker to front and show unlock dialog
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            self.showUnlockDialog = true
            self.isCurrentlyBlocking = false
        }
    }
    
    // MARK: - Blocking Overlay
    
    private func showBlockingOverlay(appName: String) {
        dismissBlockingOverlay()
        
        guard let screen = NSScreen.main else { return }
        
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        
        let overlay = BlockingOverlayView(appName: appName)
        window.contentView = NSHostingView(rootView: overlay)
        window.makeKeyAndOrderFront(nil)
        
        blockingWindow = window
        
        // Auto dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + blockingOverlayDuration) { [weak self] in
            self?.dismissBlockingOverlay()
        }
    }
    
    func dismissBlockingOverlay() {
        blockingWindow?.orderOut(nil)
        blockingWindow = nil
    }
    
    // MARK: - Temporary Unlock
    
    func temporarilyUnlock(bundleID: String, duration: TimeInterval? = nil) {
        let actualDuration = duration ?? unlockDuration
        temporarilyUnlockedApps.insert(bundleID)
        dismissBlockingOverlay()
        
        addLog("UNLOCKED: \(bundleID) for \(Int(actualDuration))s")
        recordUsage(bundleID: bundleID, appName: lastBlockedAppName ?? bundleID, event: .unlocked)
        
        if let appName = lastBlockedAppName {
            NotificationManager.shared.sendUnlockedAppNotification(appName: appName, bundleID: bundleID)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + actualDuration) { [weak self] in
            self?.temporarilyUnlockedApps.remove(bundleID)
            self?.addLog("RE-LOCKED: \(bundleID)")
        }
    }
    
    var unlockDurationFormatted: String {
        let mins = Int(unlockDuration) / 60
        let secs = Int(unlockDuration) % 60
        if mins > 0 && secs > 0 { return "\(mins)m \(secs)s" }
        else if mins > 0 { return "\(mins) min" }
        else { return "\(secs)s" }
    }
    
    // MARK: - Locked Apps Management
    
    func addLockedApp(info: LockedAppInfo) {
        if !lockedApps.contains(where: { $0.bundleID == info.bundleID }) {
            lockedApps.append(info)
            saveLockedApps()
            addLog("ADDED: \(info.displayName) to locked list")
        }
    }
    
    func addLockedApp(bundleID: String) {
        if !lockedApps.contains(where: { $0.bundleID == bundleID }) {
            var name = bundleID
            var path: String? = nil
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
               let bundle = Bundle(url: url) {
                name = bundle.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle.infoDictionary?["CFBundleName"] as? String
                    ?? bundleID
                path = url.path
            }
            let info = LockedAppInfo(bundleID: bundleID, displayName: name, path: path, dateAdded: Date())
            lockedApps.append(info)
            saveLockedApps()
            addLog("ADDED: \(name) to locked list")
        }
    }
    
    func removeLockedApp(bundleID: String) {
        lockedApps.removeAll { $0.bundleID == bundleID }
        temporarilyUnlockedApps.remove(bundleID)
        saveLockedApps()
        addLog("REMOVED: \(bundleID) from locked list")
    }
    
    func isAppLocked(bundleID: String) -> Bool {
        return lockedApps.contains { $0.bundleID == bundleID }
    }
    
    func updateAppSchedule(bundleID: String, schedule: LockSchedule?) {
        if let index = lockedApps.firstIndex(where: { $0.bundleID == bundleID }) {
            let app = lockedApps[index]
            lockedApps[index] = LockedAppInfo(
                bundleID: app.bundleID, displayName: app.displayName,
                path: app.path, dateAdded: app.dateAdded,
                category: app.category, schedule: schedule
            )
            saveLockedApps()
        }
    }
    
    func updateAppCategory(bundleID: String, category: String?) {
        if let index = lockedApps.firstIndex(where: { $0.bundleID == bundleID }) {
            let app = lockedApps[index]
            lockedApps[index] = LockedAppInfo(
                bundleID: app.bundleID, displayName: app.displayName,
                path: app.path, dateAdded: app.dateAdded,
                category: category, schedule: app.schedule
            )
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
    
    struct AppLockerExport: Codable {
        let version: String
        let exportDate: Date
        let lockedApps: [LockedAppInfo]
        let categories: [AppCategory]
        let settings: ExportedSettings
    }
    
    struct ExportedSettings: Codable {
        let unlockDuration: TimeInterval
        let autoLockOnSleep: Bool
        let blockingOverlayDuration: TimeInterval
    }
    
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
        let doLog = { [weak self] in
            guard let self = self else { return }
            self.blockLog.insert(entry, at: 0)
            if self.blockLog.count > 500 {
                self.blockLog = Array(self.blockLog.prefix(500))
            }
            self.saveBlockLog()
        }
        if Thread.isMainThread { doLog() }
        else { DispatchQueue.main.async(execute: doLog) }
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
}

// MARK: - Blocking Overlay View

struct BlockingOverlayView: View {
    let appName: String
    @State private var pulseAnimation = false
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 160, height: 160)
                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseAnimation)
                
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
            }
            
            Text("ACCESS BLOCKED")
                .font(.system(size: 36, weight: .heavy))
                .foregroundColor(.white)
            
            Text("\"\(appName)\" has been terminated.")
                .font(.title2)
                .foregroundColor(.white.opacity(0.8))
            
            Text("This app is locked by AppLocker.\nUnlock it from the AppLocker window.")
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.6))
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            pulseAnimation = true
        }
    }
}
