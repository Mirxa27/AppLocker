import Foundation
import XCTest
import UserNotifications
@testable import AppLocker

@MainActor
final class NotificationManagerTests: XCTestCase {
    
    var notificationManager: NotificationManager!
    
    override func setUp() async throws {
        notificationManager = NotificationManager.shared
        notificationManager.clearHistory()
    }
    
    func testNotificationHistory() async {
        let testAppName = "TestApp"
        let testBundleID = "com.test.app"
        
        let initialCount = notificationManager.notificationHistory.count
        
        notificationManager.sendBlockedAppNotification(appName: testAppName, bundleID: testBundleID)
        
        XCTAssertEqual(notificationManager.notificationHistory.count, initialCount + 1)
        
        let latestNotification = notificationManager.notificationHistory.first
        XCTAssertEqual(latestNotification?.appName, testAppName)
        XCTAssertEqual(latestNotification?.bundleID, testBundleID)
        XCTAssertEqual(latestNotification?.type, .blocked)
    }
    
    func testNotificationSettings() async {
        // Test enabling/disabling notifications
        notificationManager.notificationsEnabled = false
        XCTAssertFalse(notificationManager.notificationsEnabled)
        
        notificationManager.notificationsEnabled = true
        XCTAssertTrue(notificationManager.notificationsEnabled)
        
        // Test cross-device settings
        notificationManager.crossDeviceEnabled = false
        XCTAssertFalse(notificationManager.crossDeviceEnabled)
        
        notificationManager.crossDeviceEnabled = true
        XCTAssertTrue(notificationManager.crossDeviceEnabled)
    }
    
    func testRemoteCommandSigning() async {
        let command = RemoteCommand(
            id: UUID(),
            action: .lockAll,
            bundleID: nil,
            sourceDevice: "TestDevice",
            timestamp: Date()
        )
        
        // Test that commands can be created
        XCTAssertEqual(command.action, .lockAll)
        XCTAssertNil(command.bundleID)
        XCTAssertEqual(command.sourceDevice, "TestDevice")
    }
    
    func testFocusModeNotifications() async {
        let testProfile = "Deep Work"
        
        // Test start notification
        notificationManager.sendFocusModeNotification(profile: testProfile, started: true)
        
        // Test end notification
        notificationManager.sendFocusModeNotification(profile: testProfile, started: false)
        
        // Verify notifications were added to history
        XCTAssertTrue(notificationManager.notificationHistory.count >= 2)
    }
    
    func testQuotaNotifications() async {
        let testAppName = "QuotaApp"
        let testBundleID = "com.test.quotaapp"
        
        // Test warning notification
        notificationManager.sendQuotaWarningNotification(
            appName: testAppName,
            bundleID: testBundleID,
            minutesRemaining: 5
        )
        
        // Test exceeded notification
        notificationManager.sendQuotaExceededNotification(
            appName: testAppName,
            bundleID: testBundleID
        )
        
        XCTAssertTrue(notificationManager.notificationHistory.count >= 2)
    }
    
    func testFailedAuthNotification() async {
        let testAppName = "AuthApp"
        let testBundleID = "com.test.authapp"
        
        notificationManager.sendFailedAuthNotification(appName: testAppName, bundleID: testBundleID)
        
        let latestNotification = notificationManager.notificationHistory.first
        XCTAssertEqual(latestNotification?.appName, testAppName)
        XCTAssertEqual(latestNotification?.bundleID, testBundleID)
        XCTAssertEqual(latestNotification?.type, .failedAttempt)
    }
    
    func testUnlockedAppNotification() async {
        let testAppName = "UnlockApp"
        let testBundleID = "com.test.unlockapp"
        
        notificationManager.sendUnlockedAppNotification(appName: testAppName, bundleID: testBundleID)
        
        let latestNotification = notificationManager.notificationHistory.first
        XCTAssertEqual(latestNotification?.appName, testAppName)
        XCTAssertEqual(latestNotification?.bundleID, testBundleID)
        XCTAssertEqual(latestNotification?.type, .unlocked)
    }
    
    func testHistoryClear() async {
        // Add some notifications
        notificationManager.sendBlockedAppNotification(appName: "Test", bundleID: "com.test")
        XCTAssertFalse(notificationManager.notificationHistory.isEmpty)
        
        // Clear history
        notificationManager.clearHistory()
        XCTAssertTrue(notificationManager.notificationHistory.isEmpty)
    }
}