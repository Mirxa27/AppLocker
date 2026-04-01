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
    enum Behavior: String, Codable, CaseIterable, Identifiable {
        case blockDuringWindow
        case allowDuringWindow

        var id: String { rawValue }

        var title: String {
            switch self {
            case .blockDuringWindow:
                return "Block In Window"
            case .allowDuringWindow:
                return "Allow In Window"
            }
        }

        var shortTitle: String {
            switch self {
            case .blockDuringWindow:
                return "Scheduled Block"
            case .allowDuringWindow:
                return "Scheduled Allow"
            }
        }

        var explanation: String {
            switch self {
            case .blockDuringWindow:
                return "This app is blocked only during the selected time window."
            case .allowDuringWindow:
                return "This app is allowed only during the selected time window and blocked outside it."
            }
        }
    }

    var enabled: Bool = false
    var startHour: Int = 0
    var startMinute: Int = 0
    var endHour: Int = 23
    var endMinute: Int = 59
    var activeDays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    var behavior: Behavior = .blockDuringWindow

    enum CodingKeys: String, CodingKey {
        case enabled
        case startHour
        case startMinute
        case endHour
        case endMinute
        case activeDays
        case behavior
    }

    init(
        enabled: Bool = false,
        startHour: Int = 0,
        startMinute: Int = 0,
        endHour: Int = 23,
        endMinute: Int = 59,
        activeDays: Set<Int> = [1, 2, 3, 4, 5, 6, 7],
        behavior: Behavior = .blockDuringWindow
    ) {
        self.enabled = enabled
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.activeDays = activeDays
        self.behavior = behavior
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        startHour = try container.decodeIfPresent(Int.self, forKey: .startHour) ?? 0
        startMinute = try container.decodeIfPresent(Int.self, forKey: .startMinute) ?? 0
        endHour = try container.decodeIfPresent(Int.self, forKey: .endHour) ?? 23
        endMinute = try container.decodeIfPresent(Int.self, forKey: .endMinute) ?? 59
        activeDays = try container.decodeIfPresent(Set<Int>.self, forKey: .activeDays) ?? [1, 2, 3, 4, 5, 6, 7]
        behavior = try container.decodeIfPresent(Behavior.self, forKey: .behavior) ?? .blockDuringWindow
    }

    var startTimeFormatted: String {
        String(format: "%02d:%02d", startHour, startMinute)
    }

    var endTimeFormatted: String {
        String(format: "%02d:%02d", endHour, endMinute)
    }

    func isWithinScheduledWindow(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let weekday = calendar.component(.weekday, from: date)
        guard activeDays.contains(weekday) else { return false }

        let currentMinutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute

        if startMinutes <= endMinutes {
            return currentMinutes >= startMinutes && currentMinutes <= endMinutes
        } else {
            return currentMinutes >= startMinutes || currentMinutes <= endMinutes
        }
    }

    func shouldBlock(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard enabled else { return true }
        let isWithinWindow = isWithinScheduledWindow(at: date, calendar: calendar)

        switch behavior {
        case .blockDuringWindow:
            return isWithinWindow
        case .allowDuringWindow:
            return !isWithinWindow
        }
    }

    func isActiveNow() -> Bool {
        shouldBlock(at: Date(), calendar: .current)
    }

    var scheduleSummary: String {
        switch behavior {
        case .blockDuringWindow:
            return "Blocks \(startTimeFormatted)-\(endTimeFormatted)"
        case .allowDuringWindow:
            return "Allows \(startTimeFormatted)-\(endTimeFormatted)"
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

struct EncryptedNotesEnvelope: Codable {
    var updatedAt: Date
    var notes: [EncryptedNote]
}

// MARK: - Shared Design System

enum AppDesign {
    static let accent = Color(red: 0.11, green: 0.50, blue: 0.95)
    static let accentSecondary = Color(red: 0.17, green: 0.71, blue: 0.91)
    static let success = Color(red: 0.19, green: 0.66, blue: 0.38)
    static let warning = Color(red: 0.95, green: 0.58, blue: 0.21)
    static let danger = Color(red: 0.85, green: 0.25, blue: 0.28)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.10, blue: 0.16),
                Color(red: 0.08, green: 0.18, blue: 0.28),
                Color(red: 0.10, green: 0.13, blue: 0.21),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var panelGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.22),
                Color.white.opacity(0.10),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct AppScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            AppDesign.backgroundGradient
                .ignoresSafeArea()
        }
    }
}

struct AppSurfaceModifier: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppDesign.panelGradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    }
            }
    }
}

struct AppStatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

struct AppMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .appSurface(padding: 14, cornerRadius: 14)
    }
}

extension View {
    func appScreenBackground() -> some View {
        modifier(AppScreenBackground())
    }

    func appSurface(padding: CGFloat = 16, cornerRadius: CGFloat = 16) -> some View {
        modifier(AppSurfaceModifier(padding: padding, cornerRadius: cornerRadius))
    }
}
