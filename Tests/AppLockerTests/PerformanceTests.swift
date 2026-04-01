import Foundation
import XCTest
import CryptoKit
@testable import AppLocker

@MainActor
final class PerformanceTests: XCTestCase {
    
    func testPBKDF2Performance() {
        let passcode = "testpasscode1234567890"
        let salt = Data("performance-test-salt".utf8)
        
        measure {
            for _ in 0..<10 {
                _ = PBKDF2Helper.deriveKey(passcode: passcode, salt: salt)
            }
        }
    }
    
    func testAESGCMEncryptionPerformance() {
        let plaintext = Data(repeating: 0x42, count: 1024 * 1024) // 1MB data
        let salt = Data("perf-salt".utf8)
        let key = CryptoHelper.deriveKey(passcode: "test", salt: salt, context: "perf")
        
        measure {
            for _ in 0..<5 {
                _ = try? CryptoHelper.encrypt(plaintext, using: key)
            }
        }
    }
    
    func testScheduleEvaluationPerformance() {
        let schedule = LockSchedule(
            enabled: true,
            startHour: 9,
            startMinute: 0,
            endHour: 17,
            endMinute: 0,
            activeDays: [2, 3, 4, 5, 6],
            behavior: .blockDuringWindow
        )
        
        let testDate = Date()
        
        measure {
            for _ in 0..<1000 {
                _ = schedule.shouldBlock(at: testDate)
            }
        }
    }
    
    func testLargeDatasetPerformance() {
        let appMonitor = AppMonitor.shared
        
        // Add many apps
        measure {
            for i in 0..<100 {
                appMonitor.addLockedApp(bundleID: "com.test.app\(i)")
            }
        }
        
        // Clean up
        for i in 0..<100 {
            appMonitor.removeLockedApp(bundleID: "com.test.app\(i)")
        }
    }
    
    func testNotificationHistoryPerformance() {
        let notificationManager = NotificationManager.shared
        
        measure {
            for i in 0..<100 {
                notificationManager.sendBlockedAppNotification(
                    appName: "Test App \(i)",
                    bundleID: "com.test.app\(i)"
                )
            }
        }
        
        // Clean up
        notificationManager.clearHistory()
    }
}