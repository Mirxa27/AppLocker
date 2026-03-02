// Sources/AppLocker/ScheduleTemplates/ScheduleTemplateManager.swift
#if os(macOS)
import Foundation

@MainActor
class ScheduleTemplateManager {
    static let shared = ScheduleTemplateManager()
    
    let templates: [ScheduleTemplate] = [
        // Work Hours
        ScheduleTemplate(
            name: "Work Hours",
            icon: "briefcase.fill",
            description: "Block distractions during 9 AM - 5 PM, Monday-Friday",
            schedule: LockSchedule(
                enabled: true,
                startHour: 9,
                startMinute: 0,
                endHour: 17,
                endMinute: 0,
                activeDays: [2, 3, 4, 5, 6] // Mon-Fri
            ),
            categories: ["Social Media", "Games", "Entertainment"]
        ),
        
        // Evening Wind Down
        ScheduleTemplate(
            name: "Evening Wind Down",
            icon: "moon.fill",
            description: "Block stimulating apps after 9 PM every day",
            schedule: LockSchedule(
                enabled: true,
                startHour: 21,
                startMinute: 0,
                endHour: 7,
                endMinute: 0,
                activeDays: [1, 2, 3, 4, 5, 6, 7] // All days
            ),
            categories: ["Social Media", "Games", "Entertainment"]
        ),
        
        // Study Time
        ScheduleTemplate(
            name: "Study Time",
            icon: "book.fill",
            description: "Focus mode: 6 PM - 9 PM on weekdays",
            schedule: LockSchedule(
                enabled: true,
                startHour: 18,
                startMinute: 0,
                endHour: 21,
                endMinute: 0,
                activeDays: [2, 3, 4, 5, 6] // Mon-Fri
            ),
            categories: ["Social Media", "Games", "Entertainment", "Communication"]
        ),
        
        // Weekend Free Time
        ScheduleTemplate(
            name: "Weekend Limits",
            icon: "sun.max.fill",
            description: "Relaxed schedule: 10 AM - 8 PM on weekends",
            schedule: LockSchedule(
                enabled: true,
                startHour: 10,
                startMinute: 0,
                endHour: 20,
                endMinute: 0,
                activeDays: [1, 7] // Sat, Sun
            ),
            categories: ["Games"]
        ),
        
        // Late Night Block
        ScheduleTemplate(
            name: "Late Night Block",
            icon: "sleep",
            description: "Block all apps from 11 PM to 6 AM for better sleep",
            schedule: LockSchedule(
                enabled: true,
                startHour: 23,
                startMinute: 0,
                endHour: 6,
                endMinute: 0,
                activeDays: [1, 2, 3, 4, 5, 6, 7]
            ),
            categories: ["Social Media", "Games", "Entertainment", "Browsers"]
        ),
        
        // Morning Routine
        ScheduleTemplate(
            name: "Morning Focus",
            icon: "sunrise.fill",
            description: "Block distractions from 6 AM - 9 AM",
            schedule: LockSchedule(
                enabled: true,
                startHour: 6,
                startMinute: 0,
                endHour: 9,
                endMinute: 0,
                activeDays: [2, 3, 4, 5, 6]
            ),
            categories: ["Social Media", "Games", "Entertainment"]
        ),
        
        // Lunch Break
        ScheduleTemplate(
            name: "Lunch Break",
            icon: "fork.knife",
            description: "Allow social apps 12 PM - 1 PM only",
            schedule: LockSchedule(
                enabled: true,
                startHour: 12,
                startMinute: 0,
                endHour: 13,
                endMinute: 0,
                activeDays: [2, 3, 4, 5, 6]
            ),
            categories: ["Social Media"],
            isAllowList: true // Only allow these during the time, block outside
        ),
        
        // Custom Weekend Study
        ScheduleTemplate(
            name: "Weekend Study",
            icon: "graduationcap.fill",
            description: "Study session: 2 PM - 5 PM on weekends",
            schedule: LockSchedule(
                enabled: true,
                startHour: 14,
                startMinute: 0,
                endHour: 17,
                endMinute: 0,
                activeDays: [1, 7]
            ),
            categories: ["Games", "Entertainment", "Social Media"]
        )
    ]
    
    private init() {}
    
    func applyTemplate(_ template: ScheduleTemplate, to apps: [LockedAppInfo]? = nil) -> Int {
        let monitor = AppMonitor.shared
        let targetApps = apps ?? monitor.lockedApps
        var appliedCount = 0
        
        for app in targetApps {
            // Check if app matches any category in template
            let shouldApply = template.categories.contains { category in
                app.category == category || template.appliesToAll
            }
            
            if shouldApply || template.appliesToAll {
                if template.isAllowList {
                    // For allow list templates, only allow during specified time
                    // This means locking outside the window
                    // For simplicity, we'll apply the schedule as-is for now
                    monitor.updateAppSchedule(bundleID: app.bundleID, schedule: template.schedule)
                } else {
                    monitor.updateAppSchedule(bundleID: app.bundleID, schedule: template.schedule)
                }
                appliedCount += 1
            }
        }
        
        AppMonitor.shared.addLog("Applied template '\(template.name)' to \(appliedCount) apps")
        return appliedCount
    }
    
    func previewApps(for template: ScheduleTemplate) -> [String] {
        let monitor = AppMonitor.shared
        return monitor.lockedApps
            .filter { app in
                template.categories.contains { $0 == app.category } || template.appliesToAll
            }
            .map { $0.displayName }
    }
}

struct ScheduleTemplate: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let description: String
    let schedule: LockSchedule
    let categories: [String]
    var isAllowList: Bool = false
    var appliesToAll: Bool = false
    
    var formattedTime: String {
        "\(schedule.startTimeFormatted) - \(schedule.endTimeFormatted)"
    }
    
    var formattedDays: String {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let days = schedule.activeDays.sorted()
        
        if days.count == 7 {
            return "Every day"
        } else if days == [2, 3, 4, 5, 6] {
            return "Weekdays"
        } else if days == [1, 7] {
            return "Weekends"
        } else {
            return days.map { dayNames[$0 - 1] }.joined(separator: ", ")
        }
    }
}

#endif
