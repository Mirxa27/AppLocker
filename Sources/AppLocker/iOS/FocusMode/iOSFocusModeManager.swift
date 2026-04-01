// Sources/AppLocker/iOS/FocusMode/iOSFocusModeManager.swift
#if os(iOS)
import Foundation
import SwiftUI
import UserNotifications
import Combine

@MainActor
class iOSFocusModeManager: ObservableObject {
    static let shared = iOSFocusModeManager()

    @Published var isActive = false
    @Published var selectedProfile: FocusProfile = .work
    @Published var timeRemaining: TimeInterval = 0
    @Published var sessionDuration: TimeInterval = 25 * 60
    @Published var sessionHistory: [FocusSessionEntry] = []
    @Published var allowBreaks = true
    @Published var breakDuration: TimeInterval = 5 * 60
    @Published var isOnBreak = false
    @Published var completedSessionsToday: Int = 0
    @Published var totalFocusMinutesToday: Int = 0

    private var timer: Timer?
    private var sessionStartTime: Date?
    private var breakStartTime: Date?
    private let sessionHistoryKey = "com.applocker.ios.focusMode.history"
    private let userDefaults = UserDefaults.standard

    private init() {
        loadSessionHistory()
        updateTodayStats()
    }

    // MARK: - Profiles

    enum FocusProfile: String, CaseIterable, Identifiable, Codable {
        case work = "Deep Work"
        case study = "Study Mode"
        case meeting = "Meeting Focus"
        case creative = "Creative Flow"
        case custom = "Custom"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .work: return "briefcase.fill"
            case .study: return "book.fill"
            case .meeting: return "person.3.fill"
            case .creative: return "paintbrush.fill"
            case .custom: return "slider.horizontal.3"
            }
        }

        var color: Color {
            switch self {
            case .work: return .blue
            case .study: return .purple
            case .meeting: return .green
            case .creative: return .orange
            case .custom: return .gray
            }
        }

        var defaultDuration: TimeInterval {
            switch self {
            case .work: return 25 * 60
            case .study: return 45 * 60
            case .meeting: return 60 * 60
            case .creative: return 30 * 60
            case .custom: return 30 * 60
            }
        }

        var description: String {
            switch self {
            case .work: return "25 min focused work session"
            case .study: return "45 min study block"
            case .meeting: return "60 min meeting protection"
            case .creative: return "30 min creative flow"
            case .custom: return "Configure your own duration"
            }
        }

        var blockedAppCategories: [String] {
            switch self {
            case .work: return ["Social Media", "Games", "Entertainment"]
            case .study: return ["Social Media", "Games", "Entertainment", "Communication"]
            case .meeting: return ["Games", "Entertainment"]
            case .creative: return ["Social Media", "Communication"]
            case .custom: return []
            }
        }
    }

    // MARK: - Session Control

    func startFocus(profile: FocusProfile? = nil, customDuration: TimeInterval? = nil) {
        if let profile = profile {
            selectedProfile = profile
            sessionDuration = customDuration ?? profile.defaultDuration
        }

        isActive = true
        isOnBreak = false
        timeRemaining = sessionDuration
        sessionStartTime = Date()

        startTimer()
        sendNotification(started: true)

        // Lock distracting apps
        let blockedCategories = selectedProfile.blockedAppCategories
        let lockManager = iOSAppLockManager.shared
        for app in lockManager.lockedApps where blockedCategories.contains(where: { app.displayName.contains($0) }) {
            lockManager.lockApp(bundleID: app.bundleID)
        }
    }

    func stopFocus(completed: Bool = false) {
        timer?.invalidate()
        timer = nil
        isActive = false
        isOnBreak = false

        if let startTime = sessionStartTime {
            let actualDuration = Date().timeIntervalSince(startTime)
            let entry = FocusSessionEntry(
                id: UUID(),
                profile: selectedProfile,
                startTime: startTime,
                plannedDuration: sessionDuration,
                actualDuration: actualDuration,
                completed: completed
            )
            sessionHistory.insert(entry, at: 0)
            if sessionHistory.count > 200 {
                sessionHistory = Array(sessionHistory.prefix(200))
            }
            saveSessionHistory()
            updateTodayStats()
        }

        sessionStartTime = nil
        breakStartTime = nil
        timeRemaining = 0

        sendNotification(started: false)
    }

    func startBreak() {
        guard allowBreaks else { return }
        isOnBreak = true
        breakStartTime = Date()
        timeRemaining = breakDuration
    }

    func endBreak() {
        isOnBreak = false
        breakStartTime = nil
        if let startTime = sessionStartTime {
            timeRemaining = sessionDuration - Date().timeIntervalSince(startTime)
        }
        if timeRemaining < 0 { timeRemaining = 0 }
    }

    func extendSession(minutes: Int) {
        sessionDuration += TimeInterval(minutes * 60)
        timeRemaining += TimeInterval(minutes * 60)
    }

    func skipBreak() {
        guard isOnBreak else { return }
        endBreak()
    }

    // MARK: - Timer

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
                startTimer()
            } else {
                stopFocus(completed: true)
            }
            return
        }
        timeRemaining -= 1
    }

    // MARK: - Notifications

    private func sendNotification(started: Bool) {
        let content = UNMutableNotificationContent()
        if started {
            content.title = "Focus Mode Started"
            content.body = "\(selectedProfile.rawValue) - Stay focused!"
            content.sound = .default
        } else {
            content.title = "Focus Session Complete"
            content.body = "Great work! Take a break."
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "focus-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Statistics

    var totalFocusTimeThisWeek: TimeInterval {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return sessionHistory
            .filter { $0.startTime >= cutoff }
            .reduce(0) { $0 + $1.actualDuration }
    }

    var completedSessionsThisWeek: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return sessionHistory.filter { $0.startTime >= cutoff && $0.completed }.count
    }

    var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = Date()

        while true {
            let dayCompleted = sessionHistory.contains { entry in
                calendar.isDate(entry.startTime, inSameDayAs: checkDate) && entry.completed
            }
            if dayCompleted {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else {
                break
            }
        }
        return streak
    }

    private func updateTodayStats() {
        let calendar = Calendar.current
        completedSessionsToday = sessionHistory.filter {
            calendar.isDateInToday($0.startTime) && $0.completed
        }.count
        totalFocusMinutesToday = Int(sessionHistory
            .filter { calendar.isDateInToday($0.startTime) }
            .reduce(0) { $0 + $1.actualDuration } / 60)
    }

    // MARK: - Formatting

    var formattedTimeRemaining: String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var progress: Double {
        guard sessionDuration > 0 else { return 0 }
        return 1.0 - (timeRemaining / sessionDuration)
    }

    // MARK: - Persistence

    private func saveSessionHistory() {
        if let data = try? JSONEncoder().encode(sessionHistory) {
            userDefaults.set(data, forKey: sessionHistoryKey)
        }
    }

    private func loadSessionHistory() {
        guard let data = userDefaults.data(forKey: sessionHistoryKey),
              let history = try? JSONDecoder().decode([FocusSessionEntry].self, from: data) else {
            return
        }
        sessionHistory = history
    }

    func clearHistory() {
        sessionHistory.removeAll()
        saveSessionHistory()
        updateTodayStats()
    }
}

// MARK: - Models

struct FocusSessionEntry: Codable, Identifiable {
    let id: UUID
    let profile: iOSFocusModeManager.FocusProfile
    let startTime: Date
    let plannedDuration: TimeInterval
    let actualDuration: TimeInterval
    let completed: Bool

    var formattedDuration: String {
        let minutes = Int(actualDuration / 60)
        return "\(minutes) min"
    }

    var formattedDate: String {
        startTime.formatted(date: .abbreviated, time: .shortened)
    }
}
#endif
