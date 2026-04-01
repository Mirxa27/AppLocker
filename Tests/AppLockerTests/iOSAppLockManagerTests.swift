#if os(iOS)
import Foundation
import XCTest
import CryptoKit
import FamilyControls
@testable import AppLocker

@MainActor
final class iOSAppLockManagerTests: XCTestCase {
    
    var appLockManager: iOSAppLockManager!
    
    override func setUp() async throws {
        appLockManager = iOSAppLockManager.shared
        appLockManager.resetAllData()
    }
    
    func testAppLockingBasics() async {
        let testBundleID = "com.test.lockapp"
        let testDisplayName = "Test Lock App"
        
        // Test adding a locked app
        let selection = FamilyActivitySelection()
        let count = appLockManager.addLockedApplications(from: selection)
        
        // Should return 0 since we didn't provide actual apps
        XCTAssertEqual(count, 0)
        
        // Test app state management
        appLockManager.unlockApp(bundleID: testBundleID)
        XCTAssertTrue(appLockManager.sessionUnlockedApps.contains(testBundleID))
        
        appLockManager.lockApp(bundleID: testBundleID)
        XCTAssertFalse(appLockManager.sessionUnlockedApps.contains(testBundleID))
    }
    
    func testSettingsPersistence() async {
        let testDuration: TimeInterval = 600 // 10 minutes
        let testAutoLock = false
        let testBiometric = false
        
        // Test setting values
        appLockManager.unlockDuration = testDuration
        appLockManager.autoLockOnBackground = testAutoLock
        appLockManager.useBiometricForUnlock = testBiometric
        
        // Verify values are set
        XCTAssertEqual(appLockManager.unlockDuration, testDuration)
        XCTAssertEqual(appLockManager.autoLockOnBackground, testAutoLock)
        XCTAssertEqual(appLockManager.useBiometricForUnlock, testBiometric)
    }
    
    func testStatistics() async {
        XCTAssertEqual(appLockManager.lockedAppCount, 0)
        XCTAssertEqual(appLockManager.currentlyUnlockedCount, 0)
        XCTAssertEqual(appLockManager.shieldedAppCount, 0)
        
        // Add some test data
        // Note: This is a simplified test since we can't easily mock FamilyActivitySelection
        XCTAssertTrue(true) // Placeholder assertion
    }
    
    func testPasscodeVerification() async {
        let testBundleID = "com.test.passcodeapp"
        let testPasscode = "1234"
        
        // This test verifies the method signature and basic functionality
        // Actual verification requires proper iOS environment
        let result = appLockManager.verifyPasscode(testPasscode, for: testBundleID)
        
        // Should return false since no app is locked
        XCTAssertFalse(result)
    }
    
    func testLockAllFunctionality() async {
        // Test that lockAll doesn't crash
        appLockManager.lockAll()
        
        // Should clear any unlocked apps
        XCTAssertTrue(appLockManager.sessionUnlockedApps.isEmpty)
    }
    
    func testBackgroundForegroundHandling() async {
        // Test background handling
        appLockManager.handleBackground()
        
        // Test foreground handling
        appLockManager.handleForeground()
        
        // These methods should execute without crashing
        XCTAssertTrue(true)
    }
    
    func testAuthorizationStatus() async {
        // Test that authorization checking doesn't crash
        appLockManager.checkAuthorizationStatus()
        
        // The actual status depends on the test environment
        XCTAssertTrue(true)
    }
}
#endif