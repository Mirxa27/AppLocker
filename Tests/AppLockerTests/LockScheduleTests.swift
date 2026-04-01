import Foundation
import XCTest
@testable import AppLocker

final class LockScheduleTests: XCTestCase {
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

    func testBlockDuringWindowBlocksInsideAndAllowsOutside() throws {
        let schedule = LockSchedule(
            enabled: true,
            startHour: 9,
            startMinute: 0,
            endHour: 17,
            endMinute: 0,
            activeDays: [1, 2, 3, 4, 5, 6, 7],
            behavior: .blockDuringWindow
        )

        XCTAssertTrue(schedule.shouldBlock(at: makeDate(hour: 10, minute: 30), calendar: calendar))
        XCTAssertFalse(schedule.shouldBlock(at: makeDate(hour: 18, minute: 15), calendar: calendar))
    }

    func testAllowDuringWindowBlocksOutsideWindow() throws {
        let schedule = LockSchedule(
            enabled: true,
            startHour: 12,
            startMinute: 0,
            endHour: 13,
            endMinute: 0,
            activeDays: [1, 2, 3, 4, 5, 6, 7],
            behavior: .allowDuringWindow
        )

        XCTAssertFalse(schedule.shouldBlock(at: makeDate(hour: 12, minute: 30), calendar: calendar))
        XCTAssertTrue(schedule.shouldBlock(at: makeDate(hour: 14, minute: 0), calendar: calendar))
    }

    func testOvernightWindowWrapsAcrossMidnight() throws {
        let schedule = LockSchedule(
            enabled: true,
            startHour: 21,
            startMinute: 0,
            endHour: 7,
            endMinute: 0,
            activeDays: [1, 2, 3, 4, 5, 6, 7]
        )

        XCTAssertTrue(schedule.isWithinScheduledWindow(at: makeDate(hour: 22, minute: 15), calendar: calendar))
        XCTAssertTrue(schedule.isWithinScheduledWindow(at: makeDate(hour: 6, minute: 45), calendar: calendar))
        XCTAssertFalse(schedule.isWithinScheduledWindow(at: makeDate(hour: 14, minute: 0), calendar: calendar))
    }

    func testDisabledScheduleDefaultsToBlockedApp() throws {
        let schedule = LockSchedule(enabled: false)
        XCTAssertTrue(schedule.shouldBlock(at: makeDate(hour: 8, minute: 0), calendar: calendar))
    }

    func testLegacyScheduleDecodingDefaultsBehaviorToBlockDuringWindow() throws {
        let legacyJSON = """
        {
          "enabled": true,
          "startHour": 9,
          "startMinute": 0,
          "endHour": 17,
          "endMinute": 0,
          "activeDays": [1, 2, 3, 4, 5]
        }
        """.data(using: .utf8)!

        let schedule = try JSONDecoder().decode(LockSchedule.self, from: legacyJSON)

        XCTAssertEqual(schedule.behavior, .blockDuringWindow)
        XCTAssertEqual(schedule.activeDays, [1, 2, 3, 4, 5])
    }
}
