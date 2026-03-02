// Sources/AppLocker/FocusMode/FocusModeManager.swift
#if os(macOS)
import Foundation
import Combine
import SwiftUI

@MainActor
class FocusModeManager: ObservableObject {
    static let shared = FocusModeManager()
    
    @Published var isActive = false
    @Published var selectedProfile: FocusProfile = .work
    @Published var timeRemaining: TimeInterval = 0
    @Published var sessionDuration: TimeInterval = 25 * 60
    @Published var sessionHistory: [FocusSession] = []
    @Published var allowBreaks = true
    @Published var breakDuration: TimeInterval = 5 * 60
    @Published var isOnBreak = false
    
    let essentialApps = [
        "com.apple.finder",
        "com.apple.systempreferences",
        "com.apple.Terminal",
        "com.apple.dt.Xcode",
        "com.microsoft.VSCode",
        "com.sublimetext.4"
    ]
    
    private var timer: Timer?
    private var sessionStartTime: Date?
    private var breakStartTime: Date?
    private let sessionHistoryKey = "com.applocker.focusMode.history"
    
    private init() {
        loadSessionHistory()
    }
    
    enum FocusProfile: String, CaseIterable, Identifiable, Codable {
        case work = "Deep Work"
        case study = "Study Mode"
        case meeting = "Meeting Focus"
        case custom = "Custom"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .work: return "briefcase.fill"
            case .study: return "book.fill"
            case .meeting: return "person.3.fill"
            case .custom: return "slider.horizontal.3"
            }
        }
        
        var color: String {
            switch self {
            case .work: return "blue"
            case .study: return "purple"
            case .meeting: return "green"
            case .custom: return "orange"
            }
        }
        
        var defaultDuration: TimeInterval {
            switch self {
            case .work: return 25 * 60
            case .study: return 45 * 60
            case .meeting: return 60 * 60
            case .custom: return 30 * 60
            }
        }
        
        var description: String {
            switch self {
            case .work: return "Block distractions, allow work tools"
            case .study: return "Focus on learning materials"
            case .meeting: return "Only communication apps allowed"
            case .custom: return "Configure your own rules"
            }
        }
    }
    
    func startFocus(profile: FocusProfile? = nil) {
        if let profile = profile {
            selectedProfile = profile
            sessionDuration = profile.defaultDuration
        }
        
        isActive = true
        isOnBreak = false
        timeRemaining = sessionDuration
        sessionStartTime = Date()
        
        unlockEssentialApps()
        enforceFocusRules()
        startTimer()
        
        AppMonitor.shared.addLog("Focus Mode started: \(selectedProfile.rawValue)")
        NotificationManager.shared.sendFocusModeNotification(profile: selectedProfile.rawValue, started: true)
    }
    
    func stopFocus(completed: Bool = false) {
        timer?.invalidate()
        timer = nil
        isActive = false
        isOnBreak = false
        
        if let startTime = sessionStartTime {
            let actualDuration = Date().timeIntervalSince(startTime)
            let session = FocusSession(
                id: UUID(),
                profile: selectedProfile,
                startTime: startTime,
                plannedDuration: sessionDuration,
                actualDuration: actualDuration,
                completed: completed
            )
            sessionHistory.insert(session, at: 0)
            if sessionHistory.count > 100 {
                sessionHistory = Array(sessionHistory.prefix(100))
            }
            saveSessionHistory()
        }
        
        sessionStartTime = nil
        breakStartTime = nil
        timeRemaining = 0
        
        AppMonitor.shared.addLog("Focus Mode ended")
        NotificationManager.shared.sendFocusModeNotification(profile: selectedProfile.rawValue, started: false)
    }
    
    func startBreak() {
        guard allowBreaks else { return }
        isOnBreak = true
        breakStartTime = Date()
        timeRemaining = breakDuration
        AppMonitor.shared.addLog("Focus Mode: Break started")
    }
    
    func endBreak() {
        isOnBreak = false
        breakStartTime = nil
        timeRemaining = sessionDuration - (Date().timeIntervalSince(sessionStartTime ?? Date()))
        if timeRemaining < 0 { timeRemaining = 0 }
        AppMonitor.shared.addLog("Focus Mode: Break ended")
    }
    
    func extendSession(minutes: Int) {
        sessionDuration += TimeInterval(minutes * 60)
        timeRemaining += TimeInterval(minutes * 60)
        AppMonitor.shared.addLog("Focus Mode extended by \(minutes) minutes")
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }
    
    private func tick() {
        guard timeRemaining > 0 else {
            if isOnBreak {
                endBreak()
            } else {
                stopFocus(completed: true)
            }
            return
        }
        
        timeRemaining -= 1
        
        if Int(timeRemaining) % 5 == 0 {
            enforceFocusRules()
        }
    }
    
    private func unlockEssentialApps() {
        for bundleID in essentialApps {
            AppMonitor.shared.temporarilyUnlockedApps.insert(bundleID)
        }
    }
    
    private func enforceFocusRules() {
        guard isActive && !isOnBreak else { return }
        
        let monitor = AppMonitor.shared
        let allowedCategories = getAllowedCategories(for: selectedProfile)
        
        for app in monitor.lockedApps {
            let isEssential = essentialApps.contains(app.bundleID)
            let isAllowedCategory = allowedCategories.contains(app.category ?? "")
            
            if !isEssential && !isAllowedCategory {
                monitor.temporarilyUnlockedApps.remove(app.bundleID)
            }
        }
    }
    
    private func getAllowedCategories(for profile: FocusProfile) -> [String] {
        switch profile {
        case .work:
            return ["Productivity", "Development", "Browsers"]
        case .study:
            return ["Education", "Reference", "Productivity"]
        case .meeting:
            return ["Communication", "Productivity"]
        case .custom:
            return []
        }
    }
    
    var totalFocusTimeToday: TimeInterval {
        let calendar = Calendar.current
        return sessionHistory
            .filter { calendar.isDateInToday($0.startTime) }
            .reduce(0) { $0 + $1.actualDuration }
    }
    
    var sessionsCompletedToday: Int {
        let calendar = Calendar.current
        return sessionHistory
            .filter { calendar.isDateInToday($0.startTime) && $0.completed }
            .count
    }
    
    var weeklyStats: [FocusSession] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return sessionHistory.filter { $0.startTime >= weekAgo }
    }
    
    private func saveSessionHistory() {
        if let data = try? JSONEncoder().encode(sessionHistory) {
            UserDefaults.standard.set(data, forKey: sessionHistoryKey)
        }
    }
    
    private func loadSessionHistory() {
        guard let data = UserDefaults.standard.data(forKey: sessionHistoryKey),
              let history = try? JSONDecoder().decode([FocusSession].self, from: data) else {
            return
        }
        sessionHistory = history
    }
}

struct FocusSession: Codable, Identifiable {
    let id: UUID
    let profile: FocusModeManager.FocusProfile
    let startTime: Date
    let plannedDuration: TimeInterval
    let actualDuration: TimeInterval
    let completed: Bool
    
    var formattedDuration: String {
        let minutes = Int(actualDuration / 60)
        return "\(minutes) min"
    }
}

#endif
