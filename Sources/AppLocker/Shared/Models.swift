import Foundation
import SwiftUI

// MARK: - Installed App Info (for browsing)
struct InstalledAppInfo: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let displayName: String
    let path: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleID)
    }

    static func == (lhs: InstalledAppInfo, rhs: InstalledAppInfo) -> Bool {
        lhs.bundleID == rhs.bundleID
    }
}

// MARK: - Locked App Info
struct LockedAppInfo: Codable, Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let displayName: String
    let path: String?
    let dateAdded: Date
    var category: String?
    var schedule: LockSchedule?
    var passcode: String? // Added for per-app passcode support

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleID)
    }

    static func == (lhs: LockedAppInfo, rhs: LockedAppInfo) -> Bool {
        return lhs.bundleID == rhs.bundleID
    }
}

// MARK: - Lock Schedule
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

// MARK: - App Category
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

// MARK: - Usage Record
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

// MARK: - Usage Stats
struct UsageStats: Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let appName: String
    var blockedCount: Int
    var unlockedCount: Int
    var failedAttemptCount: Int
    var lastBlocked: Date?
}

// MARK: - Notification Record
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

// MARK: - Export Models
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

// MARK: - Remote Command
struct RemoteCommand: Codable {
    enum Action: String, Codable {
        case lockAll
        case unlockAll
        case unlockApp
    }
    let id: UUID
    let action: Action
    let bundleID: String?
    let sourceDevice: String
    let timestamp: Date
    var hmac: String?   // HMAC-SHA256 of id+action+timestamp, base64-encoded
}

// MARK: - Vault

struct VaultFile: Codable, Identifiable {
    let id: UUID
    let originalName: String
    let encryptedFilename: String   // UUID string, no extension, stored in vault dir
    let fileSize: Int               // original plaintext size in bytes
    let dateAdded: Date
    let fileExtension: String       // e.g. "pdf", "png"
}

// MARK: - File Locker

struct LockedFileRecord: Codable, Identifiable {
    let id: UUID
    let originalPath: String        // where the original was before encryption
    let lockedPath: String          // current .aplk path
    let dateEncrypted: Date
}

// MARK: - Clipboard Guard

struct ClipboardEvent: Codable, Identifiable {
    var id: UUID = UUID()
    let timestamp: Date
    let estimatedCharCount: Int     // approximate, not the actual content
}

// MARK: - Network Monitor

struct NetworkConnection: Identifiable {
    var id: String { "\(pid)-\(remoteIP):\(remotePort)-\(proto)" }
    let processName: String
    let pid: Int32
    let remoteIP: String
    let remotePort: String
    var remoteOrg: String           // populated asynchronously via whois
    let localAddress: String
    let proto: String               // "TCP" / "UDP"
    let state: String               // "ESTABLISHED" / "LISTEN" / etc.
}

// MARK: - Secure Notes

struct EncryptedNote: Codable, Identifiable {
    let id: UUID
    var title: String
    var encryptedBody: Data         // AES-GCM combined (nonce + ciphertext + tag)
    let createdAt: Date
    var modifiedAt: Date
}
