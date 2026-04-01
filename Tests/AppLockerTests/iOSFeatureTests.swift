import Foundation
import XCTest
@testable import AppLocker

// MARK: - Lock Schedule Tests (Cross-platform)

final class LockScheduleExtendedTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(year: Int = 2026, month: Int = 4, day: Int = 1, hour: Int, minute: Int) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return calendar.date(from: components)!
    }

    func testScheduleSummaryBlockDuringWindow() {
        let schedule = LockSchedule(
            enabled: true,
            startHour: 9,
            startMinute: 0,
            endHour: 17,
            endMinute: 0,
            behavior: .blockDuringWindow
        )
        XCTAssertEqual(schedule.scheduleSummary, "Blocks 09:00-17:00")
    }

    func testScheduleSummaryAllowDuringWindow() {
        let schedule = LockSchedule(
            enabled: true,
            startHour: 12,
            startMinute: 30,
            endHour: 14,
            endMinute: 0,
            behavior: .allowDuringWindow
        )
        XCTAssertEqual(schedule.scheduleSummary, "Allows 12:30-14:00")
    }

    func testScheduleFormattedTimes() {
        let schedule = LockSchedule(
            enabled: true,
            startHour: 8,
            startMinute: 5,
            endHour: 18,
            endMinute: 30
        )
        XCTAssertEqual(schedule.startTimeFormatted, "08:05")
        XCTAssertEqual(schedule.endTimeFormatted, "18:30")
    }

    func testIsActiveNowWithCurrentDate() {
        let schedule = LockSchedule(
            enabled: true,
            startHour: 0,
            startMinute: 0,
            endHour: 23,
            endMinute: 59,
            activeDays: [1, 2, 3, 4, 5, 6, 7],
            behavior: .blockDuringWindow
        )
        XCTAssertTrue(schedule.isActiveNow())
    }

    func testDisabledScheduleReturnsFalseForWindow() {
        let schedule = LockSchedule(enabled: false)
        XCTAssertFalse(schedule.isWithinScheduledWindow(at: makeDate(hour: 12, minute: 0), calendar: calendar))
    }

    func testScheduleActiveDaysFiltering() {
        let schedule = LockSchedule(
            enabled: true,
            startHour: 9,
            startMinute: 0,
            endHour: 17,
            endMinute: 0,
            activeDays: [2, 3, 4, 5, 6], // Mon-Fri in Gregorian
            behavior: .blockDuringWindow
        )
        // Wednesday (weekday 4 in Gregorian with Sunday=1)
        let wednesday = makeDate(year: 2026, month: 4, day: 1, hour: 10, minute: 0)
        XCTAssertTrue(schedule.isWithinScheduledWindow(at: wednesday, calendar: calendar))
    }
}

// MARK: - App Category Tests

final class AppCategoryTests: XCTestCase {

    func testDefaultCategoriesExist() {
        let defaults = AppCategory.defaults
        XCTAssertFalse(defaults.isEmpty)
        XCTAssertTrue(defaults.contains { $0.name == "Social Media" })
        XCTAssertTrue(defaults.contains { $0.name == "Games" })
        XCTAssertTrue(defaults.contains { $0.name == "Productivity" })
    }

    func testCategoryCodable() throws {
        let category = AppCategory(
            name: "Test Category",
            icon: "star.fill",
            appBundleIDs: ["com.test.app1", "com.test.app2"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(category)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AppCategory.self, from: data)

        XCTAssertEqual(decoded.name, "Test Category")
        XCTAssertEqual(decoded.icon, "star.fill")
        XCTAssertEqual(decoded.appBundleIDs.count, 2)
    }
}

// MARK: - Usage Record Tests

final class UsageRecordTests: XCTestCase {

    func testUsageRecordCodable() throws {
        let record = UsageRecord(
            bundleID: "com.test.app",
            appName: "Test App",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            event: .blocked
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(record)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(UsageRecord.self, from: data)

        XCTAssertEqual(decoded.bundleID, "com.test.app")
        XCTAssertEqual(decoded.appName, "Test App")
        XCTAssertEqual(decoded.event, .blocked)
    }

    func testAllUsageEvents() {
        let events: [UsageRecord.UsageEvent] = [.blocked, .unlocked, .failedAttempt, .launched]
        XCTAssertEqual(events.count, 4)
    }
}

// MARK: - Notification Record Tests

final class NotificationRecordTests: XCTestCase {

    func testNotificationRecordCodable() throws {
        let record = NotificationRecord(
            appName: "Test App",
            bundleID: "com.test.app",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            type: .blocked
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(record)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NotificationRecord.self, from: data)

        XCTAssertEqual(decoded.appName, "Test App")
        XCTAssertEqual(decoded.type, .blocked)
    }

    func testNotificationTypeProperties() {
        XCTAssertEqual(NotificationRecord.NotificationType.blocked.displayName, "Blocked")
        XCTAssertEqual(NotificationRecord.NotificationType.unlocked.displayName, "Unlocked")
        XCTAssertEqual(NotificationRecord.NotificationType.failedAttempt.displayName, "Failed Attempt")

        XCTAssertEqual(NotificationRecord.NotificationType.blocked.icon, "hand.raised.fill")
        XCTAssertEqual(NotificationRecord.NotificationType.unlocked.icon, "lock.open.fill")
        XCTAssertEqual(NotificationRecord.NotificationType.failedAttempt.icon, "exclamationmark.triangle.fill")
    }
}

// MARK: - Remote Command Tests

final class RemoteCommandTests: XCTestCase {

    func testRemoteCommandCodable() throws {
        let command = RemoteCommand(
            id: UUID(),
            action: .lockAll,
            bundleID: nil,
            sourceDevice: "Test Device",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            hmac: "test-hmac"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(command)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RemoteCommand.self, from: data)

        XCTAssertEqual(decoded.action, .lockAll)
        XCTAssertEqual(decoded.sourceDevice, "Test Device")
        XCTAssertEqual(decoded.hmac, "test-hmac")
    }

    func testRemoteCommandActions() {
        let actions: [RemoteCommand.Action] = [.lockAll, .unlockAll, .unlockApp]
        XCTAssertEqual(actions.count, 3)
    }
}

// MARK: - Export Model Tests

final class ExportModelTests: XCTestCase {

    func testAppLockerExportCodable() throws {
        let export = AppLockerExport(
            version: "1.0.0",
            exportDate: Date(timeIntervalSince1970: 1700000000),
            lockedApps: [
                LockedAppInfo(
                    bundleID: "com.test.app",
                    displayName: "Test",
                    path: "/Applications/Test.app",
                    dateAdded: Date(),
                    category: nil,
                    schedule: nil,
                    passcode: nil
                )
            ],
            categories: AppCategory.defaults,
            settings: ExportedSettings(
                unlockDuration: 300,
                autoLockOnSleep: true,
                blockingOverlayDuration: 3.0
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(export)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AppLockerExport.self, from: data)

        XCTAssertEqual(decoded.version, "1.0.0")
        XCTAssertEqual(decoded.lockedApps.count, 1)
        XCTAssertEqual(decoded.settings.unlockDuration, 300)
        XCTAssertEqual(decoded.settings.autoLockOnSleep, true)
    }
}

// MARK: - Vault File Tests

final class VaultFileTests: XCTestCase {

    func testVaultFileCodable() throws {
        let file = VaultFile(
            id: UUID(),
            originalName: "secret.pdf",
            encryptedFilename: UUID().uuidString,
            fileSize: 2048,
            dateAdded: Date(timeIntervalSince1970: 1700000000),
            fileExtension: "pdf"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(file)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(VaultFile.self, from: data)

        XCTAssertEqual(decoded.originalName, "secret.pdf")
        XCTAssertEqual(decoded.fileSize, 2048)
        XCTAssertEqual(decoded.fileExtension, "pdf")
    }
}

// MARK: - Encrypted Note Tests

final class EncryptedNoteTests: XCTestCase {

    func testEncryptedNoteCodable() throws {
        let note = EncryptedNote(
            id: UUID(),
            title: "Test Note",
            encryptedBody: Data("encrypted content".utf8),
            createdAt: Date(timeIntervalSince1970: 1700000000),
            modifiedAt: Date(timeIntervalSince1970: 1700001000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(note)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(EncryptedNote.self, from: data)

        XCTAssertEqual(decoded.title, "Test Note")
        XCTAssertEqual(decoded.encryptedBody, Data("encrypted content".utf8))
    }
}

// MARK: - Locked File Record Tests (macOS)

final class LockedFileRecordTests: XCTestCase {

    func testLockedFileRecordCodable() throws {
        let record = LockedFileRecord(
            id: UUID(),
            originalPath: "/Users/test/document.pdf",
            lockedPath: "/Users/test/document.pdf.aplk",
            dateEncrypted: Date(timeIntervalSince1970: 1700000000)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(record)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LockedFileRecord.self, from: data)

        XCTAssertEqual(decoded.originalPath, "/Users/test/document.pdf")
        XCTAssertEqual(decoded.lockedPath, "/Users/test/document.pdf.aplk")
    }
}
