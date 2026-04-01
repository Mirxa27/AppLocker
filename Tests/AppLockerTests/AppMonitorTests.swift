import Foundation
import XCTest
import AppKit
@testable import AppLocker

@MainActor
final class AppMonitorTests: XCTestCase {
    
    var appMonitor: AppMonitor!
    
    override func setUp() async throws {
        appMonitor = AppMonitor.shared
        appMonitor.stopMonitoring()
        appMonitor.resetAllData()
    }
    
    func testAddAndRemoveLockedApp() async {
        let testBundleID = "com.test.app"
        
        // Test adding app
        appMonitor.addLockedApp(bundleID: testBundleID)
        XCTAssertTrue(appMonitor.lockedApps.contains { $0.bundleID == testBundleID })
        
        // Test removing app
        appMonitor.removeLockedApp(bundleID: testBundleID)
        XCTAssertFalse(appMonitor.lockedApps.contains { $0.bundleID == testBundleID })
    }
    
    func testCategoryManagement() async {
        let testBundleID = "com.test.categoryapp"
        let testCategory = "TestCategory"
        
        appMonitor.addLockedApp(bundleID: testBundleID)
        appMonitor.updateAppCategory(bundleID: testBundleID, category: testCategory)
        
        let app = appMonitor.lockedApps.first { $0.bundleID == testBundleID }
        XCTAssertEqual(app?.category, testCategory)
    }
    
    func testScheduleManagement() async {
        let testBundleID = "com.test.scheduleapp"
        let schedule = LockSchedule(
            enabled: true,
            startHour: 9,
            startMinute: 0,
            endHour: 17,
            endMinute: 0,
            behavior: .blockDuringWindow
        )
        
        appMonitor.addLockedApp(bundleID: testBundleID)
        appMonitor.updateAppSchedule(bundleID: testBundleID, schedule: schedule)
        
        let app = appMonitor.lockedApps.first { $0.bundleID == testBundleID }
        XCTAssertEqual(app?.schedule?.enabled, true)
        XCTAssertEqual(app?.schedule?.behavior, .blockDuringWindow)
    }
    
    func testTemporaryUnlock() async {
        let testBundleID = "com.test.tempapp"
        
        appMonitor.addLockedApp(bundleID: testBundleID)
        appMonitor.temporarilyUnlock(bundleID: testBundleID)
        
        XCTAssertTrue(appMonitor.temporarilyUnlockedApps.contains(testBundleID))
    }
    
    func testUsageTracking() async {
        let testBundleID = "com.test.usageapp"
        let testAppName = "TestApp"
        
        appMonitor.addLockedApp(bundleID: testBundleID)
        appMonitor.recordUsage(bundleID: testBundleID, appName: testAppName, event: .blocked)
        
        let stats = appMonitor.getUsageStats()
        let appStats = stats.first { $0.bundleID == testBundleID }
        XCTAssertEqual(appStats?.blockedCount, 1)
    }
    
    func testExportImportConfiguration() async {
        let testBundleID = "com.test.exportapp"
        
        appMonitor.addLockedApp(bundleID: testBundleID)
        
        // Test export
        guard let exportData = appMonitor.exportConfiguration() else {
            XCTFail("Failed to export configuration")
            return
        }
        
        // Clear current data
        appMonitor.resetAllData()
        XCTAssertTrue(appMonitor.lockedApps.isEmpty)
        
        // Test import
        appMonitor.importConfiguration(data: exportData)
        XCTAssertTrue(appMonitor.lockedApps.contains { $0.bundleID == testBundleID })
    }
    
    func testLogging() async {
        let testMessage = "Test log message"
        let initialCount = appMonitor.blockLog.count
        
        appMonitor.addLog(testMessage)
        
        XCTAssertEqual(appMonitor.blockLog.count, initialCount + 1)
        XCTAssertTrue(appMonitor.blockLog.first?.contains(testMessage) == true)
    }
    
    func testMonitoringControl() async {
        XCTAssertFalse(appMonitor.isMonitoring)
        
        appMonitor.startMonitoring()
        XCTAssertTrue(appMonitor.isMonitoring)
        
        appMonitor.stopMonitoring()
        XCTAssertFalse(appMonitor.isMonitoring)
    }
    
    func testInstalledAppsDiscovery() async {
        let apps = appMonitor.getInstalledApps()
        
        // Should at least find some system apps
        XCTAssertFalse(apps.isEmpty)
        
        // Should contain Finder
        let finderApps = apps.filter { $0.bundleID.contains("finder") }
        XCTAssertFalse(finderApps.isEmpty)
    }
}