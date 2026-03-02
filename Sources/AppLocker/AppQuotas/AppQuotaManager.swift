// Sources/AppLocker/AppQuotas/AppQuotaManager.swift
#if os(macOS)
import Foundation
import Combine
import AppKit

@MainActor
class AppQuotaManager: ObservableObject {
    static let shared = AppQuotaManager()
    
    @Published var quotas: [AppQuota] = []
    @Published var todayUsage: [String: TimeInterval] = [:] // bundleID -> seconds used
    @Published var isMonitoring = false
    
    private var monitorTimer: Timer?
    private var lastCheckTime: Date?
    private let quotasKey = "com.applocker.appQuotas"
    private let usageKey = "com.applocker.dailyUsage"
    private let lastResetKey = "com.applocker.lastQuotaReset"
    
    private init() {
        loadQuotas()
        loadTodayUsage()
        checkAndResetDaily()
    }
    
    // MARK: - Quota Management
    
    func setQuota(bundleID: String, minutes: Int, allowOverride: Bool = false) {
        if let index = quotas.firstIndex(where: { $0.bundleID == bundleID }) {
            quotas[index].dailyLimitMinutes = minutes
            quotas[index].allowOverride = allowOverride
        } else {
            let quota = AppQuota(
                bundleID: bundleID,
                dailyLimitMinutes: minutes,
                allowOverride: allowOverride
            )
            quotas.append(quota)
        }
        saveQuotas()
        AppMonitor.shared.addLog("Quota set: \(bundleID) = \(minutes) min/day")
    }
    
    func removeQuota(bundleID: String) {
        quotas.removeAll { $0.bundleID == bundleID }
        saveQuotas()
    }
    
    func getQuota(for bundleID: String) -> AppQuota? {
        quotas.first { $0.bundleID == bundleID }
    }
    
    func hasQuota(for bundleID: String) -> Bool {
        quotas.contains { $0.bundleID == bundleID }
    }
    
    // MARK: - Usage Monitoring
    
    func startMonitoring() {
        isMonitoring = true
        lastCheckTime = Date()
        
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkRunningAppUsage()
            }
        }
        
        AppMonitor.shared.addLog("App Quota monitoring started")
    }
    
    func stopMonitoring() {
        isMonitoring = false
        monitorTimer?.invalidate()
        monitorTimer = nil
        lastCheckTime = nil
        AppMonitor.shared.addLog("App Quota monitoring stopped")
    }
    
    private func checkRunningAppUsage() {
        guard let lastCheck = lastCheckTime else { return }
        
        let now = Date()
        let elapsed = now.timeIntervalSince(lastCheck)
        lastCheckTime = now
        
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier,
                  let quota = getQuota(for: bundleID),
                  app.isActive else { continue }
            
            // Add elapsed time
            let currentUsage = todayUsage[bundleID] ?? 0
            todayUsage[bundleID] = currentUsage + elapsed
            
            // Check if limit exceeded
            let usedMinutes = Int((todayUsage[bundleID] ?? 0) / 60)
            
            if usedMinutes >= quota.dailyLimitMinutes && !quota.limitReached {
                // Mark as reached and notify
                if let index = quotas.firstIndex(where: { $0.bundleID == bundleID }) {
                    quotas[index].limitReached = true
                    quotas[index].limitReachedAt = now
                    
                    // Only terminate if override not allowed
                    if !quota.allowOverride {
                        terminateApp(app)
                        NotificationManager.shared.sendQuotaExceededNotification(
                            appName: app.localizedName ?? bundleID,
                            bundleID: bundleID
                        )
                    } else {
                        NotificationManager.shared.sendQuotaWarningNotification(
                            appName: app.localizedName ?? bundleID,
                            bundleID: bundleID,
                            minutesRemaining: 0
                        )
                    }
                }
            } else if usedMinutes >= quota.dailyLimitMinutes - 5 && !quota.warningSent {
                // 5 minute warning
                if let index = quotas.firstIndex(where: { $0.bundleID == bundleID }) {
                    quotas[index].warningSent = true
                    let remaining = quota.dailyLimitMinutes - usedMinutes
                    NotificationManager.shared.sendQuotaWarningNotification(
                        appName: app.localizedName ?? bundleID,
                        bundleID: bundleID,
                        minutesRemaining: max(0, remaining)
                    )
                }
            }
        }
        
        saveTodayUsage()
    }
    
    private func terminateApp(_ app: NSRunningApplication) {
        if !app.terminate() {
            app.forceTerminate()
        }
    }
    
    // MARK: - Daily Reset
    
    func checkAndResetDaily() {
        let calendar = Calendar.current
        let now = Date()
        
        if let lastReset = UserDefaults.standard.object(forKey: lastResetKey) as? Date {
            if !calendar.isDate(lastReset, inSameDayAs: now) {
                resetDailyUsage()
            }
        } else {
            resetDailyUsage()
        }
    }
    
    func resetDailyUsage() {
        todayUsage.removeAll()
        for i in quotas.indices {
            quotas[i].limitReached = false
            quotas[i].limitReachedAt = nil
            quotas[i].warningSent = false
        }
        saveTodayUsage()
        saveQuotas()
        UserDefaults.standard.set(Date(), forKey: lastResetKey)
        AppMonitor.shared.addLog("Daily quotas reset")
    }
    
    // MARK: - Statistics
    
    func usagePercentage(for bundleID: String) -> Double {
        guard let quota = getQuota(for: bundleID), quota.dailyLimitMinutes > 0 else { return 0 }
        let used = (todayUsage[bundleID] ?? 0) / 60
        return min(100, (used / Double(quota.dailyLimitMinutes)) * 100)
    }
    
    func remainingMinutes(for bundleID: String) -> Int {
        guard let quota = getQuota(for: bundleID) else { return 0 }
        let used = Int((todayUsage[bundleID] ?? 0) / 60)
        return max(0, quota.dailyLimitMinutes - used)
    }
    
    func formattedUsage(for bundleID: String) -> String {
        let seconds = Int(todayUsage[bundleID] ?? 0)
        let minutes = seconds / 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // MARK: - Persistence
    
    private func saveQuotas() {
        if let data = try? JSONEncoder().encode(quotas) {
            UserDefaults.standard.set(data, forKey: quotasKey)
        }
    }
    
    private func loadQuotas() {
        guard let data = UserDefaults.standard.data(forKey: quotasKey),
              let loaded = try? JSONDecoder().decode([AppQuota].self, from: data) else {
            return
        }
        quotas = loaded
    }
    
    private func saveTodayUsage() {
        let usageData = todayUsage.mapValues { $0 }
        if let data = try? JSONEncoder().encode(usageData) {
            UserDefaults.standard.set(data, forKey: usageKey)
        }
    }
    
    private func loadTodayUsage() {
        guard let data = UserDefaults.standard.data(forKey: usageKey),
              let loaded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) else {
            return
        }
        todayUsage = loaded
    }
}

// MARK: - Models

struct AppQuota: Codable, Identifiable {
    let id: UUID
    let bundleID: String
    var dailyLimitMinutes: Int
    var allowOverride: Bool
    var limitReached: Bool
    var limitReachedAt: Date?
    var warningSent: Bool
    
    init(bundleID: String, dailyLimitMinutes: Int, allowOverride: Bool = false) {
        self.id = UUID()
        self.bundleID = bundleID
        self.dailyLimitMinutes = dailyLimitMinutes
        self.allowOverride = allowOverride
        self.limitReached = false
        self.limitReachedAt = nil
        self.warningSent = false
    }
}

#endif
